import 'dart:typed_data';

import 'package:chessboard_pgn/src/crop_page.dart';
import 'package:chessboard_pgn/src/locate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';

/// A known small image: 200 x 100 px.
final png = Uint8List.fromList(
  img.encodePng(img.Image(width: 200, height: 100)),
);

class Opened {
  Box? result;
  bool closed = false;
}

/// Opens the crop page from a button and waits for the image to decode.
/// On an 800 px wide screen the 200 px wide image is shown 4 x bigger.
Future<Opened> openCrop(WidgetTester tester, {Box? initial}) async {
  tester.view.physicalSize = const Size(800, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final o = Opened();
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async {
            o.result = await showCropPage(context, png, initial: initial);
            o.closed = true;
          },
          child: const Text('abrir'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('abrir'));
  await tester.pump(); // (a spinner runs until the image is decoded: no pumpAndSettle yet)
  await tester.pump(const Duration(milliseconds: 500));
  // image decoding is real async work, outside the fake clock
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 300)),
  );
  await tester.pumpAndSettle();
  return o;
}

void main() {
  testWidgets('dragging a corner handle returns a box in image pixels', (
    tester,
  ) async {
    final o = await openCrop(tester);
    expect(
      find.text('Encierra un tablero (mejor con un poco de margen)'),
      findsOneWidget,
    );
    final size = tester.getSize(find.byKey(const ValueKey('handle-br')));
    expect(size.width, greaterThanOrEqualTo(44));
    expect(size.height, greaterThanOrEqualTo(44));

    // Default frame: centred square of 70 % of the shorter side = (65, 15)-(135, 85) in image pixels.
    await tester.drag(
      find.byKey(const ValueKey('handle-br')),
      const Offset(40, 20),
    ); // +10, +5 image px
    await tester.pump();
    await tester.tap(find.text('Leer tablero'));
    await tester.pumpAndSettle();

    expect(o.closed, isTrue);
    final b = o.result!;
    expect(b.x0, closeTo(65, 1));
    expect(b.y0, closeTo(15, 1));
    expect(b.x1, closeTo(145, 1));
    expect(b.y1, closeTo(90, 1));
  });

  testWidgets('dragging inside moves the frame', (tester) async {
    final o = await openCrop(tester);
    await tester.drag(
      find.byKey(const ValueKey('crop-move')),
      const Offset(-40, 20),
    );
    await tester.pump();
    await tester.tap(find.text('Leer tablero'));
    await tester.pumpAndSettle();
    final b = o.result!;
    expect(b.x0, closeTo(55, 1));
    expect(b.y0, closeTo(20, 1));
    expect(b.width, closeTo(70, 1));
    expect(b.height, closeTo(70, 1));
  });

  testWidgets('the frame stays inside the image and keeps a minimum size', (
    tester,
  ) async {
    final o = await openCrop(tester, initial: const Box(10, 10, 60, 60));
    await tester.drag(
      find.byKey(const ValueKey('crop-move')),
      const Offset(-300, -300),
    );
    await tester.pump();
    await tester.drag(
      find.byKey(const ValueKey('handle-br')),
      const Offset(-3000, -3000),
    );
    await tester.pump();
    await tester.tap(find.text('Leer tablero'));
    await tester.pumpAndSettle();
    final b = o.result!;
    expect(b.x0, greaterThanOrEqualTo(0));
    expect(b.y0, greaterThanOrEqualTo(0));
    expect(b.width, greaterThanOrEqualTo(20)); // minimum size
    expect(b.height, greaterThanOrEqualTo(20));
  });

  testWidgets('cancel returns null', (tester) async {
    final o = await openCrop(tester);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(o.closed, isTrue);
    expect(o.result, isNull);
  });
}
