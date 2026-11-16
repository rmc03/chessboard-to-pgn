// The enamel plate: the gesture of the Plaza world. A street-name plate is an enamel fill with a thin off-white
// rule inset from the edge and small round corners. Only four things carry it (nothing else does: if everything
// is a plate, nothing is): the number of a diagram, the header of a capture, the floating action button and the
// one primary button of a screen.
//
//   EnamelPlate.numeral(2)                    "DIAGRAMA" over a big 2 (reads "Diagrama 2")
//   EnamelPlate.label('CAPTURA 1')            small plate with a line of text
//   EnamelPlate.numeral(1, muted: true)       the plate of something that is not yours (the example of the empty
//                                             screen): stone fill and an outline rule, no enamel, no inner rule
//   FloatingActionButton.extended(...)        gets [PlateBorder] from the theme: nothing to do
//   FilledButton(style: plateButtonStyle(context), ...)   the primary button of a screen
//   PlateBorder(ruleColor: ...)               the shape itself, for anything else that must be a plate
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'theme.dart';
import 'tokens.dart';

/// A rounded rectangle that also paints the inner rule of an enamel plate: a [ruleWidth] line of [ruleColor],
/// [inset] dp from the edge, with the corner radius reduced by the inset. Use it as the `shape` of anything
/// that is a plate (a [Material], a button style, a [ShapeDecoration]); the rule is painted over the child, like
/// a border.
class PlateBorder extends OutlinedBorder {
  const PlateBorder({
    required this.ruleColor,
    this.radius = Corner.control,
    this.inset = 3,
    this.ruleWidth = 1.5,
    super.side,
  });

  /// The off-white of the rule (`AppTheme.onPlate`).
  final Color ruleColor;

  /// Corner radius of the plate (6 dp).
  final double radius;

  /// Distance from the plate's edge to the outside of the rule.
  final double inset;

  /// Thickness of the rule.
  final double ruleWidth;

  RRect _outer(Rect rect) =>
      RRect.fromRectAndRadius(rect, Radius.circular(radius));

  /// The rounded rectangle the rule is drawn along (its centre line).
  RRect ruleRect(Rect rect) {
    final d = inset + ruleWidth / 2;
    return RRect.fromRectAndRadius(
      rect.deflate(d),
      Radius.circular(math.max(radius - inset, 1.5)),
    );
  }

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(_outer(rect));

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      Path()..addRRect(_outer(rect).deflate(side.width));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (rect.isEmpty) return;
    if (side.style != BorderStyle.none && side.width > 0) {
      canvas.drawRRect(
        _outer(rect).deflate(side.width / 2),
        side.toPaint()..style = PaintingStyle.stroke,
      );
    }
    canvas.drawRRect(
      ruleRect(rect),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = ruleWidth
        ..isAntiAlias = true
        ..color = ruleColor,
    );
  }

  @override
  PlateBorder copyWith({
    BorderSide? side,
    Color? ruleColor,
    double? radius,
    double? inset,
    double? ruleWidth,
  }) => PlateBorder(
    ruleColor: ruleColor ?? this.ruleColor,
    radius: radius ?? this.radius,
    inset: inset ?? this.inset,
    ruleWidth: ruleWidth ?? this.ruleWidth,
    side: side ?? this.side,
  );

  @override
  ShapeBorder scale(double t) => PlateBorder(
    ruleColor: ruleColor,
    radius: radius * t,
    inset: inset * t,
    ruleWidth: ruleWidth * t,
    side: side.scale(t),
  );

  @override
  bool operator ==(Object other) =>
      other is PlateBorder &&
      other.ruleColor == ruleColor &&
      other.radius == radius &&
      other.inset == inset &&
      other.ruleWidth == ruleWidth &&
      other.side == side;

  @override
  int get hashCode => Object.hash(ruleColor, radius, inset, ruleWidth, side);

  @override
  String toString() =>
      'PlateBorder($ruleColor, r$radius, inset $inset, rule $ruleWidth)';
}

/// Button style of the one primary button of a screen: enamel fill, off-white text, the plate shape and its
/// inner rule. `FilledButton(style: plateButtonStyle(context), onPressed: ..., child: ...)`. Disabled, it falls
/// back to a plain 6 dp tonal button (a dead plate would still look pressable).
ButtonStyle plateButtonStyle(BuildContext context) {
  final scheme = Theme.of(context).colorScheme;
  final app = AppTheme.of(context);
  return ButtonStyle(
    backgroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? scheme.onSurface.withValues(alpha: 0.12)
          : app.plate,
    ),
    foregroundColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.disabled)
          ? scheme.onSurface.withValues(alpha: 0.38)
          : app.onPlate,
    ),
    overlayColor: WidgetStateProperty.resolveWith(
      (states) => states.contains(WidgetState.pressed)
          ? app.onPlate.withValues(alpha: 0.16)
          : states.contains(WidgetState.hovered)
          ? app.onPlate.withValues(alpha: 0.10)
          : states.contains(WidgetState.focused)
          ? app.onPlate.withValues(alpha: 0.14)
          : null,
    ),
    shape: WidgetStateProperty.resolveWith<OutlinedBorder>(
      (states) => states.contains(WidgetState.disabled)
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Corner.control),
            )
          : PlateBorder(ruleColor: app.onPlate),
    ),
    elevation: const WidgetStatePropertyAll(0),
  );
}

