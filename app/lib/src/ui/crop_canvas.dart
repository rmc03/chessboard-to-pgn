// The canvas of the manual crop screen: ONE gesture layer (a raw Listener, no competing detectors) and ONE
// painter (image, dim, grid, outline, handles, loupe).
//
// Gesture arbitration, in one place:
//   * first pointer down is hit-tested once (handle / inside / outside) and remembered;
//   * it only starts to act after a small slop, and acts on the absolute distance from where it went down, so
//     the slop costs no movement;
//   * a second pointer landing switches to zoom/pan for good, and a drag that began less than
//     [_undoWindow] ago is undone (it was the first finger of a two-finger gesture), so the rectangle never
//     jumps; the rectangle is never touched again until every finger is up;
//   * if one of two fingers lifts, the other keeps panning the view.
//   Mouse: left button = same as one finger, wheel = zoom around the pointer, middle button pans.
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'crop_controller.dart';
import 'crop_geometry.dart';

/// Colours of the canvas, resolved from the theme by the page.
class CropPalette {
  const CropPalette({
    required this.canvas,
    required this.scrim,
    required this.accent,
    required this.light,
    required this.dark,
  });

  /// Behind the image.
  final Color canvas;

  /// Dim over what is outside the rectangle.
  final Color scrim;

  /// Colour of the active handle halo.
  final Color accent;

  /// The two strokes of the outline: a white casing ([light]) and a park-bench green core ([dark]), so the
  /// frame shows on white paper (the green) and on dark print (the white).
  final Color light, dark;
}

const double _touchSlop = 6;
const double _mouseSlop = 2;
const Duration _undoWindow = Duration(milliseconds: 200);
const Duration _tapTime = Duration(milliseconds: 300);
const double _loupeSize = 120;

class CropCanvas extends StatefulWidget {
  const CropCanvas({
    super.key,
    required this.controller,
    required this.palette,
    required this.focusNode,
    required this.onAccept,
    this.showFocusRing = false,
  });

  final CropController controller;
  final CropPalette palette;
  final FocusNode focusNode;

  /// Enter pressed on the canvas.
  final VoidCallback onAccept;

  final bool showFocusRing;

  @override
  State<CropCanvas> createState() => _CropCanvasState();
}

enum _Mode { none, pending, handle, move, pan, scale }

class _CropCanvasState extends State<CropCanvas> {
  final Map<int, Offset> _pointers = {};
  _Mode _mode = _Mode.none;
  int? _primary;
  PointerDeviceKind _kind = PointerDeviceKind.touch;
  Offset _downPos = Offset.zero;
  Duration _downTime = Duration.zero;
  Duration _engagedAt = Duration.zero;
  CropHit _hit = CropHit.outside;
  Rect _rectAtDown = Rect.zero;
  Offset _panOrigin = Offset.zero, _panOffset = Offset.zero;
  Offset _lastCentroid = Offset.zero;
  double _lastSpan = 0;
  bool _tapOk = false;
  Duration? _lastTapTime;
  Offset _lastTapPos = Offset.zero;
  CropView _trackpadStart = const CropView(1, Offset.zero);
  MouseCursor _cursor = SystemMouseCursors.grab;

  CropController get c => widget.controller;

  // ------------------------------------------------------------------------------------------- pointers

  void _down(PointerDownEvent e) {
    widget.focusNode.requestFocus();
    c.stopAnimation();
    _pointers[e.pointer] = e.localPosition;
    if (_pointers.length == 1) {
      _primary = e.pointer;
      _kind = e.kind;
      _downPos = e.localPosition;
      _downTime = e.timeStamp;
      _rectAtDown = c.rect;
      final primaryButton =
          e.kind != PointerDeviceKind.mouse || e.buttons == kPrimaryButton;
      _hit = primaryButton ? c.hitTest(e.localPosition) : CropHit.outside;
      _mode = _Mode.pending;
      _tapOk = primaryButton;
      _setCursor(_cursorFor(_hit));
    } else {
      _beginScale(e.timeStamp);
    }
  }

  void _move(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;
    final p = e.localPosition;
    switch (_mode) {
      case _Mode.pending:
        final slop = _kind == PointerDeviceKind.mouse ? _mouseSlop : _touchSlop;
        if (e.pointer == _primary && (p - _downPos).distance > slop) {
          _engage(e.timeStamp);
          _update(p);
        }
      case _Mode.handle || _Mode.move || _Mode.pan:
        if (e.pointer == _primary) _update(p);
      case _Mode.scale:
        _updateScale();
      case _Mode.none:
        break;
    }
  }

