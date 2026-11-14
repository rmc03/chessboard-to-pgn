// The Dart image pipeline must read the fixture images exactly as the Python reference does.
// (expected.json is written by `python -m chessdiag.export_dart` from the Python pipeline.)
import 'dart:convert';
import 'dart:io';

import 'package:chessboard_pgn/src/classifier.dart';
import 'package:chessboard_pgn/src/locate.dart';
import 'package:chessboard_pgn/src/pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

final model = ModelAssets(
  File('assets/model/manifest.json').readAsStringSync(),
  File('assets/model/weights.bin').readAsBytesSync(),
);
final expected =
    (jsonDecode(File('test/fixtures/expected.json').readAsStringSync())
            as Map<String, dynamic>)
        .map((k, v) => MapEntry(k, (v as List).cast<String>()));

void main() {
  test('one diagram image: same position as Python', () async {
    final bytes = File('test/fixtures/board_single.png').readAsBytesSync();
    final boards = await recognizeImage(bytes, model);
    expect(boards, hasLength(1));
    expect(boards.single.placement, expected['board_single.png']!.single);
  });

  test('screenshot with three framed diagrams, a status bar and captions: same positions as Python', () async {
    final bytes = File('test/fixtures/page_three_boards.png').readAsBytesSync();
    var announced = -1;
    final boards = await recognizeImage(
      bytes,
      model,
      onFound: (n) => announced = n,
    );
    expect(announced, 3);
    expect(
      boards.map((b) => b.placement).toList(),
      expected['page_three_boards.png'],
    );
    expect(boards.every((b) => !b.fallback), isTrue);
  });

  group('manual region', () {
    final bytes = File('test/fixtures/page_three_boards.png').readAsBytesSync();
    final found = prepareBoards(
      bytes,
    )[1].box; // 2nd board, as the automatic pass sees it

    Box around(double pad) => Box(
      found.x0 - pad * found.width,
      found.y0 - pad * found.height,
      found.x1 + pad * found.width,
      found.y1 + pad * found.height,
    );

    for (final (name, pad) in [
      ('generous margin', 0.15),
      ('small margin', 0.05),
      ('tight crop', 0.0),
    ]) {
      test('$name around the 2nd board reads the expected position', () async {
        final region = around(pad);
        final prepared = prepareRegion(bytes, region);
        expect(prepared.manual, isTrue);
        expect(prepared.fallback, isFalse);
        // the snapped box is in full-image coordinates, inside the region and close to the automatic one
        expect(
          (prepared.box.x0 - found.x0).abs(),
          lessThan(0.05 * found.width),
        );
        expect(
          (prepared.box.y0 - found.y0).abs(),
          lessThan(0.05 * found.width),
        );
        final board = await recognizeRegion(bytes, region, model);
        expect(board.manual, isTrue);
        expect(board.placement, expected['page_three_boards.png']![1]);
      });
    }

    test('a region partly outside the image is clamped', () {
      final prepared = prepareRegion(
        bytes,
        Box(found.x0 - 5000, found.y0 - 5000, found.x1 + 5000, found.y1 + 5000),
      );
      expect(prepared.manual, isTrue);
    });
  });
}
