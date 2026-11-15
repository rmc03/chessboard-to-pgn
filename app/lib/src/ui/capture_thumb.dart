// The small picture of a capture at the start of its group header, and the full-screen viewer it opens: pinch to
// zoom and drag, with a close button. The thumbnail is decoded small (`cacheWidth`), once: the image cache keeps
// it for every rebuild of the header.
import 'package:material_ui/material_ui.dart';

import '../session.dart';
import 'icons.dart';
import 'tokens.dart';

/// Side of the picture; the tap target around it is [minTarget].
const double captureThumbSize = 40;

class CaptureThumb extends StatelessWidget {
  const CaptureThumb({super.key, required this.source});

  final SourceImage source;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = source.title.toLowerCase();
    return Semantics(
      button: true,
      label: 'Ver la $title a pantalla completa',
      excludeSemantics: true,
      child: InkWell(
        key: const ValueKey('capture-thumb'),
        onTap: () => CaptureViewerPage.open(context, source),
        borderRadius: BorderRadius.circular(Corner.control),
        child: SizedBox.square(
          dimension: minTarget,
          child: Center(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Corner.control / 2),
              child: SizedBox.square(
                dimension: captureThumbSize,
                child: Image.memory(
                  source.bytes,
                  cacheWidth: 120,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  gaplessPlayback: true,
                  excludeFromSemantics: true,
                  errorBuilder: (context, error, stack) =>
                      ColoredBox(color: scheme.surfaceContainerHighest),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The whole capture, zoomable.
class CaptureViewerPage extends StatelessWidget {
  const CaptureViewerPage({super.key, required this.source});

  final SourceImage source;

  static Future<void> open(BuildContext context, SourceImage source) =>
      Navigator.of(context).push<void>(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => CaptureViewerPage(source: source),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.inverseSurface,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: IconButton(
          key: const ValueKey('viewer-close'),
          tooltip: 'Cerrar',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const AppIcon(AppIcons.close),
        ),
        title: Text(source.title),
      ),
      body: SafeArea(
        top: false,
        child: InteractiveViewer(
          maxScale: 8,
          child: Center(
            child: Image.memory(
              source.bytes,
              fit: BoxFit.contain,
              semanticLabel: source.title,
              errorBuilder: (context, error, stack) => AppIcon(
                AppIcons.error,
                size: 48,
                color: scheme.onInverseSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
