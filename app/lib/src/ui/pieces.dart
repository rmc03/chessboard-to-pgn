// Pieces: the catalogue of piece sets (SVG sets from assets/pieces/sets.json plus the built-in typographic
// set), how a piece is painted, and the [PieceView] widget.
//
// The SVG pieces are parsed once per set ([PieceSetCatalog.ensureLoaded] loads all 12 pieces of a set) and kept
// as vector pictures, so a board paints them synchronously and crisply at any size. While a set is still
// loading nothing is drawn for it; if it fails to load, the typographic set (the bundled ChessFigures font)
// is drawn instead, so a piece is never missing and never depends on system fonts.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_ui/material_ui.dart';

import '../chess.dart';
import 'scope.dart';
import 'tokens.dart';

/// Bundled font with only the 12 chess figures (assets/fonts, see app/tool/make_figures_font.py).
///
/// The figures must NOT come from the system fonts: on Android the pawn U+265F (the only chess figure that is
/// also an emoji) is replaced by a colour emoji that ignores the text colour, so white and black pawns looked
/// the same while every other piece was fine.
const figuresFont = 'ChessFigures';

/// Filled figure of a piece class (U+265A king .. U+265F pawn), whatever its colour.
String solidFigure(int cls) =>
    String.fromCharCode(0x2660 - (cls <= 6 ? cls : cls - 6));

/// Line-drawing figure of the same piece (U+2654 king .. U+2659 pawn).
String outlineFigure(int cls) =>
    String.fromCharCode(0x265A - (cls <= 6 ? cls : cls - 6));

/// Fraction of the box the typographic figure occupies.
const double _figureScale = 0.92;

/// Draws the typographic figure of [cls] centred in [rect].
/// White: white body, black contour and inner lines. Black: solid black.
void paintFigure(Canvas canvas, Rect rect, int cls) {
  final size = rect.shortestSide * _figureScale;
  TextPainter glyph(String text, {Color? color, Paint? foreground}) =>
      TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(
            fontFamily: figuresFont,
            fontSize: size,
            height: 1,
            color: color,
            foreground: foreground,
          ),
        ),
        textDirection: TextDirection.ltr,
        textScaler: TextScaler.noScaling,
      )..layout();
  void draw(TextPainter tp) =>
      tp.paint(canvas, rect.center - Offset(tp.width / 2, tp.height / 2));

  if (isWhite(cls)) {
    draw(
      glyph(
        solidFigure(cls),
        foreground: Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = size * 0.05
          ..strokeJoin = StrokeJoin.round
          ..color = BoardMarks.pieceBlack,
      ),
    );
    draw(glyph(solidFigure(cls), color: BoardMarks.pieceWhite));
    draw(glyph(outlineFigure(cls), color: BoardMarks.pieceBlack));
  } else {
    draw(glyph(solidFigure(cls), color: BoardMarks.pieceBlack));
  }
}

/// One piece in a [size] x [size] box (the figure itself is about 0.73 of it, centred), made of text widgets.
/// This is the typographic set as a widget; boards and [PieceView] paint the same drawing with [paintFigure].
class PieceFigure extends StatelessWidget {
  const PieceFigure(this.cls, {super.key, required this.size});

  final int cls;
  final double size;

  @override
  Widget build(BuildContext context) {
    Widget figure(String text, {Color? color, Paint? paint}) => Text(
      text,
      textScaler: TextScaler.noScaling,
      style: TextStyle(
        fontFamily: figuresFont,
        fontSize: size,
        height: 1,
        color: color,
        foreground: paint,
      ),
    );
    final contour = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size * 0.05
      ..strokeJoin = StrokeJoin.round
      ..color = BoardMarks.pieceBlack;
    return Semantics(
      label: pieceNames[cls],
      excludeSemantics: true,
      child: isWhite(cls)
          ? Stack(
              alignment: Alignment.center,
              children: [
                figure(solidFigure(cls), paint: contour),
                figure(solidFigure(cls), color: BoardMarks.pieceWhite),
                figure(outlineFigure(cls), color: BoardMarks.pieceBlack),
              ],
            )
          : figure(solidFigure(cls), color: BoardMarks.pieceBlack),
    );
  }
}

// ------------------------------------------------------------------------------------------- catalogue

/// A set of 12 pieces.
@immutable
class PieceSet {
  const PieceSet({
    required this.id,
    required this.name,
    required this.author,
    required this.license,
    this.licenseUrl = '',
    this.source = '',
    this.builtIn = false,
  });

