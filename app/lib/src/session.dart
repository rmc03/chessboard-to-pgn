// The working list of the current run of the app: every captured image ("captura") read so far and its
// diagrams. The session ACCUMULATES captures; nothing is persisted between runs of the app (undecided in
// PRODUCT.md, so deliberately not done).
//
// UI contract:
//  * Listen to the [Session] (a [ChangeNotifier]) for structure and progress: captures added/removed,
//    reading progress, diagrams added/removed/replaced.
//  * Listen to a [SourceImage] (also a [ChangeNotifier]) for the changes of that capture only (its progress, its
//    diagrams): a group of the list rebuilds on its own source, not on every change of the session.
//  * Listen to each [Diagram] (also a [ChangeNotifier]) for edits of that diagram (square, turn, castling).
//    The session does not forward them: it does not need to, `allPgn` is computed on demand.
import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'classifier.dart';
import 'diagram.dart';
import 'locate.dart';
import 'pipeline.dart';

/// Reads every diagram of an image, reporting progress (see [recognizeImageStreaming], the default). A fake
/// for widget tests must call [onFound] once, then [onBoard] for each board, and return the boards in order.
typedef ReadImageFn = Future<List<RecognizedBoard>> Function(
  Uint8List bytes, {
  BoardsFoundFn? onFound,
  BoardReadFn? onBoard,
});

/// Reads the single board inside a hand-drawn [region] (image pixels); see [recognizeRegion].
typedef ReadRegionFn = Future<RecognizedBoard> Function(
  Uint8List bytes,
  Box region,
);

/// Why a capture or a hand-drawn region could not be read; [message] is Spanish and fit to show as is.
class ReadFailure implements Exception {
  const ReadFailure(this.message, [this.cause]);

  final String message;

  /// The underlying error, for logs.
  final Object? cause;

  @override
  String toString() => message;
}

enum SourceStatus {
  /// Added while another capture is still being read; waits its turn (see [Session.addImage]).
  queued,

  /// Being read: [SourceImage.found] / [SourceImage.read] tell how far.
  reading,

  /// Read; [SourceImage.diagrams] holds the result (it may be empty if the user removed them all).
  done,

  /// The reader found no board. The UI offers "Recortar a mano" ([Session.readRegion]).
  noBoards,

  /// Unexpected error; [SourceImage.errorMessage] says what to tell the user. The UI offers
  /// [Session.retry].
  failed,
}

/// One captured image and what was read from it.
class SourceImage extends ChangeNotifier {
  SourceImage._(this.id, this.bytes, this._number);

  /// Unique within the run and never reused: a stable key for widgets.
  final int id;

  /// The original encoded image, kept for the manual crop screen.
  final Uint8List bytes;

  int _number;
  int _width = 0, _height = 0;
  SourceStatus _status = SourceStatus.queued;
  int? _found;
  int _read = 0;
  String? _errorMessage;
  Object? _error;
  final List<Diagram> _diagrams = [];
  bool _discarded = false;
  Completer<void> _finished = Completer<void>();

  /// 1-based position of the capture in the session ("Captura N"). Renumbered when a capture is removed.
  int get number => _number;

  /// "Captura 2".
  String get title => 'Captura $_number';

  /// Pixel size of the image the diagram boxes refer to (EXIF rotation already applied); 0 until the reader
  /// has reported it, and for a capture that could not be decoded.
  int get width => _width;
  int get height => _height;

  SourceStatus get status => _status;

  /// Queued or reading.
  bool get isPending =>
      _status == SourceStatus.queued || _status == SourceStatus.reading;

  /// How many boards were located; null until known.
  int? get found => _found;

  /// How many of those boards have been read and are already in [diagrams] (they are released in reading
  /// order, so `read` never counts a board that sits behind an unfinished one).
  int get read => _read;

  /// Spanish message for [SourceStatus.failed], else null.
  String? get errorMessage => _errorMessage;

  /// The error behind [errorMessage], for logs.
  Object? get error => _error;

  /// The diagrams read so far, in reading order (top to bottom, left to right). Unmodifiable view.
  late final List<Diagram> diagrams = UnmodifiableListView(_diagrams);

  /// Skeletons the UI still has to draw while reading: located but not yet read.
  int get skeletons => _status == SourceStatus.reading
      ? ((_found ?? 0) - _read).clamp(0, 1 << 20)
      : 0;

