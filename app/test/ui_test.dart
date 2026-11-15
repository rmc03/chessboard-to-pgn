import 'dart:convert';

import 'package:chessboard_pgn/main.dart';
import 'package:chessboard_pgn/src/chess.dart';
import 'package:chessboard_pgn/src/locate.dart';
import 'package:chessboard_pgn/src/pipeline.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';

const sample = '4r1k1/1p3ppp/1qn5/3p4/Q3n3/1NP5/PP3PPP/R4BK1';

/// A fake recogniser: one board whose square b6 (index 17) is doubtful.
Future<List<RecognizedBoard>> fakeRecognize(
  Uint8List bytes,
  void Function(int) onFound,
) async {
  onFound(1);
  final confidence = List<double>.filled(64, 0.99)..[17] = 0.5;
  final grid = placementToGrid(
    sample.replaceFirst('1qn5', '1Qn5'),
  ); // the model reads b6 as a white queen
  return [
    RecognizedBoard(const Box(0, 0, 100, 100), grid, confidence, grid, false),
  ];
}

Future<Uint8List?> fakeImage() async =>
    Uint8List.fromList(img.encodePng(img.Image(width: 4, height: 4)));

void main() {
  void bigScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(900, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('home screen invites to pick an image', (tester) async {
    bigScreen(tester);
    await tester.pumpWidget(const ChessPgnApp());
    expect(find.text('Elegir imagen'), findsOneWidget);
    expect(find.textContaining('Elige una imagen'), findsOneWidget);
    expect(find.text('Diagrama 1'), findsNothing);
  });

  testWidgets(
    'read a diagram, fix the doubtful square, switch turn and copy the PGN',
    (tester) async {
      bigScreen(tester);
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(pickImage: fakeImage, recognize: fakeRecognize),
        ),
      );
      await tester.tap(find.text('Elegir imagen'));
      await tester.pumpAndSettle();

      expect(find.text('Diagrama 1'), findsOneWidget);
      expect(find.textContaining('1 casilla(s) dudosa(s)'), findsOneWidget);
      expect(
        find.textContaining('1Qn5'),
        findsOneWidget,
      ); // FEN as read (white queen on b6)

      // tap b6 and choose a black queen (class 11)
      await tester.tap(find.byKey(const ValueKey('square-17')));
      await tester.pumpAndSettle();
      expect(find.text('Casilla b6'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pick-11')));
      await tester.pumpAndSettle();
      expect(find.textContaining('1qn5'), findsOneWidget);
      expect(
        find.textContaining('casilla(s) dudosa(s)'),
        findsNothing,
      ); // a corrected square is trusted

      await tester.tap(find.text('Negras'));
      await tester.pumpAndSettle();
      expect(find.textContaining('$sample b - -'), findsOneWidget);

      await tester.tap(find.textContaining('Copiar PGN'));
      await tester.pumpAndSettle();
      expect(clipboard, contains('[Event "Diagrama 1"]'));
      expect(clipboard, contains('[FEN "$sample b - - 0 1"]'));
      expect(clipboard, contains('[SetUp "1"]'));
    },
  );

  testWidgets('an illegal position is flagged', (tester) async {
    bigScreen(tester);
    Future<List<RecognizedBoard>> noKing(
      Uint8List b,
      void Function(int) f,
    ) async {
      f(1);
      final grid = placementToGrid('8/8/8/8/8/8/8/4K3');
      return [
        RecognizedBoard(
          const Box(0, 0, 100, 100),
          grid,
          List<double>.filled(64, 1),
          grid,
          true,
        ),
      ];
    }

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(pickImage: fakeImage, recognize: noKing),
      ),
    );
    await tester.tap(find.text('Elegir imagen'));
    await tester.pumpAndSettle();
    expect(find.textContaining('falta el rey negro'), findsOneWidget);
    expect(find.textContaining('No se encontró un marco'), findsOneWidget);
  });

  group('crop by hand', () {
    Future<RecognizedBoard> manualBoard(Uint8List b, Box region) async {
      final grid = placementToGrid('8/8/8/8/8/8/8/4K2k');
      return RecognizedBoard(
        region,
        grid,
        List<double>.filled(64, 1),
        grid,
        true, // even if flagged fallback, a manual board must not show the "no frame" notice
        manual: true,
      );
    }

    testWidgets(
      '"Recortar a mano" appends a diagram; "Ajustar recorte" replaces one',
      (tester) async {
        bigScreen(tester);
        final initials = <Box?>[];
        var next = const Box(10, 20, 30, 40);
        await tester.pumpWidget(
          MaterialApp(
            home: HomePage(
              pickImage: fakeImage,
              recognize: fakeRecognize,
              cropRegion: (context, bytes, initial) async {
                initials.add(initial);
                return next;
              },
              recognizeRegion: manualBoard,
            ),
          ),
        );
        expect(
          find.text('Recortar a mano'),
          findsNothing,
        ); // needs an image first
        await tester.tap(find.text('Elegir imagen'));
        await tester.pumpAndSettle();
        expect(find.text('Recortar a mano'), findsOneWidget);
        expect(find.text('Diagrama 1'), findsOneWidget);

        await tester.tap(find.text('Recortar a mano'));
        await tester.pumpAndSettle();
        expect(initials.single, isNull);
        expect(find.text('Diagrama 2'), findsOneWidget); // appended
        expect(find.textContaining('4K2k'), findsOneWidget);
        expect(find.textContaining('No se encontró un marco'), findsNothing);

        // adjust diagram 1 (box 0,0,100,100): starts from the box plus 5 % margin, then replaces it
        next = const Box(0, 0, 50, 50);
        await tester.tap(find.text('Ajustar recorte').first);
        await tester.pumpAndSettle();
        final init = initials.last!;
        expect(init.x0, closeTo(-5, 1e-9));
        expect(init.x1, closeTo(105, 1e-9));
        expect(find.text('Diagrama 3'), findsNothing); // replaced, not appended
        expect(find.text('Diagrama 2'), findsOneWidget);
        expect(
          find.textContaining('1Qn5'),
          findsNothing,
        ); // the first reading is gone
        expect(find.textContaining('4K2k'), findsNWidgets(2));
      },
    );

    testWidgets('cancelling the crop changes nothing', (tester) async {
      bigScreen(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            pickImage: fakeImage,
            recognize: fakeRecognize,
            cropRegion: (context, bytes, initial) async => null,
            recognizeRegion: manualBoard,
          ),
        ),
      );
      await tester.tap(find.text('Elegir imagen'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Recortar a mano'));
      await tester.pumpAndSettle();
      expect(find.text('Diagrama 2'), findsNothing);
    });

    testWidgets(
      'with only the whole-image fallback the status points to "Recortar a mano"',
      (tester) async {
        bigScreen(tester);
        Future<List<RecognizedBoard>> onlyFallback(
          Uint8List b,
          void Function(int) f,
        ) async {
          final grid = placementToGrid('8/8/8/8/8/8/8/4K2k');
          return [
            RecognizedBoard(
              const Box(0, 0, 4, 4),
              grid,
              List<double>.filled(64, 1),
              grid,
              true,
            ),
          ];
        }

        await tester.pumpWidget(
          MaterialApp(
            home: HomePage(pickImage: fakeImage, recognize: onlyFallback),
          ),
        );
        await tester.tap(find.text('Elegir imagen'));
        await tester.pumpAndSettle();
        expect(find.textContaining('«Recortar a mano»'), findsOneWidget);
      },
    );
  });

  group('export', () {
    Future<void> loaded(
      WidgetTester tester, {
      Future<bool> Function(String, Uint8List)? save,
      Future<void> Function(String)? onText,
      Future<void> Function(String, Uint8List)? onFile,
    }) async {
      bigScreen(tester);
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            pickImage: fakeImage,
            recognize: fakeRecognize,
            saveFile: save,
            shareText: onText,
            shareFile: onFile,
          ),
        ),
      );
      await tester.tap(find.text('Elegir imagen'));
      await tester.pumpAndSettle();
    }

    testWidgets(
      '"Guardar .pgn" saves diagramas-YYYYMMDD-HHMM.pgn with the PGN text',
      (tester) async {
        String? name;
        String? content;
        await loaded(
          tester,
          save: (String n, Uint8List bytes) async {
            name = n;
            content = utf8.decode(bytes);
            return true;
          },
        );
        await tester.tap(find.text('Guardar .pgn'));
        await tester.pumpAndSettle();
        expect(name, matches(RegExp(r'^diagramas-\d{8}-\d{4}\.pgn$')));
        expect(content, contains('[Event "Diagrama 1"]'));
        expect(content, contains('[FEN "'));
        expect(find.textContaining('Guardado: $name'), findsOneWidget);
      },
    );

    testWidgets('a cancelled save shows nothing', (tester) async {
      await loaded(tester, save: (String n, Uint8List bytes) async => false);
      await tester.tap(find.text('Guardar .pgn'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Guardado'), findsNothing);
    });

    testWidgets('"Compartir" offers text or .pgn file', (tester) async {
      String? text;
      String? fileName;
      String? fileContent;
      await loaded(
        tester,
        onText: (String t) async => text = t,
        onFile: (String n, Uint8List b) async {
          fileName = n;
          fileContent = utf8.decode(b);
        },
      );
      await tester.tap(find.text('Compartir'));
      await tester.pumpAndSettle();
      expect(find.text('Como archivo .pgn'), findsOneWidget);
      await tester.tap(find.text('Como texto'));
      await tester.pumpAndSettle();
      expect(text, contains('[Event "Diagrama 1"]'));
      expect(text, contains('[SetUp "1"]'));

      await tester.tap(find.text('Compartir'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Como archivo .pgn'));
      await tester.pumpAndSettle();
      expect(fileName, endsWith('.pgn'));
      expect(fileContent, text);
    });

    testWidgets('the card menu offers FEN, PGN, share and adjust', (
      tester,
    ) async {
      String? text;
      await loaded(tester, onText: (String t) async => text = t);
      await tester.tap(find.byKey(const ValueKey('card-menu')));
      await tester.pumpAndSettle();
      expect(find.text('Copiar FEN'), findsOneWidget);
      expect(find.text('Copiar PGN'), findsOneWidget);
      expect(find.text('Ajustar recorte'), findsNWidgets(2)); // menu + button
      await tester.tap(find.text('Compartir PGN'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Como texto'));
      await tester.pumpAndSettle();
      expect(text, contains('[Event "Diagrama 1"]'));
    });
  });
}
