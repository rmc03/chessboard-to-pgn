import 'package:chessboard_pgn/src/chess.dart';
import 'package:chessboard_pgn/src/export.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'lichessAnalysisUri keeps the slashes and turns spaces into underscores',
    () {
      expect(
        lichessAnalysisUri(startFen).toString(),
        'https://lichess.org/analysis/standard/rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR_w_KQkq_-_0_1',
      );
      expect(
        lichessAnalysisUri(
          '4r1k1/1p3ppp/1qn5/3p4/Q3n3/1NP5/PP3PPP/R4BK1 b - - 0 1',
        ).toString(),
        'https://lichess.org/analysis/standard/4r1k1/1p3ppp/1qn5/3p4/Q3n3/1NP5/PP3PPP/R4BK1_b_-_-_0_1',
      );
    },
  );

  test('openInLichess hands the analysis URI to the launcher', () async {
    Uri? opened;
    final ok = await openInLichess(
      startFen,
      open: (uri) async {
        opened = uri;
        return true;
      },
    );
    expect(ok, isTrue);
    expect(opened, lichessAnalysisUri(startFen));
  });

  test('openInLichess returns false when nothing can open it, and when the launcher throws', () async {
    expect(await openInLichess(startFen, open: (_) async => false), isFalse);
    expect(
      await openInLichess(
        startFen,
        open: (_) async => throw PlatformException(code: 'ACTIVITY_NOT_FOUND'),
      ),
      isFalse,
    );
  });

  test(
    'the real launcher does not throw when the plugin is missing (test host)',
    () async {
      expect(await openInLichess(startFen), isFalse);
    },
  );

  test(
    'the export bar and the save snackbar say how many diagrams need a look',
    () {
      expect(diagramsText(1), '1 diagrama');
      expect(diagramsText(3), '3 diagramas');
      expect(warningsText(1), '1 con aviso');
      expect(warningsText(3), '3 con avisos');
      expect(savedMessage('a.pgn'), 'Guardado: a.pgn');
      expect(
        savedMessage('a.pgn', flagged: 3),
        'Guardado: a.pgn · 3 diagramas con avisos',
      );
      expect(
        savedMessage('a.pgn', flagged: 1),
        'Guardado: a.pgn · 1 diagrama con aviso',
      );
    },
  );
}