  /// 0..1 for a determinate progress bar; null (indeterminate) while the boards are not located yet.
  double? get progress {
    final n = _found;
    if (n == null) return null;
    return n == 0 ? 1 : _read / n;
  }

  /// "En espera…", "Buscando diagramas…", "Leyendo 2 de 4…" while pending, else null.
  String? get progressText {
    switch (_status) {
      case SourceStatus.queued:
        return 'En espera…';
      case SourceStatus.reading:
        final n = _found;
        if (n == null) return 'Buscando diagramas…';
        if (n == 0) return 'Leyendo…';
        return 'Leyendo ${(_read + 1).clamp(1, n)} de $n…';
      case SourceStatus.done:
      case SourceStatus.noBoards:
      case SourceStatus.failed:
        return null;
    }
  }

  /// "1 diagrama" / "3 diagramas" / "Sin diagramas".
  String get diagramCountText => switch (_diagrams.length) {
    0 => 'Sin diagramas',
    1 => '1 diagrama',
    final n => '$n diagramas',
  };

  /// Completes when this capture is no longer pending (done, noBoards, failed or removed).
  Future<void> get finished => _finished.future;

  void _touch() => notifyListeners();
}

/// How many doubtful squares make the reading of a whole-image fallback board implausible.
const int implausibleDoubts = 16;

/// The reader found no frame and read the whole image as one board, and the reading is mostly doubt: the
/// image is not a diagram. [Session] then ends the capture as [SourceStatus.noBoards] (no diagram) so the UI
/// offers "Recortar a mano" instead of a nonsense position. A fallback board with fewer doubts is kept.
bool implausibleFallback(RecognizedBoard board) =>
    board.fallback &&
    board.confidence.where((c) => c < Diagram.doubtful).length >=
        implausibleDoubts;

/// What [Session.removeDiagram] took out; hand it to [Session.restore] to undo ("Deshacer").
class RemovedDiagram {
  const RemovedDiagram._(this.diagram, this.source, this.index);

  final Diagram diagram;
  final SourceImage source;

  /// Position the diagram had inside [source].
  final int index;
}

/// What [Session.removeSource] took out; hand it to [Session.restoreSource] to undo ("Deshacer").
class RemovedSource {
  const RemovedSource._(this.source, this.index, this.restorable);

  final SourceImage source;

  /// Position the capture had in the session.
  final int index;

  /// False for a capture that was still being read: its reader was told to stop, so it cannot come back as it
  /// was (add the image again instead).
  final bool restorable;
}

/// What [Session.clear] took out; hand it to [Session.restoreCleared] to undo ("Deshacer").
class ClearedSession {
  const ClearedSession._(this.sources);

  /// The captures that were read (or had failed) when the session was cleared, in order.
  final List<SourceImage> sources;

  /// Nothing can come back (every capture was still being read).
  bool get isEmpty => sources.isEmpty;
}

class Session extends ChangeNotifier {
  /// [readImage] and [readRegion] default to the real pipeline, which loads the model assets from
  /// [assets] (default `rootBundle`) lazily, once, on the first read. Pass fakes in widget tests.
  Session({this._readImage, this._readRegion, AssetBundle? assets})
    : _assets = assets ?? rootBundle;

  final ReadImageFn? _readImage;
  final ReadRegionFn? _readRegion;
  final AssetBundle _assets;

  final List<SourceImage> _sources = [];
  final List<SourceImage> _queue = [];
  int _nextId = 1;
  int _regionReads = 0;
  bool _pumping = false;
  bool _disposed = false;
  Future<ModelAssets>? _model;

  // ------------------------------------------------------------------ state

  /// The captures in the order they were added. Unmodifiable snapshot.
  List<SourceImage> get sources => List.unmodifiable(_sources);

  /// Every diagram of every capture, in display order (the order numbers follow). Unmodifiable snapshot.
  List<Diagram> get diagrams =>
      List.unmodifiable([for (final s in _sources) ...s._diagrams]);

  int get diagramCount => _sources.fold(0, (n, s) => n + s._diagrams.length);

  /// Nothing in the session: no captures at all (show the first-run screen). A capture that is reading or
  /// failed makes the session non-empty.
  bool get isEmpty => _sources.isEmpty;

