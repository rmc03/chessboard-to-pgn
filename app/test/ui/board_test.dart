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
  theme: buildTheme(stones.first, b),
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
  final i = 4 * (y.floor() * p.width + x.floor());
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
    'doubtful squares get the amber marker, others do not; selected gets the green rule',
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
      final amber = AppTheme.fallback.warningMark;
      expect(amber, BoardMarks.doubt);
      expect(_at(px, corner(21).dx, corner(21).dy), amber);
      expect(_at(px, corner(20).dx, corner(20).dy), isNot(amber));
      // 2 dp rule on the left edge of the doubtful square
      expect(_at(px, cell(21).left + 1, cell(21).center.dy + 12), amber);
      // selected e4 (36): 1 dp white hairline outside a 3 dp green ring
      final deep = selectionTone(stones.first);
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
    'flat, stone and printed styles: stone squares (plain or speckled) versus white paper with black hatching',
    (tester) async {
      final stone = stones.first;
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

        // share of the pixels of a square that have exactly [color]
        double share(int sq, Color color) {
          final rect = layout.cellRect(sq);
          var hit = 0, total = 0;
          for (var y = 3.0; y < rect.height - 3; y++) {
            for (var x = 3.0; x < rect.width - 3; x++) {
              total++;
              if (_at(px, rect.left + x, rect.top + y) == color) hit++;
            }
          }
          return hit / total;
        }

        // a8 (0,0) is light, a7 (1,0) is dark
        if (style == BoardStyle.flat) {
          expect(sample(0, 0, 25, 25), stone.lightSquare);
          expect(sample(1, 0, 25, 25), stone.darkSquare);
          expect(share(0, stone.lightSquare), 1.0);
        } else if (style == BoardStyle.stone) {
          // the speckle is faint: most of the board is still the stone, but not all of it
          var hit = 0.0;
          for (var sq = 0; sq < 64; sq++) {
            final dark = ((sq ~/ 8) + (sq % 8)).isOdd;
            hit += share(sq, dark ? stone.darkSquare : stone.lightSquare);
          }
          expect(hit / 64, inInclusiveRange(0.7, 0.999));
        } else {
          expect(sample(0, 0, 25, 25), BoardMarks.paper);
          var inked = 0, white = 0;
          final rect = layout.cellRect(8);
          for (var y = 2.0; y < rect.height - 2; y++) {
            for (var x = 2.0; x < rect.width - 2; x++) {
              final c = _at(px, rect.left + x, rect.top + y);
              if (c == BoardMarks.paper) white++;
              if (contrastDark(c, BoardMarks.pieceBlack)) inked++;
            }
          }
          expect(inked, greaterThan(300), reason: 'black hatching lines');
          expect(white, greaterThan(300), reason: 'paper between the lines');
        }
      }
    },
  );

  testWidgets(
    'the stone style has a granite frame with a bevel; the other styles have only a margin',
    (tester) async {
      Future<({ByteData data, int width})> render(BoardStyle style) async {
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
        return _pixels(tester);
      }

      final layout = BoardLayout(400, coordinates: false);
      expect(layout.frame, inInclusiveRange(3, 6));
      final stone = await render(BoardStyle.stone);
      // middle of the left band of the frame: granite (dark, grey) and not the background of the page
      final mid = Offset(layout.frame / 2 + 0.5, 200);
      final granite = _at(stone, mid.dx, mid.dy);
      expect(lightnessOf(granite), inInclusiveRange(20, 50));
      // bevel: the outer top-left edge is lighter than the bottom-right edge
      final lit = _at(stone, 200, 0.5), shade = _at(stone, 200, 399.5);
      expect(lightnessOf(lit), greaterThan(lightnessOf(shade)));
      // a dark hairline between frame and squares
      final hair = _at(stone, layout.boardRect.left - 0.5, 200);
      expect(lightnessOf(hair), lessThan(lightnessOf(granite)));
      final flat = await render(BoardStyle.flat);
      expect(
        _at(flat, mid.dx, mid.dy),
        _at(flat, 1, 1),
        reason: 'margin only: same as the corner',
      );
    },
  );

  testWidgets(
    'the terrazzo is deterministic: two renders of the same board are identical',
    (tester) async {
      Future<List<int>> bytes() async {
        await tester.pumpWidget(
          _host(
            BoardView.fromGrid(
              grid: List<int>.filled(64, 0),
              style: BoardStyle.stone,
              showCoordinates: false,
              size: 300,
            ),
            side: 300,
          ),
        );
        final p = await _pixels(tester);
        return p.data.buffer.asUint8List().toList();
      }

      final a = await bytes();
      await tester.pumpWidget(const SizedBox());
      final b = await bytes();
      expect(a, b);
    },
  );

  testWidgets('the doubtful mark glows in the dark theme only', (tester) async {
    Future<({ByteData data, int width})> render(Brightness b) async {
      await tester.pumpWidget(
        _host(
          BoardView(
            diagram: _diagram(),
            showCoordinates: false,
            pieceSetId: PieceSetCatalog.fallbackId,
          ),
          b: b,
        ),
      );
      await tester.pump(const Duration(seconds: 1)); // the theme animation
      return _pixels(tester);
    }

    final layout = BoardLayout(400, coordinates: false);
    final f6 = layout.cellRect(21);
    // just outside the left edge of f6, in the middle of the edge
    final outside = Offset(f6.left - 2, f6.center.dy + 14);
    final plainPx = await render(Brightness.light);
    final glowPx = await render(Brightness.dark);
    await tester.pump(const Duration(seconds: 1));
    final plain = _at(plainPx, outside.dx, outside.dy);
    final glowing = _at(glowPx, outside.dx, outside.dy);
    // a1 square colours differ by tint: the lit one has a warmer red channel than blue
    double warmth(Color c) => c.r - c.b;
    expect(warmth(glowing), greaterThan(warmth(plain)));
    // the ring itself is the lamp amber in the dark theme and the street amber in the light one
    expect(_at(plainPx, f6.left + 1, f6.center.dy + 14), BoardMarks.doubt);
    expect(_at(glowPx, f6.left + 1, f6.center.dy + 14), BoardMarks.doubtLamp);
  });

  testWidgets('hatching continues across the corner of two dark squares', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        BoardView.fromGrid(
          grid: List<int>.filled(64, 0),
          style: BoardStyle.printed,
          showCoordinates: false,
          size: 404,
        ),
        side: 404,
      ),
    );
    final px = await _pixels(tester);
    final layout = BoardLayout(404, coordinates: false);
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
    expect(l.frame, inInclusiveRange(3, 6));
    expect(l.frameRect.left, l.gutter);
    expect(l.frameRect.right, 400);
    expect(l.frameRect.bottom, 400 - l.gutter);
    expect(l.boardRect.left, l.gutter + l.frame);
    expect(l.boardRect.top, l.frame);
    expect(l.boardRect.right, 400 - l.frame);
    expect(l.boardRect.bottom, 400 - l.gutter - l.frame);
    expect(l.boardRect.width, l.board);
    expect(l.cellRect(63).right, 400 - l.frame);
    expect(l.cellRect(0).topLeft, l.boardRect.topLeft);
    expect(BoardLayout(400, coordinates: false).gutter, 0);
    expect(BoardLayout(120, coordinates: true).gutter, 0);
    expect(BoardLayout(120, coordinates: true).frame, 3);
    expect(BoardLayout(120, coordinates: true).board, 114);
    expect(
      BoardLayout(900, coordinates: false).frame,
      6,
      reason: 'scaled, capped at 6 dp',
    );
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
  test(
    'selected ring: 3:1 or more against both squares of every stone, green',
    () {
      for (final stone in stones) {
        final tone = selectionTone(stone);
        expect(
          contrastRatio(tone, stone.lightSquare),
          greaterThanOrEqualTo(3),
          reason: '${stone.id} on light',
        );
        expect(
          contrastRatio(tone, stone.darkSquare),
          greaterThanOrEqualTo(3),
          reason: '${stone.id} on dark',
        );
        // park-bench green (darkened only where that is not enough)
        expect(
          lightnessOf(tone),
          lessThanOrEqualTo(lightnessOf(BoardMarks.selection)),
        );
        final c = HSLColor.fromColor(tone);
        expect(
          c.hue,
          inInclusiveRange(140, 170),
          reason: '${stone.id} stays green',
        );
      }
    },
  );

  testWidgets('selected ring is the same green in the dark theme', (
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
      selectionTone(stones.first),
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
      selectionTone(stones.first),
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
        theme: buildTheme(stones.first, Brightness.light),
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

/// Is [c] close to [ref] (antialiasing tolerance)?
bool contrastDark(Color c, Color ref) =>
    (c.r - ref.r).abs() < 0.04 &&
    (c.g - ref.g).abs() < 0.04 &&
    (c.b - ref.b).abs() < 0.04;
