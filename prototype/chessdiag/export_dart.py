"""Export what the Flutter app needs to run the classifier in pure Dart (no native plugin) and to be tested.

    python -m chessdiag.export_dart --model ../models/squares.tflite --out ../app/assets/model --fixtures ../app/test/fixtures

Why pure Dart for the first app: the network is ~9.7 M multiply-adds per square, so a plain Dart forward pass
is fast enough to try the app on Android and Windows without any native TFLite plugin (the usual source of
broken desktop/CI builds). LiteRT stays the plan for speed later; model_contract.json is unchanged.

Outputs
  weights.bin / manifest.json   layer by layer: int8 weights + float32 per-output-channel scales exactly as stored
                                in the .tflite (4x smaller than float32, bit-identical once dequantised), float32 biases
  fixtures/golden_cells.bin     64 squares (uint8 0..255, 32x32) + golden_probs.json from the real TFLite model
  fixtures/*.png + expected.json  synthetic diagram/page images and what the Python pipeline reads from them
"""
from __future__ import annotations

import argparse
import json
import random
from dataclasses import dataclass, field
from pathlib import Path

import cv2
import numpy as np
from PIL import Image

from . import CLASSES
from .squares import SQUARE


@dataclass
class Layer:
    spec: dict
    arrays: list  # float32 tensors for the numpy reference (dequantised)
    quant: list = field(default_factory=list)  # per tensor: (int8 array, float32 scales) or None


def _tensor(interp, tensors, k: int):
    """(float32 array, (int8 array, scales) | None). int8 tensors are symmetric, per output channel."""
    t, a = tensors[k], interp.get_tensor(k)
    if a.dtype != np.int8:
        return a.astype(np.float32), None
    q = t["quantization_parameters"]
    assert q["quantized_dimension"] == 0 and not np.any(q["zero_points"]), "expected symmetric per-output-channel int8"
    scales = q["scales"].astype(np.float32)
    dequantised = (a.astype(np.float32) * scales.reshape([-1] + [1] * (a.ndim - 1))).astype(np.float32)
    return dequantised, (a.copy(), scales)


def read_graph(model: Path):
    """(interpreter, [Layer]) in execution order, from the .tflite."""
    import tensorflow as tf

    interp = tf.lite.Interpreter(model_path=str(model))
    interp.allocate_tensors()
    tensors = {t["index"]: t for t in interp.get_tensor_details()}
    layers, fc_seen = [], 0
    for op in interp._get_ops_details():
        name = op["op_name"]
        if name == "CONV_2D":
            (w, qw), (b, qb) = (_tensor(interp, tensors, op["inputs"][i]) for i in (1, 2))
            layers.append(Layer({"type": "conv3x3", "out": int(w.shape[0]), "in": int(w.shape[3]), "relu": True}, [w, b], [qw, qb]))
        elif name == "MAX_POOL_2D":
            layers.append(Layer({"type": "maxpool2"}, []))
        elif name == "RESHAPE":
            layers.append(Layer({"type": "flatten"}, []))
        elif name == "FULLY_CONNECTED":
            (w, qw), (b, qb) = (_tensor(interp, tensors, op["inputs"][i]) for i in (1, 2))
            fc_seen += 1
            layers.append(Layer({"type": "dense", "out": int(w.shape[0]), "in": int(w.shape[1]), "relu": fc_seen == 1}, [w, b], [qw, qb]))
        elif name == "SOFTMAX":
            layers.append(Layer({"type": "softmax"}, []))
    return interp, layers


