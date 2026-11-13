"""Synthetic training data: random positions rendered as digital diagrams in many styles.

Why synthetic: labelled *digital diagrams* barely exist as a public dataset, but they are
cheap to render. Robustness to unseen piece designs comes from variety (several font
families + an SVG set), stroke/size/slant jitter, hatched/stippled/flat/coloured squares,
page margins with coordinates and captions, down-scaling blur, noise and JPEG artefacts.

Piece "families" (cburnett / dejavu / freefont / unifont) exist so experiments can hold a
whole family out and measure how the model copes with a design it never saw.
"""
from __future__ import annotations

import random
from concurrent.futures import ProcessPoolExecutor
from dataclasses import dataclass
from pathlib import Path

import chess
import chess.svg
import cv2
import numpy as np
import pymupdf
from PIL import Image, ImageDraw, ImageFont

from . import CLASSES
from .squares import SQUARE, cut_squares

SPRITE = 192  # canvas (px) of the pre-rendered piece sprites
SS = 3  # supersampling used while drawing a board

_DEJAVU = "/usr/share/fonts/truetype/dejavu/"
_FREE = "/usr/share/fonts/truetype/freefont/"
FONTS = {  # name -> (family, path). Missing fonts are skipped.
    "dejavu_sans": ("dejavu", _DEJAVU + "DejaVuSans.ttf"),
    "dejavu_bold": ("dejavu", _DEJAVU + "DejaVuSans-Bold.ttf"),
    "dejavu_mono": ("dejavu", _DEJAVU + "DejaVuSansMono.ttf"),
    "free_serif": ("freefont", _FREE + "FreeSerif.ttf"),
    "free_serif_bold": ("freefont", _FREE + "FreeSerifBold.ttf"),
    "free_mono": ("freefont", _FREE + "FreeMono.ttf"),
    "unifont": ("unifont", "/usr/share/fonts/opentype/unifont/unifont.otf"),
}
_WHITE_CP = {"K": 0x2654, "Q": 0x2655, "R": 0x2656, "B": 0x2657, "N": 0x2658, "P": 0x2659}
_SYMS = "PNBRQKpnbrqk"
_TEXT_FONT = _DEJAVU + "DejaVuSans.ttf"


@dataclass
class SpriteSet:
    name: str
    family: str
    sprites: dict[str, np.ndarray]  # symbol -> RGBA uint8 (SPRITE, SPRITE, 4)


def _svg_sprite(sym: str) -> np.ndarray:
    svg = chess.svg.piece(chess.Piece.from_symbol(sym), size=SPRITE)
    page = pymupdf.open(stream=svg.encode(), filetype="svg")[0]
    zoom = SPRITE / page.rect.width
    pix = page.get_pixmap(matrix=pymupdf.Matrix(zoom, zoom), alpha=True)
    arr = np.frombuffer(pix.samples, np.uint8).reshape(pix.height, pix.width, pix.n)
    out = np.zeros((SPRITE, SPRITE, 4), np.uint8)
    out[: arr.shape[0], : arr.shape[1]] = arr[:SPRITE, :SPRITE]
    return out


