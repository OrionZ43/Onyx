import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_new_shapes/material_new_shapes.dart';

import '../../../core/theme/app_motion.dart';
import '../m3/m3_loading_indicator.dart';
import 'hero_state.dart';

/// Главная кнопка темы Material 3 Expressive — «печенька» из MaterialShapes.
///
/// * off — Cookie9 в `primaryContainer`;
/// * connecting — `ContainedLoadingIndicator` (морф и вращение форм, порт
///   Compose из «Расписания МИТСО»);
/// * on — морф в Sunny, `primary`;
/// * error — морф в Puffy, `errorContainer`.
///
/// Форма морфится пружиной `defaultSpatial` (с перелётом), цвет — пружиной
/// `defaultEffects` (без перелёта), как предписывает M3 Expressive. При каждой
/// смене состояния фигура доворачивается на 45°.
class M3CookieButton extends StatefulWidget {
  const M3CookieButton({super.key, required this.phase, required this.onTap, this.size = 240});

  final HeroPhase phase;
  final VoidCallback onTap;
  final double size;

  @override
  State<M3CookieButton> createState() => _M3CookieButtonState();
}

class _M3CookieButtonState extends State<M3CookieButton> with SingleTickerProviderStateMixin {
  static RoundedPolygon _shapeOf(HeroPhase p) => switch (p) {
        HeroPhase.on => MaterialShapes.sunny,
        HeroPhase.error => MaterialShapes.puffy,
        _ => MaterialShapes.cookie9Sided,
      };

  late RoundedPolygon _from = _shapeOf(widget.phase).normalized();
  late RoundedPolygon _to = _from;
  late Morph _morph = Morph(_from, _to);
  late final AnimationController _ctrl = AnimationController.unbounded(vsync: this, value: 1);
  double _turnFrom = 0, _turnTo = 0;
  bool _pressed = false;

  @override
  void didUpdateWidget(M3CookieButton old) {
    super.didUpdateWidget(old);
    if (old.phase == widget.phase) return;
    final next = _shapeOf(widget.phase).normalized();
    if (!identical(next, _to)) {
      // Начинаем морф с текущей промежуточной формы — без скачка.
      _from = _to;
      _to = next;
      _morph = Morph(_from, _to);
      _turnFrom = _turnTo;
      _turnTo += 45;
      if (reduceMotionOf(context)) {
        _ctrl.value = 1;
      } else {
        _ctrl.value = 0;
        _ctrl.animateWith(AppMotion.defaultSpatial.simulate());
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final phase = widget.phase;
    final (Color fill, Color on) = switch (phase) {
      HeroPhase.on => (s.primary, s.onPrimary),
      HeroPhase.error => (s.errorContainer, s.onErrorContainer),
      _ => (s.primaryContainer, s.onPrimaryContainer),
    };
    final size = widget.size;
    final effects = AppMotion.defaultEffects;
    return Semantics(
      button: true,
      label: heroActionLabel(phase),
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: () {
          HapticFeedback.lightImpact();
          widget.onTap();
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedScale(
            scale: _pressed ? 0.94 : 1,
            duration: AppMotion.fastSpatial.duration,
            curve: AppMotion.fastSpatial.curve,
            child: SizedBox.square(
              dimension: size,
              child: AnimatedSwitcher(
                duration: AppMotion.defaultEffects.duration,
                switchInCurve: AppMotion.defaultSpatial.curve,
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: ScaleTransition(scale: Tween(begin: 0.85, end: 1.0).animate(a), child: child),
                ),
                child: phase == HeroPhase.connecting
                    ? M3LoadingIndicator(
                        key: const ValueKey('loading'),
                        contained: true,
                        size: size.clamp(M3LoadingIndicator.minSize, M3LoadingIndicator.maxSize),
                        semanticsLabel: 'Подключение',
                      )
                    : TweenAnimationBuilder<Color?>(
                        key: const ValueKey('shape'),
                        tween: ColorTween(end: fill),
                        duration: effects.duration,
                        curve: effects.curve,
                        builder: (context, color, _) => AnimatedBuilder(
                          animation: _ctrl,
                          builder: (context, _) {
                            final v = _ctrl.value;
                            return Transform.rotate(
                              angle: (_turnFrom + (_turnTo - _turnFrom) * v) * 3.1415926535 / 180,
                              child: CustomPaint(
                                size: Size.square(size),
                                painter: _MorphPainter(_morph, v.clamp(-0.2, 1.2), color ?? fill),
                              ),
                            );
                          },
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    ).withIcon(
      phase == HeroPhase.connecting
          ? null
          : Icon(
              phase == HeroPhase.error ? Icons.error_outline_rounded : Icons.power_settings_new_rounded,
              size: size * 0.24,
              color: on,
            ),
    );
  }
}

extension on Widget {
  /// Иконка поверх фигуры — не вращается вместе с ней.
  Widget withIcon(Widget? icon) => icon == null
      ? this
      : Stack(alignment: Alignment.center, children: [this, IgnorePointer(child: icon)]);
}

class _MorphPainter extends CustomPainter {
  _MorphPainter(this.morph, this.progress, this.color);
  final Morph morph;
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final path = morph.toPath(progress: progress).transform(
          Matrix4.diagonal3Values(size.width, size.height, 1).storage,
        );
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_MorphPainter o) => o.progress != progress || o.color != color || o.morph != morph;
}
