// The board must show white and black pieces differently, pawns included, without relying on system fonts
// (on Android the system draws the pawn U+265F as a colour emoji that ignores the text colour).
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chessboard_pgn/src/board_view.dart';
import 'package:chessboard_pgn/src/chess.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _fontFile = 'assets/fonts/ChessFigures.ttf';

void main() {
  setUpAll(() async {
    final loader = FontLoader(figuresFont)
      ..addFont(
        Future.value(ByteData.sublistView(File(_fontFile).readAsBytesSync())),
      );
    await loader.load();
  });

  test('the figures font is declared in the app bundle', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final manifest =
        jsonDecode(await rootBundle.loadString('FontManifest.json')) as List;
    final entry = manifest.cast<Map<String, dynamic>>().firstWhere(
      (f) => f['family'] == figuresFont,
    );
    expect((entry['fonts'] as List).single['asset'], _fontFile);
    await rootBundle.load(_fontFile); // throws if the asset is not packaged
  });

  test('figure code points', () {
    expect(solidFigure(whitePawn), '♟');
    expect(solidFigure(blackPawn), '♟');
    expect(outlineFigure(whitePawn), '♙');
    expect(solidFigure(whiteKing), '♚');
    expect(outlineFigure(blackKing), '♔');
  });

  testWidgets('white and black pieces are drawn in different colours', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(480, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    // row 0: white P N B R Q K + 2 empty; row 1: black p n b r q k + 2 empty (both square colours occur)
    final grid = List<int>.filled(64, 0);
    for (var k = 1; k <= 6; k++) {
      grid[k - 1] = k;
      grid[8 + k - 1] = k + 6;
    }
    grid[16] = blackPawn; // light square (row 2, col 0)
    grid[17] = whitePawn; // dark square
    final key = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: RepaintBoundary(
            key: key,
            child: SizedBox(
              width: 480,
              height: 480,
              child: BoardView(
                grid: grid,
                doubtful: (_) => false,
                onTap: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(key),
    );
    late ui.Image image;
    late ByteData rgba;
    await tester.runAsync(() async {
      image = await boundary.toImage();
      rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final out = Platform.environment['FIGURES_PNG'];
      if (out != null) {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        File(out).writeAsBytesSync(png!.buffer.asUint8List());
      }
    });
    expect(image.width, 480);

    // share of pure white / pure black pixels in a square (the squares themselves are cream and brown)
    (double, double) whiteBlack(int sq) {
      const cell = 60;
      final x0 = (sq % 8) * cell, y0 = (sq ~/ 8) * cell;
      var white = 0, black = 0;
      for (var y = y0; y < y0 + cell; y++) {
        for (var x = x0; x < x0 + cell; x++) {
          final i = 4 * (y * image.width + x);
          final r = rgba.getUint8(i),
              g = rgba.getUint8(i + 1),
              b = rgba.getUint8(i + 2);
          if (r > 235 && g > 235 && b > 235) white++;
          if (r < 40 && g < 40 && b < 40) black++;
        }
      }
      return (white / (cell * cell), black / (cell * cell));
    }

    for (final sq in [0, 1, 2, 3, 4, 5, 17]) {
      final (white, black) = whiteBlack(sq);
      final name = pieceNames[grid[sq]];
      expect(white, greaterThan(0.03), reason: '$name: white body');
      expect(black, greaterThan(0.02), reason: '$name: black outline');
      expect(white, greaterThan(black * 0.5), reason: '$name: mostly white');
    }
    for (final sq in [8, 9, 10, 11, 12, 13, 16]) {
      final (white, black) = whiteBlack(sq);
      final name = pieceNames[grid[sq]];
      expect(white, lessThan(0.002), reason: '$name: no white body');
      expect(black, greaterThan(0.08), reason: '$name: solid black');
    }
    final (emptyWhite, emptyBlack) = whiteBlack(40);
    expect(emptyWhite + emptyBlack, 0);
  });

  testWidgets('the piece picker shows white and black figures', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Material(
          child: Row(
            children: [
              PieceFigure(whitePawn, size: 30),
              PieceFigure(blackPawn, size: 30),
            ],
          ),
        ),
      ),
    );
    expect(find.bySemanticsLabel('peón blanco'), findsOneWidget);
    expect(find.bySemanticsLabel('peón negro'), findsOneWidget);
    // every figure text uses the bundled font, never a system fallback candidate
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      expect(t.style!.fontFamily, figuresFont);
    }
  });
}
