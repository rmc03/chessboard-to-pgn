// Small colour helpers: WCAG contrast and CIE lightness. No colour literals here.
import 'dart:math' as math;
import 'dart:ui' show Color;

/// WCAG 2.x contrast ratio between two opaque colours (1..21).
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = math.max(la, lb), lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

/// CIE L* (0..100) of an opaque colour.
double lightnessOf(Color c) {
  final y = c.computeLuminance();
  final f = y > 216 / 24389
      ? math.pow(y, 1 / 3).toDouble()
      : (24389 / 27 * y + 16) / 116;
  return 116 * f - 16;
}

/// [fg] painted over [bg] with [fg]'s own alpha, as an opaque colour.
Color overOpaque(Color fg, Color bg) => Color.alphaBlend(fg, bg);
