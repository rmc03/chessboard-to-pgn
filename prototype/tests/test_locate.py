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
