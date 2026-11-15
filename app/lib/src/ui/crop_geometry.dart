// Pure geometry of the manual crop screen: the image <-> screen mapping, zoom and pan limits, the rectangle
// operations (resize by a handle, move, clamp), hit testing of the handles and the loupe placement.
// No widgets here, so every rule is unit-testable. The rectangle always lives in IMAGE pixels; the view
// (scale + offset) maps image pixels to the screen: screen = image * scale + offset.
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart' show immutable;

/// The eight handles of the rectangle.
enum CropHandle {
  topLeft,
  top,
  topRight,
  right,
  bottomRight,
  bottom,
  bottomLeft,
  left;

  bool get isCorner =>
      this == topLeft ||
      this == topRight ||
      this == bottomLeft ||
      this == bottomRight;
  bool get movesLeft => this == topLeft || this == left || this == bottomLeft;
  bool get movesRight =>
      this == topRight || this == right || this == bottomRight;
  bool get movesTop => this == topLeft || this == top || this == topRight;
  bool get movesBottom =>
      this == bottomLeft || this == bottom || this == bottomRight;

  /// Where this handle sits on [r].
  Offset on(Rect r) => switch (this) {
    topLeft => r.topLeft,
    top => r.topCenter,
    topRight => r.topRight,
    right => r.centerRight,
    bottomRight => r.bottomRight,
    bottom => r.bottomCenter,
    bottomLeft => r.bottomLeft,
    left => r.centerLeft,
  };
}

/// What a point touches: a handle, the inside of the rectangle (moves it) or the outside (pans the view).
enum CropHitKind { handle, inside, outside }

@immutable
class CropHit {
  const CropHit(this.kind, [this.handle]);
  final CropHitKind kind;
  final CropHandle? handle;

  static const CropHit inside = CropHit(CropHitKind.inside);
  static const CropHit outside = CropHit(CropHitKind.outside);

  @override
  bool operator ==(Object other) =>
      other is CropHit && other.kind == kind && other.handle == handle;
  @override
  int get hashCode => Object.hash(kind, handle);
  @override
  String toString() => 'CropHit($kind${handle == null ? '' : ', $handle'})';
}

/// Image -> screen transform: `screen = image * scale + offset`.
@immutable
class CropView {
  const CropView(this.scale, this.offset);
  final double scale;
  final Offset offset;

  Offset toScreen(Offset image) => image * scale + offset;
  Offset toImage(Offset screen) => (screen - offset) / scale;
  Rect rectToScreen(Rect r) =>
      Rect.fromPoints(toScreen(r.topLeft), toScreen(r.bottomRight));
  Rect rectToImage(Rect r) =>
      Rect.fromPoints(toImage(r.topLeft), toImage(r.bottomRight));

  @override
  bool operator ==(Object other) =>
      other is CropView && other.scale == scale && other.offset == offset;
  @override
  int get hashCode => Object.hash(scale, offset);
  @override
  String toString() => 'CropView(scale: $scale, offset: $offset)';
}

/// The static setting a [CropView] lives in: image size, viewport size and the limits that follow.
class CropFrame {
  const CropFrame({required this.image, required this.viewport, this.pad = 24});

  final Size image, viewport;

  /// Empty band kept around the fitted image and allowed as extra pan range, so the handles of a rectangle
  /// that touches an image edge stay fully on screen (and away from the system gesture zones).
  final double pad;

  /// Scale at which the whole image is visible (inside the padded viewport).
  double get fitScale {
    final w = (viewport.width - 2 * pad) / image.width;
    final h = (viewport.height - 2 * pad) / image.height;
    return math.max(math.min(w, h), 1e-4);
  }

  /// At least 8x the fit scale, and never less than 4 logical px per image px (small diagrams in a big image).
  double get maxScale => math.max(fitScale * 8, 4);

  double zoomOf(CropView v) => v.scale / fitScale;

  CropView get fit => clamp(CropView(fitScale, Offset.zero));

