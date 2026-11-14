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

void main() => runApp(const ChessPgnApp());

class ChessPgnApp extends StatelessWidget {
  const ChessPgnApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Chess → PGN',
    theme: ThemeData(
      colorSchemeSeed: const Color(0xFF8D6E63),
      useMaterial3: true,
    ),
    home: const HomePage(),
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
      appBar: AppBar(title: const Text('Chess → PGN')),
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
