// Screenshot harness: renders real screens to PNG files with the real fonts, in light and dark, at phone and
// desktop size. Skipped in the normal `flutter test` run.
//
// RUN (from app/, flutter on the PATH):
//
//   SCREENSHOT_DIR=/some/dir flutter test test/screenshots
//   SCREENSHOT_DIR=/some/dir flutter test test/screenshots --plain-name "settings"   # only scenes whose
//                                                                                    # test name matches
//
// OUTPUT: `<name>__<light|dark>__<phone|desktop>.png` for every registered scene (phone = 412 x 915 dp at
// devicePixelRatio 2.625, desktop = 1280 x 800 dp at 1.0). Scenes registered with `textScale13: true` also
// get `<name>__<light|dark>__phone-ts13.png` (system font size 1.3).
//
// ADDING A SCENE (in scenes.dart, or any file called from `registerAllScenes()`):
//
//   registerScene(
//     'diagram_block',                                   // file name stem; use snake_case
//     (env) => Scaffold(body: MyScreen(session: env.session)),
//     settings: () => AppSettings(stoneId: 'nogal'),       // optional; the theme mode is set per variant
//     setup: (tester, env) async {                       // optional: interact before the picture is taken
//       await tester.runAsync(() => env.session.addImage(bytes));
//       await tester.pump();
//     },
//     phoneSize: const Size(412, 2200),                  // optional: taller page for a long screen
//     textScale13: true,
//   );
//
// The builder receives a [SceneEnv] with the fakes that are also in the `AppScope`: `settings` (in-memory),
// `session` (a [Session] whose reader returns [fakeBoards]) and `catalog` (the real piece sets, all parsed).
// The widget it returns is the HOME of a real `ChessPgnApp`, so it gets the real theme, the Spanish
// localisation, the scope and the system bars handling. Fonts: Barlow, Barlow Condensed, JetBrains Mono and
// ChessFigures from assets/fonts, Material Icons from the Flutter SDK cache.
import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:chessboard_pgn/main.dart';
import 'package:chessboard_pgn/src/chess.dart';
import 'package:chessboard_pgn/src/locate.dart';
import 'package:chessboard_pgn/src/pipeline.dart';
import 'package:chessboard_pgn/src/session.dart';
import 'package:chessboard_pgn/src/settings.dart';
import 'package:chessboard_pgn/src/ui/pieces.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// What a scene builder receives; the same objects are in the `AppScope` above the scene.
class SceneEnv {
  SceneEnv(this.settings, this.session, this.catalog);

  final AppSettings settings;
  final Session session;
  final PieceSetCatalog catalog;
}

typedef SceneBuilder = Widget Function(SceneEnv env);
typedef SceneSetup = Future<void> Function(WidgetTester tester, SceneEnv env);

class Scene {
  const Scene(
    this.name,
    this.builder, {
    this.settings,
    this.setup,
    this.phoneSize = const Size(412, 915),
    this.desktopSize = const Size(1280, 800),
    this.textScale13 = false,
    this.phone = true,
    this.desktop = true,
    this.readImage,
    this.readRegion,
  });

  final String name;
  final SceneBuilder builder;
  final AppSettings Function()? settings;
  final SceneSetup? setup;
  final Size phoneSize, desktopSize;
  final bool textScale13, phone, desktop;

  /// Readers of the scene's [Session]; [fakeReadImage] and the real region reader by default.
  final ReadImageFn? readImage;
  final ReadRegionFn? readRegion;
}

final List<Scene> registeredScenes = [];

/// Registers a scene (see the header comment).
void registerScene(
  String name,
  SceneBuilder builder, {
  AppSettings Function()? settings,
  SceneSetup? setup,
  Size phoneSize = const Size(412, 915),
  Size desktopSize = const Size(1280, 800),
  bool textScale13 = false,
  bool phone = true,
  bool desktop = true,
  ReadImageFn? readImage,
  ReadRegionFn? readRegion,
}) {
  assert(
    !registeredScenes.any((s) => s.name == name),
    'scene $name is registered twice',
  );
  registeredScenes.add(
    Scene(
      name,
      builder,
      settings: settings,
      setup: setup,
      phoneSize: phoneSize,
      desktopSize: desktopSize,
      textScale13: textScale13,
      phone: phone,
      desktop: desktop,
      readImage: readImage,
      readRegion: readRegion,
    ),
  );
}

// ------------------------------------------------------------------------------------------------ fakes

