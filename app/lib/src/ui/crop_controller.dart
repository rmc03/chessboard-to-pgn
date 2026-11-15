// State of the manual crop screen: the decoded image, the selection rectangle (image pixels), the view
// (zoom and pan) and what the gesture layer is doing (the dragged handle, for the loupe). The painters listen
// to it; the gesture layer and the keyboard call its methods. All maths lives in crop_geometry.dart.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'crop_geometry.dart';
import 'tokens.dart';

class CropController extends ChangeNotifier {
  CropController({required this.image, required this.vsync, Rect? initial})
    : imageSize = Size(image.width.toDouble(), image.height.toDouble()) {
    final start = _sanitise(initial);
    _startRect = start.$1;
    _focusStart = start.$2;
    rect = _startRect;
    _anim = AnimationController(vsync: vsync)..addListener(_onTick);
  }

  /// Decoded once; never re-decoded.
  final ui.Image image;
  final Size imageSize;
  final TickerProvider vsync;

  /// Length of animated zooms; zero (set by the page when the system removes animations) means jump.
  Duration animationDuration = Motion.medium;

  late final AnimationController _anim;
  late final Rect _startRect;
  late final bool _focusStart;
  CropView _animFrom = const CropView(1, Offset.zero);
  CropView _animTo = const CropView(1, Offset.zero);

  /// Selection, image pixels.
  late Rect rect;

  CropFrame? frame;
  CropView view = const CropView(1, Offset.zero);

  // ---------------------------------------------------------------------------------------------- drag state

  /// The handle being dragged and where the finger is, while a loupe may be shown (touch only).
  CropHandle? activeHandle;
  Offset? loupeFinger;

  bool get isDragging => activeHandle != null;

  /// Image point the loupe is centred on: the dragged corner, or the point of the dragged edge nearest the finger.
  Offset? get loupeFocus {
    final h = activeHandle, f = loupeFinger, fr = frame;
    if (h == null || f == null || fr == null) return null;
    if (h.isCorner) return h.on(rect);
    final p = view.toImage(f);
    return switch (h) {
      CropHandle.left || CropHandle.right => Offset(
        h.on(rect).dx,
        p.dy.clamp(rect.top, rect.bottom),
      ),
      _ => Offset(p.dx.clamp(rect.left, rect.right), h.on(rect).dy),
    };
  }

  // ---------------------------------------------------------------------------------------------- start

  /// The rectangle to start from and whether the view starts zoomed on it.
  (Rect, bool) _sanitise(Rect? initial) {
    final s = imageSize;
    if (initial != null) {
      final r = initial.intersect(Offset.zero & s);
      final m = CropRectOps.minSide(s);
      if (!r.isEmpty && r.width >= m && r.height >= m) return (r, true);
    }
    // A tall screenshot (a phone page with the board somewhere in the middle): a smaller square, so the
    // whole image stays visible around it and the board is not swallowed by an oversized frame.
    final tall = s.height / s.width > 1.6;
    final side = tall ? 0.4 * s.width : 0.7 * math.min(s.width, s.height);
    return (
      Rect.fromCenter(center: s.center(Offset.zero), width: side, height: side),
      false,
    );
  }

  CropView get _startView {
    final f = frame!;
    return _focusStart ? f.focusOn(_startRect) : f.fit;
  }

  // ---------------------------------------------------------------------------------------------- layout

