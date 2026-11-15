// Scenes of the home / session screen, the diagram block and the square editor (docs/ux-spec.md, 4.1 and 4.2).
//
// The boards are REAL readings: page_three_boards.png goes through the real pipeline once (so the "Original"
// comparator shows a genuine crop of the page and the read position matches it), then each scene's session
// reader hands out those boards (edited where a scene needs a doubtful or impossible position). A scene starts
// from the real UI: the picker is injected, and `setup` taps "Elegir captura" / "Añadir captura".
import 'dart:async';
import 'dart:io';

import 'package:chessboard_pgn/src/chess.dart';
import 'package:chessboard_pgn/src/classifier.dart';
import 'package:chessboard_pgn/src/locate.dart';
import 'package:chessboard_pgn/src/pipeline.dart';
import 'package:chessboard_pgn/src/ui/diagram_block.dart';
import 'package:chessboard_pgn/src/ui/home_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'harness.dart';

/// What the fake reader returns for the first byte of the image.
enum Capture {
  /// The three boards of the page: legible with two doubtful squares, impossible, clean.
  three(1),

  /// A single clean board.
  one(2),

  /// Four boards located, one read, the rest never arrive (the capture stays in "Leyendo 2 de 4…").
  stuck(3),

  /// The reader throws.
  broken(4),

  /// The reader finds no board.
  empty(5),

  /// A king in check on a position with every castling right.
  castling(6);

  const Capture(this.code);
  final int code;

  /// The page itself (so the capture thumbnail is a real picture) with the scene's code as the last byte.
  Uint8List get bytes => Uint8List.fromList([..._page, code]);
}

List<RecognizedBoard>? _real;
List<int> _page = const [];

Future<List<RecognizedBoard>> _loadReal() async {
  final model = ModelAssets(
    File('assets/model/manifest.json').readAsStringSync(),
    File('assets/model/weights.bin').readAsBytesSync(),
  );
  return recognizeImage(
    File('test/fixtures/page_three_boards.png').readAsBytesSync(),
    model,
  );
}

RecognizedBoard _copy(
  RecognizedBoard b, {
  Map<int, int> set = const {},
  Map<int, double> confidence = const {},
}) {
  final grid = List<int>.of(b.grid);
  set.forEach((sq, cls) => grid[sq] = cls);
  final conf = List<double>.filled(64, 1);
  confidence.forEach((sq, c) => conf[sq] = c);
  return RecognizedBoard(
    b.box,
    grid,
    conf,
    grid,
    false,
    originalCrop: b.originalCrop,
  );
}

/// The page's three boards as the scenes show them.
List<RecognizedBoard> _three() {
  final r = _real!;
  return [
    // clean position, black to move (forced by a check), two doubtful squares
    _copy(r[2], confidence: {26: 0.62, 36: 0.81}),
    // impossible: both kings in check; one doubtful square on top
    _copy(r[1], confidence: {49: 0.7}),
    // clean, white to move (forced by a check): a rook was missing from the reading
    _copy(r[0], set: {58: 0}),
  ];
}

RecognizedBoard _castlingBoard() {
  final grid = placementToGrid(
    'r3k2r/ppp2ppp/5n2/1B2p3/4P3/2N2N2/PPPP1PPP/R1BQK2R',
  );
  return RecognizedBoard(
    const Box(0, 0, 100, 100),
    grid,
    List<double>.filled(64, 1),
    grid,
    false,
  );
}

final List<Uint8List> _picks = [];

/// The reader of every scene: behaviour chosen by the first byte of the image.
Future<List<RecognizedBoard>> _read(
  Uint8List bytes, {
  BoardsFoundFn? onFound,
  BoardReadFn? onBoard,
}) async {
  Future<List<RecognizedBoard>> deliver(List<RecognizedBoard> boards) async {
    onFound?.call(boards.length, 800, 1200);
    for (final (i, b) in boards.indexed) {
      onBoard?.call(i, b);
    }
    return boards;
  }

  switch (bytes.last) {
    case 1:
      return deliver(_three());
    case 2:
      return deliver([_three()[0]]);
    case 3:
      final boards = _three();
      onFound?.call(4, 800, 1200);
      onBoard?.call(0, boards[0]);
      return Completer<List<RecognizedBoard>>()
          .future; // never finishes: the capture stays "reading"
    case 4:
      throw Exception('boom');
    case 5:
      return deliver(const []);
    default:
      return deliver([_castlingBoard()]);
  }
}

Widget _home() => HomePage(
  pickImage: () async => _picks.isEmpty ? null : _picks.removeAt(0),
  canShare: true,
  openUri: (_) async => true,
);

