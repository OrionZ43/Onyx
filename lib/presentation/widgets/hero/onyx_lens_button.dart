import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/theme/app_motion.dart';
import '../../../core/theme/onyx_tokens.dart';
import '../onyx_icon.dart';
import 'hero_state.dart';

/// Главная кнопка темы Onyx — «Линза» (docs/redesign/concepts.md §9).
///
/// Круг из чёрного камня с мягким объёмом и световым ободком 1 px; вокруг на
/// зазоре — тонкое кольцо, в котором живёт состояние:
/// * off — графитовый трек;
/// * connecting — шампань-дуга растёт от 12 ч, яркость «дышит» (1,6 с);
/// * on — кольцо замкнуто, тёплое свечение;
/// * error — короткий терракотовый сегмент сверху, две вспышки и покой.
///
/// В покое (off / on) тикер стоит — 0 кадров/с.
class OnyxLensButton extends StatefulWidget {
  const OnyxLensButton({super.key, required this.phase, required this.onTap, this.size = 280, this.compact = false, this.progress});

  final HeroPhase phase;
  final VoidCallback onTap;
  final double size;

  /// Без подписи внутри — для маленьких размеров (мини-панель в трее).
  final bool compact;

  /// Настоящий прогресс этапа 0..1 (автопилот: проверено серверов из всех);
  /// null — условная дуга по времени.
  final double? progress;

  @override
  State<OnyxLensButton> createState() => _OnyxLensButtonState();
}

class _OnyxLensButtonState extends State<OnyxLensButton> with TickerProviderStateMixin {
  /// Длина дуги 0..1 и «включённость» тёплого свечения 0..1.
  late final AnimationController _arc = AnimationController(
    vsync: this,
    value: widget.phase == HeroPhase.on ? 1 : 0,
  );
  late final AnimationController _glow = AnimationController(
    vsync: this,
    duration: OnyxMotion.slow,
    value: widget.phase == HeroPhase.on ? 1 : 0,
  );
  late final AnimationController _errorPulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  Ticker? _connectTicker;
  double _breath = 1;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    if (widget.phase == HeroPhase.connecting) _startConnecting();
  }

  @override
  void didUpdateWidget(OnyxLensButton old) {
    super.didUpdateWidget(old);
    if (old.phase == widget.phase) return;
    _stopConnecting();
    switch (widget.phase) {
      case HeroPhase.connecting:
        _startConnecting();
        _glow.animateTo(0, duration: OnyxMotion.fast);
      case HeroPhase.on:
        _arc.animateTo(1, duration: OnyxMotion.medium, curve: OnyxMotion.enter);
        _glow.animateTo(1, curve: OnyxMotion.enter);
      case HeroPhase.off:
        _arc.animateTo(0, duration: const Duration(milliseconds: 350), curve: OnyxMotion.exit);
        _glow.animateTo(0, duration: OnyxMotion.medium);
      case HeroPhase.error:
        _arc.animateTo(0, duration: OnyxMotion.fast);
        _glow.animateTo(0, duration: OnyxMotion.fast);
        _errorPulse.forward(from: 0);
    }
  }

  void _startConnecting() {
    final from = _arc.value;
    var real = false;
    _connectTicker = createTicker((elapsed) {
      final p = widget.progress;
      if (p != null || real) {
        // Настоящий прогресс (автопилот) — плавно догоняем, до полного кольца
        // не доводим; когда этап сменился подключением — тянемся к 0,9.
        real = true;
        final goal = p != null ? p.clamp(0.0, 1.0) * 0.95 : 0.9;
        _arc.value += (goal - _arc.value) * 0.12;
      } else {
        final target = connectingProgress(elapsed);
        // Дуга не откатывается назад, если подключение началось с непустой.
        _arc.value = math.max(from * (1 - target), target);
      }
      _breath = 0.8 + 0.2 * math.cos(elapsed.inMilliseconds / 1600 * 2 * math.pi);
    })..start();
  }

  void _stopConnecting() {
    _connectTicker?.dispose();
    _connectTicker = null;
    _breath = 1;
  }

  @override
  void dispose() {
    _stopConnecting();
    _arc.dispose();
    _glow.dispose();
    _errorPulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    final d = widget.size;
    final lens = d * 0.74;
    final phase = widget.phase;
    final label = heroActionLabel(phase);
    final contentColor = switch (phase) {
      HeroPhase.on => t.accent,
      HeroPhase.connecting => t.accentMuted,
      HeroPhase.error => t.text,
      HeroPhase.off => t.text,
    };
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: widget.onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: SizedBox.square(
            dimension: d,
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: Listenable.merge([_arc, _glow, _errorPulse]),
                builder: (context, _) => CustomPaint(
                  painter: _RingPainter(
                    tokens: t,
                    arc: _arc.value,
                    breath: _breath,
                    glow: _glow.value,
                    error: phase == HeroPhase.error,
                    errorPulse: _errorPulse.value,
                    lensDiameter: lens,
                  ),
                  child: Center(
                    child: AnimatedScale(
                      scale: _pressed || phase == HeroPhase.connecting ? 0.975 : 1,
                      duration: OnyxMotion.fast,
                      curve: OnyxMotion.enter,
                      child: _Lens(
                        diameter: lens,
                        glow: _glow.value,
                        phase: phase,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            OnyxIcon(OnyxGlyph.power, size: lens * (widget.compact ? 0.22 : 0.15), color: contentColor),
                            if (!widget.compact) SizedBox(height: lens * 0.05),
                            if (!widget.compact) AnimatedDefaultTextStyle(
                              duration: OnyxMotion.medium,
                              style: t.caps(
                                size: 10.5,
                                color: phase == HeroPhase.error
                                    ? t.danger
                                    : phase == HeroPhase.off
                                        ? t.textMuted
                                        : contentColor,
                              ),
                              child: Text(label.toUpperCase()),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Сам камень: радиальный объём, внутренняя тень, ободок ярче сверху.
class _Lens extends StatelessWidget {
  const _Lens({required this.diameter, required this.glow, required this.phase, required this.child});
  final double diameter;
  final double glow;
  final HeroPhase phase;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    final warm = glow;
    final top = Color.lerp(const Color(0xFF1D1D21), const Color(0xFF1F1D19), warm)!;
    final mid = Color.lerp(const Color(0xFF101012), const Color(0xFF110F0D), warm)!;
    return Container(
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(0, -1),
          radius: 1.1,
          colors: [top, mid, const Color(0xFF070708)],
          stops: const [0, 0.45, 1],
        ),
        boxShadow: [
          const BoxShadow(color: Color(0x99000000), blurRadius: 48, offset: Offset(0, 16)),
          if (warm > 0)
            BoxShadow(color: t.accent.withValues(alpha: 0.13 * warm), blurRadius: 90),
        ],
      ),
      child: CustomPaint(
        painter: _RimPainter(tokens: t, warm: warm, phase: phase),
        child: Center(child: child),
      ),
    );
  }
}

class _RimPainter extends CustomPainter {
  _RimPainter({required this.tokens, required this.warm, required this.phase});
  final OnyxTokens tokens;
  final double warm;
  final HeroPhase phase;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final c = rect.center;
    final r = size.width / 2;
    // Внутренняя тень снизу — объём.
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0x00000000), Color(0x00000000), Color(0x8C000000)],
          stops: [0, 0.6, 1],
        ).createShader(rect),
    );
    // Блик сверху.
    final hl = Rect.fromCenter(center: Offset(c.dx, size.height * 0.16), width: size.width * 0.56, height: size.height * 0.22);
    canvas.drawOval(
      hl,
      Paint()
        ..shader = const RadialGradient(colors: [Color(0x0FFFFFFF), Color(0x00FFFFFF)]).createShader(hl),
    );
    // Ободок 1 px: ярче сверху, гаснет к бокам.
    final Color rim = switch (phase) {
      HeroPhase.error => tokens.danger,
      HeroPhase.connecting => tokens.accent,
      _ => Color.lerp(Colors.white, tokens.accent, warm)!,
    };
    final double topA = switch (phase) {
      HeroPhase.error => 0.55,
      HeroPhase.connecting => 0.40,
      _ => 0.30 + 0.45 * warm,
    };
    canvas.drawCircle(
      c,
      r - 0.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            rim.withValues(alpha: topA),
            rim.withValues(alpha: 0.04 + 0.06 * warm),
            rim.withValues(alpha: 0.02 + 0.02 * warm),
            rim.withValues(alpha: 0.08 + 0.14 * warm),
          ],
          stops: const [0, 0.38, 0.7, 1],
        ).createShader(rect),
    );
    canvas.drawCircle(c, r + 0.5, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Color.lerp(const Color(0xFF17171A), const Color(0xFF2A2419), warm)!);
  }

  @override
  bool shouldRepaint(_RimPainter o) => o.warm != warm || o.phase != phase || o.tokens != tokens;
}

