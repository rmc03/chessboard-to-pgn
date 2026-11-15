import 'dart:typed_data';

import 'package:chessboard_pgn/src/chess.dart';
import 'package:chessboard_pgn/src/diagram.dart';
import 'package:flutter_test/flutter_test.dart';

const sample = '4r1k1/1p3ppp/1qn5/3p4/Q3n3/1NP5/PP3PPP/R4BK1';
const startPlacement = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR';

/// Index of a square from its name ("e4").
int sq(String name) =>
    (8 - int.parse(name[1])) * 8 + 'abcdefgh'.indexOf(name[0]);

void main() {
  group('castling', () {
    test('possible follows the king and rook placement; FEN uses possible and enabled', () {
      final d = Diagram.fromPlacement(startPlacement);
      expect(d.possibleCastling, CastlingRight.values.toSet());
      expect(d.fen, '$startPlacement w KQkq - 0 1');

      d.setCastlingEnabled(CastlingRight.whiteKingside, false);
      expect(d.isCastlingEnabled(CastlingRight.whiteKingside), isFalse);
      expect(d.activeCastling, {
        CastlingRight.whiteQueenside,
        CastlingRight.blackKingside,
        CastlingRight.blackQueenside,
      });
      expect(d.fen, '$startPlacement w Qkq - 0 1');
    });

    test(
      'a position without king and rook on their squares allows nothing',
      () {
        final d = Diagram.fromPlacement(sample);
        expect(d.possibleCastling, isEmpty);
        expect(d.fen, endsWith(' w - - 0 1'));
      },
    );

    test('editing a square recomputes what is possible; switched-off rights stay off', () {
      final d = Diagram.fromPlacement(startPlacement)
        ..setCastlingEnabled(CastlingRight.blackQueenside, false);
      d.setSquare(sq('h1'), 0); // the white king-side rook leaves
      expect(d.possibleCastling, {
        CastlingRight.whiteQueenside,
        CastlingRight.blackKingside,
        CastlingRight.blackQueenside,
      });
      expect(d.castlingField, 'Qk'); // q is possible but switched off
      d.setSquare(sq('h1'), 4); // rook back
      expect(d.castlingField, 'KQk');
      d.setCastlingEnabled(CastlingRight.blackQueenside, true);
      expect(d.castlingField, 'KQkq');
    });

    test('the legacy on/off switch maps to all rights / none', () {
      final d = Diagram.fromPlacement(startPlacement);
      expect(d.castlingPossible, isTrue);
      d.castlingPossible = false;
      expect(d.fen, '$startPlacement w - - 0 1');
      expect(d.castlingPossible, isFalse);
      d.castlingPossible = true;
      expect(d.fen, '$startPlacement w KQkq - 0 1');
    });
  });

  group('turn', () {
    test('a king in check forces the side to move and says why', () {
      // black king e8 attacked by the rook on e1
      final d = Diagram.fromPlacement('4k3/8/8/8/8/8/8/4R1K1');
      expect(d.turnIsForced, isTrue);
      expect(d.forcedTurn, 'b');
      expect(d.forcedTurnReason, 'El rey negro está en jaque: mueven negras.');
      expect(d.turn, 'b');
      d.turn = 'w'; // ignored while forced
      expect(d.turn, 'b');
      expect(d.fen, contains(' b '));
      expect(d.problems, isEmpty);

      d.setSquare(
        sq('e1'),
        0,
      ); // the check disappears: the stored choice applies again
      expect(d.turnIsForced, isFalse);
      expect(d.forcedTurnReason, isNull);
      expect(d.turn, 'w');
      d.turn = 'b';
      expect(d.fen, contains(' b '));
    });

    test('white in check', () {
      final d = Diagram.fromPlacement('4k3/4r3/8/8/8/8/8/4K3', turn: 'b');
      expect(d.forcedTurn, 'w');
      expect(
        d.forcedTurnReason,
        'El rey blanco está en jaque: mueven blancas.',
      );
      expect(d.turn, 'w');
    });

    test('free turn is whatever the user chose', () {
      final d = Diagram.fromPlacement(sample);
      expect(d.turnIsForced, isFalse);
      d.turn = 'b';
      expect(d.fen, '$sample b - - 0 1');
    });
  });

  group('doubtful squares', () {
    Diagram doubtfulDiagram() {
      final conf = List<double>.filled(64, 0.99);
      for (final i in [3, 17, 40]) {
        conf[i] = 0.4;
      }
      return Diagram(
        grid: placementToGrid(sample),
        confidence: conf,
        turn: 'w',
      );
    }

    test('doubtfulSquares are in index order and counted', () {
      final d = doubtfulDiagram();
      expect(d.doubtfulSquares, [3, 17, 40]);
      expect(d.doubtfulCount, 3);
      expect(d.hasDoubts, isTrue);
    });

    test('nextDoubtfulAfter moves on, wraps, and ends', () {
      final d = doubtfulDiagram();
      expect(d.nextDoubtfulAfter(-1), 3);
      expect(d.nextDoubtfulAfter(3), 17);
      expect(d.nextDoubtfulAfter(20), 40);
      expect(d.nextDoubtfulAfter(40), 3); // wraps
      expect(d.nextDoubtfulAfter(40, wrap: false), isNull);
      d.confirmSquare(3);
      d.confirmSquare(17);
      expect(
        d.nextDoubtfulAfter(40),
        isNull,
      ); // only itself left: nothing else to review
      d.confirmSquare(40);
      expect(d.nextDoubtfulAfter(0), isNull);
    });

    test(
      'confirmSquare trusts the square without changing it and notifies',
      () {
        final d = doubtfulDiagram();
        var notified = 0;
        d.addListener(() => notified++);
        final before = d.grid[17];
        d.confirmSquare(17);
        expect(d.isDoubtful(17), isFalse);
        expect(d.grid[17], before);
        expect(notified, 1);
        d.confirmSquare(17); // already trusted: nothing to say
        expect(notified, 1);
      },
    );

    test('correcting a square also trusts it', () {
      final d = doubtfulDiagram();
      d.setSquare(40, 0);
      expect(d.doubtfulSquares, [3, 17]);
    });
  });

  group('rotate180', () {
    Diagram fromBlackSide() {
      // what the reader returns for a book that prints the diagram from Black's side
      final upside = placementToGrid(sample).reversed.toList();
      final conf = List<double>.filled(64, 1)..[5] = 0.3;
      return Diagram(
        grid: upside,
        confidence: conf,
        turn: 'w',
        originalCrop: Uint8List.fromList([1, 2, 3]),
      );
    }

    test(
      'stores the position from White\'s side and keeps the original crop',
      () {
        final d = fromBlackSide();
        final crop = d.originalCrop;
        expect(d.seenFromBlack, isFalse);
        d.rotate180();
        expect(d.placement, sample);
        expect(d.fen, '$sample w - - 0 1');
        expect(d.seenFromBlack, isTrue);
        expect(d.doubtfulSquares, [
          58,
        ]); // 63 - 5, confidence travels with the piece
        expect(identical(d.originalCrop, crop), isTrue);
      },
    );

    test('twice is the identity', () {
      final d = fromBlackSide();
      final grid = List<int>.of(d.grid);
      final conf = List<double>.of(d.confidence);
      d.rotate180();
      d.rotate180();
      expect(d.grid, grid);
      expect(d.confidence, conf);
      expect(d.seenFromBlack, isFalse);
    });

    test('notifies, and flipSquare is its own inverse', () {
      final d = fromBlackSide();
      var n = 0;
      d.addListener(() => n++);
      d.rotate180();
      expect(n, 1);
      expect(flipSquare(0), 63);
      expect(flipSquare(flipSquare(17)), 17);
    });
  });

  group('labels, status and PGN', () {
    test('squareLabel', () {
      final conf = List<double>.filled(64, 1)..[sq('e4')] = 0.5;
      final d = Diagram(
        grid: placementToGrid(sample),
        confidence: conf,
        turn: 'w',
      );
      expect(d.squareLabel(sq('e4')), 'e4, caballo negro, dudosa');
      expect(d.squareLabel(sq('a4')), 'a4, dama blanca');
      expect(d.squareLabel(sq('h5')), 'h5, vacía');
      d.confirmSquare(sq('e4'));
      expect(d.squareLabel(sq('e4')), 'e4, caballo negro');
    });

    test('status of a clean, a doubtful and an impossible diagram', () {
      final clean = Diagram.fromPlacement(sample).status;
      expect(clean.severity, DiagramSeverity.ok);
      expect(clean.headline, isNull);

      final conf = List<double>.filled(64, 1)
        ..[1] = 0.2
        ..[2] = 0.2;
      final doubtful = Diagram(
        grid: placementToGrid(sample),
        confidence: conf,
        turn: 'w',
      ).status;
      expect(doubtful.severity, DiagramSeverity.doubtful);
      expect(doubtful.doubtfulText, '2 casillas dudosas');
      expect(doubtful.headline, '2 casillas dudosas');
      conf[2] = 1;
      expect(
        Diagram(
          grid: placementToGrid(sample),
          confidence: conf,
          turn: 'w',
        ).status.doubtfulText,
        '1 casilla dudosa',
      );

      final impossible = Diagram.fromPlacement('8/8/8/8/8/8/8/4K3').status;
      expect(impossible.severity, DiagramSeverity.impossible);
      expect(impossible.problems, ['Falta el rey negro.']);
      expect(impossible.headline, 'Posición imposible: falta el rey negro.');
    });

    test('several problems are summarised', () {
      final s = Diagram.fromPlacement('8/8/8/8/8/8/8/8').status;
      expect(s.problems.length, 3);
      expect(s.problemText, startsWith('Posición imposible: '));
      expect(s.problemText, endsWith(' Y 2 más.'));
    });

    test('describeProblem covers every message of validate and degrades gracefully', () {
      for (final p in [
        'tablero vacío',
        'falta el rey blanco',
        'falta el rey negro',
        'hay más de un rey de un color',
        'más de 8 peones blancos',
        'más de 8 peones negros',
        'más de 16 piezas blancas',
        'más de 16 piezas negras',
        'hay un peón en la fila 1 u 8',
        'el bando que no mueve está en jaque',
      ]) {
        final s = describeProblem(p);
        expect(s[0], s[0].toUpperCase(), reason: p);
        expect(s, endsWith('.'), reason: p);
        expect(
          s.toLowerCase(),
          isNot(p),
          reason: 'must be a full sentence: $p',
        );
      }
      expect(describeProblem('algo raro'), 'Algo raro.');
    });

    test('the PGN event reads "Diagrama N"', () {
      final d = Diagram.fromPlacement(sample);
      expect(d.pgn(3), contains('[Event "Diagrama 3"]'));
      expect(d.pgn(3), contains('[FEN "$sample w - - 0 1"]'));
    });
  });

  group('fix round: coloured check problem, read class, warnings', () {
    // Both kings in check: the side that does not move is in check whoever moves.
    const bothInCheck = 'r6k/8/8/8/8/8/8/K6R';

    test('the check problem names the colour that does not move', () {
      const p = 'el bando que no mueve está en jaque';
      expect(
        describeProblem(p, turn: 'w'),
        'Las negras están en jaque y no les toca mover.',
      );
      expect(
        describeProblem(p, turn: 'b'),
        'Las blancas están en jaque y no les toca mover.',
      );
      expect(describeProblem(p), 'El bando que no mueve está en jaque.');

      final d = Diagram.fromPlacement(bothInCheck);
      expect(d.forcedTurn, isNull);
      expect(d.status.problems, [
        'Las negras están en jaque y no les toca mover.',
      ]);
      d.turn = 'b';
      expect(d.status.problems, [
        'Las blancas están en jaque y no les toca mover.',
      ]);
    });

    test(
      '"Cambiar turno" is offered only when switching really fixes the check',
      () {
        // both in check: switching just moves the problem to the other colour
        expect(
          Diagram.fromPlacement(bothInCheck).switchingTurnFixesCheck,
          isFalse,
        );
        // one king in check: the turn is forced and there is nothing to fix
        final forced = Diagram.fromPlacement(
          'r3k2r/ppp2ppp/5n2/1B2p3/4P3/2N2N2/PPPP1PPP/R1BQK2R',
        );
        expect(forced.turnIsForced, isTrue);
        expect(forced.switchingTurnFixesCheck, isFalse);
        // no check problem at all
        expect(Diagram.fromPlacement(sample).switchingTurnFixesCheck, isFalse);
      },
    );

    test(
      'readClass keeps what the reader recognised; restoreRead puts it back',
      () {
        final d = Diagram.fromPlacement(sample);
        final e4 = sq('e4'); // a black knight
        expect(d.readClass(e4), 8);
        expect(d.changedFromRead(e4), isFalse);
        d.setSquare(e4, 0);
        expect(d.readClass(e4), 8);
        expect(d.changedFromRead(e4), isTrue);
        var notified = 0;
        d.addListener(() => notified++);
        d.restoreRead(e4);
        expect(d.grid[e4], 8);
        expect(d.changedFromRead(e4), isFalse);
        expect(d.confidence[e4], 1);
        expect(notified, 1);
      },
    );

    test('restoreRead restores a doubtful read class as trusted and survives rotate180', () {
      final conf = List<double>.filled(64, 1)..[sq('b6')] = 0.4;
      final d = Diagram(
        grid: placementToGrid(sample),
        confidence: conf,
        turn: 'w',
      );
      final b6 = sq('b6'); // black queen
      expect(d.isDoubtful(b6), isTrue);
      d.setSquare(b6, 3);
      d.rotate180();
      // the square is the same board square, now at the mirrored index
      expect(d.readClass(63 - b6), 11);
      expect(d.changedFromRead(63 - b6), isTrue);
      d.restoreRead(63 - b6);
      expect(d.grid[63 - b6], 11);
      expect(d.isDoubtful(63 - b6), isFalse);
      d.rotate180();
      expect(d.grid[b6], 11);
      expect(d.changedFromRead(b6), isFalse);
    });

    test('hasWarnings: doubts or an impossible position', () {
      expect(Diagram.fromPlacement(sample).hasWarnings, isFalse);
      expect(Diagram.fromPlacement('8/8/8/8/8/8/8/4K3').hasWarnings, isTrue);
      final conf = List<double>.filled(64, 1)..[0] = 0.5;
      expect(
        Diagram(
          grid: placementToGrid(sample),
          confidence: conf,
          turn: 'w',
        ).hasWarnings,
        isTrue,
      );
    });
  });
}
