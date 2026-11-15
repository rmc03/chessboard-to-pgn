// A recognised diagram the user can correct and export.
//
// Coordinates: [Diagram.grid] is always stored from White's side (index 0 = a8, 63 = h1), whatever way up the
// book printed the diagram. Square indices and [squareName] therefore never change when the diagram is
// rotated with [Diagram.rotate180]; only the contents of the squares move. Views that show the board with
// Black at the bottom map an index to its screen position with [flipSquare].
import 'package:flutter/foundation.dart';

import 'chess.dart';
import 'locate.dart';
import 'pipeline.dart';

/// The four castling rights, in FEN order (KQkq).
enum CastlingRight {
  whiteKingside('K', 'Blancas O-O'),
  whiteQueenside('Q', 'Blancas O-O-O'),
  blackKingside('k', 'Negras O-O'),
  blackQueenside('q', 'Negras O-O-O');

  const CastlingRight(this.symbol, this.label);

  /// Letter in the FEN castling field.
  final String symbol;

  /// Spanish label for a chip.
  final String label;
}

/// Overall state of a diagram for the header line.
enum DiagramSeverity {
  /// Nothing to report.
  ok,

  /// Squares the reading is unsure about (and the position is legal).
  doubtful,

  /// The position cannot exist in a game (see [DiagramStatus.problems]).
  impossible,
}

/// What the header of a diagram block says, already in Spanish.
class DiagramStatus {
  const DiagramStatus(this.doubtfulCount, this.problems);

  /// Number of doubtful squares.
  final int doubtfulCount;

  /// Why the position is impossible, as short Spanish sentences ("Falta el rey blanco."). Empty when legal.
  final List<String> problems;

  bool get hasDoubts => doubtfulCount > 0;
  bool get hasProblems => problems.isNotEmpty;

  /// Problems win over doubts: an impossible position is the more urgent thing to show.
  DiagramSeverity get severity => hasProblems
      ? DiagramSeverity.impossible
      : hasDoubts
      ? DiagramSeverity.doubtful
      : DiagramSeverity.ok;

  /// "1 casilla dudosa" / "3 casillas dudosas"; null when there are none.
  String? get doubtfulText => hasDoubts
      ? (doubtfulCount == 1
            ? '1 casilla dudosa'
            : '$doubtfulCount casillas dudosas')
      : null;

  /// "Posición imposible: falta el rey blanco." (plus " Y N motivos más." when there are several); null when
  /// the position is legal.
  String? get problemText {
    if (!hasProblems) return null;
    final first = problems.first;
    final rest = problems.length - 1;
    final reason = first.endsWith('.')
        ? first.substring(0, first.length - 1)
        : first;
    final lower = reason[0].toLowerCase() + reason.substring(1);
    return 'Posición imposible: $lower.${rest > 0 ? ' Y $rest más.' : ''}';
  }

  /// The single line for the header: [problemText], else [doubtfulText], else null.
  String? get headline => problemText ?? doubtfulText;
}

/// Turns a problem string of [validate] (chess.dart) into a short Spanish sentence. Unknown strings are only
/// capitalised and ended with a full stop, so a new rule in [validate] still shows something sensible.
String describeProblem(String problem) {
  const known = {
    'tablero vacío': 'El tablero está vacío.',
    'falta el rey blanco': 'Falta el rey blanco.',
    'falta el rey negro': 'Falta el rey negro.',
    'hay más de un rey de un color': 'Hay más de un rey del mismo color.',
    'más de 8 peones blancos': 'Hay más de 8 peones blancos.',
    'más de 8 peones negros': 'Hay más de 8 peones negros.',
    'más de 16 piezas blancas': 'Hay más de 16 piezas blancas.',
    'más de 16 piezas negras': 'Hay más de 16 piezas negras.',
    'hay un peón en la fila 1 u 8':
        'Hay un peón en la primera o la última fila.',
    'el bando que no mueve está en jaque':
        'El bando que no mueve está en jaque.',
  };
  final hit = known[problem];
  if (hit != null) return hit;
  if (problem.isEmpty) return problem;
  final sentence = problem[0].toUpperCase() + problem.substring(1);
  return sentence.endsWith('.') ? sentence : '$sentence.';
}

