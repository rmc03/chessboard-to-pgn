import 'dart:async';
import 'dart:io';

import 'package:chessboard_pgn/src/chess.dart';
import 'package:chessboard_pgn/src/diagram.dart';
import 'package:chessboard_pgn/src/locate.dart';
import 'package:chessboard_pgn/src/pipeline.dart';
import 'package:chessboard_pgn/src/session.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const sample = '4r1k1/1p3ppp/1qn5/3p4/Q3n3/1NP5/PP3PPP/R4BK1';
const start = 'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR';

RecognizedBoard board(String placement, {Box? box, double conf = 1}) {
  final grid = placementToGrid(placement);
  return RecognizedBoard(
    box ?? const Box(0, 0, 100, 100),
    grid,
    List<double>.filled(64, conf),
    grid,
    false,
  );
}

/// A reader that finds [placements].length boards and reports them one per microtask turn, in [order].
ReadImageFn fakeReader(List<String> placements, {List<int>? order}) =>
    (bytes, {onFound, onBoard}) async {
      final boards = [for (final p in placements) board(p)];
      await Future<void>.delayed(Duration.zero); // locating takes a moment
      onFound?.call(boards.length, 800, 600);
      for (final i in order ?? List.generate(boards.length, (i) => i)) {
        await Future<void>.delayed(Duration.zero);
        onBoard?.call(i, boards[i]);
      }
      return boards;
    };

final bytesA = Uint8List.fromList([1]);
final bytesB = Uint8List.fromList([2]);

/// (status, found, read) every time the session notifies.
List<(SourceStatus, int?, int)> record(Session s, SourceImage src) {
  final log = <(SourceStatus, int?, int)>[];
  s.addListener(() {
    final t = (src.status, src.found, src.read);
    if (log.isEmpty || log.last != t) log.add(t);
  });
  return log;
}

