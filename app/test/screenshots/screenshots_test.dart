// Renders every registered scene to PNG. Skipped unless SCREENSHOT_DIR is set; see harness.dart.
import 'dart:io';

import 'package:chessboard_pgn/src/ui/pieces.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show Brightness;

import 'harness.dart';
import 'scenes.dart';

void main() {
  final dir = Platform.environment['SCREENSHOT_DIR'];
  final enabled = dir != null && dir.isNotEmpty;
  TestWidgetsFlutterBinding.ensureInitialized();
  registerAllScenes();

  late PieceSetCatalog catalog;
  setUpAll(() async {
    if (!enabled) return;
    await loadRealFonts();
    catalog = await PieceSetCatalog.load();
    await catalog.ensureAllLoaded();
  });

  for (final scene in registeredScenes) {
    for (final brightness in Brightness.values) {
      for (final device in Device.values) {
        if (device == Device.phone ? !scene.phone : !scene.desktop) continue;
        final scales = [
          1.0,
          if (device == Device.phone && scene.textScale13) 1.3,
        ];
        for (final scale in scales) {
          final label =
              '${scene.name} ${brightness.name} ${device.name}${scale == 1 ? '' : ' x$scale'}';
          testWidgets(label, skip: !enabled, (tester) async {
            final file = await renderScene(
              tester,
              scene,
              brightness: brightness,
              device: device,
              dir: dir!,
              catalog: catalog,
              textScale: scale,
            );
            // ignore: avoid_print
            print('wrote $dir/$file');
          });
        }
      }
    }
  }
}
