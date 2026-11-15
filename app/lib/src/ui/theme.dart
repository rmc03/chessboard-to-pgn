// Theme of the app: one [ColorScheme] per (ink, brightness), the type scale, component themes and the
// [AppTheme] extension for what Material lacks (warning roles, board colours, the three named text styles).
//
// Screens get everything through the theme:
//   Theme.of(context).colorScheme          Material roles (primary, surfaceContainerLow, outline, error...)
//   Theme.of(context).textTheme            the type scale
//   context.app.warning / .masthead ...    [AppTheme], see below
import 'dart:ui' as ui show FontFeature;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'color_math.dart';
import 'tokens.dart';

/// Tabular (equal width) figures, for numerals and counters.
const List<ui.FontFeature> tabularFigures = [ui.FontFeature.tabularFigures()];

/// What Material has no role for.
@immutable
class AppTheme extends ThemeExtension<AppTheme> {
  const AppTheme({
    required this.ink,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.boardLight,
    required this.boardDark,
    required this.boardHatch,
    required this.boardPaper,
    required this.masthead,
    required this.numeral,
    required this.mono,
    required this.systemOverlay,
  });

  /// The ink this theme was built for.
  final SpotInk ink;

  /// Doubtful squares and other "look again" states. Amber harmonised with the ink: [warning] is the
  /// icon/text colour on a surface, [warningContainer] a band behind text coloured [onWarningContainer].
  /// [onWarning] is for text on a [warning] fill.
  final Color warning, onWarning, warningContainer, onWarningContainer;

  /// Flat board squares of the ink (the same in light and dark: the diagram is the constant).
  final Color boardLight, boardDark;

  /// Colour of the hatching of the printed style (the ink itself).
  final Color boardHatch;

  /// Light squares of the printed style.
  final Color boardPaper;

  /// Archivo Condensed 700 for the app bar title (the masthead).
  final TextStyle masthead;

  /// Archivo Condensed 700 with tabular figures, for the big diagram number. No colour: use the ink
  /// (`colorScheme.primary`).
  final TextStyle numeral;

  /// JetBrains Mono for FEN and PGN (data). No colour.
  final TextStyle mono;

  /// Style of the system bars (edge to edge, icon brightness that matches the app bar and the page).
  final SystemUiOverlayStyle systemOverlay;

  /// The extension of the nearest theme; the default ink in light mode when there is none (tests, previews
  /// outside the app).
  static AppTheme of(BuildContext context) =>
      Theme.of(context).extension<AppTheme>() ?? fallback;

  /// [AppTheme] of the default ink, light.
  static final AppTheme fallback = buildTheme(
    defaultInk,
    Brightness.light,
  ).extension<AppTheme>()!;

  @override
  AppTheme copyWith({
    SpotInk? ink,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? boardLight,
    Color? boardDark,
    Color? boardHatch,
    Color? boardPaper,
    TextStyle? masthead,
    TextStyle? numeral,
    TextStyle? mono,
    SystemUiOverlayStyle? systemOverlay,
  }) => AppTheme(
    ink: ink ?? this.ink,
    warning: warning ?? this.warning,
    onWarning: onWarning ?? this.onWarning,
    warningContainer: warningContainer ?? this.warningContainer,
    onWarningContainer: onWarningContainer ?? this.onWarningContainer,
    boardLight: boardLight ?? this.boardLight,
    boardDark: boardDark ?? this.boardDark,
    boardHatch: boardHatch ?? this.boardHatch,
    boardPaper: boardPaper ?? this.boardPaper,
    masthead: masthead ?? this.masthead,
    numeral: numeral ?? this.numeral,
    mono: mono ?? this.mono,
    systemOverlay: systemOverlay ?? this.systemOverlay,
  );

  @override
  AppTheme lerp(ThemeExtension<AppTheme>? other, double t) {
    if (other is! AppTheme) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return AppTheme(
      ink: t < 0.5 ? ink : other.ink,
      warning: mix(warning, other.warning),
      onWarning: mix(onWarning, other.onWarning),
      warningContainer: mix(warningContainer, other.warningContainer),
      onWarningContainer: mix(onWarningContainer, other.onWarningContainer),
      boardLight: mix(boardLight, other.boardLight),
      boardDark: mix(boardDark, other.boardDark),
      boardHatch: mix(boardHatch, other.boardHatch),
      boardPaper: mix(boardPaper, other.boardPaper),
      masthead: TextStyle.lerp(masthead, other.masthead, t)!,
      numeral: TextStyle.lerp(numeral, other.numeral, t)!,
      mono: TextStyle.lerp(mono, other.mono, t)!,
      systemOverlay: t < 0.5 ? systemOverlay : other.systemOverlay,
    );
  }
}

