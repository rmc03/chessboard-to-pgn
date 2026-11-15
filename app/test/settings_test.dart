import 'package:chessboard_pgn/src/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults when nothing is stored', () async {
    final s = await AppSettings.load();
    expect(s.themeMode, ThemeMode.system);
    expect(s.inkId, 'cobalto');
    expect(s.boardStyle, BoardStyle.flat);
    expect(s.showCoordinates, isTrue);
    expect(s.pieceSetId, 'merida');
  });

  test('the ink list holds the six ids and the default is the first', () {
    expect(inkIds, [
      'cobalto',
      'torneo',
      'granate',
      'madera',
      'ciruela',
      'grafito',
    ]);
    expect(defaultInkId, inkIds.first);
  });

  test('every setter saves, notifies, and survives a reload', () async {
    final s = await AppSettings.load();
    var notified = 0;
    s.addListener(() => notified++);

    await s.setThemeMode(ThemeMode.dark);
    await s.setInkId('granate');
    await s.setBoardStyle(BoardStyle.printed);
    await s.setShowCoordinates(false);
    await s.setPieceSetId('cburnett');
    expect(notified, 5);

    final again = await AppSettings.load();
    expect(again.themeMode, ThemeMode.dark);
    expect(again.inkId, 'granate');
    expect(again.boardStyle, BoardStyle.printed);
    expect(again.showCoordinates, isFalse);
    expect(again.pieceSetId, 'cburnett');
  });

  test('setting the same value does not notify', () async {
    final s = await AppSettings.load();
    var notified = 0;
    s.addListener(() => notified++);
    await s.setInkId('cobalto');
    await s.setThemeMode(ThemeMode.system);
    expect(notified, 0);
  });

  test('an unknown ink id is ignored', () async {
    final s = await AppSettings.load();
    var notified = 0;
    s.addListener(() => notified++);
    await s.setInkId('fucsia');
    expect(s.inkId, 'cobalto');
    expect(notified, 0);
  });

  test('corrupt or unknown stored values fall back to the defaults', () async {
    SharedPreferences.setMockInitialValues({
      'settings.themeMode': 'neon',
      'settings.inkId': 'fucsia',
      'settings.boardStyle': 7, // wrong type
      'settings.showCoordinates': 'yes', // wrong type: the typed getter throws
      'settings.pieceSetId': '',
    });
    final s = await AppSettings.load();
    expect(s.themeMode, ThemeMode.system);
    expect(s.inkId, 'cobalto');
    expect(s.boardStyle, BoardStyle.flat);
    expect(s.showCoordinates, isTrue);
    expect(s.pieceSetId, 'merida');
  });

  test('valid stored values are read back', () async {
    SharedPreferences.setMockInitialValues({
      'settings.themeMode': 'light',
      'settings.inkId': 'ciruela',
      'settings.boardStyle': 'printed',
      'settings.showCoordinates': false,
      'settings.pieceSetId': 'alpha',
    });
    final s = await AppSettings.load();
    expect(s.themeMode, ThemeMode.light);
    expect(s.inkId, 'ciruela');
    expect(s.boardStyle, BoardStyle.printed);
    expect(s.showCoordinates, isFalse);
    expect(s.pieceSetId, 'alpha');
  });

  test('ensurePieceSet replaces a set missing from the catalogue', () async {
    SharedPreferences.setMockInitialValues({'settings.pieceSetId': 'gone'});
    final s = await AppSettings.load();
    var notified = 0;
    s.addListener(() => notified++);

    s.ensurePieceSet(['merida', 'alpha'], fallback: 'merida');
    expect(s.pieceSetId, 'merida');
    expect(notified, 1);
    await Future<void>.delayed(Duration.zero);
    expect((await AppSettings.load()).pieceSetId, 'merida');

    s.ensurePieceSet(['merida', 'alpha'], fallback: 'alpha'); // already valid
    expect(s.pieceSetId, 'merida');
    expect(notified, 1);
  });

  test(
    'the plain constructor works without storage and sanitises the ink',
    () async {
      final s = AppSettings(inkId: 'nope', themeMode: ThemeMode.dark);
      expect(s.inkId, 'cobalto');
      await s.setBoardStyle(BoardStyle.printed);
      expect(s.boardStyle, BoardStyle.printed);
    },
  );
}
