// Command og renders the link-preview images (Open Graph, 1200x630) of freeroom.hblabs.co, one per
// language, into static/img/og/<lang>.jpg (referenced by og:image in partials/_layout.html.tmpl).
//
// Each image is an HTML scene (og.html.tmpl: the macOS menu bar with the open Freeroom menu, the
// detailed window behind it, and the app's identity with the translated headline and the
// Safe/Review/Keep labels) photographed with headless Chrome, so every script (CJK, Devanagari, ...)
// is set with the system fonts.
//
// Usage, from site/:
//
//	go run ./scripts/og                 # all languages
//	go run ./scripts/og -lang de,ja     # some
//
// Needs Google Chrome (path override: -chrome) and macOS (sips, for the JPEG). Re-run when a headline, label or screenshot changes.
package main

import (
	_ "embed"
	"encoding/json"
	"flag"
	"fmt"
	"html/template"
	"os"
	"os/exec"
	"path/filepath"
	"sort"
	"strings"
)

//go:embed og.html.tmpl
var sceneHTML string

const (
	width       = 1200
	height      = 630
	jpegQuality = "84"
)

type scene struct {
	Lang, Headline, Eyebrow, Safe, Review, Keep, Clock string
	Icon, Window, Menu, HBLogo                         template.URL
}

func main() {
	chrome := flag.String("chrome", "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", "Chrome binary")
	only := flag.String("lang", "", "comma-separated languages (default: all in locales/)")
	flag.Parse()

	root, err := filepath.Abs(".")
	check(err)
	if _, err := os.Stat(filepath.Join(root, "locales")); err != nil {
		fail("run from site/ (locales/ not found)")
	}
	langs := languages(root, *only)
	tmpl := template.Must(template.New("scene").Parse(sceneHTML))
	work, err := os.MkdirTemp("", "freeroom-og-")
	check(err)
	defer os.RemoveAll(work)

	file := func(rel string) template.URL { return template.URL("file://" + filepath.Join(root, rel)) }
	for _, lang := range langs {
		t := locale(root, lang)
		page := filepath.Join(work, lang+".html")
		f, err := os.Create(page)
		check(err)
		check(tmpl.Execute(f, scene{
			Lang: lang, Headline: t["hero.headline"], Eyebrow: t["hero.eyebrow"],
			Safe: t["label.safe"], Review: t["label.review"], Keep: t["label.keep"], Clock: "9:41",
			Icon:   file("static/img/freeroom-icon-dark.svg"),
			Window: file("static/img/screenshots/detailed-dark.png"),
			Menu:   file("static/img/screenshots/menu-dark.png"),
			HBLogo: file("scripts/og/hb-logo-on-dark.svg"),
		}))
		check(f.Close())

		shot := filepath.Join(work, lang+".png")
		cmd := exec.Command(*chrome, "--headless=new", "--disable-gpu", "--hide-scrollbars",
			"--force-device-scale-factor=1", "--allow-file-access-from-files",
			fmt.Sprintf("--window-size=%d,%d", width, height), "--screenshot="+shot, "file://"+page)
		if b, err := cmd.CombinedOutput(); err != nil {
			fail(fmt.Sprintf("%s: chrome: %v\n%s", lang, err, b))
		}
		// JPEG keeps each preview well under the ~300 KB that WhatsApp and others accept reliably
		// (the PNG is ~400 KB). sips ships with macOS.
		out := filepath.Join(root, "static/img/og", lang+".jpg")
		if b, err := exec.Command("sips", "-s", "format", "jpeg", "-s", "formatOptions", jpegQuality,
			shot, "--out", out).CombinedOutput(); err != nil {
			fail(fmt.Sprintf("%s: sips: %v\n%s", lang, err, b))
		}
		fmt.Println(out)
	}
}

func languages(root, only string) []string {
	if only != "" {
		return strings.Split(only, ",")
	}
	files, err := filepath.Glob(filepath.Join(root, "locales", "*.json"))
	check(err)
	var langs []string
	for _, f := range files {
		langs = append(langs, strings.TrimSuffix(filepath.Base(f), ".json"))
	}
	sort.Strings(langs)
	return langs
}

func locale(root, lang string) map[string]string {
	b, err := os.ReadFile(filepath.Join(root, "locales", lang+".json"))
	check(err)
	t := map[string]string{}
	check(json.Unmarshal(b, &t))
	for _, k := range []string{"hero.headline", "hero.eyebrow", "label.safe", "label.review", "label.keep"} {
		if t[k] == "" {
			fail(lang + ": missing " + k)
		}
	}
	return t
}

func check(err error) {
	if err != nil {
		fail(err.Error())
	}
}

func fail(msg string) {
	fmt.Fprintln(os.Stderr, "og:", msg)
	os.Exit(1)
}
