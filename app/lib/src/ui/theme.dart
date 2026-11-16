// Theme of the app, the "Plaza" world: one [ColorScheme] per brightness built by hand from the palette of
// docs/ux-spec.md (section 2), the type scale (Barlow, Barlow Condensed, JetBrains Mono), component themes with
// the shapes of an enamel plate (6 dp radius, no capsules, no shadows) and the [AppTheme] extension for what
// Material lacks (warning roles, plate colours, board colours of the chosen stone, the named text styles).
//
// Screens get everything through the theme:
//   Theme.of(context).colorScheme          Material roles (primary, surfaceContainerLow, outline, error...)
//   Theme.of(context).textTheme            the type scale
//   context.app.warning / .masthead ...    [AppTheme], see below
import 'dart:ui' as ui show FontFeature;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'icons.dart';
import 'plate.dart';
import 'tokens.dart';

/// Tabular (equal width) figures, for numerals and counters.
const List<ui.FontFeature> tabularFigures = [ui.FontFeature.tabularFigures()];

/// What Material has no role for.
@immutable
class AppTheme extends ThemeExtension<AppTheme> {
  const AppTheme({
    required this.stone,
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.warningMark,
    required this.lampGlow,
    required this.shell,
    required this.onShell,
    required this.plate,
    required this.onPlate,
    required this.stage,
    required this.stoneFrame,
    required this.boardLight,
    required this.boardDark,
    required this.boardHatch,
    required this.boardPaper,
    required this.masthead,
    required this.numeral,
    required this.plateLabel,
    required this.plateCaption,
    required this.mono,
    required this.systemOverlay,
  });

  /// The stone of the board this theme was built for.
  final Stone stone;

  /// Doubtful squares and other "look again" states (street-lamp amber). [warning] is the AA text and icon
  /// colour on a surface (dark amber in light, lamp amber in dark); [warningContainer] a band behind text coloured
  /// [onWarningContainer]; [onWarning] is for text on a [warning] fill.
  final Color warning, onWarning, warningContainer, onWarningContainer;

  /// The amber of the doubtful marker on the board (ring and corner triangle). A mark, not a text colour.
  final Color warningMark;

  /// Whether the doubtful mark gets a faint lamp halo (the dark theme: the plaza at night).
  final bool lampGlow;

  /// The shell: app bar background and the colour on it.
  final Color shell, onShell;

  /// Enamel of the plates, the FAB and the primary button, and the off-white of their inner rule and text.
  final Color plate, onPlate;

  /// Basalt behind a picture that is being worked on (the crop screen): dark in both themes, so a white page
  /// of a book sits on it like paper on a stone slab.
  final Color stage;

  /// Body colour of the polished granite frame of the board (the same in light and dark).
  final Color stoneFrame;

  /// Squares of the chosen stone (the same in light and dark: the diagram is the constant).
  final Color boardLight, boardDark;

  /// Colour of the hatching of the printed style (black, like a book).
  final Color boardHatch;

  /// Light squares of the printed style.
  final Color boardPaper;

  /// Barlow Condensed 700 for the app bar title (the masthead).
  final TextStyle masthead;

  /// Barlow Condensed 700 with tabular figures, for the big diagram number (see `EnamelPlate.numeral`). No
  /// colour.
  final TextStyle numeral;

  /// Barlow Condensed 700 for the text of a small plate (`EnamelPlate.label`). Write it in capitals. No colour.
  final TextStyle plateLabel;

  /// Barlow Condensed 600, small and tracked, for the caption above the numeral of a plate. No colour.
  final TextStyle plateCaption;

  /// JetBrains Mono for FEN and PGN (data). No colour.
  final TextStyle mono;

  /// Style of the system bars (edge to edge, icon brightness that matches the app bar and the page).
  final SystemUiOverlayStyle systemOverlay;

  /// The extension of the nearest theme; the default stone in light mode when there is none (tests, previews
  /// outside the app).
  static AppTheme of(BuildContext context) =>
      Theme.of(context).extension<AppTheme>() ?? fallback;

  /// [AppTheme] of the default stone, light.
  static final AppTheme fallback = buildTheme(
    defaultStone,
    Brightness.light,
  ).extension<AppTheme>()!;

