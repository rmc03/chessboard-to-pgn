// Shared setup of the home-screen tests: a real app around [HomePage] with every platform call replaced by a
// recording fake, and boards that are easy to reason about.
import 'dart:async';

import 'package:chessboard_pgn/main.dart';
import 'package:chessboard_pgn/src/chess.dart';
import 'package:chessboard_pgn/src/locate.dart';
import 'package:chessboard_pgn/src/pipeline.dart';
import 'package:chessboard_pgn/src/session.dart';
import 'package:chessboard_pgn/src/settings.dart';
import 'package:chessboard_pgn/src/ui/home_page.dart';
import 'package:chessboard_pgn/src/ui/pieces.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';

export '../screenshots/harness.dart' show loadRealFonts;

const middlegame = 'r1bq1rk1/pp2ppbp/2np1np1/8/3NP3/2N1BP2/PPPQ2PP/2KR1B1R';
const endgame = '8/5pk1/6p1/3R4/8/6P1/5PK1/3r4';

/// A black king in check with every castling right available: turn forced, four chips.
const castlingCheck = 'r3k2r/ppp2ppp/5n2/1B2p3/4P3/2N2N2/PPPP1PPP/R1BQK2R';

/// A small PNG standing in for the crop of the original board.
Uint8List samplePng() {
  final image = img.Image(width: 32, height: 32);
  img.fill(image, color: img.ColorRgb8(30, 120, 30));
  return Uint8List.fromList(img.encodePng(image));
}

RecognizedBoard board(
  String placement, {
  Map<int, double> confidence = const {},
  bool crop = false,
  bool fallback = false,
}) {
  final grid = placementToGrid(placement);
  final conf = List<double>.filled(64, 1);
  confidence.forEach((sq, c) => conf[sq] = c);
  return RecognizedBoard(
    const Box(0, 0, 100, 100),
    grid,
    conf,
    grid,
    fallback,
    originalCrop: crop ? samplePng() : null,
  );
}

/// A reader that finds [boards] at once and hands them out. [onRead] sees each call.
ReadImageFn readerOf(List<RecognizedBoard> Function(Uint8List bytes) boards) =>
    (bytes, {onFound, onBoard}) async {
      final list = boards(bytes);
      onFound?.call(list.length, 800, 600);
      for (final (i, b) in list.indexed) {
        onBoard?.call(i, b);
      }
      return list;
    };

class Home {
  Home(this.session);

  final Session session;
  final List<Uint8List> picks = [];
  int picked = 0;
  final List<(String, Uint8List)> saved = [];
  final List<String> sharedText = [];
  final List<(String, Uint8List)> sharedFiles = [];
  final List<Uri> opened = [];
  bool openResult = true;
  String? clipboard;
  Box? cropResult;
  int crops = 0;
  DateTime now = DateTime(2026, 3, 4, 9, 5);

  Future<void> pump(
    WidgetTester tester, {
    bool canShare = true,
    Size size = const Size(480, 2400),
    double textScale = 1,
    bool? saveResult,
    Future<Uint8List?> Function()? pickImage,
    TargetPlatform platform = TargetPlatform.android,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearAllTestValues();
    });
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard = (call.arguments as Map)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    await tester.pumpWidget(
      ChessPgnApp(
        settings: AppSettings(themeMode: ThemeMode.light),
        session: session,
        catalog: PieceSetCatalog.builtIn(),
        home: HomePage(
          pickImage:
              pickImage ??
              () async {
                picked++;
                return picks.isEmpty ? null : picks.removeAt(0);
              },
          cropRegion: (context, bytes, initial) async {
            crops++;
            return cropResult;
          },
          saveFile: (name, bytes) async {
            saved.add((name, bytes));
            return saveResult ?? true;
          },
          shareText: (text) async => sharedText.add(text),
          shareFile: (name, bytes) async => sharedFiles.add((name, bytes)),
          openUri: (uri) async {
            opened.add(uri);
            return openResult;
          },
          canShare: canShare,
          platform: platform,
          now: () => now,
        ),
      ),
    );
    await tester.pump();
  }

  /// Taps "Elegir captura" / the "Añadir captura" FAB (extended or icon only) with [bytes] in the picker and lets the read finish.
  Future<void> addCapture(WidgetTester tester, [int code = 1]) async {
    picks.add(Uint8List.fromList([code]));
    await tester.tap(
      session.isEmpty
          ? find.text('Elegir captura')
          : find.byType(FloatingActionButton),
    );
    await tester.pumpAndSettle();
  }
}

/// Session whose reader returns the boards of [byCode] for the first byte of the image.
Session sessionWith(
  Map<int, List<RecognizedBoard> Function()> byCode, {
  ReadRegionFn? readRegion,
}) => Session(
  readImage: readerOf((bytes) => byCode[bytes.first]!()),
  readRegion: readRegion,
);

Finder square(int sq) => find.byKey(ValueKey('square-$sq')).first;

/// A reader gate: the read of a capture stops at each [Completer] until the test completes it.
class Gate {
  final found = Completer<void>();
  final boards = <Completer<void>>[];
  final finish = Completer<void>();

  ReadImageFn reader(List<RecognizedBoard> list) {
    while (boards.length < list.length) {
      boards.add(Completer<void>());
    }
    return (bytes, {onFound, onBoard}) async {
      await found.future;
      onFound?.call(list.length, 800, 600);
      for (final (i, b) in list.indexed) {
        await boards[i].future;
        onBoard?.call(i, b);
      }
      await finish.future;
      return list;
    };
  }
}
