import 'dart:ui' show Tristate;

import 'package:flutter/services.dart';
import 'package:chessboard_pgn/src/diagram.dart';
import 'package:chessboard_pgn/src/settings.dart';
import 'package:chessboard_pgn/src/ui/board.dart';
import 'package:chessboard_pgn/src/ui/color_math.dart';
import 'package:chessboard_pgn/src/ui/pieces.dart';
import 'package:chessboard_pgn/src/ui/theme.dart';
import 'package:chessboard_pgn/src/ui/tokens.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

final _key = GlobalKey();

Widget _host(
  Widget board, {
  double side = 400,
  Brightness b = Brightness.light,
}) => MaterialApp(
  theme: buildTheme(inks.first, b),
  home: Scaffold(
    body: Center(
      child: RepaintBoundary(
        key: _key,
        child: SizedBox(width: side, height: side, child: board),
      ),
    ),
  ),
);

Diagram _diagram() {
  final d = Diagram.fromPlacement(
    'r1bq1rk1/pp2ppbp/2np1np1/8/3NP3/2N1BP2/PPPQ2PP/2KR1B1R',
  );
  d.confidence[21] = 0.4; // f6, black knight
  return d;
}

/// RGBA pixels of the host's RepaintBoundary.
Future<({ByteData data, int width})> _pixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_key));
  late ByteData data;
  late int width;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    width = image.width;
    data = (await image.toByteData())!;
  });
  return (data: data, width: width);
}

Color _at(({ByteData data, int width}) p, double x, double y) {
  final i = 4 * (y.round() * p.width + x.round());
  return Color.fromARGB(
    p.data.getUint8(i + 3),
    p.data.getUint8(i),
    p.data.getUint8(i + 1),
    p.data.getUint8(i + 2),
  );
}

