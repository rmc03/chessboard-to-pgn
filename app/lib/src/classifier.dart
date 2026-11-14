// Square classifier: the tiny CNN of prototype/chessdiag/model.py run in plain Dart (no native plugin).
//
// Input : 32 x 32 grayscale square, values in [0, 1].
// Output: 13 class probabilities (see classSymbols in chess.dart).
// Weights come from `python -m chessdiag.export_dart` (weights.bin: int8 + scales, manifest.json). About 9.7 M
// multiply-adds per square, so ~0.6 G per board: fine for trying the app, LiteRT is the plan for speed.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'chess.dart';

const int squareSize = 32;

/// Raw model files, as loaded from the assets (cheap to send to another isolate).
class ModelAssets {
  const ModelAssets(this.manifestJson, this.weights);
  final String manifestJson;
  final Uint8List weights;
}

abstract class _Layer {
  Float32List run(Float32List x);
}

class _Shape {
  _Shape(this.h, this.w, this.c);
  int h, w, c;
}

class _Conv3x3 extends _Layer {
  _Conv3x3(this.shape, this.cout, this.weights, this.bias, this.relu);
  final _Shape shape;
  final int cout;
  final Float32List weights; // [out][kh][kw][in]
  final Float32List bias;
  final bool relu;

  @override
  Float32List run(Float32List x) {
    final h = shape.h, w = shape.w, cin = shape.c;
    final out = Float32List(h * w * cout);
    for (var y = 0; y < h; y++) {
      for (var xx = 0; xx < w; xx++) {
        final obase = (y * w + xx) * cout;
        for (var o = 0; o < cout; o++) {
          var acc = bias[o];
          final wo = o * 9 * cin;
          for (var dy = 0; dy < 3; dy++) {
            final iy = y + dy - 1;
            if (iy < 0 || iy >= h) continue;
            for (var dx = 0; dx < 3; dx++) {
              final ix = xx + dx - 1;
              if (ix < 0 || ix >= w) continue;
              final xb = (iy * w + ix) * cin;
              final wb = wo + (dy * 3 + dx) * cin;
              for (var ci = 0; ci < cin; ci++) {
                acc += x[xb + ci] * weights[wb + ci];
              }
            }
          }
          out[obase + o] = relu && acc < 0 ? 0 : acc;
        }
      }
    }
    shape.c = cout;
    return out;
  }
}

class _MaxPool2 extends _Layer {
  _MaxPool2(this.shape);
  final _Shape shape;

  @override
  Float32List run(Float32List x) {
    final h = shape.h, w = shape.w, c = shape.c;
    final oh = h ~/ 2, ow = w ~/ 2;
    final out = Float32List(oh * ow * c);
    for (var y = 0; y < oh; y++) {
      for (var xx = 0; xx < ow; xx++) {
        for (var ch = 0; ch < c; ch++) {
          final a = x[((2 * y) * w + 2 * xx) * c + ch];
          final b = x[((2 * y) * w + 2 * xx + 1) * c + ch];
          final d = x[((2 * y + 1) * w + 2 * xx) * c + ch];
          final e = x[((2 * y + 1) * w + 2 * xx + 1) * c + ch];
          out[(y * ow + xx) * c + ch] = math.max(
            math.max(a, b),
            math.max(d, e),
          );
        }
      }
    }
    shape
      ..h = oh
      ..w = ow;
    return out;
  }
}

class _Dense extends _Layer {
  _Dense(this.nin, this.nout, this.weights, this.bias, this.relu);
  final int nin, nout;
  final Float32List weights; // [out][in]
  final Float32List bias;
  final bool relu;

  @override
  Float32List run(Float32List x) {
    final out = Float32List(nout);
    for (var o = 0; o < nout; o++) {
      var acc = bias[o];
      final wb = o * nin;
      for (var i = 0; i < nin; i++) {
        acc += x[i] * weights[wb + i];
      }
      out[o] = relu && acc < 0 ? 0 : acc;
    }
    return out;
  }
}

