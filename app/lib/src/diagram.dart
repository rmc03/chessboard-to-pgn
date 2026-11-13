// A recognised diagram the user can correct and export.
import 'chess.dart';
import 'locate.dart';
import 'pipeline.dart';

class Diagram {
  Diagram({
    required this.grid,
    required this.confidence,
    required this.turn,
    this.castlingPossible = true,
    this.box,
    this.fallback = false,
  });

  factory Diagram.fromRecognized(RecognizedBoard b) => Diagram(
    grid: List<int>.of(b.grid),
    confidence: List<double>.of(b.confidence),
    // a picture cannot tell whose move it is, unless one side is in check
    turn: suggestTurn(b.placement) ?? 'w',
    box: b.box,
    fallback: b.fallback,
  );

  /// Builds a diagram from a FEN placement (all squares fully trusted). Handy for tests.
  factory Diagram.fromPlacement(String placement, {String turn = 'w'}) =>
      Diagram(
        grid: placementToGrid(placement),
        confidence: List<double>.filled(64, 1),
        turn: turn,
      );

  final List<int> grid;
  final List<double> confidence;
  String turn; // 'w' or 'b'
  bool castlingPossible; // true: every right the king/rook placement allows; false: none ('-')
  final Box? box;
  final bool fallback;

  static const double doubtful = 0.9;

  bool isDoubtful(int sq) => confidence[sq] < doubtful;
  int get doubtfulCount =>
      List<int>.generate(64, (i) => i).where(isDoubtful).length;

  String get placement => gridToPlacement(grid);
  String get fen =>
      toFen(placement, turn: turn, castling: castlingPossible ? null : '-');
  List<String> get problems => validate(fen);

  /// The user fixed a square: it is trusted from now on.
  void setSquare(int sq, int cls) {
    grid[sq] = cls;
    confidence[sq] = 1;
  }

  String pgn(int number) => toPgn(fen, event: 'Diagram $number');
}

String squareName(int sq) => '${'abcdefgh'[sq % 8]}${8 - sq ~/ 8}';
