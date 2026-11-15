// The scenes the screenshot harness renders (see harness.dart for how to run it and how to add one).

import 'package:chessboard_pgn/main.dart';
import 'package:chessboard_pgn/src/settings.dart';
import 'package:chessboard_pgn/src/ui/board.dart';
import 'package:chessboard_pgn/src/ui/pieces.dart';
import 'package:chessboard_pgn/src/ui/settings_page.dart';
import 'package:chessboard_pgn/src/ui/theme.dart';
import 'package:chessboard_pgn/src/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'harness.dart';
import 'home_scenes.dart';

void registerAllScenes() {
  registerScene(
    'settings',
    (env) => const SettingsPage(appVersion: kAppVersion),
    textScale13: true,
  );
  registerScene(
    'settings_full',
    (env) => const SettingsPage(appVersion: kAppVersion),
    phoneSize: const Size(412, 2500),
    desktopSize: const Size(1280, 1000),
  );
  registerScene(
    'settings_granate_printed',
    (env) => const SettingsPage(appVersion: kAppVersion),
    settings: () => AppSettings(
      inkId: 'granate',
      boardStyle: BoardStyle.printed,
      pieceSetId: 'cburnett',
    ),
    phoneSize: const Size(412, 2500),
    desktopSize: const Size(1280, 1000),
  );
  registerScene(
    'board_gallery',
    (env) => const _BoardGallery(),
    phoneSize: const Size(412, 1700),
    desktopSize: const Size(1280, 1100),
  );
  registerScene(
    'piece_sets',
    (env) => _PieceSets(catalog: env.catalog),
    phoneSize: const Size(412, 1500),
    desktopSize: const Size(1280, 900),
  );
  registerScene(
    'specimen_type',
    (env) => const _TypeSpecimen(),
    phoneSize: const Size(412, 1800),
    desktopSize: const Size(1280, 1100),
  );
  registerScene(
    'specimen_components',
    (env) => const _ComponentSpecimen(),
    phoneSize: const Size(412, 2300),
    desktopSize: const Size(1280, 1500),
    textScale13: true,
  );
  registerScene(
    'specimen_overlays',
    (env) => const _OverlaySpecimen(),
    setup: (tester, env) async {
      await tester.tap(find.byKey(const ValueKey('open-sheet')));
      await tester.pump(const Duration(milliseconds: 400));
    },
  );
  registerHomeScenes();
}

// -------------------------------------------------------------------------------------------- gallery

/// A scrollable page with a title bar, for specimen scenes.
class _Page extends StatelessWidget {
  const _Page({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.sizeOf(context).width;
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView(
        padding: EdgeInsets.symmetric(horizontal: Space.gutter(w), vertical: Space.lg),
        children: children,
      ),
    );
  }
}

