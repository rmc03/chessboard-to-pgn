"""Adapt the classifier to ONE real book/site whose diagrams all use the same typeface.

Workflow (the data directory stays out of git: page images and glyphs are someone's artwork):

  1. python -m chessdiag.book extract --pages data/book/pages --model ../models/squares.tflite --out data/book
        finds every framed board, cuts the squares, clusters the occupied ones by shape and writes
        clusters.png: one row per cluster (same piece, same colour, same square colour).
  2. Look at clusters.png and say what each row is, top to bottom:
     python -m chessdiag.book label --out data/book --rows "p P p P n K R k r N r R Q q B B b b"
        writes book_cells.npz + labels.json and checks every board against the rules of chess.
        Mis-identified rows show up as boards with two kings, back-rank pawns, impossible checks...
  3. python -m chessdiag.train --book data/book/book_cells.npz ...   (see train.py)

Why clustering instead of trusting an existing model: a model that has never seen the typeface is
confidently wrong in a consistent way (v2 read every pawn of the first book as a bishop), so its
guesses would poison the labels. Shapes of one typeface cluster almost perfectly, and identifying
~18 clusters once is far less work, and far safer, than labelling ~500 squares.
"""
from __future__ import annotations

import argparse
import collections
import json
import random
from dataclasses import dataclass
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

from . import CLASSES
from .fen import grid_to_placement, suggest_turn, to_fen, validate
from .locate import find_board, find_boards
from .squares import cut_squares

CELL = 48  # pool resolution: close to the native size of phone screenshots


# ----------------------------------------------------------------------------- pool for synthesis
@dataclass
class BookPool:
    cells: np.ndarray  # (N, CELL, CELL) uint8 gray
    cls: np.ndarray  # (N,) class id (0 = empty)
    parity: np.ndarray  # (N,) 0 = light square, 1 = dark square

    @staticmethod
    def load(path: str | Path, pages: set[str] | None = None) -> "BookPool":
        d = np.load(path)
        keep = np.ones(len(d["cls"]), bool) if pages is None else np.isin(d["page"], list(pages))
        return BookPool(d["cells"][keep], d["cls"][keep], d["parity"][keep])

    def __post_init__(self):
        self._index = collections.defaultdict(list)
        for i, (k, p) in enumerate(zip(self.cls, self.parity)):
            self._index[(int(k), int(p))].append(i)
        self._by_class = collections.defaultdict(list)
        for i, k in enumerate(self.cls):
            self._by_class[int(k)].append(i)

    def sample(self, cls: int, parity: int, rng: random.Random) -> np.ndarray:
        pool = self._index.get((cls, parity)) or self._by_class.get(cls)  # same class on the other square colour as fallback
        return self.cells[rng.choice(pool)]


def render_book_board(grid, pool: BookPool, rng: random.Random):
    """Board assembled from real cells, then rescaled/blurred/noised/JPEG'd. Returns (RGB uint8, box)."""
    board = np.empty((8 * CELL, 8 * CELL), np.uint8)
    for i, k in enumerate(grid):
        r, f = divmod(i, 8)
        board[r * CELL:(r + 1) * CELL, f * CELL:(f + 1) * CELL] = pool.sample(k, (r + f) % 2, rng)
    frame = rng.choice([0, 1, 2, 2, 3])
    page = np.full((8 * CELL + 2 * frame + 2 * 6, 8 * CELL + 2 * frame + 2 * 6), 255, np.uint8)
    if frame:
        page[6:-6, 6:-6] = 0
    page[6 + frame:6 + frame + 8 * CELL, 6 + frame:6 + frame + 8 * CELL] = board
    scale = np.exp(rng.uniform(np.log(0.4), np.log(1.5)))  # phone zoom levels
    size = max(40, round(page.shape[0] * scale))
    img = cv2.resize(page, (size, size), interpolation=cv2.INTER_AREA if scale < 1 else rng.choice([cv2.INTER_LINEAR, cv2.INTER_CUBIC])).astype(np.float32)
    if rng.random() < 0.6:
        img = cv2.GaussianBlur(img, (0, 0), rng.uniform(0.3, 0.9))
    img += np.random.default_rng(rng.getrandbits(32)).normal(0, rng.uniform(0, 3), img.shape)
    img = np.clip((img - 128) * rng.uniform(0.85, 1.05) + 128 + rng.uniform(-10, 10), 0, 255).astype(np.uint8)
    if rng.random() < 0.7:
        img = cv2.imdecode(cv2.imencode(".jpg", img, [cv2.IMWRITE_JPEG_QUALITY, rng.randrange(50, 96)])[1], cv2.IMREAD_GRAYSCALE)
    k = size / page.shape[0]
    lo, hi = (6 + frame) * k, (6 + frame + 8 * CELL) * k  # the 8x8 cells only, as in synth.py
    box = (lo, lo, hi, hi)
    return np.stack([img] * 3, -1), box


# ----------------------------------------------------------------------------- harvesting
def _montage(cells: np.ndarray, labels: np.ndarray, k: int, path: Path, per_row: int = 12) -> None:
    order = np.argsort(-np.bincount(labels, minlength=k))
    s = 64
    sheet = np.full((k * s, (per_row + 1) * s, 3), 255, np.uint8)
    for row, c in enumerate(order):
        idx = np.flatnonzero(labels == c)
        cv2.putText(sheet, f"row {row}", (2, row * s + 24), cv2.FONT_HERSHEY_SIMPLEX, 0.55, (200, 0, 0), 2, cv2.LINE_AA)
        cv2.putText(sheet, f"n={len(idx)}", (2, row * s + 48), cv2.FONT_HERSHEY_SIMPLEX, 0.5, (200, 0, 0), 1, cv2.LINE_AA)
        for j, i in enumerate(np.random.default_rng(0).permutation(idx)[:per_row]):
            t = cv2.resize(cells[i], (s - 2, s - 2), interpolation=cv2.INTER_CUBIC)
            sheet[row * s + 1:row * s + s - 1, (j + 1) * s + 1:(j + 1) * s + s - 1] = t[..., None]
        sheet[row * s, :] = 170
    Image.fromarray(sheet).save(path)


