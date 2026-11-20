#!/usr/bin/env python3
"""Checks that every L("…") key used in Sources/FreeroomApp exists in localization/strings.json
with all 15 translations, that printf placeholders match the English key, and that the generated
L10nData.swift is up to date. Exits non-zero on any problem: python3 scripts/check-l10n.py"""
import json, pathlib, re, subprocess, sys

root = pathlib.Path(__file__).resolve().parent.parent
LANGS = ["es", "de", "fr", "it", "pt", "nl", "pl", "ru", "ja", "zh-Hans", "zh-Hant", "ko", "hi", "id", "vi"]
# Ecosystem titles are passed through L() at display time; product names stay as they are.
UNTRANSLATED_ECOSYSTEMS = {"Docker", "JavaScript", "Python", "Rust", "Go", ".NET", "Homebrew"}

KEY_RE = re.compile(r'\bL\("((?:[^"\\]|\\.)*)"\)')
ECO_RE = re.compile(r'static let \w+ = Ecosystem\(id: "[^"]*", title: "([^"]*)"')
PH_RE = re.compile(r"%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:ll|l|h)?[@dDuUxXoOfeEgGcCsSpaAF%]")


def swift_unescape(s: str) -> str:
    return s.encode("utf-8").decode("unicode_escape").encode("latin-1").decode("utf-8") if "\\" in s else s


def placeholders(s: str) -> list[str]:
    return sorted(p for p in PH_RE.findall(s) if p != "%%")


def main() -> int:
    used: dict[str, set[str]] = {}
    for path in sorted((root / "Sources/FreeroomApp").glob("*.swift")):
        if path.name == "L10nData.swift":
            continue
        text = path.read_text()
        for m in KEY_RE.finditer(text):
            if "\\(" in m.group(1):
                print(f"{path.name}: interpolation inside a key: {m.group(1)!r}")
                return 1
            used.setdefault(swift_unescape(m.group(1)), set()).add(path.name)
        for m in ECO_RE.finditer(text):
            if m.group(1) not in UNTRANSLATED_ECOSYSTEMS:
                used.setdefault(m.group(1), set()).add(path.name)

    strings = json.loads((root / "localization/strings.json").read_text())
    errors = []
    for key in sorted(used):
        entry = strings.get(key)
        if entry is None:
            errors.append(f"missing key {key!r} (used in {', '.join(sorted(used[key]))})")
            continue
        expected = placeholders(key)
        for lang in LANGS:
            value = entry.get(lang)
            if not value or not value.strip():
                errors.append(f"{key!r}: missing {lang}")
            elif placeholders(value) != expected:
                errors.append(f"{key!r} [{lang}]: placeholders {placeholders(value)} != {expected}")
            elif expected and "%" in PH_RE.sub("", value):
                errors.append(f"{key!r} [{lang}]: stray % (write %% in format strings)")
        extra = set(entry) - set(LANGS)
        if extra:
            errors.append(f"{key!r}: unknown languages {sorted(extra)}")
    unused = sorted(set(strings) - set(used))
    for key in unused:
        print(f"warning: unused key {key!r}")

    generated = root / "Sources/FreeroomApp/L10nData.swift"
    before = generated.read_text()
    subprocess.run([sys.executable, str(root / "scripts/gen-l10n.py")], check=True, stdout=subprocess.DEVNULL)
    if generated.read_text() != before:
        errors.append("L10nData.swift was out of date (regenerated it; rebuild)")

    for e in errors:
        print("error:", e)
    print(f"{len(used)} keys used, {len(strings)} in strings.json, {len(LANGS)} languages, {len(errors)} errors")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
