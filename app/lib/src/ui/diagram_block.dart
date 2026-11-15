// The diagram block (docs/ux-spec.md, 4.2): ONE tonal surface per diagram, top to bottom: numeral and status,
// the Leído | Original comparator over the board, the turn caption, the castling chips, the actions and the FEN.
//
// The block listens to its [Diagram] and rebuilds only itself; structure changes (numbers, removals) come in
// from the list through [DiagramBlock.number]. [DiagramSkeleton] is the same surface with the same metrics
// while a board is still being read, so nothing jumps when the reading arrives.
import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../diagram.dart';
import '../session.dart';
import 'board.dart';
import 'home_actions.dart';
import 'scope.dart';
import 'square_sheet.dart';
import 'theme.dart';
import 'tokens.dart';

/// Widest a block may grow: past this the board would become huge.
const double blockMaxWidth = 440;

const double _pad = Space.lg;
const double _headerHeight = 52;

enum _Menu { review, copyPgn, share, rotate, adjust, delete }

class DiagramBlock extends StatefulWidget {
  const DiagramBlock({
    super.key,
    required this.diagram,
    required this.number,
    required this.actions,
  });

  final Diagram diagram;

  /// Position of the diagram in the session (1-based).
  final int number;

  final HomeActions actions;

  @override
  State<DiagramBlock> createState() => _DiagramBlockState();
}

class _DiagramBlockState extends State<DiagramBlock> {
  final GlobalKey _boardKey = GlobalKey();
  bool _showOriginal = false;
  bool _peek = false;
  int? _selected;

  Diagram get _d => widget.diagram;
  HomeActions get _actions => widget.actions;
  Session get _session => _actions.session;

  // ------------------------------------------------------------------ editing

  void _scrollToBoard() {
    final ctx = _boardKey.currentContext;
    if (ctx == null) return;
    unawaited(
      Scrollable.ensureVisible(
        ctx,
        alignment: 0,
        duration: Motion.of(context, Motion.slow),
        curve: Motion.standard,
      ),
    );
  }

  Future<void> _edit(int square) async {
    setState(() => _selected = square);
    await showSquareSheet(context, diagram: _d, square: square);
    if (mounted) setState(() => _selected = null);
  }

  /// "Revisar dudosas": one sheet that walks through every doubtful square.
  Future<void> _review() async {
    final first = _d.doubtfulSquares;
    if (first.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _selected = first.first);
    _scrollToBoard();
    final result = await showSquareSheet(
      context,
      diagram: _d,
      square: first.first,
      review: true,
      onSquare: (sq) {
        if (mounted) setState(() => _selected = sq);
      },
    );
    if (mounted) setState(() => _selected = null);
    if (result == SquareSheetResult.reviewed) {
      _actions.toast(messenger, 'Todas las casillas revisadas');
    }
  }

  void _delete() {
    final messenger = ScaffoldMessenger.of(context);
    final number = widget.number;
    final removed = _session.removeDiagram(_d);
    if (removed == null) return;
    _actions.toast(
      messenger,
      'Diagrama $number eliminado',
      action: 'Deshacer',
      onAction: () => _session.restore(removed),
      duration: const Duration(seconds: 6),
    );
  }

  void _onMenu(_Menu item) {
    switch (item) {
      case _Menu.review:
        unawaited(_review());
      case _Menu.copyPgn:
        unawaited(_actions.copy(context, _session.pgnOf(_d), 'PGN copiado'));
      case _Menu.share:
        unawaited(_actions.share(context, _session.pgnOf(_d)));
      case _Menu.rotate:
        _d.rotate180();
      case _Menu.adjust:
        final source = _session.sourceOf(_d);
        if (source != null) {
          unawaited(_actions.cropByHand(context, source, replacing: _d));
        }
      case _Menu.delete:
        _delete();
    }
  }

