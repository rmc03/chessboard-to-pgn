// Registers the licences of what the app bundles that Flutter does not know about (the piece sets and the
// fonts) with [LicenseRegistry], so Flutter's licence page ("Licencias" in Ajustes) shows them next to the
// licences of the Dart packages. The texts live in assets: assets/licenses/ for the GPL, Apache and MIT
// texts and assets/fonts/ for the font licences; the attribution of each piece set comes from
// assets/pieces/sets.json.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

bool _registered = false;

/// Adds the bundled licences to [LicenseRegistry]. Call once at startup; later calls do nothing. The assets
/// are read lazily, when the licence page is opened.
void registerBundledLicenses([AssetBundle? bundle]) {
  if (_registered) return;
  _registered = true;
  LicenseRegistry.addLicense(() => bundledLicenses(bundle ?? rootBundle));
}

/// Lets a test register again.
@visibleForTesting
void resetBundledLicensesForTest() => _registered = false;

const Map<String, String> _licenseFiles = {
  'GPLv2+': 'assets/licenses/GPL-2.0.txt',
  'GPLv3+': 'assets/licenses/GPL-3.0.txt',
  'Apache 2.0': 'assets/licenses/Apache-2.0.txt',
  'MIT': 'assets/licenses/MIT-celtic.txt',
};

/// Every licence entry of the bundled fonts and piece sets.
Stream<LicenseEntry> bundledLicenses(AssetBundle bundle) async* {
  Future<String?> text(String path) async {
    try {
      return await bundle.loadString(path);
    } catch (e) {
      debugPrint('Licence text $path not found: $e');
      return null;
    }
  }

  // Fonts
  final fonts = <(List<String>, String)>[
    (['Barlow', 'Barlow Condensed'], 'assets/fonts/OFL-Barlow.txt'),
    (['JetBrains Mono'], 'assets/fonts/OFL-JetBrainsMono.txt'),
    (['ChessFigures (DejaVu Sans)'], 'assets/fonts/LICENSE-DejaVu.txt'),
  ];
  for (final (packages, path) in fonts) {
    final body = await text(path);
    if (body != null) yield LicenseEntryWithLineBreaks(packages, body);
  }

  // Piece sets: one attribution entry per set, then each full licence text once for the sets that use it.
  final sets = <Map<String, dynamic>>[];
  try {
    sets.addAll(
      (jsonDecode(await bundle.loadString('assets/pieces/sets.json')) as List)
          .cast<Map<String, dynamic>>(),
    );
  } catch (e) {
    debugPrint('sets.json not found for the licences: $e');
  }
  final byLicense = <String, List<String>>{};
  for (final s in sets) {
    final name = 'Piezas ${s['name']}';
    final license = s['license'] as String;
    (byLicense[license] ??= []).add(name);
    yield LicenseEntryWithLineBreaks(
      [name],
      [
        'Juego de piezas ${s['name']}.',
        'Autor: ${s['author']}.',
        'Licencia: $license (${s['licenseUrl']}).',
        'Origen: ${s['source']}.',
        'Los dibujos se incluyen sin cambios.',
      ].join('\n\n'),
    );
  }
  for (final e in byLicense.entries) {
    final path = _licenseFiles[e.key];
    if (path == null) continue;
    final body = await text(path);
    if (body != null) yield LicenseEntryWithLineBreaks(e.value, body);
  }
}
