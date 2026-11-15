// The diagram block and the square editor: editing, confirming, the review flow, turn, castling, the
// Leído | Original comparator, orientation, deleting with undo, Lichess.
import 'package:chessboard_pgn/src/export.dart';
import 'package:chessboard_pgn/src/pipeline.dart';
import 'package:chessboard_pgn/src/locate.dart';
import 'package:chessboard_pgn/src/session.dart';
import 'package:chessboard_pgn/src/ui/board.dart';
import 'package:chessboard_pgn/src/ui/diagram_block.dart';
import 'package:chessboard_pgn/src/ui/icons.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'home_harness.dart';

Finder inFirstBlock(Finder f) =>
    find.descendant(of: find.byType(DiagramBlock).first, matching: f);

/// Walks the Tab order until the focus is on the icon button with [tooltip], then presses Enter on it.
Future<void> pressByKeyboard(WidgetTester tester, String tooltip) async {
  for (var i = 0; i < 120; i++) {
    final focused = FocusManager.instance.primaryFocus?.context;
    final button = focused?.findAncestorWidgetOfExactType<IconButton>();
    if (button?.tooltip == tooltip) {
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      return;
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
  }
  fail('the Tab order never reached "$tooltip"');
}

Future<Home> _home(
  WidgetTester tester,
  List<RecognizedBoard> boards, {
  Size size = const Size(480, 2400),
  bool canShare = true,
}) async {
  final home = Home(sessionWith({1: () => boards}));
  await home.pump(tester, size: size, canShare: canShare);
  await home.addCapture(tester);
  return home;
}

void main() {
  setUpAll(loadRealFonts);

  group('editing squares', () {
    testWidgets(
      'a tap opens the sheet; one pick applies, closes and changes the FEN',
      (tester) async {
        final home = await _home(tester, [board(middlegame)]);
        final d = home.session.diagrams.single;
        final before = d.fen;
        expect(d.grid[17], 0); // b6 is empty

        await tester.tap(square(17));
        await tester.pumpAndSettle();
        expect(find.text('Casilla b6'), findsOneWidget);
        expect(find.text('Se leyó: vacía'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('confirm-square')),
          findsNothing,
          reason: 'b6 is not doubtful',
        );
        expect(find.byType(BottomSheet), findsOneWidget);

        await tester.tap(find.byKey(const ValueKey('pick-11'))); // black queen
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        expect(d.grid[17], 11);
        expect(d.fen, isNot(before));
        expect(d.fen.split(' ').first.split('/')[2], contains('q'));
        expect(find.textContaining('q'), findsWidgets); // the FEN line shows it
      },
    );

    testWidgets(
      'the sheet marks the current piece as selected and offers every class',
      (tester) async {
        await _home(tester, [board(middlegame)]);
        await tester.tap(square(21)); // f6 holds a black knight (class 8)
        await tester.pumpAndSettle();
        for (var cls = 0; cls <= 12; cls++) {
          expect(
            find.byKey(ValueKey('pick-$cls')),
            findsOneWidget,
            reason: 'pick-$cls',
          );
        }
        final selected = find.byWidgetPredicate(
          (w) => w is PieceTile && w.selected,
        );
        expect(selected, findsOneWidget);
        expect(tester.widget<PieceTile>(selected).cls, 8);
      },
    );

    testWidgets('"Vacía" empties the square', (tester) async {
      final home = await _home(tester, [board(middlegame)]);
      await tester.tap(square(21));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pick-0')));
      await tester.pumpAndSettle();
      expect(home.session.diagrams.single.grid[21], 0);
    });

    testWidgets(
      '"Está bien" confirms a doubtful square without changing the piece',
      (tester) async {
        final home = await _home(tester, [
          board(middlegame, confidence: {21: 0.5}),
        ]);
        final d = home.session.diagrams.single;
        expect(find.text('1 casilla dudosa'), findsOneWidget);
        await tester.tap(square(21));
        await tester.pumpAndSettle();
        expect(find.text('Está bien'), findsOneWidget);
        await tester.tap(find.text('Está bien'));
        await tester.pumpAndSettle();
        expect(d.isDoubtful(21), isFalse);
        expect(d.grid[21], 8);
        expect(find.text('1 casilla dudosa'), findsNothing);
        expect(find.byType(BottomSheet), findsNothing);
      },
    );

    testWidgets('Esc closes the sheet', (tester) async {
      await _home(tester, [board(middlegame)]);
      await tester.tap(square(17));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets(
      '"Revisar dudosas" walks every doubtful square and ends with a snackbar',
      (tester) async {
        final home = await _home(tester, [
          board(middlegame, confidence: {18: 0.6, 21: 0.5, 40: 0.7}),
        ]);
        final d = home.session.diagrams.single;
        BoardView boardView() =>
            tester.widget<BoardView>(find.byType(BoardView).first);

        await tester.tap(find.byKey(const ValueKey('review-doubtful')));
        await tester.pumpAndSettle();
        expect(find.text('Casilla c6'), findsOneWidget);
        expect(find.text('Dudosa 1 de 3'), findsOneWidget);
        expect(
          boardView().selected,
          18,
          reason: 'the square under review is marked on the board',
        );

        await tester.tap(find.text('Está bien'));
        await tester.pumpAndSettle();
        expect(find.text('Casilla f6'), findsOneWidget);
        expect(find.text('Dudosa 2 de 3'), findsOneWidget);
        expect(boardView().selected, 21);

        // fixing it with a piece also moves on
        await tester.tap(find.byKey(const ValueKey('pick-2')));
        await tester.pumpAndSettle();
        expect(d.grid[21], 2);
        expect(find.text('Casilla a3'), findsOneWidget);
        expect(find.text('Dudosa 3 de 3'), findsOneWidget);

        // a3 is empty: the only answer offered is a single "Está vacía"
        expect(find.byKey(const ValueKey('pick-0')), findsNothing);
        expect(find.text('Está bien'), findsNothing);
        await tester.tap(find.text('Está vacía'));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        expect(d.doubtfulCount, 0);
        expect(find.text('Todas las casillas revisadas'), findsOneWidget);
        expect(boardView().selected, isNull);
      },
    );

    testWidgets('dismissing the review stops it and keeps what was answered', (
      tester,
    ) async {
      final home = await _home(tester, [
        board(middlegame, confidence: {18: 0.6, 21: 0.5}),
      ]);
      await tester.tap(find.byKey(const ValueKey('review-doubtful')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Está bien'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(home.session.diagrams.single.doubtfulSquares, [21]);
      expect(find.text('Todas las casillas revisadas'), findsNothing);
    });
  });

  group('turn and castling', () {
    testWidgets('the caption control sets the side to move', (tester) async {
      final home = await _home(tester, [board(endgame)]);
      final d = home.session.diagrams.single;
      expect(d.turn, 'w');
      await tester.tap(find.text('Mueven negras'));
      await tester.pump();
      expect(d.turn, 'b');
      expect(d.fen.split(' ')[1], 'b');
      await tester.tap(find.text('Mueven blancas'));
      await tester.pump();
      expect(d.turn, 'w');
    });

    testWidgets('a forced turn is locked and explained in one line', (
      tester,
    ) async {
      final home = await _home(tester, [board(castlingCheck)]);
      final d = home.session.diagrams.single;
      expect(d.forcedTurn, 'b');
      expect(
        find.text('El rey negro está en jaque: mueven negras.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Mueven blancas'), warnIfMissed: false);
      await tester.pump();
      expect(d.turn, 'b');
      final segments = tester.widget<SegmentedButton<String>>(
        find.byType(SegmentedButton<String>),
      );
      expect(
        segments.segments.firstWhere((s) => s.value == 'w').enabled,
        isFalse,
      );
      expect(
        segments.segments.firstWhere((s) => s.value == 'b').enabled,
        isTrue,
      );
    });

    testWidgets('no reason line when the turn is free', (tester) async {
      await _home(tester, [board(endgame)]);
      expect(find.textContaining('está en jaque'), findsNothing);
    });

    testWidgets('chips exist only for the possible rights and change the FEN', (
      tester,
    ) async {
      final home = await _home(tester, [board(castlingCheck)]);
      final d = home.session.diagrams.single;
      for (final label in [
        'Blancas O-O',
        'Blancas O-O-O',
        'Negras O-O',
        'Negras O-O-O',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(d.fen.split(' ')[2], 'KQkq');
      await tester.tap(find.text('Blancas O-O'));
      await tester.pump();
      expect(d.fen.split(' ')[2], 'Qkq');
      await tester.tap(find.text('Negras O-O-O'));
      await tester.pump();
      expect(d.fen.split(' ')[2], 'Qk');
      await tester.tap(find.text('Blancas O-O'));
      await tester.pump();
      expect(d.fen.split(' ')[2], 'KQk');
    });

    testWidgets('no chip row when no castling is possible', (tester) async {
      await _home(tester, [board(endgame)]);
      expect(find.byType(FilterChip), findsNothing);
    });

    testWidgets(
      'editing a square updates the chips (a king that leaves loses its rights)',
      (tester) async {
        final home = await _home(tester, [board(castlingCheck)]);
        expect(find.byType(FilterChip), findsNWidgets(4));
        // e1 is square 60: empty it
        await tester.tap(square(60));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('pick-0')));
        await tester.pumpAndSettle();
        expect(find.text('Blancas O-O'), findsNothing);
        expect(home.session.diagrams.single.fen.split(' ')[2], 'kq');
      },
    );
  });

  group('Leído | Original', () {
    double overlay(WidgetTester tester) => tester
        .widget<AnimatedOpacity>(find.byKey(const ValueKey('original-overlay')))
        .opacity;

    testWidgets('hidden when there is no original crop', (tester) async {
      await _home(tester, [board(endgame)]);
      expect(find.text('Original'), findsNothing);
      expect(find.byKey(const ValueKey('original-overlay')), findsNothing);
    });

    testWidgets(
      'Original fades the crop in over exactly the squares of the board',
      (tester) async {
        await _home(tester, [board(middlegame, crop: true)]);
        expect(overlay(tester), 0);
        final blockHeight = tester.getSize(find.byType(DiagramBlock)).height;

        await tester.tap(find.text('Original'));
        await tester.pump(const Duration(milliseconds: 80));
        final mid = overlay(tester);
        expect(
          mid,
          1,
          reason:
              'the target opacity is set at once; the animation takes 150 ms',
        );
        await tester.pumpAndSettle();

        // the picture covers the board's 8x8 squares (not the coordinate gutter), square for square
        final boardBox = tester.getRect(find.byType(BoardView).first);
        final layout = BoardLayout(boardBox.width, coordinates: true);
        final squares = layout.boardRect;
        final image = tester.getRect(
          find.descendant(
            of: find.byKey(const ValueKey('original-overlay')),
            matching: find.byType(Image),
          ),
        );
        expect(image.left, closeTo(boardBox.left + squares.left, 0.5));
        expect(image.top, closeTo(boardBox.top + squares.top, 0.5));
        expect(image.width, closeTo(layout.board, 0.5));
        expect(image.height, closeTo(layout.board, 0.5));

        expect(
          tester.getSize(find.byType(DiagramBlock)).height,
          blockHeight,
          reason: 'no jump when switching',
        );
        await tester.tap(find.text('Leído'));
        await tester.pumpAndSettle();
        expect(overlay(tester), 0);
        expect(tester.getSize(find.byType(DiagramBlock)).height, blockHeight);
      },
    );

    testWidgets('with "remove animations" the switch is instant', (
      tester,
    ) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await _home(tester, [board(middlegame, crop: true)]);
      await tester.tap(find.text('Original'));
      await tester.pump();
      expect(
        tester
            .widget<AnimatedOpacity>(
              find.byKey(const ValueKey('original-overlay')),
            )
            .duration,
        Duration.zero,
      );
    });

    testWidgets(
      'press and hold peeks at the original and never edits a square',
      (tester) async {
        final home = await _home(tester, [board(middlegame, crop: true)]);
        final target = tester.getCenter(square(27));
        final g = await tester.startGesture(target);
        await tester.pump(const Duration(milliseconds: 700));
        expect(overlay(tester), 1);
        await g.up();
        await tester.pumpAndSettle();
        expect(overlay(tester), 0);
        expect(
          find.byType(BottomSheet),
          findsNothing,
          reason: 'a hold is not a tap',
        );
        expect(home.session.diagrams.single.grid[27], 0);

        // a plain tap still edits
        await tester.tap(square(27));
        await tester.pumpAndSettle();
        expect(find.text('Casilla d5'), findsOneWidget);
      },
    );
  });

  group('orientation', () {
    testWidgets(
      '"Ver desde las negras" rotates the reading and draws Black at the bottom; again undoes it',
      (tester) async {
        final home = await _home(tester, [board(middlegame)]);
        final d = home.session.diagrams.single;
        final before = d.fen;
        final grid = List<int>.of(d.grid);
        expect(
          tester.widget<BoardView>(find.byType(BoardView).first).blackAtBottom,
          isFalse,
        );
        IconButton flip() =>
            tester.widget<IconButton>(find.byKey(const ValueKey('flip')));
        expect(flip().isSelected, isFalse);

        await tester.tap(find.byTooltip('Ver desde las negras'));
        await tester.pumpAndSettle();
        expect(d.seenFromBlack, isTrue);
        expect(d.grid, grid.reversed.toList());
        expect(
          tester.widget<BoardView>(find.byType(BoardView).first).blackAtBottom,
          isTrue,
        );
        expect(flip().isSelected, isTrue);

        await tester.tap(find.byTooltip('Ver desde las blancas'));
        await tester.pumpAndSettle();
        expect(d.fen, before);
        expect(
          tester.widget<BoardView>(find.byType(BoardView).first).blackAtBottom,
          isFalse,
        );
        expect(flip().isSelected, isFalse);
      },
    );

    testWidgets('the toggle works from the keyboard', (tester) async {
      final home = await _home(tester, [board(middlegame)]);
      await pressByKeyboard(tester, 'Ver desde las negras');
      expect(home.session.diagrams.single.seenFromBlack, isTrue);
    });
  });

  group('actions of the block (no overflow menu)', () {
    testWidgets('Copiar PGN copies this diagram with its number (Windows)', (
      tester,
    ) async {
      final home = await _home(tester, [
        board(middlegame),
        board(endgame),
      ], canShare: false);
      expect(find.byTooltip('Compartir o copiar PGN'), findsNothing);
      await tester.tap(find.byTooltip('Copiar PGN').first);
      await tester.pumpAndSettle();
      expect(home.clipboard, home.session.pgnOf(home.session.diagrams.first));
      expect(home.clipboard, contains('[Event "Diagrama 1"]'));
      expect(find.text('PGN copiado'), findsOneWidget);
    });

    testWidgets(
      'Android: the share icon opens a sheet with the three ways out',
      (tester) async {
        final home = await _home(tester, [board(middlegame), board(endgame)]);
        expect(find.byTooltip('Copiar PGN'), findsNothing);
        await tester.tap(find.byTooltip('Compartir o copiar PGN').first);
        await tester.pumpAndSettle();
        expect(find.text('Copiar PGN'), findsOneWidget);
        expect(find.text('Compartir como texto'), findsOneWidget);
        expect(find.text('Compartir como archivo .pgn'), findsOneWidget);
        await tester.tap(find.text('Compartir como texto'));
        await tester.pumpAndSettle();
        expect(
          home.sharedText.single,
          home.session.pgnOf(home.session.diagrams.first),
        );
        expect(home.sharedText.single, isNot(home.session.allPgn));

        await tester.tap(find.byTooltip('Compartir o copiar PGN').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Compartir como archivo .pgn'));
        await tester.pumpAndSettle();
        expect(
          String.fromCharCodes(home.sharedFiles.single.$2),
          home.session.pgnOf(home.session.diagrams.first),
        );

        await tester.tap(find.byTooltip('Compartir o copiar PGN').first);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Copiar PGN'));
        await tester.pumpAndSettle();
        expect(home.clipboard, home.session.pgnOf(home.session.diagrams.first));
        expect(find.text('PGN copiado'), findsOneWidget);
      },
    );

    testWidgets(
      '"Quitar diagrama" removes the block and Deshacer brings it back where it was, edits intact',
      (tester) async {
        final home = await _home(tester, [board(middlegame), board(endgame)]);
        final first = home.session.diagrams.first..turn = 'b';
        await tester.tap(find.byTooltip('Quitar diagrama').first);
        await tester.pumpAndSettle();
        expect(home.session.diagramCount, 1);
        expect(find.byType(DiagramBlock), findsOneWidget);
        expect(find.text('Diagrama 1 quitado'), findsOneWidget);
        expect(find.text('Deshacer'), findsOneWidget);
        expect(find.text('Captura 1 · 1 diagrama'), findsOneWidget);

        await tester.tap(find.text('Deshacer'));
        await tester.pumpAndSettle();
        expect(home.session.diagrams.first, same(first));
        expect(first.turn, 'b');
        expect(find.byType(DiagramBlock), findsNWidgets(2));
      },
    );

    testWidgets(
      '"Ajustar recorte" asks for a region and replaces this diagram',
      (tester) async {
        final session = Session(
          readImage: readerOf((_) => [board(middlegame)]),
          readRegion: (bytes, region) async => board(endgame),
        );
        final home = Home(session)..cropResult = const Box(1, 2, 3, 4);
        await home.pump(tester);
        await home.addCapture(tester);
        await tester.tap(find.byTooltip('Ajustar recorte'));
        await tester.pumpAndSettle();
        expect(home.crops, 1);
        expect(session.diagrams.single.placement, endgame);
      },
    );

    testWidgets(
      'every moved action has a tooltip, is 48 dp and works from the keyboard',
      (tester) async {
        final home = await _home(tester, [board(middlegame, crop: true)]);
        for (final tip in [
          'Ajustar recorte',
          'Ver desde las negras',
          'Compartir o copiar PGN',
          'Quitar diagrama',
          'Copiar FEN',
        ]) {
          final f = find.byTooltip(tip);
          expect(f, findsOneWidget, reason: tip);
          final size = tester.getSize(f);
          expect(size.width, greaterThanOrEqualTo(48), reason: tip);
          expect(size.height, greaterThanOrEqualTo(48), reason: tip);
        }
        await pressByKeyboard(tester, 'Copiar FEN');
        await tester.pumpAndSettle();
        expect(home.clipboard, home.session.diagrams.single.fen);
        await pressByKeyboard(tester, 'Quitar diagrama');
        await tester.pumpAndSettle();
        expect(home.session.diagramCount, 0);
      },
    );

    testWidgets(
      'the comparator row keeps the icons beside the segmented control at 360 dp and 1.3x text',
      (tester) async {
        final home = Home(
          sessionWith({
            1: () => [board(middlegame, crop: true)],
          }),
        );
        await home.pump(tester, size: const Size(360, 2400), textScale: 1.3);
        await home.addCapture(tester);
        final segmented = tester.getRect(find.byType(SegmentedButton<bool>));
        final crop = tester.getRect(find.byTooltip('Ajustar recorte'));
        final flip = tester.getRect(find.byTooltip('Ver desde las negras'));
        expect(crop.center.dy, closeTo(segmented.center.dy, 8));
        expect(flip.center.dy, closeTo(segmented.center.dy, 8));
        expect(segmented.right, lessThanOrEqualTo(crop.left + 0.5));
        expect(crop.right, lessThanOrEqualTo(flip.left + 0.5));
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('Lichess and copying', () {
    testWidgets(
      '"Analizar en Lichess" opens the analysis link of the current FEN',
      (tester) async {
        final home = await _home(tester, [board(middlegame)]);
        final d = home.session.diagrams.single..turn = 'b';
        await tester.tap(find.text('Analizar en Lichess'));
        await tester.pumpAndSettle();
        expect(home.opened.single, lichessAnalysisUri(d.fen));
        expect(find.textContaining('No se pudo abrir Lichess'), findsNothing);
      },
    );

    testWidgets(
      'when nothing can open it the link is copied and the user is told',
      (tester) async {
        final home = await _home(tester, [board(middlegame)]);
        home.openResult = false;
        final d = home.session.diagrams.single;
        await tester.tap(find.text('Analizar en Lichess'));
        await tester.pumpAndSettle();
        expect(home.clipboard, lichessAnalysisUri(d.fen).toString());
        expect(
          find.text('No se pudo abrir Lichess. Enlace copiado.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('the FEN line and its 48 dp copy button copy the FEN', (
      tester,
    ) async {
      final home = await _home(tester, [board(middlegame)]);
      final d = home.session.diagrams.single;
      expect(find.text('Copiar FEN'), findsNothing, reason: 'no text button');
      await tester.tap(find.byTooltip('Copiar FEN'));
      await tester.pumpAndSettle();
      expect(home.clipboard, d.fen);
      expect(find.text('FEN copiado'), findsOneWidget);

      home.clipboard = null;
      await tester.tap(find.byKey(const ValueKey('fen-line')));
      await tester.pumpAndSettle();
      expect(home.clipboard, d.fen);

      home.clipboard = null;
      await tester.longPress(find.byKey(const ValueKey('fen-line')));
      await tester.pumpAndSettle();
      expect(home.clipboard, d.fen);
    });

    testWidgets(
      'the FEN line is one line of mono text with a "FEN: …" semantics label',
      (tester) async {
        final home = await _home(tester, [board(middlegame)]);
        final d = home.session.diagrams.single;
        final text = tester.widget<Text>(
          find.descendant(
            of: find.byKey(const ValueKey('fen-line')),
            matching: find.byType(Text),
          ),
        );
        expect(text.maxLines, 1);
        expect(text.overflow, TextOverflow.ellipsis);
        expect(text.style!.fontFamily, 'JetBrainsMono');
        expect(find.bySemanticsLabel('FEN: ${d.fen}'), findsOneWidget);
      },
    );
  });

  group('header', () {
    testWidgets('nothing in the status when the reading is fine', (
      tester,
    ) async {
      await _home(tester, [board(endgame)]);
      expect(find.textContaining('dudosa'), findsNothing);
      expect(find.textContaining('imposible'), findsNothing);
    });

    testWidgets('doubtful squares: warning icon, count and the review entry', (
      tester,
    ) async {
      await _home(tester, [
        board(endgame, confidence: {10: 0.5, 11: 0.5}),
      ]);
      expect(find.text('2 casillas dudosas'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('review-doubtful')),
          matching: find.byType(AppIcon),
        ),
        findsNWidgets(2),
        reason: 'warning and chevron',
      );
      expect(find.text('Revisar dudosas'), findsOneWidget);
    });

    testWidgets(
      'an impossible position AND doubtful squares show both: the reason and the review row',
      (tester) async {
        final home = await _home(tester, [
          board('8/8/8/8/8/8/8/4K3', confidence: {10: 0.5}),
        ]);
        expect(find.text('Posición imposible'), findsOneWidget);
        expect(find.text('Falta el rey negro.'), findsOneWidget);
        expect(find.text('1 casilla dudosa'), findsOneWidget);
        expect(find.byKey(const ValueKey('review-doubtful')), findsOneWidget);
        expect(find.byTooltip('Más opciones'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('review-doubtful')));
        await tester.pumpAndSettle();
        expect(find.text('Dudosa 1 de 1'), findsOneWidget);
        await tester.tap(find.text('Está vacía'));
        await tester.pumpAndSettle();
        expect(home.session.diagrams.single.doubtfulCount, 0);
        expect(find.text('Posición imposible'), findsOneWidget);
      },
    );

    testWidgets('the check problem names the colour', (tester) async {
      await _home(tester, [board('r6k/8/8/8/8/8/8/K6R')]);
      expect(
        find.text('Las negras están en jaque y no les toca mover.'),
        findsOneWidget,
      );
      // switching the side to move would only move the problem to the other colour: no shortcut offered
      expect(find.text('Cambiar turno'), findsNothing);
    });

    testWidgets('the block is one surface: no Card inside', (tester) async {
      await _home(tester, [board(middlegame)]);
      expect(
        find.descendant(
          of: find.byType(DiagramBlock),
          matching: find.byType(Card),
        ),
        findsNothing,
      );
    });
  });
}