  /// Keeps the scale in range and the image on screen (centred while it is smaller than the viewport).
  CropView clamp(CropView v) {
    final s = v.scale.clamp(fitScale, maxScale);
    return CropView(
      s,
      Offset(
        _clampAxis(v.offset.dx, image.width * s, viewport.width),
        _clampAxis(v.offset.dy, image.height * s, viewport.height),
      ),
    );
  }

  double _clampAxis(double o, double shown, double vp) {
    if (shown + 2 * pad <= vp + 1e-9) return (vp - shown) / 2;
    return o.clamp(vp - shown - pad, pad);
  }

  /// [v] with the scale set to [scale] around the screen point [focal]: the image point under it stays there.
  CropView zoomAt(CropView v, Offset focal, double scale) {
    final s = scale.clamp(fitScale, maxScale);
    final p = v.toImage(focal);
    return clamp(CropView(s, focal - p * s));
  }

  /// Zoom and pan in one step: the image point under [from] ends up under [to], scaled by [factor].
  CropView transform(CropView v, Offset from, Offset to, double factor) {
    final s = (v.scale * factor).clamp(fitScale, maxScale);
    final p = v.toImage(from);
    return clamp(CropView(s, to - p * s));
  }

  /// The view in which [r] (image pixels) is centred and fills about [fill] of the viewport, never zoomed out
  /// past the fit view.
  CropView focusOn(Rect r, {double fill = 0.65}) {
    final s = math.min(
      viewport.width * fill / r.width,
      viewport.height * fill / r.height,
    );
    return centreOn(r.center, s);
  }

  /// Same view after the viewport changed from [old]: keeps the zoom factor and the image point at the centre.
  CropView relayout(CropView v, CropFrame old) {
    final centre = v.toImage(old.viewport.center(Offset.zero));
    final s = (v.scale / old.fitScale) * fitScale;
    return centreOn(centre, s);
  }

  /// The view of scale [scale] with the image point [p] at the centre of the viewport.
  CropView centreOn(Offset p, double scale) {
    final s = scale.clamp(fitScale, maxScale);
    return clamp(CropView(s, viewport.center(Offset.zero) - p * s));
  }

  /// [a] -> [b] at progress [t]: geometric scale, linear image point at the viewport centre.
  CropView lerp(CropView a, CropView b, double t) {
    final c = viewport.center(Offset.zero);
    final pa = a.toImage(c), pb = b.toImage(c);
    final s = a.scale * math.pow(b.scale / a.scale, t);
    final p = Offset.lerp(pa, pb, t)!;
    return CropView(s, c - p * s);
  }
}

/// Operations on the selection rectangle (image pixels).
abstract final class CropRectOps {
  /// Smallest side: 24 image px (a board smaller than that cannot be read), or the image side if smaller.
  static double minSide(Size image) =>
      math.min(24, math.min(image.width, image.height));

  /// [r] inside the image, with at least the minimum side.
  static Rect clampRect(Rect r, Size image) {
    final m = minSide(image);
    final w = r.width.clamp(m, image.width),
        h = r.height.clamp(m, image.height);
    final l = r.left.clamp(0.0, image.width - w);
    final t = r.top.clamp(0.0, image.height - h);
    return Rect.fromLTWH(l, t, w, h);
  }

  /// [start] with [handle] moved by [d] image px; the rectangle stays inside the image and above the minimum.
  static Rect resize(Rect start, CropHandle handle, Offset d, Size image) {
    final m = minSide(image);
    var l = start.left, t = start.top, r = start.right, b = start.bottom;
    if (handle.movesLeft) l = (l + d.dx).clamp(0.0, r - m);
    if (handle.movesRight) r = (r + d.dx).clamp(l + m, image.width);
    if (handle.movesTop) t = (t + d.dy).clamp(0.0, b - m);
    if (handle.movesBottom) b = (b + d.dy).clamp(t + m, image.height);
    return Rect.fromLTRB(l, t, r, b);
  }

