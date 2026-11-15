import 'dart:async';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import 'src/classifier.dart';
import 'src/crop_page.dart';
import 'src/diagram.dart';
import 'src/diagram_card.dart';
import 'src/export.dart' as exporter;
import 'src/locate.dart';
import 'src/pipeline.dart';
import 'src/session.dart';
import 'src/settings.dart';
import 'src/ui/licenses.dart';
import 'src/ui/localizations.dart';
import 'src/ui/pieces.dart';
import 'src/ui/scope.dart';
import 'src/ui/settings_page.dart';
import 'src/ui/theme.dart';
import 'src/ui/tokens.dart';

/// Version shown in Ajustes. Keep equal to `version:` in pubspec.yaml (without the build number); a test
/// checks it.
const String kAppVersion = '0.2.1';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
  final settings = await AppSettings.load();
  final catalog = await PieceSetCatalog.load();
  settings.ensurePieceSet(
    catalog.ids,
    fallback: catalog.find(defaultPieceSetId) != null
        ? defaultPieceSetId
        : PieceSetCatalog.fallbackId,
  );
  // The first frame already has the pieces of the chosen set (no pop-in).
  await catalog.ensureLoaded(settings.pieceSetId);
  registerBundledLicenses();
  runApp(
    ChessPgnApp(
      settings: settings,
      session: Session(),
      catalog: catalog,
      appVersion: kAppVersion,
    ),
  );
}

/// The app: provides the settings, the session and the piece catalogue (see [AppScope]) and builds the
/// Material app with the theme of the chosen ink. Everything is optional so a test can start it bare.
class ChessPgnApp extends StatefulWidget {
  const ChessPgnApp({
    super.key,
    this.settings,
    this.session,
    this.catalog,
    this.appVersion = kAppVersion,
    this.home,
  });

  /// Defaults to in-memory settings.
  final AppSettings? settings;

  /// Defaults to a new session with the real reader.
  final Session? session;

  /// Defaults to the built-in typographic set only.
  final PieceSetCatalog? catalog;
  final String appVersion;

  /// The first screen; defaults to [HomePage]. The screenshot harness puts the screen it renders here.
  final Widget? home;

  @override
  State<ChessPgnApp> createState() => _ChessPgnAppState();
}

class _ChessPgnAppState extends State<ChessPgnApp>
    with WidgetsBindingObserver {
  late final AppSettings _settings = widget.settings ?? AppSettings();
  late final Session _session = widget.session ?? Session();
  late final PieceSetCatalog _catalog =
      widget.catalog ?? PieceSetCatalog.builtIn();

  late bool _reduceMotion = _systemReducesMotion();
  String? _themedInk;
  late ThemeData _light, _dark;

  bool _systemReducesMotion() =>
      WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
          .disableAnimations;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAccessibilityFeatures() {
    final now = _systemReducesMotion();
    if (now != _reduceMotion) setState(() => _reduceMotion = now);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.session == null) _session.dispose();
    if (widget.catalog == null) _catalog.dispose();
    super.dispose();
  }

  /// The two themes of the current ink; the same objects until the ink changes, so changing anything else
  /// (style, coordinates, pieces) does not restart the theme animation.
  void _themeFor(String inkId) {
    if (_themedInk == inkId) return;
    final ink = inkById(inkId);
    _light = buildTheme(ink, Brightness.light);
    _dark = buildTheme(ink, Brightness.dark);
    _themedInk = inkId;
  }

  @override
  Widget build(BuildContext context) => AppScope(
    settings: _settings,
    session: _session,
    catalog: _catalog,
    child: ListenableBuilder(
      listenable: _settings,
      builder: (context, _) {
        _themeFor(_settings.inkId);
        return MaterialApp(
          title: 'Chess to PGN',
          debugShowCheckedModeBanner: false,
          theme: _light,
          darkTheme: _dark,
          themeMode: _settings.themeMode,
          // Re-inking is a ~200 ms theme lerp; the system's "remove animations" turns it into a cut.
          themeAnimationDuration: _reduceMotion
              ? Duration.zero
              : Motion.medium,
          themeAnimationCurve: Motion.standard,
          locale: SpanishMaterialLocalizations.locale,
          supportedLocales: const [SpanishMaterialLocalizations.locale],
          localizationsDelegates: SpanishMaterialLocalizations.delegates,
          builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
            value: context.app.systemOverlay,
            child: child!,
          ),
          home: widget.home ?? const HomePage(),
        );
      },
    ),
  );
}

