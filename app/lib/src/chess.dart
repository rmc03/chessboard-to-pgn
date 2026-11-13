// FEN/PGN helpers and rule-constrained decoding of per-square probabilities.
// Port of prototype/chessdiag/fen.py: keep the two in sync.
//
// Grid convention everywhere: 64 entries, index = row * 8 + col, row 0 = rank 8, col 0 = file a
// (the diagram seen from White's side). Class ids: 0 = empty, 1..6 = PNBRQK, 7..12 = pnbrqk.
import 'dart:math' as math;
import 'dart:typed_data';

const List<String> classSymbols = [
  '.',
  'P',
  'N',
  'B',
  'R',
  'Q',
  'K',
  'p',
  'n',
  'b',
  'r',
  'q',
  'k',
];
const int whitePawn = 1, whiteKing = 6, blackPawn = 7, blackKing = 12;
const String startFen =
    'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1';

bool isWhite(int cls) => cls >= 1 && cls <= 6;
bool isBlack(int cls) => cls >= 7 && cls <= 12;

String gridToPlacement(List<int> grid) {
  final rows = <String>[];
  for (var r = 0; r < 8; r++) {
    final out = StringBuffer();
    var empty = 0;
    for (var c = 0; c < 8; c++) {
      final k = grid[r * 8 + c];
      if (k == 0) {
        empty++;
      } else {
        if (empty > 0) {
          out.write(empty);
          empty = 0;
        }
        out.write(classSymbols[k]);
      }
    }
    if (empty > 0) out.write(empty);
    rows.add(out.toString());
  }
  return rows.join('/');
}

List<int> placementToGrid(String placement) {
  final grid = <int>[];
  for (final ch in placement.split(' ').first.split('')) {
    if (ch == '/') continue;
    final digit = int.tryParse(ch);
    if (digit != null) {
      grid.addAll(List<int>.filled(digit, 0));
    } else {
      final k = classSymbols.indexOf(ch);
      if (k < 1) throw FormatException('bad piece "$ch" in $placement');
      grid.add(k);
    }
  }
  if (grid.length != 64) {
    throw FormatException('placement does not describe 64 squares: $placement');
  }
  return grid;
}

class Decoded {
  Decoded(this.grid, this.confidence, this.rawArgmax);
  final List<int> grid;

  /// Probability the model gave to the class finally chosen for each square.
  final List<double> confidence;

  /// Plain argmax before the chess rules were applied (diagnostics).
  final List<int> rawArgmax;
}

int _argmax(List<double> v, {int exclude = -1}) {
  var best = -1;
  var bestValue = double.negativeInfinity;
  for (var i = 0; i < v.length; i++) {
    if (i == exclude) continue;
    if (best < 0 || v[i] > bestValue) {
      best = i;
      bestValue = v[i];
    }
  }
  return best;
}

/// Most likely board that also obeys hard chess rules: no pawns on ranks 1/8, exactly one king per
/// colour, at most 8 pawns per colour. [probs] is 64 x 13 row-major.
Decoded decode(Float32List probs) {
  const eps = 1e-6;
  final lp = List<List<double>>.generate(
    64,
    (sq) => List<double>.generate(
      13,
      (c) => math.log(math.max(eps, math.min(1.0, probs[sq * 13 + c]))),
    ),
  );
  for (var sq = 0; sq < 64; sq++) {
    if (sq < 8 || sq >= 56) {
      lp[sq][whitePawn] = double.negativeInfinity;
      lp[sq][blackPawn] = double.negativeInfinity;
    }
  }
  final grid = List<int>.generate(64, (sq) => _argmax(lp[sq]));
  void reassign(int sq, int forbidden) =>
      grid[sq] = _argmax(lp[sq], exclude: forbidden);

  for (var pass = 0; pass < 2; pass++) {
    // a repair can create a violation for the other king
    for (final king in const [whiteKing, blackKing]) {
      final squares = [
        for (var s = 0; s < 64; s++)
          if (grid[s] == king) s,
      ];
      if (squares.length > 1) {
        var keep = squares.first;
        for (final s in squares) {
          if (lp[s][king] > lp[keep][king]) keep = s;
        }
        for (final s in squares) {
          if (s != keep) reassign(s, king);
        }
      } else if (squares.isEmpty) {
        var best = 0;
        var bestCost = double.negativeInfinity;
        for (var s = 0; s < 64; s++) {
          final cost = lp[s][king] - lp[s][grid[s]]; // cheapest square to flip
          if (cost > bestCost) {
            bestCost = cost;
            best = s;
          }
        }
        grid[best] = king;
      }
    }
    for (final pawn in const [whitePawn, blackPawn]) {
      final squares = [
        for (var s = 0; s < 64; s++)
          if (grid[s] == pawn) s,
      ];
      if (squares.length > 8) {
        squares.sort(
          (a, b) => lp[a][pawn].compareTo(lp[b][pawn]),
        ); // weakest first
        for (var i = 0; i < squares.length - 8; i++) {
          reassign(squares[i], pawn);
        }
      }
    }
  }
  final conf = List<double>.generate(
    64,
    (sq) => probs[sq * 13 + grid[sq]].toDouble(),
  );
  final raw = List<int>.generate(
    64,
    (sq) =>
        _argmax([for (var c = 0; c < 13; c++) probs[sq * 13 + c].toDouble()]),
  );
  return Decoded(grid, conf, raw);
}

