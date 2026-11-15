// Full-screen manual crop ("Recortar a mano"): the user frames one board on the screenshot and gets its
// rectangle back in IMAGE PIXELS. A rough frame is enough: the pipeline snaps to the 8x8 grid inside it.
//
// Pieces: ui/crop_geometry.dart (pure maths), ui/crop_controller.dart (state), ui/crop_canvas.dart (the single
// gesture layer, painter and loupe). This file is the page around them: app bar, bottom bar, zoom buttons,
// keyboard focus, semantics.
import 'dart:ui' as ui;

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'locate.dart';
import 'ui/crop_canvas.dart';
import 'ui/crop_controller.dart';
import 'ui/tokens.dart';

/// Opens the crop page; the chosen rectangle in image pixels, or null when the user cancels.
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

class CropPage extends StatefulWidget {
  const CropPage({super.key, required this.imageBytes, this.initial});

  final Uint8List imageBytes;

  /// Starting rectangle in image pixels (the view starts zoomed on it); default = a centred square of 70 % of
  /// the shorter side with the whole image visible.
  final Box? initial;

  @override
  State<CropPage> createState() => _CropPageState();
}

class _CropPageState extends State<CropPage>
    with SingleTickerProviderStateMixin {
  CropController? _c;
  Object? _error;
  final FocusNode _focus = FocusNode(debugLabel: 'crop canvas');

  @override
  void initState() {
    super.initState();
    _focus.addListener(_refocus);
    FocusManager.instance.addHighlightModeListener(_highlight);
    _load();
  }

  void _refocus() => setState(() {});
  void _highlight(FocusHighlightMode _) {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      // Decoded once. Screenshots carry no EXIF rotation, so the decoded size is the displayed size.
      final codec = await ui.instantiateImageCodec(widget.imageBytes);
      final frame = await codec.getNextFrame();
      codec.dispose();
      if (!mounted) {
        frame.image.dispose();
        return;
      }
      final i = widget.initial;
      setState(() {
        _c = CropController(
          image: frame.image,
          vsync: this,
          initial: i == null ? null : Rect.fromLTRB(i.x0, i.y0, i.x1, i.y1),
        );
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  void dispose() {
    FocusManager.instance.removeHighlightModeListener(_highlight);
    _focus
      ..removeListener(_refocus)
      ..dispose();
    final c = _c;
    c?.dispose();
    c?.image.dispose();
    super.dispose();
  }

  void _accept() {
    final c = _c;
    if (c == null) return;
    final r = c.rect;
    Navigator.of(context).pop(Box(r.left, r.top, r.right, r.bottom));
  }

  void _close() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = _c;
    c?.animationDuration = Motion.of(context, Motion.medium);

    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Cerrar',
            onPressed: _close,
          ),
          title: const Text('Recortar tablero'),
        ),
        body: Column(
          children: [
            Expanded(
              child: _error != null
                  ? const _Message('No se pudo leer la imagen.')
                  : c == null
                  ? const Center(child: CircularProgressIndicator())
                  : _Stage(
                      controller: c,
                      focusNode: _focus,
                      onAccept: _accept,
                      palette: CropPalette(
                        canvas: Color.alphaBlend(
                          scheme.scrim.withValues(alpha: 0.82),
                          scheme.surfaceContainerHighest,
                        ),
                        scrim: scheme.scrim.withValues(alpha: 0.5),
                        accent: scheme.primary,
                        light: BoardMarks.paper,
                        dark: BoardMarks.pieceBlack,
                      ),
                      showFocusRing:
                          _focus.hasFocus &&
                          FocusManager.instance.highlightMode ==
                              FocusHighlightMode.traditional,
                    ),
            ),
            _BottomBar(onReset: c?.reset, onAccept: c == null ? null : _accept),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(Space.xl),
      child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
    ),
  );
}

/// The canvas with its semantics and, on wide windows, the zoom buttons.
class _Stage extends StatelessWidget {
  const _Stage({
    required this.controller,
    required this.focusNode,
    required this.onAccept,
    required this.palette,
    required this.showFocusRing,
  });

  final CropController controller;
  final FocusNode focusNode;
  final VoidCallback onAccept;
  final CropPalette palette;
  final bool showFocusRing;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= Breakpoint.medium;
    return Stack(
      children: [
        Positioned.fill(
          child: ListenableBuilder(
            listenable: controller,
            // The canvas repaints itself from the controller; only the semantics value is rebuilt per change.
            child: CropCanvas(
              key: const ValueKey('crop-canvas'),
              controller: controller,
              palette: palette,
              focusNode: focusNode,
              onAccept: onAccept,
              showFocusRing: showFocusRing,
            ),
            builder: (context, canvas) {
              final (w, h) = controller.percent;
              return Semantics(
                container: true,
                label:
                    'Recortar tablero. Arrastra las esquinas o los bordes para encerrar el tablero; '
                    'pellizca para ampliar.',
                value: 'Recorte: $w % del ancho, $h % del alto',
                customSemanticsActions: {
                  const CustomSemanticsAction(label: 'Acercar'):
                      controller.zoomIn,
                  const CustomSemanticsAction(label: 'Alejar'):
                      controller.zoomOut,
                },
                child: canvas,
              );
            },
          ),
        ),
        if (wide)
          Positioned(
            right: Space.lg,
            bottom: Space.lg,
            child: ListenableBuilder(
              listenable: controller,
              builder: (context, _) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton.filledTonal(
                    key: const ValueKey('zoom-in'),
                    icon: const Icon(Icons.add),
                    tooltip: 'Acercar',
                    onPressed: controller.canZoomIn ? controller.zoomIn : null,
                  ),
                  const SizedBox(height: Space.sm),
                  IconButton.filledTonal(
                    key: const ValueKey('zoom-out'),
                    icon: const Icon(Icons.remove),
                    tooltip: 'Alejar',
                    onPressed: controller.canZoomOut
                        ? controller.zoomOut
                        : null,
                  ),
                  const SizedBox(height: Space.sm),
                  IconButton.filledTonal(
                    key: const ValueKey('zoom-fit'),
                    icon: const Icon(Icons.fit_screen),
                    tooltip: 'Ver toda la imagen',
                    onPressed: controller.canZoomOut
                        ? controller.fitView
                        : null,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.onReset, required this.onAccept});

  final VoidCallback? onReset, onAccept;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final wide = MediaQuery.sizeOf(context).width >= Breakpoint.medium;
    final hint = Text(
      'Encierra el tablero; no hace falta que sea exacto.',
      style: theme.textTheme.bodyMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    );
    final reset = TextButton(
      key: const ValueKey('crop-reset'),
      onPressed: onReset,
      child: const Text('Restablecer'),
    );
    final accept = FilledButton(
      key: const ValueKey('crop-accept'),
      onPressed: onAccept,
      child: const Text('Leer este tablero'),
    );
    final gutter = Space.gutter(MediaQuery.sizeOf(context).width);

    return Material(
      color: scheme.surfaceContainer,
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: Space.sm),
        child: Padding(
          padding: EdgeInsets.fromLTRB(gutter, Space.md, gutter, Space.xs),
          child: wide
              ? Row(
                  children: [
                    Expanded(child: hint),
                    const SizedBox(width: Space.lg),
                    reset,
                    const SizedBox(width: Space.sm),
                    accept,
                  ],
                )
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    hint,
                    const SizedBox(height: Space.sm),
                    Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: Space.sm,
                      runSpacing: Space.sm,
                      children: [reset, accept],
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