  factory PieceSet.fromJson(Map<String, dynamic> json) => PieceSet(
    id: json['id'] as String,
    name: json['name'] as String,
    author: json['author'] as String,
    license: json['license'] as String,
    licenseUrl: (json['licenseUrl'] as String?) ?? '',
    source: (json['source'] as String?) ?? '',
  );

  /// Folder under `assets/pieces/` (and the value stored in the settings).
  final String id;

  /// Name shown in Ajustes.
  final String name;
  final String author;
  final String license;
  final String licenseUrl;
  final String source;

  /// Drawn with the bundled font instead of SVG files.
  final bool builtIn;
}

/// Whether the SVG pieces of a set can be drawn.
enum PieceLoad { loading, ready, failed }

/// The piece sets of the app, loaded once at startup with [load] and shared through the `AppScope`.
class PieceSetCatalog extends ChangeNotifier {
  PieceSetCatalog(List<PieceSet> svgSets, {AssetBundle? bundle})
    : sets = List.unmodifiable([...svgSets, typographic]),
      _bundle = bundle ?? rootBundle;

  /// Only the built-in typographic set: what a board uses when nothing else was loaded.
  PieceSetCatalog.builtIn() : this(const []);

  /// Id of the set that needs no asset and is the fallback for every other.
  static const String fallbackId = 'tipografico';

  /// The built-in set (the ChessFigures font).
  static const PieceSet typographic = PieceSet(
    id: fallbackId,
    name: 'Tipográfico',
    author: 'DejaVu Sans',
    license: 'Bitstream Vera',
    builtIn: true,
  );

  static const List<String> _kinds = ['P', 'N', 'B', 'R', 'Q', 'K'];

  /// Reads `assets/pieces/sets.json`. If it is missing or broken only the typographic set remains.
  static Future<PieceSetCatalog> load([AssetBundle? bundle]) async {
    final b = bundle ?? rootBundle;
    try {
      final list = jsonDecode(await b.loadString('assets/pieces/sets.json'));
      final svgSets = [
        for (final e in list as List) PieceSet.fromJson(e as Map<String, dynamic>),
      ];
      return PieceSetCatalog(svgSets, bundle: b);
    } catch (e) {
      debugPrint('Piece sets unavailable, using the typographic set: $e');
      return PieceSetCatalog(const [], bundle: b);
    }
  }

  /// SVG sets in file order, then the typographic set.
  final List<PieceSet> sets;
  final AssetBundle _bundle;

  final Map<String, List<PictureInfo>> _pictures = {};
  final Set<String> _failed = {};
  final Map<String, Future<void>> _loading = {};
  bool _disposed = false;

  List<String> get ids => [for (final s in sets) s.id];

