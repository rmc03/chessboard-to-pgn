// The diagram block (docs/ux-spec.md, 4.2): ONE tonal surface per diagram, top to bottom: numeral and status
// (the error lines and, when there are doubtful squares, the "Revisar dudosas" row), the Leído | Original
// comparator with "Ajustar recorte" and "Ver desde las negras" on the same row, the board, the turn caption, the
// castling chips, the actions (Lichess, share or copy, remove) and the FEN with its copy button. No overflow menu.
//
// The block rebuilds only itself: on its own [Diagram], on the changes of its capture and on the actions' state.
// The shell below is built once and reused while the parent rebuilds with the same number, diagram and actions,
// so a change somewhere else in the list never reaches it. [DiagramSkeleton] is the same surface with the same
// metrics while a board is still being read, so nothing jumps when the reading arrives.
import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals, visibleForTesting;
import 'package:material_ui/material_ui.dart';

import '../diagram.dart';
import '../session.dart';
import 'board.dart';
import 'home_actions.dart';
import 'icons.dart';
import 'scope.dart';
import 'square_sheet.dart';
import 'theme.dart';
import 'tokens.dart';

/// Widest a block may grow: past this the board would become huge.
const double blockMaxWidth = 440;

const double _pad = Space.lg;
const double _headerHeight = 52;

/// How many times the content of any block was built (tests check that unrelated changes do not rebuild it).
@visibleForTesting
int diagramBlockBuilds = 0;

class _Tick extends ChangeNotifier {
  void bump() => notifyListeners();
}

class DiagramBlock extends StatefulWidget {
  const DiagramBlock({
    super.key,
    required this.diagram,
    required this.number,
    required this.actions,
    this.source,
  });

  final Diagram diagram;

  /// Position of the diagram in the session (1-based).
  final int number;

  final HomeActions actions;

  /// The capture the diagram belongs to; the block follows its changes (reading finished, region being read).
  final SourceImage? source;

  @override
  State<DiagramBlock> createState() => DiagramBlockState();
}

class DiagramBlockState extends State<DiagramBlock> {
  final GlobalKey _boardKey = GlobalKey();
  final _Tick _tick = _Tick();
  Widget? _shell;
  bool _showOriginal = false;
  bool _peek = false;
  int? _selected;

  Diagram get _d => widget.diagram;
  HomeActions get _actions => widget.actions;
  Session get _session => _actions.session;
  SourceImage? get _source => widget.source ?? _session.sourceOf(_d);

