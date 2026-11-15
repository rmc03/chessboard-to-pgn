// The board: an 8x8 diagram laid in the stone of the setting, as a stone table of a plaza would be.
//
// Everything that is not interactive (frame, squares, speckle, hatching, rule, coordinates, pieces, marks) is
// painted by one [CustomPainter], so the board is crisp at any size (about 120 dp for a thumbnail up to 560 dp
// and more) and cheap to repaint. Taps and accessibility go through a transparent layer of 64 targets on top.
//
// Layout. The widget is a square of side S. With coordinates on, the files (a-h) go in a strip under the board
// and the ranks (1-8) in a strip at its left ([BoardLayout.gutter]), so letters and numbers never touch a
// piece. The rest is the framed board: a frame of 3-6 dp ([BoardLayout.frame], the polished granite of the
// `stone` style, plain margin in the other styles) around the 8x8 squares ([BoardLayout.boardRect]).
//
// Square indices are the ones of Diagram (0 = a8 ... 63 = h1, always from White's side). `blackAtBottom`
// only changes where a square is drawn (via [flipSquare]); callbacks keep reporting Diagram indices.
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../chess.dart';
import '../diagram.dart';
import '../settings.dart';
import 'color_math.dart';
import 'pieces.dart';
import 'scope.dart';
import 'theme.dart';
import 'tokens.dart';

/// A real middlegame (Sicilian Dragon, Yugoslav attack) with every piece type of both colours: the position
/// of the previews in Ajustes and of the first-run example.
const String samplePlacement =
    'r1bq1rk1/pp2ppbp/2np1np1/8/3NP3/2N1BP2/PPPQ2PP/2KR1B1R';

/// [samplePlacement] as a grid (White's side).
List<int> sampleGrid() => placementToGrid(samplePlacement);

/// The colour of the selection ring on [stone]: park-bench green, the same in both themes (the board is the
/// constant of the design), darkened toward black in 4 % steps until it keeps 3.2:1 or more against both
/// squares of the stone, so the ring reads on the light and on the dark square.
Color selectionTone(Stone stone) => _selectionTones.putIfAbsent(stone.id, () {
  var c = BoardMarks.selection;
  for (var i = 0; i < 24; i++) {
    if (contrastRatio(c, stone.lightSquare) >= 3.2 &&
        contrastRatio(c, stone.darkSquare) >= 3.2) {
      break;
    }
    c = Color.lerp(c, const Color(0xFF000000), 0.04)!;
  }
  // on the 8-bit grid, so what is painted equals what is asked for
  int byte(double v) => (v * 255).round();
  return Color.fromARGB(255, byte(c.r), byte(c.g), byte(c.b));
});

final Map<String, Color> _selectionTones = {};

/// Counts calls of the board painters' `paint` (tests check that unrelated rebuilds do not repaint).
@visibleForTesting
int boardPaintCount = 0;

/// Where the parts of a board of side [side] are. Use it to overlay something exactly on the squares (for
/// instance the original crop in the "Original" comparator: [boardRect]).
class BoardLayout {
  factory BoardLayout(double side, {required bool coordinates}) {
    final gutter = coordinates && side >= minSideForCoordinates
        ? (side * 0.045).clamp(14.0, 20.0)
        : 0.0;
    final framed = side - gutter;
    final frame = frameWidthFor(framed);
    return BoardLayout._(side, gutter, frame, framed - 2 * frame);
  }

  const BoardLayout._(this.side, this.gutter, this.frame, this.board);

  /// Below this side the coordinates are left out automatically (they would not be legible).
  static const double minSideForCoordinates = 168;

  /// Width of the frame of a framed board of side [framed]: 3 to 6 dp, scaled with the board.
  static double frameWidthFor(double framed) =>
      (framed * 0.018).clamp(3.0, 6.0);

  final double side;

  /// Width of the strip with the ranks and height of the strip with the files; 0 without coordinates.
  final double gutter;

  /// Width of the frame around the squares (3-6 dp). Painted as granite in the `stone` style and left as plain
  /// margin in the others, so the squares never move when the style changes.
  final double frame;

  /// Side of the 8x8 squares.
  final double board;

  double get cell => board / 8;

  /// The framed board (frame included), inside the widget without the coordinate strips.
  Rect get frameRect =>
      Rect.fromLTWH(gutter, 0, board + 2 * frame, board + 2 * frame);

  /// The 8x8 squares inside the widget (inside the frame).
  Rect get boardRect => Rect.fromLTWH(gutter + frame, frame, board, board);