def _font_sprites(path: str, mode: str) -> dict[str, np.ndarray]:
    """mode: outline = classic Unicode look, stroke = solid silhouettes (white ones with a
    black stroke), engraved = solid silhouettes with the inner detail lines drawn on top."""
    probe = ImageFont.truetype(path, 400)
    extents = [probe.getbbox(chr(_WHITE_CP[s] + 6), anchor="ls") for s in "PNBRQK"]
    biggest = max(max(b[3] - b[1], b[2] - b[0]) for b in extents)
    font = ImageFont.truetype(path, max(8, int(400 * 0.9 * SPRITE / biggest)))
    sprites = {}
    for sym in _SYMS:
        white = sym.isupper()
        solid, line = chr(_WHITE_CP[sym.upper()] + 6), chr(_WHITE_CP[sym.upper()])
        left, _, right, bottom = font.getbbox(solid, anchor="ls")
        origin = (SPRITE / 2 - (left + right) / 2, 0.97 * SPRITE - bottom)
        img = Image.new("RGBA", (SPRITE, SPRITE), (0, 0, 0, 0))
        d = ImageDraw.Draw(img)
        W, B = (255, 255, 255, 255), (0, 0, 0, 255)
        stroke = max(2, SPRITE // 40)
        if mode == "outline":
            if white:
                d.text(origin, solid, font=font, fill=W, anchor="ls")
                d.text(origin, line, font=font, fill=B, anchor="ls")
            else:
                d.text(origin, solid, font=font, fill=B, anchor="ls")
        elif mode == "stroke":
            if white:
                d.text(origin, solid, font=font, fill=W, anchor="ls", stroke_width=stroke, stroke_fill=B)
            else:
                d.text(origin, solid, font=font, fill=B, anchor="ls")
        else:  # engraved
            d.text(origin, solid, font=font, fill=W if white else B, anchor="ls", stroke_width=1, stroke_fill=B)
            d.text(origin, line, font=font, fill=B if white else W, anchor="ls")
        sprites[sym] = np.array(img)
    return sprites


def build_sprite_sets() -> list[SpriteSet]:
    sets = [SpriteSet("cburnett", "cburnett", {s: _svg_sprite(s) for s in _SYMS})]
    for name, (family, path) in FONTS.items():
        if Path(path).exists():
            for mode in ("outline", "stroke", "engraved"):
                sets.append(SpriteSet(f"{name}:{mode}", family, _font_sprites(path, mode)))
    return sets


# ----------------------------------------------------------------------------- positions
def random_grid(rng: random.Random) -> list[int]:
    """Random plausible-looking position (not necessarily reachable): 64 class ids."""
    grid = [0] * 64
    squares = list(range(64))
    rng.shuffle(squares)
    grid[squares.pop()] = CLASSES.index("K")
    grid[squares.pop()] = CLASSES.index("k")
    n = int(min(30, max(0, rng.triangular(2, 30, 14))))
    kinds = ["P"] * 8 + ["N"] * 2 + ["B"] * 2 + ["R"] * 2 + ["Q"] * 1
    for sq in squares[:n]:
        sym = rng.choice(kinds)
        if rng.random() < 0.5:
            sym = sym.lower()
        if sym in "Pp" and (sq < 8 or sq >= 56):
            sym = rng.choice("NBRQ") if sym == "P" else rng.choice("nbrq")
        grid[sq] = CLASSES.index(sym)
    return grid


# ----------------------------------------------------------------------------- drawing
def _pattern_tile(c: int, rng: random.Random, base: float, ink: float, kind: str) -> np.ndarray:
    """c x c float tile of one square's background (gray level 0..255)."""
    yy, xx = np.mgrid[0:c, 0:c].astype(np.float32)
    p = SS * rng.uniform(1.6, 4.0)
    thick = rng.uniform(0.25, 0.55)
    if kind == "flat":
        mask = np.zeros((c, c), np.float32)
    elif kind == "dots":
        mask = ((np.sin(2 * np.pi * xx / p) * np.sin(2 * np.pi * yy / p)) > 0.2).astype(np.float32)
    elif kind == "hatch":
        mask = (((xx + yy) % p) < thick * p).astype(np.float32)
    elif kind == "cross":
        mask = ((xx % p < thick * p) | (yy % p < thick * p)).astype(np.float32)
    elif kind == "mesh":  # one-pixel checker at final resolution, like old print screens
        mask = (((xx // SS) + (yy // SS)) % 2).astype(np.float32)
    else:  # speckle
        mask = (np.random.default_rng(rng.getrandbits(32)).random((c, c)) < rng.uniform(0.2, 0.5)).astype(np.float32)
    return base * (1 - mask) + ink * mask


def _prep_sprite(sprite: np.ndarray, c: int, rng: random.Random, bold: int, ax: float, slant: float) -> np.ndarray:
    size = max(4, int(c * rng.uniform(0.86, 1.0)))
    w, h = max(4, int(size * ax)), size
    sp = cv2.resize(sprite, (w, h), interpolation=cv2.INTER_AREA).astype(np.float32)
    if bold > 0:
        k = np.ones((bold, bold), np.uint8)
        sp[..., :3] = cv2.erode(sp[..., :3], k)  # darker ink grows
        sp[..., 3] = cv2.dilate(sp[..., 3], k)
    if abs(slant) > 1e-3:
        m = np.array([[1, slant, -slant * h / 2], [0, 1, 0]], np.float32)
        sp = cv2.warpAffine(sp, m, (w, h), flags=cv2.INTER_LINEAR)
    return sp


def render_board(grid, sets: list[SpriteSet], rng: random.Random, set_idx: int | None = None):
    """Draw one diagram. Returns (RGB uint8 image, ground-truth board box, SpriteSet used)."""
    sset = sets[rng.randrange(len(sets))] if set_idx is None else sets[set_idx]
    cell = int(np.exp(rng.uniform(np.log(11), np.log(64))))
    c = cell * SS

    # colours / square patterns
    if rng.random() < 0.55:  # black & white print
        paper = rng.uniform(240, 255)
        light_base, dark_base = paper, rng.uniform(150, 235)
        pat = rng.choice(["flat", "dots", "hatch", "cross", "mesh", "speckle"])
        dark_ink = rng.uniform(40, 130) if pat != "flat" else dark_base
        light_pat = rng.choice(["flat"] * 6 + ["dots"])
        tiles = (
            _pattern_tile(c, rng, light_base, 190, light_pat),
            _pattern_tile(c, rng, light_base if pat != "flat" else dark_base, dark_ink, pat),
        )
        tile_rgb = [np.repeat(t[..., None], 3, 2) for t in tiles]
    else:
        palettes = [((240, 217, 181), (181, 136, 99)), ((238, 238, 210), (118, 150, 86)),
                    ((222, 227, 230), (140, 162, 173)), ((234, 233, 210), (75, 115, 153)),
                    ((255, 255, 255), (170, 170, 170))]
        li, da = rng.choice(palettes) if rng.random() < 0.8 else (
            tuple(rng.randrange(150, 256) for _ in range(3)), tuple(rng.randrange(40, 200) for _ in range(3)))
        tile_rgb = [np.ones((c, c, 3), np.float32) * np.array(li, np.float32),
                    np.ones((c, c, 3), np.float32) * np.array(da, np.float32)]

    side = 8 * c
    board = np.zeros((side, side, 3), np.float32)
    for r in range(8):
        for f in range(8):
            t = tile_rgb[(r + f) % 2]  # (r + f) even = light square (a8 is light)
            board[r * c:(r + 1) * c, f * c:(f + 1) * c] = np.roll(t, (rng.randrange(c), rng.randrange(c)), (0, 1))

    # pieces
    bold = rng.choice([0, 0, 1, 2]) * max(1, SS // 2)
    ax, slant = rng.uniform(0.9, 1.1), rng.uniform(-0.05, 0.05)
    prepared = {s: _prep_sprite(sset.sprites[s], c, rng, bold, ax, slant) for s in _SYMS}
    ink_tone = rng.uniform(0.0, 0.35) if rng.random() < 0.3 else 0.0  # greyer print
    for i, k in enumerate(grid):
        if k == 0:
            continue
        sp = prepared[CLASSES[k]]
        h, w = sp.shape[:2]
        r, f = divmod(i, 8)
        x = f * c + (c - w) // 2 + int(rng.uniform(-0.03, 0.03) * c)
        y = r * c + c - h - int(rng.uniform(0, 0.06) * c)
        x, y = min(max(x, 0), side - w), min(max(y, 0), side - h)
        a = sp[..., 3:4] / 255.0
        rgb = sp[..., :3] * (1 - ink_tone) + 255 * ink_tone * (sp[..., :3] < 128)
        board[y:y + h, x:x + w] = board[y:y + h, x:x + w] * (1 - a) + rgb * a

    # frame
    frame = max(1, int(round(cell * rng.uniform(0, 0.07)))) * SS if rng.random() < 0.8 else 0
    ml, mr, mt, mb = [int(rng.uniform(0.15, 1.0) * c) if rng.random() < 0.8 else 0 for _ in range(4)]
    tight = rng.random() < 0.12
    if tight:
        ml = mr = mt = mb = 0
    page_bg = np.array([rng.uniform(244, 255)] * 3, np.float32) if rng.random() < 0.88 else np.array(
        [rng.uniform(20, 70)] * 3 if rng.random() < 0.5 else [rng.randrange(120, 250) for _ in range(3)], np.float32)
    H, W = side + mt + mb + 2 * frame, side + ml + mr + 2 * frame
    page = np.ones((H, W, 3), np.float32) * page_bg
    if frame:
        page[mt:H - mb, ml:W - mr] = rng.uniform(0, 60)
    page[mt + frame:mt + frame + side, ml + frame:ml + frame + side] = board
    bx0, by0 = ml + frame, mt + frame

    # coordinates and captions in the margins (never over the board)
    pil = Image.fromarray(np.clip(page, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(pil)
    txt_col = (0, 0, 0) if page_bg.mean() > 128 else (230, 230, 230)
    font = ImageFont.truetype(_TEXT_FONT, max(6, int(c * rng.uniform(0.28, 0.45))))
    if mb > c * 0.4 and rng.random() < 0.6:
        for f in range(8):
            d.text((bx0 + f * c + c // 2, by0 + side + frame + mb // 2), "abcdefgh"[f], font=font, fill=txt_col, anchor="mm")
    if ml > c * 0.4 and rng.random() < 0.6:
        for r in range(8):
            d.text((ml // 2, by0 + r * c + c // 2), str(8 - r), font=font, fill=txt_col, anchor="mm")
    if mt > c * 0.4 and rng.random() < 0.3:
        d.text((bx0, mt // 2), f"{rng.randrange(1, 400)}", font=font, fill=txt_col, anchor="lm")
    page = np.array(pil).astype(np.float32)

    # down-scale (with slight non-uniform stretch), blur, noise, JPEG, tone
    sx, sy = rng.uniform(0.92, 1.08), rng.uniform(0.92, 1.08)
    fw, fh = max(16, round(W / SS * sx)), max(16, round(H / SS * sy))
    img = cv2.resize(page, (fw, fh), interpolation=cv2.INTER_AREA)
    if rng.random() < 0.7:
        img = cv2.GaussianBlur(img, (0, 0), rng.uniform(0.3, 0.9))
    img += np.random.default_rng(rng.getrandbits(32)).normal(0, rng.uniform(0, 4), img.shape)
    img = (img - 128) * rng.uniform(0.75, 1.1) + 128 + rng.uniform(-18, 18)
    img = np.clip(img, 0, 255).astype(np.uint8)
    if rng.random() < 0.7:
        ok, buf = cv2.imencode(".jpg", img[..., ::-1], [cv2.IMWRITE_JPEG_QUALITY, rng.randrange(35, 96)])
        img = cv2.imdecode(buf, cv2.IMREAD_COLOR)[..., ::-1]
    kx, ky = fw / W, fh / H
    box = (bx0 * kx, by0 * ky, (bx0 + side) * kx, (by0 + side) * ky)
    return np.ascontiguousarray(img), box, sset


def jitter_box(box, rng: random.Random, amount: float = 0.10):
    x0, y0, x1, y1 = box
    cw, ch = (x1 - x0) / 8, (y1 - y0) / 8
    j = lambda: rng.uniform(-amount, amount)
    return (x0 + j() * cw, y0 + j() * ch, x1 + j() * cw, y1 + j() * ch)


# ----------------------------------------------------------------------------- datasets
def _worker(args):
    seed, n_boards, allow_families = args
    rng = random.Random(seed)
    sets = [s for s in build_sprite_sets() if allow_families is None or s.family in allow_families]
    xs, ys = [], []
    for _ in range(n_boards):
        grid = random_grid(rng)
        img, box, _ = render_board(grid, sets, rng)
        cells = cut_squares(img, jitter_box(box, rng), SQUARE)
        xs.append((cells * 255).round().astype(np.uint8))
        ys.append(np.asarray(grid, np.int8))
    return np.concatenate(xs), np.concatenate(ys)


def make_dataset(n_boards: int, seed: int, families: set[str] | None = None, workers: int = 4):
    """(X uint8 (n*64, 32, 32), y int8 (n*64,)) rendered from `families` (None = all)."""
    chunks = max(workers * 4, 1)
    per = max(1, n_boards // chunks)
    jobs = [(seed * 100003 + i, per, families) for i in range(chunks)]
    with ProcessPoolExecutor(workers) as ex:
        parts = list(ex.map(_worker, jobs))
    return np.concatenate([p[0] for p in parts]), np.concatenate([p[1] for p in parts])
