// Ajustes (docs/ux-spec.md, 4.4): theme, stone, board style, coordinates, piece set and "Acerca de".
//
// A live preview board is fixed at the top (compact width) or in its own column (>= 840 dp wide, where the
// controls sit to its right in a constrained column, not a stretched phone). Every change goes straight to
// the [AppSettings] of the `AppScope`, which applies it live and persists it.
import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../settings.dart';
import 'board.dart';
import 'icons.dart';
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
    final stone = stoneById(settings.stoneId);
    final set = scope.catalog.resolve(settings.pieceSetId);
    final summary = [
      stone.name,
      _styleNames[settings.boardStyle]!,
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

/// The live preview: a real position in the current stone, style, piece set and coordinates.
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
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: ThemeMode.system, label: Text('Sistema')),
            ButtonSegment(value: ThemeMode.light, label: Text('Claro')),
            ButtonSegment(value: ThemeMode.dark, label: Text('Oscuro')),
          ],
          selected: {settings.themeMode},
          onSelectionChanged: (s) => unawaited(settings.setThemeMode(s.first)),
        ),
        const SizedBox(height: Space.lg),
        const _Label('Piedra'),
        _StonePicker(
          selectedId: settings.stoneId,
          onSelected: (id) => unawaited(settings.setStoneId(id)),
        ),
        const _Section('Tablero'),
        const _Label('Estilo'),
        SegmentedButton<BoardStyle>(
          expandedInsets: EdgeInsets.zero,
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: BoardStyle.stone, label: Text('Piedra')),
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
          leading: const AppIcon(AppIcons.info),
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
          leading: AppIcon(AppIcons.privacy),
          title: Text('Todo se procesa en el dispositivo.'),
          subtitle: Text('Las capturas no salen del móvil ni del ordenador.'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const AppIcon(AppIcons.licenses),
          title: const Text('Licencias'),
          subtitle: const Text('Piezas, fuentes y paquetes'),
          trailing: const AppIcon(AppIcons.go),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: Space.sm),
            const Divider(),
          ],
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

// ---------------------------------------------------------------------------------------------- stones

const Map<BoardStyle, String> _styleNames = {
  BoardStyle.stone: 'Piedra',
  BoardStyle.flat: 'Liso',
  BoardStyle.printed: 'Impreso',
};

class _StonePicker extends StatelessWidget {
  const _StonePicker({required this.selectedId, required this.onSelected});

  final String selectedId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 440 ? 5 : 3;
        final cell = constraints.maxWidth / columns;
        return Wrap(
          children: [
            for (final stone in stones)
              SizedBox(
                width: cell,
                child: _StoneSwatch(
                  stone: stone,
                  selected: stone.id == selectedId,
                  onTap: () => onSelected(stone.id),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// A piece of the board in a stone (2 x 2 squares with the speckle) and its name. The chosen one has a green
/// ring, a check and a bold name (never colour alone).
class _StoneSwatch extends StatelessWidget {
  const _StoneSwatch({
    required this.stone,
    required this.selected,
    required this.onTap,
  });

  final Stone stone;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const ring = 3.0, gap = 3.0, sample = 52.0;
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: stone.name,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        borderRadius: BorderRadius.circular(Corner.control),
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
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    AnimatedContainer(
                      duration: Motion.of(context, Motion.fast),
                      padding: const EdgeInsets.all(gap),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: selected ? scheme.primary : Colors.transparent,
                          width: ring,
                        ),
                      ),
                      child: StoneSample(stone: stone, size: sample),
                    ),
                    if (selected)
                      Positioned(
                        right: -4,
                        top: -4,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: IconTheme(
                              data: IconThemeData(color: scheme.onPrimary),
                              child: const AppIcon(AppIcons.check, size: 16),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: Space.xs),
                Text(
                  stone.name,
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
          borderRadius: BorderRadius.circular(Corner.control),
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
                      AppIcon(
                        AppIcons.check,
                        color: scheme.onSecondaryContainer,
                        size: 22,
                      ),
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