  /// The square drawn at screen position [index] (0..63, row-major from the top-left).
  Rect cellRect(int index) => Rect.fromLTWH(
    gutter + frame + (index % 8) * cell,
    frame + (index ~/ 8) * cell,
    cell,
    cell,
  );
}

/// An interactive or static board.
///
/// ```dart
/// BoardView(diagram: d, onTap: (sq) => edit(sq), selected: editing)   // follows the diagram's edits
/// BoardView.fromGrid(grid: g, doubtful: (sq) => false)                // plain grid
/// BoardView.preview(size: 120)                                        // static, no coordinates, sample position
/// ```
/// Style, coordinates and piece set come from the settings in the `AppScope` unless given.
class BoardView extends StatefulWidget {
  /// Draws [diagram] and repaints when it changes. Semantics use [Diagram.squareLabel].
  BoardView({
    super.key,
    required Diagram this.diagram,
    this.onTap,
    this.selected,
    this.blackAtBottom = false,
    this.showDoubts = true,
    this.style,
    this.showCoordinates,
    this.stone,
    this.pieceSetId,
    this.catalog,
    this.size,
    this.semanticLabel,
  }) : grid = diagram.grid,
       doubtful = diagram.isDoubtful,
       squareLabel = diagram.squareLabel,
       listenable = diagram;

  /// Draws a bare [grid] (64 class ids from White's side).
  const BoardView.fromGrid({
    super.key,
    required List<int> this.grid,
    this.doubtful,
    this.squareLabel,
    this.onTap,
    this.selected,
    this.blackAtBottom = false,
    this.showDoubts = true,
    this.style,
    this.showCoordinates,
    this.stone,
    this.pieceSetId,
    this.catalog,
    this.size,
    this.semanticLabel,
  }) : diagram = null,
       listenable = null;

  /// A small non-interactive board for previews, thumbnails and the empty state: no coordinates unless asked,
  /// one semantics node ("Vista previa del tablero"), the sample position unless [grid] is given.
  BoardView.preview({
    super.key,
    List<int>? grid,
    this.blackAtBottom = false,
    this.style,
    this.showCoordinates = false,
    this.stone,
    this.pieceSetId,
    this.catalog,
    this.size,
    this.semanticLabel = 'Vista previa del tablero',
  }) : grid = grid ?? sampleGrid(),
       diagram = null,
       doubtful = null,
       squareLabel = null,
       onTap = null,
       selected = null,
       showDoubts = false,
       listenable = null;

  final Diagram? diagram;
  final List<int>? grid;

  /// Which squares (Diagram indices) carry the doubtful mark.
  final bool Function(int square)? doubtful;

  /// Accessibility label of a square; default "e4, caballo blanco" (plus ", dudosa").
  final String Function(int square)? squareLabel;
  final Listenable? listenable;

  /// A square was tapped (Diagram index). Without it the board is not interactive.
  final void Function(int square)? onTap;

  /// The square being edited (Diagram index): wash and 3 dp green ring (see [selectionTone]) with a white
  /// outer hairline.
  final int? selected;

  /// Draw the board from Black's side (a1 at the top right).
  final bool blackAtBottom;

  /// Draw the doubtful marks (amber 2 dp ring with a dark hairline and a folded-corner triangle).
  final bool showDoubts;

  /// Overrides the board style of the settings.
  final BoardStyle? style;

  /// Overrides the coordinates setting.
  final bool? showCoordinates;

  /// Draw with this stone instead of the one of the theme (the gallery shows all five).
  final Stone? stone;

  /// Overrides the piece set of the settings.
  final String? pieceSetId;
  final PieceSetCatalog? catalog;

  /// Fixed side; by default the largest square that fits the constraints.
  final double? size;

  /// When given the board is a single accessibility node with this label and its squares are hidden.
  final String? semanticLabel;

  /// Layout of a board of side [side] (see [BoardLayout]).
  static BoardLayout layoutFor(double side, {required bool coordinates}) =>
      BoardLayout(side, coordinates: coordinates);

  @override
  State<BoardView> createState() => _BoardViewState();
}

class _BoardViewState extends State<BoardView> {
  static final PieceSetCatalog _builtIn = PieceSetCatalog.builtIn();

  final FocusNode _focus = FocusNode(debugLabel: 'BoardView');
  int? _pressed; // Diagram index
  int _cursor = 0; // screen index of the keyboard cursor
  bool _focused = false;

  PieceSetCatalog _catalog = _builtIn;
  String _setId = PieceSetCatalog.fallbackId;

  bool get _interactive => widget.onTap != null;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  int _squareAt(int screenIndex) =>
      widget.blackAtBottom ? flipSquare(screenIndex) : screenIndex;

