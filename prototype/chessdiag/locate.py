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


def _inner_lines_score(profile: np.ndarray, a: float, b: float) -> float:
    """How grid-like [a, b] is: edge energy on its 7 inner lines against that halfway between lines.

    Only positions inside the image count, so the board edges may lie outside it (a crop that cut into the
    edge squares). Weak lines against strong midpoints (25th vs 75th percentile): EVERY line of a true grid
    is an edge, while a wrong grid that only catches a frame or every other true line (a harmonic) has
    several quiet lines.
    """
    c = (b - a) / 8
    xs = np.arange(len(profile))
    lines = a + c * np.arange(1, 8)
    mids = a + c * (np.arange(8) + 0.5)
    lines = lines[(lines >= 0) & (lines <= len(profile) - 1)]
    mids = mids[(mids >= 0) & (mids <= len(profile) - 1)]
    if not len(lines) or not len(mids):
        return -1e9
    return float(np.percentile(np.interp(lines, xs, profile), 25) - np.percentile(np.interp(mids, xs, profile), 75))


def _snap_inset(profile: np.ndarray, a: float, b: float) -> tuple[float, float]:
    """Grid inside the coarse box [a, b] that may be inset from it (thick frame, frame around margins)."""
    n, c0 = len(profile), (b - a) / 8
    if c0 < 3:
        return a, b
    best_score, best = -1e9, (a, b)
    for s in np.linspace(0.75 * c0, 1.07 * c0, 33):
        for x0 in np.arange(a - 0.3 * c0, a + 0.75 * c0 + 1e-6, 0.5):
            if x0 + 8 * s > b + 0.3 * c0:
                continue
            score = _inner_lines_score(profile, x0, x0 + 8 * s)
            if score > best_score:
                best_score, best = score, (float(x0), float(x0 + 8 * s))
    return best


def _snap_tight(profile: np.ndarray) -> tuple[float, float]:
    """Grid for an image cropped ON or slightly INSIDE the board: 8 cells spanning about the whole axis.

    The outer lines may fall just outside the image (a crop that cut into the edge squares), so the fit is
    scored on the 7 inner lines only; cut_squares replicates the border for the missing sliver.
    """
    n = len(profile)
    c0 = n / 8
    best_score, best = -1.0, (0.0, float(n))
    for s in np.linspace(0.9 * c0, 1.1 * c0, 21):
        for x0 in np.arange(-0.35 * c0, 0.35 * c0 + 1e-6, 0.25):
            if x0 + 8 * s < n - 0.35 * c0 or x0 + 8 * s > n + 0.35 * c0:
                continue
            score = _inner_lines_score(profile, x0, x0 + 8 * s)
            if score > best_score:
                best_score, best = score, (float(x0), float(x0 + 8 * s))
    return best