  /// Called by the canvas with its size. The first call sets the starting view; later ones (window resize,
  /// rotation) keep the zoom factor and the image point at the centre.
  void layout(Size viewport) {
    final old = frame;
    if (old != null && old.viewport == viewport) return;
    final f = CropFrame(image: imageSize, viewport: viewport);
    frame = f;
    view = old == null ? _startView : f.relayout(view, old);
    _anim.stop();
    // Listeners other than the painter (zoom buttons) catch up after this frame.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (_alive) notifyListeners();
    });
  }

  bool _alive = true;

  @override
  void dispose() {
    _alive = false;
    _anim.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------------------------- queries

  double get scale => view.scale;
  double get zoom => frame == null ? 1 : frame!.zoomOf(view);
  bool get canZoomIn => frame != null && view.scale < frame!.maxScale - 1e-6;
  bool get canZoomOut => frame != null && view.scale > frame!.fitScale + 1e-6;

  Offset toScreen(Offset image) => view.toScreen(image);
  Offset toImage(Offset screen) => view.toImage(screen);
  Rect get screenRect => view.rectToScreen(rect);

  CropHit hitTest(Offset screenPoint) =>
      CropRectOps.hitTest(screenPoint, screenRect);

  // ---------------------------------------------------------------------------------------------- view

  void stopAnimation() {
    if (_anim.isAnimating) _anim.stop();
  }

  void _setView(CropView v) {
    final c = frame!.clamp(v);
    if (c == view) return;
    view = c;
    notifyListeners();
  }

  void _animateTo(CropView target) {
    final f = frame!;
    final to = f.clamp(target);
    _anim.stop();
    if (animationDuration == Duration.zero || to == view) {
      _setView(to);
      return;
    }
    _animFrom = view;
    _animTo = to;
    _anim.duration = animationDuration;
    _anim.forward(from: 0);
  }

  void _onTick() {
    final t = Motion.standard.transform(_anim.value);
    view = frame!.lerp(_animFrom, _animTo, t);
    notifyListeners();
  }

  /// Pan so that [offset] is the image origin on screen.
  void panTo(Offset offset) => _setView(CropView(view.scale, offset));

  /// Pinch/pan step: the image point under [from] moves to [to] while the scale is multiplied by [factor].
  void transformBy(Offset from, Offset to, double factor) =>
      _setView(frame!.transform(view, from, to, factor));

  /// Wheel / trackpad: scale around [focal] immediately.
  void zoomAtBy(Offset focal, double factor) =>
      _setView(frame!.zoomAt(view, focal, view.scale * factor));

  /// Trackpad pinch: [start] scaled by [factor] around [focal] and moved by [pan], all since the gesture began.
  void setViewFrom(CropView start, Offset focal, Offset pan, double factor) {
    final f = frame!;
    final sc = (start.scale * factor).clamp(f.fitScale, f.maxScale);
    _setView(CropView(sc, focal + pan - start.toImage(focal) * sc));
  }

  void zoomIn() => _zoomFromCentre(1.6);
  void zoomOut() => _zoomFromCentre(1 / 1.6);

  void _zoomFromCentre(double factor) {
    final f = frame!;
    final c = f.viewport.center(Offset.zero);
    _animateTo(f.zoomAt(view, c, view.scale * factor));
  }

  /// Double tap / double click: in around [focal] when mostly zoomed out, back to the fit view otherwise.
  void toggleZoomAt(Offset focal) {
    final f = frame!;
    if (f.zoomOf(view) < 2) {
      _animateTo(f.zoomAt(view, focal, math.min(f.fitScale * 3, f.maxScale)));
    } else {
      _animateTo(f.fit);
    }
  }

  void fitView() => _animateTo(frame!.fit);

  /// Resets the rectangle and the view to how the screen opened.
  void reset() {
    rect = _startRect;
    activeHandle = null;
    loupeFinger = null;
    _animateTo(_startView);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------------------------- rectangle

  void setRect(Rect r) {
    final c = CropRectOps.clampRect(r, imageSize);
    if (c == rect) return;
    rect = c;
    notifyListeners();
  }

  void beginHandleDrag(CropHandle h, Offset finger, {required bool showLoupe}) {
    activeHandle = h;
    loupeFinger = showLoupe ? finger : null;
    notifyListeners();
  }

  /// [start] resized by [handle] with the finger [deltaScreen] away from where it went down.
  void dragHandle(
    CropHandle handle,
    Rect start,
    Offset deltaScreen,
    Offset finger,
  ) {
    rect = CropRectOps.resize(
      start,
      handle,
      deltaScreen / view.scale,
      imageSize,
    );
    if (loupeFinger != null) loupeFinger = finger;
    notifyListeners();
  }

  void dragMove(Rect start, Offset deltaScreen) {
    rect = CropRectOps.move(start, deltaScreen / view.scale, imageSize);
    notifyListeners();
  }

  void endDrag() {
    if (activeHandle == null && loupeFinger == null) return;
    activeHandle = null;
    loupeFinger = null;
    notifyListeners();
  }

  /// Keyboard: moves the rectangle by [dx], [dy] screen dp.
  void nudge(double dx, double dy) =>
      setRect(CropRectOps.move(rect, Offset(dx, dy) / view.scale, imageSize));

  /// Keyboard: grows (positive) or shrinks the rectangle from its bottom-right corner by screen dp.
  void resizeBy(double dx, double dy) => setRect(
    CropRectOps.resize(
      rect,
      CropHandle.bottomRight,
      Offset(dx, dy) / view.scale,
      imageSize,
    ),
  );

  /// Rectangle as a percentage of the image.
  (int, int) get percent => (
    (rect.width / imageSize.width * 100).round(),
    (rect.height / imageSize.height * 100).round(),
  );
}