  String _labelOf(int sq) {
    final custom = widget.squareLabel;
    if (custom != null) return custom(sq);
    final grid = widget.grid!;
    final doubt = widget.showDoubts && (widget.doubtful?.call(sq) ?? false);
    return '${squareName(sq)}, ${pieceNames[grid[sq]]}${doubt ? ', dudosa' : ''}';
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (!_interactive || event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    var r = _cursor ~/ 8, c = _cursor % 8;
    if (key == LogicalKeyboardKey.arrowLeft) {
      c = math.max(0, c - 1);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      c = math.min(7, c + 1);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      r = math.max(0, r - 1);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      r = math.min(7, r + 1);
    } else if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter ||
        key == LogicalKeyboardKey.space) {
      if (event is KeyDownEvent) widget.onTap!(_squareAt(_cursor));
      return KeyEventResult.handled;
    } else {
      return KeyEventResult.ignored;
    }
    setState(() => _cursor = r * 8 + c);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.maybeOf(context);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final app = AppTheme.of(context);
    final style =
        widget.style ?? scope?.settings.boardStyle ?? BoardStyle.stone;
    final wantCoordinates =
        widget.showCoordinates ?? scope?.settings.showCoordinates ?? true;
    _catalog = widget.catalog ?? scope?.catalog ?? _builtIn;
    _setId =
        widget.pieceSetId ??
        scope?.settings.pieceSetId ??
        PieceSetCatalog.fallbackId;
    unawaited(_catalog.ensureLoaded(_setId));

    return LayoutBuilder(
      builder: (context, constraints) {
        final fit = math.min(
          constraints.maxWidth.isFinite ? constraints.maxWidth : 320.0,
          constraints.maxHeight.isFinite ? constraints.maxHeight : 320.0,
        );
        // Accepted exception to the 48 dp target: the board fills the width, so a phone cell is about 40 dp;
        // squares are tapped one at a time and a visible confirmation sheet follows.
        final side = widget.size ?? fit;
        final layout = BoardLayout(side, coordinates: wantCoordinates);
        final labelStyle = (theme.textTheme.labelSmall ?? const TextStyle())
            .copyWith(color: scheme.onSurfaceVariant);

        final listenable = Listenable.merge([
          if (widget.listenable != null) widget.listenable!,
        ]);
        return ListenableBuilder(
          listenable: listenable,
          builder: (context, _) {
            final grid = widget.grid!;
            final doubts = List<bool>.generate(
              64,
              (sq) => widget.showDoubts && (widget.doubtful?.call(sq) ?? false),
            );
            final painter = _BoardPainter(
              layout: layout,
              grid: List<int>.of(grid),
              doubts: doubts,
              selected: widget.selected,
              pressed: _pressed,
              cursor: _interactive && _focused && _highlightFocus
                  ? _squareAt(_cursor)
                  : null,
              blackAtBottom: widget.blackAtBottom,
              style: style,
              light: widget.stone?.lightSquare ?? app.boardLight,
              dark: widget.stone?.darkSquare ?? app.boardDark,
              hatch: app.boardHatch,
              paper: app.boardPaper,
              frameColor: app.stoneFrame,
              rule: scheme.outline,
              tone: selectionTone(widget.stone ?? app.stone),
              mark: app.warningMark,
              glow: app.lampGlow,
              labelStyle: labelStyle,
              showCoordinates: layout.gutter > 0,
              catalog: _catalog,
              setId: _setId,
            );
            Widget board = RepaintBoundary(
              child: CustomPaint(
                size: Size.square(side),
                painter: painter,
                isComplex: true,
              ),
            );
            if (widget.semanticLabel != null) {
              board = Semantics(
                label: widget.semanticLabel,
                image: true,
                excludeSemantics: true,
                child: board,
              );
            } else {
              board = Stack(children: [board, ..._targets(layout)]);
              board = Semantics(
                container: true,
                explicitChildNodes: true,
                label: 'Tablero',
                child: board,
              );
              if (_interactive) {
                board = Focus(
                  focusNode: _focus,
                  onKeyEvent: _onKey,
                  onFocusChange: (f) => setState(() => _focused = f),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: board,
                  ),
                );
              }
            }
            return Align(
              alignment: Alignment.topLeft,
              widthFactor: 1,
              heightFactor: 1,
              child: SizedBox.square(dimension: side, child: board),
            );
          },
        );
      },
    );
  }

  bool get _highlightFocus =>
      FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

  List<Widget> _targets(BoardLayout layout) {
    return [
      for (var i = 0; i < 64; i++) _target(i, _squareAt(i), layout.cellRect(i)),
    ];
  }

  Widget _target(int screenIndex, int sq, Rect rect) {
    final selected = widget.selected == sq;
    Widget target = Semantics(
      label: _labelOf(sq),
      button: _interactive,
      selected: selected,
      excludeSemantics: true,
      child: const SizedBox.expand(),
    );
    if (_interactive) {
      target = GestureDetector(
        key: ValueKey('square-$sq'),
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = sq),
        onTapUp: (_) => setState(() => _pressed = null),
        onTapCancel: () => setState(() => _pressed = null),
        onTap: () {
          _cursor = screenIndex;
          widget.onTap!(sq);
        },
        child: target,
      );
    } else {
      target = KeyedSubtree(key: ValueKey('square-$sq'), child: target);
    }
    return Positioned.fromRect(rect: rect, child: target);
  }
}

