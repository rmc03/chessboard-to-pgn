"""Find the 8x8 board inside a digital diagram (margins, coordinates, captions around it).

Two steps, both classic image processing so they port 1:1 to Dart:
 1. coarse box: the board is the largest block of columns/rows with dense "ink" (pixels that
    differ from the page background; dark squares alternate along every row and column);
 2. grid snap: nudge the box so the 9 grid lines are equally spaced on the strongest
    brightness edges. This removes frames, shadows and a few pixels of coarse-box error.

Anything that does not fit (screenshots with UI, photos) must be cropped by the user: the app
shows four draggable corners and calls cut_squares() with that box instead.
"""
from __future__ import annotations

import cv2
import numpy as np

Box = tuple[float, float, float, float]  # x0, y0, x1, y1 in pixels (x1/y1 exclusive)


def to_gray(img: np.ndarray) -> np.ndarray:
    if img.ndim == 2:
        return img.astype(np.float32)
    rgb = img[..., :3].astype(np.float32)
    return rgb @ np.array([0.299, 0.587, 0.114], dtype=np.float32)


def _page_background(gray: np.ndarray) -> tuple[float, float] | None:
    """(level, noise) of the plain page around the board, or None if the image edge is not plain."""
    ring = np.concatenate([gray[0], gray[-1], gray[1:-1, 0], gray[1:-1, -1]])
    hist, edges = np.histogram(ring, bins=64, range=(0, 256))
    peak = int(np.convolve(hist, np.ones(3), "same").argmax())
    level = float((edges[peak] + edges[peak + 1]) / 2)
    near = np.abs(ring - level) < 12
    if near.mean() < 0.45:
        return None
    return level, float(ring[near].std())


def _longest_run(profile: np.ndarray, thresh: float, max_gap: int) -> tuple[int, int]:
    best, start, last_on = (0, 0), None, None
    for i, v in enumerate(profile > thresh):
        if v:
            if start is None:
                start = i
            last_on = i
        elif start is not None and i - last_on > max_gap:
            if last_on + 1 - start > best[1] - best[0]:
                best = (start, last_on + 1)
            start = None
    if start is not None and last_on + 1 - start > best[1] - best[0]:
        best = (start, last_on + 1)
    return best


def _snap_axis(profile: np.ndarray, a: float, b: float) -> tuple[float, float]:
    """Best equally-spaced 9-line grid near [a, b] on a 1-D edge-energy profile."""
    n, c0 = len(profile), (b - a) / 8
    if c0 < 3:
        return a, b
    xs, grid = np.arange(n), np.arange(9)
    best_score, best = -1.0, (a, b)
    for s in np.linspace(0.93 * c0, 1.07 * c0, 15):
        for x0 in np.arange(a - 0.3 * c0, a + 0.3 * c0 + 1e-6, 0.25):
            pos = x0 + s * grid
            if pos[0] < 0 or pos[-1] > n - 1:
                continue
            score = float(np.interp(pos, xs, profile).sum())
            if score > best_score:
                best_score, best = score, (x0, x0 + 8 * s)
    return best


