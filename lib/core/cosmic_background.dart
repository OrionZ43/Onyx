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
    this.isConnected = false,
  });

  final Animation<double> animation;
  final double intensity;
  final bool isConnected;

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
              isConnected: isConnected,
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
  const _NebulaPainter(
      {required this.progress,
      required this.intensity,
      required this.isConnected});
  final double progress;
  final double intensity;
  final bool isConnected;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height * 0.4;

    // Глубокий сапфир
    _drawBlob(canvas, cx, cy, 250, progress * math.pi * 2,
        const Color(0x150F1A3A), 200);
    // Темный аметист
    _drawBlob(canvas, cx, cy, 200, progress * math.pi * 2 + math.pi,
        const Color(0x101A0F2E), 180);

    // Центральное свечение под кнопкой
    final center = Offset(cx, cy + size.height * 0.12);
    final glowColor =
        isConnected ? AppColors.accentGold : AppColors.accentSilver;
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [
          glowColor.withValues(alpha: 0.05 * intensity),
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
    final center = Offset(x, y);

    // Используем RadialGradient вместо MaskFilter.blur (в 10-20 раз быстрее!)
    final paint = Paint()
      ..shader = RadialGradient(
        colors: [color, color.withValues(alpha: 0.0)],
        stops: const [0.2, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: blur));

    canvas.drawCircle(center, blur, paint);
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