// ------------------------------------------------------------------------------------------------ texture

/// Small polygons (the chips of terrazzo or the grains of granite) scattered over a [side] x [side] square,
/// recorded once as a [ui.Picture]. Deterministic: the same seed and size always give the same stone, so the
/// board never shimmers between frames or between theme changes.
ui.Picture _chipPicture({
  required double side,
  required List<(Color, double)> tones,
  required List<double> radii,
  required double unit,
  required int count,
  required int seed,
  Rect? hole,
}) {
  final rnd = math.Random(seed);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder, Rect.fromLTWH(0, 0, side, side));
  var placed = 0, tries = 0;
  while (placed < count && tries < count * 20) {
    tries++;
    final cx = rnd.nextDouble() * side, cy = rnd.nextDouble() * side;
    // draw the random numbers of a chip whether it is kept or not, so a hole never changes the others
    final r =
        radii[rnd.nextInt(radii.length)] *
        (0.8 + rnd.nextDouble() * 0.4) *
        unit;
    final sides = const [4, 5, 5, 6][rnd.nextInt(4)];
    final a0 = rnd.nextDouble() * math.pi * 2;
    final tone = tones[rnd.nextInt(tones.length)];
    final jitter = List<double>.generate(sides, (_) => rnd.nextDouble());
    final rj = List<double>.generate(sides, (_) => rnd.nextDouble());
    if (hole != null && hole.inflate(r).contains(Offset(cx, cy))) continue;
    placed++;
    final path = Path();
    for (var k = 0; k < sides; k++) {
      final a = a0 + k * math.pi * 2 / sides + (jitter[k] - 0.5) * 0.7;
      final rr = r * (0.65 + rj[k] * 0.5);
      final pt = Offset(cx + rr * math.cos(a), cy + rr * math.sin(a));
      k == 0 ? path.moveTo(pt.dx, pt.dy) : path.lineTo(pt.dx, pt.dy);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()..color = tone.$1.withValues(alpha: tone.$2 * 0.8),
    );
  }
  return recorder.endRecording();
}

final Map<String, ui.Picture> _pictureCache = {};

ui.Picture _cached(String key, ui.Picture Function() make) {
  if (_pictureCache.length > 24) _pictureCache.clear();
  return _pictureCache.putIfAbsent(key, make);
}

/// The terrazzo of the squares: about 230 chips per 300 dp, drawn over light and dark squares alike (dark chips
/// show on the light squares, pale ones on the dark squares). Cached per board size.
void paintTerrazzo(Canvas canvas, Rect board) {
  final side = board.width;
  if (side <= 0) return;
  final unit = math.max(side / 300, 0.55);
  final count = (230 * math.pow(side / (300 * unit), 2)).round().clamp(8, 700);
  final picture = _cached(
    'terrazzo/${(side * 2).round()}',
    () => _chipPicture(
      side: side,
      tones: BoardTexture.terrazzo,
      radii: const [0.7, 0.9, 1.1, 1.3, 1.6, 2.0, 2.6],
      unit: unit,
      count: count,
      seed: 7,
    ),
  );
  canvas.save();
  canvas.clipRect(board);
  canvas.translate(board.left, board.top);
  canvas.drawPicture(picture);
  canvas.restore();
}

// ------------------------------------------------------------------------------------------------ paint

class _BoardPainter extends CustomPainter {
  _BoardPainter({
    required this.layout,
    required this.grid,
    required this.doubts,
    required this.selected,
    required this.pressed,
    required this.cursor,
    required this.blackAtBottom,
    required this.style,
    required this.light,
    required this.dark,
    required this.hatch,
    required this.paper,
    required this.frameColor,
    required this.rule,
    required this.tone,
    required this.mark,
    required this.glow,
    required this.labelStyle,
    required this.showCoordinates,
    required this.catalog,
    required this.setId,
  }) : super(repaint: catalog);

