// Image -> boards. The same steps as prototype/chessdiag/pipeline.py:
//   decode -> find boards -> cut 64 squares each -> classify -> apply chess rules.
// Heavy work runs in isolates so the UI stays responsive: one isolate prepares the image, then every
// board is classified in its own isolate (in parallel).
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import 'chess.dart';
import 'classifier.dart';
import 'imaging.dart';
import 'locate.dart';

/// One board's 64 squares, ready for the classifier.
class PreparedBoard {
  PreparedBoard(
    this.box,
    this.cells, {
    this.fallback = false,
    this.manual = false,
  });

  /// Board box in image pixels.
  final Box box;

  /// 64 x 32 x 32 floats in [0, 1], rank 8 first, file a first.
  final Float32List cells;

  /// True when no framed diagram was found and the whole image was treated as one board.
  final bool fallback;

  /// True when the user drew the region by hand (see [prepareRegion]).
  final bool manual;
}

class RecognizedBoard {
  RecognizedBoard(
    this.box,
    this.grid,
    this.confidence,
    this.rawArgmax,
    this.fallback, {
    this.manual = false,
  });
  final Box box;
  final List<int> grid;
  final List<double> confidence;
  final List<int> rawArgmax;
  final bool fallback;
  final bool manual;

  String get placement => gridToPlacement(grid);
}

Rgb decodeRgb(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) throw const FormatException('No se pudo leer la imagen');
  final upright = img.bakeOrientation(
    decoded,
  ); // photos from phones carry an EXIF rotation
  final rgb = upright.convert(numChannels: 3);
  return Rgb(
    rgb.width,
    rgb.height,
    Uint8List.fromList(rgb.getBytes(order: img.ChannelOrder.rgb)),
  );
}

/// Enlarges zoomed-out screenshots before looking for frames (same filter as OpenCV's INTER_CUBIC).
Rgb resizeBicubic(Rgb src, double scale) => resizeCubic(src, scale);

/// 64 squares of 32 x 32 floats in [0, 1] for [box] inside [crop]. Fractional boxes are fine.
Float32List cutSquares(Gray gray, Box box, {int size = squareSize}) {
  final sx = 8 * size / box.width, sy = 8 * size / box.height;
  var g = gray;
  if (sx < 1 || sy < 1) {
    g = gaussianBlur(
      g,
      0.5 / math.min(sx, sy),
    ); // strong downscale: low-pass first
  }
  final side = 8 * size;
  final out = Float32List(64 * size * size);
  double sample(int x, int y) =>
      g.d[math.min(math.max(y, 0), g.h - 1) * g.w +
          math.min(math.max(x, 0), g.w - 1)];
  for (var v = 0; v < side; v++) {
    final y = box.y0 + v / sy;
    final yi = y.floor();
    final fy = y - yi;
    for (var u = 0; u < side; u++) {
      final x = box.x0 + u / sx;
      final xi = x.floor();
      final fx = x - xi;
      final top = sample(xi, yi) * (1 - fx) + sample(xi + 1, yi) * fx;
      final bottom =
          sample(xi, yi + 1) * (1 - fx) + sample(xi + 1, yi + 1) * fx;
      final value = (top * (1 - fy) + bottom * fy) / 255.0;
      final cell = (v ~/ size) * 8 + (u ~/ size);
      out[cell * size * size + (v % size) * size + (u % size)] = value < 0
          ? 0
          : (value > 1 ? 1 : value);
    }
  }
  return out;
}

/// Finds every complete framed diagram of an image and cuts its squares. If none is framed, the whole
/// image is treated as a single board (an already-cropped diagram), flagged `fallback`.
List<PreparedBoard> prepareBoards(Uint8List imageBytes) {
  final rgb = decodeRgb(imageBytes);
  final boxes = findBoards(rgb, resize: resizeBicubic);
  if (boxes.isEmpty) {
    final box = findBoard(rgb);
    return [PreparedBoard(box, cutSquares(rgb.toGray(), box), fallback: true)];
  }
  final prepared = <PreparedBoard>[];
  for (final b in boxes) {
    final pad = (0.04 * b.width).toInt();
    final ox = math.max(0, b.x0.toInt() - pad),
        oy = math.max(0, b.y0.toInt() - pad);
    final crop = rgb.crop(ox, oy, b.x1.toInt() + pad, b.y1.toInt() + pad);
    final local = findBoard(crop);
    prepared.add(
      PreparedBoard(
        Box(local.x0 + ox, local.y0 + oy, local.x1 + ox, local.y1 + oy),
        cutSquares(crop.toGray(), local),
      ),
    );
  }
  return prepared;
}

/// The board inside a region the user drew by hand (image pixels). The region is clamped to the image and
/// cropped; [findBoard] snaps to the 8x8 grid inside the crop. If that box looks wrong, the whole crop is
/// used. The returned box is in full-image coordinates and the board is flagged `manual`.
PreparedBoard prepareRegion(Uint8List imageBytes, Box region) {
  final rgb = decodeRgb(imageBytes);
  // A little extra margin (like prepareBoards) lets findBoard see the frame of a tightly drawn region.
  final pad = 0.04 * region.width;
  final x0 = (region.x0 - pad).round().clamp(0, rgb.w - 1);
  final y0 = (region.y0 - pad).round().clamp(0, rgb.h - 1);
  final x1 = (region.x1 + pad).round().clamp(x0 + 1, rgb.w);
  final y1 = (region.y1 + pad).round().clamp(y0 + 1, rgb.h);
  final crop = rgb.crop(x0, y0, x1, y1);
  var local = findBoard(crop);
  final ratio = local.width / local.height;
  final plausible =
      (local.width >= 0.5 * crop.w || local.height >= 0.5 * crop.h) &&
      ratio >= 0.8 &&
      ratio <= 1.25;
  if (!plausible) {
    local = Box(0, 0, crop.w.toDouble(), crop.h.toDouble());
  }
  return PreparedBoard(
    Box(local.x0 + x0, local.y0 + y0, local.x1 + x0, local.y1 + y0),
    cutSquares(crop.toGray(), local),
    manual: true,
  );
}

RecognizedBoard classifyBoard(ModelAssets model, PreparedBoard board) {
  final probs = SquareClassifier.fromAssets(model).classify(board.cells);
  final d = decode(probs);
  return RecognizedBoard(
    board.box,
    d.grid,
    d.confidence,
    d.rawArgmax,
    board.fallback,
    manual: board.manual,
  );
}

/// Whole pipeline off the UI thread. [onFound] is called once the boards are located (to show progress).
Future<List<RecognizedBoard>> recognizeImage(
  Uint8List imageBytes,
  ModelAssets model, {
  void Function(int boards)? onFound,
}) async {
  final prepared = await Isolate.run(() => prepareBoards(imageBytes));
  onFound?.call(prepared.length);
  return Future.wait([
    for (final p in prepared) Isolate.run(() => classifyBoard(model, p)),
  ]);
}

/// [prepareRegion] + classification off the UI thread.
Future<RecognizedBoard> recognizeRegion(
  Uint8List imageBytes,
  Box region,
  ModelAssets model,
) => Isolate.run(() => classifyBoard(model, prepareRegion(imageBytes, region)));