  void _engage(Duration now) {
    _tapOk = false;
    _engagedAt = now;
    switch (_hit.kind) {
      case CropHitKind.handle:
        _mode = _Mode.handle;
        c.beginHandleDrag(
          _hit.handle!,
          _downPos,
          showLoupe: _kind != PointerDeviceKind.mouse,
        );
      case CropHitKind.inside:
        _mode = _Mode.move;
      case CropHitKind.outside:
        _mode = _Mode.pan;
        _panOrigin = _downPos;
        _panOffset = c.view.offset;
        _setCursor(SystemMouseCursors.grabbing);
    }
  }

  void _update(Offset p) {
    switch (_mode) {
      case _Mode.handle:
        c.dragHandle(_hit.handle!, _rectAtDown, p - _downPos, p);
      case _Mode.move:
        c.dragMove(_rectAtDown, p - _downPos);
      case _Mode.pan:
        c.panTo(_panOffset + (p - _panOrigin));
      default:
        break;
    }
  }

  void _beginScale(Duration now) {
    if ((_mode == _Mode.handle || _mode == _Mode.move) &&
        now - _engagedAt < _undoWindow) {
      c.setRect(_rectAtDown);
    }
    c.endDrag();
    _mode = _Mode.scale;
    _tapOk = false;
    _resetScale();
  }

  void _resetScale() {
    final pts = _pointers.values.toList();
    _lastCentroid = _centroid(pts);
    _lastSpan = _span(pts, _lastCentroid);
  }

  static Offset _centroid(List<Offset> pts) =>
      pts.fold(Offset.zero, (a, b) => a + b) / pts.length.toDouble();

  static double _span(List<Offset> pts, Offset centre) =>
      pts.fold<double>(0, (a, b) => a + (b - centre).distance) / pts.length;

  void _updateScale() {
    final pts = _pointers.values.toList();
    if (pts.length < 2) return;
    final centre = _centroid(pts);
    final span = _span(pts, centre);
    final factor = _lastSpan > 4 && span > 4 ? span / _lastSpan : 1.0;
    c.transformBy(_lastCentroid, centre, factor);
    _lastCentroid = centre;
    _lastSpan = span;
  }

  void _up(PointerUpEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    final p = e.localPosition;
    _pointers.remove(e.pointer);
    if (_mode == _Mode.scale) {
      if (_pointers.length >= 2) {
        _resetScale();
      } else if (_pointers.length == 1) {
        // The remaining finger keeps panning the view; it never moves the rectangle.
        _primary = _pointers.keys.first;
        _mode = _Mode.pan;
        _panOrigin = _pointers.values.first;
        _panOffset = c.view.offset;
        _hit = CropHit.outside;
      } else {
        _finish();
      }
      return;
    }
    if (e.pointer != _primary) return;
    if (_mode == _Mode.pending &&
        _tapOk &&
        e.timeStamp - _downTime < _tapTime) {
      _tap(p, e.timeStamp);
    }
    _finish();
  }

  void _cancel(PointerCancelEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers.remove(e.pointer);
    if (_mode == _Mode.handle || _mode == _Mode.move) c.setRect(_rectAtDown);
    if (_pointers.isEmpty) _finish();
  }

  void _finish() {
    _pointers.clear();
    _mode = _Mode.none;
    _primary = null;
    c.endDrag();
    _setCursor(SystemMouseCursors.grab);
  }

  void _tap(Offset p, Duration at) {
    final last = _lastTapTime;
    if (last != null &&
        at - last < _tapTime &&
        (p - _lastTapPos).distance < 48) {
      _lastTapTime = null;
      c.toggleZoomAt(p);
    } else {
      _lastTapTime = at;
      _lastTapPos = p;
    }
  }

  // ------------------------------------------------------------------------------------ wheel, trackpad

  void _signal(PointerSignalEvent e) {
    if (e is! PointerScrollEvent) return;
    GestureBinding.instance.pointerSignalResolver.register(e, (event) {
      final s = event as PointerScrollEvent;
      c.stopAnimation();
      c.zoomAtBy(s.localPosition, math.exp(-s.scrollDelta.dy / 400));
    });
  }

  void _panZoomStart(PointerPanZoomStartEvent e) {
    c.stopAnimation();
    _trackpadStart = c.view;
  }

  void _panZoomUpdate(PointerPanZoomUpdateEvent e) =>
      c.setViewFrom(_trackpadStart, e.localPosition, e.localPan, e.scale);

  // ------------------------------------------------------------------------------------------- cursor

  void _hover(PointerHoverEvent e) {
    if (_mode != _Mode.none) return;
    _setCursor(_cursorFor(c.hitTest(e.localPosition)));
  }

  void _setCursor(MouseCursor m) {
    if (m == _cursor) return;
    setState(() => _cursor = m);
  }