  @override
  AppTheme copyWith({
    Stone? stone,
    Color? warning,
    Color? onWarning,
    Color? warningContainer,
    Color? onWarningContainer,
    Color? warningMark,
    bool? lampGlow,
    Color? shell,
    Color? onShell,
    Color? plate,
    Color? onPlate,
    Color? stage,
    Color? stoneFrame,
    Color? boardLight,
    Color? boardDark,
    Color? boardHatch,
    Color? boardPaper,
    TextStyle? masthead,
    TextStyle? numeral,
    TextStyle? plateLabel,
    TextStyle? plateCaption,
    TextStyle? mono,
    SystemUiOverlayStyle? systemOverlay,
  }) => AppTheme(
    stone: stone ?? this.stone,
    warning: warning ?? this.warning,
    onWarning: onWarning ?? this.onWarning,
    warningContainer: warningContainer ?? this.warningContainer,
    onWarningContainer: onWarningContainer ?? this.onWarningContainer,
    warningMark: warningMark ?? this.warningMark,
    lampGlow: lampGlow ?? this.lampGlow,
    shell: shell ?? this.shell,
    onShell: onShell ?? this.onShell,
    plate: plate ?? this.plate,
    onPlate: onPlate ?? this.onPlate,
    stage: stage ?? this.stage,
    stoneFrame: stoneFrame ?? this.stoneFrame,
    boardLight: boardLight ?? this.boardLight,
    boardDark: boardDark ?? this.boardDark,
    boardHatch: boardHatch ?? this.boardHatch,
    boardPaper: boardPaper ?? this.boardPaper,
    masthead: masthead ?? this.masthead,
    numeral: numeral ?? this.numeral,
    plateLabel: plateLabel ?? this.plateLabel,
    plateCaption: plateCaption ?? this.plateCaption,
    mono: mono ?? this.mono,
    systemOverlay: systemOverlay ?? this.systemOverlay,
  );