class _Softmax extends _Layer {
  @override
  Float32List run(Float32List x) {
    var m = x[0];
    for (final v in x) {
      if (v > m) m = v;
    }
    final out = Float32List(x.length);
    var sum = 0.0;
    for (var i = 0; i < x.length; i++) {
      final e = math.exp(x[i] - m);
      out[i] = e;
      sum += e;
    }
    for (var i = 0; i < x.length; i++) {
      out[i] /= sum;
    }
    return out;
  }
}

class SquareClassifier {
  SquareClassifier._(this._build);
  final List<_Layer> Function() _build;

  /// Builds the network from `manifest.json` + `weights.bin` (float32 little-endian).
  factory SquareClassifier.fromAssets(ModelAssets assets) {
    final manifest = jsonDecode(assets.manifestJson) as Map<String, dynamic>;
    final bytes = ByteData.sublistView(assets.weights);
    final specs = (manifest['layers'] as List).cast<Map<String, dynamic>>();

    // "f32": plain float32. "i8": int8 values followed (at scales_offset) by one float32 scale per output
    // channel, exactly as stored in the TFLite model; value = int8 * scale.
    Float32List tensor(Map<String, dynamic> t) {
      final shape = (t['shape'] as List).cast<int>();
      final n = shape.fold<int>(1, (a, b) => a * b);
      final offset = t['offset'] as int;
      final out = Float32List(n);
      if (t['dtype'] == 'i8') {
        final scalesOffset = t['scales_offset'] as int;
        final channels = shape.first, perChannel = n ~/ channels;
        for (var o = 0; o < channels; o++) {
          final scale = bytes.getFloat32(scalesOffset + 4 * o, Endian.little);
          for (var i = 0; i < perChannel; i++) {
            out[o * perChannel + i] =
                bytes.getInt8(offset + o * perChannel + i) * scale;
          }
        }
      } else {
        for (var i = 0; i < n; i++) {
          out[i] = bytes.getFloat32(offset + 4 * i, Endian.little);
        }
      }
      return out;
    }

    // tensors are decoded once; every run() builds fresh cheap layer objects (the shape is mutable state)
    final decoded = [
      for (final s in specs)
        [
          for (final t in (s['tensors'] as List).cast<Map<String, dynamic>>())
            tensor(t),
        ],
    ];
    return SquareClassifier._(() {
      final shape = _Shape(squareSize, squareSize, 1);
      final layers = <_Layer>[];
      for (var i = 0; i < specs.length; i++) {
        final s = specs[i];
        switch (s['type'] as String) {
          case 'conv3x3':
            layers.add(
              _Conv3x3(
                shape,
                s['out'] as int,
                decoded[i][0],
                decoded[i][1],
                s['relu'] as bool,
              ),
            );
          case 'maxpool2':
            layers.add(_MaxPool2(shape));
          case 'flatten':
            break; // memory is already NHWC contiguous
          case 'dense':
            layers.add(
              _Dense(
                s['in'] as int,
                s['out'] as int,
                decoded[i][0],
                decoded[i][1],
                s['relu'] as bool,
              ),
            );
          case 'softmax':
            layers.add(_Softmax());
          default:
            throw FormatException('unknown layer ${s['type']}');
        }
      }
      return layers;
    });
  }

  /// [cells] = n squares of 32 x 32 floats in [0, 1], concatenated. Returns n x 13 probabilities.
  Float32List classify(Float32List cells) {
    const per = squareSize * squareSize;
    final n = cells.length ~/ per;
    final out = Float32List(n * classSymbols.length);
    for (var i = 0; i < n; i++) {
      var x = Float32List.sublistView(cells, i * per, (i + 1) * per);
      for (final layer in _build()) {
        x = layer.run(x);
      }
      out.setRange(i * classSymbols.length, (i + 1) * classSymbols.length, x);
    }
    return out;
  }
}
