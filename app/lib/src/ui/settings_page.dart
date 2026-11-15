// Ajustes (docs/ux-spec.md, 4.4): theme, ink, board style, coordinates, piece set and "Acerca de".
//
// A live preview board is fixed at the top (compact width) or in its own column (>= 840 dp wide, where the
// controls sit to its right in a constrained column, not a stretched phone). Every change goes straight to
// the [AppSettings] of the `AppScope`, which applies it live and persists it.
import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../settings.dart';
import 'board.dart';
import 'color_math.dart';
import 'pieces.dart';
import 'scope.dart';
import 'theme.dart';
import 'tokens.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.appVersion});

  /// Shown in "Acerca de" (from the pubspec; the app passes it in).
  final String appVersion;

  /// Pushes the page on the nearest navigator.
  static Future<void> open(
    BuildContext context, {
    required String appVersion,
  }) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SettingsPage(appVersion: appVersion),
      settings: const RouteSettings(name: '/ajustes'),
    ),
  );

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // The piece-set tiles show every set: parse them all once, now.
    final scope = AppScope.maybeOf(context);
    if (scope != null) unawaited(scope.catalog.ensureAllLoaded());
  }

  @override
  Widget build(BuildContext context) {
    final scope = AppScope.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= Breakpoint.expanded;
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: SafeArea(
        top: false,
        child: wide
            ? _WideLayout(scope: scope, appVersion: widget.appVersion)
            : _CompactLayout(scope: scope, appVersion: widget.appVersion),
      ),
    );
  }
}

// ------------------------------------------------------------------------------------------- layouts

class _CompactLayout extends StatelessWidget {
  const _CompactLayout({required this.scope, required this.appVersion});

  final AppScope scope;
  final String appVersion;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final scheme = Theme.of(context).colorScheme;
    final gutter = Space.gutter(size.width);
    final side = (size.width * 0.56)
        .clamp(150.0, 232.0)
        .clamp(0.0, size.height * 0.32);
    return Column(
      children: [
        // The preview stays put while the controls scroll under it.
        ColoredBox(
          color: scheme.surfaceContainerLow,
          child: SizedBox(
            width: double.infinity,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: Space.lg),
              child: Center(
                child: _Preview(settings: scope.settings, side: side),
              ),
            ),
          ),
        ),
        Expanded(
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: _Controls(
                scope: scope,
                appVersion: appVersion,
                padding: EdgeInsets.fromLTRB(gutter, 0, gutter, Space.xl),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _WideLayout extends StatelessWidget {
  const _WideLayout({required this.scope, required this.appVersion});

  final AppScope scope;
  final String appVersion;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final settings = scope.settings;
    final ink = inkById(settings.inkId);
    final set = scope.catalog.resolve(settings.pieceSetId);
    final summary = [
      ink.name,
      settings.boardStyle == BoardStyle.printed ? 'Impreso' : 'Liso',
      set.name,
    ].join(' · ');
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.xl, Space.xl, Space.xl, 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 392,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(Corner.container),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(Space.xl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _Preview(settings: settings, side: 344),
                        const SizedBox(height: Space.lg),
                        Text(
                          summary,
                          style: text.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Space.xxl),
              Expanded(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 580),
                    child: _Controls(
                      scope: scope,
                      appVersion: appVersion,
                      padding: const EdgeInsets.only(bottom: Space.xl),
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
}

/// The live preview: a real position in the current ink, style, piece set and coordinates.
class _Preview extends StatelessWidget {
  const _Preview({required this.settings, required this.side});

  final AppSettings settings;
  final double side;

  @override
  Widget build(BuildContext context) => BoardView.preview(
    size: side,
    showCoordinates: settings.showCoordinates,
    semanticLabel: 'Vista previa del tablero',
  );
}

// ---------------------------------------------------------------------------------------------- controls

class _Controls extends StatelessWidget {
  const _Controls({
    required this.scope,
    required this.appVersion,
    required this.padding,
  });

  final AppScope scope;
  final String appVersion;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final settings = scope.settings;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: padding,
      children: [
        const _Section('Apariencia'),
        const _Label('Tema'),
        SegmentedButton<ThemeMode>(
          expandedInsets: EdgeInsets.zero,
          showSelectedIcon: true,
          segments: const [
            ButtonSegment(value: ThemeMode.system, label: Text('Sistema')),
            ButtonSegment(value: ThemeMode.light, label: Text('Claro')),
            ButtonSegment(value: ThemeMode.dark, label: Text('Oscuro')),
          ],
          selected: {settings.themeMode},
          onSelectionChanged: (s) => unawaited(settings.setThemeMode(s.first)),
        ),
        const SizedBox(height: Space.lg),
        const _Label('Tinta'),
        _InkPicker(
          selectedId: settings.inkId,
          onSelected: (id) => unawaited(settings.setInkId(id)),
        ),
        const _Section('Tablero'),
        const _Label('Estilo'),
        SegmentedButton<BoardStyle>(
          expandedInsets: EdgeInsets.zero,
          segments: const [
            ButtonSegment(value: BoardStyle.flat, label: Text('Liso')),
            ButtonSegment(value: BoardStyle.printed, label: Text('Impreso')),
          ],
          selected: {settings.boardStyle},
          onSelectionChanged: (s) => unawaited(settings.setBoardStyle(s.first)),
        ),
        const SizedBox(height: Space.sm),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Coordenadas'),
          subtitle: const Text('Letras a–h y números 1–8 junto al tablero'),
          value: settings.showCoordinates,
          onChanged: (v) => unawaited(settings.setShowCoordinates(v)),
        ),
        const SizedBox(height: Space.sm),
        const _Label('Piezas'),
        _PieceGrid(
          catalog: scope.catalog,
          selectedId: scope.catalog.resolve(settings.pieceSetId).id,
          boardStyle: settings.boardStyle,
          onSelected: (id) => unawaited(settings.setPieceSetId(id)),
        ),
        const _Section('Acerca de'),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.info_outline),
          title: const Text('Versión'),
          trailing: Text(
            appVersion,
            style: text.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              fontFeatures: tabularFigures,
            ),
          ),
        ),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.lock_outline),
          title: Text('Todo se procesa en el dispositivo.'),
          subtitle: Text('Las capturas no salen del móvil ni del ordenador.'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.description_outlined),
          title: const Text('Licencias'),
          subtitle: const Text('Piezas, fuentes y paquetes'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => showLicensePage(
            context: context,
            applicationName: 'Chess to PGN',
            applicationVersion: appVersion,
          ),
        ),
      ],
    );
  }
}

