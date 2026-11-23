package langpick

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

var langs = []string{"en", "de", "zh-Hans", "zh-Hant"}

func TestChinese(t *testing.T) {
	cases := map[string]string{
		"":               "",
		"zh-CN,zh;q=0.9": "zh-Hans",
		"zh":             "zh-Hans",
		"zh-TW":          "zh-Hant",
		"zh-HK;q=0.8":    "zh-Hant",
		"zh-MO":          "zh-Hant",
		"zh-Hant-TW,en":  "zh-Hant",
		"de-DE,zh-CN":    "",
		"fr,zh-CN":       "zh-Hans",
		"x":              "",
	}
	for h, want := range cases {
		if got := Chinese(h, langs); got != want {
			t.Errorf("Chinese(%q) = %q, want %q", h, got, want)
		}
	}
	if got := Chinese("zh-TW,de", []string{"de", "zh-Hans"}); got != "" {
		t.Errorf("unsupported variant should fall through, got %q", got)
	}
}

func TestMiddleware(t *testing.T) {
	next := http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusTeapot) })
	h := Middleware(next, langs)
	do := func(path, al string, cookie string) *httptest.ResponseRecorder {
		req := httptest.NewRequest(http.MethodGet, path, nil)
		req.Header.Set("Accept-Language", al)
		if cookie != "" {
			req.AddCookie(&http.Cookie{Name: langCookie, Value: cookie})
		}
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		return rec
	}
	if rec := do("/", "zh-TW", ""); rec.Code != http.StatusFound || rec.Header().Get("Location") != "/zh-Hant/" {
		t.Fatalf("zh-TW: %d %q", rec.Code, rec.Header().Get("Location"))
	}
	if rec := do("/", "zh-TW", "de"); rec.Code != http.StatusTeapot {
		t.Fatalf("cookie should win: %d", rec.Code)
	}
	if rec := do("/", "de", ""); rec.Code != http.StatusTeapot {
		t.Fatalf("non-zh should pass: %d", rec.Code)
	}
	if rec := do("/de/", "zh-CN", ""); rec.Code != http.StatusTeapot {
		t.Fatalf("non-root should pass: %d", rec.Code)
	}
	if rec := do("/", "zh-CN", "xx"); rec.Code != http.StatusFound {
		t.Fatalf("invalid cookie ignored: %d", rec.Code)
	}
}
