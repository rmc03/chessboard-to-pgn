// Same cases as prototype/tests/test_fen.py: the Dart rules must behave like the Python reference.
import 'dart:typed_data';

import 'package:chessboard_pgn/src/chess.dart';
import 'package:flutter_test/flutter_test.dart';

const sample = '4r1k1/1p3ppp/1qn5/3p4/Q3n3/1NP5/PP3PPP/R4BK1';

/// One-hot-ish probabilities (0.95 on [grid]) for 64 squares.
Float32List onehot(List<int> grid, {double p = 0.95}) {
  final out = Float32List(64 * 13);
  for (var sq = 0; sq < 64; sq++) {
    for (var c = 0; c < 13; c++) {
      out[sq * 13 + c] = c == grid[sq] ? p : (1 - p) / 12;
    }
  }
  return out;
}

void setSquare(Float32List probs, int sq, Map<int, double> values) {
  for (var c = 0; c < 13; c++) {
    probs[sq * 13 + c] = values[c] ?? 0.001;
  }
}

void main() {
  test('placement round trip', () {
    expect(gridToPlacement(placementToGrid(sample)), sample);
    expect(gridToPlacement(List<int>.filled(64, 0)), '8/8/8/8/8/8/8/8');
  });

  test('decode of a clean board is the identity', () {
    final grid = placementToGrid(sample);
    final d = decode(onehot(grid));
    expect(d.grid, grid);
    expect(d.confidence.reduce((a, b) => a < b ? a : b), greaterThan(0.9));
  });

  test('decode adds a missing king on the most likely square', () {
    final grid = placementToGrid(sample);
    final blackKingSquare = grid.indexOf(blackKing);
    final probs = onehot(grid);
    setSquare(probs, blackKingSquare, {
      8: 0.60,
      blackKing: 0.30,
    }); // knight first, king second
    expect(decode(probs).grid[blackKingSquare], blackKing);
  });

  test('decode keeps one king per colour and no back-rank pawns', () {
    final grid = List<int>.filled(64, 0)
      ..[60] = whiteKing
      ..[4] = blackKing;
    final probs = onehot(grid);
    setSquare(probs, 10, {whiteKing: 0.95}); // a second "white king"
    setSquare(probs, 2, {whitePawn: 0.95}); // a pawn on rank 8
    final d = decode(probs);
    expect(d.grid.where((k) => k == whiteKing).length, 1);
    expect(d.grid.where((k) => k == blackKing).length, 1);
    expect(d.grid[2] == whitePawn || d.grid[2] == blackPawn, isFalse);
  });

  test('castling guess and turn', () {
    expect(guessCastling('r3k2r/8/8/8/8/8/8/R3K2R'), 'KQkq');
    expect(guessCastling(sample), '-');
    expect(
      suggestTurn('4k3/8/8/8/8/8/8/4K2r'),
      'w',
    ); // white king attacked -> white to move
    expect(
      suggestTurn(sample),
      isNull,
    ); // nobody in check: a picture cannot tell
  });

  test('check detection covers knights, pawns, bishops and blocked lines', () {
    bool blackInCheck(String p) =>
        kingInCheck(placementToGrid(p), white: false);
    bool whiteInCheck(String p) => kingInCheck(placementToGrid(p), white: true);
    expect(
      blackInCheck('4k3/8/8/3N4/8/8/8/4K3'),
      isFalse,
    ); // knight d5 attacks c7/e7, not e8
    expect(
      blackInCheck('4k3/2N5/8/8/8/8/8/4K3'),
      isTrue,
    ); // knight c7 attacks e8
    expect(
      whiteInCheck('8/8/8/8/8/3p4/4K3/8'),
      isTrue,
    ); // black pawn d3 attacks e2 (and c2)
    expect(
      whiteInCheck('8/8/8/8/8/4p3/4K3/8'),
      isFalse,
    ); // a pawn straight ahead attacks nothing
    expect(
      blackInCheck('4k3/8/8/8/B7/8/8/4K3'),
      isTrue,
    ); // bishop a4: a4-b5-c6-d7-e8
    expect(
      blackInCheck('4k3/3p4/8/8/B7/8/8/4K3'),
      isFalse,
    ); // blocked by the pawn on d7
    expect(
      blackInCheck('4k3/8/8/8/8/8/8/4RK2'),
      isTrue,
    ); // rook on the open e-file
    expect(blackInCheck('4k3/4p3/8/8/8/8/8/4RK2'), isFalse); // blocked
  });

  test('PGN is position-only with SetUp and FEN', () {
    final fen = toFen(sample, turn: 'b');
    expect(fen, '$sample b - - 0 1');
    final pgn = toPgn(fen);
    expect(pgn, contains('[SetUp "1"]'));
    expect(pgn, contains('[FEN "$fen"]'));
    expect(pgn.trim().endsWith('*'), isTrue);
    expect(pgn.contains('1.'), isFalse);
  });

  test('validate reports illegal positions', () {
    expect(validate(toFen(sample, turn: 'w')), isEmpty);
    expect(
      validate('8/8/8/8/8/8/8/4K3 w - - 0 1'),
      contains('falta el rey negro'),
    );
    expect(
      validate('4k3/8/8/8/8/8/8/4K2r w - - 0 1'),
      isEmpty,
    ); // white in check and to move: fine
    expect(
      validate('4k3/8/8/8/8/8/8/4K2r b - - 0 1'),
      contains('el bando que no mueve está en jaque'),
    );
  });
}