/// Кольцо прогресса вокруг линзы.
class _RingPainter extends CustomPainter {
  _RingPainter({
    required this.tokens,
    required this.arc,
    required this.breath,
    required this.glow,
    required this.error,
    required this.errorPulse,
    required this.lensDiameter,
  });

  final OnyxTokens tokens;
  final double arc, breath, glow, errorPulse, lensDiameter;
  final bool error;

  static const double stroke = 1.6, gap = 13;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = lensDiameter / 2 + gap;
    final rect = Rect.fromCircle(center: c, radius: r);
    // Трек.
    canvas.drawCircle(c, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = error ? const Color(0xFF2A1714) : const Color(0xFF1A1A1D));

    if (error) {
      // Две мягкие вспышки, затем ровный сегмент.
      final flash = errorPulse < 1 ? (0.5 + 0.5 * math.cos(errorPulse * 4 * math.pi)) : 1.0;
      final seg = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = tokens.danger.withValues(alpha: 0.35 + 0.65 * flash);
      canvas.drawArc(rect, -math.pi / 2 - 0.25, 0.5, false, seg);
      return;
    }
    if (arc <= 0.001) return;
    final sweep = 2 * math.pi * arc;
    final shader = SweepGradient(
      startAngle: 0,
      endAngle: 2 * math.pi,
      transform: const GradientRotation(-math.pi / 2),
      colors: [const Color(0xFF9C8661), const Color(0xFFE6D3AE), const Color(0xFF9C8661)],
      stops: const [0, 0.5, 1],
    ).createShader(rect);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = arc >= 0.999 ? StrokeCap.butt : StrokeCap.round
      ..shader = shader;
    // Свечение дуги — один размытый проход, только когда виден акцент.
    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke * 3
      ..color = tokens.accent.withValues(alpha: 0.28 * breath * (0.5 + 0.5 * glow))
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawArc(rect, -math.pi / 2, sweep, false, glowPaint);
    canvas.saveLayer(rect.inflate(8), Paint()..color = Color.fromRGBO(0, 0, 0, breath));
    canvas.drawArc(rect, -math.pi / 2, sweep, false, p);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_RingPainter o) =>
      o.arc != arc || o.breath != breath || o.glow != glow || o.error != error || o.errorPulse != errorPulse;
}