/// Loads the real boards (real async: it runs the pipeline in an isolate).
Future<void> _prepare(WidgetTester tester) async {
  _picks.clear();
  _page = File('test/fixtures/page_three_boards.png').readAsBytesSync();
  _real ??= (await tester.runAsync(_loadReal))!;
}

/// Adds captures through the real UI, one after the other.
Future<void> _add(WidgetTester tester, List<Capture> captures) async {
  for (final (i, c) in captures.indexed) {
    _picks.add(c.bytes);
    await tester.tap(
      i == 0 ? find.text('Elegir captura') : find.byType(FloatingActionButton),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 400));
  }
}

/// Scrolls the session list to its very end (the last block, "Quitar todas las capturas").
Future<void> _toEnd(WidgetTester tester) async {
  for (var i = 0; i < 3; i++) {
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -20000),
      8000,
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();
  }
}

SceneSetup _session(
  List<Capture> captures, [
  Future<void> Function(WidgetTester)? then,
]) => (tester, env) async {
  await _prepare(tester);
  await _add(tester, captures);
  // let the thumbnails and crops decode (real async) before the picture is taken
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 400)),
  );
  await tester.pump(const Duration(milliseconds: 100));
  await then?.call(tester);
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 400)),
  );
};

void registerHomeScenes() {
  registerScene(
    'home_empty',
    (env) => _home(),
    readImage: _read,
    setup: (t, e) => _prepare(t),
  );

  registerScene(
    'home_session',
    (env) => _home(),
    readImage: _read,
    setup: _session([Capture.three]),
    textScale13: true,
  );

  registerScene(
    'home_session_tall',
    (env) => _home(),
    readImage: _read,
    setup: _session([Capture.three]),
    phoneSize: const Size(412, 2300),
    desktopSize: const Size(1280, 1200),
  );

  registerScene(
    'home_reading',
    (env) => _home(),
    readImage: _read,
    setup: _session([Capture.one, Capture.stuck]),
    desktopSize: const Size(1280, 1000),
  );

  registerScene(
    'home_failures',
    (env) => _home(),
    readImage: _read,
    setup: _session([Capture.broken, Capture.empty]),
  );

  registerScene(
    'block_original',
    (env) => _home(),
    readImage: _read,
    setup: _session([Capture.three], (tester) async {
      await tester.tap(find.text('Original').first);
      await tester.pump(const Duration(milliseconds: 300));
    }),
  );

  registerScene(
    'block_turn_castling',
    (env) => _home(),
    readImage: _read,
    setup: _session([Capture.castling]),
  );

  registerScene(
    'sheet_review',
    (env) => _home(),
    readImage: _read,
    setup: _session([Capture.three], (tester) async {
      await tester.tap(find.byKey(const ValueKey('review-doubtful')).first);
      await tester.pump(const Duration(milliseconds: 500));
    }),
  );

  registerScene(
    'share_sheet',
    (env) => _home(),
    readImage: _read,
    setup: _session([Capture.three], (tester) async {
      await tester.tap(find.byTooltip('Compartir o copiar PGN').first);
      await tester.pump(const Duration(milliseconds: 400));
    }),
  );

  registerScene(
    'sheet_changed_square',
    (env) => _home(),
    readImage: _read,
    setup: _session([Capture.three], (tester) async {
      // an occupied square the user changed, opened again: "Se leyó" + "Volver a lo leído"
      final square = find.byKey(const ValueKey('square-26')).first;
      await tester.tap(square);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('pick-5')));
      await tester.pumpAndSettle();
      await tester.tap(square);
      await tester.pump(const Duration(milliseconds: 500));
    }),
  );

  registerScene(
    'block_impossible_doubtful',
    (env) => _home(),
    readImage: _read,
    setup: _session([Capture.three], (tester) async {
      if (find.byType(DiagramBlock).evaluate().length < 2) {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -800));
        await tester.pumpAndSettle();
      }
      await tester.ensureVisible(find.byType(DiagramBlock).at(1));
      await tester.pumpAndSettle();
    }),
  );

  registerScene(
    'export_warnings',
    (env) => _home(),
    readImage: _read,
    setup: _session([Capture.three]),
    textScale13: true,
  );

  registerScene(
    'home_end',
    (env) => _home(),
    readImage: _read,
    setup: _session([Capture.three], _toEnd),
    textScale13: true,
    phoneSize: const Size(360, 780),
    desktopSize: const Size(1280, 800),
  );

  registerScene(
    'home_long',
    (env) => _home(),
    readImage: _read,
    setup: _session([Capture.three, Capture.three, Capture.three]),
    phone: false,
    desktopSize: const Size(1280, 1800),
  );

  registerScene(
    'home_long_two_columns',
    (env) => _home(),
    readImage: _read,
    setup: _session([Capture.three, Capture.three, Capture.three]),
    phone: false,
    desktopSize: const Size(900, 1800),
  );
}
