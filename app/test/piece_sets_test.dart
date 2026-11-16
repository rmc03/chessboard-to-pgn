import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

const _kinds = ['K', 'Q', 'R', 'B', 'N', 'P'];
const _light = ui.Color(0xFFEEF1F6);
const _dark = ui.Color(0xFF7F9DCB);
const _cell = 96;

class _Raster {
  _Raster(this.w, this.h, this.rgba);
  final int w, h;
  final Uint8List rgba;
  int ch(int x, int y, int c) => rgba[(y * w + x) * 4 + c];
}

/// Draws [pic] scaled to fit a [_cell] square at (dx, dy) on [canvas].
void _drawPiece(ui.Canvas canvas, PictureInfo pic, double dx, double dy) {
  final s =
      _cell /
      (pic.size.width > pic.size.height ? pic.size.width : pic.size.height);
  canvas.save();
  canvas.translate(
    dx + (_cell - pic.size.width * s) / 2,
    dy + (_cell - pic.size.height * s) / 2,
  );
  canvas.scale(s);
  canvas.drawPicture(pic.picture);
  canvas.restore();
}

Future<_Raster> _toRaster(void Function(ui.Canvas) paint, int w, int h) async {
  final rec = ui.PictureRecorder();
  paint(ui.Canvas(rec));
  final img = await rec.endRecording().toImage(w, h);
  final bytes = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  return _Raster(w, h, bytes.buffer.asUint8List());
}

Future<_Raster> _render(PictureInfo pic, ui.Color bg) => _toRaster(
  (c) {
    c.drawRect(
      ui.Rect.fromLTWH(0, 0, _cell.toDouble(), _cell.toDouble()),
      ui.Paint()..color = bg,
    );
    _drawPiece(c, pic, 0, 0);
  },
  _cell,
  _cell,
);

double _lum(int r, int g, int b) => 0.2126 * r + 0.7152 * g + 0.0722 * b;

class _Stats {
  _Stats(
    this.opaque,
    this.meanLum,
    this.whiteShare,
    this.darkShare,
    this.minX,
    this.minY,
    this.maxX,
    this.maxY,
  );
  final double opaque, meanLum, whiteShare, darkShare;
  final int minX, minY, maxX, maxY;
}

/// Analyses a piece using two renders over different backgrounds: a pixel
/// that is identical in both is opaque piece ink; one that differs is
/// (partly) background.
_Stats _analyse(_Raster a, _Raster b) {
  var opaque = 0, white = 0, dark = 0;
  double lumSum = 0;
  var minX = a.w, minY = a.h, maxX = -1, maxY = -1;
  for (var y = 0; y < a.h; y++) {
    for (var x = 0; x < a.w; x++) {
      final ar = a.ch(x, y, 0), ag = a.ch(x, y, 1), ab = a.ch(x, y, 2);
      final br = b.ch(x, y, 0), bg = b.ch(x, y, 1), bb = b.ch(x, y, 2);
      final bgA = _light, bgB = _dark;
      final isBgA =
          (ar - (bgA.r * 255).round()).abs() < 3 &&
          (ag - (bgA.g * 255).round()).abs() < 3 &&
          (ab - (bgA.b * 255).round()).abs() < 3;
      final isBgB =
          (br - (bgB.r * 255).round()).abs() < 3 &&
          (bg - (bgB.g * 255).round()).abs() < 3 &&
          (bb - (bgB.b * 255).round()).abs() < 3;
      if (isBgA && isBgB) continue; // fully transparent
      if (x < minX) minX = x;
      if (x > maxX) maxX = x;
      if (y < minY) minY = y;
      if (y > maxY) maxY = y;
      final same =
          (ar - br).abs() < 8 && (ag - bg).abs() < 8 && (ab - bb).abs() < 8;
      if (!same) continue;
      opaque++;
      final l = _lum(ar, ag, ab);
      lumSum += l;
      if (ar >= 220 && ag >= 220 && ab >= 220) white++;
      if (l < 70) dark++;
    }
  }
  final n = opaque == 0 ? 1 : opaque;
  return _Stats(
    opaque / (a.w * a.h),
    lumSum / n,
    white / n,
    dark / n,
    minX,
    minY,
    maxX,
    maxY,
  );
}

Future<PictureInfo> _load(String svg) =>
    vg.loadPicture(SvgStringLoader(svg), null);