  /// A capture is queued/reading or a manual region is being read: disable actions that would clash.
  bool get isBusy => _regionReads > 0 || _sources.any((s) => s.isPending);

  /// Global number (1..N) of [diagram] in display order, 0 if it is not in the session. Recomputed on the
  /// fly, so it is always right after removals, restores and replacements.
  int numberOf(Diagram diagram) {
    var n = 0;
    for (final s in _sources) {
      for (final d in s._diagrams) {
        n++;
        if (identical(d, diagram)) return n;
      }
    }
    return 0;
  }

  /// The capture [diagram] belongs to, or null.
  SourceImage? sourceOf(Diagram diagram) {
    for (final s in _sources) {
      if (s._diagrams.any((d) => identical(d, diagram))) return s;
    }
    return null;
  }

  /// Diagrams with doubtful squares or an impossible position, in display order.
  List<Diagram> get flagged => [
    for (final d in diagrams)
      if (d.hasWarnings) d,
  ];

  /// How many diagrams are [flagged].
  int get flaggedCount => flagged.length;

  /// The next diagram after [diagram] (display order, wrapping round) that still has doubtful squares; null when
  /// no other diagram has any.
  Diagram? nextWithDoubtsAfter(Diagram diagram) {
    final all = diagrams;
    final at = all.indexWhere((d) => identical(d, diagram));
    for (var i = 1; i <= all.length; i++) {
      final d = all[(at + i) % all.length];
      if (!identical(d, diagram) && d.hasDoubts) return d;
    }
    return null;
  }

  /// PGN of every diagram, one game each (`[Event "Diagrama N"]`), joined as the app has always exported.
  String get allPgn =>
      [for (final (i, d) in diagrams.indexed) d.pgn(i + 1)].join('\n');

  /// PGN of one diagram with its session number; empty string if it is not in the session.
  String pgnOf(Diagram diagram) {
    final n = numberOf(diagram);
    return n == 0 ? '' : diagram.pgn(n);
  }

  // ----------------------------------------------------------- adding images

  /// Adds a capture and starts reading it. The capture appears in [sources] immediately (before this method
  /// returns), then [SourceImage.found] is set as soon as the boards are located and [SourceImage.read] grows
  /// by one as each board finishes, ending in [SourceStatus.done], [SourceStatus.noBoards] or
  /// [SourceStatus.failed] (a failure is a status, never a thrown error).
  ///
  /// Captures are read one at a time, in the order added: one added while another is reading waits in
  /// [SourceStatus.queued]. (Boards of one capture are classified in parallel already; running whole captures
  /// in parallel would only compete for the same cores and memory.)
  SourceImage enqueueImage(Uint8List bytes) {
    final source = SourceImage._(_nextId++, bytes, _sources.length + 1);
    _sources.add(source);
    _queue.add(source);
    _changed();
    _pump();
    return source;
  }

  /// [enqueueImage] and wait until the capture has been read. Returns it.
  Future<SourceImage> addImage(Uint8List bytes) async {
    final source = enqueueImage(bytes);
    await source.finished;
    return source;
  }

  /// Reads a [SourceStatus.failed] capture again from the start (its diagrams, if any, are dropped). No-op
  /// for a capture that is not failed or not in the session.
  void retry(SourceImage source) {
    if (source._discarded || source._status != SourceStatus.failed) return;
    source
      .._diagrams.clear()
      .._found = null
      .._read = 0
      .._errorMessage = null
      .._error = null
      .._status = SourceStatus.queued
      .._finished = Completer<void>();
    _queue.add(source);
    _changed(source: source);
    _pump();
  }

  Future<void> _pump() async {
    if (_pumping) return;
    _pumping = true;
    try {
      while (_queue.isNotEmpty) {
        final source = _queue.removeAt(0);
        if (source._discarded) {
          _complete(source);
        } else {
          await _read(source);
        }
      }
    } finally {
      _pumping = false;
    }
  }

  void _complete(SourceImage source) {
    if (!source._finished.isCompleted) source._finished.complete();
  }

