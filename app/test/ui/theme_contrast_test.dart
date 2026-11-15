// Contrast is verified in code for both brightnesses (WCAG 2.x), the board squares are checked against the pieces
// drawn on them, and the shapes of the component themes are checked against the spec (6 dp, no capsules).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chessboard_pgn/src/settings.dart';
import 'package:chessboard_pgn/src/ui/board.dart';
import 'package:chessboard_pgn/src/ui/color_math.dart';
import 'package:chessboard_pgn/src/ui/plate.dart';
import 'package:chessboard_pgn/src/ui/theme.dart';
import 'package:chessboard_pgn/src/ui/tokens.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('Barlow really has tabular figures: 1111 and 8888 are equally wide only with them', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader('Barlow')..addFont(
          Future.value(
            ByteData.sublistView(
              File('assets/fonts/Barlow-Regular.ttf').readAsBytesSync(),
            ),
          ),
        ))
        .load();
    double width(String s, List<ui.FontFeature> f) => (TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontFamily: 'Barlow', fontSize: 20, fontFeatures: f),
      ),
      textDirection: TextDirection.ltr,
    )..layout()).width;
    expect(width('1111', const []), isNot(closeTo(width('8888', const []), 1)));
    expect(
      width('1111', tabularFigures),
      closeTo(width('8888', tabularFigures), 0.01),
    );
  });

  test('numerals and counters request tabular figures', () {
    final t = buildTheme(stones.first, Brightness.light);
    expect(t.extension<AppTheme>()!.numeral.fontFeatures, tabularFigures);
    expect(t.textTheme.labelSmall!.fontFeatures, tabularFigures);
    expect(t.textTheme.labelLarge!.fontFeatures, tabularFigures);
    expect(t.textTheme.bodyMedium!.tabular.fontFeatures, tabularFigures);
  });

  test('type: Barlow everywhere, Barlow Condensed for masthead, numerals and plates, Mono for data', () {
    final t = buildTheme(stones.first, Brightness.light);
    final app = t.extension<AppTheme>()!;
    final text = t.textTheme;
    for (final s in [
      text.displayLarge, text.displayMedium, text.displaySmall, //
      text.headlineLarge, text.headlineMedium, text.headlineSmall,
      text.titleLarge, text.titleMedium, text.titleSmall,
      text.bodyLarge, text.bodyMedium, text.bodySmall,
      text.labelLarge, text.labelMedium, text.labelSmall,
    ]) {
      expect(s!.fontFamily, 'Barlow');
    }
    expect(
      text.labelLarge!.fontWeight,
      FontWeight.w600,
      reason: 'button labels',
    );
    for (final s in [
      app.masthead,
      app.numeral,
      app.plateLabel,
      app.plateCaption,
    ]) {
      expect(s.fontFamily, 'BarlowCondensed');
    }
    expect(app.mono.fontFamily, 'JetBrainsMono');
    expect(t.appBarTheme.titleTextStyle!.fontFamily, 'BarlowCondensed');
  });

  test('the stone table matches the ids of the settings and the spec', () {
    expect([for (final s in stones) s.id], stoneIds);
    expect(stoneById('nope').id, defaultStoneId);
    expect(stones.first.id, 'serpentina');
    expect(stones.map((s) => s.name), [
      'Serpentina',
      'Pizarra',
      'Rojo Alicante',
      'Nogal',
      'Granito',
    ]);
    // spec values (docs/ux-spec.md); only alicante and nogal dark squares moved, to reach L* 55
    expect(stoneById('serpentina').lightSquare, const Color(0xFFE8E1CD));
    expect(stoneById('serpentina').darkSquare, const Color(0xFF76927F));
    expect(stoneById('pizarra').darkSquare, const Color(0xFF7D8590));
    expect(stoneById('alicante').lightSquare, const Color(0xFFEADFCC));
    expect(stoneById('nogal').lightSquare, const Color(0xFFEBD9B8));
    expect(stoneById('granito').darkSquare, const Color(0xFF8F918C));
  });

  for (final brightness in Brightness.values) {
    final label = brightness.name;
    group(label, () {
      final theme = buildTheme(stones.first, brightness);
      final s = theme.colorScheme;
      final app = theme.extension<AppTheme>()!;
      void atLeast(String what, Color fg, Color bg, double min) {
        expect(
          contrastRatio(fg, bg),
          greaterThanOrEqualTo(min),
          reason: '$label: $what ${contrastRatio(fg, bg).toStringAsFixed(2)}',
        );
      }

      test('the scheme is the palette of the spec', () {
        if (brightness == Brightness.light) {
          expect(s.primary, const Color(0xFF1F5C46));
          expect(s.onPrimary, const Color(0xFFF4F1E8));
          expect(s.surface, const Color(0xFFECE8DF));
          expect(s.surfaceContainerLow, const Color(0xFFE0DBCD));
          expect(s.onSurface, const Color(0xFF1D2520));
          expect(s.error, const Color(0xFFA3402A));
          expect(app.warningMark, const Color(0xFFD98E00));
        } else {
          expect(s.surface, const Color(0xFF0F1411));
          expect(s.surfaceContainerLow, const Color(0xFF181F1B));
          expect(s.onSurface, const Color(0xFFE4E8E0));
          expect(s.onSurfaceVariant, const Color(0xFFA9B3AA));
          expect(s.error, const Color(0xFFD9694C));
          expect(app.warningMark, const Color(0xFFFFB93D));
          expect(app.shell, const Color(0xFF143E30));
        }
        expect(app.lampGlow, brightness == Brightness.dark);
      });

      test('text pairs reach 4.5:1', () {
        atLeast('onPrimary/primary', s.onPrimary, s.primary, 4.5);
        atLeast(
          'onPrimaryContainer/primaryContainer',
          s.onPrimaryContainer,
          s.primaryContainer,
          4.5,
        );
        atLeast(
          'onSecondaryContainer/secondaryContainer',
          s.onSecondaryContainer,
          s.secondaryContainer,
          4.5,
        );
        atLeast(
          'onTertiaryContainer/tertiaryContainer',
          s.onTertiaryContainer,
          s.tertiaryContainer,
          4.5,
        );
        atLeast('onError/error', s.onError, s.error, 4.5);
        atLeast(
          'onErrorContainer/errorContainer',
          s.onErrorContainer,
          s.errorContainer,
          4.5,
        );
        atLeast('onSurface/surface', s.onSurface, s.surface, 4.5);
        atLeast('onSurfaceVariant/surface', s.onSurfaceVariant, s.surface, 4.5);
        for (final (name, bg) in [
          ('surfaceContainerLow', s.surfaceContainerLow),
          ('surfaceContainer', s.surfaceContainer),
          ('surfaceContainerHigh', s.surfaceContainerHigh),
          ('surfaceContainerHighest', s.surfaceContainerHighest),
        ]) {
          atLeast('onSurface/$name', s.onSurface, bg, 4.5);
          atLeast('onSurfaceVariant/$name', s.onSurfaceVariant, bg, 4.5);
          atLeast('primary/$name', s.primary, bg, 4.5);
        }
        atLeast('primary/surface', s.primary, s.surface, 4.5);
        atLeast('error/surface', s.error, s.surface, 4.5);
        atLeast(
          'error/surfaceContainerLow (status of a block)',
          s.error,
          s.surfaceContainerLow,
          4.5,
        );
        atLeast(
          'onSurface/surfaceContainerHigh (no-boards strip)',
          s.onSurface,
          s.surfaceContainerHigh,
          4.5,
        );
        atLeast(
          'onInverseSurface/inverseSurface',
          s.onInverseSurface,
          s.inverseSurface,
          4.5,
        );
        atLeast(
          'inversePrimary/inverseSurface (snackbar action)',
          s.inversePrimary,
          s.inverseSurface,
          4.5,
        );
      });

      test('warning pairs reach 4.5:1', () {
        atLeast('onWarning/warning', app.onWarning, app.warning, 4.5);
        atLeast(
          'onWarningContainer/warningContainer',
          app.onWarningContainer,
          app.warningContainer,
          4.5,
        );
        atLeast('warning/surface', app.warning, s.surface, 4.5);
        atLeast(
          'warning/surfaceContainerLow',
          app.warning,
          s.surfaceContainerLow,
          4.5,
        );
        atLeast(
          'warning/surfaceContainer',
          app.warning,
          s.surfaceContainer,
          4.5,
        );
      });

      test('plate pairs: off-white text and rule on enamel reach 4.5:1', () {
        atLeast('onPlate/plate', app.onPlate, app.plate, 4.5);
        atLeast('onShell/shell', app.onShell, app.shell, 4.5);
        // the enamel stands out from the page (the rule completes it)
        atLeast('plate/surface', app.plate, s.surface, 2.5);
        atLeast(
          'plate/surfaceContainerLow',
          app.plate,
          s.surfaceContainerLow,
          2.5,
        );
        final fab = theme.floatingActionButtonTheme;
        expect(fab.backgroundColor, app.plate);
        expect(fab.foregroundColor, app.onPlate);
      });

      test('app bar pairs reach 4.5:1', () {
        final bar = theme.appBarTheme;
        atLeast(
          'appbar fg/bg',
          bar.foregroundColor!,
          bar.backgroundColor!,
          4.5,
        );
        expect(bar.backgroundColor, app.shell);
        expect(
          bar.backgroundColor,
          brightness == Brightness.light ? s.primary : s.primaryContainer,
        );
      });

      test('chip labels, check marks and tonal button labels reach 4.5:1', () {
        final chip = theme.chipTheme;
        const selected = {WidgetState.selected};
        const plain = <WidgetState>{};
        Color labelOf(Set<WidgetState> st) =>
            WidgetStateProperty.resolveAs<Color?>(chip.labelStyle!.color, st)!;
        final selectedFill = chip.color!.resolve(selected)!;
        atLeast(
          'selected chip label/fill',
          labelOf(selected),
          selectedFill,
          4.5,
        );
        atLeast(
          'selected chip check/fill',
          chip.checkmarkColor!,
          selectedFill,
          4.5,
        );
        // an unselected chip has no fill: it sits on whatever surface holds it
        expect(chip.color!.resolve(plain), isNull);
        for (final (name, bg) in [
          ('surface', s.surface),
          ('surfaceContainerLow', s.surfaceContainerLow),
          ('surfaceContainer', s.surfaceContainer),
        ]) {
          atLeast('unselected chip label/$name', labelOf(plain), bg, 4.5);
        }
        atLeast(
          'chip rule/surfaceContainerLow',
          chip.side!.color,
          s.surfaceContainerLow,
          3,
        );
        // FilledButton.tonal and the selected segment: onSecondaryContainer on secondaryContainer
        atLeast(
          'tonal label/fill',
          s.onSecondaryContainer,
          s.secondaryContainer,
          7,
        );
      });

      test('graphic elements reach 3:1', () {
        atLeast('outline/surface', s.outline, s.surface, 3);
        atLeast(
          'outline/surfaceContainerLow',
          s.outline,
          s.surfaceContainerLow,
          3,
        );
        atLeast('amber text colour/surface', app.warning, s.surface, 4.5);
      });

      test('the doubtful marker reads through its dark hairline', () {
        atLeast('hairline/mark', BoardMarks.doubtEdge, app.warningMark, 3);
      });

      test('shapes: 6 dp controls, 10 dp containers, no capsule anywhere', () {
        RoundedRectangleBorder rr(OutlinedBorder? b) {
          expect(b, isA<RoundedRectangleBorder>());
          return b! as RoundedRectangleBorder;
        }

        double radius(ShapeBorder? b) =>
            ((b! as RoundedRectangleBorder).borderRadius as BorderRadius)
                .topLeft
                .x;
        ShapeBorder? styleShape(ButtonStyle? st) =>
            st?.shape?.resolve(const {});
        for (final st in [
          theme.filledButtonTheme.style,
          theme.elevatedButtonTheme.style,
          theme.outlinedButtonTheme.style,
          theme.textButtonTheme.style,
          theme.iconButtonTheme.style,
          theme.segmentedButtonTheme.style,
        ]) {
          expect(radius(rr(styleShape(st) as OutlinedBorder?)), Corner.control);
        }
        expect(radius(theme.chipTheme.shape), Corner.control);
        expect(radius(theme.snackBarTheme.shape), Corner.control);
        expect(radius(theme.popupMenuTheme.shape), Corner.control);
        expect(
          ((theme.tooltipTheme.decoration! as BoxDecoration).borderRadius!
                  as BorderRadius)
              .topLeft
              .x,
          Corner.control,
        );
        expect(radius(theme.dialogTheme.shape), Corner.container);
        final sheet = theme.bottomSheetTheme.shape! as RoundedRectangleBorder;
        expect(
          (sheet.borderRadius as BorderRadius).topLeft.x,
          Corner.container,
        );
        expect((sheet.borderRadius as BorderRadius).bottomLeft.x, 0);
        final input = theme.inputDecorationTheme.border! as OutlineInputBorder;
        expect(input.borderRadius.topLeft.x, Corner.control);
        final fab = theme.floatingActionButtonTheme.shape;
        expect(fab, isA<PlateBorder>());
        expect((fab! as PlateBorder).radius, 6);
        expect(Corner.control, 6);
        expect(Corner.container, 10);
        // elevation 0 everywhere
        expect(theme.floatingActionButtonTheme.elevation, 0);
        expect(theme.appBarTheme.elevation, 0);
        expect(theme.popupMenuTheme.elevation, 0);
      });

      test('the selected segment is a filled stone with strong text', () {
        final st = theme.segmentedButtonTheme.style!;
        const on = {WidgetState.selected};
        expect(st.backgroundColor!.resolve(on), s.secondaryContainer);
        expect(st.foregroundColor!.resolve(on), s.onSecondaryContainer);
        expect(st.textStyle!.resolve(on)!.fontWeight, FontWeight.w700);
        expect(st.side!.resolve(const {})!.width, 1);
        expect(st.side!.resolve(const {})!.color, s.outline);
      });
    });
  }

  for (final stone in stones) {
    group('${stone.id} board', () {
      test('the dark square is a mid tone', () {
        final l = lightnessOf(stone.darkSquare);
        expect(l, inInclusiveRange(55, 65));
        expect(lightnessOf(stone.lightSquare), greaterThan(85));
      });

      test('pieces keep 3:1 against the squares', () {
        const white = BoardMarks.pieceWhite, black = BoardMarks.pieceBlack;
        // A white piece has a white body (3:1 against the dark square) and a black outline (3:1 against both).
        expect(
          contrastRatio(white, stone.darkSquare),
          greaterThanOrEqualTo(3.0),
          reason: 'white body on dark',
        );
        expect(
          contrastRatio(black, stone.darkSquare),
          greaterThanOrEqualTo(3.0),
          reason: 'black on dark',
        );
        expect(
          contrastRatio(black, stone.lightSquare),
          greaterThanOrEqualTo(3.0),
          reason: 'black on light',
        );
        // The white body cannot reach 3:1 on a light square (it would not be light): its black outline does.
        expect(contrastRatio(white, stone.lightSquare), lessThan(3.0));
        // the two squares tell apart
        expect(
          contrastRatio(stone.lightSquare, stone.darkSquare),
          greaterThanOrEqualTo(2.2),
        );
      });

      test('the hatching of the printed style is black on white paper', () {
        final app = buildTheme(stone, Brightness.light).extension<AppTheme>()!;
        expect(app.boardHatch, BoardMarks.pieceBlack);
        expect(app.boardPaper, BoardMarks.paper);
      });

      test('the selection ring keeps 3:1 against both squares', () {
        final tone = selectionTone(stone);
        expect(contrastRatio(tone, stone.lightSquare), greaterThanOrEqualTo(3));
        expect(contrastRatio(tone, stone.darkSquare), greaterThanOrEqualTo(3));
      });

      test('the doubtful hairline reads on both squares, in both themes', () {
        expect(
          contrastRatio(BoardMarks.doubtEdge, stone.lightSquare),
          greaterThanOrEqualTo(3),
        );
        expect(
          contrastRatio(BoardMarks.doubtEdge, stone.darkSquare),
          greaterThanOrEqualTo(3),
        );
      });
    });
  }

  // What really gets painted, not only what the theme says.
  for (final brightness in Brightness.values) {
    testWidgets(
      'rendered chips and tonal button are legible (${brightness.name})',
      (tester) async {
        final theme = buildTheme(defaultStone, brightness);
        final s = theme.colorScheme;
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: Column(
                children: [
                  FilterChip(
                    label: const Text('Sí'),
                    selected: true,
                    onSelected: (_) {},
                  ),
                  FilterChip(
                    label: const Text('No'),
                    selected: false,
                    onSelected: (_) {},
                  ),
                  FilledButton.tonal(
                    onPressed: () {},
                    child: const Text('Tonal'),
                  ),
                ],
              ),
            ),
          ),
        );
        // the label is painted with the ambient text style of its widget
        Color colorOf(String text) =>
            DefaultTextStyle.of(tester.element(find.text(text))).style.color!;
        expect(
          contrastRatio(colorOf('Sí'), s.secondaryContainer),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrastRatio(colorOf('No'), s.surface),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrastRatio(colorOf('Tonal'), s.secondaryContainer),
          greaterThanOrEqualTo(4.5),
        );
        // none of them is a capsule: 6 dp corners
        final tonal = tester.widget<Material>(
          find.descendant(
            of: find.byType(FilledButton),
            matching: find.byType(Material),
          ),
        );
        expect(
          (tonal.shape! as RoundedRectangleBorder).borderRadius,
          BorderRadius.circular(Corner.control),
        );
      },
    );
  }
}