void main() {
  final sets = (jsonDecode(
    File('assets/pieces/sets.json').readAsStringSync(),
  ) as List).cast<Map<String, dynamic>>();

  test('sets.json is valid and lists existing files', () {
    expect(sets.length, inInclusiveRange(5, 8));
    final ids = <String>{};
    for (final s in sets) {
      for (final k in [
        'id',
        'name',
        'author',
        'license',
        'licenseUrl',
        'source',
      ]) {
        expect(s[k], isA<String>(), reason: '${s['id']}.$k');
        expect((s[k] as String).trim(), isNotEmpty, reason: '${s['id']}.$k');
      }
      expect(ids.add(s['id'] as String), isTrue, reason: 'duplicate id');
      final lic = (s['license'] as String).toLowerCase();
      expect(
        lic.contains('nc') ||
            lic.contains('noncommercial') ||
            lic.contains('personal'),
        isFalse,
      );
      for (final c in ['w', 'b']) {
        for (final k in _kinds) {
          final f = File('assets/pieces/${s['id']}/$c$k.svg');
          expect(f.existsSync(), isTrue, reason: f.path);
          expect(f.lengthSync(), greaterThan(200), reason: f.path);
        }
      }
    }
  });

  for (final s in sets) {
    final id = s['id'] as String;
    testWidgets('piece set $id renders correctly', (tester) async {
      await tester.runAsync(() async {
        final pics = <String, PictureInfo>{};
        for (final c in ['w', 'b']) {
          for (final k in _kinds) {
            pics['$c$k'] = await _load(
              File('assets/pieces/$id/$c$k.svg').readAsStringSync(),
            );
          }
        }
        final stats = <String, _Stats>{};
        for (final e in pics.entries) {
          final a = await _render(e.value, _light);
          final b = await _render(e.value, _dark);
          final st = _analyse(a, b);
          stats[e.key] = st;
          final r = '$id/${e.key}';
          expect(
            st.opaque,
            greaterThan(0.06),
            reason: '$r mostly empty (${st.opaque})',
          );
          expect(st.opaque, lessThan(0.75), reason: '$r blob (${st.opaque})');
          // Not clipped: margin on every side, and not spanning all four edges.
          expect(st.minX, greaterThanOrEqualTo(1), reason: '$r touches left');
          expect(st.minY, greaterThanOrEqualTo(1), reason: '$r touches top');
          expect(
            st.maxX,
            lessThanOrEqualTo(_cell - 2),
            reason: '$r touches right',
          );
          expect(
            st.maxY,
            lessThanOrEqualTo(_cell - 2),
            reason: '$r touches bottom',
          );
          expect(st.maxX - st.minX, greaterThan(30), reason: '$r too narrow');
          expect(st.maxY - st.minY, greaterThan(30), reason: '$r too short');
          final cx = (st.minX + st.maxX) / 2, cy = (st.minY + st.maxY) / 2;
          expect(
            (cx - _cell / 2).abs(),
            lessThan(14),
            reason: '$r off-centre x ($cx)',
          );
          expect(
            (cy - _cell / 2).abs(),
            lessThan(14),
            reason: '$r off-centre y ($cy)',
          );
          if (e.key.startsWith('w')) {
            expect(
              st.whiteShare,
              greaterThan(0.12),
              reason: '$r white share ${st.whiteShare}',
            );
          } else {
            expect(
              st.meanLum,
              lessThan(120),
              reason: '$r not dark (${st.meanLum})',
            );
            expect(
              st.darkShare,
              greaterThan(0.35),
              reason: '$r dark share ${st.darkShare}',
            );
          }
        }
        for (final k in _kinds) {
          expect(
            stats['w$k']!.meanLum,
            greaterThan(stats['b$k']!.meanLum + 40),
            reason: '$id/$k white not lighter than black',
          );
        }

        final dir = Platform.environment['PIECES_PNG_DIR'];
        if (dir != null && dir.isNotEmpty) {
          Directory(dir).createSync(recursive: true);
          final order = [
            for (final c in ['w', 'b'])
              for (final k in _kinds) '$c$k',
          ];
          final sheet = await _toRaster(
            (c) {
              for (var i = 0; i < 12; i++) {
                final col = i % 6, row = i ~/ 6;
                final dx = col * _cell.toDouble(), dy = row * _cell.toDouble();
                c.drawRect(
                  ui.Rect.fromLTWH(dx, dy, _cell.toDouble(), _cell.toDouble()),
                  ui.Paint()..color = (col + row).isEven ? _light : _dark,
                );
                _drawPiece(c, pics[order[i]]!, dx, dy);
              }
            },
            _cell * 6,
            _cell * 2,
          );
          final img =
              await ui.ImageDescriptor.raw(
                    await ui.ImmutableBuffer.fromUint8List(sheet.rgba),
                    width: sheet.w,
                    height: sheet.h,
                    pixelFormat: ui.PixelFormat.rgba8888,
                  )
                  .instantiateCodec()
                  .then((c) => c.getNextFrame())
                  .then((f) => f.image);
          final png = (await img.toByteData(format: ui.ImageByteFormat.png))!;
          File('$dir/$id.png').writeAsBytesSync(png.buffer.asUint8List());
        }
      });
    });
  }
}
