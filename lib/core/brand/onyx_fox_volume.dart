import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Объёмная лиса V1 «Кабошон» (#42): низкополигональная огранка чёрного
/// оникса. Каждая грань затеняется по нормали (свет сверху-слева), внутри
/// грани — мягкий градиент, освещённые рёбра бликуют шампанью, внутренние
/// стороны ушей тёплые, нос — «бриллиант». Та же геометрия, что в
/// docs/redesign/src/logo-fox-hood.html (вершины: x, y в 0..100, z — высота).
class FoxVolumePainter extends CustomPainter {
  FoxVolumePainter({this.dark = true, this.accent = const Color(0xFFD2B98F), this.shadow = true});

  final bool dark;
  final Color accent;
  final bool shadow;

  static const Map<String, List<double>> v = {
    'L1': [19, 8, 16], 'LE': [29, 23, 11], 'L2': [40, 33, 6], 'T': [50, 36, 13], 'R2': [60, 33, 6], 'RE': [71, 23, 11], 'R1': [81, 8, 16],
    'RT': [86, 45, 3], 'RC': [73, 68, 6], 'N': [50, 93, 24], 'LC': [27, 68, 6], 'LT': [14, 45, 3], 'LB': [37, 47, 15], 'RB': [63, 47, 15],
    'C': [50, 58, 25], 'M': [50, 77, 26], 'LJ': [36, 80, 10], 'RJ': [64, 80, 10],
  };
  static const facets = [
    ['L1', 'LE', 'LT'], ['LE', 'L2', 'LT'], ['L1', 'L2', 'LE'], ['R1', 'RT', 'RE'], ['RE', 'RT', 'R2'], ['R1', 'RE', 'R2'],
    ['L2', 'T', 'LB'], ['T', 'RB', 'R2'], ['LB', 'T', 'C'], ['T', 'RB', 'C'], ['LT', 'L2', 'LB'], ['R2', 'RT', 'RB'],
    ['LT', 'LB', 'LC'], ['RB', 'RT', 'RC'], ['LB', 'C', 'LC'], ['RB', 'RC', 'C'], ['LC', 'C', 'M'], ['C', 'RC', 'M'],
    ['LC', 'M', 'LJ'], ['M', 'RC', 'RJ'], ['LJ', 'M', 'N'], ['M', 'RJ', 'N'],
  ];
  static const innerEar = {2, 5};
  static const outline = ['L1', 'LE', 'L2', 'T', 'R2', 'RE', 'R1', 'RT', 'RC', 'RJ', 'N', 'LJ', 'LC', 'LT'];

  static List<double> _norm(List<double> a) {
    final l = math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2]);
    return l == 0 ? a : [a[0] / l, a[1] / l, a[2] / l];
  }

  static final light = _norm([-0.55, -0.75, 1.0]);

  @override
  void paint(Canvas canvas, Size size) {
    // Поле знака — 108×112 условных единиц (запас под тень), как в макете.
    final k = size.width / 108;
    canvas.save();
    canvas.translate(4 * k, 4 * k);
    Offset o(String n) => Offset(v[n]![0] * k, v[n]![1] * k);
    final small = size.width < 48;

    if (shadow && !small) {
      final r = Rect.fromCenter(center: Offset(50 * k, 101 * k), width: 60 * k, height: 10 * k);
      canvas.drawOval(r, Paint()
        ..shader = RadialGradient(colors: [Colors.black.withValues(alpha: dark ? .75 : .28), Colors.transparent]).createShader(r));
    }

    final lo = dark ? const Color(0xFF050506) : const Color(0xFF111114);
    final hi = dark ? const Color(0xFF5A564D) : const Color(0xFF77726A);
    for (var i = 0; i < facets.length; i++) {
      final f = facets[i];
      final a = v[f[0]]!, b = v[f[1]]!, c = v[f[2]]!;
      final u = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], w = [c[0] - a[0], c[1] - a[1], c[2] - a[2]];
      var n = _norm([u[1] * w[2] - u[2] * w[1], u[2] * w[0] - u[0] * w[2], u[0] * w[1] - u[1] * w[0]]);
      if (n[2] < 0) n = [-n[0], -n[1], -n[2]];
      final lit = math.max(0.0, n[0] * light[0] + n[1] * light[1] + n[2] * light[2]);
      final base = Color.lerp(lo, hi, math.pow(lit, 1.6).toDouble())!;
      final c1 = innerEar.contains(i) ? Color.lerp(base, accent, .28)! : Color.lerp(base, Colors.white, .08)!;
      final c2 = Color.lerp(base, Colors.black, .35)!;
      final path = Path()..addPolygon([o(f[0]), o(f[1]), o(f[2])], true);
      final cen = Offset((a[0] + b[0] + c[0]) / 3 * k, (a[1] + b[1] + c[1]) / 3 * k);
      canvas.drawPath(path, Paint()
        ..shader = LinearGradient(colors: [c1, c2]).createShader(Rect.fromCenter(center: cen, width: 18 * k, height: 22 * k)));
      if (!small) {
        canvas.drawPath(path, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .45 * k
          ..strokeJoin = StrokeJoin.round
          ..color = accent.withValues(alpha: .08 + math.pow(lit, 3) * .55));
      }
    }
    canvas.drawPath(
      Path()..addPolygon([for (final n in outline) o(n)], true),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = (small ? 2.4 : .8) * k
        ..strokeJoin = StrokeJoin.round
        ..color = accent.withValues(alpha: small ? .9 : .55),
    );
    for (final eye in const [
      [Offset(33, 53), Offset(44, 56), Offset(35, 59)],
      [Offset(67, 53), Offset(56, 56), Offset(65, 59)],
    ]) {
      final p = Path()..addPolygon([for (final e in eye) e * k], true);
      canvas.drawPath(p, Paint()..color = const Color(0xFF030303));
      if (!small) {
        canvas.drawPath(p, Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .6 * k
          ..color = accent.withValues(alpha: .7));
      }
    }
    final nose = Path()..addPolygon([Offset(45 * k, 85 * k), Offset(55 * k, 85 * k), Offset(50 * k, 93.5 * k)], true);
    canvas.drawPath(nose, Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [const Color(0xFFF4E6C8), accent, const Color(0xFF6B5A3E)],
      ).createShader(nose.getBounds()));
    canvas.restore();
  }

  @override
  bool shouldRepaint(FoxVolumePainter o) => o.dark != dark || o.accent != accent || o.shadow != shadow;
}
