// Home / session screen (docs/ux-spec.md, 4.1): the first-run composition, then the captures read so far as
// groups of diagram blocks, with the "Añadir captura" FAB, the export bar and, at the end of the list, "Quitar
// todas las capturas". No overflow menus anywhere: every action is a visible button.
//
//   < 600 dp   one column            >= 840 dp   two columns (and the FAB docks in the export bar)
//   >= 1240 dp three columns         blocks never grow past [blockMaxWidth]
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../main.dart' show kAppVersion;
import '../diagram.dart';
import '../export.dart' as exporter;
import '../session.dart';
import 'board.dart';
import 'capture_thumb.dart';
import 'diagram_block.dart';
import 'equal_row.dart';
import 'export_bar.dart';
import 'home_actions.dart';
import 'icons.dart';
import 'scope.dart';
import 'settings_page.dart';
import 'theme.dart';
import 'tokens.dart';

export 'home_actions.dart' show CropRegionFn, ImageSourceFn;

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.pickImage,
    this.cropRegion,
    this.saveFile,
    this.shareText,
    this.shareFile,
    this.openUri,
    this.canShare,
    this.now,
    this.platform,
  });

  /// The image picker (the gallery by default).
  final ImageSourceFn? pickImage;

  /// The manual crop screen ([showCropPage] by default).
  final CropRegionFn? cropRegion;

  final exporter.SaveFileFn? saveFile;
  final exporter.ShareTextFn? shareText;
  final exporter.ShareFileFn? shareFile;

  /// Opens a link outside the app (Lichess).
  final exporter.OpenUriFn? openUri;

  /// Whether to offer sharing; [exporter.canShare] (Android) by default.
  final bool? canShare;

  final DateTime Function()? now;

  /// The platform the wording follows ("Elige la imagen de tu galería" on Android); [defaultTargetPlatform] by
  /// default.
  final TargetPlatform? platform;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ScrollController _scroll = ScrollController();
  final ValueNotifier<bool> _scrolled = ValueNotifier(false);
  final Map<int, GlobalKey> _headerKeys = {};
  final Map<Diagram, GlobalKey<DiagramBlockState>> _blockKeys = {};
  final GlobalKey _fabKey = GlobalKey();
  double _fabHeight = 56;
  HomeActions? _actions;

  HomeActions get actions => _actions!;
  Session get session => actions.session;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      final away = _scroll.hasClients && _scroll.offset > 8;
      if (away != _scrolled.value) _scrolled.value = away;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_actions == null) {
      final scope = AppScope.of(context);
      _actions =
          HomeActions(
              session: scope.session,
              pickImage: widget.pickImage,
              cropRegion: widget.cropRegion,
              saveFile: widget.saveFile,
              shareText: widget.shareText,
              shareFile: widget.shareFile,
              openUri: widget.openUri,
              canShare: widget.canShare,
              now: widget.now,
            )
            ..onCaptureAdded = _reveal
            ..onRevealDiagram = _revealDiagram;
    }
  }

  @override
  void dispose() {
    _actions?.dispose();
    _scroll.dispose();
    _scrolled.dispose();
    super.dispose();
  }

  GlobalKey _headerKey(SourceImage s) =>
      _headerKeys.putIfAbsent(s.id, GlobalKey.new);

  GlobalKey<DiagramBlockState> _blockKey(Diagram d) =>
      _blockKeys.putIfAbsent(d, GlobalKey<DiagramBlockState>.new);

  /// Scrolls the list to the group of a capture that was just added.
  void _reveal(SourceImage source, {int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _headerKeys[source.id]?.currentContext;
      if (ctx != null) {
        unawaited(
          Scrollable.ensureVisible(
            ctx,
            alignment: 0,
            duration: Motion.of(context, Motion.slow),
            curve: Motion.emphasized,
          ),
        );
      } else if (attempt < 3 && _scroll.hasClients) {
        // The group is far below what is built: go to the end, where new captures are, and look again.
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
        _reveal(source, attempt: attempt + 1);
      }
    });
  }

  /// Scrolls to the block of [diagram], however far it is (the list is lazy: blocks off screen are not built, so
  /// it walks towards the block until it exists), and opens its review when asked.
  Future<void> _revealDiagram(Diagram diagram, {bool review = false}) async {
    final key = _blockKey(diagram);
    for (var attempt = 0; attempt < 60; attempt++) {
      if (!mounted) return;
      if (!_scroll.hasClients) return;
      final ctx = key.currentContext;
      if (ctx != null && ctx.mounted) {
        await Scrollable.ensureVisible(
          ctx,
          alignment: 0,
          duration: Motion.of(context, Motion.slow),
          curve: Motion.standard,
        );
        break;
      }
      final target = session.numberOf(diagram);
      final built = [
        for (final e in _blockKeys.entries)
          if (e.value.currentContext != null) session.numberOf(e.key),
      ];
      final forward = built.isEmpty || target > built.reduce(math.max);
      final position = _scroll.position;
      final step = position.viewportDimension * 0.7;
      final to = (position.pixels + (forward ? step : -step)).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if (to == position.pixels) return;
      _scroll.jumpTo(to);
      WidgetsBinding.instance.scheduleFrame();
      await WidgetsBinding.instance.endOfFrame;
    }
    if (review && mounted) await _blockKeys[diagram]?.currentState?.review();
  }

  /// The count of diagrams with warnings in the export bar: the first of them, with its review when it has
  /// doubtful squares.
  void _onWarnings(Diagram first) =>
      unawaited(_revealDiagram(first, review: first.hasDoubts));

  void _removeSource(SourceImage source) {
    final messenger = ScaffoldMessenger.of(context);
    final title = source.title;
    final removed = session.removeSource(source);
    if (removed == null) return;
    actions.toast(
      messenger,
      '$title quitada',
      action: removed.restorable ? 'Deshacer' : null,
      onAction: () => session.restoreSource(removed),
      duration: const Duration(seconds: 6),
    );
  }

  void _clearAll() {
    final messenger = ScaffoldMessenger.of(context);
    final cleared = session.clear();
    if (cleared == null) return;
    actions.toast(
      messenger,
      'Sesión vaciada',
      action: cleared.isEmpty ? null : 'Deshacer',
      onAction: () => session.restoreCleared(cleared),
      duration: const Duration(seconds: 6),
    );
  }

  /// Keeps the list's bottom padding equal to the real FAB.
  void _measureFab() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final h = _fabKey.currentContext?.size?.height;
      if (h != null && h != _fabHeight) setState(() => _fabHeight = h);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): () =>
            unawaited(actions.pick(context)),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () {
          if (session.diagramCount > 0) unawaited(actions.saveAll(context));
        },
      },
      child: Focus(
        autofocus: true,
        child: ListenableBuilder(
          listenable: Listenable.merge([session, actions]),
          builder: (context, _) {
            final width = MediaQuery.sizeOf(context).width;
            final wide = width >= Breakpoint.expanded;
            final empty = session.isEmpty;
            final hasBar = session.diagramCount > 0;
            final docked = wide && hasBar;
            if (!empty) _measureFab();
            return Scaffold(
              backgroundColor: scheme.surface,
              appBar: AppBar(
                title: const Text('Chess to PGN'),
                actions: [
                  IconButton(
                    icon: const AppIcon(AppIcons.settings),
                    tooltip: 'Ajustes',
                    onPressed: () =>
                        SettingsPage.open(context, appVersion: kAppVersion),
                  ),
                ],
              ),
              body: empty
                  ? _EmptyState(
                      onPick: () => unawaited(actions.pick(context)),
                      android:
                          (widget.platform ?? defaultTargetPlatform) ==
                          TargetPlatform.android,
                    )
                  : _list(context, floatingFab: !docked),
              floatingActionButton: empty || docked ? null : _fab(false),
              bottomNavigationBar: hasBar
                  ? ExportBar(
                      actions: actions,
                      horizontalPadding: wide ? _sidePadding(width) : null,
                      trailing: docked ? _fab(true) : null,
                      onWarnings: _onWarnings,
                    )
                  : null,
            );
          },
        ),
      ),
    );
  }

  /// "Añadir captura": the extended FAB. On a phone it shrinks to the 56 dp icon FAB once the list has been
  /// scrolled away from the top, or when the text size is large (the label would take half the screen).
  Widget _fab(bool docked) => KeyedSubtree(
    key: docked ? null : _fabKey,
    child: ValueListenableBuilder<bool>(
      valueListenable: _scrolled,
      builder: (context, scrolled, _) {
        final width = MediaQuery.sizeOf(context).width;
        final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final compact =
            width < Breakpoint.medium && (scrolled || scale >= 1.15);
        void add() => unawaited(actions.pick(context));
        return AnimatedSwitcher(
          duration: Motion.of(context, Motion.fast),
          child: compact
              ? FloatingActionButton(
                  key: const ValueKey('fab-compact'),
                  heroTag: null,
                  tooltip: 'Añadir captura',
                  onPressed: add,
                  child: const AppIcon(AppIcons.addCapture),
                )
              : FloatingActionButton.extended(
                  key: const ValueKey('fab-extended'),
                  heroTag: null,
                  onPressed: add,
                  icon: const AppIcon(AppIcons.addCapture),
                  label: const Text('Añadir captura'),
                ),
        );
      },
    ),
  );

  // ---------------------------------------------------------------- the list

  static int _columnsFor(double width) => width >= Breakpoint.wide
      ? 3
      : width >= Breakpoint.expanded
      ? 2
      : 1;

  static const double _gap = Space.lg;

  static double _contentWidth(double width) {
    final cols = _columnsFor(width);
    return math.min(
      width - 2 * Space.gutter(width),
      cols * blockMaxWidth + (cols - 1) * _gap,
    );
  }

  static double _sidePadding(double width) =>
      (width - _contentWidth(width)) / 2;

  Widget _list(BuildContext context, {required bool floatingFab}) {
    final padding = MediaQuery.paddingOf(context);
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        final cols = _columnsFor(width);
        final side = math.max(
          _sidePadding(width),
          math.max(padding.left, padding.right),
        );
        // The FAB floats over the end of the list: the padding is its real height plus the margin the Scaffold
        // leaves under it and the same again above it, so the last block's actions stay clear of it. (The bar is
        // not part of this: the Scaffold lays the list out above it.)
        final bottom = floatingFab
            ? _fabHeight + 2 * Space.lg + padding.bottom
            : Space.xl;
        final sources = session.sources;
        _blockKeys.removeWhere(
          (d, _) => !sources.any((s) => s.diagrams.contains(d)),
        );
        var before = 0;
        final groups = <Widget>[];
        for (final source in sources) {
          groups.add(
            _GroupHost(
              key: ValueKey('group-${source.id}'),
              source: source,
              first: identical(source, sources.first),
              before: before,
              columns: cols,
              actions: actions,
              headerKey: _headerKey(source),
              blockKey: _blockKey,
              onRemove: _removeSource,
            ),
          );
          before += source.diagrams.length;
        }
        return CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(side, 0, side, bottom),
              sliver: SliverMainAxisGroup(
                slivers: [
                  ...groups,
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.only(top: Space.sm),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _ClearAll(onPressed: _clearAll),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ------------------------------------------------------------------------------------- clear everything

/// The one quiet way to empty the session, after the last group (it used to hide in a menu of the app bar).
class _ClearAll extends StatelessWidget {
  const _ClearAll({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => TextButton.icon(
    key: const ValueKey('clear-all'),
    style: TextButton.styleFrom(
      foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
    ),
    onPressed: onPressed,
    icon: const AppIcon(AppIcons.deleteAll),
    label: const Text('Quitar todas las capturas'),
  );
}

// ------------------------------------------------------------------------------------------------- group

/// One capture: its header, its rows of blocks and skeletons, and its failure strip. It follows its own
/// [SourceImage]; a change of another capture (or of a diagram in another group) does not rebuild it, because the
/// same widget tree is handed back to the framework while the inputs are the same.
class _GroupHost extends StatefulWidget {
  const _GroupHost({
    super.key,
    required this.source,
    required this.first,
    required this.before,
    required this.columns,
    required this.actions,
    required this.headerKey,
    required this.blockKey,
    required this.onRemove,
  });

  final SourceImage source;
  final bool first;

  /// Diagrams in the captures before this one (the numbers go on from there).
  final int before;
  final int columns;
  final HomeActions actions;
  final GlobalKey headerKey;
  final GlobalKey<DiagramBlockState> Function(Diagram) blockKey;
  final void Function(SourceImage) onRemove;

  @override
  State<_GroupHost> createState() => _GroupHostState();
}

class _GroupHostState extends State<_GroupHost> {
  Widget? _shell;

  static const double _gap = Space.lg;

  @override
  void didUpdateWidget(_GroupHost old) {
    super.didUpdateWidget(old);
    if (old.source != widget.source ||
        old.first != widget.first ||
        old.before != widget.before ||
        old.columns != widget.columns ||
        old.actions != widget.actions) {
      _shell = null;
    }
  }

  @override
  Widget build(BuildContext context) => _shell ??= ListenableBuilder(
    listenable: Listenable.merge([widget.source, widget.actions]),
    builder: (context, _) => _group(),
  );

  Widget _group() {
    final source = widget.source;
    final cols = widget.columns;
    final diagrams = List<Diagram>.of(source.diagrams);
    final skeletons = source.status == SourceStatus.reading
        ? (source.found == null ? 1 : source.skeletons)
        : 0;
    final strip =
        source.status == SourceStatus.failed ||
        source.status == SourceStatus.noBoards;
    final count = diagrams.length + skeletons;
    final rows = (count / cols).ceil();

    Widget item(int i) {
      if (i < diagrams.length) {
        final d = diagrams[i];
        return DiagramBlock(
          key: widget.blockKey(d),
          diagram: d,
          number: widget.before + i + 1,
          actions: widget.actions,
          source: source,
        );
      }
      return DiagramSkeleton(
        key: ValueKey('skeleton-${source.id}-${i - diagrams.length}'),
      );
    }

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: _CaptureHeader(
            key: widget.headerKey,
            source: source,
            first: widget.first,
            actions: widget.actions,
            onRemove: () => widget.onRemove(source),
          ),
        ),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, r) => Padding(
              padding: const EdgeInsets.only(bottom: _gap),
              child: EqualHeightRow(
                columns: cols,
                gap: _gap,
                children: [
                  for (var j = 0; j < cols; j++)
                    if (r * cols + j < count) item(r * cols + j),
                ],
              ),
            ),
            childCount: rows,
          ),
        ),
        if (strip)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: _gap),
              child: _StatusStrip(
                key: ValueKey('strip-${source.id}'),
                source: source,
                actions: widget.actions,
                onRemove: () => widget.onRemove(source),
                wide: cols > 1,
              ),
            ),
          ),
      ],
    );
  }
}

