// The square editor (docs/ux-spec.md, 4.2): a bottom sheet with the square's name, what was read next to the
// square cut from the original ("Original" | "Leído"), two rows of six pieces (white, black), "Vacía" and
// "Está bien" ("Está vacía" for a doubtful empty square). One tap applies and closes.
//
// In the "Revisar dudosas" flow ([review]) the same sheet stays open and moves on to the next doubtful square
// after each answer ("Dudosa 2 de 3"), until none is left.
import 'package:material_ui/material_ui.dart';

import '../chess.dart';
import '../diagram.dart';
import 'board.dart';
import 'icons.dart';
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
/// ran out of doubtful squares. [onHeight] hears the height of the sheet once it is laid out (and again when it
/// changes), so the screen behind can leave room for it.
Future<SquareSheetResult?> showSquareSheet(
  BuildContext context, {
  required Diagram diagram,
  required int square,
  bool review = false,
  ValueChanged<int>? onSquare,
  ValueChanged<double>? onHeight,
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
      onHeight: onHeight,
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
    this.onHeight,
  });

  final Diagram diagram;
  final int square;
  final bool review;
  final ValueChanged<int>? onSquare;
  final ValueChanged<double>? onHeight;

  @override
  State<SquareSheet> createState() => _SquareSheetState();
}

class _SquareSheetState extends State<SquareSheet> {
  late int _square = widget.square;
  late final int _total = widget.diagram.doubtfulCount;
  int _step = 1;

  // The original crop is decoded once per diagram: this provider is equal to the one of the block's overlay, so
  // both come from the same entry of the image cache.
  late final MemoryImage? _original = widget.diagram.originalCrop == null
      ? null
      : MemoryImage(widget.diagram.originalCrop!);

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
    final read = _d.readClass(_square);
    final changed = _d.changedFromRead(_square);
    final doubtful = _d.isDoubtful(_square);
    final gutter = Space.gutter(MediaQuery.sizeOf(context).width);
    if (widget.onHeight != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final box = mounted ? context.findRenderObject() : null;
        if (box is RenderBox && box.hasSize) widget.onHeight!(box.size.height);
      });
    }

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
                    child: Text(
                      'Casilla ${squareName(_square)}',
                      style: text.titleLarge,
                    ),
                  ),
                ),
                if (widget.review) ...[
                  const SizedBox(width: Space.md),
                  Semantics(
                    liveRegion: true,
                    child: _flag('Dudosa $_step de $_total', text, warning),
                  ),
                ] else if (doubtful) ...[
                  const SizedBox(width: Space.md),
                  _flag('Dudosa', text, warning),
                ],
              ],
            ),
            const SizedBox(height: Space.xs),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Se leyó: ${pieceNames[read]}',
                        style: text.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      if (changed)
                        TextButton(
                          key: const ValueKey('restore-read'),
                          style: TextButton.styleFrom(
                            padding: EdgeInsets.zero,
                            alignment: Alignment.centerLeft,
                          ),
                          onPressed: () =>
                              _resolve(() => _d.restoreRead(_square)),
                          child: const Text('Volver a lo leído'),
                        ),
                    ],
                  ),
                ),
                if (_original != null) ...[
                  const SizedBox(width: Space.md),
                  _CompareTile(
                    caption: 'Original',
                    semanticLabel: 'Original de la casilla',
                    child: _OriginalSquare(
                      key: const ValueKey('tile-original'),
                      image: _original,
                      index: _d.seenFromBlack ? flipSquare(_square) : _square,
                      size: _compareTile,
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  _CompareTile(
                    caption: 'Leído',
                    semanticLabel: 'Leído: ${pieceNames[read]}',
                    child: PieceTile(
                      read,
                      key: const ValueKey('tile-read'),
                      size: _compareTile,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: Space.lg),
            LayoutBuilder(
              builder: (context, c) {
                const gap = Space.sm;
                final tile = ((c.maxWidth - 5 * gap) / 6).clamp(
                  minTarget,
                  64.0,
                );
                return Column(
                  children: [
                    _PieceRow(
                      classes: const [6, 5, 4, 3, 2, 1],
                      size: tile,
                      gap: gap,
                      current: current,
                      onPick: (cls) =>
                          _resolve(() => _d.setSquare(_square, cls)),
                    ),
                    const SizedBox(height: gap),
                    _PieceRow(
                      classes: const [12, 11, 10, 9, 8, 7],
                      size: tile,
                      gap: gap,
                      current: current,
                      onPick: (cls) =>
                          _resolve(() => _d.setSquare(_square, cls)),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: Space.lg),
            _answers(current, doubtful),
          ],
        ),
      ),
    );
  }

  static const double _compareTile = 56;

  Widget _flag(String label, TextTheme text, Color warning) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      AppIcon(AppIcons.warning, size: 18, color: warning),
      const SizedBox(width: Space.xs),
      Text(label, style: text.labelLarge?.copyWith(color: warning)),
    ],
  );

  /// The answers under the pieces:
  ///  * a doubtful empty square: one filled "Está vacía";
  ///  * a doubtful piece: "Vacía" and a filled "Está bien";
  ///  * a trusted square: "Vacía" only.
  Widget _answers(int current, bool doubtful) {
    if (doubtful && current == 0) {
      return FilledButton(
        key: const ValueKey('confirm-square'),
        onPressed: () => _resolve(() => _d.confirmSquare(_square)),
        child: const Text('Está vacía'),
      );
    }
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            key: const ValueKey('pick-0'),
            onPressed: () => _resolve(() => _d.setSquare(_square, 0)),
            icon: current == 0 ? const AppIcon(AppIcons.check) : null,
            label: const Text('Vacía'),
          ),
        ),
        if (doubtful) ...[
          const SizedBox(width: Space.sm),
          Expanded(
            child: FilledButton(
              key: const ValueKey('confirm-square'),
              onPressed: () => _resolve(() => _d.confirmSquare(_square)),
              child: const Text('Está bien'),
            ),
          ),
        ],
      ],
    );
  }
}

/// A 56 dp tile with its caption underneath ("Original" | "Leído").
class _CompareTile extends StatelessWidget {
  const _CompareTile({
    required this.caption,
    required this.semanticLabel,
    required this.child,
  });

  final String caption, semanticLabel;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: semanticLabel,
      image: true,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          child,
          const SizedBox(height: Space.xs),
          Text(
            caption,
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// One square of the original picture: the crop is drawn at 8 x [size] and shifted so that the square at screen
/// position [index] (0..63, row-major from the top-left, the way the picture is oriented) fills the tile.
class _OriginalSquare extends StatelessWidget {
  const _OriginalSquare({
    super.key,
    required this.image,
    required this.index,
    required this.size,
  });

  final ImageProvider image;
  final int index;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final row = index ~/ 8, col = index % 8;
    return Container(
      width: size,
      height: size,
      foregroundDecoration: BoxDecoration(
        border: Border.all(color: scheme.outline),
      ),
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment(-1 + 2 * col / 7, -1 + 2 * row / 7),
          minWidth: size * 8,
          maxWidth: size * 8,
          minHeight: size * 8,
          maxHeight: size * 8,
          child: Image(
            image: image,
            fit: BoxFit.fill,
            gaplessPlayback: true,
            filterQuality: FilterQuality.medium,
            excludeFromSemantics: true,
          ),
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
            child: PieceTile(cls, size: size, selected: cls == current),
          ),
        ),
      ],
    ],
  );
}
