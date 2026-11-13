"""Held-out evaluation on freshly rendered full-page diagrams (locator in the loop)."""
from __future__ import annotations

import collections
import json
import random
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

from .fen import grid_to_placement
from .pipeline import recognize, recognize_page
from .synth import build_sprite_sets, random_grid, render_board


def evaluate(predictor, n_boards: int, seed: int, families: set[str] | None = None, verbose: bool = False) -> dict:
    rng = random.Random(seed)
    sets = [s for s in build_sprite_sets() if families is None or s.family in families]
    sq_ok = sq_total = exact_raw = exact = loc_ok = 0
    worst = []
    for _ in range(n_boards):
        grid = random_grid(rng)
        img, gt_box, sset = render_board(grid, sets, rng)
        rec = recognize(img, predictor)
        cw, ch = (gt_box[2] - gt_box[0]) / 8, (gt_box[3] - gt_box[1]) / 8
        # box counts as located if each edge is within 0.2 of a cell of the truth
        err = np.abs(np.array(rec.box) - np.array(gt_box)) / np.array([cw, ch, cw, ch])
        loc_ok += int(err.max() <= 0.2)
        sq_ok += int(sum(a == b for a, b in zip(rec.grid, grid)))
        sq_total += 64
        exact_raw += int(rec.raw_argmax == grid)
        exact += int(rec.grid == grid)
        if rec.grid != grid:
            worst.append((sset.name, grid_to_placement(grid), rec.placement))
    out = {
        "boards": n_boards,
        "locator_hit": loc_ok / n_boards,
        "square_acc": sq_ok / sq_total,
        "board_exact_raw_argmax": exact_raw / n_boards,
        "board_exact_with_rules": exact / n_boards,
    }
    if verbose:
        out["failures"] = worst[:5]
    return out


def evaluate_pages(predictor, pages_dir: Path, labels_path: Path, pages: set[str] | None = None,
                   scales=(1.0, 0.7, 0.5, 1.4)) -> dict:
    """Exact-board accuracy on real screenshots, re-rendered at several phone zoom levels.

    labels.json (written by chessdiag.book label) lists the boards of each page in reading order.
    Boards are matched by content, so a board the detector drops is a miss and never shifts the others.
    """
    labels = json.loads(Path(labels_path).read_text())
    by_page = collections.defaultdict(list)
    for k in sorted(labels, key=int):
        by_page[labels[k]["page"]].append(labels[k]["placement"])
    files = {f.stem: f for f in list(Path(pages_dir).glob("*.jp*g")) + list(Path(pages_dir).glob("*.png"))}
    report = {}
    for scale in scales:
        total = exact = found = 0
        for page, truth in by_page.items():
            if pages and page not in pages:
                continue
            img = np.array(Image.open(files[page]).convert("RGB"))
            if scale != 1.0:
                interp = cv2.INTER_AREA if scale < 1 else cv2.INTER_CUBIC
                img = cv2.resize(img, None, fx=scale, fy=scale, interpolation=interp)
                img = cv2.imdecode(cv2.imencode(".jpg", img[..., ::-1], [cv2.IMWRITE_JPEG_QUALITY, 85])[1], cv2.IMREAD_COLOR)[..., ::-1]
            recs = recognize_page(img, predictor)
            total += len(truth)
            found += len(recs)
            remaining = list(truth)  # a board counts when its content equals a still-unclaimed true position
            for r in recs:
                if r.placement in remaining:
                    remaining.remove(r.placement)
                    exact += 1
        report[f"x{scale}"] = f"{exact}/{total} boards exactly right, {found} detected"
    return report