/// Screen position (0..63, row-major from the top-left) of square [sq] when the board is drawn with Black at
/// the bottom; the same function maps back. `flipSquare(flipSquare(x)) == x`.
int flipSquare(int sq) => 63 - sq;

class Diagram extends ChangeNotifier {
  Diagram({
    required this.grid,
    required this.confidence,
    required this._turn,
    Set<CastlingRight> castlingSwitchedOff = const {},
    this.box,
    this.fallback = false,
    this.manual = false,
    this.originalCrop,
    this._seenFromBlack = false,
  }) : _castlingOff = {...castlingSwitchedOff};

  factory Diagram.fromRecognized(RecognizedBoard b) => Diagram(
    grid: List<int>.of(b.grid),
    confidence: List<double>.of(b.confidence),
    // a picture cannot tell whose move it is (unless a king is in check, which [turn] enforces on its own)
    turn: 'w',
    box: b.box,
    fallback: b.fallback,
    manual: b.manual,
    originalCrop: b.originalCrop,
  );

  /// Builds a diagram from a FEN placement (all squares fully trusted). Handy for tests.
  factory Diagram.fromPlacement(String placement, {String turn = 'w'}) =>
      Diagram(
        grid: placementToGrid(placement),
        confidence: List<double>.filled(64, 1),
        turn: turn,
      );

  /// The 64 squares from White's side (see the library comment). Changed in place by [setSquare] and
  /// [rotate180]: listen to the diagram instead of keeping copies.
  final List<int> grid;

  /// Per-square confidence, same order as [grid]; below [doubtful] a square is doubtful.
  final List<double> confidence;

  /// Where the board was found in the source image (pixels), or null. Never changes, not even on rotation.
  final Box? box;

  /// No framed diagram was found; the whole image was used.
  final bool fallback;

  /// The user drew the region by hand.
  final bool manual;

  /// PNG of the board exactly as the book shows it: the [box] cut from the source image with no margin and the
  /// longest side capped (about 600 px), so it overlays the drawn board square for square. Null for diagrams
  /// that did not come from an image. It is NOT rotated by [rotate180].
  ///
  /// To compare "Leído | Original" draw the read board with the same orientation as this picture: Black at the
  /// bottom when [seenFromBlack] is true (use [flipSquare] to place the squares), White at the bottom otherwise.
  final Uint8List? originalCrop;

  String _turn;
  final Set<CastlingRight> _castlingOff;
  bool _seenFromBlack;

  static const double doubtful = 0.9;

  // ---------------------------------------------------------------- squares

  bool isDoubtful(int sq) => confidence[sq] < doubtful;

  int get doubtfulCount => doubtfulSquares.length;

  bool get hasDoubts => doubtfulCount > 0;

  /// Doubtful squares in index order (a8, b8 … h1), for the "Revisar dudosas" flow.
  List<int> get doubtfulSquares => [
    for (var sq = 0; sq < 64; sq++)
      if (isDoubtful(sq)) sq,
  ];

  /// The next doubtful square after [sq] in index order, excluding [sq] itself; null when there is none. With
  /// [wrap] (default) the search continues from a8 after h1, so the review loops until nothing is doubtful.
  int? nextDoubtfulAfter(int sq, {bool wrap = true}) {
    for (var i = sq + 1; i < 64; i++) {
      if (isDoubtful(i)) return i;
    }
    if (wrap) {
      for (var i = 0; i < sq; i++) {
        if (isDoubtful(i)) return i;
      }
    }
    return null;
  }

  /// The user fixed a square: it is trusted from now on.
  void setSquare(int sq, int cls) {
    grid[sq] = cls;
    confidence[sq] = 1;
    notifyListeners();
  }

  /// The user says the reading of [sq] is right: it is trusted from now on, the piece does not change.
  void confirmSquare(int sq) {
    if (confidence[sq] == 1) return;
    confidence[sq] = 1;
    notifyListeners();
  }

  /// "e4, caballo blanco, dudosa" / "a1, vacía" (screen readers).
  String squareLabel(int sq) =>
      '${squareName(sq)}, ${pieceNames[grid[sq]]}${isDoubtful(sq) ? ', dudosa' : ''}';

  // ------------------------------------------------------------ orientation

