// What the home screen does besides drawing: pick an image, read a hand-drawn region, copy, save, share and
// open Lichess, with the Spanish feedback (snackbars) each of them owes the user. Every platform call is
// injectable so the screen can be tested without plugins.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:material_ui/material_ui.dart';

import '../crop_page.dart';
import '../diagram.dart';
import '../export.dart' as exporter;
import '../locate.dart';
import '../session.dart';
import 'icons.dart';
import 'tokens.dart';

/// Where images come from: the gallery. Null when the user cancels.
typedef ImageSourceFn = Future<Uint8List?> Function();

/// Lets the user frame a board by hand; null when cancelled. [initial] is in image pixels.
typedef CropRegionFn = Future<Box?> Function(
  BuildContext context,
  Uint8List bytes,
  Box? initial,
);

Future<Box?> defaultCropRegion(
  BuildContext context,
  Uint8List bytes,
  Box? initial,
) => showCropPage(context, bytes, initial: initial);

Future<Uint8List?> pickFromGallery() async {
  final file = await ImagePicker().pickImage(source: ImageSource.gallery);
  return file?.readAsBytes();
}

/// The hint about the press-and-hold peek at the original (in the first block, or once in a snackbar).
const String peekHint = 'Mantén pulsado el tablero para ver el original.';

class HomeActions extends ChangeNotifier {
  HomeActions({
    required this.session,
    ImageSourceFn? pickImage,
    CropRegionFn? cropRegion,
    exporter.SaveFileFn? saveFile,
    exporter.ShareTextFn? shareText,
    exporter.ShareFileFn? shareFile,
    this._openUri,
    bool? canShare,
    DateTime Function()? now,
  }) : _pickImage = pickImage ?? pickFromGallery,
       _cropRegion = cropRegion ?? defaultCropRegion,
       _saveFile = saveFile ?? exporter.saveFileWithDialog,
       _shareText = shareText ?? exporter.shareText,
       _shareFile = shareFile ?? exporter.shareFile,
       canShare = canShare ?? exporter.canShare,
       _now = now ?? DateTime.now;

  final Session session;
  final ImageSourceFn _pickImage;
  final CropRegionFn _cropRegion;
  final exporter.SaveFileFn _saveFile;
  final exporter.ShareTextFn _shareText;
  final exporter.ShareFileFn _shareFile;
  final exporter.OpenUriFn? _openUri;
  final DateTime Function() _now;

  /// Whether the system share sheet is offered (Android only).
  final bool canShare;

  /// Called with each capture the user adds, so the screen can scroll to its group.
  void Function(SourceImage source)? onCaptureAdded;

  /// Set by the screen: scrolls to [diagram] and, with `review`, opens its "Revisar dudosas".
  Future<void> Function(Diagram diagram, {bool review})? onRevealDiagram;

  /// Scrolls the list to [diagram] (and opens its review) wherever the screen is; a no-op without a screen.
  Future<void> goToDiagram(Diagram diagram, {bool review = false}) async =>
      onRevealDiagram?.call(diagram, review: review);

  /// Height of the square editor while it is open (0 otherwise). The list leaves that much room under its end,
  /// so the board being edited can be scrolled clear of the sheet even when the list is short.
  final ValueNotifier<double> sheetHeight = ValueNotifier(0);

  @override
  void dispose() {
    sheetHeight.dispose();
    super.dispose();
  }

  bool _peekHintDismissed = false;

  /// The hint "Mantén pulsado el tablero para ver el original." is shown once per session, until the user peeks
  /// at the original or opens it with the segmented control.
  bool get peekHintVisible => !_peekHintDismissed;

  void dismissPeekHint() {
    if (_peekHintDismissed) return;
    _peekHintDismissed = true;
    notifyListeners();
  }

  bool _picking = false;
  final Set<SourceImage> _readingRegion = {};

  /// A hand-drawn region of [source] is being read.
  bool isReadingRegion(SourceImage source) => _readingRegion.contains(source);

  // ------------------------------------------------------------------ feedback