/// Two boards as the reader would return them: the sample middlegame with squares f6 and c6 doubtful, and an
/// endgame with one doubtful square.
List<RecognizedBoard> fakeBoards() {
  final a = placementToGrid(
    'r1bq1rk1/pp2ppbp/2np1np1/8/3NP3/2N1BP2/PPPQ2PP/2KR1B1R',
  );
  final confA = List<double>.filled(64, 0.99)
    ..[21] = 0.5
    ..[18] = 0.7;
  final b = placementToGrid('8/5pk1/6p1/3R4/8/6P1/5PK1/3r4');
  final confB = List<double>.filled(64, 0.99)..[27] = 0.6;
  return [
    RecognizedBoard(const Box(0, 0, 100, 100), a, confA, a, false),
    RecognizedBoard(const Box(0, 120, 100, 220), b, confB, b, false),
  ];
}

/// A [Session] reader that "finds" [fakeBoards] without touching the model.
Future<List<RecognizedBoard>> fakeReadImage(
  Uint8List bytes, {
  BoardsFoundFn? onFound,
  BoardReadFn? onBoard,
}) async {
  final boards = fakeBoards();
  onFound?.call(boards.length, 100, 240);
  for (final (i, b) in boards.indexed) {
    onBoard?.call(i, b);
  }
  return boards;
}

// ------------------------------------------------------------------------------------------------ fonts

/// Loads the bundled fonts and Material Icons so text and icons render for real instead of as Ahem boxes.
Future<void> loadRealFonts() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  Future<void> family(String name, List<String> files) async {
    final loader = FontLoader(name);
    for (final f in files) {
      final bytes = File(f).readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }

  const dir = 'assets/fonts';
  await family('Barlow', [
    '$dir/Barlow-Regular.ttf',
    '$dir/Barlow-Medium.ttf',
    '$dir/Barlow-SemiBold.ttf',
    '$dir/Barlow-Bold.ttf',
  ]);
  await family('BarlowCondensed', [
    '$dir/BarlowCondensed-SemiBold.ttf',
    '$dir/BarlowCondensed-Bold.ttf',
  ]);
  await family('JetBrainsMono', [
    '$dir/JetBrainsMono-Regular.ttf',
    '$dir/JetBrainsMono-Medium.ttf',
  ]);
  await family('ChessFigures', ['$dir/ChessFigures.ttf']);
  await family('MaterialIcons', [_materialIconsPath()]);
}

String _materialIconsPath() {
  final roots = <String>[
    ?Platform.environment['FLUTTER_ROOT'],
    // `flutter` on the PATH: <root>/bin/flutter
    for (final p in (Platform.environment['PATH'] ?? '').split(':'))
      if (File('$p/flutter').existsSync())
        File('$p/flutter')
            .resolveSymbolicLinksSync()
            .replaceFirst(RegExp(r'/bin/flutter$'), ''),
  ];
  for (final root in roots) {
    final f = File(
      '$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
    );
    if (f.existsSync()) return f.path;
  }
  throw StateError(
    'MaterialIcons-Regular.otf not found under the Flutter SDK cache (tried $roots)',
  );
}

// ------------------------------------------------------------------------------------------------ render

enum Device { phone, desktop }

/// Renders [scene] in [brightness] on [device] and writes the PNG into [dir]. Returns the file name.
Future<String> renderScene(
  WidgetTester tester,
  Scene scene, {
  required Brightness brightness,
  required Device device,
  required String dir,
  required PieceSetCatalog catalog,
  double textScale = 1,
}) async {
  final phone = device == Device.phone;
  final logical = phone ? scene.phoneSize : scene.desktopSize;
  final dpr = phone ? 2.625 : 1.0;
  tester.view.physicalSize = logical * dpr;
  tester.view.devicePixelRatio = dpr;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
  });

  final settings = scene.settings?.call() ?? AppSettings();
  await settings.setThemeMode(
    brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
  );
  final session = Session(
    readImage: scene.readImage ?? fakeReadImage,
    readRegion: scene.readRegion,
  );
  final env = SceneEnv(settings, session, catalog);

  final key = GlobalKey();
  await tester.pumpWidget(
    RepaintBoundary(
      key: key,
      child: ChessPgnApp(
        settings: settings,
        session: session,
        catalog: catalog,
        home: Builder(builder: (_) => scene.builder(env)),
      ),
    ),
  );
  await tester.pump();
  await scene.setup?.call(tester, env);
  // let the theme animation, sheet and snackbar transitions finish (fixed time: some scenes keep animating)
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(milliseconds: 600));

  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: dpr);
    final data = await image.toByteData(format: ImageByteFormat.png);
    image.dispose();
    return data!.buffer.asUint8List();
  });

  final variant = phone ? (textScale == 1 ? 'phone' : 'phone-ts13') : 'desktop';
  final file =
      '${scene.name}__${brightness == Brightness.dark ? 'dark' : 'light'}__$variant.png';
  Directory(dir).createSync(recursive: true);
  File('$dir/$file').writeAsBytesSync(bytes!);
  return file;
}
