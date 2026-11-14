// Small image-processing toolbox on typed lists (no OpenCV): everything the board locator needs.
// Mirrors the OpenCV calls used by prototype/chessdiag/locate.py and squares.py.
import 'dart:math' as math;
import 'dart:typed_data';

/// Row-major grayscale image, values 0..255.
class Gray {
  Gray(this.w, this.h, [Float32List? data]) : d = data ?? Float32List(w * h);
  final int w, h;
  final Float32List d;

  double at(int x, int y) => d[y * w + x];
}

/// RGB bytes plus size (what the decoder hands over).
class Rgb {
  Rgb(this.w, this.h, this.data);
  final int w, h;
  final Uint8List data; // r, g, b interleaved

  Gray toGray() {
    final g = Gray(w, h);
    for (var i = 0, j = 0; i < w * h; i++, j += 3) {
      g.d[i] = 0.299 * data[j] + 0.587 * data[j + 1] + 0.114 * data[j + 2];
    }
    return g;
  }

  /// Sub-image [x0, x1) x [y0, y1), clamped to the image.
  Rgb crop(int x0, int y0, int x1, int y1) {
    x0 = math.max(0, x0);
    y0 = math.max(0, y0);
    x1 = math.min(w, x1);
    y1 = math.min(h, y1);
    final cw = x1 - x0, ch = y1 - y0;
    final out = Uint8List(cw * ch * 3);
    for (var y = 0; y < ch; y++) {
      out.setRange(y * cw * 3, (y + 1) * cw * 3, data, ((y0 + y) * w + x0) * 3);
    }
    return Rgb(cw, ch, out);
  }
}

/// OpenCV's default border (BORDER_REFLECT_101): ... 2 1 | 0 1 2 ... n-2 n-1 | n-2 n-3 ...
int reflect101(int i, int n) {
  if (n == 1) return 0;
  while (i < 0 || i >= n) {
    if (i < 0) i = -i;
    if (i >= n) i = 2 * (n - 1) - i;
  }
  return i;
}

Float32List _gaussianKernel(double sigma) {
  final ksize =
      (sigma * 8 + 1).round() |
      1; // OpenCV's choice for float images when ksize = 0
  final r = ksize ~/ 2;
  final k = Float32List(2 * r + 1);
  var sum = 0.0;
  for (var i = -r; i <= r; i++) {
    final v = math.exp(-(i * i) / (2 * sigma * sigma));
    k[i + r] = v;
    sum += v;
  }
  for (var i = 0; i < k.length; i++) {
    k[i] /= sum;
  }
  return k;
}

/// Separable Gaussian blur (reflect-101 borders).
Gray gaussianBlur(Gray src, double sigma) {
  final k = _gaussianKernel(sigma);
  final r = k.length ~/ 2;
  final tmp = Gray(src.w, src.h), out = Gray(src.w, src.h);
  for (var y = 0; y < src.h; y++) {
    for (var x = 0; x < src.w; x++) {
      var acc = 0.0;
      for (var i = -r; i <= r; i++) {
        acc += k[i + r] * src.d[y * src.w + reflect101(x + i, src.w)];
      }
      tmp.d[y * src.w + x] = acc;
    }
  }
  for (var y = 0; y < src.h; y++) {
    for (var x = 0; x < src.w; x++) {
      var acc = 0.0;
      for (var i = -r; i <= r; i++) {
        acc += k[i + r] * tmp.d[reflect101(y + i, src.h) * src.w + x];
      }
      out.d[y * src.w + x] = acc;
    }
  }
  return out;
}

/// 1-D Gaussian smoothing of a profile.
Float64List gaussianBlur1d(Float64List v, double sigma) {
  final k = _gaussianKernel(sigma);
  final r = k.length ~/ 2;
  final out = Float64List(v.length);
  for (var x = 0; x < v.length; x++) {
    var acc = 0.0;
    for (var i = -r; i <= r; i++) {
      acc += k[i + r] * v[reflect101(x + i, v.length)];
    }
    out[x] = acc;
  }
  return out;
}

