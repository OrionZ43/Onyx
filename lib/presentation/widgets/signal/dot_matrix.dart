import 'package:flutter/material.dart';

/// Точечная матрица 5×7 для темы Signal: таймер, процент, `ERR`.
///
/// Шрифт нарисован здесь же (только цифры, `: - + E R`), без сторонних
/// лицензий. Непогашенные точки рисуются тускло — «табло».
class DotMatrixText extends StatelessWidget {
  const DotMatrixText(
    this.text, {
    super.key,
    this.dot = 6,
    this.gap = 2.4,
    this.on = Colors.white,
    this.off = const Color(0xFF141414),
  });

  final String text;
  final double dot;
  final double gap;
  final Color on;
  final Color off;

  static const Map<String, List<String>> glyphs = {
    '0': ['01110', '10001', '10011', '10101', '11001', '10001', '01110'],
    '1': ['00100', '01100', '00100', '00100', '00100', '00100', '01110'],
    '2': ['01110', '10001', '00001', '00010', '00100', '01000', '11111'],
    '3': ['11111', '00010', '00100', '00010', '00001', '10001', '01110'],
    '4': ['00010', '00110', '01010', '10010', '11111', '00010', '00010'],
    '5': ['11111', '10000', '11110', '00001', '00001', '10001', '01110'],
    '6': ['00110', '01000', '10000', '11110', '10001', '10001', '01110'],
    '7': ['11111', '00001', '00010', '00100', '01000', '01000', '01000'],
    '8': ['01110', '10001', '10001', '01110', '10001', '10001', '01110'],
    '9': ['01110', '10001', '10001', '01111', '00001', '00010', '01100'],
    'E': ['11111', '10000', '10000', '11110', '10000', '10000', '11111'],
    'R': ['11110', '10001', '10001', '11110', '10100', '10010', '10001'],
    '+': ['00000', '00100', '00100', '11111', '00100', '00100', '00000'],
    ':': ['0', '0', '1', '0', '1', '0', '0'],
    '-': ['000', '000', '000', '111', '000', '000', '000'],
    ' ': ['0', '0', '0', '0', '0', '0', '0'],
  };

  static int columnsOf(String text) {
    var cols = 0;
    for (final ch in text.split('')) {
      cols += (glyphs[ch] ?? glyphs[' ']!)[0].length + 1;
    }
    return cols == 0 ? 0 : cols - 1;
  }

  @override
  Widget build(BuildContext context) {
    final cols = columnsOf(text);
    final w = cols * (dot + gap) - gap, h = 7 * (dot + gap) - gap;
    return Semantics(
      label: text,
      child: CustomPaint(
        size: Size(w < 0 ? 0 : w, h),
        painter: _DotTextPainter(text, dot, gap, on, off),
      ),
    );
  }
}

class _DotTextPainter extends CustomPainter {
  _DotTextPainter(this.text, this.dot, this.gap, this.on, this.off);
  final String text;
  final double dot, gap;
  final Color on, off;

  @override
  void paint(Canvas canvas, Size size) {
    final pOn = Paint()..color = on;
    final pOff = Paint()..color = off;
    var x = 0;
    for (final ch in text.split('')) {
      final g = DotMatrixText.glyphs[ch] ?? DotMatrixText.glyphs[' ']!;
      final w = g[0].length;
      for (var y = 0; y < 7; y++) {
        for (var i = 0; i < w; i++) {
          final c = Offset((x + i) * (dot + gap) + dot / 2, y * (dot + gap) + dot / 2);
          canvas.drawCircle(c, dot / 2, g[y][i] == '1' ? pOn : pOff);
        }
      }
      x += w + 1;
    }
  }

  @override
  bool shouldRepaint(_DotTextPainter o) =>
      o.text != text || o.on != on || o.off != off || o.dot != dot;
}

/// Ряд точек-индикаторов (пинг: 4 точки = отлично).
class DotRow extends StatelessWidget {
  const DotRow({super.key, required this.lit, this.count = 4, this.dot = 4, this.gap = 3, required this.on, required this.off});
  final int lit, count;
  final double dot, gap;
  final Color on, off;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) SizedBox(width: gap),
            Container(
              width: dot,
              height: dot,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i < lit ? on : off,
              ),
            ),
          ],
        ],
      );
}
