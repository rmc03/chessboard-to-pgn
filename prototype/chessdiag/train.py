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
    a = ap.parse_args()
    out = Path(a.out)
    tf_fams = _fam(a.train_families)

    t = time.time()
    X, y = make_dataset(a.boards, seed=1, families=tf_fams)
    Xv, yv = make_dataset(a.val_boards, seed=2, families=tf_fams)
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

    test_fams = _fam(a.test_families) or tf_fams
    for name, fams in (("held-out boards", test_fams),):
        print(name, evaluate(tfl, a.eval_boards, seed=99, families=fams, verbose=True))


if __name__ == "__main__":
    main()
