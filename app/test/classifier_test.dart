// The pure-Dart forward pass must reproduce the real TFLite model (golden data from export_dart.py).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chessboard_pgn/src/chess.dart';
import 'package:chessboard_pgn/src/classifier.dart';
import 'package:flutter_test/flutter_test.dart';

ModelAssets loadModel() => ModelAssets(
  File('assets/model/manifest.json').readAsStringSync(),
  File('assets/model/weights.bin').readAsBytesSync(),
);

void main() {
  test('forward pass matches the TFLite golden output', () {
    final cellsU8 = File('test/fixtures/golden_cells.bin').readAsBytesSync();
    final golden =
        (jsonDecode(File('test/fixtures/golden_probs.json').readAsStringSync())
                as List)
            .map(
              (row) =>
                  (row as List).cast<num>().map((v) => v.toDouble()).toList(),
            )
            .toList();
    final cells = Float32List(cellsU8.length);
    for (var i = 0; i < cellsU8.length; i++) {
      cells[i] = cellsU8[i] / 255.0;
    }
    final sw = Stopwatch()..start();
    final probs = SquareClassifier.fromAssets(loadModel()).classify(cells);
    // ignore: avoid_print
    print(
      '64 squares classified in ${sw.elapsedMilliseconds} ms (JIT, debug test run)',
    );

    var worst = 0.0;
    for (var sq = 0; sq < 64; sq++) {
      var best = 0, goldBest = 0;
      for (var c = 0; c < 13; c++) {
        worst = [
          worst,
          (probs[sq * 13 + c] - golden[sq][c]).abs(),
        ].reduce((a, b) => a > b ? a : b);
        if (probs[sq * 13 + c] > probs[sq * 13 + best]) best = c;
        if (golden[sq][c] > golden[sq][goldBest]) goldBest = c;
      }
      expect(
        best,
        goldBest,
        reason:
            'square $sq: ${classSymbols[best]} vs ${classSymbols[goldBest]}',
      );
    }
    expect(
      worst,
      lessThan(0.05),
    ); // TFLite also quantises activations: ambiguous squares differ by ~1e-2
    // ignore: avoid_print
    print('max |prob diff| vs TFLite: ${worst.toStringAsFixed(5)}');
  });
}
