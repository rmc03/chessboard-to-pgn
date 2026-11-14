// ignore_for_file: avoid_print
// AOT timing of the pure-Dart classifier:
//   dart compile exe tool/bench_classifier.dart -o /tmp/bench && /tmp/bench
import 'dart:io';
import 'dart:typed_data';

import 'package:chessboard_pgn/src/classifier.dart';

void main() {
  final model = ModelAssets(
    File('assets/model/manifest.json').readAsStringSync(),
    File('assets/model/weights.bin').readAsBytesSync(),
  );
  final u8 = File('test/fixtures/golden_cells.bin').readAsBytesSync();
  final cells = Float32List(u8.length);
  for (var i = 0; i < u8.length; i++) {
    cells[i] = u8[i] / 255.0;
  }
  final clf = SquareClassifier.fromAssets(model);
  clf.classify(cells); // warm-up
  final sw = Stopwatch()..start();
  const runs = 5;
  for (var i = 0; i < runs; i++) {
    clf.classify(cells);
  }
  print(
    '64 squares (one board): ${sw.elapsedMilliseconds / runs} ms per board',
  );
}
