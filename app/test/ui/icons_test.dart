// The icon dictionary of docs/icons.md, and the rule that no screen uses Material's own icons.
import 'dart:convert';
import 'dart:io';

import 'package:chessboard_pgn/src/ui/icons.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets(
    'AppIcon draws a Hugeicon in the colour and size of the icon theme, with one stroke width',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: IconTheme(
              data: IconThemeData(size: 20, color: Color(0xFF123456)),
              child: AppIcon(AppIcons.crop),
            ),
          ),
        ),
      );
      final huge = tester.widget<HugeIcon>(find.byType(HugeIcon));
      expect(huge.icon, HugeIcons.strokeRoundedCrop);
      expect(huge.size, 20);
      expect(huge.strokeWidth, appIconStroke);
      expect(appIconStroke, 1.8);
      expect(tester.getSize(find.byType(AppIcon)), const Size(20, 20));
      // an explicit size and colour win
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: AppIcon(AppIcons.check, size: 16, color: Color(0xFFFF0000)),
          ),
        ),
      );
      expect(tester.widget<HugeIcon>(find.byType(HugeIcon)).size, 16);
      expect(
        tester.widget<HugeIcon>(find.byType(HugeIcon)).color,
        const Color(0xFFFF0000),
      );
    },
  );

  testWidgets('icons are hidden from semantics unless given a label', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            AppIcon(AppIcons.warning),
            AppIcon(AppIcons.error, semanticLabel: 'Error'),
          ],
        ),
      ),
    );
    expect(find.bySemanticsLabel('Error'), findsOneWidget);
    handle.dispose();
  });

  test('every row of docs/icons.md is in AppIcons', () {
    expect(AppIcons.settings, HugeIcons.strokeRoundedSettings02);
    expect(AppIcons.addCapture, HugeIcons.strokeRoundedImageAdd02);
    expect(AppIcons.crop, HugeIcons.strokeRoundedCrop);
    expect(AppIcons.delete, HugeIcons.strokeRoundedDelete02);
    expect(AppIcons.deleteAll, HugeIcons.strokeRoundedDelete04);
    expect(AppIcons.share, HugeIcons.strokeRoundedShare08);
    expect(AppIcons.copy, HugeIcons.strokeRoundedCopy01);
    expect(AppIcons.save, HugeIcons.strokeRoundedDownload04);
    expect(AppIcons.openExternal, HugeIcons.strokeRoundedLinkSquare02);
    expect(AppIcons.flip, HugeIcons.strokeRoundedArrowUpDown);
    expect(AppIcons.warning, HugeIcons.strokeRoundedAlert02);
    expect(AppIcons.error, HugeIcons.strokeRoundedAlertCircle);
    expect(AppIcons.lock, HugeIcons.strokeRoundedSquareLock02);
    expect(AppIcons.go, HugeIcons.strokeRoundedArrowRight01);
    expect(AppIcons.close, HugeIcons.strokeRoundedCancel01);
    expect(AppIcons.retry, HugeIcons.strokeRoundedRefresh);
    expect(AppIcons.undo, HugeIcons.strokeRoundedUndo02);
    expect(AppIcons.zoomIn, HugeIcons.strokeRoundedZoomInArea);
    expect(AppIcons.zoomOut, HugeIcons.strokeRoundedZoomOutArea);
    expect(AppIcons.fitAll, HugeIcons.strokeRoundedFullScreen);
    expect(AppIcons.check, HugeIcons.strokeRoundedTick02);
    expect(AppIcons.info, HugeIcons.strokeRoundedInformationCircle);
    expect(AppIcons.privacy, HugeIcons.strokeRoundedSquareLock02);
    expect(AppIcons.licenses, HugeIcons.strokeRoundedLicense);
    expect(AppIcons.noBoard, HugeIcons.strokeRoundedSearch01);
    expect(AppIcons.back, HugeIcons.strokeRoundedArrowLeft01);
  });

  test('the Hugeicons licence ships with the package, which Flutter collects into the app licences', () {
    // `flutter build` gathers the LICENSE of every pub dependency (the licence page lists them); the
    // LicenseRegistry is empty in tests, so check the source of that list: the package and its MIT text.
    final config = jsonDecode(
      File('.dart_tool/package_config.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final pkg = (config['packages'] as List)
        .cast<Map<String, dynamic>>()
        .firstWhere((p) => p['name'] == 'hugeicons');
    final root = Uri.parse(pkg['rootUri'] as String);
    final dir = root.isAbsolute
        ? root.toFilePath()
        : File('.dart_tool/package_config.json').parent.uri
              .resolveUri(root)
              .toFilePath();
    expect(File('$dir/LICENSE').readAsStringSync(), contains('MIT License'));
    expect(File('pubspec.yaml').readAsStringSync(), contains('hugeicons:'));
  });

  test('no file under lib/ uses Material icons (Icons.*, Icon(...)): the app draws with AppIcon', () {
    final offenders = <String>[];
    final pattern = RegExp(r'\bIcons\.[a-z_]+|[^A-Za-z]Icon\(');
    for (final f
        in Directory('lib')
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final code = lines[i].split('//').first;
        if (pattern.hasMatch(code)) {
          offenders.add('${f.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
