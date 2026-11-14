"""Builds app/assets/fonts/ChessFigures.ttf: the 12 chess figures of DejaVu Sans, nothing else.

    pip install fonttools
    python app/tool/make_figures_font.py [/path/to/DejaVuSans.ttf]

The app draws its board with this font instead of the system one: on Android the system replaces the
pawn (U+265F, the only chess figure that is also an emoji) with a colour emoji that ignores the text
colour, so white and black pawns looked the same. The font is renamed, as the DejaVu licence asks of
modified versions (see app/assets/fonts/LICENSE-DejaVu.txt).
"""
import sys
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont

SRC = sys.argv[1] if len(sys.argv) > 1 else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
OUT = Path(__file__).resolve().parent.parent / "assets" / "fonts" / "ChessFigures.ttf"
NAME = "ChessFigures"

options = subset.Options(layout_features=[], hinting=False, name_IDs=[0, 1, 2, 3, 4, 6], notdef_outline=True)
font = TTFont(SRC)
sub = subset.Subsetter(options)
sub.populate(unicodes=range(0x2654, 0x2660))
sub.subset(font)
for record in font["name"].names:
    if record.nameID in (1, 4, 6):
        record.string = NAME
    elif record.nameID == 3:
        record.string = NAME + " (chess figures of DejaVu Sans)"
# One-em line box with the figures (all 0..1496 units high) centred in it, so a figure centres in its square.
em = font["head"].unitsPerEm
top = max(font["glyf"][g].yMax for g in font.getGlyphOrder())
ascent = top + (em - top) // 2
font["hhea"].ascent, font["hhea"].descent, font["hhea"].lineGap = ascent, ascent - em, 0
os2 = font["OS/2"]
os2.sTypoAscender, os2.sTypoDescender, os2.sTypoLineGap = ascent, ascent - em, 0
os2.usWinAscent, os2.usWinDescent = ascent, em - ascent
font.save(OUT)
print(OUT, OUT.stat().st_size, "bytes", sorted(hex(c) for c in TTFont(OUT).getBestCmap()))