  @override
  AppTheme lerp(ThemeExtension<AppTheme>? other, double t) {
    if (other is! AppTheme) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    TextStyle mixText(TextStyle a, TextStyle b) => TextStyle.lerp(a, b, t)!;
    return AppTheme(
      stone: t < 0.5 ? stone : other.stone,
      warning: mix(warning, other.warning),
      onWarning: mix(onWarning, other.onWarning),
      warningContainer: mix(warningContainer, other.warningContainer),
      onWarningContainer: mix(onWarningContainer, other.onWarningContainer),
      warningMark: mix(warningMark, other.warningMark),
      lampGlow: t < 0.5 ? lampGlow : other.lampGlow,
      shell: mix(shell, other.shell),
      onShell: mix(onShell, other.onShell),
      plate: mix(plate, other.plate),
      onPlate: mix(onPlate, other.onPlate),
      stage: mix(stage, other.stage),
      stoneFrame: mix(stoneFrame, other.stoneFrame),
      boardLight: mix(boardLight, other.boardLight),
      boardDark: mix(boardDark, other.boardDark),
      boardHatch: mix(boardHatch, other.boardHatch),
      boardPaper: mix(boardPaper, other.boardPaper),
      masthead: mixText(masthead, other.masthead),
      numeral: mixText(numeral, other.numeral),
      plateLabel: mixText(plateLabel, other.plateLabel),
      plateCaption: mixText(plateCaption, other.plateCaption),
      mono: mixText(mono, other.mono),
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

const String _ui = 'Barlow';
const String _condensed = 'BarlowCondensed';
const String _monoFamily = 'JetBrainsMono';

/// Barlow on a ~1.2 scale (12, 13, 15, 17, 20, 24, 29, 35, 42, 50, 60) mapped to the Material roles. Barlow sets
/// small for its size, so body text starts at 15. Button labels are Barlow 600 in sentence case.
TextTheme _textTheme() => const TextTheme(
  displayLarge: TextStyle(
    fontFamily: _ui,
    fontSize: 60,
    height: 1.1,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.4,
  ),
  displayMedium: TextStyle(
    fontFamily: _ui,
    fontSize: 50,
    height: 1.1,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
  ),
  displaySmall: TextStyle(
    fontFamily: _ui,
    fontSize: 42,
    height: 1.15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.2,
  ),
  headlineLarge: TextStyle(
    fontFamily: _ui,
    fontSize: 35,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  ),
  headlineMedium: TextStyle(
    fontFamily: _ui,
    fontSize: 29,
    height: 1.2,
    fontWeight: FontWeight.w600,
  ),
  headlineSmall: TextStyle(
    fontFamily: _ui,
    fontSize: 24,
    height: 1.25,
    fontWeight: FontWeight.w600,
  ),
  titleLarge: TextStyle(
    fontFamily: _ui,
    fontSize: 21,
    height: 1.3,
    fontWeight: FontWeight.w600,
  ),
  titleMedium: TextStyle(
    fontFamily: _ui,
    fontSize: 17,
    height: 1.35,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  ),
  titleSmall: TextStyle(
    fontFamily: _ui,
    fontSize: 15,
    height: 1.35,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  ),
  bodyLarge: TextStyle(
    fontFamily: _ui,
    fontSize: 17,
    height: 1.4,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
  ),
  bodyMedium: TextStyle(
    fontFamily: _ui,
    fontSize: 15,
    height: 1.4,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.1,
  ),
  bodySmall: TextStyle(
    fontFamily: _ui,
    fontSize: 13,
    height: 1.4,
    fontWeight: FontWeight.w400,
    letterSpacing: 0.15,
  ),
  labelLarge: TextStyle(
    fontFamily: _ui,
    fontSize: 15,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
    fontFeatures: tabularFigures,
  ),
  labelMedium: TextStyle(
    fontFamily: _ui,
    fontSize: 13,
    height: 1.3,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
    fontFeatures: tabularFigures,
  ),
  labelSmall: TextStyle(
    fontFamily: _ui,
    fontSize: 12,
    height: 1.3,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.2,
    fontFeatures: tabularFigures,
  ),
);

const TextStyle _mastheadStyle = TextStyle(
  fontFamily: _condensed,
  fontSize: 28,
  height: 1.1,
  fontWeight: FontWeight.w700,
  letterSpacing: 0.2,
);

const TextStyle _numeralStyle = TextStyle(
  fontFamily: _condensed,
  fontSize: 30,
  height: 0.95,
  fontWeight: FontWeight.w700,
  letterSpacing: 0,
  fontFeatures: tabularFigures,
);

const TextStyle _plateLabelStyle = TextStyle(
  fontFamily: _condensed,
  fontSize: 16,
  height: 1.0,
  fontWeight: FontWeight.w700,
  letterSpacing: 1.0,
  fontFeatures: tabularFigures,
);

const TextStyle _plateCaptionStyle = TextStyle(
  fontFamily: _condensed,
  fontSize: 10,
  height: 1.0,
  fontWeight: FontWeight.w600,
  letterSpacing: 1.3,
);

const TextStyle _monoStyle = TextStyle(
  fontFamily: _monoFamily,
  fontSize: 13,
  height: 1.5,
  fontWeight: FontWeight.w400,
  letterSpacing: 0,
);

// ---------------------------------------------------------------------------------------------- palette

/// The palette of docs/ux-spec.md section 2, built into a full scheme by hand (no seed): primary = park-bench
/// green, surfaces = limestone and stone (light) or basalt (dark). `secondaryContainer` is the tuned fill of the
/// selected segment and chip (and of the tonal button).
const ColorScheme _lightScheme = ColorScheme(
  brightness: Brightness.light,
  primary: Color(0xFF1F5C46),
  onPrimary: Color(0xFFF4F1E8),
  primaryContainer: Color(0xFFC5DACB),
  onPrimaryContainer: Color(0xFF0F3527),
  secondary: Color(0xFF4A5F53),
  onSecondary: Color(0xFFF4F1E8),
  secondaryContainer: Color(0xFFBBD4C4),
  onSecondaryContainer: Color(0xFF0E3224),
  tertiary: Color(0xFF4F6068),
  onTertiary: Color(0xFFF4F1E8),
  tertiaryContainer: Color(0xFFD5DDE0),
  onTertiaryContainer: Color(0xFF1F2D33),
  error: Color(0xFFA3402A), // spec brick #A8432C, a step darker to reach 4.5:1 on the stone of the blocks
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFF3D3C9),
  onErrorContainer: Color(0xFF5A1A0B),
  surface: Color(0xFFECE8DF),
  onSurface: Color(0xFF1D2520),
  surfaceDim: Color(0xFFDDD8CC),
  surfaceBright: Color(0xFFF4F1E8),
  surfaceContainerLowest: Color(0xFFF4F1E8),
  surfaceContainerLow: Color(0xFFE0DBCD),
  surfaceContainer: Color(0xFFDAD5C7),
  surfaceContainerHigh: Color(0xFFD5D0C2),
  surfaceContainerHighest: Color(0xFFD0CBBD),
  onSurfaceVariant: Color(0xFF47524A),
  outline: Color(0xFF697768),
  outlineVariant: Color(0xFFC4BFB0),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  inverseSurface: Color(0xFF2A332D),
  onInverseSurface: Color(0xFFECE8DF),
  inversePrimary: Color(0xFF8DD1AD),
  surfaceTint: Color(0xFF1F5C46),
);

const ColorScheme _darkScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFF8DD1AD),
  onPrimary: Color(0xFF0B2A1E),
  primaryContainer: Color(0xFF143E30),
  onPrimaryContainer: Color(0xFFE6EDE6),
  secondary: Color(0xFFA9C7B6),
  onSecondary: Color(0xFF10281D),
  secondaryContainer: Color(0xFF2A4C3D),
  onSecondaryContainer: Color(0xFFD5ECDE),
  tertiary: Color(0xFFA9BDC6),
  onTertiary: Color(0xFF1B2A30),
  tertiaryContainer: Color(0xFF2E3C42),
  onTertiaryContainer: Color(0xFFDCE5E8),
  error: Color(0xFFD9694C),
  onError: Color(0xFF2A0D05),
  errorContainer: Color(0xFF5A2415),
  onErrorContainer: Color(0xFFF8D6CC),
  surface: Color(0xFF0F1411),
  onSurface: Color(0xFFE4E8E0),
  surfaceDim: Color(0xFF0B0F0D),
  surfaceBright: Color(0xFF2F3A34),
  surfaceContainerLowest: Color(0xFF0B0F0D),
  surfaceContainerLow: Color(0xFF181F1B),
  surfaceContainer: Color(0xFF1C2420),
  surfaceContainerHigh: Color(0xFF232C27),
  surfaceContainerHighest: Color(0xFF2B352F),
  onSurfaceVariant: Color(0xFFA9B3AA),
  outline: Color(0xFF6F7E73),
  outlineVariant: Color(0xFF2C3631),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  inverseSurface: Color(0xFFE4E8E0),
  onInverseSurface: Color(0xFF1D2520),
  inversePrimary: Color(0xFF1F5C46),
  surfaceTint: Color(0xFF8DD1AD),
);

