// Contrast is verified in code for every ink in both brightnesses (WCAG 2.x), and the board squares are
// checked against the pieces drawn on them.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chessboard_pgn/src/settings.dart';
import 'package:chessboard_pgn/src/ui/color_math.dart';
import 'package:chessboard_pgn/src/ui/theme.dart';
import 'package:chessboard_pgn/src/ui/tokens.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  test('Archivo really has tabular figures: 1111 and 8888 are equally wide only with them', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader('Archivo')..addFont(
          Future.value(
            ByteData.sublistView(
              File('assets/fonts/Archivo-Regular.ttf').readAsBytesSync(),
            ),
          ),
        ))
        .load();
    double width(String s, List<ui.FontFeature> f) => (TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(fontFamily: 'Archivo', fontSize: 20, fontFeatures: f),
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
    final t = buildTheme(inks.first, Brightness.light);
    expect(t.extension<AppTheme>()!.numeral.fontFeatures, tabularFigures);
    expect(t.textTheme.labelSmall!.fontFeatures, tabularFigures);
    expect(t.textTheme.labelLarge!.fontFeatures, tabularFigures);
    expect(t.textTheme.bodyMedium!.tabular.fontFeatures, tabularFigures);
  });

  test('the ink table matches the ids of the settings and the spec', () {
    expect([for (final i in inks) i.id], inkIds);
    expect(inkById('nope').id, defaultInkId);
    expect(inks.first.seed, const Color(0xFF1F4E9A));
    expect(inks.map((i) => i.name), [
      'Azul cobalto',
      'Verde torneo',
      'Granate',
      'Madera',
      'Ciruela',
      'Grafito',
    ]);
  });

  for (final ink in inks) {
    for (final brightness in Brightness.values) {
      final label = '${ink.id} ${brightness.name}';
      group(label, () {
        final theme = buildTheme(ink, brightness);
        final s = theme.colorScheme;
        final app = theme.extension<AppTheme>()!;
        void atLeast(String what, Color fg, Color bg, double min) {
          expect(
            contrastRatio(fg, bg),
            greaterThanOrEqualTo(min),
            reason: '$label: $what ${contrastRatio(fg, bg).toStringAsFixed(2)}',
          );
        }

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
          atLeast(
            'onSurfaceVariant/surface',
            s.onSurfaceVariant,
            s.surface,
            4.5,
          );
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
            'onErrorContainer/errorContainer (failure strip)',
            s.onErrorContainer,
            s.errorContainer,
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
        });

        test('app bar pairs reach 4.5:1', () {
          final bar = theme.appBarTheme;
          atLeast(
            'appbar fg/bg',
            bar.foregroundColor!,
            bar.backgroundColor!,
            4.5,
          );
          expect(
            bar.backgroundColor,
            brightness == Brightness.light ? s.primary : s.primaryContainer,
          );
        });

        test(
          'chip labels, check marks and tonal button labels reach 4.5:1',
          () {
            final chip = theme.chipTheme;
            const selected = {WidgetState.selected};
            const plain = <WidgetState>{};
            Color labelOf(Set<WidgetState> st) =>
                WidgetStateProperty.resolveAs<Color?>(
                  chip.labelStyle!.color,
                  st,
                )!;
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
              'unselected chip rule/surfaceContainerLow',
              WidgetStateProperty.resolveAs<BorderSide?>(
                chip.side,
                plain,
              )!.color,
              s.surfaceContainerLow,
              3,
            );
            // FilledButton.tonal: onSecondaryContainer on secondaryContainer
            atLeast(
              'tonal button label/fill',
              s.onSecondaryContainer,
              s.secondaryContainer,
              7,
            );
          },
        );

        test('graphic elements reach 3:1', () {
          atLeast('outline/surface', s.outline, s.surface, 3);
          atLeast(
            'outline/surfaceContainerLow',
            s.outline,
            s.surfaceContainerLow,
            3,
          );
        });
      });
    }

    group('${ink.id} board', () {
      test('the dark square is a mid tone', () {
        final l = lightnessOf(ink.darkSquare);
        expect(l, inInclusiveRange(55, 68));
        expect(lightnessOf(ink.lightSquare), greaterThan(85));
      });

      test('pieces keep 3:1 against the squares', () {
        const white = BoardMarks.pieceWhite, black = BoardMarks.pieceBlack;
        // A white piece has a white body (3:1 against the dark square) and a black outline (3:1 against both).
        expect(
          contrastRatio(white, ink.darkSquare),
          greaterThanOrEqualTo(3.0),
          reason: 'white body on dark',
        );
        expect(
          contrastRatio(black, ink.darkSquare),
          greaterThanOrEqualTo(3.0),
          reason: 'black on dark',
        );
        expect(
          contrastRatio(black, ink.lightSquare),
          greaterThanOrEqualTo(3.0),
          reason: 'black on light',
        );
        // The white body cannot reach 3:1 on a light square (it would not be light): its black outline does.
        expect(contrastRatio(white, ink.lightSquare), lessThan(3.0));
        // the two squares tell apart
        expect(
          contrastRatio(ink.lightSquare, ink.darkSquare),
          greaterThanOrEqualTo(2.2),
        );
      });

      test('the hatching ink is dark enough to carry the printed style', () {
        expect(
          contrastRatio(ink.seed, BoardMarks.paper),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrastRatio(BoardMarks.pieceBlack, ink.seed),
          greaterThanOrEqualTo(1.5),
        );
      });

      test(
        'the doubtful marker reads on both squares through its dark edge',
        () {
          expect(
            contrastRatio(BoardMarks.doubtEdge, ink.lightSquare),
            greaterThanOrEqualTo(3),
          );
          expect(
            contrastRatio(BoardMarks.doubtEdge, ink.darkSquare),
            greaterThanOrEqualTo(3),
          );
          expect(
            contrastRatio(BoardMarks.doubtEdge, BoardMarks.doubt),
            greaterThanOrEqualTo(3),
          );
        },
      );
    });
  }

  // What really gets painted, not only what the theme says.
  for (final brightness in Brightness.values) {
    testWidgets(
      'rendered chips and tonal button are legible (${brightness.name})',
      (tester) async {
        final theme = buildTheme(defaultInk, brightness);
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
      },
    );
  }
}
