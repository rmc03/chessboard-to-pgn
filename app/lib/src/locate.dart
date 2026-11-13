// Board location. Port of prototype/chessdiag/locate.py: keep the two in sync.
//
//  * findBoard : the 8x8 board inside one diagram image (margins/captions around it).
//  * findBoards: every complete framed board of a screenshot (several diagrams per page).
import 'dart:math' as math;
import 'dart:typed_data';

import 'imaging.dart';

/// x0, y0, x1, y1 in pixels (x1/y1 exclusive).
class Box {
  const Box(this.x0, this.y0, this.x1, this.y1);
  final double x0, y0, x1, y1;
  double get width => x1 - x0;
  double get height => y1 - y0;
  @override
  String toString() =>
      'Box(${x0.toStringAsFixed(1)}, ${y0.toStringAsFixed(1)}, ${x1.toStringAsFixed(1)}, ${y1.toStringAsFixed(1)})';
}

/// (level, noise) of the plain page around the board, or null if the image edge is not plain.
({double level, double noise})? _pageBackground(Gray g) {
  final ring = <double>[
    for (var x = 0; x < g.w; x++) g.at(x, 0),
    for (var x = 0; x < g.w; x++) g.at(x, g.h - 1),
    for (var y = 1; y < g.h - 1; y++) g.at(0, y),
    for (var y = 1; y < g.h - 1; y++) g.at(g.w - 1, y),
  ];
  final hist = List<int>.filled(64, 0); // 64 bins over [0, 256)
  for (final v in ring) {
    hist[math.min(63, math.max(0, v ~/ 4))]++;
  }
  var peak = 0, best = -1;
  for (var i = 0; i < 64; i++) {
    final s = hist[i] + (i > 0 ? hist[i - 1] : 0) + (i < 63 ? hist[i + 1] : 0);
    if (s > best) {
      best = s;
      peak = i;
    }
  }
  final level = peak * 4 + 2.0;
  final near = [
    for (final v in ring)
      if ((v - level).abs() < 12) v,
  ];
  if (near.length / ring.length < 0.45) return null;
  final mean = near.reduce((a, b) => a + b) / near.length;
  final variance =
      near.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
      near.length;
  return (level: level, noise: math.sqrt(variance));
}

/// Longest run of values above [thresh], bridging gaps of at most [maxGap] samples. Returns (start, end).
(int, int) _longestRun(List<double> profile, double thresh, int maxGap) {
  var best = (0, 0);
  int? start, lastOn;
  for (var i = 0; i < profile.length; i++) {
    if (profile[i] > thresh) {
      start ??= i;
      lastOn = i;
    } else if (start != null && i - lastOn! > maxGap) {
      if (lastOn + 1 - start > best.$2 - best.$1) best = (start, lastOn + 1);
      start = null;
    }
  }
  if (start != null && lastOn! + 1 - start > best.$2 - best.$1) {
    best = (start, lastOn + 1);
  }
  return best;
}

double _interp(Float64List profile, double x) {
  final i = x.floor();
  if (i >= profile.length - 1) return profile[profile.length - 1];
  final f = x - i;
  return profile[i] * (1 - f) + profile[i + 1] * f;
}

/// Best equally spaced 9-line grid near [a, b] on a 1-D edge-energy profile.
(double, double) _snapAxis(Float64List profile, double a, double b) {
  final c0 = (b - a) / 8;
  if (c0 < 3) return (a, b);
  final n = profile.length;
  var bestScore = -1.0;
  var best = (a, b);
  for (var si = 0; si < 15; si++) {
    final s = 0.93 * c0 + (1.07 * c0 - 0.93 * c0) * si / 14;
    final lo = a - 0.3 * c0, hi = a + 0.3 * c0;
    for (var x0 = lo; x0 <= hi + 1e-6; x0 += 0.25) {
      if (x0 < 0 || x0 + 8 * s > n - 1) continue;
      var score = 0.0;
      for (var g = 0; g < 9; g++) {
        score += _interp(profile, x0 + s * g);
      }
      if (score > bestScore) {
        bestScore = score;
        best = (x0, x0 + 8 * s);
      }
    }
  }
  return best;
}

/// The board box inside one diagram image. Falls back to the whole image if nothing board-like is found.
Box findBoard(Rgb img, {bool snap = true}) {
  final gray = gaussianBlur(img.toGray(), 0.7);
  final w = gray.w, h = gray.h;
  final full = Box(0, 0, w.toDouble(), h.toDouble());
  final bg = _pageBackground(gray);
  if (bg == null) return full; // edges are not a plain page: image is already cropped to the board
  final thresh = math.max(9.0, 4 * bg.noise);

  var x0 = 0, x1 = w, y0 = 0, y1 = h;
  for (var round = 0; round < 2; round++) {
    // columns restricted to the row band, then rows restricted to the columns
    final col = List<double>.filled(w, 0);
    for (var y = y0; y < y1; y++) {
      for (var x = 0; x < w; x++) {
        if ((gray.at(x, y) - bg.level).abs() > thresh) col[x]++;
      }
    }
    for (var x = 0; x < w; x++) {
      col[x] /= (y1 - y0);
    }
    (x0, x1) = _longestRun(
      col,
      0.25 * col.reduce(math.max),
      math.max(2, w ~/ 50),
    );
    final row = List<double>.filled(h, 0);
    for (var y = 0; y < h; y++) {
      for (var x = x0; x < x1; x++) {
        if ((gray.at(x, y) - bg.level).abs() > thresh) row[y]++;
      }
      row[y] /= math.max(1, x1 - x0);
    }
    (y0, y1) = _longestRun(
      row,
      0.25 * row.reduce(math.max),
      math.max(2, h ~/ 50),
    );
    if (x1 - x0 < 16 || y1 - y0 < 16) return full;
  }
  if (!snap) {
    return Box(x0.toDouble(), y0.toDouble(), x1.toDouble(), y1.toDouble());
  }

  // |Sobel| edge energy summed over the board band, smoothed, then the best 9-line grid
  final gx = Float64List(w), gy = Float64List(h);
  double px(int x, int y) => gray.at(reflect101(x, w), reflect101(y, h));
  for (var y = y0; y < y1; y++) {
    for (var x = 0; x < w; x++) {
      gx[x] +=
          ((px(x + 1, y - 1) + 2 * px(x + 1, y) + px(x + 1, y + 1)) -
                  (px(x - 1, y - 1) + 2 * px(x - 1, y) + px(x - 1, y + 1)))
              .abs();
    }
  }
  for (var y = 0; y < h; y++) {
    for (var x = x0; x < x1; x++) {
      gy[y] +=
          ((px(x - 1, y + 1) + 2 * px(x, y + 1) + px(x + 1, y + 1)) -
                  (px(x - 1, y - 1) + 2 * px(x, y - 1) + px(x + 1, y - 1)))
              .abs();
    }
  }
  final (sx0, sx1) = _snapAxis(
    gaussianBlur1d(gx, 0.8),
    x0.toDouble(),
    x1.toDouble(),
  );
  final (sy0, sy1) = _snapAxis(
    gaussianBlur1d(gy, 0.8),
    y0.toDouble(),
    y1.toDouble(),
  );
  return Box(sx0, sy0, sx1, sy1);
}

