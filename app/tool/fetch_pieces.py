#!/usr/bin/env python3
"""Re-download the bundled chess piece sets from the Lichess repo (lila).

Usage (from app/):  python3 tool/fetch_pieces.py

Writes assets/pieces/<id>/{wK,...,bP}.svg, sets.json is maintained by hand
next to them. Authors/licences come from lila's COPYING.md (see LICENSES.md).
Only normalisation: CSS <style> blocks (unsupported by flutter_svg) are
inlined into presentation attributes; the drawing itself is not touched.
"""
import re
import sys
import urllib.request
from pathlib import Path

BASE = "https://raw.githubusercontent.com/lichess-org/lila/master/public/piece"
SETS = ["merida", "cburnett", "chessnut", "mpchess", "celtic"]
PIECES = [c + p for c in "wb" for p in "KQRBNP"]
OUT = Path(__file__).resolve().parent.parent / "assets" / "pieces"


def inline_styles(svg: str) -> str:
    """Replace `<style>.cls{a:b;c:d}</style>` + class="cls" by attributes."""
    rules = {}
    for block in re.findall(r"<style[^>]*>(.*?)</style>", svg, re.S):
        for sel, body in re.findall(r"([^{}]+)\{([^{}]*)\}", block):
            for s in sel.split(","):
                s = s.strip()
                if re.fullmatch(r"\.[\w-]+", s):
                    rules.setdefault(s[1:], []).extend(
                        d.strip().split(":", 1) for d in body.split(";") if ":" in d)
                elif s:
                    raise ValueError(f"unsupported CSS selector {s!r}")
    svg = re.sub(r"<style[^>]*>.*?</style>", "", svg, flags=re.S)

    def repl(m):
        attrs = m.group(0)
        cls = re.search(r'\sclass="([^"]*)"', attrs)
        if not cls:
            return attrs
        add = ""
        have = set(re.findall(r'\s([\w:-]+)="', attrs))
        for c in cls.group(1).split():
            for k, v in rules.get(c, []):
                k = k.strip()
                if k not in have:
                    add += f' {k}="{v.strip()}"'
                    have.add(k)
        return attrs.replace(cls.group(0), add)

    return re.sub(r"<[a-zA-Z][^>]*\sclass=\"[^\"]*\"[^>]*>", repl, svg)


def main():
    for s in SETS:
        d = OUT / s
        d.mkdir(parents=True, exist_ok=True)
        for p in PIECES:
            with urllib.request.urlopen(f"{BASE}/{s}/{p}.svg", timeout=30) as r:
                svg = r.read().decode("utf-8")
            if "<style" in svg:
                svg = inline_styles(svg)
            (d / f"{p}.svg").write_text(svg, encoding="utf-8")
        print(s, sum(f.stat().st_size for f in d.glob("*.svg")), "bytes")


if __name__ == "__main__":
    sys.exit(main())