// ------------------------------------------------------------------------------------------ group header

class _CaptureHeader extends StatelessWidget {
  const _CaptureHeader({
    super.key,
    required this.source,
    required this.first,
    required this.actions,
    required this.onRemove,
  });

  final SourceImage source;
  final bool first;
  final HomeActions actions;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final done = source.status == SourceStatus.done;
    final progress = source.progressText;
    final readingRegion = actions.isReadingRegion(source);
    final busy = source.isPending || readingRegion;
    final progressLine = readingRegion ? 'Leyendo el recorte…' : progress;

    return Padding(
      padding: EdgeInsets.only(
        top: first ? Space.sm : Space.lg,
        bottom: Space.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: minTarget),
            child: Row(
              children: [
                CaptureThumb(source: source),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      done
                          ? '${source.title} · ${source.diagramCountText}'
                          : source.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: text.titleMedium,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('capture-crop'),
                  tooltip: 'Recortar otro tablero a mano',
                  onPressed: busy
                      ? null
                      : () => unawaited(actions.cropByHand(context, source)),
                  icon: const AppIcon(AppIcons.crop),
                ),
                IconButton(
                  key: const ValueKey('capture-remove'),
                  tooltip: 'Quitar captura',
                  onPressed: onRemove,
                  icon: const AppIcon(AppIcons.delete),
                ),
              ],
            ),
          ),
          if (progressLine != null) ...[
            Semantics(
              liveRegion: true,
              child: Text(
                progressLine,
                style: text.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: Space.sm),
            if (source.status != SourceStatus.queued)
              LinearProgressIndicator(
                value: readingRegion ? null : source.progress,
                semanticsLabel: progressLine,
                borderRadius: BorderRadius.circular(2),
              ),
          ],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------------------------------ failure strip

/// A capture that could not be read, inline in its group, with what happened and the way out. On a window with
/// several columns it is a band across the content column (message at the start, actions at the end) instead of
/// a block-sized box stuck in the first column.
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({
    super.key,
    required this.source,
    required this.actions,
    required this.onRemove,
    required this.wide,
  });

  final SourceImage source;
  final HomeActions actions;
  final VoidCallback onRemove;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final failed = source.status == SourceStatus.failed;
    final bg = failed ? scheme.errorContainer : scheme.surfaceContainerHigh;
    final fg = failed ? scheme.onErrorContainer : scheme.onSurface;
    final message = failed
        ? source.errorMessage ??
              'No se pudo leer esta captura. Inténtalo de nuevo.'
        : 'No se encontró ningún tablero en esta captura. Si el diagrama es pequeño, recórtalo a mano.';
    final busy = actions.isReadingRegion(source);
    final lead = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppIcon(failed ? AppIcons.error : AppIcons.noBoard, color: fg),
        const SizedBox(width: Space.md),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodyLarge?.copyWith(color: fg),
          ),
        ),
      ],
    );
    final buttons = Wrap(
      spacing: Space.sm,
      runSpacing: Space.xs,
      children: [
        if (failed)
          FilledButton.tonalIcon(
            onPressed: () => actions.session.retry(source),
            icon: const AppIcon(AppIcons.retry),
            label: const Text('Reintentar'),
          )
        else
          FilledButton.tonalIcon(
            onPressed: busy
                ? null
                : () => unawaited(actions.cropByHand(context, source)),
            icon: const AppIcon(AppIcons.crop),
            label: const Text('Recortar a mano'),
          ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: fg),
          onPressed: onRemove,
          child: const Text('Quitar'),
        ),
      ],
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Corner.container),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: lead),
                  const SizedBox(width: Space.lg),
                  buttons,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  lead,
                  const SizedBox(height: Space.md),
                  buttons,
                ],
              ),
      ),
    );
  }
}