  final BoardLayout layout;
  final List<int> grid;
  final List<bool> doubts;
  final int? selected, pressed, cursor;
  final bool blackAtBottom, showCoordinates, glow;
  final BoardStyle style;
  final Color light, dark, hatch, paper, frameColor, rule, tone, mark;
  final TextStyle labelStyle;
  final PieceSetCatalog catalog;
  final String setId;

  int _squareAt(int i) => blackAtBottom ? flipSquare(i) : i;

  @override
  void paint(Canvas canvas, Size size) {
    boardPaintCount++;
    final board = layout.boardRect;
    final cell = layout.cell;

    if (style == BoardStyle.stone) _paintFrame(canvas);
    paintBoardSquares(
      canvas,
      board,
      8,
      style: style,
      light: light,
      dark: dark,
      hatch: hatch,
      paper: paper,
    );
    if (showCoordinates) _paintCoordinates(canvas, cell);

    // state layers under the pieces
    for (var i = 0; i < 64; i++) {
      final sq = _squareAt(i);
      if (sq == pressed) {
        canvas.drawRect(
          layout.cellRect(i),
          Paint()..color = BoardMarks.pieceBlack.withValues(alpha: 0.14),
        );
      }
      if (sq == selected) {
        canvas.drawRect(
          layout.cellRect(i),
          Paint()..color = tone.withValues(alpha: 0.2),
        );
      }
      if (doubts[sq]) {
        canvas.drawRect(
          layout.cellRect(i),
          Paint()..color = mark.withValues(alpha: glow ? 0.34 : 0.30),
        );
      }
    }

    // the rule around the squares: a hairline in the frame, 1 dp in `outline` (flat) or black (printed)
    switch (style) {
      case BoardStyle.stone:
        canvas.drawRect(
          board.inflate(0.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = BoardTexture.hairline,
        );
      case BoardStyle.flat:
        canvas.drawRect(
          board.deflate(0.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = rule,
        );
      case BoardStyle.printed:
        canvas.drawRect(
          board.deflate(0.75),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = hatch,
        );
    }

    for (var i = 0; i < 64; i++) {
      final cls = grid[_squareAt(i)];
      if (cls != 0) {
        paintPiece(canvas, layout.cellRect(i), cls, catalog, setId);
      }
    }

    for (var i = 0; i < 64; i++) {
      final sq = _squareAt(i);
      final rect = layout.cellRect(i);
      final isSelected = sq == selected;
      if (isSelected) _paintSelected(canvas, rect, cell);
      if (doubts[sq]) _paintDoubt(canvas, rect, cell, ringed: isSelected);
      if (sq == cursor) _paintCursor(canvas, rect);
    }
  }

  /// Polished granite: a 135 degree gradient, fine grains, a light top-left edge and a shaded bottom-right edge.
  void _paintFrame(Canvas canvas) {
    final outer = layout.frameRect;
    final rrect = RRect.fromRectAndRadius(outer, const Radius.circular(3));
    canvas.drawRRect(
      rrect,
      Paint()
        ..shader = ui.Gradient.linear(
          outer.topLeft,
          outer.bottomRight,
          [
            Color.lerp(frameColor, BoardMarks.pieceWhite, 0.22)!,
            frameColor,
            Color.lerp(frameColor, BoardMarks.pieceBlack, 0.25)!,
          ],
          const [0, 0.4, 1],
        ),
    );
    final band = Path.combine(
      PathOperation.difference,
      Path()..addRRect(rrect),
      Path()..addRect(layout.boardRect),
    );
    final side = outer.width;
    final grains = _cached(
      'granite/${(side * 2).round()}/${(layout.frame * 2).round()}',
      () => _chipPicture(
        side: side,
        tones: BoardTexture.granite,
        radii: const [0.4, 0.55, 0.7, 0.9],
        unit: 1,
        count: (4 * side * layout.frame / 40).round(),
        seed: 11,
        hole: layout.boardRect.shift(-outer.topLeft),
      ),
    );
    canvas.save();
    canvas.clipPath(band);
    canvas.translate(outer.left, outer.top);
    canvas.drawPicture(grains);
    canvas.restore();
    // bevel
    Paint edge(Color c) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round
      ..color = c;
    final lit = edge(BoardTexture.bevelLight),
        shade = edge(BoardTexture.bevelShade);
    canvas.drawLine(
      Offset(outer.left + 3, outer.top + 0.5),
      Offset(outer.right - 3, outer.top + 0.5),
      lit,
    );
    canvas.drawLine(
      Offset(outer.left + 0.5, outer.top + 3),
      Offset(outer.left + 0.5, outer.bottom - 3),
      lit,
    );
    canvas.drawLine(
      Offset(outer.left + 3, outer.bottom - 0.5),
      Offset(outer.right - 3, outer.bottom - 0.5),
      shade,
    );
    canvas.drawLine(
      Offset(outer.right - 0.5, outer.top + 3),
      Offset(outer.right - 0.5, outer.bottom - 3),
      shade,
    );
  }

  void _paintCoordinates(Canvas canvas, double cell) {
    TextPainter label(String text) => TextPainter(
      text: TextSpan(text: text, style: labelStyle),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    final g = layout.gutter;
    final bottom = layout.frameRect.bottom;
    for (var c = 0; c < 8; c++) {
      final tp = label('abcdefgh'[blackAtBottom ? 7 - c : c]);
      tp.paint(
        canvas,
        Offset(
          layout.boardRect.left + (c + 0.5) * cell - tp.width / 2,
          bottom + (g - tp.height) / 2,
        ),
      );
    }
    for (var r = 0; r < 8; r++) {
      final tp = label('${blackAtBottom ? r + 1 : 8 - r}');
      tp.paint(
        canvas,
        Offset(
          (g - tp.width) / 2,
          layout.boardRect.top + (r + 0.5) * cell - tp.height / 2,
        ),
      );
    }
  }

  /// A lamp-amber ring of 2 dp inside a dark hairline, plus a folded-corner triangle in the top right: the mark
  /// is a shape, not only a colour, and the hairline keeps it readable on light, mid-tone and hatched squares
  /// alike. In the dark theme a faint halo of lamp light spills outside the square.
  /// When [ringed] (the square is also selected) the selection ring owns the edge: only the triangle is drawn,
  /// inside the ring.
  void _paintDoubt(
    Canvas canvas,
    Rect rect,
    double cell, {
    bool ringed = false,
  }) {
    final thin = cell < 24;
    var width = thin ? 1.0 : 2.0;
    if (glow && !ringed) _paintGlow(canvas, rect, cell);
    if (ringed) {
      width = _selectedWidth(cell) + 2;
    } else {
      canvas.drawRect(
        rect.deflate(width / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..color = mark,
      );
      canvas.drawRect(
        rect.deflate(width + 0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = BoardMarks.doubtEdge,
      );
    }
    final t = math.max(cell * 0.36, 7.0).clamp(7.0, 22.0);
    final tri = Path()
      ..moveTo(rect.right - t, rect.top + width)
      ..lineTo(rect.right - width, rect.top + width)
      ..lineTo(rect.right - width, rect.top + t)
      ..close();
    canvas.drawPath(tri, Paint()..color = mark);
    canvas.drawPath(
      tri,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..strokeJoin = StrokeJoin.round
        ..color = BoardMarks.doubtEdge,
    );
  }

  void _paintGlow(Canvas canvas, Rect rect, double cell) {
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(rect.inflate(cell * 0.5)),
      Path()..addRect(rect),
    );
    canvas.save();
    canvas.clipPath(outside);
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, cell * 0.09)
        ..color = mark.withValues(alpha: 0.6),
    );
    canvas.restore();
  }

  double _selectedWidth(double cell) => cell < 24 ? 2.0 : 3.0;

  /// 3 dp ring in park-bench green (darkened per stone, see [selectionTone]) under a 1 dp white outer
  /// hairline: the same in both themes, so it keeps 3:1 against the light and the dark squares.
  void _paintSelected(Canvas canvas, Rect rect, double cell) {
    final w = _selectedWidth(cell);
    canvas.drawRect(
      rect.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = BoardMarks.pieceWhite,
    );
    canvas.drawRect(
      rect.deflate(1 + w / 2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = w
        ..color = tone,
    );
  }

  /// Keyboard focus: black ring with a white ring inside it.
  void _paintCursor(Canvas canvas, Rect rect) {
    canvas.drawRect(
      rect.deflate(1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = BoardMarks.pieceBlack,
    );
    canvas.drawRect(
      rect.deflate(3),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = BoardMarks.pieceWhite,
    );
  }

  /// Repaints only when something drawn changed. [grid] and [doubts] are copies taken at build time, so a
  /// Diagram edited in place compares by content. (The catalogue repaints through `repaint: catalog`.)
  @override
  bool shouldRepaint(_BoardPainter old) =>
      layout.side != old.layout.side ||
      layout.gutter != old.layout.gutter ||
      selected != old.selected ||
      pressed != old.pressed ||
      cursor != old.cursor ||
      blackAtBottom != old.blackAtBottom ||
      showCoordinates != old.showCoordinates ||
      style != old.style ||
      light != old.light ||
      dark != old.dark ||
      hatch != old.hatch ||
      paper != old.paper ||
      frameColor != old.frameColor ||
      rule != old.rule ||
      tone != old.tone ||
      mark != old.mark ||
      glow != old.glow ||
      labelStyle != old.labelStyle ||
      !identical(catalog, old.catalog) ||
      setId != old.setId ||
      !listEquals(grid, old.grid) ||
      !listEquals(doubts, old.doubts);
}

/// Paints a [cells] x [cells] chequered area in [board]: flat squares (with the terrazzo speckle in the `stone`
/// style), or white paper with the dark squares hatched in black. a1 (bottom left) is dark.
void paintBoardSquares(
  Canvas canvas,
  Rect board,
  int cells, {
  required BoardStyle style,
  required Color light,
  required Color dark,
  required Color hatch,
  required Color paper,
}) {
  final cell = board.width / cells;
  Rect at(int r, int c) =>
      Rect.fromLTWH(board.left + c * cell, board.top + r * cell, cell, cell);
  if (style != BoardStyle.printed) {
    canvas.drawRect(board, Paint()..color = light);
    final darkPaint = Paint()..color = dark;
    for (var r = 0; r < cells; r++) {
      for (var c = 0; c < cells; c++) {
        if ((r + c).isOdd) canvas.drawRect(at(r, c), darkPaint);
      }
    }
    if (style == BoardStyle.stone) paintTerrazzo(canvas, board);
    return;
  }
  // printed: white paper, dark squares hatched in black
  canvas.drawRect(board, Paint()..color = paper);
  final darkSquares = Path();
  for (var r = 0; r < cells; r++) {
    for (var c = 0; c < cells; c++) {
      if ((r + c).isOdd) darkSquares.addRect(at(r, c));
    }
  }
  // One lattice of 45-degree lines for the whole board whose spacing divides the cell, so every line passes
  // through the corners where two dark squares meet and neighbouring squares hatch in step.
  final n = (cell / 5.5).round().clamp(3, 12);
  final step = cell / n;
  final lines = Path();
  for (var k = 1; k < 2 * cells * n; k++) {
    final d = k * step;
    if (d <= board.width) {
      lines.moveTo(board.left + d, board.top);
      lines.lineTo(board.left, board.top + d);
    } else {
      final e = d - board.width;
      lines.moveTo(board.right, board.top + e);
      lines.lineTo(board.left + e, board.bottom);
    }
  }
  canvas.save();
  canvas.clipPath(darkSquares);
  canvas.drawPath(
    lines,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = step * 0.32
      ..strokeCap = StrokeCap.butt
      ..isAntiAlias = true
      ..color = hatch,
  );
  canvas.restore();
}

/// A [size] square of the board in [stone] (2 x 2 squares, with the terrazzo speckle) with its 1 dp rule: the
/// swatch of a stone in Ajustes. Static; hidden from semantics (the label is next to it).
class StoneSample extends StatelessWidget {
  const StoneSample({super.key, required this.stone, required this.size});

  final Stone stone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: RepaintBoundary(
          child: CustomPaint(
            painter: _StoneSamplePainter(
              stone.lightSquare,
              stone.darkSquare,
              scheme.outline,
            ),
          ),
        ),
      ),
    );
  }
}

class _StoneSamplePainter extends CustomPainter {
  const _StoneSamplePainter(this.light, this.dark, this.rule);

