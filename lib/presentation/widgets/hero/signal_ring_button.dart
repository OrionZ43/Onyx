import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/onyx_tokens.dart';
import '../signal/dot_matrix.dart';
import 'hero_state.dart';

/// Главная кнопка темы Signal — кольцо из 64 точек и табло в центре.
///
/// * off — точки погашены, на табло `--:--`;
/// * connecting — точки загораются по часовой с «хвостом», в центре процент;
///   на Android — тик хаптики каждые 8 точек;
/// * on — все точки белые, точка на 12 ч — красная REC и медленно «дышит»,
///   табло показывает время сессии;
/// * error — три красные точки сверху и `ERR`, две вспышки.
class SignalRingButton extends StatefulWidget {
  const SignalRingButton({
    super.key,
    required this.phase,
    required this.onTap,
    this.connectedAt,
    this.size = 300,
  });

  final HeroPhase phase;
  final VoidCallback onTap;
  final DateTime? connectedAt;
  final double size;

  static const int dots = 64;

  @override
  State<SignalRingButton> createState() => _SignalRingButtonState();
}

class _SignalRingButtonState extends State<SignalRingButton> with TickerProviderStateMixin {
  Ticker? _ticker;
  double _progress = 0;
  int _lastTick = 0;
  Timer? _clock;
  late final AnimationController _rec = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));
  late final AnimationController _flash = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));

  @override
  void initState() {
    super.initState();
    _enter(widget.phase);
  }

  @override
  void didUpdateWidget(SignalRingButton old) {
    super.didUpdateWidget(old);
    if (old.phase != widget.phase) _enter(widget.phase);
  }

  void _enter(HeroPhase p) {
    _ticker?.dispose();
    _ticker = null;
    _clock?.cancel();
    _clock = null;
    _rec.stop();
    switch (p) {
      case HeroPhase.connecting:
        _progress = 0;
        _lastTick = 0;
        _ticker = createTicker((e) {
          final v = connectingProgress(e);
          final lit = (v * SignalRingButton.dots).floor();
          if (lit ~/ 8 > _lastTick) {
            _lastTick = lit ~/ 8;
            HapticFeedback.selectionClick();
          }
          setState(() => _progress = v);
        })..start();
      case HeroPhase.on:
        _rec.repeat(reverse: true, period: const Duration(milliseconds: 2000));
        _clock = Timer.periodic(const Duration(seconds: 1), (_) {
          if (mounted) setState(() {});
        });
      case HeroPhase.error:
        _flash.forward(from: 0);
      case HeroPhase.off:
        break;
    }
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _clock?.cancel();
    _rec.dispose();
    _flash.dispose();
    super.dispose();
  }

  String _clockText() {
    final at = widget.connectedAt;
    if (at == null) return '--:--';
    final d = DateTime.now().difference(at);
    String two(int v) => v.toString().padLeft(2, '0');
    return d.inHours > 0 ? '${two(d.inHours)}:${two(d.inMinutes % 60)}' : '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
  }

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    final r = widget.size;
    final dot = r * 0.0175, gap = r * 0.0068;
    final phase = widget.phase;
    final Widget board = switch (phase) {
      HeroPhase.on => DotMatrixText(_clockText(), dot: dot, gap: gap, on: t.text, off: const Color(0xFF0E0E0E)),
      HeroPhase.connecting => DotMatrixText(
          '${(_progress * 100).round()}'.padLeft(2, '0'),
          dot: dot * 1.25,
          gap: gap * 1.25,
          on: t.text,
          off: const Color(0xFF0E0E0E),
        ),
      HeroPhase.error => DotMatrixText('ERR', dot: dot, gap: gap, on: AppTheme.signalRec, off: const Color(0xFF161010)),
      HeroPhase.off => DotMatrixText('--:--', dot: dot, gap: gap, on: const Color(0xFF5A5A5A), off: const Color(0xFF121212)),
    };
    final caption = switch (phase) {
      HeroPhase.on => 'нажми — отключить',
      HeroPhase.connecting => 'туннель · ${(_progress * 100).round()}%',
      HeroPhase.error => 'нажми — повторить',
      HeroPhase.off => 'нажми — подключить',
    };
    return Semantics(
      button: true,
      label: heroActionLabel(phase),
      child: GestureDetector(
        onTap: widget.onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: SizedBox.square(
            dimension: r,
            child: Stack(
              alignment: Alignment.center,
              children: [
                RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_rec, _flash]),
                    builder: (_, __) => CustomPaint(
                      size: Size.square(r),
                      painter: _DotRingPainter(
                        phase: phase,
                        progress: _progress,
                        rec: _rec.value,
                        flash: _flash.value,
                      ),
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    board,
                    SizedBox(height: r * 0.055),
                    Text(
                      caption.toUpperCase(),
                      style: t.caps(size: 10.5, color: phase == HeroPhase.off || phase == HeroPhase.connecting ? t.textMuted : t.text),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DotRingPainter extends CustomPainter {
  _DotRingPainter({required this.phase, required this.progress, required this.rec, required this.flash});
  final HeroPhase phase;
  final double progress, rec, flash;

  @override
  void paint(Canvas canvas, Size size) {
    const n = SignalRingButton.dots;
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 8;
    final p = Paint();
    final lit = (progress * n).floor();
    for (var i = 0; i < n; i++) {
      final a = i / n * 2 * math.pi - math.pi / 2;
      final o = c + Offset(math.cos(a), math.sin(a)) * r;
      var rad = 3.0;
      switch (phase) {
        case HeroPhase.on:
          if (i == 0) {
            rad = 4.2;
            p.color = AppTheme.signalRec.withValues(alpha: 0.55 + 0.45 * rec);
          } else {
            p.color = Colors.white;
          }
        case HeroPhase.connecting:
          if (i < lit) {
            final k = 0.25 + 0.75 * (i / math.max(1, lit));
            p.color = Colors.white.withValues(alpha: k);
            if (i == lit - 1) rad = 3.8;
          } else {
            p.color = const Color(0xFF1C1C1C);
          }
        case HeroPhase.error:
          final top = i <= 1 || i >= n - 1;
          final on = flash >= 1 || (flash * 4).floor().isEven;
          p.color = top && on ? AppTheme.signalRec : const Color(0xFF1C1C1C);
        case HeroPhase.off:
          p.color = i % 8 == 0 ? const Color(0xFF3A3A3A) : const Color(0xFF1E1E1E);
      }
      canvas.drawCircle(o, rad, p);
    }
    // Внутренняя пунктирная «трасса».
    final r2 = r - 20;
    p.color = phase == HeroPhase.on ? const Color(0xFF3A3A3A) : const Color(0xFF171717);
    for (var i = 0; i < 96; i++) {
      final a = i / 96 * 2 * math.pi;
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * r2, 1, p);
    }
  }

  @override
  bool shouldRepaint(_DotRingPainter o) =>
      o.phase != phase || o.progress != progress || o.rec != rec || o.flash != flash;
}