def reference_forward(layers, x: np.ndarray) -> np.ndarray:
    """numpy forward pass over the exported layers: x (N, 32, 32, 1) float32 -> (N, 13) probabilities."""
    for layer in layers:
        spec, arrays = layer.spec, layer.arrays
        t = spec["type"]
        if t == "conv3x3":
            w, b = arrays  # w: [out][kh][kw][in]
            n, h, wd, _ = x.shape
            pad = np.pad(x, ((0, 0), (1, 1), (1, 1), (0, 0)))
            out = np.zeros((n, h, wd, w.shape[0]), np.float32) + b
            for dy in range(3):
                for dx in range(3):
                    out += pad[:, dy:dy + h, dx:dx + wd, :] @ w[:, dy, dx, :].T
            x = np.maximum(out, 0) if spec["relu"] else out
        elif t == "maxpool2":
            n, h, wd, c = x.shape
            x = x.reshape(n, h // 2, 2, wd // 2, 2, c).max(axis=(2, 4))
        elif t == "flatten":
            x = x.reshape(len(x), -1)
        elif t == "dense":
            w, b = arrays
            x = x @ w.T + b
            x = np.maximum(x, 0) if spec["relu"] else x
        elif t == "softmax":
            e = np.exp(x - x.max(axis=1, keepdims=True))
            x = e / e.sum(axis=1, keepdims=True)
    return x


def export_weights(model: Path, out: Path) -> tuple:
    interp, layers = read_graph(model)
    out.mkdir(parents=True, exist_ok=True)
    blob, manifest = bytearray(), []
    for layer in layers:
        spec = dict(layer.spec)
        spec["tensors"] = []
        quant = layer.quant or [None] * len(layer.arrays)
        for a, q in zip(layer.arrays, quant):
            entry = {"shape": list(a.shape), "offset": len(blob)}
            if q is None:
                entry["dtype"] = "f32"
                blob += np.ascontiguousarray(a, dtype="<f4").tobytes()
            else:  # int8 values, then one float32 scale per output channel
                entry["dtype"] = "i8"
                blob += np.ascontiguousarray(q[0], dtype=np.int8).tobytes()
                entry["scales_offset"] = len(blob)
                blob += np.ascontiguousarray(q[1], dtype="<f4").tobytes()
            spec["tensors"].append(entry)
        manifest.append(spec)
    (out / "weights.bin").write_bytes(bytes(blob))
    (out / "manifest.json").write_text(json.dumps(
        {"input": [SQUARE, SQUARE, 1], "classes": [c or "." for c in CLASSES], "layers": manifest}, indent=1))
    check_round_trip(out, layers)
    return interp, layers


def check_round_trip(out: Path, layers) -> None:
    """Read weights.bin back the way the Dart loader does (int8 * float32 scale) and demand bit-identical floats."""
    blob = (out / "weights.bin").read_bytes()
    manifest = json.loads((out / "manifest.json").read_text())["layers"]
    for layer, spec in zip(layers, manifest):
        for expected, t in zip(layer.arrays, spec["tensors"]):
            n = int(np.prod(t["shape"]))
            if t["dtype"] == "f32":
                got = np.frombuffer(blob, "<f4", n, t["offset"]).reshape(t["shape"])
            else:
                q = np.frombuffer(blob, np.int8, n, t["offset"]).reshape(t["shape"])
                scales = np.frombuffer(blob, "<f4", t["shape"][0], t["scales_offset"])
                got = (q.astype(np.float32) * scales.reshape([-1] + [1] * (q.ndim - 1))).astype(np.float32)
            assert np.array_equal(got, expected), "weights.bin does not read back to the exported tensors"
    print(f"weights.bin round-trips bit-identically ({len(blob) // 1024} KiB)")


def export_fixtures(model: Path, interp, layers, fixtures: Path) -> None:
    from .model import predict_tflite
    from .pipeline import recognize, recognize_page
    from .squares import cut_squares
    from .synth import build_sprite_sets, random_grid, render_board

    fixtures.mkdir(parents=True, exist_ok=True)
    predict = predict_tflite(model)
    rng, sets = random.Random(7), [s for s in build_sprite_sets() if s.family in ("cburnett", "dejavu")]

    # 1) one batch of 64 squares with the real TFLite answer, to check the Dart forward pass (same argmax, probabilities within 0.05)
    img, box, _ = render_board(random_grid(rng), sets, rng)
    cells = cut_squares(img, box)
    u8 = (cells * 255).round().astype(np.uint8)
    probs = predict(u8.astype(np.float32) / 255.0)
    ref = reference_forward(layers, (u8.astype(np.float32) / 255.0)[..., None])
    # TFLite's dynamic-range int8 kernels also quantise activations on the fly, so ambiguous squares can move by
    # a couple of 1e-2 in probability against an exact float replay; decisions must be identical.
    diff = np.abs(ref - probs).max()
    print(f"float replay of the exported layers vs TFLite interpreter: max |diff| = {diff:.2e}")
    assert (ref.argmax(1) == probs.argmax(1)).all() and diff < 0.05, "exported layers do not reproduce the TFLite model"
    (fixtures / "golden_cells.bin").write_bytes(u8.tobytes())
    (fixtures / "golden_probs.json").write_text(json.dumps([[round(float(p), 6) for p in row] for row in probs]))

    # 2) images + what the Python pipeline reads from them (port-consistency test for the Dart pipeline)
    expected = {}
    img, _, _ = render_board(random_grid(rng), sets, rng)
    Image.fromarray(img).save(fixtures / "board_single.png")
    expected["board_single.png"] = [recognize(img, predict).placement]

    for attempt in range(40):  # keep drawing until the Python pipeline finds every board: a clear fixture
        page = np.full((1500, 1080, 3), 255, np.uint8)
        page[:90] = 0  # status bar
        for n, (x, y) in enumerate(((90, 200), (590, 200), (90, 800)), 1):
            board, _, _ = render_board(random_grid(rng), sets, rng)
            side = 400
            page[y:y + side, x:x + side] = cv2.resize(board, (side, side), interpolation=cv2.INTER_AREA)
            cv2.rectangle(page, (x, y), (x + side - 1, y + side - 1), (0, 0, 0), 2)  # printed diagrams have a frame
            cv2.putText(page, str(n), (x + 170, y + side + 55), cv2.FONT_HERSHEY_SIMPLEX, 1.6, (0, 0, 0), 5)
        found = recognize_page(page, predict)
        if len(found) == 3:
            break
    else:
        raise SystemExit("could not build a page with three detectable boards")
    Image.fromarray(page).save(fixtures / "page_three_boards.png")
    expected["page_three_boards.png"] = [r.placement for r in found]
    (fixtures / "expected.json").write_text(json.dumps(expected, indent=1))
    print("python pipeline on fixtures:", json.dumps(expected))


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--fixtures", type=Path, required=True)
    a = ap.parse_args()
    interp, layers = export_weights(a.model, a.out)
    export_fixtures(a.model, interp, layers, a.fixtures)
    print("weights:", (a.out / "weights.bin").stat().st_size // 1024, "KiB")


if __name__ == "__main__":
    main()