void main() {
  fallbackRules();
  group('adding captures', () {
    test(
      'the capture shows at once and progress goes found, then read 1..n',
      () async {
        final s = Session(readImage: fakeReader([sample, start, sample]));
        final src = s.enqueueImage(bytesA);
        final log = record(s, src);

        // visible before anything was read
        expect(s.sources, [src]);
        expect(s.isEmpty, isFalse);
        expect(src.number, 1);
        expect(src.title, 'Captura 1');
        expect(
          src.status,
          SourceStatus.reading,
        ); // started synchronously: nothing else was waiting
        expect(src.progressText, 'Buscando diagramas…');
        expect(src.found, isNull);
        expect(src.bytes, bytesA);
        expect(s.isBusy, isTrue);

        await src.finished;
        expect(log, [
          (SourceStatus.reading, 3, 0),
          (SourceStatus.reading, 3, 1),
          (SourceStatus.reading, 3, 2),
          (SourceStatus.reading, 3, 3),
          (SourceStatus.done, 3, 3),
        ]);
        expect(src.width, 800);
        expect(src.height, 600);
        expect(src.diagrams, hasLength(3));
        expect(src.diagrams.first.placement, sample);
        expect(src.progress, 1);
        expect(src.progressText, isNull);
        expect(s.isBusy, isFalse);
      },
    );

    test('progress text and skeletons while reading', () async {
      final gate = Completer<void>();
      final s = Session(
        readImage: (bytes, {onFound, onBoard}) async {
          if (bytes.first == 2) {
            return [board(sample)]; // the capture that goes first
          }
          onFound?.call(4, 10, 10);
          onBoard?.call(0, board(sample));
          await gate.future;
          return [for (var i = 0; i < 4; i++) board(sample)];
        },
      );
      final other = s.enqueueImage(bytesB);
      final src = s.enqueueImage(bytesA);
      expect(src.progressText, 'En espera…');
      await other.finished;
      await Future<void>.delayed(Duration.zero);
      expect(src.status, SourceStatus.reading);
      expect(src.found, 4);
      expect(src.read, 1);
      expect(src.skeletons, 3);
      expect(src.progressText, 'Leyendo 2 de 4…');
      expect(src.progress, 0.25);
      expect(src.diagrams, hasLength(1));
      gate.complete();
      await src.finished;
      expect(src.diagrams, hasLength(4));
      expect(src.skeletons, 0);
      expect(src.diagramCountText, '4 diagramas');
    });

    test(
      'boards that finish out of order are released in reading order',
      () async {
        final s = Session(
          readImage: fakeReader(
            [sample, start, '8/8/8/8/8/8/8/4K2k'],
            order: [2, 1, 0],
          ),
        );
        final src = s.enqueueImage(bytesA);
        final log = record(s, src);
        await src.finished;
        expect(
          log.map((t) => t.$3).toList(),
          [0, 3, 3],
          reason: 'nothing is released before board 0 is read, then all three at once',
        );
        expect(src.diagrams.map((d) => d.placement), [
          sample,
          start,
          '8/8/8/8/8/8/8/4K2k',
        ]);
      },
    );

    test(
      'a reader that returns the boards without progress callbacks still works',
      () async {
        final s = Session(
          readImage: (bytes, {onFound, onBoard}) async => [board(sample)],
        );
        final src = await s.addImage(bytesA);
        expect(src.status, SourceStatus.done);
        expect(src.found, 1);
        expect(src.diagrams, hasLength(1));
      },
    );

    test('no boards found', () async {
      final s = Session(readImage: fakeReader(const []));
      final src = await s.addImage(bytesA);
      expect(src.status, SourceStatus.noBoards);
      expect(src.diagrams, isEmpty);
      expect(src.diagramCountText, 'Sin diagramas');
      expect(
        s.isEmpty,
        isFalse,
      ); // the capture stays so the user can crop by hand
      expect(src.width, 800);
    });

    test('an unexpected error is a status with a Spanish message, and retry reads again', () async {
      var calls = 0;
      final s = Session(
        readImage: (bytes, {onFound, onBoard}) async {
          if (++calls == 1) throw StateError('boom');
          return fakeReader([sample])(
            bytes,
            onFound: onFound,
            onBoard: onBoard,
          );
        },
      );
      final src = await s.addImage(bytesA);
      expect(src.status, SourceStatus.failed);
      expect(
        src.errorMessage,
        'No se pudo leer esta captura. Inténtalo de nuevo.',
      );
      expect(src.error, isA<StateError>());
      expect(s.isBusy, isFalse);

      s.retry(src);
      expect(src.status, SourceStatus.reading);
      expect(src.errorMessage, isNull);
      await src.finished;
      expect(src.status, SourceStatus.done);
      expect(src.errorMessage, isNull);
      expect(src.diagrams, hasLength(1));
      expect(src.number, 1);
    });

    test('an image that cannot be decoded says so', () async {
      final s = Session(
        readImage: (bytes, {onFound, onBoard}) async =>
            throw const FormatException('No se pudo leer la imagen'),
      );
      final src = await s.addImage(bytesA);
      expect(src.status, SourceStatus.failed);
      expect(
        src.errorMessage,
        'No se pudo abrir la imagen. Prueba con otra captura.',
      );
    });

    test(
      'captures added while one is reading wait their turn and accumulate',
      () async {
        final order = <int>[];
        final gate = Completer<void>();
        final s = Session(
          readImage: (bytes, {onFound, onBoard}) async {
            order.add(bytes.first);
            if (bytes.first == 1) await gate.future;
            return fakeReader([sample])(
              bytes,
              onFound: onFound,
              onBoard: onBoard,
            );
          },
        );
        final a = s.enqueueImage(bytesA);
        final b = s.enqueueImage(bytesB);
        await Future<void>.delayed(Duration.zero);
        expect(a.status, SourceStatus.reading);
        expect(b.status, SourceStatus.queued);
        expect(b.number, 2);
        expect(order, [1]);
        gate.complete();
        await b.finished;
        expect(order, [1, 2]);
        expect(a.status, SourceStatus.done);
        expect(b.status, SourceStatus.done);
        expect(s.diagrams, hasLength(2));
        expect(s.sources, [a, b]);
      },
    );

    test('removing a capture while it is read discards the result', () async {
      final gate = Completer<void>();
      final s = Session(
        readImage: (bytes, {onFound, onBoard}) async {
          onFound?.call(1, 10, 10);
          await gate.future;
          onBoard?.call(0, board(sample));
          return [board(sample)];
        },
      );
      final a = s.enqueueImage(bytesA);
      final b = s.enqueueImage(bytesB);
      await Future<void>.delayed(Duration.zero);
      s.removeSource(a);
      s.removeSource(b); // still queued: never read
      expect(s.isEmpty, isTrue);
      gate.complete();
      await Future.wait([a.finished, b.finished]);
      expect(a.diagrams, isEmpty);
      expect(s.diagrams, isEmpty);
      expect(s.isBusy, isFalse);
    });
  });

  group('numbering, removal and restore', () {
    Future<(Session, List<SourceImage>)> two() async {
      var n = 0;
      final s = Session(
        readImage: (bytes, {onFound, onBoard}) => fakeReader(
          n++ == 0 ? [sample, start] : [start, sample, sample],
        )(bytes, onFound: onFound, onBoard: onBoard),
      );
      final a = await s.addImage(bytesA);
      final b = await s.addImage(bytesB);
      return (s, [a, b]);
    }

    test('numbers are global and follow display order', () async {
      final (s, [a, b]) = await two();
      expect(s.diagrams, hasLength(5));
      expect(s.diagramCount, 5);
      expect([for (final d in s.diagrams) s.numberOf(d)], [1, 2, 3, 4, 5]);
      expect(s.numberOf(b.diagrams.first), 3);
      expect(s.sourceOf(b.diagrams.last), b);
      expect(s.numberOf(Diagram.fromPlacement(sample)), 0);
    });

    test('removing renumbers; restore puts the diagram back where it was, edits included', () async {
      final (s, [a, b]) = await two();
      final victim = a.diagrams.first;
      victim.turn = 'b';
      final survivor = a.diagrams.last;
      var notified = 0;
      s.addListener(() => notified++);

      final removed = s.removeDiagram(victim)!;
      expect(notified, 1);
      expect(s.diagramCount, 4);
      expect(s.numberOf(survivor), 1);
      expect(s.numberOf(b.diagrams.first), 2);
      expect(s.numberOf(victim), 0);
      expect(s.removeDiagram(victim), isNull);

      expect(s.restore(removed), isTrue);
      expect(a.diagrams.first, same(victim));
      expect(victim.turn, 'b');
      expect([for (final d in s.diagrams) s.numberOf(d)], [1, 2, 3, 4, 5]);
      expect(s.restore(removed), isFalse); // already back
    });

    test('restore of a diagram whose capture is gone does nothing', () async {
      final (s, [a, _]) = await two();
      final removed = s.removeDiagram(a.diagrams.last)!;
      s.removeSource(a);
      expect(s.restore(removed), isFalse);
      expect(s.diagramCount, 3);
    });

    test('removing a capture renumbers captures and diagrams; clear empties everything', () async {
      final (s, [a, b]) = await two();
      s.removeSource(a);
      expect(b.number, 1);
      expect(b.title, 'Captura 1');
      expect(s.numberOf(b.diagrams.first), 1);
      s.clear();
      expect(s.isEmpty, isTrue);
      expect(s.diagrams, isEmpty);
      expect(s.allPgn, '');
    });

    test('removeSource returns a token; restoreSource brings the capture back where it was, renumbered', () async {
      final (s, [a, b]) = await two();
      final first = a.diagrams.first..turn = 'b';
      final removed = s.removeSource(a)!;
      expect(removed.restorable, isTrue);
      expect(removed.index, 0);
      expect(s.sources, [b]);
      expect(b.number, 1);
      expect(s.removeSource(a), isNull);

      expect(s.restoreSource(removed), isTrue);
      expect(s.sources, [a, b]);
      expect([a.number, b.number], [1, 2]);
      expect(a.diagrams.first, same(first));
      expect(first.turn, 'b');
      expect(s.diagramCount, 5);
      expect(s.restoreSource(removed), isFalse); // already back
    });

    test('a capture removed while it is being read cannot come back', () async {
      final gate = Completer<void>();
      final s = Session(
        readImage: (bytes, {onFound, onBoard}) async {
          await gate.future;
          return [board(sample)];
        },
      );
      final src = s.enqueueImage(bytesA);
      final removed = s.removeSource(src)!;
      expect(removed.restorable, isFalse);
      expect(s.restoreSource(removed), isFalse);
      gate.complete();
      await src.finished;
      expect(s.isEmpty, isTrue);
    });

    test('clear returns a token and restoreCleared puts the captures back before newer ones', () async {
      final (s, [a, b]) = await two();
      final token = s.clear()!;
      expect(s.isEmpty, isTrue);
      expect(token.sources, [a, b]);
      expect(s.clear(), isNull);

      final c = s.enqueueImage(bytesA);
      await c.finished;
      expect(s.restoreCleared(token), isTrue);
      expect(s.sources, [a, b, c]);
      expect([a.number, b.number, c.number], [1, 2, 3]);
      expect(s.diagramCount, 5 + c.diagrams.length);
      expect(s.restoreCleared(token), isFalse); // nothing left to bring back
    });

    test(
      'a capture that was still reading is not part of the clear token',
      () async {
        final gate = Completer<void>();
        final s = Session(
          readImage: (bytes, {onFound, onBoard}) async {
            await gate.future;
            return [board(sample)];
          },
        );
        s.enqueueImage(bytesA);
        final token = s.clear()!;
        expect(token.isEmpty, isTrue);
        expect(s.restoreCleared(token), isFalse);
        gate.complete();
      },
    );

    test(
      'a capture notifies its own listeners, not those of another capture',
      () async {
        final (s, [a, b]) = await two();
        var forA = 0, forB = 0;
        a.addListener(() => forA++);
        b.addListener(() => forB++);
        s.removeDiagram(a.diagrams.first);
        expect([forA, forB], [1, 0]);
        s.removeDiagram(b.diagrams.last);
        expect([forA, forB], [1, 1]);
      },
    );

    test('flagged lists diagrams with doubts or problems; nextWithDoubtsAfter wraps round', () async {
      final s = Session(
        readImage: (bytes, {onFound, onBoard}) async {
          final doubtful = board(sample)..confidence[0] = 0.5;
          final boards = [
            doubtful,
            board(sample),
            board('8/8/8/8/8/8/8/4K3'),
            board(sample)..confidence[9] = 0.2,
          ];
          onFound?.call(boards.length, 800, 600);
          for (final (i, b) in boards.indexed) {
            onBoard?.call(i, b);
          }
          return boards;
        },
      );
      final src = await s.addImage(bytesA);
      final d = src.diagrams;
      expect(s.flagged, [d[0], d[2], d[3]]);
      expect(s.flaggedCount, 3);
      expect(s.nextWithDoubtsAfter(d[0]), d[3]); // d[2] is only impossible
      expect(s.nextWithDoubtsAfter(d[3]), d[0]);
      d[3].confirmSquare(9);
      expect(s.nextWithDoubtsAfter(d[0]), isNull);
    });

    test('allPgn joins one game per diagram with its global number', () async {
      final (s, _) = await two();
      final pgn = s.allPgn;
      for (var i = 1; i <= 5; i++) {
        expect(pgn, contains('[Event "Diagrama $i"]'));
      }
      expect(
        RegExp(r'\[SetUp "1"\]').allMatches(pgn),
        hasLength(3),
      ); // the two start positions have no FEN tag
      expect(pgn, startsWith(s.diagrams.first.pgn(1)));
      expect(pgn, endsWith(s.diagrams.last.pgn(5)));
      // numbers follow removals
      s.removeDiagram(s.diagrams.first);
      expect(s.allPgn, isNot(contains('Diagrama 5')));
      expect(s.pgnOf(s.diagrams.first), s.diagrams.first.pgn(1));
    });
  });

  group('manual crop', () {
    const region = Box(10, 10, 90, 90);

    Session withRegionReader(
      ReadRegionFn region, {
      List<String> found = const [sample],
    }) => Session(readImage: fakeReader(found), readRegion: region);

    test('adds a new manual diagram at the end of the capture', () async {
      final s = withRegionReader((bytes, r) async => board(start, box: r));
      final src = await s.addImage(bytesA);
      final fresh = await s.readRegion(src, region);
      expect(src.diagrams, hasLength(2));
      expect(src.diagrams.last, same(fresh));
      expect(fresh.placement, start);
      expect(fresh.box, region);
      expect(s.numberOf(fresh), 2);
      expect(s.isBusy, isFalse);
    });

    test(
      'replaces a diagram in place, keeping its position and numbering',
      () async {
        final s = withRegionReader(
          (bytes, r) async => board(start, box: r),
          found: [sample, '8/8/8/8/8/8/8/4K2k', sample],
        );
        final src = await s.addImage(bytesA);
        final old = src.diagrams[1];
        final fresh = await s.readRegion(src, region, replacing: old);
        expect(src.diagrams, hasLength(3));
        expect(src.diagrams[1], same(fresh));
        expect(src.diagrams.contains(old), isFalse);
        expect(s.numberOf(fresh), 2);
        expect(fresh.placement, start);
      },
    );

    test('a replaced diagram that was seen from Black stays rotated', () async {
      final upside = gridToPlacement(placementToGrid(start).reversed.toList());
      final s = withRegionReader((bytes, r) async => board(upside, box: r));
      final src = await s.addImage(bytesA);
      final old = src.diagrams.single..rotate180();
      final fresh = await s.readRegion(src, region, replacing: old);
      expect(fresh.seenFromBlack, isTrue);
      expect(
        fresh.placement,
        gridToPlacement(placementToGrid(upside).reversed.toList()),
      );
    });

    test('replacing a diagram that was removed meanwhile appends', () async {
      final s = withRegionReader((bytes, r) async => board(start, box: r));
      final src = await s.addImage(bytesA);
      final old = src.diagrams.single;
      s.removeDiagram(old);
      final fresh = await s.readRegion(src, region, replacing: old);
      expect(src.diagrams, [fresh]);
    });

    test('is the way out of noBoards and failed', () async {
      final s = Session(
        readImage: fakeReader(const []),
        readRegion: (bytes, r) async => board(sample, box: r),
      );
      final src = await s.addImage(bytesA);
      expect(src.status, SourceStatus.noBoards);
      await s.readRegion(src, region);
      expect(src.status, SourceStatus.done);
      expect(src.diagrams, hasLength(1));
    });

    test('is busy while reading and failures are thrown with a message, changing nothing', () async {
      final gate = Completer<void>();
      var fail = true;
      final s = withRegionReader((bytes, r) async {
        await gate.future;
        if (fail) throw StateError('x');
        return board(start, box: r);
      });
      final src = await s.addImage(bytesA);
      final pending = s.readRegion(src, region);
      expect(s.isBusy, isTrue);
      gate.complete();
      await expectLater(
        pending,
        throwsA(
          isA<ReadFailure>().having(
            (e) => e.message,
            'message',
            'No se pudo leer el recorte. Prueba a encuadrar el tablero de otra forma.',
          ),
        ),
      );
      expect(s.isBusy, isFalse);
      expect(src.diagrams, hasLength(1));
      fail = false;
      await s.readRegion(src, region);
      expect(src.diagrams, hasLength(2));
    });

    test(
      'refuses a capture that is still being read or no longer in the session',
      () async {
        final gate = Completer<void>();
        final s = Session(
          readImage: (bytes, {onFound, onBoard}) async {
            await gate.future;
            return [board(sample)];
          },
          readRegion: (bytes, r) async => board(start),
        );
        final src = s.enqueueImage(bytesA);
        await expectLater(
          s.readRegion(src, region),
          throwsA(isA<ReadFailure>()),
        );
        gate.complete();
        await src.finished;
        s.removeSource(src);
        await expectLater(
          s.readRegion(src, region),
          throwsA(isA<ReadFailure>()),
        );
      },
    );
  });

  group('real pipeline', () {
    test(
      'reads the three-board fixture, with crops, through the default reader',
      () async {
        final s = Session(assets: _FileBundle());
        final bytes = File('test/fixtures/page_three_boards.png')
            .readAsBytesSync();
        final src = s.enqueueImage(bytes);
        final log = record(s, src);
        await src.finished;
        expect(src.error, isNull);
        expect(src.status, SourceStatus.done);
        expect(src.diagrams, hasLength(3));
        expect(src.width, greaterThan(0));
        expect(
          src.diagrams.every((d) => d.originalCrop != null && !d.fallback),
          isTrue,
        );
        expect(
          log.where((t) => t.$1 == SourceStatus.reading && t.$2 == 3).first,
          isNotNull,
        );
        expect(log.map((t) => t.$3), containsAllInOrder([0, 3]));

        // hand-crop the second board again through the real reader
        final old = src.diagrams[1];
        final fresh = await s.readRegion(src, old.box!, replacing: old);
        expect(fresh.manual, isTrue);
        expect(fresh.placement, old.placement);
        expect(src.diagrams[1], same(fresh));
      },
      timeout: const Timeout(Duration(minutes: 2)),
    );

    test('a file that is not an image fails with a message', () async {
      final s = Session(assets: _FileBundle());
      final src = await s.addImage(Uint8List.fromList([1, 2, 3]));
      expect(src.status, SourceStatus.failed);
      expect(src.errorMessage, isNotEmpty);
    });
  });
}

