// The UX fix round on the home screen: triage between diagrams, readable disabled turn, castling caption, capture
// thumbnail and viewer, rebuild isolation, phone chrome (FAB, one-row export bar, scroll padding) and desktop strips.
import 'dart:typed_data';

import 'package:chessboard_pgn/src/ui/capture_thumb.dart';
import 'package:chessboard_pgn/src/ui/color_math.dart';
import 'package:chessboard_pgn/src/ui/diagram_block.dart';
import 'package:chessboard_pgn/src/ui/export_bar.dart';
import 'package:chessboard_pgn/src/ui/plate.dart';
import 'package:chessboard_pgn/src/pipeline.dart';
import 'package:chessboard_pgn/src/session.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'home_harness.dart';

/// Pumps [home] on a tall view (the first-run screen needs room for its button), adds the capture and then
/// shrinks the view to [size].
Future<void> _shrink(WidgetTester tester, Size size) async {
  tester.view.physicalSize = size;
  await tester.pumpAndSettle();
}

Future<Home> _home(
  WidgetTester tester,
  List<RecognizedBoard> boards, {
  Size size = const Size(480, 2400),
  double textScale = 1,
  bool canShare = true,
}) async {
  final home = Home(sessionWith({1: () => boards}));
  await home.pump(tester, size: size, textScale: textScale, canShare: canShare);
  await home.addCapture(tester);
  return home;
}

