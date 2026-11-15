// Home / session screen (docs/ux-spec.md, 4.1): the first-run composition, then the captures read so far as
// groups of diagram blocks, with the extended FAB "Añadir captura" and the export bar.
//
//   < 600 dp   one column            >= 840 dp   two columns (and the FAB docks in the export bar)
//   >= 1240 dp three columns         blocks never grow past [blockMaxWidth]
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../main.dart' show kAppVersion;
import '../diagram.dart';
import '../export.dart' as exporter;
import '../session.dart';
import 'board.dart';
import 'diagram_block.dart';
import 'equal_row.dart';
import 'export_bar.dart';
import 'home_actions.dart';
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

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final ScrollController _scroll = ScrollController();
  final Map<int, GlobalKey> _headerKeys = {};
  HomeActions? _actions;

  HomeActions get actions => _actions!;
  Session get session => actions.session;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_actions == null) {
      final scope = AppScope.of(context);
      _actions = HomeActions(
        session: scope.session,
        pickImage: widget.pickImage,
        cropRegion: widget.cropRegion,
        saveFile: widget.saveFile,
        shareText: widget.shareText,
        shareFile: widget.shareFile,
        openUri: widget.openUri,
        canShare: widget.canShare,
        now: widget.now,
      )..onCaptureAdded = _reveal;
    }
  }

  @override
  void dispose() {
    _actions?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  GlobalKey _headerKey(SourceImage s) =>
      _headerKeys.putIfAbsent(s.id, GlobalKey.new);

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

  Future<void> _confirmClear() async {
    final diagrams = session.diagramCount;
    final captures = session.sources.length;
    final ok = await _confirm(
      title: '¿Vaciar la sesión?',
      body:
          'Se quitarán ${captures == 1 ? 'la captura' : 'las $captures capturas'} '
          'y ${diagrams == 1 ? 'su diagrama' : 'sus $diagrams diagramas'}. No se puede deshacer.',
      action: 'Vaciar sesión',
    );
    if (ok) session.clear();
  }

  Future<void> _removeSource(SourceImage source) async {
    if (source.diagrams.isNotEmpty) {
      final n = source.diagrams.length;
      final ok = await _confirm(
        title: '¿Quitar la ${source.title.toLowerCase()}?',
        body:
            'Se quitará${n == 1 ? ' su diagrama' : 'n sus $n diagramas'}. No se puede deshacer.',
        action: 'Quitar captura',
      );
      if (!ok) return;
    }
    session.removeSource(source);
  }

  Future<bool> _confirm({
    required String title,
    required String body,
    required String action,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyO, control: true): () =>
            unawaited(actions.pick(context)),
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
            final fab = empty
                ? null
                : FloatingActionButton.extended(
                    onPressed: () => unawaited(actions.pick(context)),
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: const Text('Añadir captura'),
                  );
            return Scaffold(
              backgroundColor: scheme.surface,
              appBar: AppBar(
                title: const Text('Chess to PGN'),
                actions: [
                  IconButton(
                    icon: const Icon(Icons.settings_outlined),
                    tooltip: 'Ajustes',
                    onPressed: () =>
                        SettingsPage.open(context, appVersion: kAppVersion),
                  ),
                  if (session.diagramCount > 0)
                    PopupMenuButton<String>(
                      tooltip: 'Más opciones',
                      onSelected: (_) => unawaited(_confirmClear()),
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'clear',
                          child: Row(
                            children: [
                              Icon(Icons.delete_sweep_outlined, size: 20),
                              SizedBox(width: Space.md),
                              Text('Vaciar sesión'),
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
              body: empty
                  ? _EmptyState(onPick: () => unawaited(actions.pick(context)))
                  : _list(context, floatingFab: !(wide && hasBar)),
              floatingActionButton: wide && hasBar ? null : fab,
              bottomNavigationBar: hasBar
                  ? ExportBar(
                      count: session.diagramCount,
                      actions: actions,
                      horizontalPadding: wide ? _sidePadding(width) : null,
                      trailing: wide ? fab : null,
                    )
                  : null,
            );
          },
        ),
      ),
    );
  }

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

  static double _sidePadding(double width) => (width - _contentWidth(width)) / 2;

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
        // The FAB floats over the end of the list: keep the last block's actions clear of it.
        final bottom = floatingFab ? 56.0 + 2 * Space.lg + Space.sm : Space.xl;
        final sources = session.sources;
        var before = 0;
        final groups = <Widget>[];
        for (final (i, source) in sources.indexed) {
          groups.add(_group(source, i == 0, before, cols));
          before += source.diagrams.length;
        }
        return CustomScrollView(
          controller: _scroll,
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                side,
                0,
                side,
                bottom + (sources.isEmpty ? 0 : 0),
              ),
              sliver: SliverMainAxisGroup(slivers: groups),
            ),
          ],
        );
      },
    );
  }

  Widget _group(SourceImage source, bool first, int before, int cols) {
    final diagrams = List<Diagram>.of(source.diagrams);
    final skeletons = source.status == SourceStatus.reading
        ? (source.found == null ? 1 : source.skeletons)
        : 0;
    final strip =
        source.status == SourceStatus.failed ||
        source.status == SourceStatus.noBoards;
    final count = diagrams.length + skeletons + (strip ? 1 : 0);
    final rows = (count / cols).ceil();

    Widget item(int i) {
      if (i < diagrams.length) {
        final d = diagrams[i];
        return DiagramBlock(
          key: ObjectKey(d),
          diagram: d,
          number: before + i + 1,
          actions: actions,
        );
      }
      if (i < diagrams.length + skeletons) {
        return DiagramSkeleton(
          key: ValueKey('skeleton-${source.id}-${i - diagrams.length}'),
        );
      }
      return _StatusStrip(
        key: ValueKey('strip-${source.id}'),
        source: source,
        actions: actions,
        onRemove: () => _removeSource(source),
      );
    }

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(
          child: _CaptureHeader(
            key: _headerKey(source),
            source: source,
            first: first,
            actions: actions,
            onRemove: () => _removeSource(source),
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
      padding: EdgeInsets.only(top: first ? Space.sm : Space.lg, bottom: Space.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: minTarget),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      done ? '${source.title} · ${source.diagramCountText}' : source.title,
                      style: text.titleMedium,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Opciones de ${source.title.toLowerCase()}',
                  icon: const Icon(Icons.more_vert),
                  onSelected: (v) {
                    if (v == 'crop') {
                      unawaited(actions.cropByHand(context, source));
                    } else {
                      onRemove();
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: 'crop',
                      enabled: !busy,
                      child: const Row(
                        children: [
                          Icon(Icons.crop, size: 20),
                          SizedBox(width: Space.md),
                          Expanded(child: Text('Recortar otro tablero a mano')),
                        ],
                      ),
                    ),
                    const PopupMenuItem(
                      value: 'remove',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline, size: 20),
                          SizedBox(width: Space.md),
                          Text('Quitar captura'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (progressLine != null) ...[
            Semantics(
              liveRegion: true,
              child: Text(
                progressLine,
                style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
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

/// A capture that could not be read, inline in its group, with what happened and the way out.
class _StatusStrip extends StatelessWidget {
  const _StatusStrip({
    super.key,
    required this.source,
    required this.actions,
    required this.onRemove,
  });

  final SourceImage source;
  final HomeActions actions;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final failed = source.status == SourceStatus.failed;
    final bg = failed ? scheme.errorContainer : scheme.surfaceContainerHigh;
    final fg = failed ? scheme.onErrorContainer : scheme.onSurface;
    final message = failed
        ? source.errorMessage ?? 'No se pudo leer esta captura. Inténtalo de nuevo.'
        : 'No se encontró ningún tablero en esta captura.';
    final busy = actions.isReadingRegion(source);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Corner.container),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(failed ? Icons.error_outline : Icons.search_off, color: fg),
                const SizedBox(width: Space.md),
                Expanded(
                  child: Text(
                    message,
                    style: theme.textTheme.bodyLarge?.copyWith(color: fg),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Space.md),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.xs,
              children: [
                if (failed)
                  FilledButton.tonalIcon(
                    onPressed: () => actions.session.retry(source),
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reintentar'),
                  )
                else
                  FilledButton.tonalIcon(
                    onPressed: busy
                        ? null
                        : () => unawaited(actions.cropByHand(context, source)),
                    icon: const Icon(Icons.crop),
                    label: const Text('Recortar a mano'),
                  ),
                TextButton(
                  style: TextButton.styleFrom(foregroundColor: fg),
                  onPressed: onRemove,
                  child: const Text('Quitar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------------------------------- empty state

/// First run: the result first (an example diagram drawn with the current ink and pieces), then three steps
/// and the one button. Two columns on wide windows.
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onPick});

  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.paddingOf(context);
    return LayoutBuilder(
      builder: (context, c) {
        final width = c.maxWidth;
        final wide = width >= Breakpoint.expanded;
        final gutter = Space.gutter(width);
        final example = _Example(maxSide: wide ? 440 : 400);
        final guide = _Guide(onPick: onPick);
        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            math.max(gutter, padding.left),
            Space.lg,
            math.max(gutter, padding.right),
            Space.xl + padding.bottom,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ? 1000 : 440),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(child: Align(alignment: Alignment.centerRight, child: example)),
                        const SizedBox(width: Space.xxl + Space.lg),
                        Expanded(child: Align(alignment: Alignment.centerLeft, child: guide)),
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
        );
      },
    );
  }
}

/// A diagram block in miniature: numeral, status with the doubtful squares the product points out, and the
/// board of the current ink and pieces.
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
                      Text('1', style: app.numeral.copyWith(color: scheme.primary)),
                      const SizedBox(width: Space.md),
                      Icon(Icons.warning_amber_rounded, size: 20, color: app.warning),
                      const SizedBox(width: Space.sm),
                      Expanded(
                        child: Text(
                          '2 casillas dudosas',
                          style: theme.textTheme.bodyMedium?.copyWith(color: app.warning),
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
  const _Guide({required this.onPick});

  final VoidCallback onPick;

  static const _steps = [
    'Haz una captura de la página',
    'Elígela aquí',
    'Revisa y exporta',
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: Text('Pasa los diagramas de tus libros a PGN', style: text.headlineSmall),
          ),
          const SizedBox(height: Space.lg),
          for (final (i, step) in _steps.indexed)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.xs),
              child: Row(
                children: [
                  SizedBox(
                    width: Space.xl + Space.sm,
                    child: ExcludeSemantics(
                      child: Text(
                        '${i + 1}',
                        style: context.app.masthead.copyWith(color: scheme.primary),
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
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Elegir captura'),
          ),
          const SizedBox(height: Space.lg),
          Row(
            children: [
              Icon(Icons.lock_outline, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: Space.sm),
              Expanded(
                child: Text(
                  'Todo se procesa en el dispositivo.',
                  style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