/// Grayscale min/max filter with a k x k square window; pixels outside the image are ignored.
Gray _extremum(Gray src, int k, {required bool max}) {
  final r = k ~/ 2;
  final w = src.w, h = src.h;
  final tmp = Gray(w, h), out = Gray(w, h);
  double pick(double a, double b) => max ? (a > b ? a : b) : (a < b ? a : b);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var m = src.d[y * w + x];
      for (var i = math.max(0, x - r); i <= math.min(w - 1, x + r); i++) {
        m = pick(m, src.d[y * w + i]);
      }
      tmp.d[y * w + x] = m;
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var m = tmp.d[y * w + x];
      for (var j = math.max(0, y - r); j <= math.min(h - 1, y + r); j++) {
        m = pick(m, tmp.d[j * w + x]);
      }
      out.d[y * w + x] = m;
    }
  }
  return out;
}

/// Black-hat = closing(src) - src: "darker than its surroundings" (thin dark lines on a lighter page).
Gray blackHat(Gray src, int k) {
  final closed = _extremum(_extremum(src, k, max: true), k, max: false);
  final out = Gray(src.w, src.h);
  for (var i = 0; i < out.d.length; i++) {
    out.d[i] = closed.d[i] - src.d[i];
  }
  return out;
}

/// Binary opening with a 1 x L (horizontal) or L x 1 (vertical) line: keeps only runs of ones of length >= L.
Uint8List openLine(
  Uint8List mask,
  int w,
  int h,
  int len, {
  required bool horizontal,
}) {
  final out = Uint8List(w * h);
  final lines = horizontal ? h : w, span = horizontal ? w : h;
  for (var a = 0; a < lines; a++) {
    var start = -1;
    for (var b = 0; b <= span; b++) {
      final on = b < span && mask[horizontal ? a * w + b : b * w + a] != 0;
      if (on) {
        if (start < 0) start = b;
      } else if (start >= 0) {
        if (b - start >= len) {
          for (var i = start; i < b; i++) {
            out[horizontal ? a * w + i : i * w + a] = 1;
          }
        }
        start = -1;
      }
    }
  }
  return out;
}

Uint8List _windowPass(
  Uint8List src,
  int w,
  int h,
  int k, {
  required bool horizontal,
  required bool dilate,
}) {
  // dilate: any one in the window; erode: all ones in the window (pixels outside the image are ignored)
  final out = Uint8List(w * h);
  final r = k ~/ 2;
  final lines = horizontal ? h : w, span = horizontal ? w : h;
  final prefix = Int32List(span + 1);
  for (var a = 0; a < lines; a++) {
    for (var b = 0; b < span; b++) {
      prefix[b + 1] =
          prefix[b] + (src[horizontal ? a * w + b : b * w + a] != 0 ? 1 : 0);
    }
    for (var b = 0; b < span; b++) {
      final lo = math.max(0, b - r), hi = math.min(span - 1, b + r);
      final ones = prefix[hi + 1] - prefix[lo];
      final hit = dilate ? ones > 0 : ones == hi - lo + 1;
      if (hit) out[horizontal ? a * w + b : b * w + a] = 1;
    }
  }
  return out;
}

/// Binary closing (dilate, then erode) with a k x k square.
Uint8List closeSquare(Uint8List mask, int w, int h, int k) {
  var m = _windowPass(mask, w, h, k, horizontal: true, dilate: true);
  m = _windowPass(m, w, h, k, horizontal: false, dilate: true);
  m = _windowPass(m, w, h, k, horizontal: true, dilate: false);
  return _windowPass(m, w, h, k, horizontal: false, dilate: false);
}

class ComponentBox {
  ComponentBox(this.x, this.y, this.w, this.h);
  final int x, y, w, h;
}