// -------------------------------------------------------------------------------------------- empty state

/// First run: the result first (an example diagram drawn with the current stone and pieces), then three steps
/// and the one button. Two columns on wide windows.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onPick, required this.android});

  final VoidCallback onPick;
  final bool android;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        final wide = width >= Breakpoint.expanded;
        final gutter = Space.gutter(width);
        final example = _Example(maxSide: wide ? 440 : 400);
        final guide = _Guide(onPick: onPick, wide: wide, android: android);
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            math.max(gutter, padding.left),
            Space.lg,
            math.max(gutter, padding.right),
            Space.xl + padding.bottom,
          ),
          child: ConstrainedBox(
            // centred in the window when it is taller than the content
            constraints: BoxConstraints(
              minHeight: math.max(
                0,
                c.maxHeight - Space.lg - Space.xl - padding.bottom,
              ),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: wide ? 1000 : 440),
                child: wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: example,
                            ),
                          ),
                          const SizedBox(width: Space.xxl + Space.lg),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: guide,
                            ),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          example,
                          const SizedBox(height: Space.xl),
                          guide,
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A diagram block in miniature: numeral, status with the doubtful squares the product points out, and the
/// board of the current stone and pieces. It is labelled "Ejemplo" and its numeral is muted: it is not yours.
class _Example extends StatelessWidget {
  const _Example({required this.maxSide});

