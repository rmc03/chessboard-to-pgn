// Square classifier: the tiny CNN of prototype/chessdiag/model.py run in plain Dart (no native plugin).
//
// Input : 32 x 32 grayscale square, values in [0, 1].
// Output: 13 class probabilities (see classSymbols in chess.dart).
// Weights come from `python -m chessdiag.export_dart` (weights.bin: int8 + scales, manifest.json). About 9.7 M
// multiply-adds per square, so ~0.6 G per board. The convolutions and dense layers run 4 output channels at a
// time with Float32x4 (SIMD on ARM NEON / x86 SSE), weights pre-arranged once so the inner loop is contiguous.
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
  /// Output of the layer for [x]. The returned list is owned by the layer and reused on the next call.
  Float32List run(Float32List x);
}

/// Groups of 4 lanes needed for [n] values.
int _quads(int n) => (n + 3) >> 2;

class _Conv3x3 extends _Layer {
  /// [weights] as exported: [out][kh][kw][in]. Stored as [kh][kw][in][out] in Float32x4 lanes.
  _Conv3x3(
    this.h,
    this.w,
    this.cin,
    this.cout,
    Float32List weights,
    Float32List bias,
    this.relu,
  ) : q = _quads(cout),
      _w = Float32x4List(9 * cin * _quads(cout)),
      _b = Float32x4List(_quads(cout)),
      _out = Float32List(h * w * _quads(cout) * 4) {
    final lanes = Float32List.view(_w.buffer);
    for (var o = 0; o < cout; o++) {
      for (var k = 0; k < 9; k++) {
        for (var i = 0; i < cin; i++) {
          lanes[(k * cin + i) * q * 4 + o] = weights[(o * 9 + k) * cin + i];
        }
      }
    }
    final b = Float32List.view(_b.buffer);
    for (var o = 0; o < cout; o++) {
      b[o] = bias[o];
    }
    _out4 = Float32x4List.view(_out.buffer);
  }

  final int h, w, cin, cout, q;
  final bool relu;
  final Float32x4List _w, _b;
  final Float32List _out; // [y][x][q * 4]: channels padded to a multiple of 4 (cout is 16/32/64 here)
  late final Float32x4List _out4;

  @override
  Float32List run(Float32List x) {
    // the input is [y][x][cin] (the previous conv pads cin to a multiple of 4; cin == 1 for the first layer)
    final out = _out4, wq = _w, b = _b;
    final zero = Float32x4.zero();
    for (var y = 0; y < h; y++) {
      for (var xx = 0; xx < w; xx++) {
        final ob = (y * w + xx) * q;
        for (var j = 0; j < q; j++) {
          out[ob + j] = b[j];
        }
        for (var dy = 0; dy < 3; dy++) {
          final iy = y + dy - 1;
          if (iy < 0 || iy >= h) continue;
          for (var dx = 0; dx < 3; dx++) {
            final ix = xx + dx - 1;
            if (ix < 0 || ix >= w) continue;
            final xb = (iy * w + ix) * cin;
            final wb = (dy * 3 + dx) * cin * q;
            for (var ci = 0; ci < cin; ci++) {
              final v = Float32x4.splat(x[xb + ci]);
              final wr = wb + ci * q;
              for (var j = 0; j < q; j++) {
                out[ob + j] += v * wq[wr + j];
              }
            }
          }
        }
        if (relu) {
          for (var j = 0; j < q; j++) {
            out[ob + j] = out[ob + j].max(zero);
          }
        }
      }
    }
    return _out;
  }
}

class _MaxPool2 extends _Layer {
  _MaxPool2(this.h, this.w, this.c)
    : _out = Float32List((h ~/ 2) * (w ~/ 2) * c);
  final int h, w, c;
  final Float32List _out;

  @override
  Float32List run(Float32List x) {
    final oh = h ~/ 2, ow = w ~/ 2;
    final out = _out;
    for (var y = 0; y < oh; y++) {
      for (var xx = 0; xx < ow; xx++) {
        final a0 = ((2 * y) * w + 2 * xx) * c, b0 = a0 + c;
        final d0 = ((2 * y + 1) * w + 2 * xx) * c, e0 = d0 + c;
        final o0 = (y * ow + xx) * c;
        for (var ch = 0; ch < c; ch++) {
          out[o0 + ch] = math.max(
            math.max(x[a0 + ch], x[b0 + ch]),
            math.max(x[d0 + ch], x[e0 + ch]),
          );
        }
      }
    }
    return out;
  }
}