  MouseCursor _cursorFor(CropHit h) {
    switch (h.kind) {
      case CropHitKind.inside:
        return SystemMouseCursors.move;
      case CropHitKind.outside:
        return SystemMouseCursors.grab;
      case CropHitKind.handle:
        return switch (h.handle!) {
          CropHandle.topLeft ||
          CropHandle.bottomRight => SystemMouseCursors.resizeUpLeftDownRight,
          CropHandle.topRight ||
          CropHandle.bottomLeft => SystemMouseCursors.resizeUpRightDownLeft,
          CropHandle.top ||
          CropHandle.bottom => SystemMouseCursors.resizeUpDown,
          CropHandle.left ||
          CropHandle.right => SystemMouseCursors.resizeLeftRight,
        };
    }
  }

  // ------------------------------------------------------------------------------------------- keyboard

  KeyEventResult _key(FocusNode node, KeyEvent e) {
    if (e is KeyUpEvent) return KeyEventResult.ignored;
    final k = e.logicalKey;
    final kb = HardwareKeyboard.instance;
    final arrow = switch (k) {
      LogicalKeyboardKey.arrowLeft => const Offset(-1, 0),
      LogicalKeyboardKey.arrowRight => const Offset(1, 0),
      LogicalKeyboardKey.arrowUp => const Offset(0, -1),
      LogicalKeyboardKey.arrowDown => const Offset(0, 1),
      _ => null,
    };
    if (arrow != null && c.frame != null) {
      final step = kb.isShiftPressed ? 16.0 : 2.0;
      final d = arrow * step;
      if (kb.isControlPressed) {
        c.resizeBy(d.dx, d.dy);
      } else {
        c.nudge(d.dx, d.dy);
      }
      return KeyEventResult.handled;
    }
    if (c.frame == null) return KeyEventResult.ignored;
    if (k == LogicalKeyboardKey.add ||
        k == LogicalKeyboardKey.numpadAdd ||
        k == LogicalKeyboardKey.equal) {
      c.zoomIn();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.minus ||
        k == LogicalKeyboardKey.numpadSubtract) {
      c.zoomOut();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.digit0 || k == LogicalKeyboardKey.numpad0) {
      c.fitView();
      return KeyEventResult.handled;
    }
    if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
      widget.onAccept();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  // ------------------------------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      autofocus: true,
      onKeyEvent: _key,
      child: MouseRegion(
        cursor: _cursor,
        onHover: _hover,
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: _down,
          onPointerMove: _move,
          onPointerUp: _up,
          onPointerCancel: _cancel,
          onPointerSignal: _signal,
          onPointerPanZoomStart: _panZoomStart,
          onPointerPanZoomUpdate: _panZoomUpdate,
          child: LayoutBuilder(
            builder: (context, box) {
              c.layout(box.biggest);
              return CustomPaint(
                size: box.biggest,
                painter: _CropPainter(
                  c,
                  widget.palette,
                  MediaQuery.devicePixelRatioOf(context),
                ),
                foregroundPainter: widget.showFocusRing
                    ? _FocusRingPainter(widget.palette.light)
                    : null,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FocusRingPainter extends CustomPainter {
  _FocusRingPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      (Offset.zero & size).deflate(1.5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_FocusRingPainter old) => old.color != color;
}

// ---------------------------------------------------------------------------------------------- painting

/// Sampling for an image drawn at [physicalScale] device px per image px: mip-mapped when shrunk, smooth when
/// slightly magnified, nearest (crisp pixels) when far in.
FilterQuality cropFilterQuality(double physicalScale) {
  if (physicalScale < 1) return FilterQuality.medium;
  if (physicalScale < 3) return FilterQuality.low;
  return FilterQuality.none;
}

class _CropPainter extends CustomPainter {
  _CropPainter(this.c, this.p, this.dpr) : super(repaint: c);

  final CropController c;
  final CropPalette p;
  final double dpr;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    canvas.drawRect(bounds, Paint()..color = p.canvas);
    if (c.frame == null) return;
    canvas.save();
    canvas.clipRect(bounds);

    final view = c.view;
    final imageScreen = view.rectToScreen(Offset.zero & c.imageSize);
    _drawImage(canvas, bounds, view.scale, view.offset);

    final sel = c.screenRect;
    _paintSelection(canvas, imageScreen.intersect(bounds), sel, grid: true);
    _paintHandles(canvas, sel);
    canvas.restore();

    final focus = c.loupeFocus;
    final finger = c.loupeFinger;
    if (focus != null && finger != null) {
      _paintLoupe(canvas, size, focus, finger);
    }
  }

  /// The visible part of the image under the transform `screen = image * scale + offset`, clipped to [clip].
  void _drawImage(Canvas canvas, Rect clip, double scale, Offset offset) {
    final imageRect = Offset.zero & c.imageSize;
    final visible = Rect.fromPoints(
      (clip.topLeft - offset) / scale,
      (clip.bottomRight - offset) / scale,
    ).intersect(imageRect);
    if (visible.isEmpty) return;
    final src = visible.inflate(1).intersect(imageRect);
    final dst = Rect.fromPoints(
      src.topLeft * scale + offset,
      src.bottomRight * scale + offset,
    );
    canvas.drawImageRect(
      c.image,
      src,
      dst,
      Paint()
        ..filterQuality = cropFilterQuality(scale * dpr)
        ..isAntiAlias = false,
    );
  }

  void _paintSelection(
    Canvas canvas,
    Rect imageScreen,
    Rect sel, {
    required bool grid,
  }) {
    // Dim everything of the image outside the rectangle.
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(imageScreen)
        ..addRect(sel.intersect(imageScreen)),
      Paint()..color = p.scrim,
    );
    if (grid && sel.shortestSide / 8 >= 6) {
      final cell = Offset(sel.width / 8, sel.height / 8);
      final lines = Path();
      for (var i = 1; i < 8; i++) {
        lines
          ..moveTo(sel.left + cell.dx * i, sel.top)
          ..lineTo(sel.left + cell.dx * i, sel.bottom)
          ..moveTo(sel.left, sel.top + cell.dy * i)
          ..lineTo(sel.right, sel.top + cell.dy * i);
      }
      canvas.drawPath(lines, _stroke(p.light.withValues(alpha: 0.45), 2));
      canvas.drawPath(lines, _stroke(p.dark.withValues(alpha: 0.7), 1));
    }
    // Double stroke: white casing + green core, readable on white paper and on dark print.
    canvas.drawRect(sel, _stroke(p.light, 4.5));
    canvas.drawRect(sel, _stroke(p.dark, 2));
  }

  static Paint _stroke(
    Color color,
    double width, {
    StrokeCap cap = StrokeCap.butt,
  }) => Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = cap
    ..strokeJoin = StrokeJoin.round
    ..color = color;

  static const double _arm = 22;
  static const double _pill = 28;

  void _paintHandles(Canvas canvas, Rect sel) {
    final active = c.activeHandle;
    final roomX = sel.width >= 2 * _arm + _pill + 8;
    final roomY = sel.height >= 2 * _arm + _pill + 8;
    for (final h in CropHandle.values) {
      if (!h.isCorner) {
        final horizontal = h == CropHandle.top || h == CropHandle.bottom;
        if (horizontal ? !roomX : !roomY) continue;
      }
      final at = h.on(sel);
      if (h == active) {
        canvas.drawCircle(
          at,
          26,
          Paint()..color = p.accent.withValues(alpha: 0.38),
        );
        canvas.drawCircle(at, 26, _stroke(p.light, 2));
      }
      final path = Path();
      if (h.isCorner) {
        final sx = h.movesLeft ? 1.0 : -1.0, sy = h.movesTop ? 1.0 : -1.0;
        path
          ..moveTo(at.dx + sx * _arm, at.dy)
          ..lineTo(at.dx, at.dy)
          ..lineTo(at.dx, at.dy + sy * _arm);
      } else if (h == CropHandle.top || h == CropHandle.bottom) {
        path
          ..moveTo(at.dx - _pill / 2, at.dy)
          ..lineTo(at.dx + _pill / 2, at.dy);
      } else {
        path
          ..moveTo(at.dx, at.dy - _pill / 2)
          ..lineTo(at.dx, at.dy + _pill / 2);
      }
      canvas.drawPath(path, _stroke(p.light, 7, cap: StrokeCap.round));
      canvas.drawPath(path, _stroke(p.dark, 3.5, cap: StrokeCap.round));
    }
  }

  void _paintLoupe(Canvas canvas, Size size, Offset focus, Offset finger) {
    final centre = placeLoupe(finger, size, size: _loupeSize);
    final r = _loupeSize / 2;
    final s = math.min(math.max(c.scale * 2.5, 2.5), 12.0);
    // The view itself is already magnified enough: no loupe.
    if (s < c.scale * 1.4) return;
    canvas.save();
    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: centre, radius: r)),
    );
    canvas.drawRect(
      Rect.fromCircle(center: centre, radius: r),
      Paint()..color = p.canvas,
    );
    final offset = centre - focus * s;
    final loupeBounds = Rect.fromCircle(center: centre, radius: r);
    _drawImage(canvas, loupeBounds, s, offset);
    final loupeView = CropView(s, offset);
    _paintSelection(
      canvas,
      loupeView.rectToScreen(Offset.zero & c.imageSize).intersect(loupeBounds),
      loupeView.rectToScreen(c.rect),
      grid: false,
    );
    canvas.restore();
    canvas.drawCircle(centre, r, _stroke(p.light, 5));
    canvas.drawCircle(centre, r, _stroke(p.dark, 2.5));
  }

  @override
  bool shouldRepaint(_CropPainter old) =>
      old.c != c || old.p != p || old.dpr != dpr;
}
