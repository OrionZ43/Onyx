// Генератор иконок Onyx из фирменной геометрии (lib/core/brand/onyx_fox.dart).
// Запуск: flutter test test/tool/generate_icons_test.dart → PNG в icons_out/,
// затем ImageMagick собирает .ico (см. docs/redesign/src/tool/pack_icons.sh).
@Tags(['tool'])
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/core/brand/onyx_fox.dart';

Future<void> png(String path, int size, void Function(Canvas c, Size s) draw) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  draw(c, Size.square(size.toDouble()));
  final img = await rec.endRecording().toImage(size, size);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(data!.buffer.asUint8List());
}

void main() {
  test('tray', () async {
    // Моно-значки трея: белый силуэт; состояние — контур / полупрозрачный / силуэт / красная метка.
    final states = <String, OnyxFoxPainter>{
      'off': OnyxFoxPainter(style: FoxStyle.silhouette, hollow: true),
      'ing': OnyxFoxPainter(style: FoxStyle.silhouette, opacity: .55),
      'on': OnyxFoxPainter(style: FoxStyle.silhouette, badge: const Color(0xFFD2B98F)),
      'err': OnyxFoxPainter(style: FoxStyle.silhouette, badge: const Color(0xFFE5484D)),
    };
    for (final e in states.entries) {
      for (final sz in [16, 20, 24, 32, 48, 64]) {
        await png('icons_out/tray_${e.key}_$sz.png', sz, (c, s) {
          // Отступ 1/16, чтобы уши не упирались в край.
          final pad = s.width / 16;
          c.translate(pad, pad);
          e.value.paint(c, Size.square(s.width - 2 * pad));
        });
      }
    }
  });

  test('app', () async {
    // Иконка приложения: знак на тёмном камне (скруглённый квадрат).
    for (final sz in [16, 24, 32, 48, 64, 128, 256, 512]) {
      await png('icons_out/app_$sz.png', sz, (c, s) {
        final r = RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(s.width * .22));
        c.drawRRect(
          r,
          Paint()
            ..shader = const RadialGradient(center: Alignment(0, -1), radius: 1.2, colors: [Color(0xFF1E1D1B), Color(0xFF060607)]).createShader(Offset.zero & s),
        );
        if (sz >= 48) {
          c.drawRRect(r.deflate(.5), Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = const Color(0x33D2B98F));
        }
        final k = s.width * .7, o = (s.width - k) / 2;
        c.translate(o, o + s.width * .02);
        OnyxFoxPainter(style: sz < 32 ? FoxStyle.silhouette : FoxStyle.faceted, ink: const Color(0xFFD2B98F)).paint(c, Size.square(k));
      });
    }
    // Android adaptive: foreground 432×432 (знак в безопасной зоне 66%), monochrome — силуэт.
    await png('icons_out/android_fg.png', 432, (c, s) {
      final k = s.width * .5, o = (s.width - k) / 2;
      c.translate(o, o + 6);
      OnyxFoxPainter(style: FoxStyle.faceted).paint(c, Size.square(k));
    });
    await png('icons_out/android_mono.png', 432, (c, s) {
      final k = s.width * .5, o = (s.width - k) / 2;
      c.translate(o, o + 6);
      OnyxFoxPainter(style: FoxStyle.silhouette).paint(c, Size.square(k));
    });
  });
}
