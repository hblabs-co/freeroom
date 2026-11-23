// service-freeroom serves freeroom.hblabs.co, the product page for
// Freeroom (the open-source macOS disk cleaner by HB Labs SAS). It lives
// next to the app in github.com/hblabs-co/freeroom and is built on the
// public github.com/hblabs-co/kit (site framework and UI kit).
//
// Besides the rendered pages it owns one route: GET /download answers
// with a 302 to the newest Freeroom-<version>.dmg, resolved from the
// GitHub Releases API and cached in memory (kit web/ghrelease), so the
// download button never needs a redeploy for a new release. POST
// /feature-request forwards the feature-request form by mail (kit
// web/contactform + mail/scaleway).
package main

import (
	"embed"
	"fmt"
	"io/fs"
	"net/http"
	"os"
	"time"

	"golang.org/x/time/rate"

	kitconst "github.com/hblabs-co/kit/core/constants"
	"github.com/hblabs-co/kit/core/envcfg"
	"github.com/hblabs-co/kit/core/log"
	"github.com/hblabs-co/kit/core/ratelimit"
	"github.com/hblabs-co/kit/core/system"
	"github.com/hblabs-co/kit/web/contactform"
	"github.com/hblabs-co/kit/web/csrf"
	"github.com/hblabs-co/kit/web/ghrelease"
	"github.com/hblabs-co/kit/web/site"
	"github.com/hblabs-co/kit/web/siteurl"
)

// siteFS is the whole service surface embedded into the binary.
// `all:partials` keeps the underscore-prefixed _layout.html.tmpl.
//
//go:embed pages all:partials locales static config
var siteFS embed.FS

// devWatchRoot is the on-disk source dir used when HB_ENV=local:
// run `go run .` from site/.
const devWatchRoot = "."

// serviceName identifies the service in logs and the boot banner.
const serviceName = "service-freeroom"

// configPath is the framework config inside whichever fs.FS render
// reads from.
const configPath = "config/config.yaml"

// defaultPort is the local `go run` port; prod pins HB_PORT=8080 in
// the Dockerfile. 8087 keeps it clear of landing (8080) and the other
// local services.
const defaultPort = 8087

// downloadPath is the stable download URL the page and the README
// link to.
const downloadPath = "/download"

// requestPath receives the feature-request form.
const requestPath = "/feature-request"

// Feature-request rate limit per client IP: a burst of 3, then one
// every 10 minutes. In-memory per replica, which is enough to cap
// volume; the honeypot and CSRF check handle bots.
const (
	requestBurst    = 3
	requestInterval = 10 * time.Minute
)

// releaseRepo hosts the DMGs; releaseAsset matches the
// Freeroom-<version>.dmg naming used by scripts/release.sh.
const releaseRepo = "hblabs-co/freeroom"

var releaseAsset = ghrelease.PrefixSuffix("Freeroom-", ".dmg")

const releaseUserAgent = "HB Labs freeroom-landing/1.0 (+https://hblabs.co)"

// requestFields are the inputs of the feature-request form in
// pages/index.html.tmpl (same names and limits as the template).
var requestFields = []contactform.Field{
	{Name: "need", Label: "What they need", Required: true, Multiline: true},
	{Name: "why", Label: "Why", Required: true, Multiline: true},
	{Name: "email", Label: "Reply to", Email: true, MaxRunes: 200},
	{Name: "macos", Label: "macOS", MaxRunes: 40},
}

// requestHandler wires the feature-request form; the result pages are
// pages/thanks and pages/request-failed.
func requestHandler(sender contactform.Sender, limiter contactform.Limiter, guard *csrf.Guard, langs []string, defaultLang string) *contactform.Handler {
	return &contactform.Handler{
		Fields:        requestFields,
		Sender:        sender,
		Limiter:       limiter,
		CSRF:          guard,
		Langs:         langs,
		DefaultLang:   defaultLang,
		FailurePage:   "request-failed",
		SubjectPrefix: "Freeroom feature request: ",
		Intro:         "New feature request from freeroom.hblabs.co",
	}
}

func main() {
	ctx := system.Boot(system.
		BootOptions(serviceName).
		With(system.Port(defaultPort)).
		With(system.BannerExtras(site.BannerExtras()...)))

	resolver, err := ghrelease.New(ghrelease.Options{
		Repo:      releaseRepo,
		Asset:     releaseAsset,
		UserAgent: releaseUserAgent,
	})
	if err != nil {
		log.Error("release resolver init failed", "err", err)
		os.Exit(1)
	}
	mailer := notifierFromEnv()
	if !mailer.Enabled() {
		log.Warn("feature-request mail not configured; the page shows the mailto fallback",
			"needs", []string{EnvScalewaySecretKey, EnvScalewayProjectID, EnvMailFrom})
	}

	handler, modules, cfg, err := site.New(site.Options{
		SiteFS:      siteFS,
		WatchRoot:   devWatchRoot,
		ConfigPath:  configPath,
		FuncMap:     serviceFuncMap(resolver, mailer),
		ExtraStatic: map[string]fs.FS{"uikit": site.UIKitFS()},
	})
	if err != nil {
		log.Error("site init failed", "err", err)
		os.Exit(1)
	}

	limiter := ratelimit.New(ratelimit.Options{
		Rate:  rate.Every(requestInterval),
		Burst: requestBurst,
	})
	limiter.Start(ctx)

	guard := csrf.New(csrf.Options{Secure: !siteurl.IsDev()})

	mux := http.NewServeMux()
	mux.Handle("GET "+downloadPath, resolver.Handler())
	mux.Handle("POST "+requestPath, requestHandler(mailer, limiter, guard, cfg.SupportedLangs, cfg.DefaultLang))
	// "/" language negotiation (incl. zh-Hans / zh-Hant) is the
	// framework's own (kit web/langpick).
	mux.Handle("/", guard.Issue(handler))

	addr := fmt.Sprintf(":%d", envcfg.Int(kitconst.EnvPort, defaultPort))
	modules = append(modules,
		&ghrelease.Refresher{Resolver: resolver},
		system.NewServer(system.ServerOptions{Addr: addr, Handler: mux}),
	)
	if err := system.RunForever(ctx, modules...); err != nil {
		log.Error("run failed", "err", err)
		os.Exit(1)
	}
}
