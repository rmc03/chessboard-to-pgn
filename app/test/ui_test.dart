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
      expect(clipboard, contains('[Event "Diagram 1"]'));
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
}