  final double maxSide;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final app = context.app;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxSide),
      child: Semantics(
        container: true,
        label: 'Ejemplo de diagrama leído, con dos casillas dudosas',
        child: ExcludeSemantics(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(Corner.container),
            ),
            child: Padding(
              padding: const EdgeInsets.all(Space.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Text(
                        '1',
                        style: app.numeral.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: Space.md),
                      AppIcon(AppIcons.warning, size: 20, color: app.warning),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Text(
                          '2 casillas dudosas',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: app.warning,
                          ),
                        ),
                      ),
                      const SizedBox(width: Space.sm),
                      Text(
                        'Ejemplo',
                        key: const ValueKey('example-label'),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Space.md),
                  LayoutBuilder(
                    builder: (context, c) => BoardView.fromGrid(
                      grid: sampleGrid(),
                      doubtful: (sq) => sq == 21 || sq == 18,
                      size: c.maxWidth,
                      semanticLabel: 'Ejemplo de tablero',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Guide extends StatelessWidget {
  const _Guide({
    required this.onPick,
    required this.wide,
    required this.android,
  });

  final VoidCallback onPick;
  final bool wide;
  final bool android;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final steps = [
      'Haz una captura de la página',
      android ? 'Elige la imagen de tu galería' : 'Elige la imagen',
      'Revisa y exporta',
    ];
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text(
              'Pasa tus diagramas a PGN',
              style: wide ? text.headlineMedium : text.headlineSmall,
            ),
          ),
          const SizedBox(height: Space.lg),
          for (final (i, step) in steps.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xs),
              child: Row(
                children: [
                  SizedBox(
                    width: Space.xl + Space.sm,
                    child: ExcludeSemantics(
                      child: Text(
                        '${i + 1}',
                        style: context.app.masthead.copyWith(
                          color: scheme.primary,
                        ),
                      ),
                    ),
                  ),
                  Expanded(child: Text(step, style: text.bodyLarge)),
                ],
              ),
            ),
          const SizedBox(height: Space.xl),
          FilledButton.icon(
            onPressed: onPick,
            icon: const AppIcon(AppIcons.addCapture),
            label: const Text('Elegir captura'),
          ),
          const SizedBox(height: Space.lg),
          Row(
            children: [
              AppIcon(
                AppIcons.privacy,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  'Todo se procesa en el dispositivo.',
                  style: text.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