  void toast(
    ScaffoldMessengerState messenger,
    String message, {
    String? action,
    VoidCallback? onAction,
    Duration duration = const Duration(seconds: 4),
  }) {
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          duration: duration,
          action: action == null
              ? null
              : SnackBarAction(label: action, onPressed: onAction ?? () {}),
        ),
      );
  }

  // -------------------------------------------------------------------- input

  /// Opens the picker; the chosen image becomes a new capture at the end of the session. Cancelling changes
  /// nothing.
  Future<void> pick(BuildContext context) async {
    if (_picking) return; // a double tap must not open a second picker
    final messenger = ScaffoldMessenger.of(context);
    final Uint8List? bytes;
    _picking = true;
    try {
      bytes = await _pickImage();
    } catch (_) {
      if (!context.mounted) return;
      toast(
        messenger,
        'No se pudo abrir la galería.',
        action: 'Reintentar',
        onAction: () {
          if (context.mounted) unawaited(pick(context));
        },
      );
      return;
    } finally {
      _picking = false;
    }
    if (bytes == null) return;
    final source = session.enqueueImage(bytes);
    onCaptureAdded?.call(source);
  }

  /// Hand-drawn crop of [source]: asks for the rectangle and reads it. With [replacing] the new reading takes
  /// the place of that diagram ("Ajustar recorte"); otherwise it is added at the end of the capture.
  Future<void> cropByHand(
    BuildContext context,
    SourceImage source, {
    Diagram? replacing,
  }) async {
    if (source.isPending || isReadingRegion(source)) return;
    final messenger = ScaffoldMessenger.of(context);
    final box = replacing?.box;
    final initial = box == null
        ? null
        : Box(
            box.x0 - 0.05 * box.width,
            box.y0 - 0.05 * box.height,
            box.x1 + 0.05 * box.width,
            box.y1 + 0.05 * box.height,
          );
    final region = await _cropRegion(context, source.bytes, initial);
    if (region == null) return;
    _readingRegion.add(source);
    notifyListeners();
    try {
      await session.readRegion(source, region, replacing: replacing);
    } on ReadFailure catch (e) {
      toast(
        messenger,
        e.message,
        action: 'Recortar a mano',
        onAction: () {
          if (context.mounted) {
            unawaited(cropByHand(context, source, replacing: replacing));
          }
        },
      );
    } finally {
      _readingRegion.remove(source);
      notifyListeners();
    }
  }

  // ------------------------------------------------------------------- output

  Future<void> copy(
    BuildContext context,
    String text,
    String confirmation,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    await Clipboard.setData(ClipboardData(text: text));
    toast(messenger, confirmation);
  }

  Future<void> openLichess(BuildContext context, Diagram diagram) async {
    final messenger = ScaffoldMessenger.of(context);
    final fen = diagram.fen;
    final opened = await exporter.openInLichess(fen, open: _openUri);
    if (opened) return;
    await Clipboard.setData(
      ClipboardData(text: exporter.lichessAnalysisUri(fen).toString()),
    );
    toast(
      messenger,
      'No se pudo abrir Lichess. Enlace copiado: pégalo en el navegador.',
    );
  }

  /// "Guardar .pgn": the PGN of every diagram, through the system save dialog.
  Future<void> saveAll(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = exporter.pgnFileName(_now());
    try {
      final saved = await _saveFile(name, exporter.pgnBytes(session.allPgn));
      if (saved) {
        toast(
          messenger,
          exporter.savedMessage(name, flagged: session.flaggedCount),
        );
      }
    } catch (_) {
      toast(
        messenger,
        'No se pudo guardar el archivo.',
        action: 'Reintentar',
        onAction: () {
          if (context.mounted) unawaited(saveAll(context));
        },
      );
    }
  }

  /// Share or copy [pgn]: a small sheet with "Copiar PGN", "Compartir como texto" and "Compartir como archivo
  /// .pgn". [copied] is what the snackbar says after copying.
  Future<void> sharePgn(
    BuildContext context,
    String pgn, {
    String copied = 'PGN copiado',
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final how = await showModalBottomSheet<_ShareAs>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const ValueKey('share-copy'),
                leading: const AppIcon(AppIcons.copy),
                title: const Text('Copiar PGN'),
                onTap: () => Navigator.pop(context, _ShareAs.copy),
              ),
              ListTile(
                key: const ValueKey('share-text'),
                leading: const AppIcon(AppIcons.share),
                title: const Text('Compartir como texto'),
                subtitle: const Text('Para chats y notas'),
                onTap: () => Navigator.pop(context, _ShareAs.text),
              ),
              ListTile(
                key: const ValueKey('share-file'),
                leading: const AppIcon(AppIcons.save),
                title: const Text('Compartir como archivo .pgn'),
                subtitle: const Text('Para abrirlo en una app de ajedrez'),
                onTap: () => Navigator.pop(context, _ShareAs.file),
              ),
            ],
          ),
        ),
      ),
    );
    if (how == null) return;
    if (how == _ShareAs.copy) {
      await Clipboard.setData(ClipboardData(text: pgn));
      toast(messenger, copied);
      return;
    }
    try {
      if (how == _ShareAs.text) {
        await _shareText(pgn);
      } else {
        await _shareFile(exporter.pgnFileName(_now()), exporter.pgnBytes(pgn));
      }
    } catch (_) {
      toast(messenger, 'No se pudo compartir. Prueba otra vez o copia el PGN.');
    }
  }
}

enum _ShareAs { copy, text, file }
