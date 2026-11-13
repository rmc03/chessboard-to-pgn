"""Image -> board placement. The mobile app mirrors exactly these steps."""
from __future__ import annotations

from dataclasses import dataclass
from typing import Callable

import numpy as np

from .fen import decode, grid_to_placement
from .locate import Box, find_board
from .squares import cut_squares


@dataclass
class Recognition:
    box: Box
    grid: list[int]
    placement: str
    confidence: np.ndarray  # (64,) per-square probability of the chosen class
    raw_argmax: list[int]  # before applying chess rules (for diagnostics)


def recognize(img: np.ndarray, predictor: Callable[[np.ndarray], np.ndarray], box: Box | None = None) -> Recognition:
    box = box or find_board(img)
    probs = predictor(cut_squares(img, box))
    grid, conf = decode(probs)
    return Recognition(box, grid, grid_to_placement(grid), conf, [int(k) for k in probs.argmax(1)])


def recognize_page(img: np.ndarray, predictor: Callable[[np.ndarray], np.ndarray]) -> list[Recognition]:
    """Every complete framed diagram on a page/screenshot, in reading order."""
    from .locate import find_boards

    results = []
    for x0, y0, x1, y1 in find_boards(img):
        pad = int(0.04 * (x1 - x0))
        ox, oy = max(0, int(x0) - pad), max(0, int(y0) - pad)
        crop = img[oy:int(y1) + pad, ox:int(x1) + pad]
        rec = recognize(crop, predictor)
        bx0, by0, bx1, by1 = rec.box
        rec.box = (bx0 + ox, by0 + oy, bx1 + ox, by1 + oy)  # back to page coordinates
        results.append(rec)
    return results
