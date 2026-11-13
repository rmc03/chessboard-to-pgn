"""python -m chessdiag.cli image.png --model squares.tflite [--turn w] [--crop x0,y0,x1,y1] [--page]

--page: the image is a page/screenshot with several framed diagrams; every complete one becomes a game
in a single PGN file (Event "Diagram N", N = reading order on the page)."""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image

from .fen import guess_castling, suggest_turn, to_fen, to_pgn, validate
from .model import predict_tflite
from .pipeline import recognize, recognize_page


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("image")
    ap.add_argument("--model", required=True, help="squares.tflite")
    ap.add_argument("--turn", choices=["w", "b"], help="side to move (a picture cannot tell; default: inferred or w)")
    ap.add_argument("--castling", help="e.g. KQkq or - (default: every right the placement allows)")
    ap.add_argument("--crop", help="board box x0,y0,x1,y1 in pixels (default: auto-detect)")
    ap.add_argument("--out", help="write the position-only PGN here")
    ap.add_argument("--page", action="store_true", help="screenshot/page with several diagrams")
    a = ap.parse_args()

    img = np.array(Image.open(a.image).convert("RGB"))
    if a.page:
        _page(img, a)
        return
    box = tuple(float(v) for v in a.crop.split(",")) if a.crop else None
    rec = recognize(img, predict_tflite(Path(a.model)), box)
    turn = a.turn or suggest_turn(rec.placement) or "w"
    fen = to_fen(rec.placement, turn, a.castling)
    print("board box :", tuple(round(v, 1) for v in rec.box))
    print("FEN       :", fen)
    weak = [f"{'abcdefgh'[i % 8]}{8 - i // 8}({c:.2f})" for i, c in enumerate(rec.confidence) if c < 0.9]
    print("low confidence squares:", ", ".join(weak) or "none")
    changed = [f"{'abcdefgh'[i % 8]}{8 - i // 8}" for i, (x, y) in enumerate(zip(rec.raw_argmax, rec.grid)) if x != y]
    print("changed by chess rules:", ", ".join(changed) or "none")
    for problem in validate(fen):
        print("WARNING:", problem)
    if a.out:
        Path(a.out).write_text(to_pgn(fen))
        print("PGN written to", a.out)
    else:
        print(to_pgn(fen))


def _page(img: np.ndarray, a: argparse.Namespace) -> None:
    games = []
    for n, rec in enumerate(recognize_page(img, predict_tflite(Path(a.model))), 1):
        turn = a.turn or suggest_turn(rec.placement) or "w"
        fen = to_fen(rec.placement, turn, a.castling)
        weak = [f"{'abcdefgh'[i % 8]}{8 - i // 8}" for i, c in enumerate(rec.confidence) if c < 0.9]
        notes = validate(fen)
        print(f"Diagram {n}: {fen}" + (f"   low confidence: {','.join(weak)}" if weak else "") + (f"   WARNING: {'; '.join(notes)}" if notes else ""))
        games.append(to_pgn(fen, {"Event": f"Diagram {n}"}))
    print(f"{len(games)} diagrams")
    if a.out:
        Path(a.out).write_text("\n".join(games))
        print("PGN written to", a.out)


if __name__ == "__main__":
    main()