def extract(pages_dir: Path, model: Path, out: Path, k: int = 18) -> None:
    from .model import predict_tflite

    predict = predict_tflite(model)
    out.mkdir(parents=True, exist_ok=True)
    recs = []  # (board_id, page, square, cell48, occupied)
    board_id = 0
    for f in sorted(pages_dir.glob("*.jp*g")) + sorted(pages_dir.glob("*.png")):
        img = np.array(Image.open(f).convert("RGB"))
        for x0, y0, x1, y1 in find_boards(img):
            pad = 16
            ox, oy = max(0, int(x0) - pad), max(0, int(y0) - pad)
            crop = img[oy:int(y1) + pad, ox:int(x1) + pad]
            box = find_board(crop)
            occupied = 1 - predict(cut_squares(crop, box, 32))[:, 0] > 0.5  # emptiness is easy even for an unseen style
            cells = cut_squares(crop, box, CELL)
            for sq in range(64):
                recs.append((board_id, f.stem, sq, (cells[sq] * 255).round().astype(np.uint8), bool(occupied[sq])))
            board_id += 1
    cells = np.stack([r[3] for r in recs])
    occ = np.array([r[4] for r in recs])
    small = np.stack([cv2.resize(c, (32, 32), interpolation=cv2.INTER_AREA) for c in cells[occ]]).reshape(occ.sum(), -1).astype(np.float32)
    cv2.setRNGSeed(3)
    _, labels, _ = cv2.kmeans(small, k, None, (cv2.TERM_CRITERIA_EPS + cv2.TERM_CRITERIA_MAX_ITER, 100, 1e-4), 20, cv2.KMEANS_PP_CENTERS)
    labels = labels.ravel()
    cluster = np.full(len(recs), -1, np.int16)
    cluster[np.flatnonzero(occ)] = labels
    np.savez_compressed(out / "extracted.npz", board=np.array([r[0] for r in recs]), page=np.array([r[1] for r in recs]),
                        sq=np.array([r[2] for r in recs]), cells=cells, occ=occ, cluster=cluster)
    _montage(cells[occ], labels, k, out / "clusters.png")
    print(f"{board_id} boards, {occ.sum()} pieces, {k} clusters -> {out / 'clusters.png'}")
    print("pieces per board:", occ.reshape(-1, 64).sum(1).tolist())


def label(out: Path, rows: list[str]) -> None:
    d = np.load(out / "extracted.npz")
    cluster, occ = d["cluster"], d["occ"]
    k = len(rows)
    sizes = np.bincount(cluster[cluster >= 0], minlength=k)
    if len(sizes) != k:
        raise SystemExit(f"--rows has {k} entries but there are {len(sizes)} clusters")
    sym_of = {int(c): rows[r] for r, c in enumerate(np.argsort(-sizes))}  # montage rows are sorted by size
    sym = np.array(["."] * len(cluster), dtype="<U1")
    sym[cluster >= 0] = [sym_of[int(c)] for c in cluster[cluster >= 0]]
    cls = np.array([CLASSES.index(s) if s != "." else 0 for s in sym], np.int8)
    sq = d["sq"]
    parity = (((sq // 8) + (sq % 8)) % 2).astype(np.int8)
    labels, bad = {}, 0
    for b in sorted(set(d["board"].tolist())):
        m = d["board"] == b
        row = sym[m]
        cnt = collections.Counter(row)
        problems = []
        if cnt["K"] != 1 or cnt["k"] != 1:
            problems.append("kings")
        if cnt["P"] > 8 or cnt["p"] > 8:
            problems.append(">8 pawns")
        if any(c in "Pp" for c in list(row[:8]) + list(row[56:])):
            problems.append("back-rank pawn")
        placement = grid_to_placement(cls[m])
        if not problems and "check" in " ".join(validate(to_fen(placement, suggest_turn(placement) or "w", "-"))):
            problems.append("impossible check")
        bad += bool(problems)
        labels[b] = {"page": str(d["page"][m][0]), "placement": placement, "problems": problems}
        print(f"board {b:3d} {labels[b]['page']:<10} {placement:<52} {problems or 'ok'}")
    print(f"{bad} of {len(labels)} boards break the rules of chess" + ("  <- a row label is probably wrong" if bad else ""))
    np.savez_compressed(out / "book_cells.npz", cells=d["cells"], cls=cls, parity=parity, page=d["page"], board=d["board"])
    (out / "labels.json").write_text(json.dumps(labels, indent=1))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    e = sub.add_parser("extract")
    e.add_argument("--pages", type=Path, required=True)
    e.add_argument("--model", type=Path, required=True)
    e.add_argument("--out", type=Path, required=True)
    e.add_argument("--k", type=int, default=18, help="clusters; 18 = 6 pieces x 2 colours x (light/dark square) merged where equal")
    lb = sub.add_parser("label")
    lb.add_argument("--out", type=Path, required=True)
    lb.add_argument("--rows", required=True, help='symbols of clusters.png rows, top to bottom, e.g. "p P p P n K ..."')
    a = ap.parse_args()
    if a.cmd == "extract":
        extract(a.pages, a.model, a.out, a.k)
    else:
        label(a.out, a.rows.split())


if __name__ == "__main__":
    main()
