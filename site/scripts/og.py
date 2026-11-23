#!/usr/bin/env python3
"""Generate the Open Graph link-preview images (1200x630) for every language.

Output: static/img/og/<lang>.png, referenced by og:image in partials/_layout.html.tmpl.
Text comes from locales/<lang>.json (hero.headline, translated in every language). Runs on macOS: it uses the system fonts,
which cover CJK and Devanagari (the shared Go renderer only covers Latin).

Usage (from the service dir):  python3 scripts/og.py [path/to/freeroom-icon.png]
Needs Pillow. Re-run when the tagline or the screenshot changes.
"""
import json, os, sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W, H = 1200, 630
FONTS = "/System/Library/Fonts"
LATIN = f"{FONTS}/SFNS.ttf"
BY_LANG = {
    "ja": f"{FONTS}/ヒラギノ角ゴシック W6.ttc",
    "zh-Hans": f"{FONTS}/Hiragino Sans GB.ttc",
    "zh-Hant": f"{FONTS}/Supplemental/Songti.ttc",
    "ko": f"{FONTS}/AppleSDGothicNeo.ttc",
    "hi": f"{FONTS}/Kohinoor.ttc",
}
ZH_HANT_CANDIDATES = [f"{FONTS}/PingFang.ttc", f"{FONTS}/Supplemental/PingFang.ttc",
                      f"{FONTS}/STHeiti Medium.ttc", f"{FONTS}/Supplemental/Songti.ttc"]


def font(path, size, bold=False):
    f = ImageFont.truetype(path, size)
    if path.endswith("SFNS.ttf"):
        try:
            f.set_variation_by_name("Bold" if bold else "Regular")
        except Exception:
            pass
    return f


def text_font(lang, size):
    path = BY_LANG.get(lang, LATIN)
    if lang == "zh-Hant":
        path = next((p for p in ZH_HANT_CANDIDATES if os.path.exists(p)), path)
    return font(path, size)


CJK = {"ja", "zh-Hans", "zh-Hant"}


def wrap(draw, text, f, max_w, lang):
    # Chinese and Japanese do not separate words with spaces: wrap per character.
    per_char = lang in CJK
    units = list(text) if per_char else text.split(" ")
    sep = "" if per_char else " "
    lines, cur = [], ""
    for u in units:
        cand = (cur + sep + u) if cur else u
        if draw.textlength(cand, font=f) <= max_w:
            cur = cand
        else:
            lines.append(cur)
            cur = u
    if cur:
        lines.append(cur)
    return lines


def rounded(img, r):
    m = Image.new("L", img.size, 0)
    ImageDraw.Draw(m).rounded_rectangle([0, 0, img.size[0], img.size[1]], r, fill=255)
    img.putalpha(m)
    return img


def background():
    bg = Image.new("RGB", (W, H))
    top, bottom = (11, 22, 48), (26, 77, 219)  # deep navy -> Freeroom blue (#1a4ddb)
    px = bg.load()
    for y in range(H):
        for x in range(W):
            t = min(1.0, (x / W) * 0.55 + (y / H) * 0.45)
            px[x, y] = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))
    return bg


def main():
    icon_path = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "static/img/apple-touch-icon.png")
    shot = Image.open(os.path.join(HERE, "static/img/screenshots/detailed-dark.png")).convert("RGBA")
    icon = Image.open(icon_path).convert("RGBA").resize((112, 112), Image.LANCZOS)
    base = background()

    # Screenshot on the right, partly off-canvas, rounded, with a soft shadow.
    sw = 760
    shot = shot.resize((sw, int(shot.height * sw / shot.width)), Image.LANCZOS)
    shot = rounded(shot, 18)
    sx, sy = 640, 120
    shadow = Image.new("RGBA", (shot.width + 80, shot.height + 80), (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle([40, 40, 40 + shot.width, 40 + shot.height], 22, fill=(0, 0, 0, 150))
    shadow = shadow.filter(ImageFilter.GaussianBlur(22))
    base.paste(shadow, (sx - 40, sy - 20), shadow)
    base.paste(shot, (sx, sy), shot)

    out_dir = os.path.join(HERE, "static/img/og")
    os.makedirs(out_dir, exist_ok=True)
    for name in sorted(os.listdir(os.path.join(HERE, "locales"))):
        if not name.endswith(".json"):
            continue
        lang = name[:-5]
        loc = json.load(open(os.path.join(HERE, "locales", name), encoding="utf-8"))
        subtitle = loc.get("hero.headline") or loc.get("og.index.subtitle", "")
        img = base.copy()
        d = ImageDraw.Draw(img)
        img.paste(icon, (72, 92), icon)
        d.text((72, 232), "Freeroom", font=font(LATIN, 84, bold=True), fill=(255, 255, 255))
        f = text_font(lang, 34)
        y = 352
        for line in wrap(d, subtitle, f, 520, lang)[:4]:
            d.text((72, y), line, font=f, fill=(214, 226, 255))
            y += 48
        d.text((72, H - 72), "freeroom.hblabs.co  ·  macOS  ·  by HB Labs SAS", font=font(LATIN, 24), fill=(160, 182, 235))
        img.save(os.path.join(out_dir, f"{lang}.png"), optimize=True)
        print(lang, os.path.getsize(os.path.join(out_dir, f"{lang}.png")) // 1024, "KB")


if __name__ == "__main__":
    main()