void main() {
  _extra();
  testWidgets(
    'semantics: every square has its label, doubtful and selected are announced',
    (tester) async {
      final handle = tester.ensureSemantics();
      final d = _diagram();
      await tester.pumpWidget(
        _host(BoardView(diagram: d, onTap: (_) {}, selected: 36)),
      );

      SemanticsData sem(int sq) => tester
          .getSemantics(find.byKey(ValueKey('square-$sq')))
          .getSemanticsData();
      expect(sem(21).label, 'f6, caballo negro, dudosa');
      expect(sem(21).label, d.squareLabel(21));
      expect(sem(0).label, 'a8, torre negra');
      expect(sem(40).label, 'a3, vacía');
      expect(sem(36).flagsCollection.isSelected, Tristate.isTrue);
      expect(sem(35).flagsCollection.isSelected, isNot(Tristate.isTrue));
      expect(sem(21).flagsCollection.isButton, isTrue);
      expect(find.bySemanticsLabel('Tablero'), findsOneWidget);
      handle.dispose();
    },
  );

  testWidgets('the preview is one semantics node', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(BoardView.preview(size: 160)));
    expect(find.bySemanticsLabel('Vista previa del tablero'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'^[a-h][1-8], ')), findsNothing);
    handle.dispose();
  });

  for (final black in [false, true]) {
    testWidgets(
      'taps report the right square (${black ? 'black' : 'white'} at the bottom)',
      (tester) async {
        final taps = <int>[];
        await tester.pumpWidget(
          _host(
            BoardView(
              diagram: _diagram(),
              onTap: taps.add,
              blackAtBottom: black,
            ),
          ),
        );
        final board = tester.getRect(find.byType(BoardView));
        final layout = BoardLayout(board.width, coordinates: true);
        // tap the centre of the screen cell at row 7, column 0 (bottom left) and at row 0, column 7 (top right)
        Offset cell(int r, int c) =>
            board.topLeft + layout.cellRect(r * 8 + c).center;
        await tester.tapAt(cell(7, 0));
        await tester.tapAt(cell(0, 7));
        expect(
          taps,
          black ? [flipSquare(56), flipSquare(7)] : [56, 7],
        ); // a1 / h8 for white, h8 / a1 for black
        // the target of square 17 (b6) sits where it is drawn
        taps.clear();
        await tester.tap(find.byKey(const ValueKey('square-17')));
        expect(taps, [17]);
        final r = tester.getRect(find.byKey(const ValueKey('square-17')));
        expect(
          r.center,
          black
              ? board.topLeft + layout.cellRect(flipSquare(17)).center
              : board.topLeft + layout.cellRect(17).center,
        );
      },
    );
  }

  testWidgets(
    'doubtful squares get the amber marker, others do not; selected gets the primary rule',
    (tester) async {
      await tester.pumpWidget(
        _host(
          BoardView(
            diagram: _diagram(),
            onTap: (_) {},
            selected: 36,
            showCoordinates: false,
            pieceSetId: PieceSetCatalog.fallbackId,
          ),
        ),
      );
      final px = await _pixels(tester);
      final layout = BoardLayout(400, coordinates: false);
      Rect cell(int sq) => layout.cellRect(sq);
      // corner triangle: just inside the top-right corner of f6 (21) is amber, the same spot of e6 (20) is not
      Offset corner(int sq) => Offset(cell(sq).right - 5, cell(sq).top + 5);
      final amber = BoardMarks.doubt;
      expect(_at(px, corner(21).dx, corner(21).dy), amber);
      expect(_at(px, corner(20).dx, corner(20).dy), isNot(amber));
      // 2 dp rule on the left edge of the doubtful square
      expect(_at(px, cell(21).left + 1, cell(21).center.dy + 12), amber);
      // selected e4 (36): 1 dp white hairline outside a 3 dp ring in the deep tone of the ink
      final deep = inkDeepTone(inks.first);
      expect(
        _at(px, cell(36).left + 0.2, cell(36).center.dy + 12),
        BoardMarks.pieceWhite,
      );
      expect(_at(px, cell(36).left + 2.5, cell(36).center.dy + 12), deep);
      expect(
        _at(px, cell(35).left + 2.5, cell(35).center.dy + 12),
        isNot(deep),
      );
    },
  );

  testWidgets(
    'flat and printed styles: ink squares versus white paper with hatching',
    (tester) async {
      final ink = inks.first;
      for (final style in BoardStyle.values) {
        await tester.pumpWidget(
          _host(
            BoardView.fromGrid(
              grid: List<int>.filled(64, 0),
              style: style,
              showCoordinates: false,
              size: 400,
            ),
          ),
        );
        final px = await _pixels(tester);
        final layout = BoardLayout(400, coordinates: false);
        Color sample(int r, int c, double dx, double dy) {
          final rect = layout.cellRect(r * 8 + c);
          return _at(px, rect.left + dx, rect.top + dy);
        }

        // a8 (0,0) is light, a7 (1,0) is dark
        if (style == BoardStyle.flat) {
          expect(sample(0, 0, 25, 25), ink.lightSquare);
          expect(sample(1, 0, 25, 25), ink.darkSquare);
        } else {
          expect(sample(0, 0, 25, 25), BoardMarks.paper);
          var inked = 0, white = 0;
          final rect = layout.cellRect(8);
          for (var y = 2.0; y < rect.height - 2; y++) {
            for (var x = 2.0; x < rect.width - 2; x++) {
              final c = _at(px, rect.left + x, rect.top + y);
              if (c == BoardMarks.paper) white++;
              if (contrastDark(c, ink.seed)) inked++;
            }
          }
          expect(inked, greaterThan(300), reason: 'hatching lines in the ink');
          expect(white, greaterThan(300), reason: 'paper between the lines');
        }
      }
    },
  );

  testWidgets('hatching continues across the corner of two dark squares', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        BoardView.fromGrid(
          grid: List<int>.filled(64, 0),
          style: BoardStyle.printed,
          showCoordinates: false,
          size: 400,
        ),
      ),
    );
    final px = await _pixels(tester);
    final layout = BoardLayout(400, coordinates: false);
    // dark squares (row 1, col 0) and (row 0, col 1) touch at the point (50, 50): the line through that point
    // belongs to both, so both sides of the corner are inked close to it
    final shared = layout.cellRect(8).topRight; // (50, 50)
    bool inked(double x, double y) =>
        _at(px, x, y).r < 0.75; // darker than paper, antialiasing included
    expect(
      inked(shared.dx - 1.0, shared.dy + 1.0),
      isTrue,
      reason: 'dark square below-left of the corner',
    );
    expect(
      inked(shared.dx + 1.0, shared.dy - 1.0),
      isTrue,
      reason: 'dark square above-right of the corner',
    );
  });

  test('layout: coordinates live in a strip outside the squares and disappear on tiny boards', () {
    final l = BoardLayout(400, coordinates: true);
    expect(l.gutter, greaterThanOrEqualTo(14));
    expect(l.boardRect.left, l.gutter);
    expect(l.boardRect.right, 400);
    expect(l.boardRect.bottom, 400 - l.gutter);
    expect(l.cellRect(63).right, 400);
    expect(BoardLayout(400, coordinates: false).gutter, 0);
    expect(BoardLayout(120, coordinates: true).gutter, 0);
    expect(BoardLayout(120, coordinates: true).board, 120);
  });

  testWidgets(
    'orientation flips the drawing: black at the bottom puts a1 at the top right',
    (tester) async {
      final d = Diagram.fromPlacement('8/8/8/8/8/8/8/K6k');
      await tester.pumpWidget(
        _host(
          BoardView(
            diagram: d,
            blackAtBottom: true,
            showCoordinates: false,
            pieceSetId: PieceSetCatalog.fallbackId,
          ),
        ),
      );
      final px = await _pixels(tester);
      final layout = BoardLayout(400, coordinates: false);
      bool hasDark(Rect r) {
        for (var y = r.top + 8; y < r.bottom - 8; y += 2) {
          for (var x = r.left + 8; x < r.right - 8; x += 2) {
            if (_at(px, x, y) == BoardMarks.pieceBlack) return true;
          }
        }
        return false;
      }

      // white king a1 (56) is drawn at screen position 7 (top right), black king h1 (63) at 0 (top left)
      expect(hasDark(layout.cellRect(0)), isTrue); // black king (solid)
      expect(
        hasDark(layout.cellRect(7)),
        isTrue,
      ); // white king has black contour pixels
      expect(hasDark(layout.cellRect(63)), isFalse);
    },
  );

  testWidgets('keyboard: arrows move the cursor and Enter taps that square', (
    tester,
  ) async {
    final taps = <int>[];
    await tester.pumpWidget(
      _host(BoardView(diagram: _diagram(), onTap: taps.add)),
    );
    // give the board focus
    final node = tester
        .widget<Focus>(
          find
              .descendant(
                of: find.byType(BoardView),
                matching: find.byType(Focus),
              )
              .first,
        )
        .focusNode!;
    node.requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(taps, [9]);
  });
}

