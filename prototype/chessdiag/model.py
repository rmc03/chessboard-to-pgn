"""Tiny CNN square classifier (32x32 gray -> 13 classes), training and TFLite export."""
from __future__ import annotations

import json
from pathlib import Path

import numpy as np

from . import CLASSES
from .squares import SQUARE

BATCH = 64  # the exported model classifies the 64 squares of a board in a single call


def build_model(batch_size: int | None = None):
    import keras
    from keras import layers

    inp = keras.Input(batch_shape=(batch_size, SQUARE, SQUARE, 1))
    x = inp
    for filters in (16, 32, 64):
        for _ in range(2):
            x = layers.Conv2D(filters, 3, padding="same", use_bias=False)(x)
            x = layers.BatchNormalization()(x)
            x = layers.ReLU()(x)
        x = layers.MaxPooling2D()(x)
    x = layers.Flatten()(x)
    x = layers.Dense(128, activation="relu")(x)
    x = layers.Dropout(0.3)(x)
    out = layers.Dense(len(CLASSES), activation="softmax")(x)
    return keras.Model(inp, out)


def train(X: np.ndarray, y: np.ndarray, Xv: np.ndarray, yv: np.ndarray, epochs: int = 10):
    import keras
    import tensorflow as tf

    model = build_model()
    model.compile(
        optimizer=keras.optimizers.Adam(2e-3),
        loss="sparse_categorical_crossentropy",
        metrics=["accuracy"],
    )

    def ds(a, b, shuffle):
        d = tf.data.Dataset.from_tensor_slices((a, b))
        if shuffle:
            d = d.shuffle(50_000)
        return d.batch(256).map(lambda i, l: (tf.cast(i[..., None], tf.float32) / 255.0, l)).prefetch(2)

    cb = [keras.callbacks.ReduceLROnPlateau(factor=0.5, patience=1, min_lr=1e-5)]
    model.fit(ds(X, y, True), validation_data=ds(Xv, yv, False), epochs=epochs, callbacks=cb, verbose=2)
    return model


def predict_keras(model):
    def f(cells: np.ndarray) -> np.ndarray:
        return model.predict(cells[..., None], batch_size=256, verbose=0)
    return f


def export_tflite(model, out_dir: Path) -> Path:
    """Fixed-batch (64,32,32,1) float32 model + a JSON contract the Flutter side reads."""
    import tensorflow as tf

    fixed = build_model(BATCH)
    fixed.set_weights(model.get_weights())
    conv = tf.lite.TFLiteConverter.from_keras_model(fixed)
    conv.optimizations = [tf.lite.Optimize.DEFAULT]  # dynamic-range int8 weights, float I/O
    blob = conv.convert()
    out_dir.mkdir(parents=True, exist_ok=True)
    path = out_dir / "squares.tflite"
    path.write_bytes(blob)
    (out_dir / "model_contract.json").write_text(json.dumps({
        "input": {"shape": [BATCH, SQUARE, SQUARE, 1], "dtype": "float32", "range": [0.0, 1.0],
                  "layout": "grayscale (BT.601 luma), squares ordered rank 8 -> 1, file a -> h"},
        "output": {"shape": [BATCH, len(CLASSES)], "dtype": "float32", "kind": "softmax"},
        "classes": [c or "." for c in CLASSES],
    }, indent=2))
    return path


def predict_tflite(path: Path):
    import tensorflow as tf

    interp = tf.lite.Interpreter(model_path=str(path))
    interp.allocate_tensors()
    i, o = interp.get_input_details()[0]["index"], interp.get_output_details()[0]["index"]

    def f(cells: np.ndarray) -> np.ndarray:
        out = []
        for s in range(0, len(cells), BATCH):
            chunk = cells[s:s + BATCH]
            pad = BATCH - len(chunk)
            if pad:
                chunk = np.concatenate([chunk, np.zeros((pad, *chunk.shape[1:]), chunk.dtype)])
            interp.set_tensor(i, chunk[..., None].astype(np.float32))
            interp.invoke()
            out.append(interp.get_tensor(o).copy()[: BATCH - pad])
        return np.concatenate(out)
    return f