  /// The book printed this diagram from Black's side (the picture had a1 at the top right). Set by
  /// [rotate180]; it only tells the UI which way up the original is.
  bool get seenFromBlack => _seenFromBlack;

  /// "Ver desde las negras": reverses the 64 squares (and their confidences) so the position is stored from
  /// White's side. Call it when the reading came out upside down; calling it again undoes it. [originalCrop]
  /// and [box] are left alone: they describe the picture, not the position.
  void rotate180() {
    final g = grid.reversed.toList();
    final c = confidence.reversed.toList();
    grid.setAll(0, g);
    confidence.setAll(0, c);
    _seenFromBlack = !_seenFromBlack;
    notifyListeners();
  }

  // ------------------------------------------------------------------- turn

  /// 'w' or 'b' when the position forces the side to move (exactly one king is in check), else null.
  String? get forcedTurn => suggestTurn(placement);

  bool get turnIsForced => forcedTurn != null;

  /// Why the control is locked ("El rey negro está en jaque: mueven negras."); null when the turn is free.
  String? get forcedTurnReason => switch (forcedTurn) {
    'w' => 'El rey blanco está en jaque: mueven blancas.',
    'b' => 'El rey negro está en jaque: mueven negras.',
    _ => null,
  };

  /// Side to move, 'w' or 'b'. While [turnIsForced] this is the forced side and the setter's value is kept
  /// but has no effect (it applies again if an edit lifts the check).
  String get turn => forcedTurn ?? _turn;
  set turn(String value) {
    assert(value == 'w' || value == 'b');
    final before = turn;
    _turn = value;
    if (turn != before) notifyListeners();
  }

  // --------------------------------------------------------------- castling

  /// The rights the king/rook placement allows (recomputed from the current squares, so editing a square
  /// updates it). The chips of the UI show exactly these.
  Set<CastlingRight> get possibleCastling {
    final letters = guessCastling(placement);
    return {
      for (final r in CastlingRight.values)
        if (letters.contains(r.symbol)) r,
    };
  }

  /// Whether the user keeps [right] on. True by default for every right, also for impossible ones.
  bool isCastlingEnabled(CastlingRight right) => !_castlingOff.contains(right);

  /// The rights that end up in the FEN: possible and not switched off.
  Set<CastlingRight> get activeCastling => {
    for (final r in possibleCastling)
      if (isCastlingEnabled(r)) r,
  };

  void setCastlingEnabled(CastlingRight right, bool enabled) {
    if (enabled == isCastlingEnabled(right)) return;
    enabled ? _castlingOff.remove(right) : _castlingOff.add(right);
    notifyListeners();
  }

  /// The FEN castling field: active rights in KQkq order, or '-'.
  String get castlingField {
    final active = activeCastling;
    final letters = [
      for (final r in CastlingRight.values)
        if (active.contains(r)) r.symbol,
    ].join();
    return letters.isEmpty ? '-' : letters;
  }

  /// Old on/off choice, kept for the first UI: false means "no castling" (all four switched off), true means
  /// every right the placement allows. The getter is false only when all four are switched off.
  bool get castlingPossible =>
      _castlingOff.length < CastlingRight.values.length;
  set castlingPossible(bool value) {
    final before = castlingField;
    _castlingOff
      ..clear()
      ..addAll(value ? const <CastlingRight>{} : CastlingRight.values);
    if (castlingField != before) notifyListeners();
  }

  // ----------------------------------------------------------------- output

  String get placement => gridToPlacement(grid);

  /// Full FEN: placement, side to move, active castling rights, no en passant.
  String get fen => toFen(placement, turn: turn, castling: castlingField);

  /// Raw (Spanish, lower-case) problems of [validate]. See [status] for sentences.
  List<String> get problems => validate(fen);

  /// Header information: doubtful squares and impossible-position reasons.
  DiagramStatus get status =>
      DiagramStatus(doubtfulCount, problems.map(describeProblem).toList());

  /// One-game PGN for this diagram; the Event tag reads "Diagrama [number]".
  String pgn(int number) => toPgn(fen, event: 'Diagrama $number');
}

String squareName(int sq) => '${'abcdefgh'[sq % 8]}${8 - sq ~/ 8}';