def find_board(img: np.ndarray, snap: bool = True) -> Box:
    """Return the board box. Falls back to the whole image if nothing board-like is found.

    Two hypotheses are compared on the grid-line energy of the whole image: the board found inside a plain
    page margin, and a board that fills the image (a crop made on, or slightly inside, the board's edge).
    """
    gray = cv2.GaussianBlur(to_gray(img), (0, 0), 0.7)
    h, w = gray.shape
    full = (0.0, 0.0, float(w), float(h))
    if snap:
        sobx = np.abs(cv2.Sobel(gray, cv2.CV_32F, 1, 0, ksize=3))
        soby = np.abs(cv2.Sobel(gray, cv2.CV_32F, 0, 1, ksize=3))
        fx = cv2.GaussianBlur(sobx.sum(axis=0)[None], (0, 0), 0.8)[0]
        fy = cv2.GaussianBlur(soby.sum(axis=1)[None], (0, 0), 0.8)[0]
        tx0, tx1 = _snap_tight(fx)
        ty0, ty1 = _snap_tight(fy)
        tight = (tx0, ty0, tx1, ty1)
    bg = _page_background(gray)
    if bg is None:  # edges are not a plain page: image is already cropped to the board
        return tight if snap else full
    level, noise = bg
    ink = (np.abs(gray - level) > max(9.0, 4 * noise)).astype(np.float32)

    x0, x1, y0, y1 = 0, w, 0, h
    for _ in range(2):  # columns restricted to the row band and vice versa
        col = ink[y0:y1].mean(axis=0)
        x0, x1 = _longest_run(col, 0.25 * col.max(), max_gap=max(2, w // 50))
        row = ink[:, x0:x1].mean(axis=1)
        y0, y1 = _longest_run(row, 0.25 * row.max(), max_gap=max(2, h // 50))
        if x1 - x0 < 16 or y1 - y0 < 16:
            return tight if snap else full
    if not snap:
        return (float(x0), float(y0), float(x1), float(y1))

    gx = cv2.GaussianBlur(sobx[y0:y1].sum(axis=0)[None], (0, 0), 0.8)[0]
    gy = cv2.GaussianBlur(soby[:, x0:x1].sum(axis=1)[None], (0, 0), 0.8)[0]
    # candidates per axis: grid on the coarse box (thin frame or none), grid inset in it (thick frame, or a
    # frame around margins/coordinates), grid filling the image (crop on the board's edge, whose white edge
    # squares can pass for a page margin). The most grid-like one wins.
    sx0, sx1 = max((_snap_axis(gx, x0, x1), _snap_inset(gx, x0, x1), (tx0, tx1)),
                   key=lambda c: _inner_lines_score(fx, *c))
    sy0, sy1 = max((_snap_axis(gy, y0, y1), _snap_inset(gy, y0, y1), (ty0, ty1)),
                   key=lambda c: _inner_lines_score(fy, *c))
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


def _inside(a: Box, b: Box) -> bool:
    """a lies within b (2 % tolerance)."""
    t = 0.02 * (b[2] - b[0])
    return a != b and a[0] >= b[0] - t and a[1] >= b[1] - t and a[2] <= b[2] + t and a[3] <= b[3] + t


def _board_like(gray: np.ndarray, box: Box) -> bool:
    """Do the 64 cells alternate light/dark like a chessboard?

    Each cell is judged by the mean of a ring near its border (mostly square background, rarely the piece;
    a mean, not a median, so that fine hatching counts as grey); light cells (a8 parity) must be clearly
    brighter than dark cells, consistently across the board.
    """
    x0, y0, x1, y1 = box
    cw, ch = (x1 - x0) / 8, (y1 - y0) / 8
    meds = np.empty(64)
    for r in range(8):
        for f in range(8):
            cx, cy = x0 + f * cw, y0 + r * ch
            a = [min(max(int(cy + t * ch), 0), gray.shape[0]) for t in (0.08, 0.25, 0.75, 0.92)]
            b = [min(max(int(cx + t * cw), 0), gray.shape[1]) for t in (0.08, 0.25, 0.75, 0.92)]
            ring = np.concatenate([
                gray[a[0]:a[1], b[0]:b[3]].ravel(), gray[a[2]:a[3], b[0]:b[3]].ravel(),
                gray[a[1]:a[2], b[0]:b[1]].ravel(), gray[a[1]:a[2], b[2]:b[3]].ravel()])
            meds[r * 8 + f] = ring.mean() if ring.size else 0.0
    light = meds[[i for i in range(64) if (i // 8 + i % 8) % 2 == 0]]
    dark = meds[[i for i in range(64) if (i // 8 + i % 8) % 2 == 1]]
    lm, dm = float(np.median(light)), float(np.median(dark))
    mid = (lm + dm) / 2
    consistent = (np.sum(light > mid) + np.sum(dark < mid)) / 64
    return lm - dm >= 6 and consistent >= 0.7


def _is_board(img: np.ndarray, gray: np.ndarray, box: Box) -> bool:
    """The framed box is an 8x8 board, or holds one (a frame may also enclose margins and coordinates)."""
    if _board_like(gray, box):
        return True
    x0, y0, x1, y1 = box
    pad = int(0.04 * (x1 - x0))
    ox, oy = max(0, int(x0) - pad), max(0, int(y0) - pad)
    crop = img[oy:int(y1) + pad, ox:int(x1) + pad]
    inner = find_board(crop)
    if min(inner[2] - inner[0], inner[3] - inner[1]) < 0.5 * min(x1 - x0, y1 - y0):
        return False
    return _board_like(to_gray(crop), inner)


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
        box = (float(x), float(y), float(x + bw), float(y + bh))
        if _is_board(img, gray, box):  # a hatched square or a block of text is not an 8x8 board
            found.append(box)
    found = [b for b in found if not any(o is not b and _inside(b, o) for o in found)]
    # reading order: group by row (similar top edge), then left to right
    found.sort(key=lambda b: b[1])
    rows: list[list[Box]] = []
    for b in found:
        if rows and abs(b[1] - rows[-1][0][1]) < 0.5 * (b[3] - b[1]):
            rows[-1].append(b)
        else:
            rows.append([b])
    ordered = [b for row in rows for b in sorted(row)]
    if len(ordered) >= 4:  # one typeface/layout per page: a box far from the median size is a damaged frame
        median = float(np.median([b[2] - b[0] for b in ordered]))
        ordered = [b for b in ordered if abs((b[2] - b[0]) - median) <= 0.08 * median and abs((b[3] - b[1]) - median) <= 0.08 * median]
    return ordered
