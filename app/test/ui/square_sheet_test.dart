// The square editor sheet: Original | Leído tiles, "Volver a lo leído", the answer buttons and plain piece tiles.
import 'package:chessboard_pgn/src/pipeline.dart';
import 'package:chessboard_pgn/src/ui/board.dart';
import 'package:chessboard_pgn/src/ui/diagram_block.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'home_harness.dart';

Future<Home> _home(
  WidgetTester tester,
  List<RecognizedBoard> boards, {
  Size size = const Size(480, 2400),
}) async {
  final home = Home(sessionWith({1: () => boards}));
  await home.pump(tester, size: size);
  await home.addCapture(tester);
  return home;
}

OverflowBox _shifted(WidgetTester tester) => tester.widget<OverflowBox>(
  find.descendant(
    of: find.byKey(const ValueKey('tile-original')),
    matching: find.byType(OverflowBox),
  ),
);

void main() {
  setUpAll(loadRealFonts);

  group('Original | Leído tiles', () {
    testWidgets(
      'two 56 dp tiles with captions: the original cut at the square, and what was read',
      (tester) async {
        await _home(tester, [
          board(middlegame, crop: true, confidence: {18: 0.5}),
        ]);
        await tester.tap(square(18)); // c6, a black knight
        await tester.pumpAndSettle();
        expect(find.text('Original'), findsWidgets);
        expect(find.text('Leído'), findsWidgets);
        final original = find.byKey(const ValueKey('tile-original'));
        final read = find.byKey(const ValueKey('tile-read'));
        expect(tester.getSize(original), const Size(56, 56));
        expect(tester.getSize(read), const Size(56, 56));
        // captions under the tiles
        final sheet = find.byType(BottomSheet);
        expect(
          find.descendant(of: sheet, matching: find.text('Original')),
          findsOneWidget,
        );
        expect(
          tester
              .getTopLeft(
                find.descendant(of: sheet, matching: find.text('Original')),
              )
              .dy,
          greaterThan(tester.getBottomLeft(original).dy - 1),
        );
        // c6 is row 2, column 2 of the picture: the crop is drawn 8x and shifted by that fraction
        final box = _shifted(tester);
        expect(box.maxWidth, 56 * 8);
        expect(box.alignment, Alignment(-1 + 2 * 2 / 7, -1 + 2 * 2 / 7));
        expect(tester.widget<PieceTile>(read).cls, 8);
      },
    );

    testWidgets('seen from Black the picture is mirrored: row and column', (
      tester,
    ) async {
      final home = await _home(tester, [board(middlegame, crop: true)]);
      home.session.diagrams.single.rotate180();
      await tester.pumpAndSettle();
      // the drawn board has Black at the bottom now; a1..h8 are mirrored, the index c6 (18) sits at 63 - 18
      await tester.tap(square(18));
      await tester.pumpAndSettle();
      final box = _shifted(tester);
      const i = 63 - 18;
      expect(
        box.alignment,
        Alignment(-1 + 2 * (i % 8) / 7, -1 + 2 * (i ~/ 8) / 7),
      );
    });

    testWidgets('hidden without an original crop', (tester) async {
      await _home(tester, [board(middlegame)]);
      await tester.tap(square(18));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('tile-original')), findsNothing);
      expect(find.byKey(const ValueKey('tile-read')), findsNothing);
      expect(find.text('Se leyó: caballo negro'), findsOneWidget);
    });

    testWidgets('an empty square shows an empty tile', (tester) async {
      await _home(tester, [board(middlegame, crop: true)]);
      await tester.tap(square(17)); // b6 is empty
      await tester.pumpAndSettle();
      expect(
        tester.widget<PieceTile>(find.byKey(const ValueKey('tile-read'))).cls,
        0,
      );
    });
  });

  group('Volver a lo leído', () {
    testWidgets(
      'appears only once the square differs from the reading, and restores it',
      (tester) async {
        final home = await _home(tester, [board(middlegame)]);
        final d = home.session.diagrams.single;
        await tester.tap(square(21)); // f6, black knight
        await tester.pumpAndSettle();
        expect(find.text('Volver a lo leído'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('pick-2'))); // white knight
        await tester.pumpAndSettle();
        expect(d.grid[21], 2);

        await tester.tap(square(21));
        await tester.pumpAndSettle();
        expect(find.text('Se leyó: caballo negro'), findsOneWidget);
        expect(find.text('Volver a lo leído'), findsOneWidget);
        await tester.tap(find.text('Volver a lo leído'));
        await tester.pumpAndSettle();
        expect(d.grid[21], 8);
        expect(find.byType(BottomSheet), findsNothing);
        expect(d.changedFromRead(21), isFalse);
      },
    );
  });

  group('answers', () {
    testWidgets(
      'a doubtful empty square has one filled "Está vacía", no "Vacía"',
      (tester) async {
        final home = await _home(tester, [
          board(middlegame, confidence: {17: 0.4}),
        ]);
        await tester.tap(square(17));
        await tester.pumpAndSettle();
        expect(find.text('Está vacía'), findsOneWidget);
        expect(find.byKey(const ValueKey('pick-0')), findsNothing);
        expect(find.text('Vacía'), findsNothing);
        expect(find.byType(OutlinedButton), findsNothing);
        expect(
          find.ancestor(
            of: find.text('Está vacía'),
            matching: find.byType(FilledButton),
          ),
          findsOneWidget,
        );
        await tester.tap(find.text('Está vacía'));
        await tester.pumpAndSettle();
        expect(home.session.diagrams.single.isDoubtful(17), isFalse);
        expect(home.session.diagrams.single.grid[17], 0);
      },
    );

    testWidgets('a doubtful piece keeps "Vacía" and "Está bien"', (
      tester,
    ) async {
      await _home(tester, [
        board(middlegame, confidence: {21: 0.4}),
      ]);
      await tester.tap(square(21));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('pick-0')), findsOneWidget);
      expect(find.text('Vacía'), findsOneWidget);
      expect(find.text('Está bien'), findsOneWidget);
      expect(find.text('Está vacía'), findsNothing);
    });

    testWidgets('a trusted square only has "Vacía"', (tester) async {
      await _home(tester, [board(middlegame)]);
      await tester.tap(square(21));
      await tester.pumpAndSettle();
      expect(find.text('Vacía'), findsOneWidget);
      expect(find.text('Está bien'), findsNothing);
      expect(find.text('Está vacía'), findsNothing);
    });

    testWidgets('all the piece tiles sit on the same (light) square colour', (
      tester,
    ) async {
      await _home(tester, [board(middlegame)]);
      await tester.tap(square(21));
      await tester.pumpAndSettle();
      final tiles = tester
          .widgetList<PieceTile>(
            find.descendant(
              of: find.byType(BottomSheet),
              matching: find.byType(PieceTile),
            ),
          )
          .toList();
      expect(tiles, hasLength(12));
      expect(tiles.every((t) => !t.dark), isTrue);
    });
  });

  testWidgets(
    'the review sheet keeps the board visible above it and the title reads "Casilla c6" + "Dudosa 1 de 2"',
    (tester) async {
      await _home(tester, [
        board(middlegame, crop: true, confidence: {18: 0.5, 21: 0.5}),
      ], size: const Size(412, 915));
      await tester.tap(find.byKey(const ValueKey('review-doubtful')));
      await tester.pumpAndSettle();
      expect(find.text('Casilla c6'), findsOneWidget);
      expect(find.text('Dudosa 1 de 2'), findsOneWidget);
      final sheetTop = tester.getTopLeft(find.byType(BottomSheet)).dy;
      final boardRect = tester.getRect(find.byType(BoardView).first);
      expect(
        boardRect.bottom,
        lessThanOrEqualTo(sheetTop),
        reason: 'board above the sheet: ${boardRect.bottom} vs $sheetTop',
      );
      expect(boardRect.top, greaterThanOrEqualTo(0));
      expect(find.byType(DiagramBlock), findsOneWidget);
    },
  );

  testWidgets('the sheet fits at 360 dp and 1.3x text', (tester) async {
    final home = Home(
      sessionWith({
        1: () => [
          board(middlegame, crop: true, confidence: {18: 0.5}),
        ],
      }),
    );
    await home.pump(tester, size: const Size(360, 780), textScale: 1.3);
    await home.addCapture(tester);
    await tester.tap(find.byKey(const ValueKey('review-doubtful')));
    await tester.pumpAndSettle();
    expect(find.text('Dudosa 1 de 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
