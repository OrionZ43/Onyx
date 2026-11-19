// Генератор иконок Onyx из финального знака V1 «Кабошон» (#42).
// Временно копируется в test/tool и запускается:
//   flutter test test/tool/generate_icons_test.dart  → PNG в icons_out/
// затем docs/redesign/src/tool/pack_icons.sh раскладывает их по проекту.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/core/brand/onyx_fox.dart';
import 'package:onyx/core/brand/onyx_fox_volume.dart';

const champ = Color(0xFFD2B98F);

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

/// Знак V1 в квадрате [s] с отступом [pad] (доля стороны).
void fox(Canvas c, Size s, {double scale = .78, double dy = 0, bool flat = false, Color ink = champ, bool shadow = false}) {
  final k = s.width * scale, o = (s.width - k) / 2;
  c.save();
  c.translate(o, o + s.width * dy);
  if (flat) {
    OnyxFoxPainter(style: FoxStyle.silhouette, ink: ink).paint(c, Size.square(k));
  } else {
    FoxVolumePainter(shadow: shadow).paint(c, Size.square(k));
  }
  c.restore();
}

/// Плитка «камень»: скруглённый квадрат, верхний свет, тонкий кант шампань.
void tile(Canvas c, Size s) {
  final r = RRect.fromRectAndRadius(Offset.zero & s, Radius.circular(s.width * .22));
  c.drawRRect(r, Paint()
    ..shader = const RadialGradient(center: Alignment(0, -1), radius: 1.25, colors: [Color(0xFF26251F), Color(0xFF0A0A0B), Color(0xFF050506)], stops: [0, .55, 1])
        .createShader(Offset.zero & s));
  if (s.width >= 48) {
    c.drawRRect(r.deflate(s.width * .006), Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.width * .012
      ..color = champ.withValues(alpha: .28));
  }
}

void main() {
  test('app + favicon', () async {
    for (final sz in [16, 20, 24, 32, 40, 48, 64, 96, 128, 256, 512, 1024]) {
      await png('icons_out/app_$sz.png', sz, (c, s) {
        tile(c, s);
        // Мелко объём не читается — плоский силуэт шампань; крупно — объёмная огранка.
        if (sz < 48) {
          fox(c, s, scale: .74, dy: .02, flat: true);
        } else {
          fox(c, s, scale: .86, dy: .03);
        }
      });
    }
  });

  test('android', () async {
    // Adaptive: foreground 432 px (108 dp @4x), знак в безопасной зоне 66 dp ≈ 61 %.
    await png('icons_out/android_fg.png', 432, (c, s) => fox(c, s, scale: .62, dy: .02));
    await png('icons_out/android_mono.png', 432, (c, s) => fox(c, s, scale: .54, dy: .02, flat: true, ink: Colors.white));
    // Сплэш (drawable-nodpi): объёмная лиса с мягкой тенью на прозрачном.
    await png('icons_out/splash_fox.png', 384, (c, s) => fox(c, s, scale: .9, shadow: true));
  });

  test('tray', () async {
    final states = <String, OnyxFoxPainter>{
      'off': OnyxFoxPainter(style: FoxStyle.silhouette, hollow: true),
      'ing': OnyxFoxPainter(style: FoxStyle.silhouette, opacity: .55),
      'on': OnyxFoxPainter(style: FoxStyle.silhouette, badge: champ),
      'err': OnyxFoxPainter(style: FoxStyle.silhouette, badge: const Color(0xFFE5484D)),
    };
    for (final e in states.entries) {
      for (final sz in [16, 20, 24, 32, 48, 64]) {
        await png('icons_out/tray_${e.key}_$sz.png', sz, (c, s) {
          final pad = s.width / 16;
          c.translate(pad, pad);
          e.value.paint(c, Size.square(s.width - 2 * pad));
        });
      }
    }
  });

  test('brand', () async {
    await png('icons_out/onyx_fox_1024.png', 1024, (c, s) => fox(c, s, scale: .9, shadow: true));
    await png('icons_out/onyx_fox_dots_512.png', 512, (c, s) {
      final k = s.width * .84, o = (s.width - k) / 2;
      c.translate(o, o);
      OnyxFoxPainter(style: FoxStyle.dots).paint(c, Size.square(k));
    });
  });
}
