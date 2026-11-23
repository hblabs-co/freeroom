package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"

	"github.com/hblabs-co/kit/web/csrf"
	"github.com/hblabs-co/kit/web/ghrelease"
)

func TestUniversal(t *testing.T) {
	cases := map[string]bool{"": false, "0.1.1": false, "0.1.2": true, "0.1.10": true, "1.0.0": true, "0.1.2-rc.1": true}
	for v, want := range cases {
		if got := universal(ghrelease.Release{Version: v}); got != want {
			t.Errorf("universal(%q) = %v, want %v", v, got, want)
		}
	}
}

func TestReleaseAsset(t *testing.T) {
	if v, ok := releaseAsset("Freeroom-0.1.7.dmg"); !ok || v != "0.1.7" {
		t.Fatalf("releaseAsset = %q, %v", v, ok)
	}
	if _, ok := releaseAsset("checksums.txt"); ok {
		t.Fatal("matched a non-DMG asset")
	}
}

func TestHblabsURL(t *testing.T) {
	if got := hblabsURL("de", "privacy"); got != "https://hblabs.co/de/privacy" {
		t.Errorf("de = %q", got)
	}
	if got := hblabsURL("ja", "legal"); got != "https://hblabs.co/en/legal" {
		t.Errorf("ja = %q", got)
	}
}

func TestFuncMap(t *testing.T) {
	r, err := ghrelease.New(ghrelease.Options{Repo: releaseRepo, Asset: releaseAsset})
	if err != nil {
		t.Fatal(err)
	}
	fm := serviceFuncMap(r, notifierFromEnv())
	for _, name := range []string{"latestRelease", "universal", "downloadURL", "requestFormEnabled", "requestPath",
		"requestRecipient", "langName", "hblabsURL", "icon", "themeBoot", "legalEntity"} {
		if fm[name] == nil {
			t.Errorf("funcmap missing %q", name)
		}
	}
	if got := fm["langName"].(func(string) string)("zh-Hant"); got != "繁體中文" {
		t.Errorf("langName(zh-Hant) = %q", got)
	}
}

func TestNotifierFromEnv(t *testing.T) {
	for _, k := range []string{EnvScalewaySecretKey, EnvScalewayProjectID, EnvMailFrom} {
		t.Setenv(k, "")
	}
	if notifierFromEnv().Enabled() {
		t.Fatal("enabled without config")
	}
	t.Setenv(EnvScalewaySecretKey, "k")
	t.Setenv(EnvScalewayProjectID, "p")
	t.Setenv(EnvMailFrom, "no-reply@example.com")
	if !notifierFromEnv().Enabled() {
		t.Fatal("disabled with full config")
	}
}

// TestRequestFieldsMatchTemplate keeps the Go field list and the form
// markup in sync.
func TestRequestFieldsMatchTemplate(t *testing.T) {
	page, err := siteFS.ReadFile("pages/index.html.tmpl")
	if err != nil {
		t.Fatal(err)
	}
	for _, f := range requestFields {
		if !strings.Contains(string(page), `name="`+f.Name+`"`) {
			t.Errorf("template has no input %q", f.Name)
		}
	}
	for _, want := range []string{`name="` + csrf.DefaultField + `"`, `name="website"`, "data-csrf-form"} {
		if !strings.Contains(string(page), want) {
			t.Errorf("template missing %s", want)
		}
	}
}

type fakeSender struct{ subject, body, replyTo string }

func (*fakeSender) Enabled() bool { return true }
func (f *fakeSender) Send(_ context.Context, s, b, r string) error {
	f.subject, f.body, f.replyTo = s, b, r
	return nil
}

type allowAll struct{}

func (allowAll) Allow(context.Context, string) bool { return true }

func TestRequestHandler(t *testing.T) {
	const tok = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	s := &fakeSender{}
	h := requestHandler(s, allowAll{}, csrf.New(csrf.Options{}), []string{"en", "de"}, "en")
	post := func(form url.Values) *httptest.ResponseRecorder {
		req := httptest.NewRequest(http.MethodPost, requestPath, strings.NewReader(form.Encode()))
		req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
		req.AddCookie(&http.Cookie{Name: csrf.DefaultCookie, Value: tok})
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		return rec
	}
	form := url.Values{"lang": {"de"}, csrf.DefaultField: {tok}, "need": {"Exclude folders"}, "why": {"VMs"},
		"email": {"user@example.com"}, "macos": {"15.2"}}
	if rec := post(form); rec.Header().Get("Location") != "/de/thanks" {
		t.Fatalf("success redirect = %q", rec.Header().Get("Location"))
	}
	if s.subject != "Freeroom feature request: Exclude folders" || s.replyTo != "user@example.com" ||
		!strings.HasPrefix(s.body, "New feature request from freeroom.hblabs.co") || !strings.Contains(s.body, "macOS: 15.2") {
		t.Fatalf("sent %+v", s)
	}
	form.Set("macos", strings.Repeat("1", 41))
	if rec := post(form); rec.Header().Get("Location") != "/de/request-failed" {
		t.Fatalf("failure redirect = %q", rec.Header().Get("Location"))
	}
}