  final Color light, dark, rule;

  @override
  void paint(Canvas canvas, Size size) {
    final board = Offset.zero & size;
    paintBoardSquares(
      canvas,
      board,
      2,
      style: BoardStyle.stone,
      light: light,
      dark: dark,
      hatch: BoardMarks.pieceBlack,
      paper: BoardMarks.paper,
    );
    canvas.drawRect(
      board.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = rule,
    );
  }

  @override
  bool shouldRepaint(_StoneSamplePainter old) =>
      light != old.light || dark != old.dark || rule != old.rule;
}

/// Four squares with a white and a black knight and king of piece set [setId], in the board style and stone
/// of the settings: the thumbnail of a piece set in Ajustes. Static; one semantics node with [semanticLabel].
class SetPreview extends StatefulWidget {
  const SetPreview({
    super.key,
    required this.setId,
    required this.size,
    this.style,
    this.stone,
    this.catalog,
    this.semanticLabel,
  });

  final String setId;
  final double size;
  final BoardStyle? style;
  final Stone? stone;
  final PieceSetCatalog? catalog;
  final String? semanticLabel;

  @override
  State<SetPreview> createState() => _SetPreviewState();
}

class _SetPreviewState extends State<SetPreview> {
  static final PieceSetCatalog _builtIn = PieceSetCatalog.builtIn();
  PieceSetCatalog _catalog = _builtIn;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _catalog = widget.catalog ?? AppScope.maybeOf(context)?.catalog ?? _builtIn;
    unawaited(_catalog.ensureLoaded(widget.setId));
  }

