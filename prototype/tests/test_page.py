import random

import cv2
import numpy as np

from chessdiag.book import CELL, BookPool, render_book_board
from chessdiag.locate import find_board, find_boards
from chessdiag.synth import random_grid


def _board(size=400):
    """A framed checkerboard with stippled dark squares, like a printed diagram."""
    c = size // 8
    img = np.full((size, size), 255, np.uint8)
    for r in range(8):
        for f in range(8):
            if (r + f) % 2:
                img[r * c:(r + 1) * c, f * c:(f + 1) * c] = 170
                img[r * c:(r + 1) * c:3, f * c:(f + 1) * c:3] = 90
    cv2.rectangle(img, (0, 0), (size - 1, size - 1), 0, 2)
    return img


def _page(width=1080, height=1700):
    page = np.full((height, width, 3), 255, np.uint8)
    page[:90] = 0  # status bar
    cv2.rectangle(page, (30, 1500), (260, 1580), (190, 80, 80), -1)  # coloured page counter overlay
    cv2.rectangle(page, (width - 40, 300), (width - 30, 520), (200, 200, 200), -1)  # scrollbar
    page[200:210] = 0  # full-width rule
    spots = [(100, 300), (580, 300), (100, 850)]
    for x, y in spots:
        page[y:y + 400, x:x + 400] = _board()[..., None]
        cv2.putText(page, "25", (x + 150, y + 450), cv2.FONT_HERSHEY_SIMPLEX, 1.6, (0, 0, 0), 5)  # caption
    return page, spots


def test_find_boards_ignores_ui_and_captions_and_keeps_reading_order():
    page, spots = _page()
    boxes = find_boards(page)
    assert len(boxes) == len(spots)
    for (x, y), b in zip(spots, boxes):
        assert max(abs(b[0] - x), abs(b[1] - y), abs(b[2] - (x + 400)), abs(b[3] - (y + 400))) <= 6


def test_find_boards_survives_zoom_out():
    page, spots = _page()
    small = cv2.resize(page, None, fx=0.75, fy=0.75, interpolation=cv2.INTER_AREA)
    assert len(find_boards(small)) == len(spots)


def test_find_boards_returns_nothing_without_frames():
    assert find_boards(np.full((800, 600, 3), 255, np.uint8)) == []


def test_find_board_still_works_on_a_cropped_diagram():
    box = find_board(np.stack([_board()] * 3, -1))
    assert max(abs(v - e) for v, e in zip(box, (0, 0, 400, 400))) <= 6


def test_book_pool_composes_boards_from_real_cells():
    rng = random.Random(0)
    cells = np.stack([np.full((CELL, CELL), 40 + 5 * i, np.uint8) for i in range(26)])
    cls = np.array([0] * 2 + [k for k in range(1, 13) for _ in range(2)], np.int8)
    parity = np.array([0, 1] * 13, np.int8)
    pool = BookPool(cells, cls, parity)
    img, box = render_book_board(random_grid(rng), pool, rng)
    h, w = img.shape[:2]
    assert img.shape[2] == 3 and 0 <= box[0] < box[2] <= w and 0 <= box[1] < box[3] <= h
    assert abs((box[2] - box[0]) - (box[3] - box[1])) < 1e-6