/// Whether the king of the given colour is attacked in [grid].
bool kingInCheck(List<int> grid, {required bool white}) {
  final king = white ? whiteKing : blackKing;
  final at = grid.indexOf(king);
  if (at < 0) return false;
  final r = at ~/ 8, c = at % 8;
  bool enemy(int cls) => white ? isBlack(cls) : isWhite(cls);
  int at2(int rr, int cc) =>
      (rr < 0 || rr > 7 || cc < 0 || cc > 7) ? -1 : grid[rr * 8 + cc];

  // pawns: a white pawn attacks towards rank 8 (row - 1), a black pawn towards rank 1 (row + 1)
  final pawnRow = white ? r - 1 : r + 1;
  for (final dc in const [-1, 1]) {
    if (at2(pawnRow, c + dc) == (white ? blackPawn : whitePawn)) return true;
  }
  for (final d in const [
    [1, 2],
    [2, 1],
    [-1, 2],
    [-2, 1],
    [1, -2],
    [2, -1],
    [-1, -2],
    [-2, -1],
  ]) {
    final k = at2(r + d[0], c + d[1]);
    if (k > 0 && enemy(k) && classSymbols[k].toUpperCase() == 'N') return true;
  }
  for (final d in const [
    [1, 1],
    [1, -1],
    [-1, 1],
    [-1, -1],
  ]) {
    for (var i = 1; i < 8; i++) {
      final k = at2(r + d[0] * i, c + d[1] * i);
      if (k == -1) break;
      if (k == 0) continue;
      final s = classSymbols[k].toUpperCase();
      if (enemy(k) && (s == 'B' || s == 'Q' || (i == 1 && s == 'K'))) {
        return true;
      }
      break;
    }
  }
  for (final d in const [
    [1, 0],
    [-1, 0],
    [0, 1],
    [0, -1],
  ]) {
    for (var i = 1; i < 8; i++) {
      final k = at2(r + d[0] * i, c + d[1] * i);
      if (k == -1) break;
      if (k == 0) continue;
      final s = classSymbols[k].toUpperCase();
      if (enemy(k) && (s == 'R' || s == 'Q' || (i == 1 && s == 'K'))) {
        return true;
      }
      break;
    }
  }
  return false;
}

/// Castling rights that are *possible* given king/rook placement (the user confirms).
String guessCastling(String placement) {
  final g = placementToGrid(placement);
  const e1 = 60, h1 = 63, a1 = 56, e8 = 4, h8 = 7, a8 = 0;
  final rights = StringBuffer();
  if (g[e1] == whiteKing) {
    if (g[h1] == 4) rights.write('K');
    if (g[a1] == 4) rights.write('Q');
  }
  if (g[e8] == blackKing) {
    if (g[h8] == 10) rights.write('k');
    if (g[a8] == 10) rights.write('q');
  }
  return rights.isEmpty ? '-' : rights.toString();
}

/// 'w' / 'b' if the position forces the side to move (the other side cannot be in check), else null.
String? suggestTurn(String placement) {
  final g = placementToGrid(placement);
  final w = kingInCheck(g, white: true), b = kingInCheck(g, white: false);
  if (w && !b) return 'w';
  if (b && !w) return 'b';
  return null;
}

String toFen(
  String placement, {
  String turn = 'w',
  String? castling,
  String ep = '-',
}) {
  final p = placement.split(' ').first;
  final c = castling == null
      ? guessCastling(p)
      : (castling.isEmpty ? '-' : castling);
  return '$p $turn $c $ep 0 1';
}

/// Human-readable problems with a full FEN (empty list = legal-looking position).
List<String> validate(String fen) {
  final parts = fen.split(' ');
  final g = placementToGrid(parts.first);
  final turn = parts.length > 1 ? parts[1] : 'w';
  final problems = <String>{};
  int count(bool Function(int) test) => g.where(test).length;
  final whiteKings = count((k) => k == whiteKing),
      blackKings = count((k) => k == blackKing);
  if (g.every((k) => k == 0)) problems.add('tablero vacío');
  if (whiteKings == 0) problems.add('falta el rey blanco');
  if (blackKings == 0) problems.add('falta el rey negro');
  if (whiteKings > 1 || blackKings > 1) {
    problems.add('hay más de un rey de un color');
  }
  if (count((k) => k == whitePawn) > 8) problems.add('más de 8 peones blancos');
  if (count((k) => k == blackPawn) > 8) problems.add('más de 8 peones negros');
  if (count(isWhite) > 16) problems.add('más de 16 piezas blancas');
  if (count(isBlack) > 16) problems.add('más de 16 piezas negras');
  for (var sq = 0; sq < 64; sq++) {
    if ((sq < 8 || sq >= 56) && (g[sq] == whitePawn || g[sq] == blackPawn)) {
      problems.add('hay un peón en la fila 1 u 8');
    }
  }
  // the side NOT to move cannot be in check
  if (kingInCheck(g, white: turn != 'w')) {
    problems.add('el bando que no mueve está en jaque');
  }
  return problems.toList()..sort();
}

/// Position-only PGN: tag pairs with SetUp/FEN and the unknown-result marker '*'.
String toPgn(String fen, {String event = 'Diagram'}) {
  final b = StringBuffer()
    ..writeln('[Event "$event"]')
    ..writeln('[Site "?"]')
    ..writeln('[Date "????.??.??"]')
    ..writeln('[Round "?"]')
    ..writeln('[White "?"]')
    ..writeln('[Black "?"]')
    ..writeln('[Result "*"]');
  if (fen != startFen) {
    b
      ..writeln('[FEN "$fen"]')
      ..writeln('[SetUp "1"]');
  }
  b
    ..writeln()
    ..writeln('*');
  return b.toString();
}