/// What goes on a plate.
enum _PlateKind { numeral, label }

/// A street-name plate: [plate] fill, a soft gloss on the upper half, the inner rule of [PlateBorder] and
/// Barlow Condensed text in [onPlate]. Sized by its content (at least 62 x 48 dp for the numeral, 30 dp high for
/// the label); text scale is capped at 1.3 so a plate never outgrows its row.
class EnamelPlate extends StatelessWidget {
  /// The number of a diagram: a small tracked [caption] over a big tabular numeral. Reads "Diagrama 2".
  const EnamelPlate.numeral(
    int this.number, {
    super.key,
    this.caption = 'DIAGRAMA',
    this.semanticLabel,
    this.muted = false,
  }) : text = null,
       _kind = _PlateKind.numeral;

  /// A small plate with one line of text, written in capitals: the header of a capture ("CAPTURA 1").
  const EnamelPlate.label(
    String this.text, {
    super.key,
    this.semanticLabel,
    this.muted = false,
  }) : number = null,
       caption = null,
       _kind = _PlateKind.label;

  final int? number;
  final String? caption;
  final String? text;
  final _PlateKind _kind;

  /// A quiet plate: stone fill with a 1 dp outline instead of enamel and the inner rule. For the example of the
  /// empty screen, which is not the user's diagram.
  final bool muted;

  /// Overrides the spoken text (default: the caption and number, or the text, in sentence case).
  final String? semanticLabel;

  /// What a screen reader says for this plate.
  String get spoken {
    if (semanticLabel != null) return semanticLabel!;
    String sentence(String s) =>
        s.isEmpty ? s : s[0].toUpperCase() + s.substring(1).toLowerCase();
    return switch (_kind) {
      _PlateKind.numeral => '${sentence(caption ?? '')} $number'.trim(),
      _PlateKind.label => sentence(text!),
    };
  }

  @override
  Widget build(BuildContext context) {
    final app = AppTheme.of(context);
    final scheme = Theme.of(context).colorScheme;
    final numeral = _kind == _PlateKind.numeral;
    final ink = muted ? scheme.onSurfaceVariant : app.onPlate;
    final content = numeral
        ? Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (caption != null && caption!.isNotEmpty)
                Text(
                  caption!,
                  maxLines: 1,
                  style: app.plateCaption.copyWith(color: ink),
                ),
              const SizedBox(height: 1),
              Text(
                '$number',
                maxLines: 1,
                style: app.numeral.copyWith(color: ink),
              ),
            ],
          )
        : Text(
            text!,
            maxLines: 1,
            softWrap: false,
            style: app.plateLabel.copyWith(color: ink),
          );
    final plate = DecoratedBox(
      decoration: ShapeDecoration(
        color: muted ? scheme.surfaceContainerHighest : app.plate,
        shape: muted
            ? RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(Corner.control),
                side: BorderSide(color: scheme.outline),
              )
            : PlateBorder(ruleColor: app.onPlate),
      ),
      child: DecoratedBox(
        // the gloss of enamel: a little light on the upper half (none on a muted plate)
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(Corner.control),
          gradient: muted
              ? null
              : LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, 0.45, 0.451],
                  colors: [
                    app.onPlate.withValues(alpha: 0.10),
                    app.onPlate.withValues(alpha: 0),
                    app.onPlate.withValues(alpha: 0),
                  ],
                ),
        ),
        child: ConstrainedBox(
          constraints: numeral
              ? const BoxConstraints(minWidth: 62, minHeight: 48)
              : const BoxConstraints(minHeight: 30),
          child: Padding(
            padding: numeral
                ? const EdgeInsets.symmetric(
                    horizontal: Space.sm + 2,
                    vertical: 5,
                  )
                : const EdgeInsets.symmetric(horizontal: Space.md, vertical: 6),
            child: Center(widthFactor: 1, heightFactor: 1, child: content),
          ),
        ),
      ),
    );
    return Semantics(
      label: spoken,
      container: true,
      excludeSemantics: true,
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: plate,
      ),
    );
  }
}
