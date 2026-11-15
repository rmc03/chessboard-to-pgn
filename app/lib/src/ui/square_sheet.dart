// The square editor (docs/ux-spec.md, 4.2): a bottom sheet with the square's name and what was read, the
// "Vacía" option, two rows of six pieces (white, black) and "Está bien" when the square is doubtful.
// One tap applies and closes.
//
// In the "Revisar dudosas" flow ([review]) the same sheet stays open and moves on to the next doubtful square
// after each answer ("Dudosa 2 de 3"), until none is left.
import 'package:material_ui/material_ui.dart';

import '../chess.dart';
import '../diagram.dart';
import 'board.dart';
import 'theme.dart';
import 'tokens.dart';

/// How the sheet ended.
enum SquareSheetResult {
  /// One square was edited or confirmed.
  edited,

  /// The review went through every doubtful square.
  reviewed,
}

/// Shows the editor for [square] of [diagram]. Returns null when the user dismissed it.
///
/// With [review] the sheet walks through the doubtful squares, calling [onSquare] each time the square it is
/// about (the one to mark as selected on the board) changes, and returns [SquareSheetResult.reviewed] when it
/// ran out of doubtful squares.
Future<SquareSheetResult?> showSquareSheet(
  BuildContext context, {
  required Diagram diagram,
  required int square,
  bool review = false,
  ValueChanged<int>? onSquare,
}) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<SquareSheetResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // In the review the board has to stay readable above the sheet.
    barrierColor: scheme.scrim.withValues(alpha: review ? 0.16 : 0.32),
    builder: (context) => SquareSheet(
      diagram: diagram,
      square: square,
      review: review,
      onSquare: onSquare,
    ),
  );
}

class SquareSheet extends StatefulWidget {
  const SquareSheet({
    super.key,
    required this.diagram,
    required this.square,
    this.review = false,
    this.onSquare,
  });

  final Diagram diagram;
  final int square;
  final bool review;
  final ValueChanged<int>? onSquare;

  @override
  State<SquareSheet> createState() => _SquareSheetState();
}

class _SquareSheetState extends State<SquareSheet> {
  late int _square = widget.square;
  late final int _total = widget.diagram.doubtfulCount;
  int _step = 1;

  Diagram get _d => widget.diagram;

  /// Applies [done] to the square and either moves to the next doubtful one (review) or closes.
  void _resolve(void Function() done) {
    final was = _square;
    done();
    if (!widget.review) {
      Navigator.pop(context, SquareSheetResult.edited);
      return;
    }
    final next = _d.nextDoubtfulAfter(was);
    if (next == null) {
      Navigator.pop(context, SquareSheetResult.reviewed);
      return;
    }
    setState(() {
      _square = next;
      _step++;
    });
    widget.onSquare?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = theme.textTheme;
    final scheme = theme.colorScheme;
    final warning = context.app.warning;
    final current = _d.grid[_square];
    final doubtful = _d.isDoubtful(_square);
    final gutter = Space.gutter(MediaQuery.sizeOf(context).width);

    return SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.fromLTRB(gutter, 0, gutter, Space.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Casilla ${squareName(_square)}', style: text.titleLarge),
                        const SizedBox(height: Space.xs),
                        Text(
                          'Se leyó: ${pieceNames[current]}',
                          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
                if (widget.review) ...[
                  const SizedBox(width: Space.md),
                  Semantics(
                    liveRegion: true,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 18, color: warning),
                        const SizedBox(width: Space.xs),
                        Text(
                          'Dudosa $_step de $_total',
                          style: text.labelLarge?.copyWith(color: warning),
                        ),
                      ],
                    ),
                  ),
                ] else if (doubtful) ...[
                  const SizedBox(width: Space.md),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 18, color: warning),
                      const SizedBox(width: Space.xs),
                      Text('Dudosa', style: text.labelLarge?.copyWith(color: warning)),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: Space.lg),
            LayoutBuilder(
              builder: (context, c) {
                const gap = Space.sm;
                final tile = ((c.maxWidth - 5 * gap) / 6).clamp(minTarget, 64.0);
                return Column(
                  children: [
                    _PieceRow(
                      classes: const [6, 5, 4, 3, 2, 1],
                      size: tile,
                      gap: gap,
                      current: current,
                      onPick: (cls) => _resolve(() => _d.setSquare(_square, cls)),
                    ),
                    const SizedBox(height: gap),
                    _PieceRow(
                      classes: const [12, 11, 10, 9, 8, 7],
                      size: tile,
                      gap: gap,
                      current: current,
                      onPick: (cls) => _resolve(() => _d.setSquare(_square, cls)),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: Space.lg),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('pick-0'),
                    onPressed: () => _resolve(() => _d.setSquare(_square, 0)),
                    icon: Icon(current == 0 ? Icons.check : Icons.crop_square),
                    label: const Text('Vacía'),
                  ),
                ),
                if (doubtful) ...[
                  const SizedBox(width: Space.sm),
                  Expanded(
                    child: FilledButton.icon(
                      key: const ValueKey('confirm-square'),
                      onPressed: () => _resolve(() => _d.confirmSquare(_square)),
                      icon: const Icon(Icons.check),
                      label: const Text('Está bien'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PieceRow extends StatelessWidget {
  const _PieceRow({
    required this.classes,
    required this.size,
    required this.gap,
    required this.current,
    required this.onPick,
  });

  final List<int> classes;
  final double size, gap;
  final int current;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (final (i, cls) in classes.indexed) ...[
        if (i > 0) SizedBox(width: gap),
        Semantics(
          label: pieceNames[cls],
          button: true,
          selected: cls == current,
          excludeSemantics: true,
          child: InkWell(
            key: ValueKey('pick-$cls'),
            onTap: () => onPick(cls),
            child: PieceTile(cls, size: size, selected: cls == current, dark: i.isOdd),
          ),
        ),
      ],
    ],
  );
}