class _Dense extends _Layer {
  /// [weights] as exported: [out][in]. Stored as [in][out] in Float32x4 lanes.
  _Dense(this.nin, this.nout, Float32List weights, Float32List bias, this.relu)
    : q = _quads(nout),
      _w = Float32x4List(nin * _quads(nout)),
      _b = Float32x4List(_quads(nout)),
      _acc = Float32x4List(_quads(nout)),
      _out = Float32List(nout) {
    final lanes = Float32List.view(_w.buffer);
    for (var o = 0; o < nout; o++) {
      for (var i = 0; i < nin; i++) {
        lanes[i * q * 4 + o] = weights[o * nin + i];
      }
    }
    final b = Float32List.view(_b.buffer);
    for (var o = 0; o < nout; o++) {
      b[o] = bias[o];
    }
  }

  final int nin, nout, q;
  final bool relu;
  final Float32x4List _w, _b, _acc;
  final Float32List _out;

  @override
  Float32List run(Float32List x) {
    final acc = _acc, wq = _w;
    for (var j = 0; j < q; j++) {
      acc[j] = _b[j];
    }
    for (var i = 0; i < nin; i++) {
      final v = Float32x4.splat(x[i]);
      final wr = i * q;
      for (var j = 0; j < q; j++) {
        acc[j] += v * wq[wr + j];
      }
    }
    final lanes = Float32List.view(acc.buffer);
    for (var o = 0; o < nout; o++) {
      final v = lanes[o];
      _out[o] = relu && v < 0 ? 0 : v;
    }
    return _out;
  }
}

class _Softmax extends _Layer {
  _Softmax(int n) : _out = Float32List(n);
  final Float32List _out;

  @override
  Float32List run(Float32List x) {
    var m = x[0];
    for (final v in x) {
      if (v > m) m = v;
    }
    var sum = 0.0;
    for (var i = 0; i < x.length; i++) {
      final e = math.exp(x[i] - m);
      _out[i] = e;
      sum += e;
    }
    for (var i = 0; i < x.length; i++) {
      _out[i] /= sum;
    }
    return _out;
  }
}

class SquareClassifier {
  SquareClassifier._(this._layers);

  /// Not safe to share between concurrent callers (layers reuse their buffers); each isolate builds its own.
  final List<_Layer> _layers;

  /// Builds the network from `manifest.json` + `weights.bin`.
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

    // walk the graph once to know every layer's input shape
    var h = squareSize, w = squareSize, c = 1;
    var width = 1; // values per pixel in memory (conv outputs are padded to a multiple of 4 channels)
    var flat = 0;
    final layers = <_Layer>[];
    for (final s in specs) {
      final t = [
        for (final x in (s['tensors'] as List).cast<Map<String, dynamic>>())
          tensor(x),
      ];
      switch (s['type'] as String) {
        case 'conv3x3':
          final cout = s['out'] as int;
          if (width != c) {
            throw FormatException(
              'conv input with $c channels stored as $width',
            );
          }
          layers.add(_Conv3x3(h, w, c, cout, t[0], t[1], s['relu'] as bool));
          c = cout;
          width = _quads(cout) * 4;
        case 'maxpool2':
          layers.add(_MaxPool2(h, w, width));
          h ~/= 2;
          w ~/= 2;
        case 'flatten':
          if (width != c) {
            throw FormatException('flatten of $c channels stored as $width');
          }
          flat = h * w * c; // memory is already NHWC contiguous
        case 'dense':
          final nin = s['in'] as int, nout = s['out'] as int;
          if (flat != 0 && nin != flat) {
            throw FormatException('dense expects $nin inputs, got $flat');
          }
          layers.add(_Dense(nin, nout, t[0], t[1], s['relu'] as bool));
          flat = nout;
        case 'softmax':
          layers.add(_Softmax(flat));
        default:
          throw FormatException('unknown layer ${s['type']}');
      }
    }
    return SquareClassifier._(layers);
  }

  /// [cells] = n squares of 32 x 32 floats in [0, 1], concatenated. Returns n x 13 probabilities.
  Float32List classify(Float32List cells) {
    const per = squareSize * squareSize;
    final n = cells.length ~/ per;
    final out = Float32List(n * classSymbols.length);
    for (var i = 0; i < n; i++) {
      var x = Float32List.sublistView(cells, i * per, (i + 1) * per);
      for (final layer in _layers) {
        x = layer.run(x);
      }
      out.setRange(i * classSymbols.length, (i + 1) * classSymbols.length, x);
    }
    return out;
  }
}
