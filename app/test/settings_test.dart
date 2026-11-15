import 'package:chessboard_pgn/src/settings.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults when nothing is stored', () async {
    final s = await AppSettings.load();
    expect(s.themeMode, ThemeMode.system);
    expect(s.stoneId, 'serpentina');
    expect(s.boardStyle, BoardStyle.stone);
    expect(s.showCoordinates, isTrue);
    expect(s.pieceSetId, 'cburnett');
  });

  test('the stone list holds the five ids and the default is the first', () {
    expect(stoneIds, ['serpentina', 'pizarra', 'alicante', 'nogal', 'granito']);
    expect(defaultStoneId, stoneIds.first);
    expect(BoardStyle.values.map((v) => v.name), ['stone', 'flat', 'printed']);
  });

  test('every setter saves, notifies, and survives a reload', () async {
    final s = await AppSettings.load();
    var notified = 0;
    s.addListener(() => notified++);

    await s.setThemeMode(ThemeMode.dark);
    await s.setStoneId('granito');
    await s.setBoardStyle(BoardStyle.printed);
    await s.setShowCoordinates(false);
    await s.setPieceSetId('merida');
    expect(notified, 5);

    final again = await AppSettings.load();
    expect(again.themeMode, ThemeMode.dark);
    expect(again.stoneId, 'granito');
    expect(again.boardStyle, BoardStyle.printed);
    expect(again.showCoordinates, isFalse);
    expect(again.pieceSetId, 'merida');
  });

  test('setting the same value does not notify', () async {
    final s = await AppSettings.load();
    var notified = 0;
    s.addListener(() => notified++);
    await s.setStoneId('serpentina');
    await s.setThemeMode(ThemeMode.system);
    expect(notified, 0);
  });

  test('an unknown stone id is ignored', () async {
    final s = await AppSettings.load();
    var notified = 0;
    s.addListener(() => notified++);
    await s.setStoneId('fucsia');
    expect(s.stoneId, 'serpentina');
    expect(notified, 0);
  });

  test('corrupt or unknown stored values fall back to the defaults', () async {
    SharedPreferences.setMockInitialValues({
      'settings.themeMode': 'neon',
      'settings.stoneId': 'fucsia',
      'settings.boardStyle': 7, // wrong type
      'settings.showCoordinates': 'yes', // wrong type: the typed getter throws
      'settings.pieceSetId': '',
    });
    final s = await AppSettings.load();
    expect(s.themeMode, ThemeMode.system);
    expect(s.stoneId, 'serpentina');
    expect(s.boardStyle, BoardStyle.stone);
    expect(s.showCoordinates, isTrue);
    expect(s.pieceSetId, 'cburnett');
  });

  test(
    'values stored by the previous design still work or fall back',
    () async {
      SharedPreferences.setMockInitialValues({
        'settings.inkId': 'granate', // the old ink: not read any more
        'settings.stoneId': 'ciruela', // not a stone
        'settings.boardStyle': 'flat', // an old style that still exists
      });
      final s = await AppSettings.load();
      expect(s.stoneId, 'serpentina');
      expect(s.boardStyle, BoardStyle.flat);
      SharedPreferences.setMockInitialValues({
        'settings.boardStyle': 'printed',
      });
      expect((await AppSettings.load()).boardStyle, BoardStyle.printed);
    },
  );

  test('valid stored values are read back', () async {
    SharedPreferences.setMockInitialValues({
      'settings.themeMode': 'light',
      'settings.stoneId': 'nogal',
      'settings.boardStyle': 'printed',
      'settings.showCoordinates': false,
      'settings.pieceSetId': 'alpha',
    });
    final s = await AppSettings.load();
    expect(s.themeMode, ThemeMode.light);
    expect(s.stoneId, 'nogal');
    expect(s.boardStyle, BoardStyle.printed);
    expect(s.showCoordinates, isFalse);
    expect(s.pieceSetId, 'alpha');
  });

  test('ensurePieceSet replaces a set missing from the catalogue', () async {
    SharedPreferences.setMockInitialValues({'settings.pieceSetId': 'gone'});
    final s = await AppSettings.load();
    var notified = 0;
    s.addListener(() => notified++);

    s.ensurePieceSet(['cburnett', 'alpha'], fallback: 'cburnett');
    expect(s.pieceSetId, 'cburnett');
    expect(notified, 1);
    await Future<void>.delayed(Duration.zero);
    expect((await AppSettings.load()).pieceSetId, 'cburnett');

    s.ensurePieceSet(['cburnett', 'alpha'], fallback: 'alpha'); // already valid
    expect(s.pieceSetId, 'cburnett');
    expect(notified, 1);
  });

  test(
    'the plain constructor works without storage and sanitises the stone',
    () async {
      final s = AppSettings(stoneId: 'nope', themeMode: ThemeMode.dark);
      expect(s.stoneId, 'serpentina');
      await s.setBoardStyle(BoardStyle.printed);
      expect(s.boardStyle, BoardStyle.printed);
    },
  );
}
