// Scenes of the manual crop screen for the screenshot harness (harness.dart). Registered by
// registerCropScenes(); run with crop_screenshots_test.dart.
import 'dart:io';
import 'dart:typed_data';

import 'package:chessboard_pgn/src/crop_page.dart';
import 'package:chessboard_pgn/src/locate.dart';
import 'package:chessboard_pgn/src/settings.dart';
import 'package:chessboard_pgn/src/ui/crop_canvas.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';

import 'harness.dart';

Uint8List? _tall;

/// A realistic 1080 x 2400 phone screenshot: the three-board test page set on a white e-book page.
Uint8List tallScreenshot() {
  final cached = _tall;
  if (cached != null) return cached;
  final page = img.decodePng(
    File('test/fixtures/page_three_boards.png').readAsBytesSync(),
  )!;
  final canvas = img.Image(width: 1080, height: 2400)
    ..clear(img.ColorRgb8(255, 255, 255));
  img.compositeImage(canvas, page, dstX: 0, dstY: 450);
  return _tall = Uint8List.fromList(img.encodePng(canvas));
}

/// Board 2 of the fixture (light, printed style) in the tall screenshot, with a loose 5 % margin.
const Box board2 = Box(570, 630, 1010, 1070);

Future<void> _ready(WidgetTester tester) async {
  for (var i = 0; i < 60 && find.byType(CropCanvas).evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
  // Focus ring only where a keyboard is in play (desktop), as on a real device.
  final desktop =
      tester.view.physicalSize.width / tester.view.devicePixelRatio >= 600;
  FocusManager.instance.highlightStrategy = desktop
      ? FocusHighlightStrategy.alwaysTraditional
      : FocusHighlightStrategy.alwaysTouch;
  addTearDown(
    () => FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.automatic,
  );
  await tester.pump();
}

void registerCropScenes() {
  registerScene(
    'crop_initial',
    (env) => CropPage(imageBytes: tallScreenshot()),
    setup: (tester, env) => _ready(tester),
    textScale13: true,
  );
  registerScene(
    'crop_zoomed',
    (env) => CropPage(imageBytes: tallScreenshot(), initial: board2),
    settings: () => AppSettings(stoneId: 'pizarra'),
    setup: (tester, env) => _ready(tester),
    textScale13: true,
  );
  registerScene(
    'crop_loupe',
    (env) => CropPage(imageBytes: tallScreenshot(), initial: board2),
    settings: () => AppSettings(stoneId: 'alicante'),
    desktop: false,
    setup: (tester, env) async {
      await _ready(tester);
      // Hold a finger on the top-left corner, moved a little: the loupe stays up for the capture.
      final canvas = tester.getTopLeft(
        find.byKey(const ValueKey('crop-canvas')),
      );
      final c = tester.widget<CropCanvas>(find.byType(CropCanvas)).controller;
      final corner = canvas + c.toScreen(c.rect.topLeft);
      final g = await tester.startGesture(corner);
      await g.moveBy(
        const Offset(10, 10),
        timeStamp: const Duration(seconds: 1),
      );
      await g.moveBy(
        const Offset(24, 24),
        timeStamp: const Duration(seconds: 1, milliseconds: 50),
      );
    },
  );
}
