"""python -m chessdiag.train --boards 3000 --epochs 10 --out runs/v1 [--train-families a,b --test-families c]"""
from __future__ import annotations

import argparse
import time
from pathlib import Path

import numpy as np

from .evaluate import evaluate
from .model import export_tflite, predict_keras, predict_tflite, train
from .synth import make_dataset


def _fam(s: str | None):
    return set(s.split(",")) if s else None


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--boards", type=int, default=3000)
    ap.add_argument("--val-boards", type=int, default=300)
    ap.add_argument("--epochs", type=int, default=10)
    ap.add_argument("--out", default="runs/latest")
    ap.add_argument("--train-families", help="comma list of cburnett,dejavu,freefont,unifont (default all)")
    ap.add_argument("--test-families", help="families for the held-out evaluation (default = train families)")
    ap.add_argument("--eval-boards", type=int, default=300)
    ap.add_argument("--book", help="book_cells.npz from `python -m chessdiag.book label`")
    ap.add_argument("--book-pages", help="comma list of page names whose cells may be used (default all)")
    ap.add_argument("--book-fraction", type=float, default=0.5, help="share of training boards built from the book's cells")
    ap.add_argument("--eval-pages", help="comma list of real pages (in data dir of --book) to evaluate on at several zooms")
    a = ap.parse_args()
    out = Path(a.out)
    tf_fams = _fam(a.train_families)

    book = None
    if a.book:
        from .book import BookPool

        pool = BookPool.load(a.book, _fam(a.book_pages))
        book = (pool, a.book_fraction)
        print(f"book pool: {len(pool.cells)} real cells from pages {a.book_pages or 'all'}", flush=True)
    t = time.time()
    X, y = make_dataset(a.boards, seed=1, families=tf_fams, book=book)
    Xv, yv = make_dataset(a.val_boards, seed=2, families=tf_fams, book=book)
    print(f"data: {len(X)} train squares, {len(Xv)} val squares in {time.time() - t:.0f}s", flush=True)
    t = time.time()
    model = train(X, y, Xv, yv, a.epochs)
    print(f"trained in {time.time() - t:.0f}s", flush=True)

    path = export_tflite(model, out)
    print(f"exported {path} ({path.stat().st_size / 1024:.0f} KiB)")
    tfl = predict_tflite(path)
    k = predict_keras(model)
    sample = Xv[: 64 * 20].astype(np.float32) / 255.0
    agree = float((tfl(sample).argmax(1) == k(sample).argmax(1)).mean())
    print(f"TFLite vs Keras argmax agreement: {agree:.4f}")

    if a.book and a.eval_pages:
        from .evaluate import evaluate_pages

        d = Path(a.book).parent
        print("real pages", a.eval_pages, evaluate_pages(tfl, d / "pages", d / "labels.json", _fam(a.eval_pages)), flush=True)

    test_fams = _fam(a.test_families) or tf_fams
    for name, fams in (("held-out boards", test_fams),):
        print(name, evaluate(tfl, a.eval_boards, seed=99, families=fams, verbose=True))


if __name__ == "__main__":
    main()
