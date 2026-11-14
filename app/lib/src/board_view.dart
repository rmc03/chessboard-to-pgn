// A very plain 8x8 board: chess figures from the bundled font, tappable squares, doubtful squares outlined in
// amber.
import 'package:material_ui/material_ui.dart';

import 'chess.dart';

const _light = Color(0xFFF0D9B5), _dark = Color(0xFFB58863);

/// Bundled font with only the 12 chess figures (assets/fonts, see app/tool/make_figures_font.py).
///
/// The figures must NOT come from the system fonts: on Android the pawn U+265F (the only chess figure that is
/// also an emoji) is replaced by a colour emoji that ignores the text colour, so white and black pawns looked
/// the same while every other piece was fine.
const figuresFont = 'ChessFigures';

/// Filled figure of a piece class (U+265A king .. U+265F pawn), whatever its colour.
String solidFigure(int cls) =>
    String.fromCharCode(0x2660 - (cls <= 6 ? cls : cls - 6));

/// Line-drawing figure of the same piece (U+2654 king .. U+2659 pawn).
String outlineFigure(int cls) =>
    String.fromCharCode(0x265A - (cls <= 6 ? cls : cls - 6));

/// One piece in a [size] x [size] box (the figure itself is about 0.73 of it, centred).
/// White: white body, black contour and inner lines. Black: solid black.
class PieceFigure extends StatelessWidget {
  const PieceFigure(this.cls, {super.key, required this.size});

  final int cls;
  final double size;

  @override
  Widget build(BuildContext context) {
    Widget figure(String text, {Color? color, Paint? paint}) => Text(
      text,
      textScaler: TextScaler.noScaling,
      style: TextStyle(
        fontFamily: figuresFont,
        fontSize: size,
        height: 1,
        color: color,
        foreground: paint,
      ),
    );
    final contour = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size * 0.05
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.black;
    return Semantics(
      label: pieceNames[cls],
      excludeSemantics: true,
      child: isWhite(cls)
          ? Stack(
              alignment: Alignment.center,
              children: [
                figure(solidFigure(cls), paint: contour),
                figure(solidFigure(cls), color: Colors.white),
                figure(outlineFigure(cls), color: Colors.black),
              ],
            )
          : figure(solidFigure(cls), color: Colors.black),
    );
  }
}

class BoardView extends StatelessWidget {
  const BoardView({
    super.key,
    required this.grid,
    required this.doubtful,
    required this.onTap,
  });

  final List<int> grid;
  final bool Function(int square) doubtful;
  final void Function(int square) onTap;

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(
        builder: (context, box) {
          final cell = box.maxWidth / 8;
          return Column(
            children: [
              for (var r = 0; r < 8; r++)
                Expanded(
                  child: Row(
                    children: [
                      for (var c = 0; c < 8; c++)
                        Expanded(
                          child: _square(r * 8 + c, (r + c) % 2 == 0, cell),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _square(int sq, bool light, double cell) {
    final cls = grid[sq];
    return GestureDetector(
      key: ValueKey('square-$sq'),
      onTap: () => onTap(sq),
      child: Container(
        decoration: BoxDecoration(
          color: light ? _light : _dark,
          border: doubtful(sq)
              ? Border.all(color: const Color(0xFFFFA000), width: 3)
              : null,
        ),
        alignment: Alignment.center,
        child: cls == 0 ? null : PieceFigure(cls, size: cell * 0.92),
      ),
    );
  }
}
