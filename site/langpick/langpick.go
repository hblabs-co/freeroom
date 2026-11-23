// Package langpick complements the render framework's language
// negotiation for the two Chinese locales. The framework matches the
// first 2-letter Accept-Language prefix, which cannot tell Simplified
// from Traditional Chinese ("zh-CN" vs "zh-TW"); Freeroom ships both
// as zh-Hans and zh-Hant. Middleware intercepts only the bare "/"
// request of a visitor without a language cookie, and only when the
// first supported Accept-Language tag is Chinese; everything else
// falls through to the framework unchanged.
package langpick

import (
	"net/http"
	"slices"
	"strings"

	kitconst "github.com/hblabs-co/kit/core/constants"
)

// langCookie mirrors packages/web/render's cookie name.
const langCookie = "hbl_lang"

const (
	hans = "zh-Hans"
	hant = "zh-Hant"
)

// Middleware wraps next; supported is the site's supported_langs.
func Middleware(next http.Handler, supported []string) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/" && !hasValidCookie(r, supported) {
			if lang := Chinese(r.Header.Get(kitconst.HeaderAcceptLanguage), supported); lang != "" {
				http.Redirect(w, r, "/"+lang+"/", http.StatusFound)
				return
			}
		}
		next.ServeHTTP(w, r)
	})
}

func hasValidCookie(r *http.Request, supported []string) bool {
	c, err := r.Cookie(langCookie)
	return err == nil && slices.Contains(supported, c.Value)
}

// Chinese returns zh-Hans or zh-Hant when the first Accept-Language
// tag the site can serve is Chinese, and "" otherwise (including when
// a non-Chinese supported language comes first).
func Chinese(header string, supported []string) string {
	for _, tag := range strings.Split(header, ",") {
		tag, _, _ = strings.Cut(strings.TrimSpace(tag), ";")
		tag = strings.ToLower(tag)
		if tag == "zh" || strings.HasPrefix(tag, "zh-") {
			lang := hans
			if strings.Contains(tag, "hant") || strings.HasSuffix(tag, "-tw") ||
				strings.HasSuffix(tag, "-hk") || strings.HasSuffix(tag, "-mo") {
				lang = hant
			}
			if slices.Contains(supported, lang) {
				return lang
			}
			continue
		}
		if len(tag) >= 2 && slices.Contains(supported, tag[:2]) {
			return ""
		}
	}
	return ""
}
