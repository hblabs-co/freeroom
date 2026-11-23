package main

import (
	"html/template"
	"slices"

	"github.com/hblabs-co/kit/web/contactform"
	"github.com/hblabs-co/kit/web/ghrelease"
	"github.com/hblabs-co/kit/web/langpick"
	"github.com/hblabs-co/kit/web/siteinfo"
	"github.com/hblabs-co/kit/web/uikit"
)

// serviceFuncMap exposes the uikit icon/theme helpers, the shared
// siteinfo footer constants, and two Freeroom helpers:
//
//	{{ latestRelease }} → ghrelease.Release (cached, never blocks on GitHub)
//	{{ universal $rel }} → whether that release is a universal build
//	{{ downloadURL }}   → the stable /download redirect
//	{{ requestFormEnabled }} → whether the feature-request mailer is configured
//	{{ requestPath }} / {{ requestRecipient }} → form action and mailto fallback
func serviceFuncMap(resolver *ghrelease.Resolver, mailer contactform.Sender) template.FuncMap {
	fm := template.FuncMap{
		"latestRelease":      resolver.Peek,
		"universal":          universal,
		"downloadURL":        func() string { return downloadPath },
		"requestFormEnabled": mailer.Enabled,
		"requestPath":        func() string { return requestPath },
		"requestRecipient":   func() string { return requestRecipient },
	}
	fm["langName"] = langpick.Name
	fm["hblabsURL"] = hblabsURL
	for name, fn := range uikit.FuncMap() {
		fm[name] = fn
	}
	for name, fn := range siteinfo.FuncMap() {
		fm[name] = fn
	}
	return fm
}

// firstUniversalVersion is the first release that ships a universal
// binary (Apple silicon and Intel); earlier ones are Apple silicon only.
const firstUniversalVersion = "0.1.2"

// universal reports whether rel is a universal build. An unresolved
// release answers false so the page falls back to neutral copy.
func universal(rel ghrelease.Release) bool { return rel.AtLeast(firstUniversalVersion) }

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
