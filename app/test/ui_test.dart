// The home / session screen end to end, with every platform call faked: picking, reading progress, several
// captures, failures, removal, export.

import 'package:chessboard_pgn/src/export.dart';
import 'package:chessboard_pgn/src/locate.dart';
import 'package:chessboard_pgn/src/session.dart';
import 'package:chessboard_pgn/src/ui/diagram_block.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'ui/home_harness.dart';

final _appBarMenu = find.descendant(
  of: find.byType(AppBar),
  matching: find.byTooltip('Más opciones'),
);

void main() {
  setUpAll(loadRealFonts);

  group('empty state and picking', () {
    testWidgets(
      'teaches the product: example, three steps, one button, the privacy line',
      (tester) async {
        final home = Home(sessionWith({}));
        await home.pump(tester);
        expect(find.text('Chess to PGN'), findsOneWidget);
        expect(find.text('Haz una captura de la página'), findsOneWidget);
        expect(find.text('Elígela aquí'), findsOneWidget);
        expect(find.text('Revisa y exporta'), findsOneWidget);
        expect(find.text('Elegir captura'), findsOneWidget);
        expect(find.text('Todo se procesa en el dispositivo.'), findsOneWidget);
        expect(
          find.bySemanticsLabel(
            'Ejemplo de diagrama leído, con dos casillas dudosas',
          ),
          findsOneWidget,
        );
        // nothing to export yet
        expect(find.text('Añadir captura'), findsNothing);
        expect(find.text('Guardar .pgn'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('cancelling the picker changes nothing', (tester) async {
      final home = Home(sessionWith({}));
      await home.pump(tester);
      await tester.tap(find.text('Elegir captura'));
      await tester.pumpAndSettle();
      expect(home.picked, 1);
      expect(home.session.isEmpty, isTrue);
      expect(find.text('Elegir captura'), findsOneWidget);
    });

    testWidgets(
      'a failing picker says so with a way to retry, never raw exception text',
      (tester) async {
        var calls = 0;
        final home = Home(sessionWith({}));
        await home.pump(
          tester,
          pickImage: () async {
            calls++;
            throw PlatformException(
              code: 'denied',
              message: 'raw platform text',
            );
          },
        );
        await tester.tap(find.text('Elegir captura'));
        await tester.pumpAndSettle();
        expect(find.text('No se pudo abrir la galería.'), findsOneWidget);
        expect(find.text('Reintentar'), findsOneWidget);
        expect(find.textContaining('raw platform text'), findsNothing);
        await tester.tap(find.text('Reintentar'));
        await tester.pumpAndSettle();
        expect(calls, 2);
      },
    );

    testWidgets(
      'picking shows the group at once with skeletons, then blocks replace them one by one',
      (tester) async {
        final gate = Gate();
        final session = Session(
          readImage: gate.reader([board(middlegame), board(endgame)]),
        );
        final home = Home(session);
        await home.pump(tester);
        home.picks.add(Uint8List.fromList([1]));
        await tester.tap(find.text('Elegir captura'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));

        // located nothing yet: one skeleton and "Buscando diagramas…"
        expect(find.text('Captura 1'), findsOneWidget);
        expect(find.text('Buscando diagramas…'), findsOneWidget);
        expect(find.byType(DiagramSkeleton), findsOneWidget);
        expect(find.byType(DiagramBlock), findsNothing);
        expect(find.byType(LinearProgressIndicator), findsOneWidget);
        expect(
          find.text('Añadir captura'),
          findsOneWidget,
          reason: 'the FAB is there while reading',
        );

        gate.found.complete();
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byType(DiagramSkeleton), findsNWidgets(2));
        expect(find.text('Leyendo 1 de 2…'), findsOneWidget);

        gate.boards[0].complete();
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byType(DiagramBlock), findsOneWidget);
        expect(find.byType(DiagramSkeleton), findsOneWidget);
        expect(find.text('Leyendo 2 de 2…'), findsOneWidget);
        // the part already read is usable
        await tester.tap(find.text('Mueven negras'));
        await tester.pump();
        expect(session.diagrams.first.turn, 'b');

        gate.boards[1].complete();
        gate.finish.complete();
        await tester.pumpAndSettle();
        expect(find.byType(DiagramBlock), findsNWidgets(2));
        expect(find.byType(DiagramSkeleton), findsNothing);
        expect(find.text('Captura 1 · 2 diagramas'), findsOneWidget);
        expect(find.text('Leyendo 2 de 2…'), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'a second capture accumulates, numbering goes on and a queued capture says "En espera…"',
      (tester) async {
        final gate = Gate();
        final session = Session(
          readImage: (bytes, {onFound, onBoard}) => bytes.first == 1
              ? readerOf((_) => [board(middlegame), board(endgame)])(
                  bytes,
                  onFound: onFound,
                  onBoard: onBoard,
                )
              : gate.reader([board(endgame)])(
                  bytes,
                  onFound: onFound,
                  onBoard: onBoard,
                ),
        );
        final home = Home(session);
        await home.pump(tester);
        await home.addCapture(tester, 1);
        expect(find.text('Captura 1 · 2 diagramas'), findsOneWidget);

        // the second capture is reading (its gate is closed); a third one waits behind it
        for (var i = 0; i < 2; i++) {
          home.picks.add(Uint8List.fromList([2]));
          await tester.tap(find.text('Añadir captura'));
          await tester.pump(const Duration(milliseconds: 50));
        }
        expect(session.sources.map((s) => s.status), [
          SourceStatus.done,
          SourceStatus.reading,
          SourceStatus.queued,
        ]);
        // the list is lazy: the headers below the fold are only looked up, not asked to be on screen
        expect(find.text('Captura 2', skipOffstage: false), findsOneWidget);
        expect(find.text('Captura 3', skipOffstage: false), findsOneWidget);
        expect(find.text('En espera…', skipOffstage: false), findsOneWidget);

        gate.found.complete();
        gate.boards[0].complete();
        gate.finish.complete();
        await tester.pumpAndSettle();
        expect(
          find.text('Captura 1 · 2 diagramas', skipOffstage: false),
          findsOneWidget,
        );
        expect(
          find.text('Captura 2 · 1 diagrama', skipOffstage: false),
          findsOneWidget,
        );
        expect(session.sources.length, 3);
        expect(session.diagramCount, 4);
        expect(find.text('4 diagramas'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  });

  group('failures', () {
    testWidgets('failed: message, Reintentar reads again, Quitar removes', (
      tester,
    ) async {
      var attempts = 0;
      final session = Session(
        readImage: (bytes, {onFound, onBoard}) async {
          attempts++;
          if (attempts == 1) throw StateError('boom');
          return readerOf((_) => [board(endgame)])(
            bytes,
            onFound: onFound,
            onBoard: onBoard,
          );
        },
      );
      final home = Home(session);
      await home.pump(tester);
      await home.addCapture(tester);
      expect(
        find.text('No se pudo leer esta captura. Inténtalo de nuevo.'),
        findsOneWidget,
      );
      expect(find.textContaining('boom'), findsNothing);
      expect(find.byType(DiagramBlock), findsNothing);

      await tester.tap(find.text('Reintentar'));
      await tester.pumpAndSettle();
      expect(attempts, 2);
      expect(find.byType(DiagramBlock), findsOneWidget);
      expect(find.text('Captura 1 · 1 diagrama'), findsOneWidget);
    });

    testWidgets('failed capture can be removed from its strip', (tester) async {
      final session = Session(
        readImage: (bytes, {onFound, onBoard}) async => throw StateError('x'),
      );
      final home = Home(session);
      await home.pump(tester);
      await home.addCapture(tester);
      await tester.tap(find.text('Quitar'));
      await tester.pumpAndSettle();
      expect(session.isEmpty, isTrue);
      expect(find.text('Elegir captura'), findsOneWidget);
    });

    testWidgets(
      'noBoards: Recortar a mano asks for a region and reads it into the capture',
      (tester) async {
        final regions = <Box>[];
        final session = Session(
          readImage: readerOf((_) => const []),
          readRegion: (bytes, region) async {
            regions.add(region);
            return board(middlegame, crop: true);
          },
        );
        final home = Home(session)..cropResult = const Box(10, 20, 110, 120);
        await home.pump(tester);
        await home.addCapture(tester);
        expect(
          find.text('No se encontró ningún tablero en esta captura.'),
          findsOneWidget,
        );

        await tester.tap(find.text('Recortar a mano'));
        await tester.pumpAndSettle();
        expect(home.crops, 1);
        expect(regions.single.x0, 10);
        expect(session.sources.single.status, SourceStatus.done);
        expect(find.byType(DiagramBlock), findsOneWidget);
        expect(find.text('Captura 1 · 1 diagrama'), findsOneWidget);
        expect(
          find.text('No se encontró ningún tablero en esta captura.'),
          findsNothing,
        );
      },
    );

    testWidgets('cancelling the crop screen changes nothing', (tester) async {
      final session = Session(readImage: readerOf((_) => const []));
      final home = Home(session);
      await home.pump(tester);
      await home.addCapture(tester);
      await tester.tap(find.text('Recortar a mano'));
      await tester.pumpAndSettle();
      expect(home.crops, 1);
      expect(session.sources.single.status, SourceStatus.noBoards);
    });

    testWidgets(
      'a region that cannot be read explains it and offers to try again',
      (tester) async {
        final session = Session(
          readImage: readerOf((_) => const []),
          readRegion: (bytes, region) async => throw StateError('nope'),
        );
        final home = Home(session)..cropResult = const Box(0, 0, 50, 50);
        await home.pump(tester);
        await home.addCapture(tester);
        await tester.tap(find.text('Recortar a mano'));
        await tester.pumpAndSettle();
        expect(
          find.textContaining('No se pudo leer el recorte'),
          findsOneWidget,
        );
        expect(find.text('Recortar a mano'), findsWidgets);
        expect(find.textContaining('nope'), findsNothing);
        expect(session.sources.single.status, SourceStatus.noBoards);
      },
    );

    testWidgets(
      'a plausible whole-image fallback is kept, with a note and "Recortar a mano"',
      (tester) async {
        final session = Session(
          readImage: readerOf(
            (_) => [board(middlegame, fallback: true, crop: true)],
          ),
        );
        final home = Home(session)..cropResult = null;
        await home.pump(tester);
        await home.addCapture(tester);
        expect(find.byType(DiagramBlock), findsOneWidget);
        expect(
          find.text(
            'No se encontró el marco del tablero; se leyó la imagen entera.',
          ),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const ValueKey('fallback-crop')));
        await tester.pumpAndSettle();
        expect(home.crops, 1);
      },
    );

    testWidgets(
      'an implausible fallback (16 doubtful squares) ends as noBoards, with no diagram',
      (tester) async {
        final doubts = {for (var i = 0; i < 16; i++) i: 0.3};
        final session = Session(
          readImage: readerOf(
            (_) => [board(middlegame, fallback: true, confidence: doubts)],
          ),
        );
        final home = Home(session);
        await home.pump(tester);
        await home.addCapture(tester);
        expect(session.sources.single.status, SourceStatus.noBoards);
        expect(find.byType(DiagramBlock), findsNothing);
        expect(
          find.text('No se encontró ningún tablero en esta captura.'),
          findsOneWidget,
        );
      },
    );
  });

  group('removal', () {
    Future<Home> two(WidgetTester tester) async {
      final session = sessionWith({
        1: () => [board(middlegame), board(endgame)],
        2: () => [board(endgame)],
      });
      final home = Home(session);
      await home.pump(tester);
      await home.addCapture(tester, 1);
      await home.addCapture(tester, 2);
      return home;
    }

    testWidgets(
      'the group menu removes a capture after confirmation and renumbers the rest',
      (tester) async {
        final home = await two(tester);
        await tester.tap(find.byTooltip('Opciones de captura 1'));
        await tester.pumpAndSettle();
        expect(find.text('Recortar otro tablero a mano'), findsOneWidget);
        await tester.tap(find.text('Quitar captura'));
        await tester.pumpAndSettle();
        expect(find.text('¿Quitar la captura 1?'), findsOneWidget);
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect(home.session.sources.length, 2);

        await tester.tap(find.byTooltip('Opciones de captura 1'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Quitar captura'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Quitar captura'));
        await tester.pumpAndSettle();
        expect(home.session.sources.length, 1);
        expect(find.text('Captura 1 · 1 diagrama'), findsOneWidget);
        expect(find.text('Captura 2 · 1 diagrama'), findsNothing);
      },
    );

    testWidgets(
      'Vaciar sesión asks first, Cancelar keeps everything, confirming empties the session',
      (tester) async {
        final home = await two(tester);
        await tester.tap(_appBarMenu);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Vaciar sesión'));
        await tester.pumpAndSettle();
        expect(find.text('¿Vaciar la sesión?'), findsOneWidget);
        expect(find.textContaining('No se puede deshacer'), findsOneWidget);
        await tester.tap(find.text('Cancelar'));
        await tester.pumpAndSettle();
        expect(home.session.diagramCount, 3);

        await tester.tap(_appBarMenu);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Vaciar sesión'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Vaciar sesión'));
        await tester.pumpAndSettle();
        expect(home.session.isEmpty, isTrue);
        expect(find.text('Elegir captura'), findsOneWidget);
      },
    );

    testWidgets('the app bar menu only exists once there are diagrams', (
      tester,
    ) async {
      final home = Home(
        sessionWith({
          1: () => [board(endgame)],
        }),
      );
      await home.pump(tester);
      expect(find.byTooltip('Más opciones'), findsNothing);
      await home.addCapture(tester);
      expect(find.byTooltip('Más opciones'), findsWidgets);
    });
  });

  group('export bar', () {
    Future<Home> one(
      WidgetTester tester, {
      bool canShare = true,
      bool? saveResult,
    }) async {
      final home = Home(
        sessionWith({
          1: () => [board(middlegame), board(endgame)],
        }),
      );
      await home.pump(tester, canShare: canShare, saveResult: saveResult);
      await home.addCapture(tester);
      return home;
    }

    testWidgets(
      'shows the count and passes the combined PGN and the file name to the saver',
      (tester) async {
        final home = await one(tester);
        expect(find.text('2 diagramas'), findsOneWidget);
        await tester.tap(find.byKey(const ValueKey('save-pgn')));
        await tester.pumpAndSettle();
        final (name, bytes) = home.saved.single;
        expect(name, pgnFileName(home.now));
        expect(name, 'diagramas-20260304-0905.pgn');
        expect(String.fromCharCodes(bytes), home.session.allPgn);
        expect(String.fromCharCodes(bytes), contains('[Event "Diagrama 2"]'));
        expect(find.text('Guardado: $name'), findsOneWidget);
      },
    );

    testWidgets('a cancelled save dialog says nothing', (tester) async {
      final home = await one(tester, saveResult: false);
      await tester.tap(find.byKey(const ValueKey('save-pgn')));
      await tester.pumpAndSettle();
      expect(home.saved, hasLength(1));
      expect(find.textContaining('Guardado'), findsNothing);
      expect(find.textContaining('No se pudo'), findsNothing);
    });

    testWidgets('Compartir is hidden when sharing is not available', (
      tester,
    ) async {
      await one(tester, canShare: false);
      expect(find.byKey(const ValueKey('share-all')), findsNothing);
      expect(find.byTooltip('Compartir'), findsNothing);
    });

    testWidgets('Compartir offers text or file and hands the PGN over', (
      tester,
    ) async {
      final home = await one(tester);
      await tester.tap(find.byKey(const ValueKey('share-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Como texto'));
      await tester.pumpAndSettle();
      expect(home.sharedText.single, home.session.allPgn);

      await tester.tap(find.byKey(const ValueKey('share-all')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Como archivo .pgn'));
      await tester.pumpAndSettle();
      expect(home.sharedFiles.single.$1, endsWith('.pgn'));
      expect(
        String.fromCharCodes(home.sharedFiles.single.$2),
        home.session.allPgn,
      );
    });

    testWidgets('Copiar PGN is in the overflow menu', (tester) async {
      final home = await one(tester);
      // the bar's menu is the last "Más opciones"
      await tester.tap(find.byTooltip('Más opciones').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copiar PGN'));
      await tester.pumpAndSettle();
      expect(home.clipboard, home.session.allPgn);
      expect(find.text('PGN de 2 diagramas copiado'), findsOneWidget);
    });
  });

  group('keyboard', () {
    testWidgets('Ctrl+O opens the picker', (tester) async {
      final home = Home(sessionWith({}));
      await home.pump(tester);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyO);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(home.picked, 1);
    });

    testWidgets('Tab reaches the primary action', (tester) async {
      final home = Home(sessionWith({}));
      await home.pump(tester);
      for (var i = 0; i < 4; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final focused = FocusManager.instance.primaryFocus?.context;
        if (focused?.findAncestorWidgetOfExactType<FilledButton>() != null) {
          break;
        }
      }
      expect(
        FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<FilledButton>(),
        isNotNull,
      );
    });
  });
}
