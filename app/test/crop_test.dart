import 'package:chessboard_pgn/src/crop_page.dart';
import 'package:chessboard_pgn/src/locate.dart';
import 'package:chessboard_pgn/src/ui/crop_canvas.dart';
import 'package:chessboard_pgn/src/ui/crop_controller.dart';
import 'package:chessboard_pgn/src/ui/crop_geometry.dart';
import 'package:chessboard_pgn/src/ui/icons.dart';
import 'package:chessboard_pgn/src/ui/plate.dart';
import 'package:chessboard_pgn/src/ui/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';

/// A known image: 400 x 400 px. On the 800 x 700 test window the canvas is about 800 x 570 dp, so the fit
/// scale is 1.28 dp per image px and the whole image is visible.
final png = Uint8List.fromList(
  img.encodePng(img.Image(width: 400, height: 400)),
);

class Opened {
  Box? result;
  bool closed = false;
}

const canvasKey = ValueKey('crop-canvas');

/// Opens the crop page from a button and waits for the image to decode.
Future<Opened> openCrop(
  WidgetTester tester, {
  Box? initial,
  Size window = const Size(800, 700),
  Uint8List? bytes,
  double textScale = 1,
  bool disableAnimations = false,
}) async {
  tester.view.physicalSize = window;
  tester.view.devicePixelRatio = 1;
  tester.platformDispatcher.textScaleFactorTestValue = textScale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
  });
  final o = Opened();
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(disableAnimations: disableAnimations),
        child: child!,
      ),
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            o.result = await showCropPage(
              context,
              bytes ?? png,
              initial: initial,
            );
            o.closed = true;
          },
          child: const Text('abrir'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  // Image decoding is real async work, outside the fake clock.
  for (var i = 0; i < 40 && find.byType(CropCanvas).evaluate().isEmpty; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
  }
  await tester.pumpAndSettle();
  return o;
}

/// A finger with explicit event timestamps (milliseconds), sent straight to the binding.
class Finger {
  Finger(this.tester, int id) : _p = TestPointer(id);
  final WidgetTester tester;
  final TestPointer _p;

  Future<void> down(Offset p, int ms) => tester.sendEventToBinding(
    _p.down(p, timeStamp: Duration(milliseconds: ms)),
  );
  Future<void> move(Offset by, int ms) => tester.sendEventToBinding(
    _p.move(_p.location! + by, timeStamp: Duration(milliseconds: ms)),
  );
  Future<void> up(int ms) =>
      tester.sendEventToBinding(_p.up(timeStamp: Duration(milliseconds: ms)));
}

CropController ctrl(WidgetTester tester) =>
    tester.widget<CropCanvas>(find.byType(CropCanvas)).controller;

Offset origin(WidgetTester tester) => tester.getTopLeft(find.byKey(canvasKey));

/// Global position of an image point.
Offset at(WidgetTester tester, Offset imagePoint) =>
    origin(tester) + ctrl(tester).toScreen(imagePoint);

/// Global position of a handle of the current rectangle.
Offset handleAt(WidgetTester tester, CropHandle h) =>
    at(tester, h.on(ctrl(tester).rect));

Future<void> accept(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('crop-accept')));
  await tester.pumpAndSettle();
}

