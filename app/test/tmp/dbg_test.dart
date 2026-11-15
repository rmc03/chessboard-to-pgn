import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import '../ui/home_harness.dart';

void main() {
  setUpAll(loadRealFonts);
  testWidgets('dbg', (tester) async {
    final home = Home(sessionWith({1: () => [board(endgame), board(middlegame, confidence: {18: 0.5, 21: 0.6}), board(middlegame)]}));
    await home.pump(tester, size: const Size(412, 700));
    await home.addCapture(tester);
    print('texts ${find.byType(Text).evaluate().map((e) => (e.widget as Text).data).toList()}');
    print(home.session.flagged.length);
  });
}
