import 'package:chessboard_pgn/main.dart';
import 'package:chessboard_pgn/src/settings.dart';
import 'package:chessboard_pgn/src/ui/scope.dart';
import 'package:chessboard_pgn/src/ui/theme.dart';
import 'package:chessboard_pgn/src/ui/tokens.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('the app provides settings, session and catalogue and speaks Spanish', (tester) async {
    await tester.pumpWidget(const ChessPgnApp());
    final context = tester.element(find.byType(Scaffold).first);
    expect(AppScope.maybeOf(context), isNotNull);
    expect(AppScope.of(context).catalog.ids, contains('tipografico'));
    expect(MaterialLocalizations.of(context).backButtonTooltip, 'Atrás');
    expect(MaterialLocalizations.of(context).licensesPageTitle, 'Licencias');
    expect(Localizations.localeOf(context).languageCode, 'es');
    expect(find.text('Chess to PGN'), findsOneWidget);
    // the Ajustes action is in the app bar
    await tester.tap(find.byTooltip('Ajustes'));
    await tester.pumpAndSettle();
    expect(find.text('Apariencia'), findsOneWidget);
  });

  testWidgets('re-inking animates the theme (about 200 ms) through MaterialApp', (tester) async {
    final settings = AppSettings(themeMode: ThemeMode.light);
    await tester.pumpWidget(ChessPgnApp(settings: settings));
    Color bar() => Theme.of(tester.element(find.byType(Scaffold).first)).appBarTheme.backgroundColor!;
    final before = bar();
    await settings.setInkId('torneo');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final mid = bar();
    expect(mid, isNot(before));
    expect(mid, isNot(buildTheme(inkById('torneo'), Brightness.light).appBarTheme.backgroundColor), reason: 'mid-animation');
    await tester.pump(const Duration(milliseconds: 200));
    expect(bar(), buildTheme(inkById('torneo'), Brightness.light).appBarTheme.backgroundColor);
    expect(AppTheme.of(tester.element(find.byType(Scaffold).first)).ink.id, 'torneo');
  });

  testWidgets('with "remove animations" the new ink applies at once', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAllTestValues);
    final settings = AppSettings(themeMode: ThemeMode.light);
    await tester.pumpWidget(ChessPgnApp(settings: settings));
    await settings.setInkId('madera');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(
      Theme.of(tester.element(find.byType(Scaffold).first)).appBarTheme.backgroundColor,
      buildTheme(inkById('madera'), Brightness.light).appBarTheme.backgroundColor,
    );
  });
}
