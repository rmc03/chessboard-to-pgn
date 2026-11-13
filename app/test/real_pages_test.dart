// Optional local check with your own screenshots (nothing from them is committed).
//
//   CHESS_REAL_PAGES=/dir/with/screenshots CHESS_REAL_EXPECTED=/path/expected.json flutter test test/real_pages_test.dart
//
// expected.json: {"page.jpg": ["placement of board 1", "placement of board 2", ...]} in reading order.
// Skipped when the variables are not set.
import 'dart:convert';
import 'dart:io';

import 'package:chessboard_pgn/src/classifier.dart';
import 'package:chessboard_pgn/src/pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final pagesDir = Platform.environment['CHESS_REAL_PAGES'];
  final expectedPath = Platform.environment['CHESS_REAL_EXPECTED'];
  final enabled = pagesDir != null && expectedPath != null;

  test(
    'real screenshots are read as expected',
    () async {
      final model = ModelAssets(
        File('assets/model/manifest.json').readAsStringSync(),
        File('assets/model/weights.bin').readAsBytesSync(),
      );
      final expected =
          (jsonDecode(File(expectedPath!).readAsStringSync())
                  as Map<String, dynamic>)
              .map((k, v) => MapEntry(k, (v as List).cast<String>()));
      var right = 0, total = 0;
      final sw = Stopwatch();
      for (final entry in expected.entries) {
        sw
          ..reset()
          ..start();
        final boards = await recognizeImage(
          File('$pagesDir/${entry.key}').readAsBytesSync(),
          model,
        );
        final got = boards.map((b) => b.placement).toList();
        // ignore: avoid_print
        print(
          '${entry.key}: ${boards.length} boards in ${sw.elapsedMilliseconds} ms, '
          'low-confidence squares: ${boards.map((b) => b.confidence.where((c) => c < 0.9).length).toList()}',
        );
        total += entry.value.length;
        for (var i = 0; i < entry.value.length; i++) {
          final ok = i < got.length && got[i] == entry.value[i];
          right += ok ? 1 : 0;
          if (!ok) {
            // ignore: avoid_print
            print(
              '  MISMATCH board ${i + 1}: expected ${entry.value[i]}  got ${i < got.length ? got[i] : '(missing)'}',
            );
          }
        }
      }
      // ignore: avoid_print
      print('exact boards: $right / $total');
      expect(right, total);
    },
    skip: enabled
        ? false
        : 'set CHESS_REAL_PAGES and CHESS_REAL_EXPECTED to run',
    timeout: const Timeout(Duration(minutes: 10)),
  );
}