const int canonicalWidth =
    1080; // narrower screenshots are enlarged before looking for frames

/// Resizes [img] by [scale] with bicubic interpolation (used to enlarge zoomed-out screenshots).
typedef Resizer = Rgb Function(Rgb img, double scale);

/// All complete, framed boards on a page/screenshot, in reading order (rows, then columns).
///
/// Each diagram has a thin dark frame, which forms one connected component whose bounding box is the
/// board. Wide bars (status bar, rules, titles), thin scrollbars, coloured overlays, small captions and
/// boards cut by the screen edge are rejected. Returns [] when no framed board exists.
List<Box> findBoards(
  Rgb img, {
  Resizer? resize,
  double minFrac = 0.12,
  double inkDelta = 25.0,
}) {
  if (img.w < 0.93 * canonicalWidth && resize != null) {
    final scale = canonicalWidth / img.w;
    return [
      for (final b in _findBoards(resize(img, scale), minFrac, inkDelta))
        Box(b.x0 / scale, b.y0 / scale, b.x1 / scale, b.y1 / scale),
    ];
  }
  return _findBoards(img, minFrac, inkDelta);
}

List<Box> _findBoards(Rgb img, double minFrac, double inkDelta) {
  final gray = img.toGray();
  final w = gray.w, h = gray.h;
  final side = minFrac * math.min(h, w);
  // black-hat = "darker than its surroundings": responds to a 1-2 px frame line however much
  // down-scaling has lightened it, unlike a fixed distance from the page colour
  final k = math.max(5, (0.0065 * math.min(h, w)).round()) | 1;
  final bh = blackHat(gray, k);
  final ink = Uint8List(w * h);
  for (var i = 0, j = 0; i < w * h; i++, j += 3) {
    final r = img.data[j], g = img.data[j + 1], b = img.data[j + 2];
    final neutral =
        math.max(r, math.max(g, b)) - math.min(r, math.min(g, b)) <
        40; // UI overlays are coloured
    if (bh.d[i] > inkDelta && neutral) ink[i] = 1;
  }
  // keep only long straight strokes (the frame); digits, captions and glyphs vanish
  final run = math.max(15, (0.6 * side).toInt());
  final hLines = openLine(ink, w, h, run, horizontal: true);
  final vLines = openLine(ink, w, h, run, horizontal: false);
  for (var i = 0; i < w * h; i++) {
    hLines[i] |= vLines[i];
  }
  final frame = closeSquare(hLines, w, h, 7); // repair JPEG gaps

  var found = <Box>[];
  for (final c in connectedComponents(frame, w, h)) {
    if (math.min(c.w, c.h) < side ||
        !(0.85 <= c.w / c.h && c.w / c.h <= 1.18)) {
      continue;
    }
    if (c.x <= 1 || c.y <= 1 || c.x + c.w >= w - 1 || c.y + c.h >= h - 1) {
      continue; // cut by the screen edge
    }
    found.add(
      Box(
        c.x.toDouble(),
        c.y.toDouble(),
        (c.x + c.w).toDouble(),
        (c.y + c.h).toDouble(),
      ),
    );
  }
  // reading order: group by row (similar top edge), then left to right
  found.sort((a, b) => a.y0.compareTo(b.y0));
  final rows = <List<Box>>[];
  for (final b in found) {
    if (rows.isNotEmpty && (b.y0 - rows.last.first.y0).abs() < 0.5 * b.height) {
      rows.last.add(b);
    } else {
      rows.add([b]);
    }
  }
  var ordered = [
    for (final row in rows) ...(row..sort((a, b) => a.x0.compareTo(b.x0))),
  ];
  if (ordered.length >= 4) {
    // one typeface/layout per page: a box far from the median size is a damaged frame
    final widths = ordered.map((b) => b.width).toList()..sort();
    final n = widths.length;
    final median = n.isOdd
        ? widths[n ~/ 2]
        : (widths[n ~/ 2 - 1] + widths[n ~/ 2]) / 2;
    ordered = [
      for (final b in ordered)
        if ((b.width - median).abs() <= 0.08 * median &&
            (b.height - median).abs() <= 0.08 * median)
          b,
    ];
  }
  return ordered;
}
