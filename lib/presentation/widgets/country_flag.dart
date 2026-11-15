import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_new_shapes/material_new_shapes.dart';

import '../../core/theme/onyx_tokens.dart';
import '../../core/theme/theme_kind.dart';
import '../m3/m3_parts.dart' show M3Flag;
import '../util/country.dart';

/// Флаг страны в стиле темы, без emoji:
/// * Onyx — круглый флаг (circle-flags, MIT) с хайрлайном и бликом;
/// * Signal — точечная матрица: флаг (flag-icons, MIT) растеризуется в сетку,
///   яркость квантуется в 4 уровня белого;
/// * Material — [M3Flag]: квадратный флаг в форме MaterialShapes `Cookie4Sided`.
///
/// Неизвестная страна — нейтральный кружок/сетка/форма с глобусом.
class CountryFlag extends StatelessWidget {
  const CountryFlag({super.key, required this.code, this.size = 32, this.selected = false});

  /// ISO alpha-2 в нижнем регистре или ''.
  final String code;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    final known = code.isNotEmpty && hasFlagAsset(code);
    final c = known ? code : '';
    return switch (t.kind) {
      AppThemeKind.signal => _DotFlag(code: c, size: size),
      AppThemeKind.material => _ShapeFlag(code: c, size: size),
      AppThemeKind.onyx => _RoundFlag(code: c, size: size),
    };
  }
}

// ── Onyx ────────────────────────────────────────────────────────────────────
class _RoundFlag extends StatelessWidget {
  const _RoundFlag({required this.code, required this.size});
  final String code;
  final double size;

  // Насыщенность −12 %: флаги не спорят с тёплым акцентом.
  static const _desaturate = ColorFilter.matrix([
    0.9083, 0.0786, 0.0131, 0, 0, //
    0.0255, 0.9614, 0.0131, 0, 0, //
    0.0255, 0.0786, 0.8959, 0, 0, //
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: t.surfaceHigh,
          boxShadow: const [BoxShadow(color: Color(0x80000000), blurRadius: 6, offset: Offset(0, 2))],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (code.isNotEmpty)
              ClipOval(
                child: ColorFiltered(
                  colorFilter: _desaturate,
                  child: SvgPicture.asset('assets/flags/circle/$code.svg', fit: BoxFit.cover),
                ),
              )
            else
              Icon(Icons.public_rounded, size: size * 0.55, color: t.textFaint),
            // Блик сверху и тень снизу — «стекло» на флаге.
            const DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x2EFFFFFF), Color(0x00FFFFFF), Color(0x40000000)],
                  stops: [0, 0.45, 1],
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0x24FFFFFF)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Signal ──────────────────────────────────────────────────────────────────
class _DotFlag extends StatefulWidget {
  const _DotFlag({required this.code, required this.size});
  final String code;
  final double size;

  static const int cols = 8, rows = 6;

  /// Кэш уровней яркости (0..3) по коду страны.
  static final Map<String, Uint8List> _cache = {};

  static Future<Uint8List> levelsOf(String code) async {
    final hit = _cache[code];
    if (hit != null) return hit;
    final info = await vg.loadPicture(SvgAssetLoader('assets/flags/square/$code.svg'), null);
    // Квадратный флаг → центральная полоса 4:3, ужатая до cols×rows.
    final rec = ui.PictureRecorder();
    final c = Canvas(rec);
    final sx = cols / info.size.width, sy = rows / (info.size.height * 0.75);
    c.scale(sx, sy);
    c.translate(0, -info.size.height * 0.125);
    c.drawPicture(info.picture);
    final img = await rec.endRecording().toImage(cols, rows);
    final data = (await img.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    info.picture.dispose();
    img.dispose();
    final out = Uint8List(cols * rows);
    for (var i = 0; i < cols * rows; i++) {
      final r = data.getUint8(i * 4), g = data.getUint8(i * 4 + 1), b = data.getUint8(i * 4 + 2);
      final l = (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255;
      out[i] = l > 0.8 ? 3 : l > 0.5 ? 2 : l > 0.25 ? 1 : 0;
    }
    return _cache[code] = out;
  }

  @override
  State<_DotFlag> createState() => _DotFlagState();
}

class _DotFlagState extends State<_DotFlag> {
  Uint8List? _levels;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_DotFlag old) {
    super.didUpdateWidget(old);
    if (old.code != widget.code) _load();
  }

  void _load() {
    final code = widget.code;
    _levels = _DotFlag._cache[code];
    if (_levels != null || code.isEmpty) return;
    _DotFlag.levelsOf(code).then((v) {
      if (mounted && widget.code == code) setState(() => _levels = v);
    }).catchError((Object _) {});
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.size * 0.75;
    return SizedBox(
      width: widget.size,
      height: h,
      child: CustomPaint(painter: _DotFlagPainter(_levels)),
    );
  }
}

class _DotFlagPainter extends CustomPainter {
  _DotFlagPainter(this.levels);
  final Uint8List? levels;

  static const _palette = [Color(0xFF262626), Color(0xFF5E5E5E), Color(0xFFA8A8A8), Color(0xFFFFFFFF)];

  @override
  void paint(Canvas canvas, Size size) {
    const cols = _DotFlag.cols, rows = _DotFlag.rows;
    final step = size.width / cols;
    final r = step * 0.33;
    final p = Paint();
    for (var y = 0; y < rows; y++) {
      for (var x = 0; x < cols; x++) {
        final lv = levels?[y * cols + x] ?? 0;
        p.color = levels == null ? const Color(0xFF262626) : _palette[lv];
        canvas.drawCircle(Offset(step * (x + 0.5), step * (y + 0.5)), r, p);
      }
    }
  }

  @override
  bool shouldRepaint(_DotFlagPainter old) => old.levels != levels;
}

// ── Material ────────────────────────────────────────────────────────────────
/// Тот же флаг, что на экранах M3 ([M3Flag]): квадратный флаг целиком в одной
/// форме `Cookie4Sided`, без увеличения. Общие экраны (лист добавления,
/// мини-панель, выбор страны) выглядят как экраны M3. Раньше форма
/// выбиралась по коду страны, а флаг увеличивался в 1,3 раза — у Китая
/// главная звезда уходила за край (#105).
class _ShapeFlag extends StatelessWidget {
  const _ShapeFlag({required this.code, required this.size});
  final String code;
  final double size;

  @override
  Widget build(BuildContext context) => M3Flag(code: code, size: size);
}

/// Обрезка по нормализованной фигуре MaterialShapes (0..1 → размер виджета).
class PolygonClipper extends CustomClipper<Path> {
  const PolygonClipper(this.polygon);
  final RoundedPolygon polygon;

  @override
  Path getClip(Size size) => polygon.normalized().toPath().transform(
        Matrix4.diagonal3Values(size.width, size.height, 1).storage,
      );

  @override
  bool shouldReclip(PolygonClipper old) => old.polygon != polygon;
}

/// Заранее растеризует точечные флаги Signal (для golden-тестов и прогрева).
Future<void> precacheDotFlags(Iterable<String> codes) async {
  for (final c in codes) {
    if (c.isNotEmpty && hasFlagAsset(c)) await _DotFlag.levelsOf(c);
  }
}
