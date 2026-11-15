import 'dart:io';

import 'package:chessboard_pgn/main.dart';
import 'package:chessboard_pgn/src/settings.dart';
import 'package:chessboard_pgn/src/ui/board.dart';
import 'package:chessboard_pgn/src/ui/icons.dart';
import 'package:chessboard_pgn/src/ui/licenses.dart';
import 'package:chessboard_pgn/src/ui/pieces.dart';
import 'package:chessboard_pgn/src/ui/settings_page.dart';
import 'package:chessboard_pgn/src/ui/theme.dart';
import 'package:chessboard_pgn/src/ui/tokens.dart';
import 'package:flutter/foundation.dart' show LicenseEntry, LicenseRegistry;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _root = GlobalKey();

Future<(AppSettings, SharedPreferences)> _pump(
  WidgetTester tester, {
  Size size = const Size(412, 915),
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final settings = await AppSettings.load(prefs: prefs);
  final catalog =
      await tester.runAsync(PieceSetCatalog.load) as PieceSetCatalog;
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    RepaintBoundary(
      key: _root,
      child: ChessPgnApp(
        settings: settings,
        catalog: catalog,
        home: const SettingsPage(appVersion: '9.8.7'),
      ),
    ),
  );
  await tester.runAsync(catalog.ensureAllLoaded);
  await tester.pump();
  return (settings, prefs);
}

Future<Color> _previewPixel(WidgetTester tester, int square) async {
  final board = tester.getRect(find.byType(BoardView).first);
  final layout = BoardLayout(
    board.width,
    coordinates:
        tester
            .widget<BoardView>(find.byType(BoardView).first)
            .showCoordinates ??
        true,
  );
  final c = board.topLeft + layout.cellRect(square).center;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_root),
  );
  late int w;
  late ByteData data;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    w = image.width;
    data = (await image.toByteData())!;
  });
  final i = 4 * (c.dy.round() * w + c.dx.round());
  return Color.fromARGB(
    255,
    data.getUint8(i),
    data.getUint8(i + 1),
    data.getUint8(i + 2),
  );
}

/// The most frequent colour of square [square] of the preview: the stone under its faint speckle.
Future<Color> _dominant(WidgetTester tester, int square) async {
  final board = tester.getRect(find.byType(BoardView).first);
  final layout = BoardLayout(
    board.width,
    coordinates:
        tester
            .widget<BoardView>(find.byType(BoardView).first)
            .showCoordinates ??
        true,
  );
  final r = board.topLeft + layout.cellRect(square).topLeft;
  final cell = layout.cell;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_root),
  );
  late int w;
  late ByteData data;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    w = image.width;
    data = (await image.toByteData())!;
  });
  final counts = <int, int>{};
  for (var y = 3.0; y < cell - 3; y++) {
    for (var x = 3.0; x < cell - 3; x++) {
      final i = 4 * ((r.dy + y).round() * w + (r.dx + x).round());
      final key =
          (data.getUint8(i) << 16) |
          (data.getUint8(i + 1) << 8) |
          data.getUint8(i + 2);
      counts[key] = (counts[key] ?? 0) + 1;
    }
  }
  final top = counts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  return Color.fromARGB(255, top >> 16, (top >> 8) & 255, top & 255);
}