def find_board(img: np.ndarray, snap: bool = True) -> Box:
    """Return the board box. Falls back to the whole image if nothing board-like is found."""
    gray = cv2.GaussianBlur(to_gray(img), (0, 0), 0.7)
    h, w = gray.shape
    full = (0.0, 0.0, float(w), float(h))
    bg = _page_background(gray)
    if bg is None:  # edges are not a plain page: image is already cropped to the board
        return full
    level, noise = bg
    ink = (np.abs(gray - level) > max(9.0, 4 * noise)).astype(np.float32)

    x0, x1, y0, y1 = 0, w, 0, h
    for _ in range(2):  # columns restricted to the row band and vice versa
        col = ink[y0:y1].mean(axis=0)
        x0, x1 = _longest_run(col, 0.25 * col.max(), max_gap=max(2, w // 50))
        row = ink[:, x0:x1].mean(axis=1)
        y0, y1 = _longest_run(row, 0.25 * row.max(), max_gap=max(2, h // 50))
        if x1 - x0 < 16 or y1 - y0 < 16:
            return full
    if not snap:
        return (float(x0), float(y0), float(x1), float(y1))

    gx = np.abs(cv2.Sobel(gray, cv2.CV_32F, 1, 0, ksize=3))[y0:y1].sum(axis=0)
    gy = np.abs(cv2.Sobel(gray, cv2.CV_32F, 0, 1, ksize=3))[:, x0:x1].sum(axis=1)
    sx0, sx1 = _snap_axis(cv2.GaussianBlur(gx[None], (0, 0), 0.8)[0], x0, x1)
    sy0, sy1 = _snap_axis(cv2.GaussianBlur(gy[None], (0, 0), 0.8)[0], y0, y1)
    return (sx0, sy0, sx1, sy1)


CANONICAL_WIDTH = 1080  # screenshots narrower than this are enlarged before looking for frames


def find_boards(img: np.ndarray, min_frac: float = 0.12, ink_delta: float = 25.0) -> list[Box]:
    """All complete, framed boards on a page/screenshot, in reading order (rows, then columns).

    Each diagram has a thin dark frame, which forms one connected component whose bounding
    box is the board. Wide bars (status bar, rules, titles), thin scrollbars, small captions
    and boards cut by the screen edge are rejected. Returns [] when no framed board exists:
    callers then fall back to find_board() on the whole image or ask for a manual crop.
    """
    scale = CANONICAL_WIDTH / img.shape[1] if img.shape[1] < 0.93 * CANONICAL_WIDTH else 1.0
    if scale != 1.0:  # zoomed-out screenshots: frame lines get thinner than the filters can see
        big = cv2.resize(img, None, fx=scale, fy=scale, interpolation=cv2.INTER_CUBIC)
        return [tuple(v / scale for v in b) for b in _find_boards(big, min_frac, ink_delta)]
    return _find_boards(img, min_frac, ink_delta)


def _find_boards(img: np.ndarray, min_frac: float, ink_delta: float) -> list[Box]:
    gray = to_gray(img)
    h, w = gray.shape
    side = min_frac * min(h, w)
    # black-hat = "darker than its surroundings": responds to a 1-2 px frame line however much
    # down-scaling has lightened it, unlike a fixed distance from the page colour
    k = max(5, int(round(0.0065 * min(h, w)))) | 1
    ink = cv2.morphologyEx(gray, cv2.MORPH_BLACKHAT, np.ones((k, k), np.uint8)) > ink_delta
    if img.ndim == 3:  # UI overlays (page counter, scrollbar) are coloured; the print is neutral
        rgb = img[..., :3].astype(np.int16)
        ink &= (rgb.max(axis=2) - rgb.min(axis=2)) < 40
    ink = ink.astype(np.uint8)
    # keep only long straight strokes (the frame); digits, captions and glyphs vanish
    run = max(15, int(0.6 * side))
    frame = cv2.morphologyEx(ink, cv2.MORPH_OPEN, np.ones((1, run), np.uint8))
    frame |= cv2.morphologyEx(ink, cv2.MORPH_OPEN, np.ones((run, 1), np.uint8))
    ink = cv2.morphologyEx(frame, cv2.MORPH_CLOSE, np.ones((7, 7), np.uint8))  # repair JPEG gaps
    n, _, stats, _ = cv2.connectedComponentsWithStats(ink, connectivity=8)
    found = []
    for x, y, bw, bh, _area in stats[1:]:
        if min(bw, bh) < side or not 0.85 <= bw / bh <= 1.18:
            continue
        if x <= 1 or y <= 1 or x + bw >= w - 1 or y + bh >= h - 1:  # cut by the screen edge
            continue
        found.append((float(x), float(y), float(x + bw), float(y + bh)))
    # reading order: group by row (similar top edge), then left to right
    found.sort(key=lambda b: b[1])
    rows: list[list[Box]] = []
    for b in found:
        if rows and abs(b[1] - rows[-1][0][1]) < 0.5 * (b[3] - b[1]):
            rows[-1].append(b)
        else:
            rows.append([b])
    return [b for row in rows for b in sorted(row)]
