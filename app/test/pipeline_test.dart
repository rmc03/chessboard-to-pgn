// The Dart image pipeline must read the fixture images exactly as the Python reference does.
// (expected.json is written by `python -m chessdiag.export_dart` from the Python pipeline.)
import 'dart:convert';
import 'dart:io';

import 'package:chessboard_pgn/src/classifier.dart';
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
}
