// Package release resolves the latest Freeroom download from the
// GitHub Releases API so the landing's download button keeps working
// for every new release without a redeploy.
//
// The resolver keeps the last good answer in memory. Callers on the
// hot path (template helpers) read it with Peek, which never touches
// the network; the /download handler calls Latest, which refreshes
// the cache once it is older than the TTL. When GitHub is
// unreachable, rate-limited or returns a release without a DMG, the
// resolver keeps serving the last good release, and before the first
// successful fetch it answers with the releases/latest page, which
// always lists the newest DMG.
package release

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"

	kitconst "github.com/hblabs-co/kit/core/constants"
)

// Defaults for the hblabs-co/freeroom repository. Exposed so main
// wires them explicitly and tests can point the resolver elsewhere.
const (
	DefaultAPIURL      = "https://api.github.com/repos/hblabs-co/freeroom/releases/latest"
	DefaultFallbackURL = "https://github.com/hblabs-co/freeroom/releases/latest"
	DefaultTTL         = 10 * time.Minute
	// retryAfter is how long a failed fetch suppresses the next
	// attempt, so a GitHub outage or the unauthenticated rate limit
	// (60 requests/hour per IP) is not hammered by every visitor.
	retryAfter   = time.Minute
	fetchTimeout = 5 * time.Second
	// maxBody caps the API response; a release JSON is a few KB.
	maxBody = 1 << 20
	// assetPrefix + assetSuffix match the DMG naming pattern
	// Freeroom-<version>.dmg used by scripts/release.sh.
	assetPrefix = "Freeroom-"
	assetSuffix = ".dmg"
	userAgent   = "HB Labs freeroom-landing/1.0 (+https://hblabs.co)"
	acceptJSON  = "application/vnd.github+json"
)

// Release is one resolved download. Version is empty when the
// resolver has never fetched successfully; URL then points at the
// releases/latest page instead of a DMG.
type Release struct {
	Version string
	URL     string
}

// Resolved reports whether r carries a concrete DMG (as opposed to
// the releases-page fallback).
func (r Release) Resolved() bool { return r.Version != "" }

// Universal reports whether the release ships a universal binary
// (Apple silicon and Intel). Universal builds start with 0.1.2;
// earlier releases are Apple silicon only. An unresolved release
// answers false so callers fall back to neutral copy.
func (r Release) Universal() bool {
	return versionAtLeast(r.Version, [3]int{0, 1, 2})
}

// versionAtLeast compares a dotted numeric version ("0.1.2",
// pre-release suffixes after '-' ignored) against min. Unparseable
// versions compare as false.
func versionAtLeast(v string, minimum [3]int) bool {
	core, _, _ := strings.Cut(v, "-")
	parts := strings.Split(core, ".")
	if len(parts) != 3 {
		return false
	}
	for i, p := range parts {
		n, err := strconv.Atoi(p)
		if err != nil {
			return false
		}
		if n != minimum[i] {
			return n > minimum[i]
		}
	}
	return true
}

// Options configures a Resolver. Zero values fall back to the
// defaults above and http.DefaultClient.
type Options struct {
	APIURL      string
	FallbackURL string
	TTL         time.Duration
	Client      *http.Client
}

// Resolver caches the latest release. Safe for concurrent use.
type Resolver struct {
	apiURL      string
	fallbackURL string
	ttl         time.Duration
	client      *http.Client
	now         func() time.Time

	mu        sync.Mutex
	cached    Release
	fetchedAt time.Time
	failedAt  time.Time
}

// New builds a Resolver from opts.
func New(opts Options) *Resolver {
	r := &Resolver{
		apiURL:      opts.APIURL,
		fallbackURL: opts.FallbackURL,
		ttl:         opts.TTL,
		client:      opts.Client,
		now:         time.Now,
	}
	if r.apiURL == "" {
		r.apiURL = DefaultAPIURL
	}
	if r.fallbackURL == "" {
		r.fallbackURL = DefaultFallbackURL
	}
	if r.ttl <= 0 {
		r.ttl = DefaultTTL
	}
	if r.client == nil {
		r.client = http.DefaultClient
	}
	return r
}

// Peek returns the cached release without any network I/O, or the
// fallback when nothing has been fetched yet.
func (r *Resolver) Peek() Release {
	r.mu.Lock()
	defer r.mu.Unlock()
	return r.currentLocked()
}

