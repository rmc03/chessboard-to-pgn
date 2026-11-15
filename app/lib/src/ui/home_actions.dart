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
import 'tokens.dart';

/// Where images come from: the gallery. Null when the user cancels.
typedef ImageSourceFn = Future<Uint8List?> Function();

/// Lets the user frame a board by hand; null when cancelled. [initial] is in image pixels.
typedef CropRegionFn =
    Future<Box?> Function(BuildContext context, Uint8List bytes, Box? initial);

Future<Box?> defaultCropRegion(
  BuildContext context,
  Uint8List bytes,
  Box? initial,
) => showCropPage(context, bytes, initial: initial);

Future<Uint8List?> pickFromGallery() async {
  final file = await ImagePicker().pickImage(source: ImageSource.gallery);
  return file?.readAsBytes();
}

class HomeActions extends ChangeNotifier {
  HomeActions({
    required this.session,
    ImageSourceFn? pickImage,
    CropRegionFn? cropRegion,
    exporter.SaveFileFn? saveFile,
    exporter.ShareTextFn? shareText,
    exporter.ShareFileFn? shareFile,
    exporter.OpenUriFn? openUri,
    bool? canShare,
    DateTime Function()? now,
  }) : _pickImage = pickImage ?? pickFromGallery,
       _cropRegion = cropRegion ?? defaultCropRegion,
       _saveFile = saveFile ?? exporter.saveFileWithDialog,
       _shareText = shareText ?? exporter.shareText,
       _shareFile = shareFile ?? exporter.shareFile,
       _openUri = openUri,
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
    final messenger = ScaffoldMessenger.of(context);
    final Uint8List? bytes;
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
          if (context.mounted) unawaited(cropByHand(context, source, replacing: replacing));
        },
      );
    } finally {
      _readingRegion.remove(source);
      notifyListeners();
    }
  }

  // ------------------------------------------------------------------- output

  Future<void> copy(BuildContext context, String text, String confirmation) async {
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
    toast(messenger, 'No se pudo abrir Lichess. Enlace copiado.');
  }

  /// "Guardar .pgn": the PGN of every diagram, through the system save dialog.
  Future<void> saveAll(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final name = exporter.pgnFileName(_now());
    try {
      final saved = await _saveFile(name, exporter.pgnBytes(session.allPgn));
      if (saved) toast(messenger, 'Guardado: $name');
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

  /// "Compartir": asks how (text or .pgn file) and hands [pgn] to the system share sheet.
  Future<void> share(BuildContext context, String pgn) async {
    final messenger = ScaffoldMessenger.of(context);
    final how = await showModalBottomSheet<_ShareAs>(
      context: context,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(bottom: Space.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.notes),
                title: const Text('Como texto'),
                subtitle: const Text('Para chats y notas'),
                onTap: () => Navigator.pop(context, _ShareAs.text),
              ),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: const Text('Como archivo .pgn'),
                subtitle: const Text('Para abrirlo en una app de ajedrez'),
                onTap: () => Navigator.pop(context, _ShareAs.file),
              ),
            ],
          ),
        ),
      ),
    );
    if (how == null) return;
    try {
      if (how == _ShareAs.text) {
        await _shareText(pgn);
      } else {
        await _shareFile(exporter.pgnFileName(_now()), exporter.pgnBytes(pgn));
      }
    } catch (_) {
      toast(messenger, 'No se pudo compartir. Inténtalo de nuevo.');
    }
  }
}

enum _ShareAs { text, file }
