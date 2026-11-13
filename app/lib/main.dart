import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import 'src/classifier.dart';
import 'src/diagram.dart';
import 'src/diagram_card.dart';
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

Future<Uint8List?> _pickFromGallery() async {
  final file = await ImagePicker().pickImage(source: ImageSource.gallery);
  return file?.readAsBytes();
}

Future<ModelAssets> _loadModel() async => ModelAssets(
  await rootBundle.loadString('assets/model/manifest.json'),
  (await rootBundle.load('assets/model/weights.bin')).buffer.asUint8List(),
);

class HomePage extends StatefulWidget {
  const HomePage({super.key, this.pickImage, this.recognize});

  final ImageSourceFn? pickImage;
  final RecognizeFn? recognize;

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
        _status =
            '${boards.length} diagrama(s) en ${(sw.elapsedMilliseconds / 1000).toStringAsFixed(1)} s. '
            'Toca una casilla para corregirla; las que están en ámbar son dudosas.';
      });
    } catch (e) {
      if (mounted) setState(() => _status = 'Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyAll() async {
    final pgn = [
      for (var i = 0; i < _diagrams.length; i++) _diagrams[i].pgn(i + 1),
    ].join('\n');
    await Clipboard.setData(ClipboardData(text: pgn));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PGN de ${_diagrams.length} diagrama(s) copiado'),
        ),
      );
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
                ),
              if (_diagrams.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 24),
                  child: FilledButton.icon(
                    onPressed: _copyAll,
                    icon: const Icon(Icons.copy_all),
                    label: Text(
                      'Copiar PGN de los ${_diagrams.length} diagramas',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
