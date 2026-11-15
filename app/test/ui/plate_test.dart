// The enamel plate: sizes, semantics and the inner rule, without goldens.
import 'dart:ui' as ui;

import 'package:chessboard_pgn/src/ui/plate.dart';
import 'package:chessboard_pgn/src/ui/theme.dart';
import 'package:chessboard_pgn/src/ui/tokens.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

final _key = GlobalKey();

Widget _host(Widget child, {Brightness b = Brightness.light}) => MaterialApp(
  theme: buildTheme(defaultStone, b),
  home: Scaffold(
    body: Center(
      child: RepaintBoundary(key: _key, child: child),
    ),
  ),
);

Future<(ByteData, int, int)> _pixels(WidgetTester tester) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_key));
  late ByteData data;
  late int w, h;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    w = image.width;
    h = image.height;
    data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  });
  return (data, w, h);
}

Color _px((ByteData, int, int) p, int x, int y) {
  final i = 4 * (y * p.$2 + x);
  return Color.fromARGB(
    255,
    p.$1.getUint8(i),
    p.$1.getUint8(i + 1),
    p.$1.getUint8(i + 2),
  );
}

void main() {
  testWidgets(
    'the numeral plate: at least 62 x 48, "DIAGRAMA" over the number, reads "Diagrama 2"',
    (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(_host(const EnamelPlate.numeral(2)));
      final size = tester.getSize(find.byType(EnamelPlate));
      expect(size.width, greaterThanOrEqualTo(62));
      expect(size.height, greaterThanOrEqualTo(48));
      expect(size.height, lessThan(60));
      expect(find.text('DIAGRAMA'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.bySemanticsLabel('Diagrama 2'), findsOneWidget);
      // the caption is above the numeral
      expect(
        tester.getBottomLeft(find.text('DIAGRAMA')).dy,
        lessThanOrEqualTo(tester.getTopLeft(find.text('2')).dy + 2),
      );
      // the number grows the plate, never overflows it
      await tester.pumpWidget(_host(const EnamelPlate.numeral(128)));
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel('Diagrama 128'), findsOneWidget);
      handle.dispose();
    },
  );

  testWidgets('the label plate is small and reads its text in sentence case', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(_host(const EnamelPlate.label('CAPTURA 1')));
    final size = tester.getSize(find.byType(EnamelPlate));
    expect(size.height, inInclusiveRange(30, 36));
    expect(
      size.width,
      lessThan(220),
      reason: 'the test font is as wide as Ahem',
    );
    expect(find.bySemanticsLabel('Captura 1'), findsOneWidget);
    await tester.pumpWidget(
      _host(
        const EnamelPlate.label('CAPTURA 1', semanticLabel: 'Primera captura'),
      ),
    );
    expect(find.bySemanticsLabel('Primera captura'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('type: Barlow Condensed in the off-white of the plate', (
    tester,
  ) async {
    await tester.pumpWidget(_host(const EnamelPlate.numeral(7)));
    final app = AppTheme.fallback;
    final numeral = tester.widget<Text>(find.text('7'));
    expect(numeral.style!.fontFamily, 'BarlowCondensed');
    expect(numeral.style!.color, app.onPlate);
    expect(numeral.style!.fontFeatures, tabularFigures);
    expect(
      tester.widget<Text>(find.text('DIAGRAMA')).style!.fontFamily,
      'BarlowCondensed',
    );
  });

  for (final b in Brightness.values) {
    testWidgets(
      'the inner rule is painted 3 dp inside the edge, 1.5 dp thick (${b.name})',
      (tester) async {
        await tester.pumpWidget(_host(const EnamelPlate.numeral(2), b: b));
        final app = buildTheme(defaultStone, b).extension<AppTheme>()!;
        final p = await _pixels(tester);
        final w = p.$2, h = p.$3;
        // plate edge column: enamel (with its gloss), then the page; the rule is at 3..4.5 dp from the edge
        final y = h ~/ 2;
        Color at(int x) => _px(p, x, y);
        expect(
          contrastRatio01(at(1), app.plate),
          lessThan(0.08),
          reason: 'enamel between the edge and the rule',
        );
        expect(at(3), isNot(equals(at(1))), reason: 'the rule starts at 3 dp');
        final rule = at(3);
        expect((rule.r - app.onPlate.r).abs(), lessThan(0.05));
        expect((rule.g - app.onPlate.g).abs(), lessThan(0.05));
        expect(
          at(5).r,
          lessThan(rule.r),
          reason: 'enamel again inside the rule',
        );
        // the same on the top edge, over the middle of the plate
        final top = _px(p, w ~/ 2, 3);
        expect((top.r - app.onPlate.r).abs(), lessThan(0.05));
      },
    );
  }

  test('PlateBorder: 6 dp radius, rule inset 3 dp, outer path is the rounded rectangle', () {
    const border = PlateBorder(ruleColor: Color(0xFFFFFFFF));
    expect(border.radius, 6);
    expect(border.inset, 3);
    expect(border.ruleWidth, 1.5);
    const rect = Rect.fromLTWH(0, 0, 100, 48);
    final outer = border.getOuterPath(rect);
    expect(outer.getBounds(), rect);
    expect(
      outer.contains(const Offset(0.2, 0.2)),
      isFalse,
      reason: 'corner is rounded',
    );
    expect(outer.contains(const Offset(50, 24)), isTrue);
    expect(border.ruleRect(rect).outerRect, rect.deflate(3.75));
    expect((border.scale(2) as PlateBorder).radius, 12);
    expect(
      border.copyWith(ruleColor: const Color(0xFF000000)).ruleColor,
      const Color(0xFF000000),
    );
    expect(border == const PlateBorder(ruleColor: Color(0xFFFFFFFF)), isTrue);
  });

  testWidgets('the FAB gets the plate shape and enamel from the theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(defaultStone, Brightness.light),
        home: Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {},
            label: const Text('Añadir captura'),
            icon: const SizedBox(width: 24, height: 24),
          ),
        ),
      ),
    );
    final fab = tester.widget<FloatingActionButton>(
      find.byType(FloatingActionButton),
    );
    final theme = Theme.of(tester.element(find.byType(FloatingActionButton)));
    expect(fab.shape, isNull, reason: 'comes from the theme');
    expect(theme.floatingActionButtonTheme.shape, isA<PlateBorder>());
    final material = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(FloatingActionButton),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(material.shape, isA<PlateBorder>());
    expect(material.color, AppTheme.fallback.plate);
    expect(material.elevation, 0);
    expect(
      tester.getSize(find.byType(FloatingActionButton)).height,
      greaterThanOrEqualTo(48),
    );
  });

  testWidgets(
    'plateButtonStyle makes a FilledButton a plate; disabled it is a plain 6 dp button',
    (tester) async {
      late BuildContext ctx;
      Widget button({required bool enabled}) => MaterialApp(
        theme: buildTheme(defaultStone, Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) {
              ctx = context;
              return FilledButton(
                style: plateButtonStyle(context),
                onPressed: enabled ? () {} : null,
                child: const Text('Elegir captura'),
              );
            },
          ),
        ),
      );
      await tester.pumpWidget(button(enabled: true));
      Material material() => tester.widget<Material>(
        find
            .descendant(
              of: find.byType(FilledButton),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material().shape, isA<PlateBorder>());
      expect(material().color, AppTheme.of(ctx).plate);
      expect(
        tester.getSize(find.byType(FilledButton)).height,
        greaterThanOrEqualTo(48),
      );
      final label = tester.widget<Text>(find.text('Elegir captura'));
      expect(
        DefaultTextStyle.of(tester.element(find.text('Elegir captura')))
            .style
            .color,
        AppTheme.of(ctx).onPlate,
      );
      expect(label.style, isNull);
      await tester.pumpWidget(button(enabled: false));
      await tester.pumpAndSettle();
      expect(material().shape, isA<RoundedRectangleBorder>());
    },
  );
}

/// Distance between two colours in 0..1 (largest channel difference).
double contrastRatio01(Color a, Color b) => [
  (a.r - b.r).abs(),
  (a.g - b.g).abs(),
  (a.b - b.b).abs(),
].reduce((x, y) => x > y ? x : y);
