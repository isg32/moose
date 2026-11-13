#!/usr/bin/env python3
"""Moose's launcher icon: the MO/OSE wordmark (Doto 900, white) on the
night wallpaper (DESIGN.md). Writes Android's adaptive icon (background,
foreground and a monochrome layer for themed icons) and the legacy sizes.

  tool/partner/.venv/bin/python tool/icon/make_icon.py
"""

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parents[2]
RES = ROOT / "android/app/src/main/res"
FONT = ROOT / "assets/fonts/Doto.ttf"

# The night wallpaper: base and three soft blobs (colour, x%, y%, size%).
BASE = (6, 7, 10)
BLOBS = [((0x24, 0x34, 0x4F), 15, 10, 60), ((0x3D, 0x25, 0x36), 95, 55, 50), ((0x15, 0x32, 0x2F), 30, 105, 60)]


def night(size: int) -> Image.Image:
    img = Image.new("RGB", (size, size), BASE)
    for colour, x, y, r in BLOBS:
        layer = Image.new("RGB", (size, size), BASE)
        d = ImageDraw.Draw(layer)
        cx, cy, rr = size * x / 100, size * y / 100, size * r / 100
        d.ellipse((cx - rr, cy - rr * 0.75, cx + rr, cy + rr * 0.75), fill=colour)
        layer = layer.filter(ImageFilter.GaussianBlur(size * 0.18))
        img = Image.composite(layer, img, Image.new("L", (size, size), 200))
    return img


def wordmark(size: int, scale: float, colour=(255, 255, 255, 255)) -> Image.Image:
    """MO over OSE, centred, its block [scale] of [size] wide."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    font = ImageFont.truetype(str(FONT), 100)
    try:
        font.set_variation_by_axes([900])
    except Exception:  # noqa: BLE001 - a static build of the font
        pass
    # Measure at 100 px, then size so the wider line fills [scale].
    probe = ImageDraw.Draw(img)
    w = max(probe.textlength(t, font=font) for t in ("MO", "OSE"))
    px = int(100 * size * scale / w)
    font = ImageFont.truetype(str(FONT), px)
    try:
        font.set_variation_by_axes([900])
    except Exception:  # noqa: BLE001
        pass
    d = ImageDraw.Draw(img)
    line = px * 0.92
    top = size / 2 - line
    for i, text in enumerate(("MO", "OSE")):
        tw = d.textlength(text, font=font)
        d.text(((size - tw) / 2, top + i * line), text, font=font, fill=colour)
    return img


def main() -> None:
    dens = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}
    for name, k in dens.items():
        out = RES / f"mipmap-{name}"
        out.mkdir(parents=True, exist_ok=True)
        # Adaptive layers are 108 dp; the safe zone is the middle 66 dp.
        layer = int(108 * k)
        night(layer).save(out / "ic_launcher_background.png")
        wordmark(layer, 0.42).save(out / "ic_launcher_foreground.png")
        wordmark(layer, 0.42).save(out / "ic_launcher_monochrome.png")
        # Legacy: 48 dp, a rounded square.
        size = int(48 * k)
        icon = night(size).convert("RGBA")
        icon.alpha_composite(wordmark(size, 0.62))
        mask = Image.new("L", (size, size), 0)
        ImageDraw.Draw(mask).rounded_rectangle((0, 0, size - 1, size - 1), radius=size * 0.22, fill=255)
        icon.putalpha(mask)
        icon.save(out / "ic_launcher.png")
    anydpi = RES / "mipmap-anydpi-v26"
    anydpi.mkdir(exist_ok=True)
    (anydpi / "ic_launcher.xml").write_text(
        '<?xml version="1.0" encoding="utf-8"?>\n'
        '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
        '    <background android:drawable="@mipmap/ic_launcher_background"/>\n'
        '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
        '    <monochrome android:drawable="@mipmap/ic_launcher_monochrome"/>\n'
        "</adaptive-icon>\n"
    )
    print("icons written to", RES)


if __name__ == "__main__":
    main()