/// Section heading: more space above than below.
class _Section extends StatelessWidget {
  const _Section(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      header: true,
      child: Padding(
        padding: const EdgeInsets.only(
          top: Space.xl + Space.sm,
          bottom: Space.md,
        ),
        child: Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

/// Name of a control, above it.
class _Label extends StatelessWidget {
  const _Label(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Text(
        label,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------------------------------- inks

class _InkPicker extends StatelessWidget {
  const _InkPicker({required this.selectedId, required this.onSelected});

  final String selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 540 ? 6 : 3;
        final cell = constraints.maxWidth / columns;
        return Wrap(
          children: [
            for (final ink in inks)
              SizedBox(
                width: cell,
                child: _InkSwatch(
                  ink: ink,
                  selected: ink.id == selectedId,
                  onTap: () => onSelected(ink.id),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A round sample of an ink with its name; the chosen one has a check and a ring (never colour alone).
class _InkSwatch extends StatelessWidget {
  const _InkSwatch({
    required this.ink,
    required this.selected,
    required this.onTap,
  });

  final SpotInk ink;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // What gets printed: the ink's `primary` in the current brightness (masthead, numerals), not the raw seed.
    final printed = inkPrimary(ink, theme.brightness);
    final onSeed =
        contrastRatio(printed, BoardMarks.pieceWhite) >=
            contrastRatio(printed, BoardMarks.pieceBlack)
        ? BoardMarks.pieceWhite
        : BoardMarks.pieceBlack;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: ink.name,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        borderRadius: BorderRadius.circular(Corner.container),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: minTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: Space.sm,
              horizontal: Space.xs,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: Motion.of(context, Motion.fast),
                  width: 52,
                  height: 52,
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected ? scheme.onSurface : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: printed,
                      border: Border.all(color: scheme.outline, width: 1),
                    ),
                    child: selected
                        ? Icon(Icons.check, color: onSeed, size: 22)
                        : null,
                  ),
                ),
                const SizedBox(height: Space.xs),
                Text(
                  ink.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------------------------- pieces

class _PieceGrid extends StatelessWidget {
  const _PieceGrid({
    required this.catalog,
    required this.selectedId,
    required this.boardStyle,
    required this.onSelected,
  });

  final PieceSetCatalog catalog;
  final String selectedId;
  final BoardStyle boardStyle;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = Space.md;
        final columns = constraints.maxWidth >= 520 ? 3 : 2;
        final cell = (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final set in catalog.sets)
              SizedBox(
                width: cell,
                child: _PieceSetTile(
                  set: set,
                  selected: set.id == selectedId,
                  boardStyle: boardStyle,
                  onTap: () => onSelected(set.id),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _PieceSetTile extends StatelessWidget {
  const _PieceSetTile({
    required this.set,
    required this.selected,
    required this.boardStyle,
    required this.onTap,
  });

  final PieceSet set;
  final bool selected;
  final BoardStyle boardStyle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final fg = selected ? scheme.onSecondaryContainer : scheme.onSurface;
    final fgVariant = selected
        ? scheme.onSecondaryContainer
        : scheme.onSurfaceVariant;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: '${set.name}, de ${set.author}',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: selected
            ? scheme.secondaryContainer
            : scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Corner.container),
          side: selected
              ? BorderSide(color: scheme.primary, width: 2)
              : BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(Space.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SetPreview(setId: set.id, size: 88, style: boardStyle),
                    const Spacer(),
                    if (selected)
                      Icon(Icons.check_circle, color: scheme.primary, size: 24),
                  ],
                ),
                const SizedBox(height: Space.sm),
                Text(
                  set.name,
                  style: theme.textTheme.titleSmall?.copyWith(color: fg),
                ),
                const SizedBox(height: Space.xs),
                Text(
                  set.author,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(color: fgVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
