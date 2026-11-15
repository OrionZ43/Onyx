import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_new_shapes/material_new_shapes.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../core/theme/app_motion.dart';
import '../../../core/theme/m3/app_state_layer.dart';
import '../../../core/theme/m3/oklab.dart';
import '../m3/m3_loading_indicator.dart';
import 'hero_state.dart';

/// Главная кнопка темы Material 3 Expressive: фигура MaterialShapes, которая
/// сама становится индикатором подключения.
///
/// * off — [restShape] (`Cookie9Sided`) в `primaryContainer`;
/// * connecting — морф и вращение по циклу неопределённого `LoadingIndicator`
///   из Compose (`LoadingIndicator.kt`, порт — [LoadingIndicatorMotion]):
///   формы `IndeterminateIndicatorPolygons`, сдвинутые так, чтобы цикл
///   начинался с формы покоя; морф каждые 650 мс пружиной 0.6/200, 90° за
///   морф и оборот за 4666 мс. В центре — крестик: нажатие отменяет;
/// * on — [onShape] (`Clover8Leaf`) в `primary`;
/// * error — [errorShape] (`Burst`) в `errorContainer`, иконка повтора.
///
/// Смена состояния — морф из текущей формы в новую пружиной `defaultSpatial`
/// с доворотом на 90° (как шаг индикатора); цвет — пружиной `defaultEffects`
/// в Oklab, как `animateColorAsState`. Из подключения кнопка выходит, когда
/// текущий шаг цикла доиграл: форма стоит ровно на фигуре цикла, и морф
/// начинается без скачка. Если состояние сменилось посреди морфа, следующий
/// морф начнётся, когда этот закончится.
///
/// Взаимодействие: state layer цветом содержимого (hover 8 %, focus и press
/// 10 %, `StateTokens`), нажатие сжимает фигуру до [pressedScale] пружиной
/// `fastSpatial`. При «Удалить анимации» формы и цвета меняются сразу, цикла
/// нет.
class M3ShapeButton extends StatefulWidget {
  const M3ShapeButton({
    super.key,
    required this.phase,
    required this.onTap,
    this.size = 240,
  });

  final HeroPhase phase;
  final VoidCallback onTap;

  /// Сторона квадрата кнопки. Все формы сжаты общим коэффициентом
  /// (`calculateScaleFactor`, как в `LoadingIndicator`), чтобы при вращении не
  /// выходить за этот квадрат и не «прыгать» по размеру.
  final double size;

  /// Форма покоя; с неё же начинается цикл подключения.
  static final RoundedPolygon restShape = MaterialShapes.cookie9Sided;

  /// «Подключено»: мягкая полная форма — контраст с колючей [errorShape].
  static final RoundedPolygon onShape = MaterialShapes.clover8Leaf;

  /// «Ошибка»: острые лучи — приём «tension» M3 Expressive.
  static final RoundedPolygon errorShape = MaterialShapes.burst;

  /// Цикл подключения — `IndeterminateIndicatorPolygons` (softBurst,
  /// cookie9Sided, pentagon, pill, sunny, cookie4Sided, oval), начатый с
  /// [restShape].
  static final List<RoundedPolygon> loop = List.unmodifiable([
    restShape,
    MaterialShapes.pentagon,
    MaterialShapes.pill,
    MaterialShapes.sunny,
    MaterialShapes.cookie4Sided,
    MaterialShapes.oval,
    MaterialShapes.softBurst,
  ]);

  /// Сжатие при нажатии. Токена у M3 нет — отступление записано в
  /// `docs/redesign/m3.md`.
  static const double pressedScale = 0.94;

  @override
  State<M3ShapeButton> createState() => _M3ShapeButtonState();
}

enum _Mode { idle, morphing, looping }

