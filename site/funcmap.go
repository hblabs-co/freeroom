package main

import (
	"html/template"
	"slices"

	"github.com/hblabs-co/kit/web/siteinfo"
	"github.com/hblabs-co/kit/web/uikit"
	"github.com/hblabs-co/freeroom/site/release"
	"github.com/hblabs-co/freeroom/site/request"
)

// serviceFuncMap exposes the uikit icon/theme helpers, the shared
// siteinfo footer constants, and two Freeroom helpers:
//
//	{{ latestRelease }} → release.Release (cached, never blocks on GitHub)
//	{{ downloadURL }}   → the stable /download redirect
//	{{ requestFormEnabled }} → whether the feature-request mailer is configured
//	{{ requestPath }} / {{ requestRecipient }} → form action and mailto fallback
func serviceFuncMap(resolver *release.Resolver, mailer *request.Mailer) template.FuncMap {
	fm := template.FuncMap{
		"latestRelease":      resolver.Peek,
		"downloadURL":        func() string { return downloadPath },
		"requestFormEnabled": mailer.Enabled,
		"requestPath":        func() string { return requestPath },
		"requestRecipient":   func() string { return request.Recipient },
	}
	fm["langName"] = langName
	fm["hblabsURL"] = hblabsURL
	for name, fn := range uikit.FuncMap() {
		fm[name] = fn
	}
	for name, fn := range siteinfo.FuncMap() {
		fm[name] = fn
	}
	return fm
}

// langNames are the endonyms shown in the language switcher, in the
// same set the app ships.
var langNames = map[string]string{
	"en": "English", "es": "Español", "de": "Deutsch", "fr": "Français",
	"it": "Italiano", "pt": "Português", "nl": "Nederlands", "pl": "Polski",
	"ru": "Русский", "ja": "日本語", "zh-Hans": "简体中文", "zh-Hant": "繁體中文",
	"ko": "한국어", "hi": "हिन्दी", "id": "Bahasa Indonesia", "vi": "Tiếng Việt",
}

func langName(code string) string {
	if n, ok := langNames[code]; ok {
		return n
	}
	return code
}

// hblabsLangs are the languages hblabs.co serves; legal pages for
// other languages fall back to English.
var hblabsLangs = []string{"es", "de", "en", "nl"}

// hblabsURL links to a page on hblabs.co (imprint, privacy) in the
// visitor's language when hblabs.co has it.
func hblabsURL(lang, page string) string {
	if !slices.Contains(hblabsLangs, lang) {
		lang = "en"
	}
	return "https://hblabs.co/" + lang + "/" + page
}