  PieceSet? find(String id) {
    for (final s in sets) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// The set with this id, or the typographic one when it is unknown.
  PieceSet resolve(String id) => find(id) ?? typographic;

  PieceLoad stateOf(String id) {
    final set = resolve(id);
    if (set.builtIn || _pictures.containsKey(set.id)) return PieceLoad.ready;
    return _failed.contains(set.id) ? PieceLoad.failed : PieceLoad.loading;
  }

  /// The vector picture of [cls] (1..12) in set [id], or null while it is not loaded (or if it failed, or for
  /// the built-in set).
  PictureInfo? picture(String id, int cls) => _pictures[id]?[cls - 1];

  /// Parses the 12 SVG files of set [id] once; completes when they are ready (or failed: see [stateOf]).
  /// Listeners are notified when the state of a set changes. Safe to call many times.
  Future<void> ensureLoaded(String id) {
    final set = find(id);
    if (set == null ||
        set.builtIn ||
        _pictures.containsKey(set.id) ||
        _failed.contains(set.id)) {
      return Future.value();
    }
    return _loading[set.id] ??= _load(set).whenComplete(() {
      _loading.remove(set.id);
    });
  }

  /// [ensureLoaded] for every set (the Ajustes previews).
  Future<void> ensureAllLoaded() =>
      Future.wait([for (final s in sets) ensureLoaded(s.id)]);

  Future<void> _load(PieceSet set) async {
    try {
      final pictures = await Future.wait([
        for (var cls = 1; cls <= 12; cls++)
          vg.loadPicture(
            SvgAssetLoader(_assetPath(set.id, cls), assetBundle: _bundle),
            null,
          ),
      ]);
      if (_disposed) {
        for (final p in pictures) {
          p.picture.dispose();
        }
        return;
      }
      _pictures[set.id] = pictures;
    } catch (e) {
      debugPrint('Piece set ${set.id} could not be loaded: $e');
      _failed.add(set.id);
    }
    if (!_disposed) notifyListeners();
  }

  static String _assetPath(String id, int cls) =>
      'assets/pieces/$id/${isWhite(cls) ? 'w' : 'b'}${_kinds[(cls - 1) % 6]}.svg';

  @override
  void dispose() {
    _disposed = true;
    for (final list in _pictures.values) {
      for (final p in list) {
        p.picture.dispose();
      }
    }
    _pictures.clear();
    super.dispose();
  }
}

/// Paints piece [cls] of set [setId] filling [rect]. Draws nothing while the set is loading and the
/// typographic figure when the set is the built-in one or failed to load.
void paintPiece(
  Canvas canvas,
  Rect rect,
  int cls,
  PieceSetCatalog catalog,
  String setId,
) {
  if (cls < 1 || cls > 12) return;
  final set = catalog.resolve(setId);
  if (!set.builtIn) {
    final info = catalog.picture(set.id, cls);
    if (info != null) {
      final s = rect.shortestSide /
          (info.size.width > info.size.height ? info.size.width : info.size.height);
      canvas.save();
      canvas.translate(
        rect.left + (rect.width - info.size.width * s) / 2,
        rect.top + (rect.height - info.size.height * s) / 2,
      );
      canvas.scale(s);
      canvas.drawPicture(info.picture);
      canvas.restore();
      return;
    }
    if (catalog.stateOf(set.id) != PieceLoad.failed) return;
  }
  paintFigure(canvas, rect, cls);
}

// ----------------------------------------------------------------------------------------------- widget

/// One piece in a [size] x [size] box, from the piece set of the settings (or [setId]).
///
/// Starts loading its set if needed and repaints when it is ready. Its semantics label is the piece name
/// ("caballo blanco"); pass [semanticLabel] false inside something that already describes it.
class PieceView extends StatefulWidget {
  const PieceView(
    this.cls, {
    super.key,
    required this.size,
    this.setId,
    this.catalog,
    this.semanticLabel = true,
  });

  /// Class id 1..12 (see chess.dart).
  final int cls;
  final double size;

  /// Piece set; defaults to the one in the settings.
  final String? setId;

  /// Defaults to the catalogue in the `AppScope`.
  final PieceSetCatalog? catalog;
  final bool semanticLabel;

  @override
  State<PieceView> createState() => _PieceViewState();
}

class _PieceViewState extends State<PieceView> {
  PieceSetCatalog _catalog = _builtIn;
  String _setId = PieceSetCatalog.fallbackId;

  static final PieceSetCatalog _builtIn = PieceSetCatalog.builtIn();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refresh();
  }

  @override
  void didUpdateWidget(PieceView old) {
    super.didUpdateWidget(old);
    _refresh();
  }

  void _refresh() {
    final scope = AppScope.maybeOf(context);
    _catalog = widget.catalog ?? scope?.catalog ?? _builtIn;
    _setId =
        widget.setId ?? scope?.settings.pieceSetId ?? PieceSetCatalog.fallbackId;
    unawaited(_catalog.ensureLoaded(_setId));
  }

  @override
  Widget build(BuildContext context) {
    final paint = SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(painter: _PiecePainter(widget.cls, _catalog, _setId)),
    );
    return widget.semanticLabel
        ? Semantics(
            label: pieceNames[widget.cls],
            image: true,
            excludeSemantics: true,
            child: paint,
          )
        : ExcludeSemantics(child: paint);
  }
}

class _PiecePainter extends CustomPainter {
  // Repaints when the catalogue reports that a set finished loading.
  _PiecePainter(this.cls, this.catalog, this.setId) : super(repaint: catalog);

  final int cls;
  final PieceSetCatalog catalog;
  final String setId;

  @override
  void paint(Canvas canvas, Size size) =>
      paintPiece(canvas, Offset.zero & size, cls, catalog, setId);

  @override
  bool shouldRepaint(_PiecePainter old) =>
      old.cls != cls || old.setId != setId || !identical(old.catalog, catalog);
}