void main() {
  group('geometry', () {
    const frame = CropFrame(image: Size(1080, 2400), viewport: Size(412, 700));

    test('image <-> screen round-trips at several zoom and pan states', () {
      final views = [
        frame.fit,
        frame.zoomAt(frame.fit, const Offset(100, 200), frame.fitScale * 2),
        frame.zoomAt(frame.fit, const Offset(300, 500), frame.fitScale * 5),
        frame.centreOn(const Offset(900, 300), frame.maxScale),
        CropView(0.8, const Offset(-120, -340)),
      ];
      for (final v in views) {
        for (final p in const [
          Offset(0, 0),
          Offset(540, 1200),
          Offset(1080, 2400),
          Offset(33.5, 77.25),
        ]) {
          final back = v.toImage(v.toScreen(p));
          expect(back.dx, closeTo(p.dx, 1e-9));
          expect(back.dy, closeTo(p.dy, 1e-9));
        }
        final r = const Rect.fromLTRB(100, 200, 500, 900);
        final rr = v.rectToImage(v.rectToScreen(r));
        expect(rr.left, closeTo(r.left, 1e-9));
        expect(rr.bottom, closeTo(r.bottom, 1e-9));
      }
    });

    test('zoom keeps the point under the focal and stays within limits', () {
      final v = frame.zoomAt(
        frame.fit,
        const Offset(206, 350),
        frame.fitScale * 3,
      );
      expect(v.scale, closeTo(frame.fitScale * 3, 1e-9));
      final p = frame.fit.toImage(const Offset(206, 350));
      expect(v.toScreen(p).dx, closeTo(206, 1e-6));
      expect(v.toScreen(p).dy, closeTo(350, 1e-6));
      expect(frame.zoomAt(v, Offset.zero, 1e9).scale, frame.maxScale);
      expect(frame.zoomAt(v, Offset.zero, 1e-9).scale, frame.fitScale);
      expect(frame.maxScale, greaterThanOrEqualTo(frame.fitScale * 8));
    });

    test('pan can never lose the image', () {
      final zoomed = frame.centreOn(
        const Offset(540, 1200),
        frame.fitScale * 4,
      );
      for (final o in const [
        Offset(1e6, 1e6),
        Offset(-1e6, -1e6),
        Offset(1e6, -1e6),
      ]) {
        final v = frame.clamp(CropView(zoomed.scale, o));
        final shown = v.rectToScreen(Offset.zero & frame.image);
        // At least `viewport - pad` of the image remains in view on each axis.
        expect(
          shown.right,
          greaterThanOrEqualTo(frame.viewport.width - frame.pad - 1e-9),
        );
        expect(shown.left, lessThanOrEqualTo(frame.pad + 1e-9));
        expect(
          shown.bottom,
          greaterThanOrEqualTo(frame.viewport.height - frame.pad - 1e-9),
        );
        expect(shown.top, lessThanOrEqualTo(frame.pad + 1e-9));
      }
    });

    test('the fit view shows the whole image, centred', () {
      final shown = frame.fit.rectToScreen(Offset.zero & frame.image);
      expect(shown.left, greaterThanOrEqualTo(frame.pad - 1e-9));
      expect(
        shown.right,
        lessThanOrEqualTo(frame.viewport.width - frame.pad + 1e-9),
      );
      expect(shown.top, greaterThanOrEqualTo(frame.pad - 1e-9));
      expect(
        shown.bottom,
        lessThanOrEqualTo(frame.viewport.height - frame.pad + 1e-9),
      );
      expect(shown.center.dx, closeTo(frame.viewport.width / 2, 1e-9));
    });

    test('hit test: corners over edges over inside over outside', () {
      const r = Rect.fromLTRB(100, 100, 300, 300);
      CropHit hit(double x, double y) => CropRectOps.hitTest(Offset(x, y), r);
      expect(
        hit(100, 100),
        const CropHit(CropHitKind.handle, CropHandle.topLeft),
      );
      expect(
        hit(120, 280),
        const CropHit(CropHitKind.handle, CropHandle.bottomLeft),
      );
      expect(
        hit(300, 90),
        const CropHit(CropHitKind.handle, CropHandle.topRight),
      );
      expect(hit(200, 100), const CropHit(CropHitKind.handle, CropHandle.top));
      expect(
        hit(200, 320),
        const CropHit(CropHitKind.handle, CropHandle.bottom),
      );
      expect(hit(80, 200), const CropHit(CropHitKind.handle, CropHandle.left));
      expect(
        hit(310, 200),
        const CropHit(CropHitKind.handle, CropHandle.right),
      );
      expect(hit(200, 200), CropHit.inside);
      expect(hit(50, 200), CropHit.outside);
      expect(hit(200, 400), CropHit.outside);
      // 48 dp hit areas: 24 dp away still grabs, 30 dp does not.
      expect(hit(300 + 24, 300 + 24).kind, CropHitKind.handle);
      expect(hit(300 + 30, 300 + 30).kind, CropHitKind.outside);
    });

    test('a tiny rectangle keeps an inside to move', () {
      const r = Rect.fromLTRB(100, 100, 150, 150);
      expect(CropRectOps.hitTest(const Offset(125, 125), r), CropHit.inside);
    });

    test('the loupe is on screen and never under the finger', () {
      const vp = Size(412, 700);
      for (final f in const [
        Offset(10, 10),
        Offset(400, 10),
        Offset(10, 690),
        Offset(400, 690),
        Offset(206, 350),
        Offset(206, 5),
        Offset(5, 350),
      ]) {
        final c = placeLoupe(f, vp);
        expect(c.dx - 60, greaterThanOrEqualTo(0));
        expect(c.dx + 60, lessThanOrEqualTo(vp.width));
        expect(c.dy - 60, greaterThanOrEqualTo(0));
        expect(c.dy + 60, lessThanOrEqualTo(vp.height));
        expect((c - f).distance, greaterThan(60 + 24), reason: 'finger $f');
      }
    });
  });

  group('screen', () {
    testWidgets('chrome: title, hint, actions, close', (tester) async {
      await openCrop(tester);
      expect(find.text('Recortar tablero'), findsOneWidget);
      expect(
        find.text('Usa la rueda o los botones para ampliar.'),
        findsOneWidget,
      );
      expect(
        find.text('Arrastra las esquinas para encerrar el tablero.'),
        findsOneWidget,
      );
      expect(find.text('Restablecer'), findsOneWidget);
      expect(find.text('Leer este tablero'), findsOneWidget);
      expect(find.byTooltip('Cerrar'), findsOneWidget);
      expect(
        find.byWidgetPredicate((w) => w is AppIcon && w.icon == AppIcons.close),
        findsOneWidget,
      );
    });

    testWidgets(
      'a 1080 x 2400 screenshot fits initially, rectangle 40 % of the width, centred',
      (tester) async {
        final big = Uint8List.fromList(
          img.encodePng(img.Image(width: 1080, height: 2400)),
        );
        await openCrop(tester, window: const Size(412, 915), bytes: big);
        final c = ctrl(tester);
        final size = tester.getSize(find.byKey(canvasKey));
        final shown = c.view.rectToScreen(Offset.zero & c.imageSize);
        expect(shown.left, greaterThanOrEqualTo(0));
        expect(shown.top, greaterThanOrEqualTo(0));
        expect(shown.right, lessThanOrEqualTo(size.width));
        expect(shown.bottom, lessThanOrEqualTo(size.height));
        expect(c.view.scale, closeTo(c.frame!.fitScale, 1e-9));
        expect(c.rect.width, closeTo(432, 1e-6));
        expect(c.rect.height, closeTo(432, 1e-6));
        expect(c.rect.center, const Offset(540, 1200));
      },
    );

    testWidgets(
      'initial is honoured, the view zooms on it, and Leer returns it unchanged',
      (tester) async {
        const initial = Box(100.5, 120.25, 220.5, 200.75);
        final o = await openCrop(tester, initial: initial);
        final c = ctrl(tester);
        final size = tester.getSize(find.byKey(canvasKey));
        final sel = c.screenRect;
        final fill = (sel.width / size.width > sel.height / size.height)
            ? sel.width / size.width
            : sel.height / size.height;
        expect(fill, inInclusiveRange(0.6, 0.7));
        expect(sel.center.dx, closeTo(size.width / 2, 1));
        await accept(tester);
        expect(o.result!.x0, initial.x0);
        expect(o.result!.y0, initial.y0);
        expect(o.result!.x1, initial.x1);
        expect(o.result!.y1, initial.y1);
      },
    );

    testWidgets('a nonsensical initial falls back to the default square', (
      tester,
    ) async {
      await openCrop(tester, initial: const Box(5000, 5000, 5100, 5100));
      expect(ctrl(tester).rect.width, closeTo(280, 1e-6));
    });

    testWidgets(
      'Plaza chrome: AppIcons on the zoom buttons, a plate for "Leer este tablero", basalt behind the picture',
      (tester) async {
        await openCrop(tester);
        for (final (key, icon) in [
          ('zoom-in', AppIcons.zoomIn),
          ('zoom-out', AppIcons.zoomOut),
          ('zoom-fit', AppIcons.fitAll),
        ]) {
          expect(
            find.descendant(
              of: find.byKey(ValueKey(key)),
              matching: find.byWidgetPredicate(
                (w) => w is AppIcon && w.icon == icon,
              ),
            ),
            findsOneWidget,
            reason: key,
          );
        }
        final accept = tester.widget<FilledButton>(
          find.byKey(const ValueKey('crop-accept')),
        );
        expect(accept.style!.shape!.resolve(const {}), isA<PlateBorder>());
        final app = AppTheme.of(tester.element(find.byType(CropPage)));
        final palette = tester
            .widget<CropCanvas>(find.byType(CropCanvas))
            .palette;
        expect(palette.canvas, app.stage);
        expect(palette.dark, app.shell, reason: 'green core of the frame');
        expect(palette.light, app.onPlate, reason: 'white casing of the frame');
      },
    );

    testWidgets('close returns null (X, Escape and system back)', (
      tester,
    ) async {
      var o = await openCrop(tester);
      await tester.tap(find.byTooltip('Cerrar'));
      await tester.pumpAndSettle();
      expect(o.closed, isTrue);
      expect(o.result, isNull);

      o = await openCrop(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(o.closed, isTrue);
      expect(o.result, isNull);

      o = await openCrop(tester);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(o.closed, isTrue);
      expect(o.result, isNull);
    });
  });

  group('handles', () {
    // A 100 px square, centred: (150,150)-(250,250).
    const start = Box(150, 150, 250, 250);

    for (final zoom in [1.0, 3.0]) {
      for (final h in CropHandle.values) {
        testWidgets(
          'dragging $h at zoom $zoom changes the box by the expected image delta',
          (tester) async {
            final o = await openCrop(tester, initial: start);
            final c = ctrl(tester);
            // Normalise the view: fit, then zoom around the rectangle centre.
            c.fitView();
            await tester.pumpAndSettle();
            if (zoom != 1) {
              c.zoomAtBy(c.toScreen(c.rect.center), zoom);
              await tester.pump();
            }
            final s = c.scale;
            final from = handleAt(tester, h);
            const delta = Offset(20, 14); // screen dp
            await tester.dragFrom(from, delta);
            await tester.pump();
            final dx = delta.dx / s, dy = delta.dy / s;
            final r = c.rect;
            expect(r.left, closeTo(150 + (h.movesLeft ? dx : 0), 1e-6));
            expect(r.right, closeTo(250 + (h.movesRight ? dx : 0), 1e-6));
            expect(r.top, closeTo(150 + (h.movesTop ? dy : 0), 1e-6));
            expect(r.bottom, closeTo(250 + (h.movesBottom ? dy : 0), 1e-6));
            await accept(tester);
            expect(o.result!.x1, closeTo(r.right, 1e-6));
          },
        );
      }
    }

    testWidgets(
      'hit areas are at least 48 dp at any zoom (24 dp away from a corner still grabs)',
      (tester) async {
        await openCrop(tester, initial: start);
        final c = ctrl(tester);
        for (final z in [1.0, 4.0]) {
          c.fitView();
          await tester.pumpAndSettle();
          c.zoomAtBy(c.toScreen(c.rect.center), z);
          await tester.pump();
          final corner = c.screenRect.bottomRight;
          expect(
            c.hitTest(corner + const Offset(22, 22)).handle,
            CropHandle.bottomRight,
          );
          expect(
            c.hitTest(corner + const Offset(-22, 22)).kind,
            isNot(CropHitKind.outside),
          );
        }
      },
    );

    testWidgets('dragging inside moves the rectangle', (tester) async {
      await openCrop(tester, initial: start);
      final c = ctrl(tester);
      c.fitView();
      await tester.pumpAndSettle();
      final s = c.scale;
      await tester.dragFrom(
        at(tester, const Offset(200, 200)),
        const Offset(-30, 18),
      );
      await tester.pump();
      expect(c.rect.left, closeTo(150 - 30 / s, 1e-6));
      expect(c.rect.top, closeTo(150 + 18 / s, 1e-6));
      expect(c.rect.width, closeTo(100, 1e-6));
      expect(c.rect.height, closeTo(100, 1e-6));
    });

    testWidgets('moving and resizing clamp at the image borders', (
      tester,
    ) async {
      await openCrop(tester, initial: start);
      final c = ctrl(tester);
      c.fitView();
      await tester.pumpAndSettle();
      await tester.dragFrom(
        at(tester, const Offset(200, 200)),
        const Offset(-3000, -3000),
      );
      await tester.pump();
      expect(c.rect, const Rect.fromLTRB(0, 0, 100, 100));
      await tester.dragFrom(
        handleAt(tester, CropHandle.bottomRight),
        const Offset(5000, 5000),
      );
      await tester.pump();
      expect(c.rect, const Rect.fromLTRB(0, 0, 400, 400));
      await tester.dragFrom(
        handleAt(tester, CropHandle.topLeft),
        const Offset(-900, -900),
      );
      await tester.pump();
      expect(c.rect, const Rect.fromLTRB(0, 0, 400, 400));
    });

    testWidgets('the rectangle cannot collapse or invert', (tester) async {
      await openCrop(tester, initial: start);
      final c = ctrl(tester);
      c.fitView();
      await tester.pumpAndSettle();
      await tester.dragFrom(
        handleAt(tester, CropHandle.bottomRight),
        const Offset(-2000, -2000),
      );
      await tester.pump();
      expect(c.rect.width, 24);
      expect(c.rect.height, 24);
      expect(c.rect.left, 150);
      await tester.dragFrom(
        handleAt(tester, CropHandle.left),
        const Offset(2000, 0),
      );
      await tester.pump();
      expect(c.rect.width, 24);
      expect(c.rect.right, 174);
    });

    testWidgets(
      'dragging outside pans when zoomed and never moves the rectangle',
      (tester) async {
        await openCrop(tester, initial: start);
        final c = ctrl(tester);
        final rect0 = c.rect;
        final off0 = c.view.offset;
        // Top-left corner of the canvas is well away from the (zoomed) rectangle.
        await tester.dragFrom(
          origin(tester) + const Offset(30, 30),
          const Offset(15, 9),
        );
        await tester.pump();
        expect(c.rect, rect0);
        expect(c.view.offset.dx, isNot(off0.dx));
      },
    );

    testWidgets(
      'a loupe shows while a corner is dragged by touch, not by mouse',
      (tester) async {
        await openCrop(tester, initial: start);
        final c = ctrl(tester);
        c.fitView();
        await tester.pumpAndSettle();
        final g = await tester.startGesture(
          handleAt(tester, CropHandle.topLeft),
        );
        await g.moveBy(const Offset(10, 10));
        await tester.pump();
        expect(c.loupeFinger, isNotNull);
        expect(c.loupeFocus, c.rect.topLeft);
        await g.up();
        await tester.pump();
        expect(c.loupeFinger, isNull);

        final m = await tester.startGesture(
          handleAt(tester, CropHandle.topLeft),
          kind: PointerDeviceKind.mouse,
          buttons: kPrimaryButton,
        );
        await m.moveBy(const Offset(10, 10));
        await tester.pump();
        expect(c.activeHandle, CropHandle.topLeft);
        expect(c.loupeFinger, isNull);
        await m.up();
      },
    );
  });

  group('zoom and pan', () {
    testWidgets(
      'double tap zooms in on the tapped point and a second one zooms back out',
      (tester) async {
        await openCrop(tester, initial: const Box(150, 150, 250, 250));
        final c = ctrl(tester);
        c.fitView();
        await tester.pumpAndSettle();
        final fit = c.scale;
        // A point outside the rectangle, on the image.
        final local = const Offset(280, 200);
        final p = origin(tester) + local;
        final under = c.toImage(local);
        await tester.tapAt(p);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tapAt(p);
        await tester.pumpAndSettle();
        expect(c.scale, closeTo(fit * 3, 1e-6));
        final after = c.toScreen(under);
        expect(after.dx, closeTo(local.dx, 0.5));
        expect(after.dy, closeTo(local.dy, 0.5));
        expect(
          c.rect,
          const Rect.fromLTRB(150, 150, 250, 250),
          reason: 'a tap never moves the rectangle',
        );

        await tester.tapAt(p);
        await tester.pump(const Duration(milliseconds: 100));
        await tester.tapAt(p);
        await tester.pumpAndSettle();
        expect(c.scale, closeTo(fit, 1e-6));
      },
    );

    testWidgets('with animations removed the double tap zoom is immediate', (
      tester,
    ) async {
      await openCrop(tester, disableAnimations: true);
      final c = ctrl(tester);
      final fit = c.scale;
      final p = origin(tester) + const Offset(300, 200);
      await tester.tapAt(p);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tapAt(p);
      await tester.pump(); // a single frame, no settling
      expect(c.scale, closeTo(fit * 3, 1e-6));
    });

    testWidgets('mouse wheel zooms around the pointer', (tester) async {
      await openCrop(tester, initial: const Box(150, 150, 250, 250));
      final c = ctrl(tester);
      c.fitView();
      await tester.pumpAndSettle();
      final fit = c.scale;
      final local = const Offset(420, 280);
      final under = c.toImage(local);
      final pointer = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(pointer.hover(origin(tester) + local));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, -600)));
      await tester.pump();
      expect(c.scale, greaterThan(fit * 1.4));
      final after = c.toScreen(under);
      expect(after.dx, closeTo(local.dx, 0.5));
      expect(after.dy, closeTo(local.dy, 0.5));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 5000)));
      await tester.pump();
      expect(
        c.scale,
        closeTo(fit, 1e-9),
        reason: 'cannot zoom out past the whole image',
      );
    });

    testWidgets('zoom reaches at least 8x the fit and stops', (tester) async {
      await openCrop(tester);
      final c = ctrl(tester);
      final fit = c.scale;
      c.zoomAtBy(const Offset(200, 200), 1e6);
      await tester.pump();
      expect(c.scale, greaterThanOrEqualTo(fit * 8));
      expect(c.canZoomIn, isFalse);
    });

    testWidgets('two fingers zoom and pan and never change the rectangle', (
      tester,
    ) async {
      await openCrop(tester, initial: const Box(150, 150, 250, 250));
      final c = ctrl(tester);
      c.fitView();
      await tester.pumpAndSettle();
      final rect0 = c.rect;
      final scale0 = c.scale;
      // Both fingers land inside the rectangle, one right on a corner handle, and spread apart.
      final a = Finger(tester, 1), b = Finger(tester, 2);
      await a.down(at(tester, rect0.center), 0);
      await b.down(handleAt(tester, CropHandle.bottomRight), 5);
      for (var i = 1; i <= 10; i++) {
        await a.move(const Offset(-6, -4), 5 + i * 16);
        await b.move(const Offset(8, 5), 5 + i * 16);
      }
      await a.up(400);
      await b.up(400);
      await tester.pump();
      expect(c.rect, rect0);
      expect(c.scale, greaterThan(scale0));
    });

    testWidgets(
      'a second finger landing right after the first undoes the first finger\'s drag',
      (tester) async {
        await openCrop(tester, initial: const Box(150, 150, 250, 250));
        final c = ctrl(tester);
        c.fitView();
        await tester.pumpAndSettle();
        final rect0 = c.rect;
        final a = Finger(tester, 1), b = Finger(tester, 2);
        await a.down(handleAt(tester, CropHandle.topLeft), 0);
        await a.move(const Offset(12, 12), 20);
        expect(
          c.rect,
          isNot(rect0),
          reason: 'the first finger acts after the slop',
        );
        await b.down(at(tester, const Offset(60, 60)), 60);
        expect(c.rect, rect0, reason: 'the rectangle jump is undone');
        expect(c.loupeFinger, isNull);
        await a.up(100);
        await b.up(100);
        expect(c.rect, rect0);
      },
    );

    testWidgets(
      'a long single-finger drag is kept when a second finger lands later',
      (tester) async {
        await openCrop(tester, initial: const Box(150, 150, 250, 250));
        final c = ctrl(tester);
        c.fitView();
        await tester.pumpAndSettle();
        final a = Finger(tester, 1), b = Finger(tester, 2);
        await a.down(handleAt(tester, CropHandle.bottomRight), 0);
        await a.move(const Offset(30, 30), 1000);
        final moved = c.rect;
        expect(moved.right, greaterThan(250));
        await b.down(origin(tester) + const Offset(40, 40), 1500);
        await a.move(const Offset(25, 25), 2000);
        await b.move(const Offset(-25, -25), 2000);
        expect(c.rect, moved, reason: 'two fingers never resize');
        // Lifting one finger leaves the other panning, still not resizing.
        await b.up(2100);
        await a.move(const Offset(10, 10), 2200);
        expect(c.rect, moved);
        await a.up(2300);
      },
    );
  });

  group('actions', () {
    testWidgets('Restablecer resets the rectangle and the zoom', (
      tester,
    ) async {
      await openCrop(tester, initial: const Box(150, 150, 250, 250));
      final c = ctrl(tester);
      final view0 = c.view;
      await tester.dragFrom(
        at(tester, const Offset(200, 200)),
        const Offset(40, 40),
      );
      c.zoomAtBy(const Offset(300, 300), 1.5);
      await tester.pump();
      expect(c.rect, isNot(const Rect.fromLTRB(150, 150, 250, 250)));
      await tester.tap(find.byKey(const ValueKey('crop-reset')));
      await tester.pumpAndSettle();
      expect(c.rect, const Rect.fromLTRB(150, 150, 250, 250));
      expect(c.view.scale, closeTo(view0.scale, 1e-9));
      expect(c.view.offset.dx, closeTo(view0.offset.dx, 1e-6));
    });

    testWidgets(
      'keyboard: arrows nudge, shift nudges more, +/- zoom, Enter reads',
      (tester) async {
        final o = await openCrop(
          tester,
          initial: const Box(150, 150, 250, 250),
        );
        final c = ctrl(tester);
        c.fitView();
        await tester.pumpAndSettle();
        final s = c.scale;
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pump();
        expect(c.rect.left, closeTo(150 + 2 / s, 1e-6));
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        await tester.pump();
        expect(c.rect.top, closeTo(150 + 16 / s, 1e-6));
        await tester.sendKeyEvent(LogicalKeyboardKey.numpadAdd);
        await tester.pumpAndSettle();
        expect(c.scale, greaterThan(s));
        await tester.sendKeyEvent(LogicalKeyboardKey.numpadSubtract);
        await tester.pumpAndSettle();
        expect(c.scale, closeTo(s, 1e-6));
        final before = c.rect;
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(o.closed, isTrue);
        expect(o.result!.x0, before.left);
        expect(o.result!.y1, before.bottom);
      },
    );

    testWidgets('zoom buttons work on wide windows', (tester) async {
      await openCrop(tester); // 800 dp wide
      expect(find.byKey(const ValueKey('zoom-in')), findsOneWidget);
      final c = ctrl(tester);
      final s = c.scale;
      await tester.tap(find.byKey(const ValueKey('zoom-in')));
      await tester.pumpAndSettle();
      expect(c.scale, greaterThan(s));
      await tester.tap(find.byKey(const ValueKey('zoom-fit')));
      await tester.pumpAndSettle();
      expect(c.scale, closeTo(s, 1e-9));
    });

    testWidgets('phones have the zoom buttons too, and the touch hint', (
      tester,
    ) async {
      await openCrop(tester, window: const Size(360, 640));
      expect(find.byKey(const ValueKey('zoom-in')), findsOneWidget);
      expect(
        find.text('Pellizca o toca dos veces para ampliar.'),
        findsOneWidget,
      );
      expect(
        find.text('Arrastra las esquinas para encerrar el tablero.'),
        findsOneWidget,
      );
      final canvas = tester.getRect(find.byKey(canvasKey));
      for (final k in ['zoom-in', 'zoom-out', 'zoom-fit']) {
        final r = tester.getRect(find.byKey(ValueKey(k)));
        expect(r.size.shortestSide, greaterThanOrEqualTo(48));
        expect(canvas.contains(r.center), isTrue);
      }
      final c = ctrl(tester);
      final s = c.scale;
      await tester.tap(find.byKey(const ValueKey('zoom-in')));
      await tester.pumpAndSettle();
      expect(c.scale, greaterThan(s));
    });

    testWidgets(
      'the zoom buttons move to the left when the rectangle nears the bottom right corner',
      (tester) async {
        // 400 x 400 image on a 360 x 640 phone: a rectangle in the bottom right of the image
        await openCrop(
          tester,
          window: const Size(360, 640),
          initial: const Box(250, 250, 395, 395),
        );
        final c = ctrl(tester);
        c.fitView();
        await tester.pumpAndSettle();
        final canvas = tester.getRect(find.byKey(canvasKey));
        final zoom = tester.getRect(find.byKey(const ValueKey('zoom-in')));
        final sel = c.screenRect.shift(canvas.topLeft);
        expect(zoom.overlaps(sel.inflate(24)), isFalse);
        expect(
          zoom.center.dx,
          lessThan(canvas.center.dx),
          reason: 'moved left',
        );
      },
    );

    testWidgets('semantics describe the screen and the selection', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await openCrop(tester, initial: const Box(100, 100, 300, 200));
      final node = tester.getSemantics(find.byKey(canvasKey));
      expect(node.label, contains('Recortar tablero'));
      expect(node.value, 'Recorte: 50 % del ancho, 25 % del alto');
      handle.dispose();
    });
  });

  group('text scale', () {
    testWidgets(
      'no overflow at 1.3x on a 360 x 640 phone, both actions fully visible',
      (tester) async {
        await openCrop(tester, window: const Size(360, 640), textScale: 1.3);
        expect(tester.takeException(), isNull);
        for (final t in ['Restablecer', 'Leer este tablero']) {
          final r = tester.getRect(find.text(t));
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(360));
          expect(r.bottom, lessThanOrEqualTo(640));
        }
        final button = tester.getSize(
          find.byKey(const ValueKey('crop-accept')),
        );
        expect(button.height, greaterThanOrEqualTo(48));
      },
    );
  });
}