class _M3ShapeButtonState extends State<M3ShapeButton>
    with TickerProviderStateMixin {
  static final List<Morph> _loopMorphs =
      LoadingIndicatorShapeSequence.morphSequence(
        M3ShapeButton.loop,
        circular: true,
      );

  static final double _scale =
      LoadingIndicatorShapeSequence.calculateScaleFactor([
        ...M3ShapeButton.loop,
        M3ShapeButton.onShape,
        M3ShapeButton.errorShape,
      ]);

  static final Map<RoundedPolygon, Path> _paths = {};
  static Path _pathOf(RoundedPolygon p) =>
      _paths.putIfAbsent(p, () => p.normalized().toPath());

  late final Ticker _ticker = createTicker(_tick);
  final _HeroFrame _frame = _HeroFrame();
  late final AnimationController _press = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );

  _Mode _mode = _Mode.idle;

  /// Непрерывное время кнопки: тикер в покое стоит, а после перезапуска
  /// считает с нуля — поэтому `_now = _base + elapsed`.
  Duration _now = Duration.zero;
  Duration _base = Duration.zero;

  /// Форма, на которой кнопка стоит (или в которую морфится).
  late RoundedPolygon _shape = _shapeOf(widget.phase);
  double _rotation = 0;

  Morph? _morph;
  RoundedPolygon? _morphTo;
  Duration _morphStart = Duration.zero;
  final SpringSimulation _morphSpring = AppMotion.defaultSpatial.simulate();
  final Path _morphPath = Path();

  Duration _loopStart = Duration.zero;

  late (Color, Color) _colorsFrom = _colorsOf(widget.phase);
  late (Color, Color) _colorsTo = _colorsFrom;
  Duration _colorStart = Duration.zero;
  bool _colorRunning = false;
  final SpringSimulation _colorSpring = AppMotion.defaultEffects.simulate();

  bool _hovered = false, _focused = false, _pressed = false;
  bool _reduceMotion = false;

  static RoundedPolygon _shapeOf(HeroPhase p) => switch (p) {
    HeroPhase.on => M3ShapeButton.onShape,
    HeroPhase.error => M3ShapeButton.errorShape,
    HeroPhase.off || HeroPhase.connecting => M3ShapeButton.restShape,
  };

  (Color, Color) _colorsOf(HeroPhase p) {
    final ColorScheme s = Theme.of(context).colorScheme;
    return switch (p) {
      HeroPhase.on => (s.primary, s.onPrimary),
      HeroPhase.error => (s.errorContainer, s.onErrorContainer),
      HeroPhase.off ||
      HeroPhase.connecting => (s.primaryContainer, s.onPrimaryContainer),
    };
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = reduceMotionOf(context);
    // Схема могла смениться (обои, тема): цвет — сразу к новому значению.
    _colorsTo = _colorsOf(widget.phase);
    if (!_colorRunning) _colorsFrom = _colorsTo;
    _advance();
    _render();
  }

  @override
  void didUpdateWidget(M3ShapeButton old) {
    super.didUpdateWidget(old);
    if (old.phase == widget.phase) return;
    final (Color, Color) shown = _currentColors();
    _colorsFrom = shown;
    _colorsTo = _colorsOf(widget.phase);
    _colorStart = _now;
    _colorRunning = !_reduceMotion;
    _advance();
    _render();
  }

  @override
  void dispose() {
    _ticker.dispose();
    _press.dispose();
    _frame.dispose();
    super.dispose();
  }

  // ── Логика состояний ─────────────────────────────────────────────────────

  /// Запускает следующий шаг к состоянию [widget.phase], если кнопка свободна.
  void _advance() {
    if (_mode != _Mode.idle) return;
    final HeroPhase want = widget.phase;
    if (want == HeroPhase.connecting) {
      if (_reduceMotion) {
        _shape = M3ShapeButton.restShape;
      } else if (identical(_shape, M3ShapeButton.restShape)) {
        _mode = _Mode.looping;
        _loopStart = _now;
      } else {
        _startMorph(M3ShapeButton.restShape);
      }
    } else {
      final RoundedPolygon target = _shapeOf(want);
      if (identical(_shape, target)) return;
      if (_reduceMotion) {
        _shape = target;
      } else {
        _startMorph(target);
      }
    }
    _ensureTicking();
  }

  void _startMorph(RoundedPolygon to) {
    _morph = Morph(_shape.normalized(), to.normalized());
    _morphTo = to;
    _morphStart = _now;
    _mode = _Mode.morphing;
  }

  void _ensureTicking() {
    final bool busy = _mode != _Mode.idle || _colorRunning;
    if (busy && !_ticker.isActive) {
      _base = _now;
      _ticker.start();
    }
  }

  (Color, Color) _currentColors() {
    if (!_colorRunning) return _colorsTo;
    final double t = _colorProgress();
    return (
      lerpOklab(_colorsFrom.$1, _colorsTo.$1, t),
      lerpOklab(_colorsFrom.$2, _colorsTo.$2, t),
    );
  }

  double _colorProgress() {
    final double t = (_now - _colorStart).inMicroseconds / 1e6;
    return _colorSpring.x(t).clamp(0.0, 1.0);
  }

  void _tick(Duration elapsed) {
    _now = _base + elapsed;
    if (_colorRunning) {
      final double t = (_now - _colorStart).inMicroseconds / 1e6;
      if (_colorSpring.isDone(t)) _colorRunning = false;
    }
    if (_mode == _Mode.morphing) {
      final double t = (_now - _morphStart).inMicroseconds / 1e6;
      if (_morphSpring.isDone(t)) {
        _shape = _morphTo!;
        _rotation += LoadingIndicatorMotion.quarterRotation;
        _morph = null;
        _mode = _Mode.idle;
        _advance();
      }
    } else if (_mode == _Mode.looping && widget.phase != HeroPhase.connecting) {
      final LoadingIndicatorFrame f = _loopFrame();
      // Шаг цикла доиграл — форма стоит ровно на фигуре цикла.
      if (f.morphProgress == 0) {
        _shape = M3ShapeButton.loop[f.morphIndex];
        _rotation = _loopRotation(f);
        _mode = _Mode.idle;
        _advance();
      }
    }
    _render();
    if (_mode == _Mode.idle && !_colorRunning) _ticker.stop();
  }

  LoadingIndicatorFrame _loopFrame() => LoadingIndicatorMotion.frameAt(
    _now - _loopStart,
    shapeCount: M3ShapeButton.loop.length,
  );

  /// Угол цикла от точки входа: `frameAt` стартует с 90°.
  double _loopRotation(LoadingIndicatorFrame f) =>
      _rotation + f.rotationDegrees - LoadingIndicatorMotion.quarterRotation;

  void _render() {
    final (Color container, Color content) = _currentColors();
    switch (_mode) {
      case _Mode.idle:
        _frame.update(_pathOf(_shape), _rotation, container, content);
      case _Mode.morphing:
        final double t = (_now - _morphStart).inMicroseconds / 1e6;
        final double p = _morphSpring.x(t);
        _morphPath.reset();
        _morph!.toPath(progress: p, path: _morphPath);
        _frame.update(
          _morphPath,
          _rotation + p * LoadingIndicatorMotion.quarterRotation,
          container,
          content,
        );
      case _Mode.looping:
        final LoadingIndicatorFrame f = _loopFrame();
        _morphPath.reset();
        _loopMorphs[f.morphIndex].toPath(
          progress: f.morphProgress,
          path: _morphPath,
        );
        _frame.update(_morphPath, _loopRotation(f), container, content);
    }
  }

  // ── Нажатие ──────────────────────────────────────────────────────────────

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
    final double target = value ? M3ShapeButton.pressedScale : 1;
    if (_reduceMotion) {
      _press.value = target;
      return;
    }
    _press.animateWith(
      SpringSimulation(
        AppMotion.fastSpatial.description,
        _press.value,
        target,
        _press.velocity,
      ),
    );
  }

  double get _stateLayer => _pressed || _focused
      ? AppStateLayer.pressedOpacity
      : _hovered
      ? AppStateLayer.hoverOpacity
      : 0;

  IconData get _icon => switch (widget.phase) {
    HeroPhase.connecting => Symbols.close,
    HeroPhase.error => Symbols.refresh,
    HeroPhase.off || HeroPhase.on => Symbols.power_settings_new,
  };

  @override
  Widget build(BuildContext context) {
    final double size = widget.size;
    // Крупная иконка: оптический размер Material Symbols — максимум 48.
    final double iconSize = (size * 0.2).clamp(24.0, 56.0);
    return Semantics(
      button: true,
      label: heroActionLabel(widget.phase),
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowHoverHighlight: (v) => setState(() => _hovered = v),
        onShowFocusHighlight: (v) => setState(() => _focused = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => _setPressed(true),
          onTapCancel: () => _setPressed(false),
          onTapUp: (_) => _setPressed(false),
          onTap: widget.onTap,
          child: AnimatedBuilder(
            animation: _press,
            builder: (context, child) =>
                Transform.scale(scale: _press.value, child: child),
            child: SizedBox.square(
              dimension: size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Positioned.fill(
                    child: RepaintBoundary(
                      child: CustomPaint(
                        painter: _HeroPainter(
                          _frame,
                          scale: _scale,
                          stateLayer: _stateLayer,
                        ),
                      ),
                    ),
                  ),
                  ListenableBuilder(
                    listenable: _frame,
                    builder: (context, _) => AnimatedSwitcher(
                      duration: AppMotion.defaultEffects.duration,
                      switchInCurve: AppMotion.defaultEffects.curve,
                      switchOutCurve: AppMotion.defaultEffects.curve,
                      child: Icon(
                        _icon,
                        key: ValueKey(_icon),
                        size: iconSize,
                        opticalSize: 48,
                        color: _frame.content,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Текущий кадр фигуры: путь в нормализованных координатах, угол и цвета.
class _HeroFrame extends ChangeNotifier {
  Path path = Path();
  double rotation = 0;
  Color container = const Color(0x00000000);
  Color content = const Color(0x00000000);

  void update(Path p, double r, Color c, Color on) {
    path = p;
    rotation = r;
    container = c;
    content = on;
    notifyListeners();
  }
}

class _HeroPainter extends CustomPainter {
  _HeroPainter(this.frame, {required this.scale, required this.stateLayer})
    : super(repaint: frame);

  final _HeroFrame frame;
  final double scale;

  /// Прозрачность state layer цветом содержимого.
  final double stateLayer;

  @override
  void paint(Canvas canvas, Size size) {
    final double side = size.shortestSide * scale;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(frame.rotation * math.pi / 180);
    canvas.scale(side);
    canvas.translate(-0.5, -0.5);
    canvas.drawPath(frame.path, Paint()..color = frame.container);
    if (stateLayer > 0) {
      canvas.drawPath(
        frame.path,
        Paint()..color = frame.content.withValues(alpha: stateLayer),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_HeroPainter old) =>
      old.frame != frame || old.scale != scale || old.stateLayer != stateLayer;
}
