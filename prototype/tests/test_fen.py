import numpy as np

from chessdiag import CLASSES
from chessdiag.fen import (decode, grid_to_placement, guess_castling, placement_to_grid,
                           suggest_turn, to_fen, to_pgn, validate)

SAMPLE = "4r1k1/1p3ppp/1qn5/3p4/Q3n3/1NP5/PP3PPP/R4BK1"  # diagram supplied with the project


def onehot(grid, p=0.95):
    probs = np.full((64, len(CLASSES)), (1 - p) / (len(CLASSES) - 1))
    probs[np.arange(64), grid] = p
    return probs


def test_placement_roundtrip():
    assert grid_to_placement(placement_to_grid(SAMPLE)) == SAMPLE
    assert grid_to_placement([0] * 64) == "8/8/8/8/8/8/8/8"


def test_decode_clean_board_is_identity():
    grid = placement_to_grid(SAMPLE)
    out, conf = decode(onehot(grid))
    assert out == grid and conf.min() > 0.9


def test_decode_adds_missing_king_on_most_likely_square():
    grid = placement_to_grid(SAMPLE)
    k = CLASSES.index("k")
    black_king_sq = grid.index(k)
    probs = onehot(grid)
    probs[black_king_sq] = onehot([CLASSES.index("n")] * 64)[0]  # model says knight...
    probs[black_king_sq, k] = 0.30  # ...but king is its second choice
    probs[black_king_sq, CLASSES.index("n")] = 0.60
    out, _ = decode(probs)
    assert out[black_king_sq] == k


def test_decode_keeps_single_king_per_colour_and_no_back_rank_pawns():
    grid = [0] * 64
    K, k, P = CLASSES.index("K"), CLASSES.index("k"), CLASSES.index("P")
    grid[60], grid[4] = K, k
    probs = onehot(grid)
    probs[10] = onehot([K] * 64)[0]  # a second "white king"
    probs[2] = onehot([P] * 64)[0]  # a pawn on rank 8
    out, _ = decode(probs)
    assert out.count(K) == 1 and out.count(k) == 1
    assert out[2] not in (P, CLASSES.index("p"))


def test_castling_guess_and_turn():
    assert guess_castling("r3k2r/8/8/8/8/8/8/R3K2R") == "KQkq"
    assert guess_castling(SAMPLE) == "-"
    assert suggest_turn("4k3/8/8/8/8/8/8/4K2r") == "w"  # white king attacked -> white to move
    assert suggest_turn(SAMPLE) is None  # nobody in check: a picture cannot tell


def test_pgn_is_position_only_with_setup_and_fen():
    fen = to_fen(SAMPLE, "b")
    assert fen == SAMPLE + " b - - 0 1"
    pgn = to_pgn(fen)
    assert '[SetUp "1"]' in pgn and f'[FEN "{fen}"]' in pgn
    assert pgn.strip().endswith("*") and "1." not in pgn


def test_validate_reports_illegal_positions():
    assert validate(to_fen(SAMPLE, "w")) == []
    assert "no black king" in validate("8/8/8/8/8/8/8/4K3 w - - 0 1")
