import 'package:flutter/material.dart';

import 'theme/onyx_tokens.dart';

/// Фон экрана.
///
/// Раньше — анимированная туманность со звёздами (постоянно 60 кадров/с).
/// Теперь — спокойный фон темы: в Onyx едва заметный верхний свет «камня»,
/// в Signal и Material — плоский цвет. Анимации нет; [animation] оставлен
/// ради совместимости со старыми экранами.
class CosmicBackground extends StatelessWidget {
  const CosmicBackground({
    super.key,
    this.animation,
    this.intensity = 1.0,
  });

  final Animation<double>? animation;
  final double intensity;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    if (!t.isOnyx) return ColoredBox(color: t.bg, child: const SizedBox.expand());
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.bg,
        gradient: RadialGradient(
          center: const Alignment(0, -1.25),
          radius: 1.25,
          colors: [const Color(0xFF17171A), t.bg],
          stops: const [0, 0.6],
        ),
      ),
      child: const SizedBox.expand(),
    );
  }
}
