// Getting the PGN out of the app: save as a .pgn file and share (text or file).
// The functions are typedef'd so the screen can be tested without plugins.
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

const pgnMimeType = 'application/x-chess-pgn';

/// Saves [bytes] under [fileName] after asking the user where. False when the user cancelled.
typedef SaveFileFn = Future<bool> Function(String fileName, Uint8List bytes);

/// Opens the system share sheet with plain text.
typedef ShareTextFn = Future<void> Function(String text);

/// Opens the system share sheet with a file.
typedef ShareFileFn = Future<void> Function(String fileName, Uint8List bytes);

/// `diagramas-YYYYMMDD-HHMM.pgn`
String pgnFileName(DateTime t) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'diagramas-${t.year.toString().padLeft(4, '0')}${two(t.month)}${two(t.day)}-${two(t.hour)}${two(t.minute)}.pgn';
}

Uint8List pgnBytes(String pgn) => Uint8List.fromList(utf8.encode(pgn));

/// Android: Storage Access Framework (the user picks the folder); Windows: the native save dialog.
Future<bool> saveFileWithDialog(String fileName, Uint8List bytes) async {
  final uri = await FilePicker.saveFile(
    fileName: fileName,
    bytes: bytes,
    mimeType: pgnMimeType,
    dialogTitle: 'Guardar PGN',
  );
  return uri != null;
}

Future<void> shareText(String text) async {
  await SharePlus.instance.share(ShareParams(text: text));
}

Future<void> shareFile(String fileName, Uint8List bytes) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(bytes, mimeType: pgnMimeType, name: fileName)],
      fileNameOverrides: [fileName],
    ),
  );
}

/// Sharing is only useful on phones: on Windows it opens the system share pane (or a mail draft on old versions).
bool get canShare => defaultTargetPlatform == TargetPlatform.android;

/// Opens [uri] outside the app (the user's browser or the Lichess app). True when something took it.
typedef OpenUriFn = Future<bool> Function(Uri uri);

/// Lichess analysis board for [fen]: `https://lichess.org/analysis/standard/<FEN>`. The slashes of the
/// placement stay path separators and every space of the FEN becomes `_`, which is how Lichess writes its own
/// analysis links (e.g. `.../standard/8/8/8/8/8/8/8/4K2k_w_-_-_0_1`). A FEN only holds letters, digits, `/`, `-`
/// and spaces, so nothing needs percent-encoding.
Uri lichessAnalysisUri(String fen) => Uri(
  scheme: 'https',
  host: 'lichess.org',
  pathSegments: [
    'analysis',
    'standard',
    ...fen.trim().replaceAll(' ', '_').split('/'),
  ],
);

Future<bool> _launchExternally(Uri uri) =>
    launchUrl(uri, mode: LaunchMode.externalApplication);

/// Opens the position in the Lichess analysis board in the browser/app. Returns false (never throws) when
/// nothing could open it, so the caller can fall back to copying `lichessAnalysisUri(fen)` to the clipboard.
/// [open] replaces the real launcher in tests.
Future<bool> openInLichess(String fen, {OpenUriFn? open}) async {
  try {
    return await (open ?? _launchExternally)(lichessAnalysisUri(fen));
  } catch (_) {
    return false;
  }
}