/// Shorthand: `context.app.warning`.
extension AppThemeContext on BuildContext {
  AppTheme get app => AppTheme.of(this);
}

/// `style.tabular` adds tabular figures to any text style.
extension TabularStyle on TextStyle {
  TextStyle get tabular => copyWith(fontFeatures: tabularFigures);
}

// ------------------------------------------------------------------------------------------ type scale

const String _ui = 'Archivo';
const String _condensed = 'ArchivoCondensed';
const String _monoFamily = 'JetBrainsMono';

/// Archivo on a ~1.2 scale (12, 14, 16, 20, 24, 29, 35, 42, 50, 60) mapped to the Material roles.
TextTheme _textTheme() => const TextTheme(
  displayLarge: TextStyle(fontFamily: _ui, fontSize: 60, height: 1.1, fontWeight: FontWeight.w600, letterSpacing: -0.6),
  displayMedium: TextStyle(fontFamily: _ui, fontSize: 50, height: 1.1, fontWeight: FontWeight.w600, letterSpacing: -0.5),
  displaySmall: TextStyle(fontFamily: _ui, fontSize: 42, height: 1.15, fontWeight: FontWeight.w600, letterSpacing: -0.4),
  headlineLarge: TextStyle(fontFamily: _ui, fontSize: 35, height: 1.2, fontWeight: FontWeight.w600, letterSpacing: -0.2),
  headlineMedium: TextStyle(fontFamily: _ui, fontSize: 29, height: 1.2, fontWeight: FontWeight.w600, letterSpacing: -0.1),
  headlineSmall: TextStyle(fontFamily: _ui, fontSize: 24, height: 1.25, fontWeight: FontWeight.w600),
  titleLarge: TextStyle(fontFamily: _ui, fontSize: 20, height: 1.3, fontWeight: FontWeight.w600),
  titleMedium: TextStyle(fontFamily: _ui, fontSize: 16, height: 1.35, fontWeight: FontWeight.w600, letterSpacing: 0.1),
  titleSmall: TextStyle(fontFamily: _ui, fontSize: 14, height: 1.35, fontWeight: FontWeight.w600, letterSpacing: 0.1),
  bodyLarge: TextStyle(fontFamily: _ui, fontSize: 16, height: 1.45, fontWeight: FontWeight.w400, letterSpacing: 0.1),
  bodyMedium: TextStyle(fontFamily: _ui, fontSize: 14, height: 1.45, fontWeight: FontWeight.w400, letterSpacing: 0.15),
  bodySmall: TextStyle(fontFamily: _ui, fontSize: 12, height: 1.4, fontWeight: FontWeight.w400, letterSpacing: 0.2),
  labelLarge: TextStyle(fontFamily: _ui, fontSize: 14, height: 1.3, fontWeight: FontWeight.w600, letterSpacing: 0.1, fontFeatures: tabularFigures),
  labelMedium: TextStyle(fontFamily: _ui, fontSize: 12, height: 1.3, fontWeight: FontWeight.w500, letterSpacing: 0.3, fontFeatures: tabularFigures),
  labelSmall: TextStyle(fontFamily: _ui, fontSize: 11, height: 1.3, fontWeight: FontWeight.w500, letterSpacing: 0.3, fontFeatures: tabularFigures),
);

const TextStyle _mastheadStyle = TextStyle(
  fontFamily: _condensed,
  fontSize: 24,
  height: 1.2,
  fontWeight: FontWeight.w700,
  letterSpacing: 0,
);

const TextStyle _numeralStyle = TextStyle(
  fontFamily: _condensed,
  fontSize: 50,
  height: 1.0,
  fontWeight: FontWeight.w700,
  letterSpacing: 0,
  fontFeatures: tabularFigures,
);

const TextStyle _monoStyle = TextStyle(
  fontFamily: _monoFamily,
  fontSize: 13,
  height: 1.5,
  fontWeight: FontWeight.w400,
  letterSpacing: 0,
);

// ----------------------------------------------------------------------------------------- warning roles