void main() {
  testWidgets(
    'theme mode: the segmented button changes the settings and the theme',
    (tester) async {
      final (settings, prefs) = await _pump(tester);
      expect(settings.themeMode, ThemeMode.system);
      await tester.tap(find.text('Oscuro'));
      await tester.pump();
      expect(settings.themeMode, ThemeMode.dark);
      await tester.pump(const Duration(milliseconds: 300));
      expect(
        Theme.of(tester.element(find.byType(Scaffold))).brightness,
        Brightness.dark,
      );
      await tester.tap(find.text('Claro'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(settings.themeMode, ThemeMode.light);
      expect(
        Theme.of(tester.element(find.byType(Scaffold))).brightness,
        Brightness.light,
      );
      expect(
        prefs.getString('settings.themeMode'),
        'light',
        reason: 'persisted',
      );
    },
  );

  Finder checkIn(String name) => find.descendant(
    of: find.widgetWithText(InkWell, name),
    matching: find.byWidgetPredicate(
      (w) => w is AppIcon && w.icon == AppIcons.check,
    ),
  );

  testWidgets(
    'stone: choosing a swatch lays the board and the preview in it, and marks it with a check',
    (tester) async {
      final (settings, prefs) = await _pump(tester);
      expect(find.text('Piedra'), findsWidgets);
      expect(settings.stoneId, 'serpentina');
      expect(checkIn('Serpentina'), findsOneWidget);
      for (final s in stones) {
        expect(
          find.text(s.name),
          findsOneWidget,
          reason: 'five named swatches',
        );
      }
      expect(find.byType(StoneSample), findsNWidgets(5));
      await tester.tap(find.text('Rojo Alicante'));
      await tester.pump(); // settings applied, theme animation under way
      expect(settings.stoneId, 'alicante');
      await tester.pump(const Duration(milliseconds: 400));
      final app = AppTheme.of(tester.element(find.byType(BoardView).first));
      expect(app.stone.id, 'alicante');
      expect(
        Theme.of(tester.element(find.byType(Scaffold)))
            .appBarTheme
            .backgroundColor,
        buildTheme(
          stoneById('serpentina'),
          Brightness.light,
        ).appBarTheme.backgroundColor,
        reason: 'the shell stays park-bench green: only the board changes',
      );
      expect(checkIn('Rojo Alicante'), findsOneWidget);
      expect(checkIn('Serpentina'), findsNothing);
      // the preview's squares carry the new stone (the speckle is faint: look for the colour of the square)
      expect(await _dominant(tester, 16), stoneById('alicante').lightSquare);
      expect(prefs.getString('settings.stoneId'), 'alicante');
    },
  );

  testWidgets('board style and coordinates update the preview', (tester) async {
    final (settings, prefs) = await _pump(tester);
    final stone = stoneById('serpentina');
    expect(settings.boardStyle, BoardStyle.stone);
    // stone: a6 is a light square of the stone, b4 (index 33) a dark one
    expect(await _dominant(tester, 16), stone.lightSquare);
    expect(await _dominant(tester, 33), stone.darkSquare);

    await tester.tap(find.text('Liso'));
    await tester.pump();
    expect(settings.boardStyle, BoardStyle.flat);
    expect(await _previewPixel(tester, 16), stone.lightSquare);
    expect(prefs.getString('settings.boardStyle'), 'flat');

    await tester.tap(find.text('Impreso'));
    await tester.pump();
    expect(settings.boardStyle, BoardStyle.printed);
    expect(await _previewPixel(tester, 16), BoardMarks.paper);
    expect(prefs.getString('settings.boardStyle'), 'printed');

    expect(
      tester.widget<BoardView>(find.byType(BoardView).first).showCoordinates,
      isTrue,
    );
    await tester.ensureVisible(find.byType(Switch));
    await tester.pump();
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(settings.showCoordinates, isFalse);
    expect(
      tester.widget<BoardView>(find.byType(BoardView).first).showCoordinates,
      isFalse,
    );
    expect(prefs.getBool('settings.showCoordinates'), isFalse);
  });

  testWidgets(
    'no capsule: the segmented buttons and the swatches are 6 dp, the selected segment has no check',
    (tester) async {
      await _pump(tester);
      final seg = tester.widget<SegmentedButton<BoardStyle>>(
        find.byType(SegmentedButton<BoardStyle>),
      );
      expect(seg.showSelectedIcon, isFalse);
      expect(
        find.descendant(
          of: find.byType(SegmentedButton<BoardStyle>),
          matching: find.byType(AppIcon),
        ),
        findsNothing,
      );
      final theme = Theme.of(tester.element(find.byType(Scaffold)));
      expect(
        (theme.segmentedButtonTheme.style!.shape!.resolve(const {})!
                as RoundedRectangleBorder)
            .borderRadius,
        BorderRadius.circular(6),
      );
    },
  );

  testWidgets(
    'piece sets: one tile per set with name and author; choosing one is applied and kept',
    (tester) async {
      final (settings, prefs) = await _pump(tester);
      await tester.scrollUntilVisible(
        find.text('Colin M.L. Burnett'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Merida'), findsOneWidget);
      expect(find.text('Armando Hernandez Marroquin'), findsOneWidget);
      expect(find.text('Tipográfico'), findsOneWidget);
      expect(settings.pieceSetId, 'cburnett');
      await tester.ensureVisible(find.text('Merida'));
      await tester.pump();
      await tester.tap(find.text('Merida'));
      await tester.pump();
      expect(settings.pieceSetId, 'merida');
      expect(prefs.getString('settings.pieceSetId'), 'merida');
      // the chosen tile is announced as selected
      final handle = tester.ensureSemantics();
      expect(
        tester
            .getSemantics(
              find
                  .ancestor(
                    of: find.text('Merida'),
                    matching: find.byType(Semantics),
                  )
                  .first,
            )
            .getSemanticsData()
            .flagsCollection
            .isSelected
            .name,
        'isTrue',
      );
      handle.dispose();
    },
  );

  testWidgets('compact: the preview is above the controls; wide: two columns', (
    tester,
  ) async {
    await _pump(tester);
    final preview = tester.getRect(find.byType(BoardView).first);
    expect(
      preview.bottom,
      lessThan(tester.getTopLeft(find.text('Apariencia')).dy),
    );
    expect(preview.width, lessThanOrEqualTo(260));

    await _pump(tester, size: const Size(1280, 800));
    final wideBoard = tester.getRect(find.byType(BoardView).first);
    final controls = tester.getTopLeft(find.text('Apariencia'));
    expect(
      wideBoard.right,
      lessThan(controls.dx),
      reason: 'preview left, controls right',
    );
    expect(controls.dy, lessThan(300));
    expect(wideBoard.width, greaterThan(300));
    // the controls column is constrained, not stretched across the window
    final segmented = tester.getRect(find.byType(SegmentedButton<ThemeMode>));
    expect(segmented.width, lessThanOrEqualTo(600));
  });

  testWidgets('Acerca de: version, privacy line and the licences page', (
    tester,
  ) async {
    await _pump(tester);
    await tester.scrollUntilVisible(
      find.text('Licencias'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('9.8.7'), findsOneWidget);
    expect(find.text('Todo se procesa en el dispositivo.'), findsOneWidget);
    await tester.ensureVisible(find.text('Licencias'));
    await tester.pump();
    await tester.tap(find.text('Licencias'));
    await tester.pumpAndSettle();
    expect(find.byType(LicensePage), findsOneWidget);
    expect(find.text('Chess to PGN'), findsWidgets);
  });

  test(
    'the bundled licences cover piece sets and fonts with their full texts',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final entries = await bundledLicenses(rootBundle).toList();
      String text(LicenseEntry e) => e.paragraphs.map((p) => p.text).join('\n');
      final byPackage = <String, String>{};
      for (final e in entries) {
        for (final p in e.packages) {
          byPackage[p] = '${byPackage[p] ?? ''}\n${text(e)}';
        }
      }
      expect(byPackage['Barlow'], contains('SIL OPEN FONT LICENSE'));
      expect(byPackage['Barlow Condensed'], contains('SIL OPEN FONT LICENSE'));
      expect(byPackage.containsKey('Archivo'), isFalse);
      expect(byPackage['JetBrains Mono'], contains('SIL OPEN FONT LICENSE'));
      expect(byPackage['ChessFigures (DejaVu Sans)'], contains('Bitstream'));
      expect(
        byPackage['Piezas Merida'],
        contains('Armando Hernandez Marroquin'),
      );
      expect(
        byPackage['Piezas Merida'],
        contains('GNU GENERAL PUBLIC LICENSE'),
      );
      expect(byPackage['Piezas Cburnett'], contains('Colin M.L. Burnett'));
      expect(
        byPackage['Piezas MP Chess'],
        contains('GNU GENERAL PUBLIC LICENSE'),
      );
      expect(byPackage['Piezas Chessnut'], contains('Apache License'));
      expect(
        byPackage['Piezas Celta'],
        contains('Permission is hereby granted'),
      );
      expect(byPackage['Piezas Celta'], contains('Maurizio Monge'));
    },
  );

  test('the registry receives them', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    resetBundledLicensesForTest();
    registerBundledLicenses();
    final all = await LicenseRegistry.licenses.toList();
    expect(all.any((e) => e.packages.contains('Piezas Merida')), isTrue);
  });

  test('main.dart shows the version of the pubspec', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final version = RegExp(
      r'^version:\s*([\d.]+)',
      multiLine: true,
    ).firstMatch(pubspec)!.group(1);
    expect(kAppVersion, version);
  });
}
