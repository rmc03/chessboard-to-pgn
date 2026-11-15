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
    this.originalCrop,
  });

  /// Board box in image pixels.
  final Box box;

  /// PNG of exactly [box] cut from the source image (see [encodeCrop]).
  final Uint8List? originalCrop;

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
    this.originalCrop,
  });
  final Box box;

  /// PNG of exactly [box] cut from the source image, longest side capped at [maxCropSide] pixels. Null when
  /// the board came from somewhere that has no image (tests, fakes).
  final Uint8List? originalCrop;
  final List<int> grid;
  final List<double> confidence;
  final List<int> rawArgmax;
  final bool fallback;
  final bool manual;

  String get placement => gridToPlacement(grid);
}

/// Longest side, in pixels, of [RecognizedBoard.originalCrop].
const int maxCropSide = 600;

/// PNG of [box] cut from [rgb] with no margin, so that it overlays the drawn board square for square. The box
/// is rounded to whole pixels and clamped to the image; the longest side is capped at [maxSide] (smaller
/// crops are never enlarged).
Uint8List encodeCrop(Rgb rgb, Box box, {int maxSide = maxCropSide}) {
  final crop = rgb.crop(
    box.x0.round(),
    box.y0.round(),
    box.x1.round(),
    box.y1.round(),
  );
  var image = img.Image.fromBytes(
    width: crop.w,
    height: crop.h,
    bytes: crop.data.buffer,
    numChannels: 3,
    order: img.ChannelOrder.rgb,
  );
  final longest = math.max(crop.w, crop.h);
  if (longest > maxSide) {
    final k = maxSide / longest;
    image = img.copyResize(
      image,
      width: math.max(1, (crop.w * k).round()),
      height: math.max(1, (crop.h * k).round()),
      interpolation: img.Interpolation.average,
    );
  }
  return img.encodePng(image, level: 3);
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

/// The boards of an image plus the size of the (orientation-corrected) image they are measured in.
class PreparedImage {
  PreparedImage(this.width, this.height, this.boards);
  final int width, height;
  final List<PreparedBoard> boards;
}

/// Finds every complete framed diagram of an image and cuts its squares. If none is framed, the whole
/// image is treated as a single board (an already-cropped diagram), flagged `fallback`.
List<PreparedBoard> prepareBoards(Uint8List imageBytes) =>
    prepareImage(imageBytes).boards;

/// [prepareBoards] that also reports the image size.
PreparedImage prepareImage(Uint8List imageBytes) {
  final rgb = decodeRgb(imageBytes);
  final boxes = findBoards(rgb, resize: resizeBicubic);
  if (boxes.isEmpty) {
    final box = findBoard(rgb);
    return PreparedImage(rgb.w, rgb.h, [
      PreparedBoard(
        box,
        cutSquares(rgb.toGray(), box),
        fallback: true,
        originalCrop: encodeCrop(rgb, box),
      ),
    ]);
  }
  final prepared = <PreparedBoard>[];
  for (final b in boxes) {
    final pad = (0.04 * b.width).toInt();
    final ox = math.max(0, b.x0.toInt() - pad),
        oy = math.max(0, b.y0.toInt() - pad);
    final crop = rgb.crop(ox, oy, b.x1.toInt() + pad, b.y1.toInt() + pad);
    final local = findBoard(crop);
    final box = Box(local.x0 + ox, local.y0 + oy, local.x1 + ox, local.y1 + oy);
    prepared.add(
      PreparedBoard(
        box,
        cutSquares(crop.toGray(), local),
        originalCrop: encodeCrop(rgb, box),
      ),
    );
  }
  return PreparedImage(rgb.w, rgb.h, prepared);
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
  final box = Box(local.x0 + x0, local.y0 + y0, local.x1 + x0, local.y1 + y0);
  return PreparedBoard(
    box,
    cutSquares(crop.toGray(), local),
    manual: true,
    originalCrop: encodeCrop(rgb, box),
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
    originalCrop: board.originalCrop,
  );
}

// These live at top level on purpose: a closure passed to Isolate.run shares its context with every other
// closure of the enclosing function, so created inline it would drag the progress callbacks (and whatever
// they capture, e.g. the Session) into the isolate message.
Future<PreparedImage> _prepareInIsolate(Uint8List imageBytes) =>
    Isolate.run(() => prepareImage(imageBytes));

Future<RecognizedBoard> _classifyInIsolate(
  ModelAssets model,
  PreparedBoard p,
) => Isolate.run(() => classifyBoard(model, p));

/// Called once the boards are located: how many, and the size of the image the box coordinates refer to.
typedef BoardsFoundFn = void Function(int boards, int width, int height);

/// Called as each board finishes (in completion order, not necessarily [index] order).
typedef BoardReadFn = void Function(int index, RecognizedBoard board);

/// Whole pipeline off the UI thread, reporting progress: [onFound] once the boards are located, then [onBoard]
/// for each board as its classification finishes. Returns the boards in reading order.
Future<List<RecognizedBoard>> recognizeImageStreaming(
  Uint8List imageBytes,
  ModelAssets model, {
  BoardsFoundFn? onFound,
  BoardReadFn? onBoard,
}) async {
  final prepared = await _prepareInIsolate(imageBytes);
  onFound?.call(prepared.boards.length, prepared.width, prepared.height);
  return Future.wait([
    for (final (i, p)
        in prepared
            .boards
            .indexed) // capture one board, not all of them, in each isolate
      _classifyInIsolate(model, p).then((b) {
        onBoard?.call(i, b);
        return b;
      }),
  ]);
}

/// Whole pipeline off the UI thread. [onFound] is called once the boards are located (to show progress).
Future<List<RecognizedBoard>> recognizeImage(
  Uint8List imageBytes,
  ModelAssets model, {
  void Function(int boards)? onFound,
}) => recognizeImageStreaming(
  imageBytes,
  model,
  onFound: onFound == null ? null : (n, _, _) => onFound(n),
);

/// [prepareRegion] + classification off the UI thread.
Future<RecognizedBoard> recognizeRegion(
  Uint8List imageBytes,
  Box region,
  ModelAssets model,
) => Isolate.run(() => classifyBoard(model, prepareRegion(imageBytes, region)));
