"""Regenerates the app icons (Android legacy + adaptive layers, Windows .ico) from one drawing.

    python3 tool/make_icons.py        # needs Pillow and the DejaVu Sans font (free licence)

A cream knight on a brown square, the same brown as the app theme.
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
BROWN, CREAM = (93, 64, 55, 255), (240, 217, 181, 255)  # #5D4037, #F0D9B5
KNIGHT = "♞"


def knight_layer(size: int, glyph_frac: float) -> Image.Image:
    """Transparent canvas with the knight centred; glyph_frac = knight height / canvas."""
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    font = ImageFont.truetype(FONT, int(size * glyph_frac * 1.35))
    d = ImageDraw.Draw(img)
    l, t, r, b = d.textbbox((0, 0), KNIGHT, font=font)
    d.text(((size - (r - l)) / 2 - l, (size - (b - t)) / 2 - t), KNIGHT, font=font, fill=CREAM)
    return img


def legacy_icon(size: int) -> Image.Image:
    s = size * 4  # draw large, then reduce for clean edges
    img = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    ImageDraw.Draw(img).rounded_rectangle((0, 0, s - 1, s - 1), radius=int(s * 0.22), fill=BROWN)
    img.alpha_composite(knight_layer(s, 0.62))
    return img.resize((size, size), Image.LANCZOS)


res = ROOT / "android/app/src/main/res"
for density, px in {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144, "xxxhdpi": 192}.items():
    legacy_icon(px).save(res / f"mipmap-{density}/ic_launcher.png", optimize=True)
    # adaptive icon layers are 108 dp: the knight must stay inside the central 66 dp (about 61 %)
    layer_px = round(px * 108 / 48)
    s = layer_px * 4
    knight_layer(s, 0.38).resize((layer_px, layer_px), Image.LANCZOS).save(
        res / f"mipmap-{density}/ic_launcher_foreground.png", optimize=True)

(res / "mipmap-anydpi-v26").mkdir(exist_ok=True)
(res / "mipmap-anydpi-v26/ic_launcher.xml").write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
    '    <background android:drawable="@color/ic_launcher_background"/>\n'
    '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
    '</adaptive-icon>\n')
(res / "values/ic_launcher_background.xml").write_text(
    '<?xml version="1.0" encoding="utf-8"?>\n'
    '<resources>\n'
    '    <color name="ic_launcher_background">#5D4037</color>\n'
    '</resources>\n')

master = legacy_icon(256)
master.save(ROOT / "windows/runner/resources/app_icon.ico", format="ICO",
            sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
print("icons written")