  /// [start] moved by [d] image px, clamped to the image (the size is kept).
  static Rect move(Rect start, Offset d, Size image) {
    final dx = d.dx.clamp(-start.left, image.width - start.right);
    final dy = d.dy.clamp(-start.top, image.height - start.bottom);
    return start.shift(Offset(dx, dy));
  }

  /// Half-size of the hit area of a handle (screen dp). 24 (a 48 dp target) unless the rectangle is so small
  /// on screen that the handle areas would swallow its inside; then it shrinks (never below 16).
  static double hitHalf(Rect screenRect, {double target = 24}) {
    final side = math.min(screenRect.width, screenRect.height);
    if (side >= 4 * target) return target;
    return math.max(16, side / 4);
  }

  /// What [p] touches on the rectangle [r] (both in screen coordinates). Corners win over edges, edges over the
  /// inside. The edge areas are bands of 2 * hit along each side, between the corner areas.
  static CropHit hitTest(Offset p, Rect r, {double target = 24}) {
    final hit = hitHalf(r, target: target);
    CropHandle? best;
    var bestD = double.infinity;
    for (final h in CropHandle.values.where((h) => h.isCorner)) {
      final c = h.on(r);
      final dx = (p.dx - c.dx).abs(), dy = (p.dy - c.dy).abs();
      if (dx <= hit && dy <= hit) {
        final d = dx * dx + dy * dy;
        if (d < bestD) {
          bestD = d;
          best = h;
        }
      }
    }
    if (best != null) return CropHit(CropHitKind.handle, best);
    final alongX = p.dx >= r.left + hit && p.dx <= r.right - hit;
    final alongY = p.dy >= r.top + hit && p.dy <= r.bottom - hit;
    if (alongX && (p.dy - r.top).abs() <= hit) {
      return const CropHit(CropHitKind.handle, CropHandle.top);
    }
    if (alongX && (p.dy - r.bottom).abs() <= hit) {
      return const CropHit(CropHitKind.handle, CropHandle.bottom);
    }
    if (alongY && (p.dx - r.left).abs() <= hit) {
      return const CropHit(CropHitKind.handle, CropHandle.left);
    }
    if (alongY && (p.dx - r.right).abs() <= hit) {
      return const CropHit(CropHitKind.handle, CropHandle.right);
    }
    return r.contains(p) ? CropHit.inside : CropHit.outside;
  }
}

/// Centre of the loupe for a finger at [finger]: above it (toward the middle of the viewport), flipped below or
/// to the side when there is no room, always inside [viewport] and never within [keepOut] of the finger.
Offset placeLoupe(
  Offset finger,
  Size viewport, {
  double size = 120,
  double gap = 12,
  double keepOut = 56,
  double margin = 8,
}) {
  final r = size / 2;
  final towardCentre = finger.dx <= viewport.width / 2 ? 1.0 : -1.0;
  final above = -(r + keepOut * 0.6 + gap);
  final below = r + keepOut + gap;
  final side = r + keepOut + gap;
  final candidates = <Offset>[
    Offset(towardCentre * (r + gap), above),
    Offset(-towardCentre * (r + gap), above),
    Offset(towardCentre * (r + gap), below),
    Offset(-towardCentre * (r + gap), below),
    Offset(towardCentre * side, 0),
    Offset(-towardCentre * side, 0),
  ];
  final bounds = Rect.fromLTRB(
    margin + r,
    margin + r,
    math.max(margin + r, viewport.width - margin - r),
    math.max(margin + r, viewport.height - margin - r),
  );
  for (final o in candidates) {
    final c = finger + o;
    if (bounds.contains(c) && (c - finger).distance >= r + keepOut * 0.5) {
      return c;
    }
  }
  // Nothing fits (tiny viewport): the first candidate pushed into the viewport.
  final c = finger + candidates.first;
  return Offset(
    c.dx.clamp(bounds.left, bounds.right),
    c.dy.clamp(bounds.top, bounds.bottom),
  );
}