/// Moves [amber] up to [maxDegrees] along the hue circle toward [target] (the ink), so the warning amber
/// belongs to the same family as the ink without ceasing to be amber.
Color _harmonize(Color amber, Color target, {double maxDegrees = 8}) {
  final a = HSLColor.fromColor(amber);
  final t = HSLColor.fromColor(target);
  var diff = t.hue - a.hue;
  if (diff > 180) diff -= 360;
  if (diff < -180) diff += 360;
  final turn = diff.abs() < 1
      ? 0.0
      : (diff.abs() * 0.5).clamp(0.0, maxDegrees) * diff.sign;
  return a.withHue((a.hue + turn + 360) % 360).toColor();
}

ColorScheme _warningScheme(SpotInk ink, Brightness brightness) =>
    ColorScheme.fromSeed(
      seedColor: _harmonize(BoardMarks.warningSeed, ink.seed),
      brightness: brightness,
      // tonal spot: pale container in light, dark container in dark (fidelity would keep the vivid seed in both)
      dynamicSchemeVariant: DynamicSchemeVariant.tonalSpot,
    );

/// Moves [fg] toward black or white (whichever the background allows) until it reaches [min]:1 on [bg].
Color _strengthen(Color fg, Color bg, double min) {
  if (contrastRatio(fg, bg) >= min) return fg;
  final target = bg.computeLuminance() > 0.5
      ? BoardMarks.pieceBlack
      : BoardMarks.pieceWhite;
  for (var t = 0.05; t <= 1.0; t += 0.05) {
    final c = Color.lerp(fg, target, t)!;
    if (contrastRatio(c, bg) >= min) return c;
  }
  return target;
}

// ----------------------------------------------------------------------------------------------- theme

/// The theme of [ink] in [brightness].
ThemeData buildTheme(SpotInk ink, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final base = ColorScheme.fromSeed(
    seedColor: ink.seed,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );
  // Fidelity leaves the text on the secondary container at about 4.5:1 (selected segments, chips): lift it.
  final scheme = base.copyWith(
    onSecondaryContainer: _strengthen(
      base.onSecondaryContainer,
      base.secondaryContainer,
      9,
    ),
  );
  final amber = _warningScheme(ink, brightness);
  final text = _textTheme();

  final barBackground = dark ? scheme.primaryContainer : scheme.primary;
  final barForeground = dark ? scheme.onPrimaryContainer : scheme.onPrimary;
  final overlay = _overlayStyle(barBackground, scheme.surface);

  final app = AppTheme(
    ink: ink,
    warning: amber.primary,
    onWarning: amber.onPrimary,
    warningContainer: amber.primaryContainer,
    onWarningContainer: amber.onPrimaryContainer,
    boardLight: ink.lightSquare,
    boardDark: ink.darkSquare,
    boardHatch: ink.seed,
    boardPaper: BoardMarks.paper,
    masthead: _mastheadStyle,
    numeral: _numeralStyle,
    mono: _monoStyle,
    systemOverlay: overlay,
  );

  final controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(Corner.control),
  );
  final focusSide = BorderSide(color: scheme.onSurface, width: 2);
  // Keyboard focus must be visible (Windows): a 2 dp ring in the text colour on top of Material's state layer.
  WidgetStateProperty<BorderSide?> ring([BorderSide? base]) =>
      WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.focused) ? focusSide : base,
      );
  const minButton = WidgetStatePropertyAll(Size(64, minTarget));

  ButtonStyle buttonStyle({BorderSide? base}) => ButtonStyle(
    minimumSize: minButton,
    shape: WidgetStatePropertyAll(controlShape),
    textStyle: WidgetStatePropertyAll(text.labelLarge),
    side: ring(base),
    iconSize: const WidgetStatePropertyAll(20),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,
    textTheme: text,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    focusColor: scheme.onSurface.withValues(alpha: 0.16),
    hoverColor: scheme.onSurface.withValues(alpha: 0.08),
    dividerColor: scheme.outlineVariant,
    extensions: [app],
    appBarTheme: AppBarTheme(
      backgroundColor: barBackground,
      foregroundColor: barForeground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: _mastheadStyle.copyWith(color: barForeground),
      systemOverlayStyle: overlay,
      actionsPadding: const EdgeInsets.only(right: Space.xs),
    ),
    filledButtonTheme: FilledButtonThemeData(style: buttonStyle()),
    elevatedButtonTheme: ElevatedButtonThemeData(style: buttonStyle()),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: buttonStyle(base: BorderSide(color: scheme.outline)),
    ),
    textButtonTheme: TextButtonThemeData(style: buttonStyle()),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(minTarget, minTarget)),
        side: ring(),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      focusColor: scheme.onPrimary.withValues(alpha: 0.24),
      // Tonal, no shadow (the direction contract): the ink fill separates it from the page.
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Corner.fab),
      ),
      extendedTextStyle: text.labelLarge?.copyWith(fontSize: 16),
      extendedPadding: const EdgeInsets.symmetric(horizontal: Space.lg),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(64, minTarget)),
        shape: WidgetStatePropertyAll(controlShape),
        textStyle: WidgetStatePropertyAll(text.labelLarge),
        side: ring(BorderSide(color: scheme.outline)),
      ),
    ),
    chipTheme: chipTheme(scheme, text, controlShape),
    switchTheme: SwitchThemeData(
      thumbIcon: WidgetStateProperty.resolveWith(
        (states) => Icon(
          states.contains(WidgetState.selected) ? Icons.check : Icons.close,
          size: 16,
        ),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      modalBackgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: scheme.onSurfaceVariant,
      dragHandleSize: const Size(32, 4),
      clipBehavior: Clip.antiAlias,
      constraints: const BoxConstraints(maxWidth: 640),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(Corner.container),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: text.bodyMedium?.copyWith(
        color: scheme.onInverseSurface,
      ),
      actionTextColor: scheme.inversePrimary,
      disabledActionTextColor: scheme.onInverseSurface.withValues(alpha: 0.5),
      shape: controlShape,
      insetPadding: const EdgeInsets.all(Space.lg),
      showCloseIcon: false,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Corner.container),
      ),
      titleTextStyle: text.headlineSmall?.copyWith(color: scheme.onSurface),
      contentTextStyle: text.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      textColor: scheme.onSurface,
      titleTextStyle: text.bodyLarge?.copyWith(color: scheme.onSurface),
      subtitleTextStyle: text.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.lg),
      minTileHeight: 56,
      minVerticalPadding: Space.sm,
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant,
      thickness: 1,
      space: 1,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: scheme.surfaceContainerHighest,
      circularTrackColor: scheme.surfaceContainerHighest,
      linearMinHeight: 4,
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      // Tonal, no shadow: a 1 dp rule in the ink's neutral edges the menu instead.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Corner.control),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      elevation: 0,
      textStyle: text.bodyLarge?.copyWith(color: scheme.onSurface),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: scheme.inverseSurface,
        borderRadius: BorderRadius.circular(Corner.control),
      ),
      textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(
        scheme.onSurfaceVariant.withValues(alpha: 0.5),
      ),
      radius: const Radius.circular(4),
      thickness: const WidgetStatePropertyAll(6),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: scheme.primary,
      selectionColor: scheme.primary.withValues(alpha: 0.28),
      selectionHandleColor: scheme.primary,
    ),
  );
}

