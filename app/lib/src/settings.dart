// User preferences (theme, stone, board look, piece set), persisted with shared_preferences.
//
// The app loads them once at startup ([AppSettings.load]) and listens to the object: every setter updates the
// in-memory value and notifies first (so the UI changes live), then writes to storage.
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

/// Ids of the five stones of the board, in the order they are offered. `stones` in tokens.dart is keyed by these.
const List<String> stoneIds = [
  'serpentina',
  'pizarra',
  'alicante',
  'nogal',
  'granito',
];

const String defaultStoneId = 'serpentina';
const String defaultPieceSetId = 'cburnett';

/// How the squares of a board are drawn.
enum BoardStyle {
  /// A table of stone: squares of the chosen stone with a faint terrazzo speckle in a polished granite frame.
  stone,

  /// Plain flat squares with a 1 dp rule.
  flat,

  /// Like the printed diagrams of a book: white light squares, dark squares hatched in black.
  printed,
}

/// Persisted preferences. Create with [load] in `main()`, or with the constructor (no storage) in tests and
/// previews.
class AppSettings extends ChangeNotifier {
  /// In-memory settings with no storage behind them (tests, previews). Invalid values are replaced by defaults.
  AppSettings({
    this._themeMode = ThemeMode.system,
    String stoneId = defaultStoneId,
    this._boardStyle = BoardStyle.stone,
    this._showCoordinates = true,
    String pieceSetId = defaultPieceSetId,
  }) : _stoneId = stoneIds.contains(stoneId) ? stoneId : defaultStoneId,
       _pieceSetId = pieceSetId.isEmpty ? defaultPieceSetId : pieceSetId,
       _prefs = null;

  AppSettings._stored(
    SharedPreferences this._prefs, {
    required this._themeMode,
    required this._stoneId,
    required this._boardStyle,
    required this._showCoordinates,
    required this._pieceSetId,
  });

  static const _kTheme = 'settings.themeMode';
  static const _kStone = 'settings.stoneId';
  static const _kBoardStyle = 'settings.boardStyle';
  static const _kCoordinates = 'settings.showCoordinates';
  static const _kPieceSet = 'settings.pieceSetId';

  /// Reads the stored preferences. Missing, corrupt or unknown values fall back to the defaults, and if the
  /// storage itself is unavailable the settings still work (they just are not saved). [prefs] lets a test or a
  /// caller that already has the instance skip `SharedPreferences.getInstance()`; tests normally call
  /// `SharedPreferences.setMockInitialValues` instead.
  static Future<AppSettings> load({SharedPreferences? prefs}) async {
    SharedPreferences store;
    try {
      store = prefs ?? await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint('Settings storage unavailable: $e');
      return AppSettings();
    }
    // A value stored with another type makes the typed getters throw: treat that as "not stored".
    T? read<T>(T? Function(SharedPreferences) get) {
      try {
        return get(store);
      } catch (_) {
        return null;
      }
    }

    final themeName = read((p) => p.getString(_kTheme));
    final stone = read((p) => p.getString(_kStone));
    final styleName = read((p) => p.getString(_kBoardStyle));
    final pieceSet = read((p) => p.getString(_kPieceSet));
    return AppSettings._stored(
      store,
      themeMode: ThemeMode.values.asNameMap()[themeName] ?? ThemeMode.system,
      stoneId: stoneIds.contains(stone) ? stone! : defaultStoneId,
      boardStyle: BoardStyle.values.asNameMap()[styleName] ?? BoardStyle.stone,
      showCoordinates: read((p) => p.getBool(_kCoordinates)) ?? true,
      pieceSetId: (pieceSet == null || pieceSet.isEmpty)
          ? defaultPieceSetId
          : pieceSet,
    );
  }

  final SharedPreferences? _prefs;
  ThemeMode _themeMode;
  String _stoneId;
  BoardStyle _boardStyle;
  bool _showCoordinates;
  String _pieceSetId;

  /// System / light / dark. Default: [ThemeMode.system].
  ThemeMode get themeMode => _themeMode;

  /// One of [stoneIds]. Default: [defaultStoneId]. (A stored id of the old inks falls back to the default.)
  String get stoneId => _stoneId;

  /// Default: [BoardStyle.stone].
  BoardStyle get boardStyle => _boardStyle;

  /// Draw a–h / 1–8 around the board. Default: true.
  bool get showCoordinates => _showCoordinates;

  /// Id of the piece set (`assets/pieces/<id>`). Default: [defaultPieceSetId]. Whether it exists in the
  /// catalogue is checked by the UI layer through [ensurePieceSet].
  String get pieceSetId => _pieceSetId;

  /// Changes the value, notifies listeners, then saves. The returned future completes when the value has been
  /// written (a failed write is logged, never thrown: the in-memory value stays).
  Future<void> setThemeMode(ThemeMode value) => _set(
    _themeMode == value,
    () => _themeMode = value,
    (p) => p.setString(_kTheme, value.name),
  );

  /// Ignored (no change, no notification) when [id] is not one of [stoneIds].
  Future<void> setStoneId(String id) => _set(
    !stoneIds.contains(id) || _stoneId == id,
    () => _stoneId = id,
    (p) => p.setString(_kStone, id),
  );

  Future<void> setBoardStyle(BoardStyle value) => _set(
    _boardStyle == value,
    () => _boardStyle = value,
    (p) => p.setString(_kBoardStyle, value.name),
  );

  Future<void> setShowCoordinates(bool value) => _set(
    _showCoordinates == value,
    () => _showCoordinates = value,
    (p) => p.setBool(_kCoordinates, value),
  );

  /// Ignored when [id] is empty.
  Future<void> setPieceSetId(String id) => _set(
    id.isEmpty || _pieceSetId == id,
    () => _pieceSetId = id,
    (p) => p.setString(_kPieceSet, id),
  );

  /// Call once the real catalogue of piece sets is known: if the stored [pieceSetId] is not in [available]
  /// (a set that was removed from the app, or a corrupt value) it is replaced by [fallback], saved and
  /// notified. [fallback] should itself be in [available].
  void ensurePieceSet(Iterable<String> available, {required String fallback}) {
    if (available.contains(_pieceSetId)) return;
    setPieceSetId(fallback);
  }

  Future<void> _set(
    bool unchanged,
    void Function() assign,
    Future<bool> Function(SharedPreferences) save,
  ) async {
    if (unchanged) return;
    assign();
    notifyListeners();
    final prefs = _prefs;
    if (prefs == null) return;
    try {
      await save(prefs);
    } catch (e) {
      debugPrint('Could not save a setting: $e');
    }
  }
}
