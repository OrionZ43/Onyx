import 'package:flutter/material.dart';

/// Фирменный знак Onyx — геометричная лиса (задача #42).
///
/// Одна геометрия на всё: экран «О программе», сплэш, иконки приложения и
/// трея (их генерирует `docs/redesign/src/tool/generate_icons_test.dart`).
/// Координаты — в квадрате 100×100.
enum FoxStyle {
  /// A — морда из граней чёрного камня, рёбра — хайрлайн акцента.
  faceted,

  /// C — один непрерывный контур + глаза-грани.
  monoline,

  /// D — точечная матрица 11×11, нос — красная точка (тема Signal).
  dots,

  /// Сплошной силуэт — трей, монохромная иконка Android.
  silhouette,
}

abstract final class FoxGeometry {
  static const l1 = Offset(19, 9), l2 = Offset(40, 33), top = Offset(50, 37), r2 = Offset(60, 33), r1 = Offset(81, 9);
  static const rt = Offset(85, 45), rc = Offset(73, 67), nose = Offset(50, 92), lc = Offset(27, 67), lt = Offset(15, 45);
  static const c = Offset(50, 60), le = Offset(28, 22), re = Offset(72, 22);

  static const outline = [l1, l2, top, r2, r1, rt, rc, nose, lc, lt];

  /// Грани (по часовой) и их тон 0..1 (0 — самая тёмная).
  static const facets = <(List<Offset>, double)>[
    ([l1, l2, lt], .55), ([r1, rt, r2], .35), ([l1, le, l2], .2), ([r1, r2, re], .7),
    ([l2, top, c], .45), ([top, r2, c], .25), ([lt, l2, c], .1), ([r2, rt, c], .5),
    ([lt, c, lc], .8), ([rt, rc, c], .3), ([lc, c, nose], .6), ([c, rc, nose], .05),
  ];

  static const dotRows = [
    '10000000001', '11000000011', '11100000111', '11111111111', '11111111111', '11101110111',
    '01111111110', '00111111100', '00011111000', '00001110000', '00000100000',
  ];

  static Path poly(List<Offset> pts, double s) {
    final p = Path()..moveTo(pts.first.dx * s, pts.first.dy * s);
    for (final o in pts.skip(1)) {
      p.lineTo(o.dx * s, o.dy * s);
    }
    return p..close();
  }
}

/// Знак-лиса. [accent] — цвет хайрлайна и носа (шампань в Onyx);
/// [ink] — основной цвет (камень/контур); [dark] — знак на тёмном фоне.
class OnyxFox extends StatelessWidget {
  const OnyxFox({
    super.key,
    this.size = 96,
    this.style = FoxStyle.faceted,
    this.accent = const Color(0xFFD2B98F),
    this.ink,
    this.dark = true,
  });

  final double size;
  final FoxStyle style;
  final Color accent;
  final Color? ink;
  final bool dark;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: OnyxFoxPainter(style: style, accent: accent, ink: ink, dark: dark)),
      );
}

class OnyxFoxPainter extends CustomPainter {
  OnyxFoxPainter({
    required this.style,
    this.accent = const Color(0xFFD2B98F),
    this.ink,
    this.dark = true,
    this.badge,
    this.hollow = false,
    this.opacity = 1,
  });

  final FoxStyle style;
  final Color accent;
  final Color? ink;
  final bool dark;

  /// Метка состояния в правом нижнем углу (трей): цвет точки или null.
  final Color? badge;

