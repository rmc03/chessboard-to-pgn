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
