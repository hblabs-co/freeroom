package request

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"

	"github.com/hblabs-co/kit/mail/scaleway"
)

// --- Mailer ---------------------------------------------------------

func TestConfigFromEnv(t *testing.T) {
	t.Setenv("HB_SCALEWAY_SECRET_KEY", "k")
	t.Setenv("HB_SCALEWAY_PROJECT_ID", "p")
	t.Setenv("HB_SCALEWAY_REGION", "nl-ams")
	t.Setenv("HB_MAIL_FROM", "no-reply@example.com")
	t.Setenv("HB_MAIL_FROM_NAME", "X")
	c := ConfigFromEnv()
	if c.SecretKey != "k" || c.ProjectID != "p" || c.Region != "nl-ams" || c.From != "no-reply@example.com" || c.FromName != "X" {
		t.Fatalf("ConfigFromEnv = %+v", c)
	}
}

func TestNewMailer_DefaultsAndEnabled(t *testing.T) {
	m := NewMailer(MailConfig{})
	if m.cfg.FromName != defaultFromName || m.cfg.To != Recipient {
		t.Fatalf("defaults = %+v", m.cfg)
	}
	if m.client.Region != "fr-par" || m.client.BaseURL == "" || m.client.HTTP == nil {
		t.Fatalf("client defaults = %+v", m.client)
	}
	if m.Enabled() {
		t.Fatal("empty config must be disabled")
	}
	var nilM *Mailer
	if nilM.Enabled() {
		t.Fatal("nil mailer must be disabled")
	}
	if err := m.Send(context.Background(), "s", "b", ""); !errors.Is(err, errDisabled) {
		t.Fatalf("Send disabled = %v", err)
	}
}

func TestMailer_Send(t *testing.T) {
	var got scaleway.Email
	var path, token string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		path, token = r.URL.Path, r.Header.Get("X-Auth-Token")
		got = scaleway.Email{}
		_ = json.NewDecoder(r.Body).Decode(&got)
		w.WriteHeader(http.StatusOK)
	}))
	defer srv.Close()
	m := NewMailer(MailConfig{SecretKey: "sk", ProjectID: "pid", From: "no-reply@example.com", BaseURL: srv.URL + "/"})
	if err := m.Send(context.Background(), "subj", "body", "user@example.com"); err != nil {
		t.Fatal(err)
	}
	if path != "/fr-par/emails" || token != "sk" || got.ProjectID != "pid" || got.To[0].Email != Recipient ||
		len(got.Headers) != 1 || got.Headers[0].Value != "user@example.com" {
		t.Fatalf("path=%s token=%s email=%+v", path, token, got)
	}
	if err := m.Send(context.Background(), "subj", "body", ""); err != nil || got.Headers != nil {
		t.Fatalf("no reply-to: err=%v headers=%v", err, got.Headers)
	}
}

func TestMailer_SendErrors(t *testing.T) {
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusBadRequest)
		_, _ = io.WriteString(w, "nope")
	}))
	defer srv.Close()
	cfg := MailConfig{SecretKey: "sk", ProjectID: "pid", From: "f@example.com", BaseURL: srv.URL}
	if err := NewMailer(cfg).Send(context.Background(), "s", "b", ""); err == nil || !strings.Contains(err.Error(), "400: nope") {
		t.Fatalf("status error = %v", err)
	}
	cfg.BaseURL = "://bad"
	if err := NewMailer(cfg).Send(context.Background(), "s", "b", ""); err == nil {
		t.Fatal("expected build error")
	}
	cfg.BaseURL = "http://127.0.0.1:1"
	if err := NewMailer(cfg).Send(context.Background(), "s", "b", ""); err == nil {
		t.Fatal("expected transport error")
	}
}

// --- Handler --------------------------------------------------------

type fakeLimiter struct{ allow bool }

func (f fakeLimiter) Allow(context.Context, string) bool { return f.allow }

type fakeSender struct {
	enabled bool
	err     error
	subject string
	body    string
	replyTo string
}

func (f *fakeSender) Enabled() bool { return f.enabled }
func (f *fakeSender) Send(_ context.Context, s, b, r string) error {
	f.subject, f.body, f.replyTo = s, b, r
	return f.err
}

const tok = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

func validForm() url.Values {
	return url.Values{
		"lang": {"de"}, CSRFField: {tok}, "need": {"Exclude folders\nsecond line"},
		"why": {"I keep VMs there"}, "email": {"user@example.com"}, "macos": {"15.2"},
	}
}