  Future<void> _read(SourceImage source) async {
    source._status = SourceStatus.reading;
    _changed(source: source);
    final done = <int, RecognizedBoard>{};
    var next = 0; // index of the next board to release into source.diagrams

    // A lone whole-image fallback board whose reading is implausible is not shown: it would flash in and out
    // when the capture ends as noBoards (see [implausibleFallback]). [force] releases it all the same.
    void release({bool force = false}) {
      while (done.containsKey(next)) {
        final board = done[next]!;
        if (!force && (source._found ?? 1) == 1 && implausibleFallback(board)) {
          break;
        }
        source._diagrams.add(Diagram.fromRecognized(done.remove(next)!));
        next++;
      }
      source._read = next;
    }

    try {
      final boards = await (_readImage ?? _defaultReadImage)(
        source.bytes,
        onFound: (count, width, height) {
          if (source._discarded) return;
          source
            .._found = count
            .._width = width
            .._height = height;
          _changed(source: source);
        },
        onBoard: (index, board) {
          if (source._discarded) return;
          done[index] = board;
          release();
          _changed(source: source);
        },
      );
      if (source._discarded) return;
      // The returned list is authoritative: add whatever the progress callbacks did not deliver.
      for (var i = next; i < boards.length; i++) {
        done.putIfAbsent(i, () => boards[i]);
      }
      final lone = boards.length == 1 && implausibleFallback(boards.first);
      release(force: !lone);
      source._found = lone ? 0 : boards.length;
      source._status = boards.isEmpty || lone
          ? SourceStatus.noBoards
          : SourceStatus.done;
    } catch (e) {
      if (source._discarded) return;
      source
        .._status = SourceStatus.failed
        .._error = e
        .._errorMessage = _describeFailure(e, whole: true);
    } finally {
      _complete(source);
      _changed(source: source);
    }
  }

  // ------------------------------------------------------------ manual crop

  /// Reads the single board inside [region] (pixels of [SourceImage.bytes], as the crop screen reports them)
  /// and puts it in [source]:
  ///  * with [replacing] (a diagram of [source], "Ajustar recorte") the new diagram takes its place in the
  ///    list; the user's edits to the old one are lost (it is a new reading) except that a diagram that was
  ///    [Diagram.seenFromBlack] stays rotated;
  ///  * otherwise it is appended at the end of the capture (a new diagram is always the last of its capture).
  ///
  /// If [replacing] is no longer in [source] (removed meanwhile) the new diagram is appended.
  /// A capture that was [SourceStatus.noBoards] or [SourceStatus.failed] becomes [SourceStatus.done].
  /// Returns the new diagram. Throws [ReadFailure] (Spanish message) when the region cannot be read, when
  /// the capture is still being read, or when it was removed meanwhile; nothing changes in that case.
  Future<Diagram> readRegion(
    SourceImage source,
    Box region, {
    Diagram? replacing,
  }) async {
    if (source._discarded || !_sources.contains(source)) {
      throw const ReadFailure(
        'Esta captura ya no está en la lista. Añádela de nuevo.',
      );
    }
    if (source.isPending) {
      throw const ReadFailure('Espera a que termine de leerse la captura.');
    }
    _regionReads++;
    _changed();
    final RecognizedBoard board;
    try {
      board = await (_readRegion ?? _defaultReadRegion)(source.bytes, region);
    } catch (e) {
      throw ReadFailure(_describeFailure(e, whole: false), e);
    } finally {
      _regionReads--;
      _changed(source: source);
    }
    if (source._discarded) {
      throw const ReadFailure(
        'La captura se quitó mientras se leía el recorte. Añádela de nuevo.',
      );
    }
    final fresh = Diagram.fromRecognized(board);
    final at = replacing == null
        ? -1
        : source._diagrams.indexWhere((d) => identical(d, replacing));
    if (at >= 0) {
      if (replacing!.seenFromBlack) fresh.rotate180();
      source._diagrams[at] = fresh;
    } else {
      source._diagrams.add(fresh);
    }
    if (source._status == SourceStatus.noBoards ||
        source._status == SourceStatus.failed) {
      source
        .._status = SourceStatus.done
        .._errorMessage = null
        .._error = null;
    }
    _changed(source: source);
    return fresh;
  }

  // ---------------------------------------------------------------- removal

  /// Takes [diagram] out of the session. Returns what [restore] needs to bring it back, or null if it was
  /// not in the session. Following diagrams are renumbered (numbers are never stored).
  RemovedDiagram? removeDiagram(Diagram diagram) {
    for (final s in _sources) {
      final i = s._diagrams.indexWhere((d) => identical(d, diagram));
      if (i < 0) continue;
      s._diagrams.removeAt(i);
      _changed(source: s);
      return RemovedDiagram._(diagram, s, i);
    }
    return null;
  }

