// Design tokens of the "Dos tintas" direction (docs/ux-spec.md, section 2): the six inks, spacing, radii,
// breakpoints, motion and the few fixed colours of the board marks. This is the ONLY file with colour literals
// (the other UI code takes colours from the Material colour scheme or from [AppTheme]).
import 'package:material_ui/material_ui.dart';

import '../settings.dart' show defaultInkId;

/// One of the six spot inks (named SpotInk because Material already has an `Ink` widget). The whole app (masthead, board squares, selection, numerals) is printed with it.
@immutable
class SpotInk {
  const SpotInk({
    required this.id,
    required this.name,
    required this.seed,
    required this.lightSquare,
    required this.darkSquare,
  });

  /// One of `inkIds` in settings.dart.
  final String id;

  /// Spanish name shown in Ajustes.
  final String name;

  /// Seed of the Material colour scheme (fidelity variant).
  final Color seed;

  /// Flat board: light square.
  final Color lightSquare;

  /// Flat board: dark square. A mid tone (L* 55-68) that keeps a white piece at 3:1 or more.
  final Color darkSquare;

  @override
  bool operator ==(Object other) => other is SpotInk && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// The inks in the order they are offered; ids match `inkIds` in settings.dart.
///
/// The seeds and light squares are the spec's. The dark squares differ from the spec's table by the smallest
/// step that lets a white piece body keep 3:1 against them (same hue and chroma in CIELAB, lightness lowered
/// to L* 61; the spec values were L* 61-68 and gave 2.4-2.9:1):
///   cobalto #7F9DCB -> #7795C3, torneo #7FA37F -> #799C79, granate #C08A86 -> #BC8682,
///   madera #B98C5E -> #B78A5D, ciruela #A48BB3 -> #A38AB2, grafito #A3A6AA -> #919397.
const List<SpotInk> inks = [
  SpotInk(
    id: 'cobalto',
    name: 'Azul cobalto',
    seed: Color(0xFF1F4E9A),
    lightSquare: Color(0xFFEEF1F6),
    darkSquare: Color(0xFF7795C3),
  ),
  SpotInk(
    id: 'torneo',
    name: 'Verde torneo',
    seed: Color(0xFF2E6B4A),
    lightSquare: Color(0xFFEDF2E6),
    darkSquare: Color(0xFF799C79),
  ),
  SpotInk(
    id: 'granate',
    name: 'Granate',
    seed: Color(0xFF8E2F3C),
    lightSquare: Color(0xFFF4ECE8),
    darkSquare: Color(0xFFBC8682),
  ),
  SpotInk(
    id: 'madera',
    name: 'Madera',
    seed: Color(0xFF8A5A2B),
    lightSquare: Color(0xFFF0DFC0),
    darkSquare: Color(0xFFB78A5D),
  ),
  SpotInk(
    id: 'ciruela',
    name: 'Ciruela',
    seed: Color(0xFF6A3F7A),
    lightSquare: Color(0xFFF0EAF2),
    darkSquare: Color(0xFFA38AB2),
  ),
  SpotInk(
    id: 'grafito',
    name: 'Grafito',
    seed: Color(0xFF4A4F57),
    lightSquare: Color(0xFFF1F1EF),
    darkSquare: Color(0xFF919397),
  ),
];

/// The ink with this id; the default ink for an unknown id.
SpotInk inkById(String id) => inks.firstWhere(
  (i) => i.id == id,
  orElse: () => inks.firstWhere((i) => i.id == defaultInkId),
);

/// The ink every screen uses until the user picks another.
SpotInk get defaultInk => inkById(defaultInkId);

/// Fixed colours of the board marks. The board is the constant of the design: its marks do not change with
/// the theme brightness.
abstract final class BoardMarks {
  /// Doubtful square: corner triangle and 2 dp rule.
  static const Color doubt = Color(0xFFFFB300);

  /// Thin dark edge that makes the amber readable on light and mid-tone squares alike.
  static const Color doubtEdge = Color(0xFF241A00);

  /// Light squares of the printed style (the paper).
  static const Color paper = Color(0xFFFFFFFF);

  /// Outline and body colours of the typographic piece set.
  static const Color pieceBlack = Color(0xFF000000);
  static const Color pieceWhite = Color(0xFFFFFFFF);

  /// Seed of the amber the warning roles are derived from (before harmonising with the ink).
  static const Color warningSeed = Color(0xFFE59A00);
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
  /// Containers: sheets, dialogs, tonal panels.
  static const double container = 12;

  /// Small controls: buttons, chips, segmented buttons, menus.
  static const double control = 8;

  /// Floating action button.
  static const double fab = 16;
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