  @override
  void didUpdateWidget(DiagramBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.diagram != widget.diagram ||
        oldWidget.number != widget.number ||
        oldWidget.actions != widget.actions ||
        oldWidget.source != widget.source) {
      _shell = null;
    }
  }

  @override
  void dispose() {
    _tick.dispose();
    super.dispose();
  }

  /// Local state changes rebuild the content through the shell's listenable, not through [build].
  void _set(VoidCallback change) {
    change();
    if (mounted) _tick.bump();
  }

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
    _set(() => _selected = square);
    await showSquareSheet(context, diagram: _d, square: square);
    if (mounted) _set(() => _selected = null);
  }

  /// "Revisar dudosas": one sheet that walks through every doubtful square. Public so the export bar and the
  /// "Siguiente con dudas" action can open it.
  Future<void> review() async {
    final first = _d.doubtfulSquares;
    if (first.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    _set(() => _selected = first.first);
    _scrollToBoard();
    final result = await showSquareSheet(
      context,
      diagram: _d,
      square: first.first,
      review: true,
      onSquare: (sq) {
        if (mounted) _set(() => _selected = sq);
      },
    );
    if (mounted) _set(() => _selected = null);
    if (result == SquareSheetResult.reviewed) {
      final next = _session.nextWithDoubtsAfter(_d);
      _actions.toast(
        messenger,
        'Todas las casillas revisadas',
        action: next == null ? null : 'Siguiente con dudas',
        onAction: next == null
            ? null
            : () => unawaited(_actions.goToDiagram(next, review: true)),
        duration: next == null
            ? const Duration(seconds: 4)
            : const Duration(seconds: 6),
      );
    }
  }

  void _delete() {
    final messenger = ScaffoldMessenger.of(context);
    final number = widget.number;
    final removed = _session.removeDiagram(_d);
    if (removed == null) return;
    _actions.toast(
      messenger,
      'Diagrama $number quitado',
      action: 'Deshacer',
      onAction: () => _session.restore(removed),
      duration: const Duration(seconds: 6),
    );
  }

  void _adjust() {
    final source = _source;
    if (source != null) {
      unawaited(_actions.cropByHand(context, source, replacing: _d));
    }
  }

  // -------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) => _shell ??= ListenableBuilder(
    listenable: Listenable.merge([_d, _actions, _tick, ?widget.source]),
    builder: (context, _) => _frame(context),
  );

  Widget _frame(BuildContext context) {
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
          child: _content(context),
        ),
      ),
    );
  }

  Widget _content(BuildContext context) {
    diagramBlockBuilds++;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final scope = AppScope.maybeOf(context);
    final coordinates = scope?.settings.showCoordinates ?? true;
    final status = _d.status;
    final source = _source;
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
            _header(context, status),
            if (_d.fallback && !_d.manual) ...[
              const SizedBox(height: Space.xs),
              _fallbackNote(context, canAdjust),
            ],
            const SizedBox(height: Space.sm),
            _comparator(context, canAdjust),
            if (_d.originalCrop != null && _actions.peekHintVisible) ...[
              const SizedBox(height: Space.xs),
              Text(
                'Mantén pulsado el tablero para ver el original.',
                key: const ValueKey('peek-hint'),
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: Space.md),
            _board(context, side, coordinates),
            const SizedBox(height: Space.md),
            _turn(context),
            _castling(context),
            const SizedBox(height: Space.md),
            if (stretched) const Spacer(),
            _actionsRow(context),
            const SizedBox(height: Space.xs),
            _fenLine(context, text, scheme),
          ],
        );
      },
    );
  }

  // ------------------------------------------------------------------- header

  Widget _header(BuildContext context, DiagramStatus status) {
    final scheme = Theme.of(context).colorScheme;
    final app = context.app;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: _headerHeight,
          child: Center(
            child: ExcludeSemantics(
              child: Text(
                '${widget.number}',
                style: app.numeral.copyWith(color: scheme.primary),
              ),
            ),
          ),
        ),
        const SizedBox(width: Space.md),
        Expanded(
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _headerHeight),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _status(context, status),
            ),
          ),
        ),
      ],
    );
  }

  /// What is wrong, with what to do:
  ///  * impossible: the first reason, "Y N más" (the full text is the tooltip) and "Cambiar turno" when
  ///    switching the side to move fixes it;
  ///  * doubtful: the tappable "N casillas dudosas · Revisar dudosas" row, ALSO when the position is impossible;
  ///  * nothing when the reading is fine.
  Widget _status(BuildContext context, DiagramStatus status) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;

    final parts = <Widget>[];
    if (status.hasProblems) {
      final rest = status.problems.length - 1;
      final reason =
          '${status.problems.first}${rest > 0 ? ' Y $rest más.' : ''}';
      parts.add(
        Tooltip(
          message: status.problemText!,
          child: Semantics(
            label: status.problemText,
            excludeSemantics: true,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 1),
                  child: AppIcon(AppIcons.error, size: 20, color: scheme.error),
                ),
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
                        maxLines: 2,
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
        ),
      );
      if (_d.switchingTurnFixesCheck) {
        parts.add(
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              key: const ValueKey('switch-turn'),
              onPressed: () => _d.turn = _d.turn == 'w' ? 'b' : 'w',
              child: const Text('Cambiar turno'),
            ),
          ),
        );
      }
    }
    if (_d.hasDoubts) parts.add(_reviewRow(context, status));
    if (parts.isEmpty) return const SizedBox.shrink();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: parts,
    );
  }

  Widget _reviewRow(BuildContext context, DiagramStatus status) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final app = context.app;
    final text = theme.textTheme;
    return Semantics(
      button: true,
      label: '${status.doubtfulText}. Revisar dudosas',
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('review-doubtful'),
        onTap: () => unawaited(review()),
        borderRadius: BorderRadius.circular(Corner.control),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: minTarget),
          child: Row(
            children: [
              AppIcon(AppIcons.warning, size: 20, color: app.warning),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: Space.xs,
                  children: [
                    Text(
                      status.doubtfulText!,
                      style: text.bodyMedium?.copyWith(color: app.warning),
                    ),
                    Text(
                      '·',
                      style: text.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      'Revisar dudosas',
                      style: text.labelLarge?.copyWith(color: scheme.primary),
                    ),
                  ],
                ),
              ),
              AppIcon(AppIcons.go, size: 18, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  /// The reader found no frame and used the whole image.
  Widget _fallbackNote(BuildContext context, bool canAdjust) {
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
              child: AppIcon(
                AppIcons.info,
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
            onPressed: canAdjust ? _adjust : null,
            icon: const AppIcon(AppIcons.crop),
            label: const Text('Recortar a mano'),
          ),
        ),
      ],
    );
  }

  // --------------------------------------------------------------- comparator

  /// Leído | Original, "Ajustar recorte" and "Ver desde las negras" on ONE row: when it is tight the segmented
  /// control shrinks, the icons never wrap below it.
  Widget _comparator(BuildContext context, bool canAdjust) {
    final black = _d.seenFromBlack;
    return Row(
      children: [
        if (_d.originalCrop != null)
          Expanded(
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Leído')),
                ButtonSegment(value: true, label: Text('Original')),
              ],
              selected: {_showOriginal},
              onSelectionChanged: (s) {
                _set(() => _showOriginal = s.first);
                if (s.first) _actions.dismissPeekHint();
              },
            ),
          )
        else
          const Spacer(),
        const SizedBox(width: Space.xs),
        IconButton(
          key: const ValueKey('adjust-crop'),
          tooltip: 'Ajustar recorte',
          onPressed: canAdjust ? _adjust : null,
          icon: const AppIcon(AppIcons.crop),
        ),
        IconButton.filledTonal(
          key: const ValueKey('flip'),
          tooltip: black ? 'Ver desde las blancas' : 'Ver desde las negras',
          isSelected: black,
          onPressed: _d.rotate180,
          icon: const AppIcon(AppIcons.flip),
          selectedIcon: const AppIcon(AppIcons.flip),
        ),
      ],
    );
  }

  // -------------------------------------------------------------------- board

  Widget _board(BuildContext context, double side, bool coordinates) {
    final layout = BoardLayout(side, coordinates: coordinates);
    final crop = _d.originalCrop;
    final original = _showOriginal || _peek;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final doubts = [
      for (var i = 0; i < 64; i++)
        _d.isDoubtful(_d.seenFromBlack ? flipSquare(i) : i),
    ];
    return RepaintBoundary(
      child: GestureDetector(
        // Press and hold shows the original while held; the squares' own taps lose the arena to it, so a hold
        // never edits a square.
        onLongPressStart: crop == null ? null : (_) => _set(() => _peek = true),
        onLongPressEnd: crop == null
            ? null
            : (_) {
                _set(() => _peek = false);
                _actions.dismissPeekHint();
              },
        onLongPressCancel: crop == null
            ? null
            : () => _set(() => _peek = false),
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
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.memory(
                              crop,
                              fit: BoxFit.fill,
                              gaplessPlayback: true,
                              filterQuality: FilterQuality.medium,
                              excludeFromSemantics: true,
                            ),
                            CustomPaint(
                              key: const ValueKey('original-doubts'),
                              painter: _DoubtMarks(
                                doubts,
                                dark ? BoardMarks.doubtLamp : BoardMarks.doubt,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
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
          // The segment the position rules out stays non-interactive but readable: full-strength secondary text.
          style: SegmentedButton.styleFrom(
            disabledForegroundColor: scheme.onSurfaceVariant,
          ),
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
                  child: AppIcon(
                    AppIcons.lock,
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
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Enroques permitidos',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Space.xs),
          Wrap(
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
        ],
      ),
    );
  }

  // ------------------------------------------------------------------ actions

  /// "Analizar en Lichess" (the block's main action), share or copy the PGN, and at the far end "Quitar
  /// diagrama". The label of the main button may take two lines at large text sizes; the icons keep their place.
  Widget _actionsRow(BuildContext context) {
    final canShare = _actions.canShare;
    return Row(
      children: [
        Flexible(
          child: FilledButton.tonalIcon(
            key: const ValueKey('lichess'),
            onPressed: () => unawaited(_actions.openLichess(context, _d)),
            icon: const AppIcon(AppIcons.openExternal),
            label: const Text('Analizar en Lichess'),
          ),
        ),
        const SizedBox(width: Space.xs),
        if (canShare)
          IconButton(
            key: const ValueKey('share-pgn'),
            tooltip: 'Compartir o copiar PGN',
            onPressed: () =>
                unawaited(_actions.sharePgn(context, _session.pgnOf(_d))),
            icon: const AppIcon(AppIcons.share),
          )
        else
          IconButton(
            key: const ValueKey('copy-pgn'),
            tooltip: 'Copiar PGN',
            onPressed: () => unawaited(
              _actions.copy(context, _session.pgnOf(_d), 'PGN copiado'),
            ),
            icon: const AppIcon(AppIcons.copy),
          ),
        const Spacer(),
        IconButton(
          key: const ValueKey('remove-diagram'),
          tooltip: 'Quitar diagrama',
          onPressed: _delete,
          icon: const AppIcon(AppIcons.delete),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------- FEN

  /// The FEN in one mono line (tap to copy) and a real 48 dp "Copiar FEN" button at its end.
  Widget _fenLine(BuildContext context, TextTheme text, ColorScheme scheme) {
    final fen = _d.fen;
    void copy() => unawaited(_actions.copy(context, fen, 'FEN copiado'));
    return Row(
      children: [
        Expanded(
          child: Semantics(
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
                child: Align(
                  alignment: Alignment.centerLeft,
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
              ),
            ),
          ),
        ),
        IconButton(
          key: const ValueKey('copy-fen'),
          tooltip: 'Copiar FEN',
          onPressed: copy,
          icon: const AppIcon(AppIcons.copy),
        ),
      ],
    );
  }
}

/// The doubtful corner marks over the "Original" picture: the same amber rule and corner triangle the board
/// draws, so the squares the reader doubted can be looked at in the book's own picture. [doubts] are by screen
/// position (row-major from the top-left).
class _DoubtMarks extends CustomPainter {
  const _DoubtMarks(this.doubts, this.color);

  final List<bool> doubts;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 8;
    final thin = cell < 24;
    final rule = thin ? 1.0 : 2.0;
    final t = (cell * 0.36).clamp(7.0, 22.0);
    for (var i = 0; i < 64; i++) {
      if (!doubts[i]) continue;
      final rect = Rect.fromLTWH((i % 8) * cell, (i ~/ 8) * cell, cell, cell);
      canvas.drawRect(
        rect.deflate(rule / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = rule
          ..color = color,
      );
      canvas.drawRect(
        rect.deflate(rule + 0.5),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = BoardMarks.doubtEdge,
      );
      final tri = Path()
        ..moveTo(rect.right - t, rect.top + rule)
        ..lineTo(rect.right - rule, rect.top + rule)
        ..lineTo(rect.right - rule, rect.top + t)
        ..close();
      canvas.drawPath(tri, Paint()..color = color);
      canvas.drawPath(
        tri,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..strokeJoin = StrokeJoin.round
          ..color = BoardMarks.doubtEdge,
      );
    }
  }

  @override
  bool shouldRepaint(_DoubtMarks old) =>
      color != old.color || !listEquals(doubts, old.doubts);
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