  @override
  void didUpdateWidget(SetPreview old) {
    super.didUpdateWidget(old);
    unawaited(_catalog.ensureLoaded(widget.setId));
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.maybeOf(context);
    final app = AppTheme.of(context);
    final scheme = Theme.of(context).colorScheme;
    final painter = _SetPreviewPainter(
      catalog: _catalog,
      setId: widget.setId,
      style: widget.style ?? scope?.settings.boardStyle ?? BoardStyle.stone,
      light: widget.stone?.lightSquare ?? app.boardLight,
      dark: widget.stone?.darkSquare ?? app.boardDark,
      hatch: app.boardHatch,
      paper: app.boardPaper,
      rule: scheme.outline,
    );
    final paint = SizedBox.square(
      dimension: widget.size,
      child: RepaintBoundary(child: CustomPaint(painter: painter)),
    );
    return widget.semanticLabel == null
        ? ExcludeSemantics(child: paint)
        : Semantics(
            label: widget.semanticLabel,
            image: true,
            excludeSemantics: true,
            child: paint,
          );
  }
}

class _SetPreviewPainter extends CustomPainter {
  _SetPreviewPainter({
    required this.catalog,
    required this.setId,
    required this.style,
    required this.light,
    required this.dark,
    required this.hatch,
    required this.paper,
    required this.rule,
  }) : super(repaint: catalog);

