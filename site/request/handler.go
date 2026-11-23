package request

import (
	"context"
	"crypto/rand"
	"crypto/subtle"
	"encoding/hex"
	"fmt"
	"net/http"
	"net/mail"
	"slices"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/hblabs-co/kit/core/httpx"
	"github.com/hblabs-co/kit/core/log"
)

// Form field and cookie names. The template and static/js/freeroom.js
// use the same literals.
const (
	CSRFCookie    = "fr_csrf"
	CSRFField     = "_csrf"
	HoneypotField = "website"
	csrfMaxAge    = 30 * 24 * 60 * 60
	tokenLen      = 64
	maxBody       = 64 << 10
	maxText       = 4000
	maxEmail      = 200
	maxMacOS      = 40
	sendTimeout   = 15 * time.Second
)

// Limiter is the subset of packages/ratelimit.Limiter the handler
// needs; an interface so tests can inject a deterministic one.
type Limiter interface {
	Allow(ctx context.Context, key string) bool
}

// Sender is the subset of *Mailer the handler needs.
type Sender interface {
	Enabled() bool
	Send(ctx context.Context, subject, text, replyTo string) error
}

// Handler serves POST /feature-request.
type Handler struct {
	Sender      Sender
	Limiter     Limiter
	Langs       []string
	DefaultLang string
}

// Submission is one validated feature request.
type Submission struct {
	Need  string
	Why   string
	Email string
	MacOS string
	Lang  string
}

// ServeHTTP implements the defense order: body cap → CSRF → honeypot
// → rate limit → validation → send. Every outcome is a 303 to a
// rendered page (thanks / request-failed), so the form works without
// JavaScript beyond the CSRF copy and the browser never re-POSTs on
// reload.
func (h *Handler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	r.Body = http.MaxBytesReader(w, r.Body, maxBody)
	if err := r.ParseForm(); err != nil {
		h.fail(w, r, h.DefaultLang, "parse: "+err.Error())
		return
	}
	lang := h.lang(r.PostFormValue("lang"))
	if why := csrfFailure(r); why != "" {
		h.fail(w, r, lang, "csrf: "+why)
		return
	}
	if r.PostFormValue(HoneypotField) != "" {
		log.Warn("feature request: honeypot hit, dropped", "ip", httpx.ClientIP(r))
		h.redirect(w, r, lang, "thanks")
		return
	}
	if !h.Limiter.Allow(r.Context(), httpx.ClientIP(r)) {
		h.fail(w, r, lang, "rate limit")
		return
	}
	sub, ok := parse(r, lang)
	if !ok {
		h.fail(w, r, lang, "validation failed")
		return
	}
	if !h.Sender.Enabled() {
		h.fail(w, r, lang, "mailer not configured")
		return
	}
	ctx, cancel := context.WithTimeout(context.WithoutCancel(r.Context()), sendTimeout)
	defer cancel()
	if err := h.Sender.Send(ctx, Subject(sub), Body(sub), sub.Email); err != nil {
		log.Error("feature request: send failed", "err", err)
		h.fail(w, r, lang, "send failed")
		return
	}
	log.Info("feature request: sent", "lang", lang, "has_email", sub.Email != "")
	h.redirect(w, r, lang, "thanks")
}

func (h *Handler) lang(v string) string {
	if slices.Contains(h.Langs, v) {
		return v
	}
	return h.DefaultLang
}

func (h *Handler) fail(w http.ResponseWriter, r *http.Request, lang, reason string) {
	log.Warn("feature request: rejected", "reason", reason, "ip", httpx.ClientIP(r))
	h.redirect(w, r, lang, "request-failed")
}

func (h *Handler) redirect(w http.ResponseWriter, r *http.Request, lang, page string) {
	http.Redirect(w, r, "/"+lang+"/"+page, http.StatusSeeOther)
}