/// A whole-image fallback board with [doubts] doubtful squares.
RecognizedBoard fallbackBoard(int doubts) {
  final grid = placementToGrid(sample);
  final conf = List<double>.filled(64, 1);
  for (var i = 0; i < doubts; i++) {
    conf[i] = 0.4;
  }
  return RecognizedBoard(const Box(0, 0, 800, 600), grid, conf, grid, true);
}

void fallbackRules() {
  group('whole-image fallback', () {
    test('16 or more doubtful squares: the capture ends as noBoards with no diagram', () async {
      final s = Session(
        readImage: (bytes, {onFound, onBoard}) async {
          final boards = [fallbackBoard(16)];
          onFound?.call(1, 800, 600);
          onBoard?.call(0, boards.first);
          return boards;
        },
      );
      final seen = <int>[];
      s.addListener(() => seen.add(s.diagramCount));
      final src = await s.addImage(bytesA);
      expect(src.status, SourceStatus.noBoards);
      expect(src.diagrams, isEmpty);
      expect(s.diagramCount, 0);
      expect(src.found, 0);
      expect(
        seen.where((n) => n > 0),
        isEmpty,
        reason: 'it never flashes in as a diagram first',
      );
      expect(src.skeletons, 0);
      expect(src.progressText, isNull);
    });

    test('15 doubtful squares: still a plausible reading, kept', () async {
      final s = Session(
        readImage: (bytes, {onFound, onBoard}) async {
          final boards = [fallbackBoard(15)];
          onFound?.call(1, 800, 600);
          onBoard?.call(0, boards.first);
          return boards;
        },
      );
      final src = await s.addImage(bytesA);
      expect(src.status, SourceStatus.done);
      expect(src.diagrams.single.fallback, isTrue);
    });

    test(
      'the rule does not apply to a framed board, however doubtful',
      () async {
        final grid = placementToGrid(sample);
        final framed = RecognizedBoard(
          const Box(0, 0, 100, 100),
          grid,
          List<double>.filled(64, 0.3),
          grid,
          false,
        );
        final s = Session(
          readImage: (bytes, {onFound, onBoard}) async {
            onFound?.call(1, 800, 600);
            onBoard?.call(0, framed);
            return [framed];
          },
        );
        final src = await s.addImage(bytesA);
        expect(src.status, SourceStatus.done);
        expect(src.diagrams, hasLength(1));
      },
    );

    test('nor when the fallback is one of several boards', () async {
      final s = Session(
        readImage: (bytes, {onFound, onBoard}) async {
          final boards = [board(sample), fallbackBoard(20)];
          onFound?.call(2, 800, 600);
          for (final (i, b) in boards.indexed) {
            onBoard?.call(i, b);
          }
          return boards;
        },
      );
      final src = await s.addImage(bytesA);
      expect(src.status, SourceStatus.done);
      expect(src.diagrams, hasLength(2));
    });

    test('a hand-drawn region still turns the capture into done', () async {
      final s = Session(
        readImage: (bytes, {onFound, onBoard}) async => [fallbackBoard(30)],
        readRegion: (bytes, region) async => board(sample),
      );
      final src = await s.addImage(bytesA);
      expect(src.status, SourceStatus.noBoards);
      await s.readRegion(src, const Box(0, 0, 10, 10));
      expect(src.status, SourceStatus.done);
      expect(src.diagrams, hasLength(1));
    });

    test('implausibleFallback is exactly "fallback and 16 doubts"', () {
      expect(implausibleFallback(fallbackBoard(16)), isTrue);
      expect(implausibleFallback(fallbackBoard(15)), isFalse);
      expect(implausibleFallback(board(sample, conf: 0.1)), isFalse);
    });
  });
}

/// Serves the model from the files in `assets/` (the tests run from `app/`).
class _FileBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) async {
    final bytes = File(key).readAsBytesSync();
    return ByteData.sublistView(bytes);
  }
}
