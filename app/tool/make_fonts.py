#!/usr/bin/env python3
"""Build the bundled UI fonts: static, subset instances of Archivo and JetBrains Mono.

Usage (from app/):  python tool/make_fonts.py        (needs: pip install fonttools brotli)

Downloads the variable fonts + OFL.txt from the Google Fonts repo (both OFL 1.1,
no Reserved Font Name declared), instantiates the weights/widths the app uses with
fontTools.varLib.instancer, subsets to Latin + a few symbols (keeps kern/tnum/lnum/
case/liga/calt, drops hinting) and checks that the sample strings are covered.
"""
import io
import sys
import urllib.request
from pathlib import Path

from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

RAW = "https://raw.githubusercontent.com/google/fonts/main/ofl"
OUT = Path(__file__).resolve().parent.parent / "assets" / "fonts"

# (output name, source dir, variable file, axis limits)
JOBS = [
    ("Archivo-Regular", "archivo", "Archivo%5Bwdth%2Cwght%5D.ttf", {"wght": 400, "wdth": 100}),
    ("Archivo-Medium", "archivo", "Archivo%5Bwdth%2Cwght%5D.ttf", {"wght": 500, "wdth": 100}),
    ("Archivo-SemiBold", "archivo", "Archivo%5Bwdth%2Cwght%5D.ttf", {"wght": 600, "wdth": 100}),
    ("Archivo-Bold", "archivo", "Archivo%5Bwdth%2Cwght%5D.ttf", {"wght": 700, "wdth": 100}),
    ("ArchivoCondensed-SemiBold", "archivo", "Archivo%5Bwdth%2Cwght%5D.ttf", {"wght": 600, "wdth": 75}),
    ("ArchivoCondensed-Bold", "archivo", "Archivo%5Bwdth%2Cwght%5D.ttf", {"wght": 700, "wdth": 75}),
    ("JetBrainsMono-Regular", "jetbrainsmono", "JetBrainsMono%5Bwght%5D.ttf", {"wght": 400}),
    ("JetBrainsMono-Medium", "jetbrainsmono", "JetBrainsMono%5Bwght%5D.ttf", {"wght": 500}),
    # Barlow is a family of static files (axes None): subset only, no instancing.
    ("Barlow-Regular", "barlow", "Barlow-Regular.ttf", None),
    ("Barlow-Medium", "barlow", "Barlow-Medium.ttf", None),
    ("Barlow-SemiBold", "barlow", "Barlow-SemiBold.ttf", None),
    ("Barlow-Bold", "barlow", "Barlow-Bold.ttf", None),
    ("BarlowCondensed-SemiBold", "barlowcondensed", "BarlowCondensed-SemiBold.ttf", None),
    ("BarlowCondensed-Bold", "barlowcondensed", "BarlowCondensed-Bold.ttf", None),
]
LICENCES = {"archivo": "OFL-Archivo.txt", "jetbrainsmono": "OFL-JetBrainsMono.txt",
            "barlow": "OFL-Barlow.txt"}
# barlowcondensed/OFL.txt is byte-identical to barlow/OFL.txt, so one licence file is kept.
LICENCE_SRC = {"barlowcondensed": "barlow"}

UNICODES = (
    list(range(0x20, 0x7F)) + list(range(0xA0, 0x100)) + list(range(0x100, 0x180))
    + list(range(0x2010, 0x2028)) + list(range(0x2030, 0x203B)) + list(range(0x2190, 0x2194))
    + [0x2026, 0x20AC, 0x2212, 0xD7, 0x25CB, 0x25CF, 0x2713, 0xBD]
)
FEATURES = ["tnum", "lnum", "case", "liga", "kern", "calt", "mark", "mkmk", "ccmp", "locl"]
SAMPLES = ["Diagrama 12 · Mueven blancas ñ á ü ¿? ½ → 0123456789", "rnbqkbnr/pppppppp/8/8/4P3 w KQkq - 0 1", "r1bq1rk1/pp2ppbp w KQkq - 0 1"]


def fetch(url):
    with urllib.request.urlopen(url, timeout=60) as r:
        return r.read()


def set_names(font, family, style):
    name = font["name"]
    for rec in list(name.names):
        if rec.nameID in (1, 2, 3, 4, 6, 16, 17, 21, 22, 25):
            name.removeNames(nameID=rec.nameID)
    ps = f"{family.replace(' ', '')}-{style.replace(' ', '')}"
    for nid, val in ((1, family), (2, style), (3, f"{ps};static"), (4, f"{family} {style}"), (6, ps)):
        name.setName(val, nid, 3, 1, 0x409)
        name.setName(val, nid, 1, 0, 0)


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    cache = {}
    for out, d, fname, axes in JOBS:
        if (d, fname) not in cache:
            cache[(d, fname)] = fetch(f"{RAW}/{d}/{fname}")
            lic = LICENCE_SRC.get(d, d)
            data = fetch(f"{RAW}/{d}/OFL.txt")
            if d in LICENCE_SRC:
                assert data == fetch(f"{RAW}/{lic}/OFL.txt"), f"{d} licence differs from {lic}"
            else:
                (OUT / LICENCES[d]).write_bytes(data)
        font = TTFont(io.BytesIO(cache[(d, fname)]))
        if axes:
            font = instancer.instantiateVariableFont(font, axes)
        opts = subset.Options()
        opts.layout_features = FEATURES
        opts.hinting = False
        opts.notdef_outline = True
        opts.name_IDs = [0, 1, 2, 3, 4, 5, 6, 13, 14]
        sub = subset.Subsetter(opts)
        sub.populate(unicodes=UNICODES)
        sub.subset(font)
        family, style = out.split("-")
        family = {"Archivo": "Archivo", "ArchivoCondensed": "Archivo Condensed", "Barlow": "Barlow",
                  "BarlowCondensed": "Barlow Condensed"}.get(family, "JetBrains Mono")
        set_names(font, family, {"SemiBold": "SemiBold"}.get(style, style))
        cmap = font.getBestCmap()
        # Upstream Barlow has no arrows (U+2190-2193), check marks or circles; Flutter falls back
        # to another font for them, so only U+2192 in the sample text is tolerated as missing.
        optional = {"→"} if out.startswith("Barlow") else set()
        missing = {c for s in SAMPLES for c in s if ord(c) not in cmap} - optional
        assert not missing, f"{out}: missing glyphs {missing}"
        if out.startswith("Barlow"):
            feats = {f.FeatureTag for f in font["GSUB"].table.FeatureList.FeatureRecord}
            assert "tnum" in feats, f"{out}: no tnum feature"
        path = OUT / f"{out}.ttf"
        font.save(path)
        print(f"{path.name}: {path.stat().st_size} bytes")


if __name__ == "__main__":
    sys.exit(main())
