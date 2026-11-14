// Full-screen manual crop: the user frames one board and gets its rectangle back in IMAGE PIXELS.
// A rough frame with some margin is enough: the pipeline snaps to the 8x8 grid inside it.
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import 'locate.dart';

/// Opens the crop page; null when the user cancels.
Future<Box?> showCropPage(
  BuildContext context,
  Uint8List imageBytes, {
  Box? initial,
}) => Navigator.of(context).push<Box>(
  MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => CropPage(imageBytes: imageBytes, initial: initial),
  ),
);

/// Touch target of every corner handle (logical px, at least 44).
const double cropHandleSize = 48;

class CropPage extends StatefulWidget {
  const CropPage({super.key, required this.imageBytes, this.initial});

  final Uint8List imageBytes;

  /// Starting rectangle in image pixels; default = a centred square of 70 % of the shorter side.
  final Box? initial;

  @override
  State<CropPage> createState() => _CropPageState();
}

class _CropPageState extends State<CropPage> {
  Size? _size; // image size in pixels
  Rect _rect = Rect.zero; // selection in image pixels
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // Screenshots carry no EXIF rotation, so the decoded size is the displayed size.
      final codec = await ui.instantiateImageCodec(widget.imageBytes);
      final frame = await codec.getNextFrame();
      final size = Size(
        frame.image.width.toDouble(),
        frame.image.height.toDouble(),
      );
      frame.image.dispose();
      codec.dispose();
      if (!mounted) return;
      setState(() {
        _size = size;
        _rect = _startRect(size);
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  double _minSide(Size s) => math.min(24, math.min(s.width, s.height));

  Rect _startRect(Size s) {
    final i = widget.initial;
    if (i != null) {
      final r = Rect.fromLTRB(
        i.x0,
        i.y0,
        i.x1,
        i.y1,
      ).intersect(Rect.fromLTWH(0, 0, s.width, s.height));
      final m = _minSide(s);
      if (r.width >= m && r.height >= m) return r;
    }
    final side = 0.7 * math.min(s.width, s.height);
    return Rect.fromCenter(
      center: Offset(s.width / 2, s.height / 2),
      width: side,
      height: side,
    );
  }

  /// Moves one corner by [d] image pixels, keeping the rectangle inside the image and above the minimum size.
  void _resize(bool left, bool top, Offset d) {
    final s = _size!;
    final m = _minSide(s);
    var l = _rect.left, t = _rect.top, r = _rect.right, b = _rect.bottom;
    if (left) {
      l = (l + d.dx).clamp(0.0, r - m);
    } else {
      r = (r + d.dx).clamp(l + m, s.width);
    }
    if (top) {
      t = (t + d.dy).clamp(0.0, b - m);
    } else {
      b = (b + d.dy).clamp(t + m, s.height);
    }
    setState(() => _rect = Rect.fromLTRB(l, t, r, b));
  }

  void _move(Offset d) {
    final s = _size!;
    final dx = d.dx.clamp(-_rect.left, s.width - _rect.right);
    final dy = d.dy.clamp(-_rect.top, s.height - _rect.bottom);
    setState(() => _rect = _rect.shift(Offset(dx, dy)));
  }

  void _accept() => Navigator.pop(
    context,
    Box(_rect.left, _rect.top, _rect.right, _rect.bottom),
  );

  Widget _canvas(BoxConstraints c) {
    final size = _size!;
    final scale = math.min(c.maxWidth / size.width, c.maxHeight / size.height);
    final shown = Size(size.width * scale, size.height * scale);
    final origin = Offset(
      (c.maxWidth - shown.width) / 2,
      (c.maxHeight - shown.height) / 2,
    );
    final sel = Rect.fromLTRB(
      origin.dx + _rect.left * scale,
      origin.dy + _rect.top * scale,
      origin.dx + _rect.right * scale,
      origin.dy + _rect.bottom * scale,
    );
    final colors = Theme.of(context).colorScheme;

    Widget handle(String id, bool left, bool top) {
      final p = Offset(left ? sel.left : sel.right, top ? sel.top : sel.bottom);
      return Positioned(
        left: p.dx - cropHandleSize / 2,
        top: p.dy - cropHandleSize / 2,
        width: cropHandleSize,
        height: cropHandleSize,
        child: GestureDetector(
          key: ValueKey('handle-$id'),
          behavior: HitTestBehavior.opaque,
          onPanUpdate: (u) => _resize(left, top, u.delta / scale),
          child: Center(
            child: Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: colors.primary,
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFFFFFFFF), width: 2),
              ),
            ),
          ),
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fromRect(
          rect: origin & shown,
          child: Image.memory(
            widget.imageBytes,
            fit: BoxFit.contain,
            gaplessPlayback: true,
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _DimPainter(sel, colors.primary, origin & shown),
            ),
          ),
        ),
        Positioned.fromRect(
          rect: sel,
          child: GestureDetector(
            key: const ValueKey('crop-move'),
            behavior: HitTestBehavior.opaque,
            onPanUpdate: (u) => _move(u.delta / scale),
          ),
        ),
        handle('tl', true, true),
        handle('tr', false, true),
        handle('bl', true, false),
        handle('br', false, false),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recortar')),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Text('Encierra un tablero (mejor con un poco de margen)'),
            ),
            Expanded(
              child: _error != null
                  ? Center(child: Text('No se pudo leer la imagen: $_error'))
                  : _size == null
                  ? const Center(child: CircularProgressIndicator())
                  : LayoutBuilder(builder: (_, c) => _canvas(c)),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: _size == null ? null : _accept,
                    child: const Text('Leer tablero'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Dims everything of the image outside the selection and outlines the selection.
class _DimPainter extends CustomPainter {
  _DimPainter(this.sel, this.color, this.image);
  final Rect sel, image;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(image)
      ..addRect(sel);
    canvas.drawPath(path, Paint()..color = const Color(0x99000000));
    canvas.drawRect(
      sel,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(_DimPainter old) => old.sel != sel || old.image != image;
}
