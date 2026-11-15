import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _samples = [
  'Diagrama 12 · Mueven blancas ñ á ü ¿? ½ … 0123456789',
  'rnbqkbnr/pppppppp/8/8/4P3 w KQkq - 0 1',
];

const _files = {
  'Barlow': {
    400: 'Barlow-Regular',
    500: 'Barlow-Medium',
    600: 'Barlow-SemiBold',
    700: 'Barlow-Bold',
  },
  'BarlowCondensed': {
    600: 'BarlowCondensed-SemiBold',
    700: 'BarlowCondensed-Bold',
  },
  'JetBrainsMono': {400: 'JetBrainsMono-Regular', 500: 'JetBrainsMono-Medium'},
};

FontWeight _w(int w) => FontWeight.values[w ~/ 100 - 1];

TextPainter _layout(String text, String family, int weight) => TextPainter(
  text: TextSpan(
    text: text,
    style: TextStyle(fontFamily: family, fontWeight: _w(weight), fontSize: 20),
  ),
  textDirection: TextDirection.ltr,
)..layout();

Future<int> _inkPixels(TextPainter tp) async {
  final rec = ui.PictureRecorder();
  tp.paint(ui.Canvas(rec), ui.Offset.zero);
  final w = tp.width.ceil() + 2, h = tp.height.ceil() + 2;
  final img = await rec.endRecording().toImage(w, h);
  final data = (await img.toByteData())!;
  var n = 0;
  for (var i = 3; i < data.lengthInBytes; i += 4) {
    if (data.getUint8(i) > 128) n++;
  }
  return n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    for (final fam in _files.entries) {
      for (final f in fam.value.entries) {
        final loader = FontLoader('${fam.key}-${f.key}');
        loader.addFont(
          Future.value(
            ByteData.sublistView(
              File('assets/fonts/${f.value}.ttf').readAsBytesSync(),
            ),
          ),
        );
        await loader.load();
      }
    }
  });

  test('every font renders real glyphs, not Ahem boxes', () async {
    final widths = <String, double>{};
    for (final fam in _files.entries) {
      for (final w in fam.value.keys) {
        final family = '${fam.key}-$w';
        for (final s in _samples) {
          final tp = _layout(s, family, w);
          // Ahem would make every glyph exactly fontSize (20) wide.
          expect(
            tp.width,
            isNot(closeTo(s.length * 20.0, 1)),
            reason: '$family looks like Ahem',
          );
          expect(tp.height > 0, isTrue);
          expect(
            await _inkPixels(tp),
            greaterThan(200),
            reason: '$family renders no ink',
          );
        }
        widths['$family/0'] = _layout(_samples[0], family, w).width;
      }
    }
    // Different files give different metrics.
    expect(
      widths['Barlow-400/0'],
      isNot(closeTo(widths['Barlow-700/0']!, 0.5)),
    );
    expect(
      widths['Barlow-500/0'],
      isNot(closeTo(widths['Barlow-600/0']!, 0.1)),
    );
    expect(
      widths['BarlowCondensed-700/0']!,
      lessThan(widths['Barlow-700/0']! * 0.92),
    );
    expect(
      widths['JetBrainsMono-400/0'],
      isNot(closeTo(widths['Barlow-400/0']!, 1)),
    );
  });

  test(
    'the old UI face is gone: no Archivo files, entries or licence text',
    () {
      final bundled = Directory('assets/fonts')
          .listSync()
          .map((e) => e.path.split('/').last);
      expect(
        bundled.where((f) => f.toLowerCase().contains('archivo')),
        isEmpty,
      );
      expect(
        File('pubspec.yaml').readAsStringSync().toLowerCase(),
        isNot(contains('archivo')),
      );
    },
  );

  test('JetBrains Mono is monospaced; Barlow has proportional letters of distinct widths', () {
    final a = _layout('iiiiiiii', 'JetBrainsMono-400', 400).width;
    final b = _layout('WWWWWWWW', 'JetBrainsMono-400', 400).width;
    expect(a, closeTo(b, 0.01));
    expect(a / 8, closeTo(12, 0.5)); // 0.6 em at 20 px
    final i = _layout('iiiiiiii', 'Barlow-400', 400).width;
    final m = _layout('WWWWWWWW', 'Barlow-400', 400).width;
    expect(m, greaterThan(i * 1.5));
  });
}