void _extra() {
  test('selected ring: 3:1 or more against both squares of every ink', () {
    for (final ink in inks) {
      final deep = inkDeepTone(ink);
      expect(
        contrastRatio(deep, ink.lightSquare),
        greaterThanOrEqualTo(3),
        reason: '${ink.id} on light',
      );
      expect(
        contrastRatio(deep, ink.darkSquare),
        greaterThanOrEqualTo(3),
        reason: '${ink.id} on dark',
      );
      // it is the ink's light-theme primary (darkened only where that is not enough), whatever the theme
      final primary = buildTheme(ink, Brightness.light).colorScheme.primary;
      if (!{'madera', 'torneo'}.contains(ink.id)) expect(deep, primary);
      expect(lightnessOf(deep), lessThanOrEqualTo(lightnessOf(primary)));
    }
  });

  testWidgets('selected ring is the same deep tone in the dark theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        BoardView(
          diagram: _diagram(),
          onTap: (_) {},
          selected: 36,
          showCoordinates: false,
          pieceSetId: PieceSetCatalog.fallbackId,
        ),
        b: Brightness.dark,
      ),
    );
    final px = await _pixels(tester);
    final cell = BoardLayout(400, coordinates: false).cellRect(36);
    expect(
      _at(px, cell.left + 2.5, cell.center.dy + 12),
      inkDeepTone(inks.first),
    );
  });

  testWidgets('a doubtful selected square keeps its triangle', (tester) async {
    await tester.pumpWidget(
      _host(
        BoardView(
          diagram: _diagram(),
          onTap: (_) {},
          selected: 21,
          showCoordinates: false,
          pieceSetId: PieceSetCatalog.fallbackId,
        ),
      ),
    );
    final px = await _pixels(tester);
    final cell = BoardLayout(400, coordinates: false).cellRect(21);
    expect(_at(px, cell.right - 8, cell.top + 8), BoardMarks.doubt);
    expect(
      _at(px, cell.left + 2.5, cell.center.dy + 12),
      inkDeepTone(inks.first),
    );
  });

  testWidgets('an edit repaints the board; an unrelated rebuild does not', (
    tester,
  ) async {
    final d = _diagram();
    late StateSetter rebuild;
    var tick = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(inks.first, Brightness.light),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              rebuild = setState;
              return Column(
                children: [
                  Text('$tick'),
                  SizedBox(
                    width: 400,
                    height: 400,
                    child: BoardView(
                      diagram: d,
                      onTap: (_) {},
                      pieceSetId: PieceSetCatalog.fallbackId,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();
    final before = boardPaintCount;
    rebuild(() => tick++);
    await tester.pump();
    expect(boardPaintCount, before, reason: 'same inputs, no repaint');
    d.setSquare(35, 1); // edit in place
    await tester.pump();
    expect(boardPaintCount, greaterThan(before), reason: 'an edit repaints');
  });
}

/// Is [c] close to [ink] (antialiasing tolerance)?
bool contrastDark(Color c, Color ink) =>
    (c.r - ink.r).abs() < 0.04 &&
    (c.g - ink.g).abs() < 0.04 &&
    (c.b - ink.b).abs() < 0.04;
