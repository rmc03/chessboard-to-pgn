"""Integration: the committed TFLite model + locator + rules on freshly rendered diagrams."""
import random
from pathlib import Path

import pytest

MODEL = Path(__file__).resolve().parents[2] / "models" / "squares.tflite"
pytestmark = pytest.mark.skipif(not MODEL.exists(), reason="models/squares.tflite not present")


def test_committed_model_reads_synthetic_diagrams():
    from chessdiag.model import predict_tflite
    from chessdiag.pipeline import recognize
    from chessdiag.synth import build_sprite_sets, random_grid, render_board

    predict = predict_tflite(MODEL)
    rng, sets = random.Random(2024), build_sprite_sets()
    right = total = 0
    for _ in range(20):
        grid = random_grid(rng)
        img, box, _ = render_board(grid, sets, rng)
        rec = recognize(img, predict, box=box)  # ground-truth box: isolates the classifier
        right += sum(a == b for a, b in zip(rec.grid, grid))
        total += 64
    assert right / total > 0.97