/// Non-Material roles of the palette, per brightness.
class _Extra {
  const _Extra({
    required this.warning,
    required this.onWarning,
    required this.warningContainer,
    required this.onWarningContainer,
    required this.warningMark,
    required this.shell,
    required this.onShell,
    required this.plate,
    required this.onPlate,
    required this.stage,
  });

  final Color warning,
      onWarning,
      warningContainer,
      onWarningContainer,
      warningMark;
  final Color shell, onShell, plate, onPlate, stage;
}

const _Extra _lightExtra = _Extra(
  warning: Color(
    0xFF7E4F05,
  ), // dark amber: AA text and icon on limestone and stone
  onWarning: Color(0xFFFFFFFF),
  warningContainer: Color(0xFFF6E2B8),
  onWarningContainer: Color(0xFF4A2E00),
  warningMark: BoardMarks.doubt,
  shell: Color(0xFF1F5C46), // park-bench green
  onShell: Color(0xFFF4F1E8),
  plate: Color(0xFF1F5C46),
  onPlate: Color(0xFFF7F5EE),
  stage: Color(0xFF0F1411), // basalt, as the dark page
);

const _Extra _darkExtra = _Extra(
  warning: Color(0xFFF5B44E), // the street lamp
  onWarning: Color(0xFF2A1A00),
  warningContainer: Color(0xFF3A2A0A),
  onWarningContainer: Color(0xFFFFD98F),
  warningMark: BoardMarks.doubtLamp,
  shell: Color(0xFF143E30),
  onShell: Color(0xFFE6EDE6),
  plate: Color(0xFF266A52), // one enamel for plates, FAB and primary button (lighter than the shell to read on basalt)
  onPlate: Color(0xFFF4F7F2),
  stage: Color(0xFF0F1411),
);

// ----------------------------------------------------------------------------------------------- theme