/// Filter chips: selected = tonal container with `onSecondaryContainer` text and check; unselected = no fill
/// (the surface behind it) with `onSurface` text and an `outline` rule. Spelled out because the Material
/// default colours are lost as soon as a theme sets `labelStyle` without a colour.
@visibleForTesting
ChipThemeData chipTheme(
  ColorScheme scheme,
  TextTheme text,
  OutlinedBorder shape,
) => ChipThemeData(
  shape: shape,
  // The chip resolves the label colour itself: it has to be a WidgetStateColor inside the style.
  labelStyle: text.labelLarge!.copyWith(
    color: WidgetStateColor.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? scheme.onSurface.withValues(alpha: 0.38)
          : states.contains(WidgetState.selected)
          ? scheme.onSecondaryContainer
          : scheme.onSurface,
    ),
  ),
  color: WidgetStateProperty.resolveWith(
    (states) => states.contains(WidgetState.selected)
        ? scheme.secondaryContainer
        : null,
  ),
  side: WidgetStateBorderSide.resolveWith(
    (states) => states.contains(WidgetState.selected)
        ? BorderSide.none
        : BorderSide(color: scheme.outline),
  ),
  checkmarkColor: scheme.onSecondaryContainer,
  iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 18),
  padding: const EdgeInsets.symmetric(horizontal: Space.xs),
);

SystemUiOverlayStyle _overlayStyle(Color bar, Color page) {
  Brightness iconsOn(Color c) =>
      ThemeData.estimateBrightnessForColor(c) == Brightness.dark
      ? Brightness.light
      : Brightness.dark;
  final status = iconsOn(bar), nav = iconsOn(page);
  return SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: status,
    statusBarBrightness: status == Brightness.light
        ? Brightness.dark
        : Brightness.light,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
    systemNavigationBarIconBrightness: nav,
    systemNavigationBarContrastEnforced: false,
  );
}
