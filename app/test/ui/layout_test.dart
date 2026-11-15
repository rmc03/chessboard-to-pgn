// Layout of the session screen: columns by width, block width cap, no overflow at large text, long lists.
import 'package:chessboard_pgn/src/session.dart';
import 'package:chessboard_pgn/src/ui/diagram_block.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'home_harness.dart';

Future<Home> _session(
  WidgetTester tester, {
  required Size size,
  int boards = 6,
  double textScale = 1,
}) async {
  final home = Home(
    sessionWith({
      1: () => [
        for (var i = 0; i < boards; i++)
          switch (i % 3) {
            0 => board(middlegame, confidence: {18: 0.5, 21: 0.5}, crop: true),
            1 => board('8/8/8/8/8/8/8/4K3', confidence: {10: 0.4}),
            _ => board(castlingCheck),
          },
      ],
    }),
  );
  await home.pump(tester, size: size, textScale: textScale);
  await home.addCapture(tester);
  return home;
}

/// Distinct left edges of the blocks that are on screen = number of columns.
int _columns(WidgetTester tester) => {
  for (final e in find.byType(DiagramBlock).evaluate())
    tester.getTopLeft(find.byElementPredicate((x) => x == e)).dx.round(),
}.length;

void main() {
  setUpAll(loadRealFonts);

  for (final (width, columns) in [
    (400.0, 1),
    (599.0, 1),
    (839.0, 1),
    (900.0, 2),
    (1239.0, 2),
    (1300.0, 3),
    (1800.0, 3),
  ]) {
    testWidgets(
      '$width dp wide: $columns column(s) of blocks, none wider than 440 dp',
      (tester) async {
        await _session(tester, size: Size(width, 3000));
        expect(_columns(tester), columns);
        for (final e in find.byType(DiagramBlock).evaluate()) {
          final size = tester.getSize(find.byElementPredicate((x) => x == e));
          expect(size.width, lessThanOrEqualTo(blockMaxWidth + 0.01));
        }
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('blocks of a row have the same height and their boards line up', (
    tester,
  ) async {
    await _session(tester, size: const Size(1300, 3000));
    final blocks = find.byType(DiagramBlock);
    final tops = <double>[],
        heights = <double>[],
        boardTops = <double>[],
        bottoms = <double>[];
    for (var i = 0; i < 3; i++) {
      final b = blocks.at(i);
      tops.add(tester.getTopLeft(b).dy);
      heights.add(tester.getSize(b).height);
      boardTops.add(
        tester
            .getTopLeft(
              find.descendant(
                of: b,
                matching: find.byKey(const ValueKey('square-0')),
              ),
            )
            .dy,
      );
      bottoms.add(
        tester
            .getBottomLeft(
              find.descendant(
                of: b,
                matching: find.byKey(const ValueKey('fen-line')),
              ),
            )
            .dy,
      );
    }
    expect(tops.toSet().length, 1);
    expect(heights.toSet().length, 1, reason: '$heights');
    // header height is fixed, so the boards sit at the same height even when statuses differ
    expect(
      boardTops.map((y) => y.round()).toSet().length,
      2,
      reason: 'one block has no comparator: $boardTops',
    );
    // the FEN lines sit at the bottom of the equal-height blocks
    expect(bottoms.map((y) => y.round()).toSet().length, 1, reason: '$bottoms');
  });

  testWidgets(
    'the last block\'s actions are not covered by the FAB (scroll padding)',
    (tester) async {
      await _session(tester, size: const Size(412, 915));
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, -6000),
        5000,
      );
      await tester.pumpAndSettle();
      final fab = tester.getRect(find.text('Añadir captura'));
      final last = find.byType(DiagramBlock).last;
      final fen = tester.getRect(
        find.descendant(
          of: last,
          matching: find.byKey(const ValueKey('fen-line')),
        ),
      );
      final lichess = tester.getRect(
        find.descendant(of: last, matching: find.text('Analizar en Lichess')),
      );
      expect(fab.overlaps(fen), isFalse);
      expect(fab.overlaps(lichess), isFalse);
    },
  );

  testWidgets(
    'no overflow at text scale 1.3 on a 360 dp phone, anywhere in the list',
    (tester) async {
      await _session(
        tester,
        size: const Size(360, 780),
        textScale: 1.3,
        boards: 3,
      );
      expect(tester.takeException(), isNull);
      final scroll = find.byType(CustomScrollView);
      for (var i = 0; i < 14; i++) {
        await tester.drag(scroll, const Offset(0, -700));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull, reason: 'after scroll $i');
      }
      await tester.pumpAndSettle();
      // the export bar wraps instead of clipping: both its parts are fully visible
      expect(find.text('3 diagramas'), findsOneWidget);
      expect(find.text('Guardar .pgn'), findsOneWidget);
      final bar = tester.getRect(find.text('Guardar .pgn'));
      expect(bar.right, lessThanOrEqualTo(360));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the same at 360 dp with the sheet open', (tester) async {
    await _session(
      tester,
      size: const Size(360, 780),
      textScale: 1.3,
      boards: 3,
    );
    await tester.tap(find.byKey(const ValueKey('review-doubtful')).first);
    await tester.pumpAndSettle();
    expect(find.text('Dudosa 1 de 2'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a long session builds lazily and scrolls', (tester) async {
    final home = await _session(tester, size: const Size(412, 915), boards: 24);
    expect(home.session.diagramCount, 24);
    expect(
      find.byType(DiagramBlock).evaluate().length,
      lessThan(8),
      reason: 'only what is near the screen is built',
    );
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -3000),
      3000,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('24 diagramas'), findsOneWidget);
  });

  testWidgets(
    'the empty state is two columns on a wide window and one on a phone',
    (tester) async {
      final wide = Home(sessionWith({}));
      await wide.pump(tester, size: const Size(1280, 800));
      final example = tester.getTopLeft(
        find.bySemanticsLabel(
          'Ejemplo de diagrama leído, con dos casillas dudosas',
        ),
      );
      final button = tester.getTopLeft(find.text('Elegir captura'));
      expect(
        button.dx,
        greaterThan(example.dx + 400),
        reason: 'steps and action sit to the right of the example',
      );
      expect(tester.takeException(), isNull);

      final phone = Home(sessionWith({}));
      await phone.pump(tester, size: const Size(360, 640), textScale: 1.3);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('skeletons stand still when the system removes animations', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    final gate = Gate();
    final home = Home(
      Session(readImage: gate.reader([board(endgame), board(middlegame)])),
    );
    await home.pump(tester);
    home.picks.add(Uint8List.fromList([1]));
    await tester.tap(find.text('Elegir captura'));
    await tester.pump(const Duration(milliseconds: 50));
    gate.found.complete();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(DiagramSkeleton), findsNWidgets(2));
    double opacity() => tester
        .widget<FadeTransition>(
          find
              .descendant(
                of: find.byType(DiagramSkeleton),
                matching: find.byType(FadeTransition),
              )
              .first,
        )
        .opacity
        .value;
    final a = opacity();
    await tester.pump(const Duration(milliseconds: 500));
    expect(opacity(), a);
    expect(a, 1);
  });

  testWidgets('skeletons pulse normally', (tester) async {
    final gate = Gate();
    final home = Home(
      Session(readImage: gate.reader([board(endgame), board(middlegame)])),
    );
    await home.pump(tester);
    home.picks.add(Uint8List.fromList([1]));
    await tester.tap(find.text('Elegir captura'));
    await tester.pump(const Duration(milliseconds: 50));
    gate.found.complete();
    await tester.pump(const Duration(milliseconds: 50));
    double opacity() => tester
        .widget<FadeTransition>(
          find
              .descendant(
                of: find.byType(DiagramSkeleton),
                matching: find.byType(FadeTransition),
              )
              .first,
        )
        .opacity
        .value;
    final a = opacity();
    await tester.pump(const Duration(milliseconds: 500));
    expect(opacity(), isNot(a));
  });
}