// parse reads and validates the form fields.
func parse(r *http.Request, lang string) (Submission, bool) {
	s := Submission{
		Need:  strings.TrimSpace(r.PostFormValue("need")),
		Why:   strings.TrimSpace(r.PostFormValue("why")),
		Email: strings.TrimSpace(r.PostFormValue("email")),
		MacOS: strings.TrimSpace(r.PostFormValue("macos")),
		Lang:  lang,
	}
	ok := s.Need != "" && utf8.RuneCountInString(s.Need) <= maxText &&
		s.Why != "" && utf8.RuneCountInString(s.Why) <= maxText &&
		utf8.RuneCountInString(s.MacOS) <= maxMacOS &&
		(s.Email == "" || validEmail(s.Email))
	return s, ok
}

func validEmail(s string) bool {
	if len(s) > maxEmail {
		return false
	}
	a, err := mail.ParseAddress(s)
	return err == nil && a.Address == s
}

// Subject builds the mail subject from the first line of the need.
func Subject(s Submission) string {
	line, _, _ := strings.Cut(s.Need, "\n")
	if r := []rune(line); len(r) > 80 {
		line = string(r[:80]) + "..."
	}
	return "Freeroom feature request: " + strings.TrimSpace(line)
}

// Body renders the plain-text mail body.
func Body(s Submission) string {
	var b strings.Builder
	b.WriteString("New feature request from freeroom.hblabs.co\n\n")
	fmt.Fprintf(&b, "What they need:\n%s\n\n", s.Need)
	fmt.Fprintf(&b, "Why:\n%s\n\n", s.Why)
	email := s.Email
	if email == "" {
		email = "(not given, no reply possible)"
	}
	macos := s.MacOS
	if macos == "" {
		macos = "(not given)"
	}
	fmt.Fprintf(&b, "Reply to: %s\nmacOS: %s\nPage language: %s\n", email, macos, s.Lang)
	return b.String()
}

// randRead is the crypto/rand seam for the fail-closed branch.
var randRead = rand.Read

func newToken() (string, error) {
	buf := make([]byte, tokenLen/2)
	if _, err := randRead(buf); err != nil {
		return "", fmt.Errorf("request: csrf rand: %w", err)
	}
	return hex.EncodeToString(buf), nil
}

// IssueCSRF wraps next so every GET/HEAD leaves a CSRF cookie behind
// (sliding expiry). The token is never embedded in HTML, so pages stay
// cacheable; static/js/freeroom.js copies it into the hidden field at
// submit time (double-submit cookie). secure sets the Secure flag.
func IssueCSRF(next http.Handler, secure bool) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Method == http.MethodGet || r.Method == http.MethodHead {
			ensureCSRFCookie(w, r, secure)
		}
		next.ServeHTTP(w, r)
	})
}

func ensureCSRFCookie(w http.ResponseWriter, r *http.Request, secure bool) {
	token := ""
	if c, err := r.Cookie(CSRFCookie); err == nil && len(c.Value) == tokenLen {
		token = c.Value
	} else {
		t, err := newToken()
		if err != nil {
			return // fail closed: the next POST is rejected
		}
		token = t
	}
	http.SetCookie(w, &http.Cookie{
		Name:     CSRFCookie,
		Value:    token,
		Path:     "/",
		MaxAge:   csrfMaxAge,
		SameSite: http.SameSiteStrictMode,
		Secure:   secure,
		// Not HttpOnly: freeroom.js reads it to fill the hidden field.
	})
}

// csrfFailure reports why the double-submit check fails ("" = ok).
func csrfFailure(r *http.Request) string {
	c, err := r.Cookie(CSRFCookie)
	if err != nil || c.Value == "" {
		return "cookie missing"
	}
	field := r.PostFormValue(CSRFField)
	if field == "" {
		return "field empty"
	}
	if subtle.ConstantTimeCompare([]byte(c.Value), []byte(field)) != 1 {
		return "cookie and field differ"
	}
	return ""
}
