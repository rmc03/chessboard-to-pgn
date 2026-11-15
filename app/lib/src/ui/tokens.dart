// Design tokens of the "Plaza" world (docs/ux-spec.md, section 2): the five stones of the board, the fixed
// colours of the board and its marks, spacing, radii, breakpoints and motion. The palette of the Material colour
// scheme lives in theme.dart; together they are the ONLY files with colour literals (the other UI code takes
// colours from the colour scheme or from [AppTheme]).
import 'package:material_ui/material_ui.dart';

import '../settings.dart' show defaultStoneId;

/// A stone the board is laid in (the setting "Piedra"). It changes the board only: the shell is always park-bench
/// green.
@immutable
class Stone {
  const Stone({
    required this.id,
    required this.name,
    required this.lightSquare,
    required this.darkSquare,
  });

  /// One of `stoneIds` in settings.dart.
  final String id;

  /// Spanish name shown in Ajustes.
  final String name;

  /// Light square.
  final Color lightSquare;

  /// Dark square: a mid tone (L* 55-65) that keeps a white piece body at 3:1 or more.
  final Color darkSquare;

  @override
  bool operator ==(Object other) => other is Stone && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// The stones in the order they are offered; ids match `stoneIds` in settings.dart.
///
/// The values are the spec's, except two dark squares that the L* 55-65 rule pushed a step lighter (same hue
/// and chroma in CIELAB): alicante #A8776A (L* 54.6) -> #AB7A6D (55.8) and nogal #9C7653 (52.6) -> #A47D59 (55.4).
const List<Stone> stones = [
  Stone(
    id: 'serpentina',
    name: 'Serpentina',
    lightSquare: Color(0xFFE8E1CD),
    darkSquare: Color(0xFF76927F),
  ),
  Stone(
    id: 'pizarra',
    name: 'Pizarra',
    lightSquare: Color(0xFFE9E8E4),
    darkSquare: Color(0xFF7D8590),
  ),
  Stone(
    id: 'alicante',
    name: 'Rojo Alicante',
    lightSquare: Color(0xFFEADFCC),
    darkSquare: Color(0xFFAB7A6D),
  ),
  Stone(
    id: 'nogal',
    name: 'Nogal',
    lightSquare: Color(0xFFEBD9B8),
    darkSquare: Color(0xFFA47D59),
  ),
  Stone(
    id: 'granito',
    name: 'Granito',
    lightSquare: Color(0xFFE3E1DA),
    darkSquare: Color(0xFF8F918C),
  ),
];

/// The stone with this id; the default stone for an unknown id.
Stone stoneById(String id) => stones.firstWhere(
  (s) => s.id == id,
  orElse: () => stones.firstWhere((s) => s.id == defaultStoneId),
);

/// The stone every screen uses until the user picks another.
Stone get defaultStone => stoneById(defaultStoneId);

/// Fixed colours of the board and its marks. The board is the constant of the design: it does not change with
/// the theme brightness (only the glow of the doubtful mark does).
abstract final class BoardMarks {
  /// Doubtful square, light theme: street-lamp amber (corner triangle and 2 dp rule).
  static const Color doubt = Color(0xFFD98E00);

  /// Doubtful square, dark theme: the lamp lit.
  static const Color doubtLamp = Color(0xFFFFB93D);

  /// Thin dark edge that makes the amber readable on light and mid-tone squares alike.
  static const Color doubtEdge = Color(0xFF241A00);

  /// Light squares of the printed style (the paper).
  static const Color paper = Color(0xFFFFFFFF);

  /// Outline and body colours of the typographic piece set; black of the printed hatching.
  static const Color pieceBlack = Color(0xFF000000);
  static const Color pieceWhite = Color(0xFFFFFFFF);

  /// Polished granite of the board frame (the body of its 135 degree gradient; the ends are derived).
  static const Color frame = Color(0xFF4A4C48);

  /// Park-bench green the selection ring is derived from (darkened per stone until it keeps 3:1).
  static const Color selection = Color(0xFF1F5C46);
}

/// The chips of the stone textures: (colour, opacity). The terrazzo of the squares is dark brown, black, tan,
/// white, cream and green chips at 16-34 % (almost invisible on purpose: legible first, texture after); the
/// granite of the frame is fine white and black grains.
abstract final class BoardTexture {
  static const List<(Color, double)> terrazzo = [
    (Color(0xFF3A332A), 0.20),
    (Color(0xFF2C2A26), 0.16),
    (Color(0xFFA57C52), 0.26),
    (Color(0xFFFFFFFF), 0.34),
    (Color(0xFFFFFFFF), 0.22),
    (Color(0xFFD9C9A4), 0.30),
    (Color(0xFF40564A), 0.22),
    (Color(0xFF8A9A8D), 0.24),
  ];

  static const List<(Color, double)> granite = [
    (Color(0xFFFFFFFF), 0.16),
    (Color(0xFF000000), 0.30),
    (Color(0xFFFFFFFF), 0.12),
    (Color(0xFF000000), 0.22),
  ];

  /// Bevel of the frame: light on the top-left edge, shade on the bottom-right edge.
  static const Color bevelLight = Color(0x57FFFFFF);
  static const Color bevelShade = Color(0x80000000);

  /// Hairline around the squares, inside the frame.
  static const Color hairline = Color(0x99000000);
}

/// Spacing on the 4 dp grid.
abstract final class Space {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// Side margin of a screen: 16 dp, 24 dp from 600 dp wide.
  static double gutter(double width) => width >= 600 ? xl : lg;
}

/// Corner radii.
abstract final class Corner {
  /// Containers: diagram blocks, bottom sheets (top corners), dialogs.
  static const double container = 10;

  /// Controls: buttons, segmented buttons, chips, fields, snackbar, tooltip, menus, plates. Never a capsule.
  static const double control = 6;

  /// Floating action button (a plate).
  static const double fab = 6;
}

/// Window width classes (dp).
abstract final class Breakpoint {
  static const double medium = 600;
  static const double expanded = 840;
  static const double wide = 1240;
}

/// Motion durations (150-250 ms, state changes only).
abstract final class Motion {
  static const Duration fast = Duration(milliseconds: 150);
  static const Duration medium = Duration(milliseconds: 200);
  static const Duration slow = Duration(milliseconds: 250);

  static const Curve standard = Easing.standard;
  static const Curve emphasized = Easing.emphasizedDecelerate;

  /// [base] unless the system asks to remove animations.
  static Duration of(BuildContext context, Duration base) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false
      ? Duration.zero
      : base;
}

/// Minimum touch target (dp).
const double minTarget = 48;
