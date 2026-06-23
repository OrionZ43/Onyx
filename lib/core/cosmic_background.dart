import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'theme/app_colors.dart';

/// Полноэкранный анимированный космический фон.
/// Содержит: туманность (вращающиеся пятна), поле звёзд, частицы пыли.
class CosmicBackground extends StatelessWidget {
  const CosmicBackground({
    super.key,
    required this.animation,
    this.intensity = 1.0,
  });

  final Animation<double> animation;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Stack(
      children: [
        // Базовый градиент
        Container(
          decoration: const BoxDecoration(gradient: AppColors.gradientNebula),
        ),

        // Туманность (вращается медленно)
        AnimatedBuilder(
          animation: animation,
          builder: (_, __) => CustomPaint(
            size: size,
            painter: _NebulaPainter(
              progress: animation.value,
              intensity: intensity,
            ),
          ),
        ),

        // Статичное звёздное поле
        CustomPaint(
          size: size,
          // ИСПРАВЛЕНО: добавлен const
          painter: const _StarFieldPainter(),
        ),

        // Мерцающие звёзды (анимированные)
        AnimatedBuilder(
          animation: animation,
          builder: (_, __) => CustomPaint(
            size: size,
            painter: _TwinklePainter(progress: animation.value),
          ),
        ),
      ],
    );
  }
}

class _NebulaPainter extends CustomPainter {
  const _NebulaPainter({required this.progress, required this.intensity});
  final double progress;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.4;

    // Большое фиолетовое облако
    _drawBlob(
      canvas,
      cx,
      cy,
      200,
      progress * math.pi * 2,
      const Color(0x302A1566),
      140,
    );

    // Синее облако
    _drawBlob(
      canvas,
      cx,
      cy,
      160,
      progress * math.pi * 2 + math.pi * 0.6,
      const Color(0x221533AA),
      120,
    );

    // Маленькое зелёное (aurora)
    _drawBlob(
      canvas,
      cx - 60,
      cy + 80,
      80,
      progress * math.pi * 2 + math.pi * 1.2,
      const Color(0x1400C8A0),
      90,
    );

    // Центральное свечение под кнопкой
    final center = Offset(cx, cy + size.height * 0.12);
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          AppColors.plasma.withValues(alpha: 0.12 * intensity),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: 180));
    canvas.drawCircle(center, 180, glow);
  }

  void _drawBlob(
    Canvas canvas,
    double cx,
    double cy,
    double radius,
    double angle,
    Color color,
    double blur,
  ) {
    final x = cx + radius * math.cos(angle) * 0.5;
    final y = cy + radius * math.sin(angle) * 0.35;
    canvas.drawCircle(
      Offset(x, y),
      blur,
      Paint()
        ..color = color
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur * 0.9),
    );
  }

  @override
  bool shouldRepaint(_NebulaPainter old) => old.progress != progress;
}

class _StarFieldPainter extends CustomPainter {
  // ИСПРАВЛЕНО: добавлен const конструктор (нужен для const _StarFieldPainter())
  const _StarFieldPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(0xDEADBEEF);
    // Крупные звёзды
    for (var i = 0; i < 60; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height * 0.8;
      final r = rng.nextDouble() * 1.5 + 0.3;
      final a = rng.nextDouble() * 0.6 + 0.1;
      canvas.drawCircle(
        Offset(x, y),
        r,
        Paint()..color = Colors.white.withValues(alpha: a),
      );
    }
    // Пылевые частицы (микро)
    for (var i = 0; i < 120; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      canvas.drawCircle(
        Offset(x, y),
        0.4,
        Paint()
          ..color = Colors.white.withValues(alpha: rng.nextDouble() * 0.25),
      );
    }
  }

  @override
  bool shouldRepaint(_StarFieldPainter _) => false;
}

class _TwinklePainter extends CustomPainter {
  const _TwinklePainter({required this.progress});
  final double progress;

  static final _rng = math.Random(0xBEEFCAFE);
  static final _stars = List.generate(
    20,
    (_) => [
      _rng.nextDouble(), // x factor
      _rng.nextDouble(), // y factor
      _rng.nextDouble(), // phase
      _rng.nextDouble() * 1.2 + 0.6, // size
    ],
  );

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in _stars) {
      final phase = s[2];
      final alpha =
          (math.sin((progress + phase) * math.pi * 2) * 0.5 + 0.5) * 0.7 + 0.1;
      canvas.drawCircle(
        Offset(s[0] * size.width, s[1] * size.height * 0.75),
        s[3],
        Paint()..color = Colors.white.withValues(alpha: alpha),
      );
    }
  }

  @override
  bool shouldRepaint(_TwinklePainter old) => old.progress != progress;
}