  /// Только контур (трей «отключено»).
  final bool hollow;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    final small = size.width < 40;
    // Свой слой: «вырезы» (BlendMode.clear) не должны пробивать фон под знаком.
    canvas.saveLayer(Offset.zero & size, Paint());
    switch (style) {
      case FoxStyle.faceted:
        final lo = dark ? const Color(0xFF09090A) : const Color(0xFF151518);
        final hi = dark ? const Color(0xFF2A2A2F) : const Color(0xFF4A4A50);
        for (final (pts, tone) in FoxGeometry.facets) {
          canvas.drawPath(FoxGeometry.poly(pts, s), Paint()..color = Color.lerp(lo, hi, tone)!);
          if (!small) {
            canvas.drawPath(
              FoxGeometry.poly(pts, s),
              Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = .7 * s
                ..strokeJoin = StrokeJoin.round
                ..color = accent.withValues(alpha: .55),
            );
          }
        }
        canvas.drawPath(
          FoxGeometry.poly(FoxGeometry.outline, s),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = (small ? 3 : 1.2) * s
            ..strokeJoin = StrokeJoin.round
            ..color = accent,
        );
        _nose(canvas, s, accent);
      case FoxStyle.monoline:
        final c = ink ?? (dark ? const Color(0xFFF3F1EC) : const Color(0xFF0B0B0D));
        canvas.drawPath(
          FoxGeometry.poly(FoxGeometry.outline, s),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = (small ? 9 : 4.5) * s
            ..strokeJoin = StrokeJoin.round
            ..color = c,
        );
        for (final eye in const [
          [Offset(31, 50), Offset(42, 54), Offset(33, 57)],
          [Offset(69, 50), Offset(58, 54), Offset(67, 57)],
        ]) {
          canvas.drawPath(FoxGeometry.poly(eye, s), Paint()..color = accent);
        }
        _nose(canvas, s, accent);
      case FoxStyle.dots:
        final on = ink ?? (dark ? Colors.white : const Color(0xFF0B0B0D));
        final off = dark ? const Color(0xFF1A1A1A) : const Color(0xFFE2E0DB);
        final st = 100 / 11 * s, r = st * .36;
        for (var y = 0; y < 11; y++) {
          for (var x = 0; x < 11; x++) {
            final isNose = y == 10 && x == 5;
            canvas.drawCircle(
              Offset(x * st + st / 2, y * st + st / 2),
              isNose ? r * 1.2 : r,
              Paint()..color = isNose ? const Color(0xFFFF3B2F) : (FoxGeometry.dotRows[y][x] == '1' ? on : (small ? Colors.transparent : off)),
            );
          }
        }
      case FoxStyle.silhouette:
        final c = (ink ?? Colors.white).withValues(alpha: opacity);
        final path = FoxGeometry.poly(FoxGeometry.outline, s);
        if (hollow) {
          canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 11 * s
              ..strokeJoin = StrokeJoin.round
              ..color = c,
          );
        } else {
          canvas.drawPath(path, Paint()..color = c);
          canvas.drawPath(
            path,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 4 * s
              ..strokeJoin = StrokeJoin.round
              ..color = c,
          );
          // Глаза-прорези — чтобы силуэт читался мордой, а не щитом.
          for (final eye in const [
            [Offset(29, 49), Offset(43, 54), Offset(31, 58)],
            [Offset(71, 49), Offset(57, 54), Offset(69, 58)],
          ]) {
            canvas.drawPath(FoxGeometry.poly(eye, s), Paint()..blendMode = BlendMode.clear);
          }
        }
    }
    if (badge != null) {
      final center = Offset(80 * s, 80 * s);
      canvas.drawCircle(center, 24 * s, Paint()..blendMode = BlendMode.clear);
      canvas.drawCircle(center, 18 * s, Paint()..color = badge!);
    }
    canvas.restore();
  }

  void _nose(Canvas canvas, double s, Color c) =>
      canvas.drawPath(FoxGeometry.poly(const [Offset(45, 85), Offset(55, 85), Offset(50, 92.5)], s), Paint()..color = c);

  @override
  bool shouldRepaint(OnyxFoxPainter o) =>
      o.style != style || o.accent != accent || o.ink != ink || o.dark != dark || o.badge != badge || o.hollow != hollow || o.opacity != opacity;
}

