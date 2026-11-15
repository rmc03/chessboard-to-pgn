import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:chessboard_pgn/src/chess.dart';
import 'package:chessboard_pgn/src/ui/pieces.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// A bundle with sets.json but whose SVG files cannot be read.
class _BrokenSvgBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => throw FlutterError('no asset $key');

  @override
  Future<String> loadString(String key, {bool cache = true}) async {
    if (key == 'assets/pieces/sets.json') {
      return jsonEncode([
        {'id': 'ghost', 'name': 'Fantasma', 'author': 'Nadie', 'license': 'MIT'},
      ]);
    }
    throw FlutterError('no asset $key');
  }
}

/// RGBA of one piece painted on a transparent 96 x 96 canvas.
Future<Uint8List> _paint(int cls, PieceSetCatalog catalog, String setId) async {
  final rec = ui.PictureRecorder();
  paintPiece(ui.Canvas(rec), const Rect.fromLTWH(0, 0, 96, 96), cls, catalog, setId);
  final image = await rec.endRecording().toImage(96, 96);
  return (await image.toByteData())!.buffer.asUint8List();
}

({int white, int black, int any, double lum}) _count(Uint8List rgba) {
  var w = 0, b = 0, a = 0;
  double lum = 0;
  for (var i = 0; i < rgba.length; i += 4) {
    if (rgba[i + 3] < 200) continue;
    a++;
    lum += 0.2126 * rgba[i] + 0.7152 * rgba[i + 1] + 0.0722 * rgba[i + 2];
    if (rgba[i] > 245 && rgba[i + 1] > 245 && rgba[i + 2] > 245) w++;
    if (rgba[i] < 40 && rgba[i + 1] < 40 && rgba[i + 2] < 40) b++;
  }
  return (white: w, black: b, any: a, lum: a == 0 ? 0 : lum / a);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await (FontLoader('ChessFigures')
          ..addFont(Future.value(ByteData.sublistView(File('assets/fonts/ChessFigures.ttf').readAsBytesSync()))))
        .load();
  });

  test('the catalogue lists the sets of sets.json and the typographic fallback last', () async {
    final catalog = await PieceSetCatalog.load();
    expect(catalog.ids, ['merida', 'cburnett', 'chessnut', 'mpchess', 'celtic', 'tipografico']);
    final merida = catalog.find('merida')!;
    expect(merida.name, 'Merida');
    expect(merida.author, 'Armando Hernandez Marroquin');
    expect(merida.license, 'GPLv2+');
    expect(merida.builtIn, isFalse);
    expect(catalog.find('tipografico')!.builtIn, isTrue);
    expect(catalog.resolve('does-not-exist').id, 'tipografico');
    expect(catalog.stateOf('merida'), PieceLoad.loading);
    expect(catalog.stateOf('tipografico'), PieceLoad.ready);
  });

  testWidgets('ensureLoaded parses the 12 pieces once and notifies', (tester) async {
    final catalog = await tester.runAsync(PieceSetCatalog.load) as PieceSetCatalog;
    var notified = 0;
    catalog.addListener(() => notified++);
    await tester.runAsync(() async {
      await Future.wait([catalog.ensureLoaded('merida'), catalog.ensureLoaded('merida')]);
    });
    expect(catalog.stateOf('merida'), PieceLoad.ready);
    expect(notified, 1);
    for (var cls = 1; cls <= 12; cls++) {
      expect(catalog.picture('merida', cls), isNotNull, reason: pieceNames[cls]);
    }
    await tester.runAsync(() => catalog.ensureLoaded('merida'));
    expect(notified, 1, reason: 'a loaded set is not loaded again');

    // a white and a black SVG piece differ: white has a white body, black has none
    final white = await tester.runAsync(() => _paint(whiteKing, catalog, 'merida'));
    final black = await tester.runAsync(() => _paint(blackKing, catalog, 'merida'));
    final w = _count(white!), b = _count(black!);
    expect(w.white, greaterThan(300));
    expect(w.lum, greaterThan(b.lum + 40), reason: 'the white king is much lighter than the black one');
    catalog.dispose();
  });

  testWidgets('without sets.json only the typographic set remains', (tester) async {
    final catalog = await tester.runAsync(() => PieceSetCatalog.load(_EmptyBundle())) as PieceSetCatalog;
    expect(catalog.ids, ['tipografico']);
    expect(PieceSetCatalog.builtIn().ids, ['tipografico']);
  });

  testWidgets('a set whose files fail falls back to the typographic figures', (tester) async {
    final catalog = await tester.runAsync(() => PieceSetCatalog.load(_BrokenSvgBundle())) as PieceSetCatalog;
    expect(catalog.ids, ['ghost', 'tipografico']);
    expect(catalog.stateOf('ghost'), PieceLoad.loading);
    // while loading nothing is drawn for an SVG set
    expect(_count((await tester.runAsync(() => _paint(whitePawn, catalog, 'ghost')))!).any, 0);
    await tester.runAsync(() => catalog.ensureLoaded('ghost'));
    expect(catalog.stateOf('ghost'), PieceLoad.failed);
    final pawn = _count((await tester.runAsync(() => _paint(whitePawn, catalog, 'ghost')))!);
    expect(pawn.any, greaterThan(300), reason: 'the figure is drawn');
    expect(pawn.white, greaterThan(100));
  });

  testWidgets('the typographic set tells white from black, pawns included, with no SVG', (tester) async {
    final catalog = PieceSetCatalog.builtIn();
    for (var cls = 1; cls <= 12; cls++) {
      final c = _count((await tester.runAsync(() => _paint(cls, catalog, 'tipografico')))!);
      if (isWhite(cls)) {
        expect(c.white, greaterThan(150), reason: '${pieceNames[cls]} has a white body');
        expect(c.black, greaterThan(60), reason: '${pieceNames[cls]} has a black outline');
      } else {
        expect(c.white, lessThan(5), reason: '${pieceNames[cls]} has no white');
        expect(c.black, greaterThan(500), reason: '${pieceNames[cls]} is solid black');
      }
    }
  });

  testWidgets('PieceView has the piece name as its semantics label and loads its set', (tester) async {
    final handle = tester.ensureSemantics();
    final catalog = await tester.runAsync(PieceSetCatalog.load) as PieceSetCatalog;
    await tester.pumpWidget(
      MaterialApp(
        home: Row(
          children: [
            PieceView(2, size: 40, catalog: catalog, setId: 'cburnett'),
            PieceView(8, size: 40, catalog: catalog, setId: 'tipografico'),
          ],
        ),
      ),
    );
    expect(find.bySemanticsLabel('caballo blanco'), findsOneWidget);
    expect(find.bySemanticsLabel('caballo negro'), findsOneWidget);
    await tester.runAsync(() => catalog.ensureLoaded('cburnett')); // the widget already asked for it
    expect(catalog.stateOf('cburnett'), PieceLoad.ready);
    handle.dispose();
    catalog.dispose();
  });

  test('every id of sets.json is declared as an asset folder', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final sets = jsonDecode(File('assets/pieces/sets.json').readAsStringSync()) as List;
    for (final s in sets) {
      expect(pubspec, contains('assets/pieces/${s['id']}/'));
    }
  });
}

class _EmptyBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async => throw FlutterError('no asset $key');
}