func post(t *testing.T, h *Handler, form url.Values, cookie bool) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(http.MethodPost, "/feature-request", strings.NewReader(form.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	if cookie {
		req.AddCookie(&http.Cookie{Name: CSRFCookie, Value: tok})
	}
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	return rec
}

func newHandler(s *fakeSender, allow bool) *Handler {
	return &Handler{Sender: s, Limiter: fakeLimiter{allow}, Langs: []string{"en", "de"}, DefaultLang: "en"}
}

func wantRedirect(t *testing.T, rec *httptest.ResponseRecorder, loc string) {
	t.Helper()
	if rec.Code != http.StatusSeeOther || rec.Header().Get("Location") != loc {
		t.Fatalf("got %d %q, want 303 %q", rec.Code, rec.Header().Get("Location"), loc)
	}
}

func TestHandler_Success(t *testing.T) {
	s := &fakeSender{enabled: true}
	wantRedirect(t, post(t, newHandler(s, true), validForm(), true), "/de/thanks")
	if s.replyTo != "user@example.com" || s.subject != "Freeroom feature request: Exclude folders" ||
		!strings.Contains(s.body, "I keep VMs there") || !strings.Contains(s.body, "macOS: 15.2") {
		t.Fatalf("sent %+v", s)
	}
}

func TestHandler_Failures(t *testing.T) {
	cases := map[string]struct {
		mutate func(url.Values)
		cookie bool
		allow  bool
		sender *fakeSender
		want   string
	}{
		"no cookie":     {func(url.Values) {}, false, true, &fakeSender{enabled: true}, "/de/request-failed"},
		"empty field":   {func(v url.Values) { v.Del(CSRFField) }, true, true, &fakeSender{enabled: true}, "/de/request-failed"},
		"field differs": {func(v url.Values) { v.Set(CSRFField, "x") }, true, true, &fakeSender{enabled: true}, "/de/request-failed"},
		"honeypot":      {func(v url.Values) { v.Set(HoneypotField, "spam") }, true, true, &fakeSender{enabled: true}, "/de/thanks"},
		"rate limit":    {func(url.Values) {}, true, false, &fakeSender{enabled: true}, "/de/request-failed"},
		"invalid":       {func(v url.Values) { v.Set("need", "") }, true, true, &fakeSender{enabled: true}, "/de/request-failed"},
		"disabled":      {func(url.Values) {}, true, true, &fakeSender{}, "/de/request-failed"},
		"send error":    {func(url.Values) {}, true, true, &fakeSender{enabled: true, err: errors.New("x")}, "/de/request-failed"},
		"unknown lang":  {func(v url.Values) { v.Set("lang", "xx"); v.Set("need", "") }, true, true, &fakeSender{enabled: true}, "/en/request-failed"},
	}
	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			f := validForm()
			c.mutate(f)
			wantRedirect(t, post(t, newHandler(c.sender, c.allow), f, c.cookie), c.want)
		})
	}
}

func TestHandler_BodyTooLarge(t *testing.T) {
	h := newHandler(&fakeSender{enabled: true}, true)
	big := url.Values{"need": {strings.Repeat("a", maxBody+10)}}
	wantRedirect(t, post(t, h, big, true), "/en/request-failed")
}

func TestParse_Validation(t *testing.T) {
	cases := map[string]struct {
		key, val string
		ok       bool
	}{
		"long need":    {"need", strings.Repeat("a", maxText+1), false},
		"empty why":    {"why", "", false},
		"long why":     {"why", strings.Repeat("a", maxText+1), false},
		"long macos":   {"macos", strings.Repeat("a", maxMacOS+1), false},
		"bad email":    {"email", "not-an-email", false},
		"named email":  {"email", "A <a@example.com>", false},
		"long email":   {"email", strings.Repeat("a", maxEmail) + "@example.com", false},
		"no email ok":  {"email", "", true},
		"no macos ok":  {"macos", "", true},
		"unicode need": {"need", strings.Repeat("ü", maxText), true},
	}
	for name, c := range cases {
		t.Run(name, func(t *testing.T) {
			f := validForm()
			f.Set(c.key, c.val)
			req := httptest.NewRequest(http.MethodPost, "/", strings.NewReader(f.Encode()))
			req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
			if _, ok := parse(req, "en"); ok != c.ok {
				t.Fatalf("ok = %v, want %v", ok, c.ok)
			}
		})
	}
}

func TestSubjectAndBody(t *testing.T) {
	long := strings.Repeat("x", 100)
	if got := Subject(Submission{Need: long}); got != "Freeroom feature request: "+strings.Repeat("x", 80)+"..." {
		t.Fatalf("Subject = %q", got)
	}
	b := Body(Submission{Need: "n", Why: "w", Lang: "es"})
	if !strings.Contains(b, "(not given, no reply possible)") || !strings.Contains(b, "macOS: (not given)") || !strings.Contains(b, "Page language: es") {
		t.Fatalf("Body = %q", b)
	}
}

// --- CSRF cookie ----------------------------------------------------

func TestIssueCSRF(t *testing.T) {
	next := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusTeapot) })
	h := IssueCSRF(next, true)

	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/", nil))
	c := rec.Result().Cookies()
	if rec.Code != http.StatusTeapot || len(c) != 1 || len(c[0].Value) != tokenLen || !c[0].Secure || c[0].HttpOnly {
		t.Fatalf("new cookie: code=%d cookies=%v", rec.Code, c)
	}

	req := httptest.NewRequest(http.MethodHead, "/", nil)
	req.AddCookie(&http.Cookie{Name: CSRFCookie, Value: tok})
	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, req)
	if c := rec.Result().Cookies(); len(c) != 1 || c[0].Value != tok {
		t.Fatalf("existing cookie not re-issued: %v", c)
	}

	rec = httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodPost, "/", nil))
	if len(rec.Result().Cookies()) != 0 {
		t.Fatal("POST must not issue a cookie")
	}
}

func TestIssueCSRF_RandFailureFailsClosed(t *testing.T) {
	orig := randRead
	randRead = func([]byte) (int, error) { return 0, errors.New("no entropy") }
	defer func() { randRead = orig }()
	rec := httptest.NewRecorder()
	IssueCSRF(http.NotFoundHandler(), false).ServeHTTP(rec, httptest.NewRequest(http.MethodGet, "/", nil))
	if len(rec.Result().Cookies()) != 0 {
		t.Fatal("cookie issued despite rand failure")
	}
}