  final PieceSetCatalog catalog;
  final String setId;
  final BoardStyle style;
  final Color light, dark, hatch, paper, rule;

  // white knight on light, black knight on dark / white king on dark, black king on light
  static const _pieces = [2, 8, 6, 12];

  @override
  void paint(Canvas canvas, Size size) {
    boardPaintCount++;
    final board = Offset.zero & size;
    paintBoardSquares(
      canvas,
      board,
      2,
      style: style,
      light: light,
      dark: dark,
      hatch: hatch,
      paper: paper,
    );
    canvas.drawRect(
      board.deflate(0.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = style == BoardStyle.printed ? hatch : rule,
    );
    final cell = size.width / 2;
    for (var i = 0; i < 4; i++) {
      paintPiece(
        canvas,
        Rect.fromLTWH((i % 2) * cell, (i ~/ 2) * cell, cell, cell),
        _pieces[i],
        catalog,
        setId,
      );
    }
  }

  @override
  bool shouldRepaint(_SetPreviewPainter old) =>
      !identical(catalog, old.catalog) ||
      setId != old.setId ||
      style != old.style ||
      light != old.light ||
      dark != old.dark ||
      hatch != old.hatch ||
      paper != old.paper ||
      rule != old.rule;
}

/// One piece on a square of the stone, framed by the 1 dp rule (3 dp `primary` when [selected]). Use it
/// wherever a piece is shown outside a board (the square editor sheet, pickers): black pieces are invisible on a
/// dark tonal surface, so a piece always sits on a board square. [size] is the side of the tile; it is also at
/// least a 48 dp target when you wrap it in an InkWell of that size.
class PieceTile extends StatelessWidget {
  const PieceTile(
    this.cls, {
    super.key,
    this.size = 48,
    this.selected = false,
    this.dark = false,
    this.catalog,
    this.setId,
  });

  /// Class id 1..12.
  final int cls;
  final double size;
  final bool selected;

  /// Use the dark square of the stone instead of the light one.
  final bool dark;
  final PieceSetCatalog? catalog;
  final String? setId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final app = AppTheme.of(context);
    return Semantics(
      selected: selected,
      child: DecoratedBox(
        decoration: BoxDecoration(color: dark ? app.boardDark : app.boardLight),
        position: DecorationPosition.background,
        child: Container(
          width: size,
          height: size,
          foregroundDecoration: BoxDecoration(
            border: Border.all(
              color: selected ? scheme.primary : scheme.outline,
              width: selected ? 3 : 1,
            ),
          ),
          child: PieceView(cls, size: size, catalog: catalog, setId: setId),
        ),
      ),
    );
  }
}