/// The theme of [stone] in [brightness].
ThemeData buildTheme(Stone stone, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = dark ? _darkScheme : _lightScheme;
  final extra = dark ? _darkExtra : _lightExtra;
  final text = _textTheme();

  final barBackground = extra.shell;
  final barForeground = extra.onShell;
  final overlay = _overlayStyle(barBackground, scheme.surface);

  final app = AppTheme(
    stone: stone,
    warning: extra.warning,
    onWarning: extra.onWarning,
    warningContainer: extra.warningContainer,
    onWarningContainer: extra.onWarningContainer,
    warningMark: extra.warningMark,
    lampGlow: dark,
    shell: extra.shell,
    onShell: extra.onShell,
    plate: extra.plate,
    onPlate: extra.onPlate,
    stage: extra.stage,
    stoneFrame: BoardMarks.frame,
    boardLight: stone.lightSquare,
    boardDark: stone.darkSquare,
    boardHatch: BoardMarks.pieceBlack,
    boardPaper: BoardMarks.paper,
    masthead: _mastheadStyle,
    numeral: _numeralStyle,
    plateLabel: _plateLabelStyle,
    plateCaption: _plateCaptionStyle,
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
    elevation: const WidgetStatePropertyAll(0),
  );

  final fabShape = PlateBorder(ruleColor: extra.onPlate);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    canvasColor: scheme.surface,
    textTheme: text,
    iconTheme: IconThemeData(size: 24, color: scheme.onSurface),
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
    actionIconTheme: ActionIconThemeData(
      backButtonIconBuilder: (_) => const AppIcon(AppIcons.back),
      closeButtonIconBuilder: (_) => const AppIcon(AppIcons.close),
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
        shape: WidgetStatePropertyAll(controlShape),
        side: ring(),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: extra.plate,
      foregroundColor: extra.onPlate,
      focusColor: extra.onPlate.withValues(alpha: 0.24),
      hoverColor: extra.onPlate.withValues(alpha: 0.12),
      // Tonal, no shadow: the enamel fill separates it from the page, the inner rule makes it a plate.
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
      shape: fabShape,
      extendedTextStyle: text.labelLarge?.copyWith(fontSize: 16),
      extendedPadding: const EdgeInsets.symmetric(horizontal: Space.lg),
      extendedIconLabelSpacing: Space.sm + Space.xs,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      // The selected segment says so by its fill and strong text; screens pass `showSelectedIcon: false`. If one
      // forgets, the check is the app's own (AppIcon), never Material's.
      selectedIcon: const AppIcon(AppIcons.check, size: 18),
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(64, minTarget)),
        shape: WidgetStatePropertyAll(controlShape),
        textStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelLarge?.copyWith(
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w500,
          ),
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.secondaryContainer
              : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.disabled)
              ? scheme.onSurface.withValues(alpha: 0.38)
              : states.contains(WidgetState.selected)
              ? scheme.onSecondaryContainer
              : scheme.onSurface,
        ),
        side: ring(BorderSide(color: scheme.outline)),
        elevation: const WidgetStatePropertyAll(0),
      ),
    ),
    chipTheme: chipTheme(scheme, text, controlShape),
    switchTheme: SwitchThemeData(
      // No thumb icon: Material only takes an `Icon` (IconData) there and the app draws its icons with
      // Hugeicons. The thumb's position and size carry the state, the track is filled when on.
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? Colors.transparent
            : scheme.outline,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLow,
      modalBackgroundColor: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
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
      elevation: 0,
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
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Corner.container),
      ),
      titleTextStyle: text.headlineSmall?.copyWith(color: scheme.onSurface),
      contentTextStyle: text.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    ),
    cardTheme: CardThemeData(
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Corner.container),
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Corner.control),
        borderSide: BorderSide(color: scheme.outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Corner.control),
        borderSide: BorderSide(color: scheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Corner.control),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Corner.control),
        borderSide: BorderSide(color: scheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Corner.control),
        borderSide: BorderSide(color: scheme.error, width: 2),
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
      shape: controlShape,
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
      borderRadius: BorderRadius.circular(2),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surfaceContainer,
      surfaceTintColor: Colors.transparent,
      // Tonal, no shadow: a 1 dp rule in the neutral edges the menu instead.
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Corner.control),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      elevation: 0,
      textStyle: text.bodyLarge?.copyWith(color: scheme.onSurface),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainer),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        elevation: const WidgetStatePropertyAll(0),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Corner.control),
            side: BorderSide(color: scheme.outlineVariant),
          ),
        ),
      ),
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
      radius: const Radius.circular(3),
      thickness: const WidgetStatePropertyAll(6),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: scheme.primary,
      selectionColor: scheme.primary.withValues(alpha: 0.28),
      selectionHandleColor: scheme.primary,
    ),
  );
}

/// Filter chips: selected = the tuned secondary container with `onSecondaryContainer` text and the check;
/// unselected = no fill (the surface behind it) with `onSurface` text; both with a 1 dp `outline` rule and the
/// 6 dp corners of every control. Spelled out because the Material default colours are lost as soon as a theme
/// sets `labelStyle` without a colour. The chip keeps its check mark: a fill alone is a weak cue on stone.
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
  side: BorderSide(color: scheme.outline),
  elevation: 0,
  pressElevation: 0,
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