class _BoardGallery extends StatelessWidget {
  const _BoardGallery();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final w = MediaQuery.sizeOf(context).width;
    final gutter = Space.gutter(w);
    final columns = w >= 900 ? 4 : 2;
    const gap = Space.lg;
    final side = (w - 2 * gutter - gap * (columns - 1)) / columns;
    final grid = sampleGrid();
    return Scaffold(
      appBar: AppBar(title: const Text('Tableros')),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(gutter),
        child: Wrap(
          spacing: gap,
          runSpacing: Space.xl,
          children: [
            for (final ink in inks)
              for (final style in BoardStyle.values)
                SizedBox(
                  width: side,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${ink.name} · ${style == BoardStyle.flat ? 'liso' : 'impreso'}',
                        style: text.labelLarge?.copyWith(color: scheme.onSurface),
                      ),
                      const SizedBox(height: Space.sm),
                      BoardView.fromGrid(
                        grid: grid,
                        ink: ink,
                        style: style,
                        size: side,
                        showCoordinates: true,
                        doubtful: (sq) => sq == 21,
                        selected: 36,
                        onTap: (_) {},
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

// -------------------------------------------------------------------------------------------- pieces

class _PieceSets extends StatelessWidget {
  const _PieceSets({required this.catalog});

  final PieceSetCatalog catalog;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final app = context.app;
    final w = MediaQuery.sizeOf(context).width;
    final gutter = Space.gutter(w);
    final columns = w >= 900 ? 3 : 1;
    const gap = Space.xl;
    final width = (w - 2 * gutter - gap * (columns - 1)) / columns;
    final cell = (width / 6).floorToDouble();
    Widget row(List<int> classes, bool startLight) => Row(
      children: [
        for (final (i, cls) in classes.indexed)
          Container(
            width: cell,
            height: cell,
            color: (i.isEven == startLight) ? app.boardLight : app.boardDark,
            child: PieceView(cls, size: cell, catalog: catalog),
          ),
      ],
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Juegos de piezas')),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(gutter),
        child: Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final set in catalog.sets)
              SizedBox(
                width: width,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(set.name, style: text.titleMedium),
                    Text(
                      '${set.author} · ${set.license}',
                      style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: Space.sm),
                    DecoratedBox(
                      decoration: BoxDecoration(border: Border.all(color: scheme.outline)),
                      child: Column(
                        children: [
                          row([6, 5, 4, 3, 2, 1], true),
                          row([12, 11, 10, 9, 8, 7], true),
                          row([1, 2, 3, 4, 5, 6], false),
                        ],
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
}

// ------------------------------------------------------------------------------------------ specimens

class _TypeSpecimen extends StatelessWidget {
  const _TypeSpecimen();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final app = context.app;
    Widget role(String name, TextStyle? style, [String? sample]) => Padding(
      padding: const EdgeInsets.symmetric(vertical: Space.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              '$name ${style?.fontSize?.round()}',
              style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              sample ?? 'Mueven blancas',
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
    return _Page(
      title: 'Chess to PGN',
      children: [
        role('display L', t.displayLarge, 'Diagrama'),
        role('display M', t.displayMedium, 'Diagrama'),
        role('display S', t.displaySmall, 'Diagrama'),
        role('headline L', t.headlineLarge),
        role('headline M', t.headlineMedium),
        role('headline S', t.headlineSmall),
        role('title L', t.titleLarge),
        role('title M', t.titleMedium),
        role('title S', t.titleSmall),
        role('body L', t.bodyLarge, 'Toca una casilla para corregirla.'),
        role('body M', t.bodyMedium, 'Toca una casilla para corregirla.'),
        role('body S', t.bodySmall, 'Toca una casilla para corregirla.'),
        role('label L', t.labelLarge, 'Guardar .pgn'),
        role('label M', t.labelMedium, 'Blancas O-O-O'),
        role('label S', t.labelSmall, 'a b c d e f g h 1 2 3 4 5 6 7 8'),
        const SizedBox(height: Space.xl),
        Text('Cabecera y numeral', style: t.titleMedium?.copyWith(color: scheme.primary)),
        const SizedBox(height: Space.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('12', style: app.numeral.copyWith(color: scheme.primary)),
            const SizedBox(width: Space.md),
            Text('Chess to PGN', style: app.masthead.copyWith(color: scheme.onSurface)),
          ],
        ),
        const SizedBox(height: Space.md),
        Text(
          'Cifras tabulares: 1111 / 8888 / 0000',
          style: t.bodyMedium?.tabular,
        ),
        Text(
          '1111 8888 0000 (proporcionales)',
          style: t.bodyMedium?.copyWith(fontFeatures: const []),
        ),
        const SizedBox(height: Space.xl),
        Text('FEN y PGN (JetBrains Mono)', style: t.titleMedium?.copyWith(color: scheme.primary)),
        const SizedBox(height: Space.sm),
        SelectableText(
          'r1bq1rk1/pp2ppbp/2np1np1/8/3NP3/2N1BP2/PPPQ2PP/2KR1B1R w - - 0 1',
          style: app.mono,
        ),
        const SizedBox(height: Space.xs),
        Text('[Event "Diagrama 1"]  [SetUp "1"]', style: app.mono.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
  }
}

class _ComponentSpecimen extends StatefulWidget {
  const _ComponentSpecimen();

  @override
  State<_ComponentSpecimen> createState() => _ComponentSpecimenState();
}

class _ComponentSpecimenState extends State<_ComponentSpecimen> {
  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final app = context.app;
    Widget head(String s) => Padding(
      padding: const EdgeInsets.only(top: Space.xl, bottom: Space.sm),
      child: Text(s, style: t.titleMedium?.copyWith(color: scheme.primary)),
    );
    Widget band(Color bg, Color fg, IconData icon, String text) => Container(
      padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.md),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(Corner.container),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg),
          const SizedBox(width: Space.md),
          Expanded(child: Text(text, style: t.bodyMedium?.copyWith(color: fg))),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Componentes'),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.settings_outlined), tooltip: 'Ajustes'),
          IconButton(onPressed: () {}, icon: const Icon(Icons.more_vert), tooltip: 'Más'),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {},
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: const Text('Añadir captura'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(Space.gutter(MediaQuery.sizeOf(context).width), 0, Space.gutter(MediaQuery.sizeOf(context).width), 96),
        children: [
          head('Botones'),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              FilledButton(onPressed: () {}, child: const Text('Elegir captura')),
              FilledButton.tonal(onPressed: () {}, child: const Text('Guardar .pgn')),
              OutlinedButton(onPressed: () {}, child: const Text('Recortar a mano')),
              TextButton(onPressed: () {}, child: const Text('Copiar FEN')),
              const FilledButton(onPressed: null, child: Text('Desactivado')),
              FilledButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.open_in_new),
                label: const Text('Analizar en Lichess'),
              ),
              IconButton.filledTonal(onPressed: () {}, icon: const Icon(Icons.share_outlined), tooltip: 'Compartir'),
              IconButton(onPressed: () {}, icon: const Icon(Icons.delete_outline), tooltip: 'Eliminar'),
            ],
          ),
          head('Segmentado'),
          SegmentedButton<int>(
            expandedInsets: EdgeInsets.zero,
            segments: const [
              ButtonSegment(value: 0, label: Text('Leído')),
              ButtonSegment(value: 1, label: Text('Original')),
            ],
            selected: const {0},
            onSelectionChanged: (_) {},
          ),
          const SizedBox(height: Space.sm),
          SegmentedButton<int>(
            expandedInsets: EdgeInsets.zero,
            segments: const [
              ButtonSegment(value: 0, label: Text('Mueven blancas'), icon: Icon(Icons.circle_outlined)),
              ButtonSegment(value: 1, label: Text('Mueven negras'), icon: Icon(Icons.circle)),
            ],
            selected: const {1},
            onSelectionChanged: (_) {},
          ),
          head('Chips'),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: [
              FilterChip(label: const Text('Blancas O-O'), selected: true, onSelected: (_) {}),
              FilterChip(label: const Text('Blancas O-O-O'), selected: true, onSelected: (_) {}),
              FilterChip(label: const Text('Negras O-O'), selected: false, onSelected: (_) {}),
              ActionChip(label: const Text('Revisar dudosas'), avatar: const Icon(Icons.warning_amber_rounded, size: 18), onPressed: () {}),
            ],
          ),
          head('Interruptores y listas'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Coordenadas'),
            value: true,
            onChanged: (_) {},
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Piezas grandes'),
            subtitle: const Text('Desactivado'),
            value: false,
            onChanged: (_) {},
          ),
          const Divider(),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.description_outlined),
            title: const Text('Licencias'),
            subtitle: const Text('Piezas, fuentes y paquetes'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {},
          ),
          head('Estados'),
          band(app.warningContainer, app.onWarningContainer, Icons.warning_amber_rounded, '2 casillas dudosas'),
          const SizedBox(height: Space.sm),
          band(scheme.errorContainer, scheme.onErrorContainer, Icons.error_outline, 'Posición imposible: falta el rey blanco.'),
          const SizedBox(height: Space.sm),
          band(scheme.surfaceContainerHigh, scheme.onSurface, Icons.info_outline, 'No se encontró ningún tablero en esta captura.'),
          const SizedBox(height: Space.md),
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: app.warning),
              const SizedBox(width: Space.sm),
              Text('Casilla dudosa', style: t.bodyMedium?.copyWith(color: app.warning)),
              const SizedBox(width: Space.xl),
              Icon(Icons.error_outline, color: scheme.error),
              const SizedBox(width: Space.sm),
              Text('Error', style: t.bodyMedium?.copyWith(color: scheme.error)),
            ],
          ),
          head('Progreso'),
          const LinearProgressIndicator(value: 0.5),
          const SizedBox(height: Space.sm),
          Text('Leyendo 2 de 4…', style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          head('Superficies tonales'),
          for (final (name, color) in [
            ('surfaceContainerLow', scheme.surfaceContainerLow),
            ('surfaceContainer', scheme.surfaceContainer),
            ('surfaceContainerHigh', scheme.surfaceContainerHigh),
          ])
            Container(
              height: 40,
              margin: const EdgeInsets.only(bottom: Space.xs),
              padding: const EdgeInsets.symmetric(horizontal: Space.md),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(Corner.control)),
              child: Text(name, style: t.labelMedium),
            ),
        ],
      ),
    );
  }
}

class _OverlaySpecimen extends StatelessWidget {
  const _OverlaySpecimen();

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Hoja y aviso')),
      body: Padding(
        padding: const EdgeInsets.all(Space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Diagrama 1', style: t.titleMedium),
            const SizedBox(height: Space.sm),
            Builder(
              builder: (context) => FilledButton(
                key: const ValueKey('open-sheet'),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Diagrama eliminado'),
                      action: SnackBarAction(label: 'Deshacer', onPressed: () {}),
                    ),
                  );
                  showModalBottomSheet<void>(
                    context: context,
                    builder: (context) => SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Casilla e4', style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(height: Space.md),
                            for (final white in [true, false])
                              Row(
                                children: [
                                  for (var k = 1; k <= 6; k++)
                                    Expanded(
                                      child: SizedBox(
                                        height: minTarget,
                                        child: Center(child: PieceTile(white ? k : k + 6, size: 40, selected: white && k == 2)),
                                      ),
                                    ),
                                ],
                              ),
                            const SizedBox(height: Space.sm),
                            OutlinedButton(onPressed: () {}, child: const Text('Vacía')),
                          ],
                        ),
                      ),
                    ),
                  );
                },
                child: const Text('Abrir hoja'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
