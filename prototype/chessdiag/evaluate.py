"""Held-out evaluation on freshly rendered full-page diagrams (locator in the loop)."""
from __future__ import annotations

import random

import numpy as np

from .fen import grid_to_placement
from .pipeline import recognize
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
