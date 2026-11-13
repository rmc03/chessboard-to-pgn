"""FEN/PGN helpers and rule-constrained decoding of per-square probabilities.

Grid convention everywhere: 64 entries, index = row * 8 + col, row 0 = rank 8,
col 0 = file a (i.e. the diagram seen from White's side).
Class ids follow chessdiag.CLASSES (0 = empty, 1..6 = PNBRQK, 7..12 = pnbrqk).
"""
from __future__ import annotations

import chess
import chess.pgn
import numpy as np

from . import CLASSES

IDX = {s: i for i, s in enumerate(CLASSES) if s}
_BACK_RANK_SQUARES = list(range(0, 8)) + list(range(56, 64))


def grid_to_placement(grid) -> str:
    rows = []
    for r in range(8):
        out, empty = "", 0
        for c in range(8):
            sym = CLASSES[int(grid[r * 8 + c])]
            if sym is None:
                empty += 1
            else:
                if empty:
                    out += str(empty)
                    empty = 0
                out += sym
        rows.append(out + (str(empty) if empty else ""))
    return "/".join(rows)


def placement_to_grid(placement: str) -> list[int]:
    grid: list[int] = []
    for row in placement.split(" ")[0].split("/"):
        for ch in row:
            if ch.isdigit():
                grid.extend([0] * int(ch))
            else:
                grid.append(IDX[ch])
    if len(grid) != 64:
        raise ValueError(f"placement does not describe 64 squares: {placement!r}")
    return grid


def decode(probs: np.ndarray, eps: float = 1e-6) -> tuple[list[int], np.ndarray]:
    """Most likely board that also obeys hard chess rules.

    probs: (64, 13) class probabilities. Rules enforced: no pawns on ranks 1/8,
    exactly one king per colour, at most 8 pawns per colour. Returns (grid, confidence)
    where confidence is the probability the model gave to the chosen class per square.
    """
    lp = np.log(np.clip(np.asarray(probs, dtype=np.float64), eps, 1.0))
    for pawn in (IDX["P"], IDX["p"]):
        lp[_BACK_RANK_SQUARES, pawn] = -np.inf
    grid = lp.argmax(1)

    def reassign(sq: int, forbidden: int) -> None:
        alt = lp[sq].copy()
        alt[forbidden] = -np.inf
        grid[sq] = alt.argmax()

    for _ in range(2):  # a repair can create a violation for the other king
        for king in (IDX["K"], IDX["k"]):
            squares = np.flatnonzero(grid == king)
            if len(squares) > 1:
                keep = squares[np.argmax(lp[squares, king])]
                for sq in squares:
                    if sq != keep:
                        reassign(int(sq), king)
            elif len(squares) == 0:
                cost = lp[:, king] - lp[np.arange(64), grid]  # cheapest square to flip
                grid[int(np.argmax(cost))] = king
        for pawn in (IDX["P"], IDX["p"]):
            squares = np.flatnonzero(grid == pawn)
            if len(squares) > 8:
                order = squares[np.argsort(lp[squares, pawn])]  # weakest first
                for sq in order[: len(squares) - 8]:
                    reassign(int(sq), pawn)
    conf = np.asarray(probs)[np.arange(64), grid]
    return [int(g) for g in grid], conf


def guess_castling(placement: str) -> str:
    """Castling rights that are *possible* given king/rook placement (the user confirms)."""
    b = chess.Board(placement.split(" ")[0] + " w - - 0 1")
    P = b.piece_at
    rights = ""
    if P(chess.E1) == chess.Piece.from_symbol("K"):
        rights += "K" if P(chess.H1) == chess.Piece.from_symbol("R") else ""
        rights += "Q" if P(chess.A1) == chess.Piece.from_symbol("R") else ""
    if P(chess.E8) == chess.Piece.from_symbol("k"):
        rights += "k" if P(chess.H8) == chess.Piece.from_symbol("r") else ""
        rights += "q" if P(chess.A8) == chess.Piece.from_symbol("r") else ""
    return rights or "-"


def suggest_turn(placement: str) -> str | None:
    """'w'/'b' if the position forces the side to move (the other side cannot be in check)."""
    b = chess.Board(placement.split(" ")[0] + " w - - 0 1")
    white_in_check = b.is_check()
    b.turn = chess.BLACK
    black_in_check = b.is_check()
    if white_in_check and not black_in_check:
        return "w"
    if black_in_check and not white_in_check:
        return "b"
    return None


_STATUS_TEXT = {
    chess.STATUS_NO_WHITE_KING: "no white king",
    chess.STATUS_NO_BLACK_KING: "no black king",
    chess.STATUS_TOO_MANY_KINGS: "more than one king of a colour",
    chess.STATUS_TOO_MANY_WHITE_PAWNS: "more than 8 white pawns",
    chess.STATUS_TOO_MANY_BLACK_PAWNS: "more than 8 black pawns",
    chess.STATUS_PAWNS_ON_BACKRANK: "pawn on rank 1 or 8",
    chess.STATUS_TOO_MANY_WHITE_PIECES: "more than 16 white pieces",
    chess.STATUS_TOO_MANY_BLACK_PIECES: "more than 16 black pieces",
    chess.STATUS_OPPOSITE_CHECK: "side not to move is in check",
    chess.STATUS_EMPTY: "empty board",
    chess.STATUS_BAD_CASTLING_RIGHTS: "castling rights do not match the pieces",
    chess.STATUS_INVALID_EP_SQUARE: "invalid en-passant square",
    chess.STATUS_RACE_CHECK: "impossible check configuration",
    chess.STATUS_RACE_OVER: "impossible check configuration",
    chess.STATUS_RACE_MATERIAL: "impossible check configuration",
    chess.STATUS_IMPOSSIBLE_CHECK: "impossible check configuration",
}


def validate(fen: str) -> list[str]:
    """Human-readable problems with a full FEN (empty list = legal-looking position)."""
    status = chess.Board(fen).status()
    return sorted({t for flag, t in _STATUS_TEXT.items() if status & flag})


def to_fen(placement: str, turn: str = "w", castling: str | None = None, ep: str = "-") -> str:
    placement = placement.split(" ")[0]
    castling = guess_castling(placement) if castling is None else (castling or "-")
    return f"{placement} {turn} {castling} {ep} 0 1"


def to_pgn(fen: str, headers: dict[str, str] | None = None) -> str:
    """Position-only PGN: tag pairs with SetUp/FEN and the unknown-result marker '*'."""
    game = chess.pgn.Game()
    game.headers["Event"] = "Diagram"
    for k, v in (headers or {}).items():
        game.headers[k] = v
    game.setup(chess.Board(fen))
    return str(game) + "\n"