  /// Undoes [removeDiagram]: the diagram returns to its capture at its old position (its edits are intact).
  /// False when it cannot (its capture was removed meanwhile, or it is already back).
  bool restore(RemovedDiagram removed) {
    final s = removed.source;
    if (s._discarded || !_sources.contains(s)) return false;
    if (s._diagrams.any((d) => identical(d, removed.diagram))) return false;
    s._diagrams.insert(
      removed.index.clamp(0, s._diagrams.length),
      removed.diagram,
    );
    _changed(source: s);
    return true;
  }

  /// Removes a capture with its diagrams (also while it is being read: the result is discarded). Later
  /// captures are renumbered. Returns what [restoreSource] needs to undo it; null if it was not in the session.
  RemovedSource? removeSource(SourceImage source) {
    final index = _sources.indexOf(source);
    if (index < 0) return null;
    _sources.removeAt(index);
    final restorable = !source.isPending;
    source._discarded = true;
    _queue.remove(source);
    _complete(source); // a reader that is still running ignores it from now on
    _renumber();
    _changed(source: source);
    return RemovedSource._(source, index, restorable);
  }

  /// Undoes [removeSource]: the capture returns at its old position with its diagrams and edits intact, and the
  /// captures after it are renumbered. False when it cannot (it was being read, or it is already back).
  bool restoreSource(RemovedSource removed) {
    final s = removed.source;
    if (!removed.restorable || _sources.contains(s)) return false;
    s._discarded = false;
    _sources.insert(removed.index.clamp(0, _sources.length), s);
    _renumber();
    _changed(source: s);
    return true;
  }

  /// "Quitar todas las capturas": removes every capture. Returns the token for [restoreCleared]; null when there
  /// was nothing to clear.
  ClearedSession? clear() {
    if (_sources.isEmpty) return null;
    final kept = [
      for (final s in _sources)
        if (!s.isPending) s,
    ];
    for (final s in _sources) {
      s._discarded = true;
      _complete(s);
    }
    _sources.clear();
    _queue.clear();
    _changed();
    return ClearedSession._(kept);
  }

  /// Undoes [clear]: the captures that had been read come back, before anything added since, and everything is
  /// renumbered. False when there is nothing to bring back.
  bool restoreCleared(ClearedSession cleared) {
    final back = [
      for (final s in cleared.sources)
        if (!_sources.contains(s)) s,
    ];
    if (back.isEmpty) return false;
    for (final s in back) {
      s._discarded = false;
    }
    _sources.insertAll(0, back);
    _renumber();
    _changed();
    for (final s in back) {
      s._touch();
    }
    return true;
  }

  void _renumber() {
    for (var i = 0; i < _sources.length; i++) {
      _sources[i]._number = i + 1;
    }
  }

  // --------------------------------------------------------- default reader

  Future<ModelAssets> _loadModel() => _model ??= () async {
    try {
      return ModelAssets(
        await _assets.loadString('assets/model/manifest.json'),
        (await _assets.load('assets/model/weights.bin')).buffer.asUint8List(),
      );
    } catch (_) {
      _model = null; // let the next read try again
      rethrow;
    }
  }();

  Future<List<RecognizedBoard>> _defaultReadImage(
    Uint8List bytes, {
    BoardsFoundFn? onFound,
    BoardReadFn? onBoard,
  }) async => recognizeImageStreaming(
    bytes,
    await _loadModel(),
    onFound: onFound,
    onBoard: onBoard,
  );

  Future<RecognizedBoard> _defaultReadRegion(
    Uint8List bytes,
    Box region,
  ) async => recognizeRegion(bytes, region, await _loadModel());

  static String _describeFailure(Object error, {required bool whole}) {
    if (error is ReadFailure) return error.message;
    if (error is FormatException) {
      return 'No se pudo abrir la imagen. Prueba con otra captura.';
    }
    return whole
        ? 'No se pudo leer esta captura. Inténtalo de nuevo.'
        : 'No se pudo leer el recorte. Prueba a encuadrar el tablero de otra forma.';
  }

  // ------------------------------------------------------------------ misc

  void _changed({SourceImage? source}) {
    if (_disposed) return;
    source?._touch();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
