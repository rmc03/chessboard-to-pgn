// EqualHeightRow and RowHeaderSlot: the cells of a row are as tall as the tallest, and the headers of the cells are
// as tall as the tallest header, so what is under the headers lines up across the row.
import 'package:chessboard_pgn/src/ui/equal_row.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _cell(ValueNotifier<double> header, Key body) => ValueListenableBuilder(
  valueListenable: header,
  builder: (context, h, _) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      RowHeaderSlot(child: SizedBox(height: h)),
      SizedBox(key: body, height: 10),
    ],
  ),
);

void main() {
  testWidgets('headers take the height of the tallest one, and follow it', (
    tester,
  ) async {
    final a = ValueNotifier<double>(30), b = ValueNotifier<double>(80);
    const ka = ValueKey('a'), kb = ValueKey('b');
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            child: EqualHeightRow(
              columns: 2,
              gap: 20,
              children: [_cell(a, ka), _cell(b, kb)],
            ),
          ),
        ),
      ),
    );
    expect(tester.getTopLeft(find.byKey(ka)).dy, 80);
    expect(tester.getTopLeft(find.byKey(kb)).dy, 80);
    expect(tester.getSize(find.byType(EqualHeightRow)).height, 90);

    // the tallest header shrinks: the other one becomes the tallest
    b.value = 20;
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(ka)).dy, 30);
    expect(tester.getTopLeft(find.byKey(kb)).dy, 30);

    // the short one grows: both follow
    a.value = 55;
    await tester.pump();
    expect(tester.getTopLeft(find.byKey(ka)).dy, 55);
    expect(tester.getTopLeft(find.byKey(kb)).dy, 55);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a slot outside a row is as tall as its child', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: RowHeaderSlot(child: SizedBox(width: 40, height: 33)),
        ),
      ),
    );
    expect(tester.getSize(find.byType(RowHeaderSlot)), const Size(40, 33));
  });

  testWidgets('a single cell keeps its own header', (tester) async {
    final a = ValueNotifier<double>(42);
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            child: EqualHeightRow(
              columns: 1,
              gap: 0,
              children: [_cell(a, const ValueKey('a'))],
            ),
          ),
        ),
      ),
    );
    expect(tester.getTopLeft(find.byKey(const ValueKey('a'))).dy, 42);
  });
}