/// Bounding boxes of the 8-connected components of ones.
List<ComponentBox> connectedComponents(Uint8List mask, int w, int h) {
  final seen = Uint8List(w * h);
  final stack = Int32List(w * h);
  final boxes = <ComponentBox>[];
  for (var start = 0; start < w * h; start++) {
    if (mask[start] == 0 || seen[start] != 0) continue;
    var top = 0;
    stack[top++] = start;
    seen[start] = 1;
    var minX = w, maxX = 0, minY = h, maxY = 0;
    while (top > 0) {
      final p = stack[--top];
      final x = p % w, y = p ~/ w;
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
      for (var dy = -1; dy <= 1; dy++) {
        final ny = y + dy;
        if (ny < 0 || ny >= h) continue;
        for (var dx = -1; dx <= 1; dx++) {
          final nx = x + dx;
          if (nx < 0 || nx >= w) continue;
          final q = ny * w + nx;
          if (mask[q] != 0 && seen[q] == 0) {
            seen[q] = 1;
            stack[top++] = q;
          }
        }
      }
    }
    boxes.add(ComponentBox(minX, minY, maxX - minX + 1, maxY - minY + 1));
  }
  return boxes;
}

/// OpenCV-compatible bicubic resize (cv2.resize with fx = fy = [scale], INTER_CUBIC): Keys kernel with
/// a = -0.75, half-pixel centres, clamped borders. The `image` package's cubic filter is softer, which
/// lightens the 1 px frames that findBoards looks for in zoomed-out screenshots.
Rgb resizeCubic(Rgb src, double scale) {
  final dw = (src.w * scale).round(), dh = (src.h * scale).round();
  const a = -0.75;
  // per destination coordinate: first source index and 4 weights
  (Int32List, Float32List) taps(int dst, int n) {
    final first = Int32List(dst);
    final w = Float32List(dst * 4);
    for (var d = 0; d < dst; d++) {
      final f = (d + 0.5) / scale - 0.5;
      final s = f.floor();
      final t = f - s;
      final w0 = ((a * (t + 1) - 5 * a) * (t + 1) + 8 * a) * (t + 1) - 4 * a;
      final w1 = ((a + 2) * t - (a + 3)) * t * t + 1;
      final w2 = ((a + 2) * (1 - t) - (a + 3)) * (1 - t) * (1 - t) + 1;
      first[d] = s - 1;
      w[d * 4] = w0;
      w[d * 4 + 1] = w1;
      w[d * 4 + 2] = w2;
      w[d * 4 + 3] = 1 - w0 - w1 - w2;
    }
    return (first, w);
  }

  final (fx, wx) = taps(dw, src.w);
  final (fy, wy) = taps(dh, src.h);
  // horizontal pass: src.h x dw x 3 floats
  final tmp = Float32List(src.h * dw * 3);
  for (var y = 0; y < src.h; y++) {
    final row = y * src.w * 3;
    for (var x = 0; x < dw; x++) {
      var r = 0.0, g = 0.0, b = 0.0;
      for (var k = 0; k < 4; k++) {
        final sx = math.min(math.max(fx[x] + k, 0), src.w - 1);
        final wk = wx[x * 4 + k];
        final p = row + sx * 3;
        r += wk * src.data[p];
        g += wk * src.data[p + 1];
        b += wk * src.data[p + 2];
      }
      final o = (y * dw + x) * 3;
      tmp[o] = r;
      tmp[o + 1] = g;
      tmp[o + 2] = b;
    }
  }
  // vertical pass, rounded and clamped to 0..255
  final out = Uint8List(dh * dw * 3);
  for (var y = 0; y < dh; y++) {
    for (var x = 0; x < dw * 3; x++) {
      var v = 0.0;
      for (var k = 0; k < 4; k++) {
        final sy = math.min(math.max(fy[y] + k, 0), src.h - 1);
        v += wy[y * 4 + k] * tmp[sy * dw * 3 + x];
      }
      out[y * dw * 3 + x] = v <= 0 ? 0 : (v >= 255 ? 255 : v.round());
    }
  }
  return Rgb(dw, dh, out);
}
