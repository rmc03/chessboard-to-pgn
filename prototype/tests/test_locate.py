import random

import numpy as np

from chessdiag.locate import find_board
from chessdiag.squares import cut_squares
from chessdiag.synth import build_sprite_sets, random_grid, render_board


def test_locator_finds_synthetic_boards_within_a_fifth_of_a_cell():
    rng, sets, hits, n = random.Random(11), build_sprite_sets(), 0, 60
    for _ in range(n):
        img, gt, _ = render_board(random_grid(rng), sets, rng)
        cw, ch = (gt[2] - gt[0]) / 8, (gt[3] - gt[1]) / 8
        err = np.abs(np.array(find_board(img)) - np.array(gt)) / np.array([cw, ch, cw, ch])
        hits += int(err.max() <= 0.2)
    assert hits / n >= 0.9


def test_cut_squares_shape_range_and_order():
    img = np.zeros((80, 80, 3), np.uint8)
    img[:10, :10] = 255  # top-left square (a8) is white
    cells = cut_squares(img, (0, 0, 80, 80), size=32)
    assert cells.shape == (64, 32, 32) and cells.dtype == np.float32
    inner = np.s_[6:-6, 6:-6]  # bilinear up-scaling softens square edges; judge the interiors
    assert cells[0][inner].mean() > 0.99  # a8 first: rank 8 first, file a first
    assert all(cells[i][inner].max() < 0.01 for i in range(1, 64))


def _crop(img, box, inset):
    """Crop on the board's box moved `inset` of the board width inwards (negative = margin)."""
    x0, y0, x1, y1 = box
    d = inset * (x1 - x0)
    cx0, cy0 = max(0, int(round(x0 + d))), max(0, int(round(y0 + d)))
    cx1, cy1 = int(round(x1 - d)), int(round(y1 - d))
    return img[cy0:cy1, cx0:cx1], (x0 - cx0, y0 - cy0, x1 - cx0, y1 - cy0)


def test_crops_on_or_inside_the_board_edge_keep_the_grid():
    """A user crop may cut into the edge squares: the grid must still be found (cut_squares pads the rest)."""
    rng, sets, hits, n = random.Random(12), build_sprite_sets(), 0, 40
    for i in range(n):
        img, gt, _ = render_board(random_grid(rng), sets, rng)
        if gt[2] - gt[0] < 120:  # tiny boards: a 2 % cut is under 3 px, nothing to test
            img = np.repeat(np.repeat(img, 3, 0), 3, 1)
            gt = tuple(3 * v for v in gt)
        crop, truth = _crop(img, gt, 0.02 if i % 2 else 0.0)
        cw = (truth[2] - truth[0]) / 8
        err = np.abs(np.array(find_board(crop)) - np.array(truth)) / cw
        hits += int(err.max() <= 0.2)
    assert hits / n >= 0.85


def test_no_false_boards_inside_a_tight_crop():
    """Hatched squares or groups of squares inside a cropped board are not boards of their own."""
    from chessdiag.locate import find_boards

    rng, sets = random.Random(13), build_sprite_sets()
    for _ in range(15):
        img, gt, _ = render_board(random_grid(rng), sets, rng)
        img = np.repeat(np.repeat(img, 3, 0), 3, 1)  # board side ~100-600 px, like a real crop
        crop, _ = _crop(img, tuple(3 * v for v in gt), 0.02)
        assert len(find_boards(crop)) <= 1
