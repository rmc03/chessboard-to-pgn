"""Cut a board box into 64 normalised square images for the classifier."""
from __future__ import annotations

import cv2
import numpy as np

from .locate import Box, to_gray

SQUARE = 32  # model input is SQUARE x SQUARE grayscale in [0, 1]


def cut_squares(img: np.ndarray, box: Box, size: int = SQUARE) -> np.ndarray:
    """(64, size, size) float32, rank 8 first, file a first. Fractional boxes are fine."""
    gray = to_gray(img)
    x0, y0, x1, y1 = box
    sx, sy = 8 * size / (x1 - x0), 8 * size / (y1 - y0)
    if sx < 1 or sy < 1:  # strong downscale: low-pass first so thin glyph strokes survive
        sigma = 0.5 / min(sx, sy)
        gray = cv2.GaussianBlur(gray, (0, 0), sigma)
    m = np.array([[sx, 0, -x0 * sx], [0, sy, -y0 * sy]], dtype=np.float32)
    board = cv2.warpAffine(
        gray, m, (8 * size, 8 * size), flags=cv2.INTER_LINEAR, borderMode=cv2.BORDER_REPLICATE
    )
    cells = board.reshape(8, size, 8, size).swapaxes(1, 2).reshape(64, size, size)
    return np.clip(cells / 255.0, 0.0, 1.0).astype(np.float32)
