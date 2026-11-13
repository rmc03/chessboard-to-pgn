// A very plain 8x8 board: Unicode figures, tappable squares, doubtful squares outlined in amber.
import 'package:material_ui/material_ui.dart';

import 'chess.dart';

const _light = Color(0xFFF0D9B5), _dark = Color(0xFFB58863);

/// ︎ forces text (not emoji) presentation of the figures.
String glyph(int cls) {
  const solid = {1: '♟', 2: '♞', 3: '♝', 4: '♜', 5: '♛', 6: '♚'};
  return '${solid[cls <= 6 ? cls : cls - 6]}︎';
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
    final white = isWhite(cls);
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
        child: cls == 0
            ? null
            : Text(
                glyph(cls),
                style: TextStyle(
                  fontSize: cell * 0.78,
                  height: 1,
                  color: white ? Colors.white : Colors.black,
                  shadows: white
                      ? const [
                          Shadow(offset: Offset(1, 0), color: Colors.black),
                          Shadow(offset: Offset(-1, 0), color: Colors.black),
                          Shadow(offset: Offset(0, 1), color: Colors.black),
                          Shadow(offset: Offset(0, -1), color: Colors.black),
                        ]
                      : null,
                ),
              ),
      ),
    );
  }
}