/// Where images come from and how they are read. Replaceable so the screen can be tested without plugins.
typedef ImageSourceFn = Future<Uint8List?> Function();
typedef RecognizeFn = Future<List<RecognizedBoard>> Function(
  Uint8List bytes,
  void Function(int boards) onFound,
);

/// Lets the user frame a board by hand; null when cancelled. [initial] is in image pixels.
typedef CropRegionFn = Future<Box?> Function(
  BuildContext context,
  Uint8List bytes,
  Box? initial,
);
typedef RecognizeRegionFn = Future<RecognizedBoard> Function(
  Uint8List bytes,
  Box region,
);

Future<Uint8List?> _pickFromGallery() async {
  final file = await ImagePicker().pickImage(source: ImageSource.gallery);
  return file?.readAsBytes();
}

Future<ModelAssets> _loadModel() async => ModelAssets(
  await rootBundle.loadString('assets/model/manifest.json'),
  (await rootBundle.load('assets/model/weights.bin')).buffer.asUint8List(),
);

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.pickImage,
    this.recognize,
    this.cropRegion,
    this.recognizeRegion,
    this.saveFile,
    this.shareText,
    this.shareFile,
  });

  final ImageSourceFn? pickImage;
  final RecognizeFn? recognize;
  final CropRegionFn? cropRegion;
  final RecognizeRegionFn? recognizeRegion;
  final exporter.SaveFileFn? saveFile;
  final exporter.ShareTextFn? shareText;
  final exporter.ShareFileFn? shareFile;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<Diagram> _diagrams = [];
  Uint8List? _image;
  String _status =
      'Elige una imagen con uno o varios diagramas de ajedrez (captura de pantalla, foto de página…).';
  bool _busy = false;
  ModelAssets? _model;

  Future<List<RecognizedBoard>> _recognize(
    Uint8List bytes,
    void Function(int) onFound,
  ) {
    final custom = widget.recognize;
    if (custom != null) return custom(bytes, onFound);
    return () async {
      _model ??= await _loadModel();
      return recognizeImage(bytes, _model!, onFound: onFound);
    }();
  }

  Future<void> _pickAndRecognize() async {
    final bytes = await (widget.pickImage ?? _pickFromGallery)();
    if (bytes == null) return;
    setState(() {
      _busy = true;
      _image = bytes;
      _diagrams.clear();
      _status = 'Buscando diagramas…';
    });
    try {
      final sw = Stopwatch()..start();
      final boards = await _recognize(bytes, (n) {
        if (mounted) {
          setState(
            () => _status = '$n diagrama(s) encontrado(s), leyendo las piezas…',
          );
        }
      });
      if (!mounted) return;
      setState(() {
        _diagrams.addAll(boards.map(Diagram.fromRecognized));
        final secs = (sw.elapsedMilliseconds / 1000).toStringAsFixed(1);
        _status = boards.isEmpty
            ? 'No se encontró ningún diagrama. Prueba con «Recortar a mano».'
            : '${boards.length} diagrama(s) en $secs s. '
                  'Toca una casilla para corregirla; las que están en ámbar son dudosas.'
                  '${boards.every((b) => b.fallback) ? ' Si no es el tablero correcto, usa «Recortar a mano».' : ''}';
      });
    } catch (e) {
      if (mounted) setState(() => _status = 'Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Crops by hand (starting from [initial]) and reads the region; null if cancelled or failed.
  Future<Diagram?> _readRegion(Box? initial) async {
    final bytes = _image;
    if (bytes == null) return null;
    final box = await (widget.cropRegion ?? _cropRegion)(
      context,
      bytes,
      initial,
    );
    if (box == null || !mounted) return null;
    setState(() {
      _busy = true;
      _status = 'Leyendo el recorte…';
    });
    try {
      final RecognizedBoard board;
      if (widget.recognizeRegion != null) {
        board = await widget.recognizeRegion!(bytes, box);
      } else {
        _model ??= await _loadModel();
        board = await recognizeRegion(bytes, box, _model!);
      }
      if (mounted) {
        setState(
          () => _status = 'Recorte leído. Toca una casilla para corregirla; las que están en ámbar son dudosas.',
        );
      }
      return Diagram.fromRecognized(board);
    } catch (e) {
      if (mounted) setState(() => _status = 'Error: $e');
      return null;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<Box?> _cropRegion(
    BuildContext context,
    Uint8List bytes,
    Box? initial,
  ) => showCropPage(context, bytes, initial: initial);

  Future<void> _addByHand() async {
    final d = await _readRegion(null);
    if (d != null && mounted) setState(() => _diagrams.add(d));
  }

  Future<void> _adjust(Diagram old) async {
    final b = old.box;
    final initial = b == null
        ? null
        : Box(
            b.x0 - 0.05 * b.width,
            b.y0 - 0.05 * b.height,
            b.x1 + 0.05 * b.width,
            b.y1 + 0.05 * b.height,
          );
    final d = await _readRegion(initial);
    if (d == null || !mounted) return;
    final i = _diagrams.indexOf(old);
    setState(() {
      if (i >= 0) {
        _diagrams[i] = d;
      } else {
        _diagrams.add(d);
      }
    });
  }

  String _pgn(List<Diagram> diagrams, {int first = 1}) =>
      [for (var i = 0; i < diagrams.length; i++) diagrams[i].pgn(first + i)]
          .join('\n');

  String get _allPgn => _pgn(_diagrams);

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copyAll() async {
    await Clipboard.setData(ClipboardData(text: _allPgn));
    _toast('PGN de ${_diagrams.length} diagrama(s) copiado');
  }

  Future<void> _save() async {
    final name = exporter.pgnFileName(DateTime.now());
    try {
      final saved = await (widget.saveFile ?? exporter.saveFileWithDialog)(
        name,
        exporter.pgnBytes(_allPgn),
      );
      if (saved) _toast('Guardado: $name');
    } catch (e) {
      _toast('No se pudo guardar: $e');
    }
  }

  /// Bottom sheet: share [pgn] as plain text or as a .pgn file.
  Future<void> _share(String pgn) async {
    final how = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.text_snippet_outlined),
              title: const Text('Como texto'),
              subtitle: const Text('Para chats y notas'),
              onTap: () => Navigator.pop(context, 'text'),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: const Text('Como archivo .pgn'),
              subtitle: const Text('Para abrirlo en una app de ajedrez'),
              onTap: () => Navigator.pop(context, 'file'),
            ),
          ],
        ),
      ),
    );
    if (how == null) return;
    try {
      if (how == 'text') {
        await (widget.shareText ?? exporter.shareText)(pgn);
      } else {
        await (widget.shareFile ?? exporter.shareFile)(
          exporter.pgnFileName(DateTime.now()),
          exporter.pgnBytes(pgn),
        );
      }
    } catch (e) {
      _toast('No se pudo compartir: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Chess to PGN'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Ajustes',
            onPressed: () =>
                SettingsPage.open(context, appVersion: kAppVersion),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FilledButton.icon(
                onPressed: _busy ? null : _pickAndRecognize,
                icon: const Icon(Icons.image),
                label: const Text('Elegir imagen'),
              ),
              if (_image != null) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _addByHand,
                  icon: const Icon(Icons.crop),
                  label: const Text('Recortar a mano'),
                ),
              ],
              const SizedBox(height: 12),
              if (_busy) const LinearProgressIndicator(),
              Text(_status),
              if (_image != null) ...[
                const SizedBox(height: 12),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: Image.memory(_image!),
                ),
              ],
              for (var i = 0; i < _diagrams.length; i++)
                DiagramCard(
                  key: ObjectKey(_diagrams[i]),
                  number: i + 1,
                  diagram: _diagrams[i],
                  onAdjust: _busy ? null : () => _adjust(_diagrams[i]),
                  onSharePgn: exporter.canShare
                      ? () => _share(_pgn([_diagrams[i]], first: i + 1))
                      : null,
                ),
              if (_diagrams.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 24),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.icon(
                        onPressed: _copyAll,
                        icon: const Icon(Icons.copy_all),
                        label: Text(
                          'Copiar PGN de los ${_diagrams.length} diagramas',
                        ),
                      ),
                      if (exporter.canShare)
                        OutlinedButton.icon(
                          onPressed: () => _share(_allPgn),
                          icon: const Icon(Icons.share),
                          label: const Text('Compartir'),
                        ),
                      OutlinedButton.icon(
                        onPressed: _save,
                        icon: const Icon(Icons.save_alt),
                        label: const Text('Guardar .pgn'),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
