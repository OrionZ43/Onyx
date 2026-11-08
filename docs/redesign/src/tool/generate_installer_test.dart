// Картинки установщика Windows (Inno Setup 6.7, тёмный мастер; #51 «Оникс»,
// #52) из финального знака V1 «Кабошон» и вордмарка ONYX.
// Временно копируется в test/tool и запускается:
//   flutter test test/tool/generate_installer_test.dart  → PNG в installer_out/
//
// * wizard_<w>x<h>.png — WizardImageFile, «Приветствие» и «Готово», 164:314,
//   без прозрачности: камень (фон страниц мастера по краям), кольцо «Линзы»
//   в состоянии «защищено», объёмная лиса, внизу ONYX шампанью.
// * small_<n>.png — WizardSmallImageFile, лиса на прозрачном (шапка ~#141312).
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/core/brand/onyx_fox.dart';
import 'package:onyx/core/brand/onyx_fox_volume.dart';

/// Токены темы Onyx (lib/core/theme/app_theme.dart).
const champ = Color(0xFFD2B98F);
const champMuted = Color(0xFF8E7B5B);
const page = Color(0xFF0C0C0E); // surface — фон страниц мастера, стык с картинкой
const track = Color(0xFF222226); // line

Future<void> loadFonts() async {
  final manifest = json.decode(await rootBundle.loadString('FontManifest.json')) as List;
  for (final f in manifest) {
    final loader = FontLoader(f['family'] as String);
    for (final a in f['fonts'] as List) {
      loader.addFont(rootBundle.load(a['asset'] as String));
    }
    await loader.load();
  }
}

Future<void> png(String path, int w, int h, void Function(Canvas c, Size s) draw) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  draw(c, Size(w.toDouble(), h.toDouble()));
  final img = await rec.endRecording().toImage(w, h);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(data!.buffer.asUint8List());
}

/// Вордмарк ONYX как в приложении (OnyxWordmark): Inter Tight 600, трекинг 0,42.
void wordmark(Canvas c, Offset center, double size, Color color) {
  final tp = TextPainter(
    text: TextSpan(
      text: 'ONYX',
      style: TextStyle(fontFamily: 'InterTight', fontSize: size, fontWeight: FontWeight.w600, letterSpacing: size * .42, color: color),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  // Трекинг добавляет пробел и после последней буквы — центрируем по буквам.
  final w = tp.width - size * .42;
  tp.paint(c, Offset(center.dx - w / 2, center.dy - tp.height / 2));
}

/// Боковая картинка мастера.
void side(Canvas c, Size s) {
  final r = Offset.zero & s;
  final w = s.width;
  final center = Offset(w / 2, s.height * .41);

  // Камень: ровный фон страницы по краям, тёплый свет к линзе.
  c.drawRect(r, Paint()..color = page);
  c.drawRect(
    r,
    Paint()
      ..shader = RadialGradient(
        center: Alignment(0, (center.dy / s.height) * 2 - 1),
        radius: .95,
        colors: const [Color(0xFF1D1B17), Color(0xFF121214), page],
        stops: const [0, .45, 1],
      ).createShader(r),
  );
  // По краям — ровно фон страницы: без шва на стыке с текстом мастера.
  for (final (begin, end) in [(Alignment.centerLeft, Alignment.centerRight), (Alignment.topCenter, Alignment.bottomCenter)]) {
    c.drawRect(
      r,
      Paint()
        ..shader = LinearGradient(
          begin: begin,
          end: end,
          colors: [page, page.withValues(alpha: 0), page.withValues(alpha: 0), page],
          stops: const [0, .16, .84, 1],
        ).createShader(r),
    );
  }

  // Кольцо «Линзы» в состоянии «защищено»: трек, замкнутая дуга, свечение.
  final ringR = w * .40;
  final ring = Rect.fromCircle(center: center, radius: ringR);
  c.drawCircle(center, ringR, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = w * .006
    ..color = track);
  c.drawCircle(center, ringR, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = w * .03
    ..color = champ.withValues(alpha: .07)
    ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * .03));
  c.drawArc(ring, -math.pi / 2, 2 * math.pi, false, Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = w * .0085
    ..shader = SweepGradient(
      transform: const GradientRotation(-math.pi / 2),
      colors: [champ.withValues(alpha: .95), champMuted.withValues(alpha: .55), champ.withValues(alpha: .95)],
    ).createShader(ring));

  // Лиса V1 «Кабошон» с мягкой тенью.
  final k = w * .66;
  c.save();
  c.translate(center.dx - k / 2, center.dy - k / 2 + w * .015);
  FoxVolumePainter(shadow: true).paint(c, Size.square(k));
  c.restore();

  // Внизу: тонкая черта и ONYX шампанью.
  final y = s.height * .84;
  c.drawLine(Offset(w * .42, y - w * .12), Offset(w * .58, y - w * .12), Paint()
    ..color = champ.withValues(alpha: .35)
    ..strokeWidth = math.max(1, w * .004));
  wordmark(c, Offset(w / 2, y), w * .1, champ);
}

/// Маленький знак шапки: лиса V1 на прозрачном. Мелко объём не читается —
/// плоский силуэт шампань (как в иконке приложения меньше 48 px).
void small(Canvas c, Size s, {required bool flat}) {
  final k = s.width * (flat ? .86 : .94), o = (s.width - k) / 2;
  c.translate(o, o + s.width * .01);
  if (flat) {
    OnyxFoxPainter(style: FoxStyle.silhouette, ink: champ).paint(c, Size.square(k));
  } else {
    FoxVolumePainter(shadow: false).paint(c, Size.square(k));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadFonts);

  test('wizard image 164:314', () async {
    for (final (w, h) in [(202, 386), (336, 643), (430, 824)]) {
      await png('installer_out/wizard_${w}x$h.png', w, h, side);
    }
  });

  test('wizard small image', () async {
    for (final n in [58, 97, 124, 159]) {
      await png('installer_out/small_$n.png', n, n, (c, s) => small(c, s, flat: false));
      await png('installer_out/small_flat_$n.png', n, n, (c, s) => small(c, s, flat: true));
    }
  });
}