  // -------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: 'Diagrama ${widget.number}',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(Corner.container),
        ),
        child: Padding(
          padding: const EdgeInsets.all(_pad),
          child: ListenableBuilder(
            listenable: Listenable.merge([_d, _actions]),
            builder: (context, _) => _content(context),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final scope = AppScope.maybeOf(context);
    final coordinates = scope?.settings.showCoordinates ?? true;
    final status = _d.status;
    final source = _session.sourceOf(_d);
    final canAdjust =
        source != null &&
        !source.isPending &&
        !_actions.isReadingRegion(source);

    return LayoutBuilder(
      builder: (context, c) {
        final side = c.maxWidth;
        // In a row of blocks the surface is stretched to the tallest one: the actions and the FEN sit at the
        // bottom so they line up across the row; what is optional above them (a forced-turn line, castling
        // chips) only moves the slack.
        final stretched = c.hasBoundedHeight;
        return Column(
          mainAxisSize: stretched ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context, status, canAdjust),
            if (_d.fallback && !_d.manual) ...[
              const SizedBox(height: Space.xs),
              _fallbackNote(context, source, canAdjust),
            ],
            const SizedBox(height: Space.sm),
            if (_d.originalCrop != null) ...[
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('Leído')),
                  ButtonSegment(value: true, label: Text('Original')),
                ],
                selected: {_showOriginal},
                onSelectionChanged: (s) =>
                    setState(() => _showOriginal = s.first),
              ),
              const SizedBox(height: Space.md),
            ],
            _board(context, side, coordinates),
            const SizedBox(height: Space.md),
            _turn(context),
            _castling(context),
            const SizedBox(height: Space.md),
            if (stretched) const Spacer(),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () => unawaited(_actions.openLichess(context, _d)),
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('Analizar en Lichess'),
                ),
                TextButton(
                  onPressed: () =>
                      unawaited(_actions.copy(context, _d.fen, 'FEN copiado')),
                  child: const Text('Copiar FEN'),
                ),
              ],
            ),
            const SizedBox(height: Space.xs),
            _fenLine(context, text, scheme),
          ],
        );
      },
    );
  }

  // ------------------------------------------------------------------- header

  Widget _header(BuildContext context, DiagramStatus status, bool canAdjust) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final app = context.app;
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _headerHeight),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ExcludeSemantics(
            child: Text(
              '${widget.number}',
              style: app.numeral.copyWith(color: scheme.primary),
            ),
          ),
          const SizedBox(width: Space.md),
          Expanded(child: _status(context, status)),
          PopupMenuButton<_Menu>(
            tooltip: 'Más opciones',
            icon: const Icon(Icons.more_vert),
            onSelected: _onMenu,
            itemBuilder: (context) => [
              if (_d.hasDoubts)
                _item(
                  _Menu.review,
                  Icons.warning_amber_rounded,
                  'Revisar dudosas',
                ),
              _item(_Menu.copyPgn, Icons.content_copy, 'Copiar PGN'),
              if (widget.actions.canShare)
                _item(
                  _Menu.share,
                  Icons.share_outlined,
                  'Compartir este diagrama',
                ),
              _item(
                _Menu.rotate,
                Icons.flip,
                _d.seenFromBlack
                    ? 'Ver desde las blancas'
                    : 'Ver desde las negras',
                checked: _d.seenFromBlack,
              ),
              _item(
                _Menu.adjust,
                Icons.crop,
                'Ajustar recorte',
                enabled: canAdjust,
              ),
              const PopupMenuDivider(),
              _item(_Menu.delete, Icons.delete_outline, 'Eliminar'),
            ],
          ),
        ],
      ),
    );
  }

  /// Two lines, always: the headline and what to do or why, so the boards of a row of blocks line up.
  ///  * impossible: "Posición imposible" and the first reason (the full text is the tooltip);
  ///  * doubtful: "2 casillas dudosas" and the "Revisar dudosas" entry;
  ///  * nothing when the reading is fine.
  Widget _status(BuildContext context, DiagramStatus status) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final app = context.app;
    final text = theme.textTheme;

    if (status.hasProblems) {
      final rest = status.problems.length - 1;
      final reason =
          '${status.problems.first}${rest > 0 ? ' Y $rest más.' : ''}';
      return Tooltip(
        message: status.problemText!,
        child: Semantics(
          label: status.problemText,
          excludeSemantics: true,
          child: Row(
            children: [
              Icon(Icons.error_outline, size: 20, color: scheme.error),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Posición imposible',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(color: scheme.error),
                    ),
                    Text(
                      reason,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (!_d.hasDoubts) return const SizedBox.shrink();
    return Semantics(
      button: true,
      label: '${status.doubtfulText}. Revisar dudosas',
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('review-doubtful'),
        onTap: () => unawaited(_review()),
        borderRadius: BorderRadius.circular(Corner.control),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: minTarget),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, size: 20, color: app.warning),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      status.doubtfulText!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(color: app.warning),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            'Revisar dudosas',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.labelLarge?.copyWith(
                              color: scheme.primary,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: scheme.primary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  PopupMenuItem<_Menu> _item(
    _Menu value,
    IconData icon,
    String label, {
    bool enabled = true,
    bool checked = false,
  }) => PopupMenuItem<_Menu>(
    value: value,
    enabled: enabled,
    child: Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: Space.md),
        Expanded(child: Text(label)),
        if (checked) ...[
          const SizedBox(width: Space.md),
          const Icon(Icons.check, size: 20),
        ],
      ],
    ),
  );

  /// The reader found no frame and used the whole image.
  Widget _fallbackNote(
    BuildContext context,
    SourceImage? source,
    bool canAdjust,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(
                Icons.info_outline,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Text(
                'No se encontró el marco del tablero; se leyó la imagen entera.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            key: const ValueKey('fallback-crop'),
            onPressed: canAdjust && source != null
                ? () => unawaited(
                    _actions.cropByHand(context, source, replacing: _d),
                  )
                : null,
            icon: const Icon(Icons.crop),
            label: const Text('Recortar a mano'),
          ),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------- board

  Widget _board(BuildContext context, double side, bool coordinates) {
    final layout = BoardLayout(side, coordinates: coordinates);
    final crop = _d.originalCrop;
    final original = _showOriginal || _peek;
    return GestureDetector(
      // Press and hold shows the original while held; the squares' own taps lose the arena to it, so a hold
      // never edits a square.
      onLongPressStart: crop == null
          ? null
          : (_) => setState(() => _peek = true),
      onLongPressEnd: crop == null
          ? null
          : (_) => setState(() => _peek = false),
      onLongPressCancel: crop == null
          ? null
          : () => setState(() => _peek = false),
      child: SizedBox.square(
        key: _boardKey,
        dimension: side,
        child: Stack(
          children: [
            BoardView(
              diagram: _d,
              size: side,
              blackAtBottom: _d.seenFromBlack,
              selected: _selected,
              onTap: _edit,
            ),
            if (crop != null)
              Positioned.fromRect(
                rect: layout.boardRect,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    key: const ValueKey('original-overlay'),
                    opacity: original ? 1 : 0,
                    duration: Motion.of(context, Motion.fast),
                    curve: Motion.standard,
                    child: Semantics(
                      image: true,
                      label: 'Original de la captura',
                      child: Image.memory(
                        crop,
                        fit: BoxFit.fill,
                        gaplessPlayback: true,
                        filterQuality: FilterQuality.medium,
                        excludeFromSemantics: true,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // --------------------------------------------------------------------- turn

  Widget _turn(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final forced = _d.forcedTurn;
    final reason = _d.forcedTurnReason;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: [
            ButtonSegment(
              value: 'w',
              label: const Text('Mueven blancas'),
              icon: const _Disc(filled: false),
              enabled: forced == null || forced == 'w',
            ),
            ButtonSegment(
              value: 'b',
              label: const Text('Mueven negras'),
              icon: const _Disc(filled: true),
              enabled: forced == null || forced == 'b',
            ),
          ],
          selected: {_d.turn},
          onSelectionChanged: (s) => _d.turn = s.first,
        ),
        if (reason != null)
          Padding(
            padding: const EdgeInsets.only(top: Space.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(
                    Icons.lock_outline,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Text(
                    reason,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ----------------------------------------------------------------- castling

  Widget _castling(BuildContext context) {
    final possible = _d.possibleCastling;
    if (possible.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: Space.xs),
      child: Wrap(
        spacing: Space.sm,
        children: [
          for (final right in CastlingRight.values)
            if (possible.contains(right))
              FilterChip(
                key: ValueKey('castling-${right.symbol}'),
                label: Text(right.label),
                selected: _d.isCastlingEnabled(right),
                onSelected: (on) => _d.setCastlingEnabled(right, on),
              ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------- FEN

  Widget _fenLine(BuildContext context, TextTheme text, ColorScheme scheme) {
    final fen = _d.fen;
    void copy() => unawaited(_actions.copy(context, fen, 'FEN copiado'));
    return Semantics(
      label: 'FEN: $fen',
      button: true,
      onTapHint: 'Copiar',
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('fen-line'),
        onTap: copy,
        onLongPress: copy,
        borderRadius: BorderRadius.circular(Corner.control),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: minTarget),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  fen,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: context.app.mono.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: Space.sm),
              Icon(
                Icons.content_copy,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The disc of the turn control: White's is white, Black's is black, in any theme (it is a piece colour, not a
/// text colour), each with a ring that keeps it visible on light and dark segments.
class _Disc extends StatelessWidget {
  const _Disc({required this.filled});

  final bool filled;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: SizedBox.square(
      dimension: 18,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: filled ? BoardMarks.pieceBlack : BoardMarks.pieceWhite,
          border: Border.all(
            color: filled ? BoardMarks.pieceWhite : BoardMarks.pieceBlack,
            width: 2,
          ),
        ),
      ),
    ),
  );
}

// ------------------------------------------------------------------------------------------------ skeleton

/// A block-shaped placeholder for a board that is located but not read yet: the same surface and metrics, the
/// empty board of the ink where the reading will appear, bars where the text will be. It pulses softly, except
/// when the system asks to remove animations.
class DiagramSkeleton extends StatefulWidget {
  const DiagramSkeleton({super.key});

  @override
  State<DiagramSkeleton> createState() => _DiagramSkeletonState();
}

class _DiagramSkeletonState extends State<DiagramSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  late final Animation<double> _opacity = Tween<double>(
    begin: 0.5,
    end: 1,
  ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _pulse.stop();
      _pulse.value = 1;
    } else if (!_pulse.isAnimating) {
      unawaited(_pulse.repeat(reverse: true));
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Widget _bar(BuildContext context, double height, {double? width}) =>
      DecoratedBox(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(Corner.control),
        ),
        child: SizedBox(height: height, width: width),
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'Leyendo un diagrama',
      container: true,
      child: ExcludeSemantics(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(Corner.container),
          ),
          child: Padding(
            padding: const EdgeInsets.all(_pad),
            child: LayoutBuilder(
              builder: (context, c) => FadeTransition(
                opacity: _opacity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: _headerHeight,
                      child: Row(
                        children: [
                          _bar(context, 36, width: 32),
                          const SizedBox(width: Space.md),
                          _bar(context, 16, width: 140),
                        ],
                      ),
                    ),
                    const SizedBox(height: Space.sm),
                    _bar(context, minTarget),
                    const SizedBox(height: Space.md),
                    BoardView.preview(
                      grid: List<int>.filled(64, 0),
                      size: c.maxWidth,
                      showCoordinates: true,
                      semanticLabel: 'Tablero vacío',
                    ),
                    const SizedBox(height: Space.md),
                    _bar(context, minTarget),
                    const SizedBox(height: Space.md),
                    Row(children: [_bar(context, minTarget, width: 190)]),
                    const SizedBox(height: Space.xs),
                    _bar(context, minTarget),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