void main() {
  setUpAll(loadRealFonts);

  group('triage: "Siguiente con dudas"', () {
    testWidgets(
      'finishing a review offers the next diagram with doubts and opens its review',
      (tester) async {
        final home = await _home(tester, [
          board(middlegame, confidence: {21: 0.5}),
          board(endgame),
          board(middlegame, confidence: {18: 0.4}),
        ]);
        await tester.tap(find.byKey(const ValueKey('review-doubtful')).first);
        await tester.pumpAndSettle();
        expect(find.text('Dudosa 1 de 1'), findsOneWidget);
        await tester.tap(find.text('Está bien'));
        await tester.pumpAndSettle();
        expect(find.text('Todas las casillas revisadas'), findsOneWidget);
        expect(find.text('Siguiente con dudas'), findsOneWidget);

        await tester.tap(find.text('Siguiente con dudas'));
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(find.text('Casilla c6'), findsOneWidget);
        expect(home.session.diagrams.first.doubtfulCount, 0);
        expect(home.session.diagrams[2].doubtfulCount, 1);
      },
    );

    testWidgets('no action when no other diagram has doubts', (tester) async {
      await _home(tester, [
        board(middlegame, confidence: {21: 0.5}),
        board(endgame),
      ]);
      await tester.tap(find.byKey(const ValueKey('review-doubtful')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Está bien'));
      await tester.pumpAndSettle();
      expect(find.text('Todas las casillas revisadas'), findsOneWidget);
      expect(find.text('Siguiente con dudas'), findsNothing);
    });
  });

  group('turn and castling details', () {
    testWidgets(
      'the locked turn segment stays non-interactive but readable (4.5:1)',
      (tester) async {
        await _home(tester, [board(castlingCheck)]);
        final scheme = Theme.of(tester.element(find.byType(DiagramBlock)))
            .colorScheme;
        final segments = tester.widget<SegmentedButton<String>>(
          find.byType(SegmentedButton<String>),
        );
        expect(segments.segments.first.enabled, isFalse);
        final label = find.text('Mueven blancas');
        final style = DefaultTextStyle.of(tester.element(label)).style;
        expect(style.color, scheme.onSurfaceVariant);
        final block = tester.element(find.byType(DiagramBlock));
        final surface = Theme.of(block).colorScheme.surfaceContainerLow;
        expect(contrastRatio(style.color!, surface), greaterThanOrEqualTo(4.5));
        // still not tappable
        final home = tester.widget<SegmentedButton<String>>(
          find.byType(SegmentedButton<String>),
        );
        home.onSelectionChanged!({'w'});
        await tester.pump();
        expect(
          find.text('El rey negro está en jaque: mueven negras.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('the castling chips have a caption', (tester) async {
      await _home(tester, [board(castlingCheck)]);
      expect(find.text('Enroques permitidos'), findsOneWidget);
      final caption = tester.getRect(find.text('Enroques permitidos'));
      final chip = tester.getRect(find.byType(FilterChip).first);
      expect(caption.bottom, lessThanOrEqualTo(chip.top));
      final style = tester
          .widget<Text>(find.text('Enroques permitidos'))
          .style!;
      expect(
        style.fontSize,
        Theme.of(tester.element(find.byType(DiagramBlock)))
            .textTheme
            .labelMedium!
            .fontSize,
      );
    });

    testWidgets('no chips, no caption', (tester) async {
      await _home(tester, [board(endgame)]);
      expect(find.text('Enroques permitidos'), findsNothing);
    });
  });

  group('capture thumbnail', () {
    testWidgets(
      '40 dp, decoded small, opens a full screen viewer with a close button',
      (tester) async {
        await _home(tester, [board(middlegame)]);
        final thumb = find.byKey(const ValueKey('capture-thumb'));
        expect(thumb, findsOneWidget);
        expect(tester.getSize(thumb), const Size(48, 48), reason: 'target');
        final image = tester.widget<Image>(
          find.descendant(of: thumb, matching: find.byType(Image)),
        );
        expect(
          tester.getSize(find.byWidget(image)),
          const Size(captureThumbSize, captureThumbSize),
        );
        expect(image.image, isA<ResizeImage>());
        expect((image.image as ResizeImage).width, 120);

        await tester.tap(thumb);
        await tester.pumpAndSettle();
        expect(find.byType(CaptureViewerPage), findsOneWidget);
        expect(find.byType(InteractiveViewer), findsOneWidget);
        expect(find.byTooltip('Cerrar'), findsOneWidget);
        await tester.tap(find.byTooltip('Cerrar'));
        await tester.pumpAndSettle();
        expect(find.byType(CaptureViewerPage), findsNothing);
        expect(find.byType(DiagramBlock), findsOneWidget);
      },
    );
  });

  group('rebuilds', () {
    testWidgets(
      'a block rebuilds on its own diagram and its group, not on other captures',
      (tester) async {
        final home = Home(
          sessionWith({
            1: () => [board(middlegame), board(endgame), board(castlingCheck)],
            2: () => [board(endgame), board(middlegame)],
          }),
        );
        await home.pump(tester, size: const Size(480, 6000));
        await home.addCapture(tester, 1);
        await home.addCapture(tester, 2);
        final d = home.session.diagrams;
        expect(d, hasLength(5));

        var base = diagramBlockBuilds;
        d[1].turn = 'b';
        await tester.pump();
        expect(diagramBlockBuilds - base, 1, reason: 'only the edited block');

        // the second capture changes: the first capture's blocks do not rebuild; the changed group's do
        base = diagramBlockBuilds;
        home.session.removeDiagram(d[4]);
        await tester.pump();
        expect(
          diagramBlockBuilds - base,
          1,
          reason: 'only the one left in capture 2',
        );

        // removing a diagram of the first capture renumbers the second: those blocks follow, nothing else moves
        base = diagramBlockBuilds;
        home.session.removeDiagram(d[0]);
        await tester.pump();
        // capture 1: two blocks (group change); capture 2: one block (new number)
        expect(diagramBlockBuilds - base, 3);
        expect(find.bySemanticsLabel('Diagrama 4'), findsNothing);
        expect(find.bySemanticsLabel('Diagrama 3'), findsOneWidget);
      },
    );

    testWidgets('every board is in its own RepaintBoundary', (tester) async {
      await _home(tester, [board(middlegame), board(endgame)]);
      for (final block in find.byType(DiagramBlock).evaluate()) {
        final b = find.byElementPredicate((e) => e == block);
        expect(
          find.descendant(
            of: b,
            matching: find.ancestor(
              of: find.byKey(const ValueKey('square-0')),
              matching: find.byType(RepaintBoundary),
            ),
          ),
          findsWidgets,
        );
      }
    });
  });

  group('phone chrome', () {
    Future<Home> long(
      WidgetTester tester, {
      required Size size,
      double textScale = 1,
      int boards = 3,
      bool warnings = false,
    }) async {
      final home = Home(
        sessionWith({
          1: () => [
            for (var i = 0; i < boards; i++)
              board(
                i == 0 && warnings ? middlegame : endgame,
                confidence: i == 0 && warnings ? {18: 0.5} : const {},
                crop: i == 1,
              ),
          ],
        }),
      );
      await home.pump(
        tester,
        size: Size(size.width, 1600),
        textScale: textScale,
      );
      await home.addCapture(tester);
      await _shrink(tester, size);
      return home;
    }

    testWidgets(
      'on a phone with the export bar nothing floats: "Añadir captura" is a 48 dp plate button at the end of the bar',
      (tester) async {
        await long(tester, size: const Size(412, 700));
        expect(find.byType(FloatingActionButton), findsNothing);
        expect(find.text('Añadir captura'), findsNothing);
        final add = find.byKey(const ValueKey('add-capture'));
        expect(tester.getSize(add), const Size(48, 48));
        expect(find.byTooltip('Añadir captura'), findsOneWidget);
        final style = tester.widget<IconButton>(add).style!;
        expect(
          style.shape!.resolve(const {}),
          isA<PlateBorder>(),
          reason: 'the shape of the FAB, so it reads as one family',
        );
        // at the end of the bar, on the row of the exports
        final copy = tester.getRect(find.byKey(const ValueKey('copy-all')));
        final rect = tester.getRect(add);
        expect(rect.left, greaterThanOrEqualTo(copy.right));
        expect(rect.center.dy, closeTo(copy.center.dy, 1));
        // the bar is the bottom of the screen: scrolling does not change a thing
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
        await tester.pumpAndSettle();
        expect(tester.getRect(add), rect);
        expect(find.byType(FloatingActionButton), findsNothing);
      },
    );

    testWidgets('at the top of the list no button covers block 1', (
      tester,
    ) async {
      await long(tester, size: const Size(360, 780), textScale: 1.3);
      expect(find.byType(FloatingActionButton), findsNothing);
      // the list ends where the bar starts, and the button is in the bar
      final list = tester.getRect(find.byType(CustomScrollView));
      final add = tester.getRect(find.byKey(const ValueKey('add-capture')));
      expect(list.overlaps(add), isFalse);
      expect(list.bottom, lessThanOrEqualTo(add.top));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'without a bar (the first capture is still being read) the extended FAB floats',
      (tester) async {
        final gate = Gate();
        final home = Home(
          Session(readImage: gate.reader([board(middlegame), board(endgame)])),
        );
        await home.pump(tester, size: const Size(412, 800));
        home.picks.add(Uint8List.fromList([1]));
        await tester.tap(find.text('Elegir captura'));
        await tester.pump(const Duration(milliseconds: 100));
        gate.found.complete();
        await tester.pump();
        expect(find.byType(FloatingActionButton), findsOneWidget);
        expect(find.text('Añadir captura'), findsOneWidget);
        expect(find.byType(DiagramSkeleton), findsWidgets);
        // finish: the bar arrives and the FAB moves into it as the plate button
        for (final c in gate.boards) {
          c.complete();
        }
        gate.finish.complete();
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.byType(FloatingActionButton), findsNothing);
        expect(find.byKey(const ValueKey('add-capture')), findsOneWidget);
      },
    );

    testWidgets('from 600 dp the extended FAB is docked in the export bar', (
      tester,
    ) async {
      await long(tester, size: const Size(700, 700));
      final fab = find.byType(FloatingActionButton);
      expect(find.text('Añadir captura'), findsOneWidget);
      final bar = tester.getRect(
        find
            .ancestor(
              of: find.byKey(const ValueKey('copy-all')),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(bar.contains(tester.getCenter(fab)), isTrue);
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.text('Añadir captura'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final (warnings, scale) in [(false, 1.3), (true, 1.3), (true, 1.0)]) {
      testWidgets(
        'the export bar is ONE row at 360 dp (text ${scale}x, warnings: $warnings)',
        (tester) async {
          await long(
            tester,
            size: const Size(360, 780),
            textScale: scale,
            warnings: warnings,
          );
          final bar = find.byKey(const ValueKey('save-pgn'));
          final buttons = [
            tester.getCenter(bar).dy,
            tester.getCenter(find.byKey(const ValueKey('share-all'))).dy,
            tester.getCenter(find.byKey(const ValueKey('copy-all'))).dy,
            tester.getCenter(find.byKey(const ValueKey('add-capture'))).dy,
          ];
          for (final c in buttons) {
            expect(c, closeTo(buttons.first, 2));
          }
          // the count (and the warnings under it) sit on the same row as the buttons
          final summary = tester.getRect(
            warnings
                ? find.byKey(const ValueKey('export-warnings'))
                : find.descendant(
                    of: find.byType(ExportBar),
                    matching: find.text('3 diagramas'),
                  ),
          );
          expect(summary.center.dy, closeTo(buttons.first, 6));
          expect(summary.right, lessThanOrEqualTo(tester.getRect(bar).left));
          expect(
            tester.getRect(find.byKey(const ValueKey('copy-all'))).right,
            lessThanOrEqualTo(
              tester.getRect(find.byKey(const ValueKey('add-capture'))).left,
            ),
          );
          expect(
            tester.getRect(find.byKey(const ValueKey('add-capture'))).right,
            lessThanOrEqualTo(360),
          );
          final barBox = tester.getRect(
            find.ancestor(of: bar, matching: find.byType(Material)).first,
          );
          expect(barBox.height, lessThanOrEqualTo(48 + 16 + 4));
          expect(tester.takeException(), isNull);
          if (scale > 1.15) {
            expect(find.byTooltip('Guardar .pgn'), findsOneWidget);
            expect(find.byTooltip('Compartir o copiar PGN'), findsWidgets);
            expect(find.byTooltip('Copiar PGN'), findsWidgets);
          }
        },
      );
    }

    testWidgets(
      'scrolled to the end, the last FEN copy button is clear of the FAB and the bar',
      (tester) async {
        await long(tester, size: const Size(412, 780), boards: 4);
        await tester.fling(
          find.byType(CustomScrollView),
          const Offset(0, -9000),
          6000,
        );
        await tester.pumpAndSettle();
        final last = find.byTooltip('Copiar FEN').last;
        expect(last.hitTestable(), findsOneWidget);
        expect(find.byType(FloatingActionButton), findsNothing);
        // the clear-all button is reachable below it
        expect(find.byKey(const ValueKey('clear-all')), findsOneWidget);
        expect(
          find.byKey(const ValueKey('clear-all')).hitTestable(),
          findsOneWidget,
        );
      },
    );

    testWidgets('the same at 1.3x text on a 360 dp phone', (tester) async {
      await long(tester, size: const Size(360, 780), textScale: 1.3, boards: 4);
      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, -12000),
        6000,
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Copiar FEN').last.hitTestable(), findsOneWidget);
      expect(
        find.byKey(const ValueKey('clear-all')).hitTestable(),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('failure strips on desktop', () {
    testWidgets(
      'a strip is a band across the content column, not a box stuck in the first column',
      (tester) async {
        final session = Session(
          readImage: (bytes, {onFound, onBoard}) async => throw StateError('x'),
        );
        final home = Home(session);
        await home.pump(tester, size: const Size(1280, 800));
        await home.addCapture(tester);
        final header = tester.getRect(
          find.byKey(const ValueKey('capture-thumb')),
        );
        final strip = tester.getRect(
          find.byKey(ValueKey('strip-${session.sources.single.id}')),
        );
        expect(strip.left, closeTo(header.left, 1));
        expect(
          strip.width,
          greaterThan(900),
          reason: 'content column, not one block',
        );
        final remove = tester.getRect(find.text('Quitar captura'));
        expect(
          remove.right,
          closeTo(strip.right - 16, 12),
          reason: 'actions at the end',
        );
      },
    );

    testWidgets('no boards: the new wording and its two exits', (tester) async {
      final home = Home(Session(readImage: readerOf((_) => const [])));
      await home.pump(tester, size: const Size(1280, 800));
      await home.addCapture(tester);
      expect(
        find.text(
          'No se encontró ningún tablero en esta captura. Si el diagrama es pequeño, recórtalo a mano.',
        ),
        findsOneWidget,
      );
      expect(find.text('Recortar a mano'), findsOneWidget);
      expect(find.text('Quitar captura'), findsOneWidget);
    });

    testWidgets('on a phone the strip stacks its parts', (tester) async {
      final session = Session(readImage: readerOf((_) => const []));
      final home = Home(session);
      await home.pump(tester, size: const Size(360, 800));
      await home.addCapture(tester);
      final message = tester.getRect(
        find.textContaining('No se encontró ningún tablero'),
      );
      final action = tester.getRect(find.text('Recortar a mano'));
      expect(action.top, greaterThan(message.bottom));
    });
  });

  group('accessibility of the moved actions', () {
    testWidgets('every moved action has a semantics label', (tester) async {
      final handle = tester.ensureSemantics();
      await _home(tester, [board(middlegame, crop: true)]);
      for (final label in [
        'Ajustes',
        'Recortar otro tablero a mano',
        'Quitar captura',
        'Ajustar recorte',
        'Ver desde las negras',
        'Compartir o copiar PGN',
        'Quitar diagrama',
        'Copiar FEN',
        'Copiar PGN',
      ]) {
        final node = tester.getSemantics(find.byTooltip(label).first);
        final data = node.getSemanticsData();
        expect(
          data.label.contains(label) || data.tooltip.contains(label),
          isTrue,
          reason: '$label: label "${data.label}", tooltip "${data.tooltip}"',
        );
      }
      handle.dispose();
    });
  });
}
