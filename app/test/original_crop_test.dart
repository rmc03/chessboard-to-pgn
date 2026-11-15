// The crop of the original board that the "Leído | Original" comparator overlays on the drawn board.
import 'dart:io';
import 'dart:typed_data';

import 'package:chessboard_pgn/src/classifier.dart';
import 'package:chessboard_pgn/src/diagram.dart';
import 'package:chessboard_pgn/src/imaging.dart';
import 'package:chessboard_pgn/src/locate.dart';
import 'package:chessboard_pgn/src/pipeline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

final model = ModelAssets(
  File('assets/model/manifest.json').readAsStringSync(),
  File('assets/model/weights.bin').readAsBytesSync(),
);

void expectSquareCrop(Uint8List? png, Box box, {bool board = true}) {
  expect(png, isNotNull);
  final crop = img.decodePng(png!)!;
  expect(crop.width / crop.height, closeTo(box.width / box.height, 0.02));
  if (board) expect(crop.width / crop.height, closeTo(1, 0.1));
  expect(crop.width, lessThanOrEqualTo(maxCropSide));
  expect(crop.height, lessThanOrEqualTo(maxCropSide));
  final k = maxCropSide / box.width;
  if (box.width <= maxCropSide) {
    expect(crop.width, closeTo(box.width, 1)); // never enlarged, no margin
  } else {
    expect(crop.width, closeTo(box.width * k, 1));
  }
}

void main() {
  test('encodeCrop cuts exactly the box, with no margin', () {
    final w = 100, h = 80;
    final data = Uint8List(w * h * 3)..fillRange(0, w * h * 3, 255);
    // red square at x 20..49, y 10..39
    for (var y = 10; y < 40; y++) {
      for (var x = 20; x < 50; x++) {
        final i = (y * w + x) * 3;
        data[i] = 255;
        data[i + 1] = 0;
        data[i + 2] = 0;
      }
    }
    final png = encodeCrop(Rgb(w, h, data), const Box(20, 10, 50, 40));
    final crop = img.decodePng(png)!;
    expect((crop.width, crop.height), (30, 30));
    for (final (x, y) in [(0, 0), (29, 0), (0, 29), (29, 29), (15, 15)]) {
      final p = crop.getPixel(x, y);
      expect((p.r, p.g, p.b), (255, 0, 0), reason: 'pixel $x,$y');
    }
  });

  test('encodeCrop caps the longest side and keeps the aspect ratio', () {
    final rgb = Rgb(1400, 1000, Uint8List(1400 * 1000 * 3));
    final crop = img.decodePng(encodeCrop(rgb, const Box(0, 0, 1200, 1000)))!;
    expect((crop.width, crop.height), (600, 500));
    final small = img.decodePng(encodeCrop(rgb, const Box(0, 0, 300, 300)))!;
    expect((small.width, small.height), (300, 300)); // never enlarged
  });

  test('the pipeline returns a crop for every board of a page', () async {
    final bytes = File('test/fixtures/page_three_boards.png').readAsBytesSync();
    final prepared = prepareImage(bytes);
    expect(prepared.boards, hasLength(3));
    for (final b in prepared.boards) {
      expectSquareCrop(b.originalCrop, b.box);
    }
    final boards = await recognizeImageStreaming(bytes, model);
    expect(boards, hasLength(3));
    for (final b in boards) {
      expectSquareCrop(b.originalCrop, b.box);
    }
    // it reaches the Diagram untouched
    final d = Diagram.fromRecognized(boards.first);
    expect(d.originalCrop, same(boards.first.originalCrop));
  });

  test(
    'the crop of the first board matches the pixels of the page under its box',
    () {
      final bytes = File('test/fixtures/page_three_boards.png')
          .readAsBytesSync();
      final page = decodeRgb(bytes);
      final b = prepareImage(bytes).boards.first;
      final crop = img.decodePng(b.originalCrop!)!;
      if (b.box.width <= maxCropSide) {
        final x = b.box.x0.round(), y = b.box.y0.round();
        var diff = 0;
        for (var j = 0; j < crop.height; j += 7) {
          for (var i = 0; i < crop.width; i += 7) {
            final p = crop.getPixel(i, j);
            final o = ((y + j) * page.w + x + i) * 3;
            diff += (p.r - page.data[o]).abs().toInt();
          }
        }
        expect(diff, 0);
      }
    },
  );

  test('a single already-cropped diagram (fallback) and a manual region get a crop too', () async {
    final single = File('test/fixtures/board_single.png').readAsBytesSync();
    final one = await recognizeImageStreaming(single, model);
    // the fallback box is the whole picture, whatever its shape
    expectSquareCrop(one.single.originalCrop, one.single.box, board: false);

    final page = File('test/fixtures/page_three_boards.png').readAsBytesSync();
    final found = prepareImage(page).boards[1].box;
    final manual = await recognizeRegion(
      page,
      Box(
        found.x0 - 0.1 * found.width,
        found.y0 - 0.1 * found.height,
        found.x1 + 0.1 * found.width,
        found.y1 + 0.1 * found.height,
      ),
      model,
    );
    expect(manual.manual, isTrue);
    expectSquareCrop(manual.originalCrop, manual.box);
  });

  test('recognizeImageStreaming reports the size, the boards found and each board read', () async {
    final bytes = File('test/fixtures/page_three_boards.png').readAsBytesSync();
    final events = <String>[];
    final seen = <int>{};
    final boards = await recognizeImageStreaming(
      bytes,
      model,
      onFound: (n, w, h) {
        events.add('found $n');
        expect(w, greaterThan(0));
        expect(h, greaterThan(0));
      },
      onBoard: (i, b) {
        events.add('board');
        seen.add(i);
      },
    );
    expect(events.first, 'found 3');
    expect(events.where((e) => e == 'board'), hasLength(3));
    expect(seen, {0, 1, 2});
    expect(boards, hasLength(3));
  });
}