// Latest returns the cached release, refreshing it first when the
// cache is older than the TTL and no failed attempt happened within
// retryAfter. It never returns an error: failures degrade to the
// last good release, then to the fallback page.
func (r *Resolver) Latest(ctx context.Context) Release {
	r.mu.Lock()
	defer r.mu.Unlock()
	now := r.now()
	fresh := r.cached.Resolved() && now.Sub(r.fetchedAt) < r.ttl
	backoff := !r.failedAt.IsZero() && now.Sub(r.failedAt) < retryAfter
	if fresh || backoff {
		return r.currentLocked()
	}
	rel, err := r.fetch(ctx)
	if err != nil {
		r.failedAt = now
		return r.currentLocked()
	}
	r.cached, r.fetchedAt, r.failedAt = rel, now, time.Time{}
	return rel
}

// currentLocked returns the cached release or the fallback. Callers
// hold r.mu.
func (r *Resolver) currentLocked() Release {
	if r.cached.Resolved() {
		return r.cached
	}
	return Release{URL: r.fallbackURL}
}

// apiRelease is the subset of the GitHub release payload we read.
type apiRelease struct {
	TagName string `json:"tag_name"`
	Draft   bool   `json:"draft"`
	Assets  []struct {
		Name string `json:"name"`
		URL  string `json:"browser_download_url"`
	} `json:"assets"`
}

// errNoDMG is returned when the latest release carries no asset
// matching Freeroom-<version>.dmg (e.g. a release still uploading).
var errNoDMG = errors.New("release: latest release has no Freeroom DMG")

func (r *Resolver) fetch(ctx context.Context) (Release, error) {
	ctx, cancel := context.WithTimeout(ctx, fetchTimeout)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, r.apiURL, nil)
	if err != nil {
		return Release{}, fmt.Errorf("release: build request: %w", err)
	}
	req.Header.Set(kitconst.HeaderAccept, acceptJSON)
	req.Header.Set(kitconst.HeaderUserAgent, userAgent)
	resp, err := r.client.Do(req)
	if err != nil {
		return Release{}, fmt.Errorf("release: fetch: %w", err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return Release{}, fmt.Errorf("release: fetch: status %d", resp.StatusCode)
	}
	var payload apiRelease
	if err := json.NewDecoder(io.LimitReader(resp.Body, maxBody)).Decode(&payload); err != nil {
		return Release{}, fmt.Errorf("release: decode: %w", err)
	}
	return pickDMG(payload)
}

// pickDMG selects the Freeroom DMG from a release payload.
func pickDMG(p apiRelease) (Release, error) {
	if p.Draft {
		return Release{}, errNoDMG
	}
	for _, a := range p.Assets {
		if strings.HasPrefix(a.Name, assetPrefix) && strings.HasSuffix(a.Name, assetSuffix) &&
			strings.HasPrefix(a.URL, "https://") {
			version := strings.TrimSuffix(strings.TrimPrefix(a.Name, assetPrefix), assetSuffix)
			return Release{Version: version, URL: a.URL}, nil
		}
	}
	return Release{}, errNoDMG
}

// Handler answers with a 302 to the latest DMG (or the releases
// page). Short shared cache so Cloudflare and browsers do not pin an
// old version for long.
func (r *Resolver) Handler() http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, req *http.Request) {
		rel := r.Latest(req.Context())
		w.Header().Set(kitconst.HeaderCacheControl, "public, max-age=300")
		http.Redirect(w, req, rel.URL, http.StatusFound)
	})
}

// Refresher is a system.Module that warms the cache at boot and
// refreshes it every TTL, so Peek (used while rendering pages) stays
// current without visitors waiting on GitHub.
type Refresher struct {
	Resolver *Resolver
	// Interval overrides the refresh period (defaults to the
	// resolver's TTL).
	Interval time.Duration
}

// Register starts the refresh loop anchored to ctx and returns
// immediately.
func (m *Refresher) Register(ctx context.Context) error {
	interval := m.Interval
	if interval <= 0 {
		interval = m.Resolver.ttl
	}
	go m.loop(ctx, interval)
	return nil
}

func (m *Refresher) loop(ctx context.Context, interval time.Duration) {
	m.Resolver.Latest(ctx)
	t := time.NewTicker(interval)
	defer t.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-t.C:
			m.Resolver.Latest(ctx)
		}
	}
}
