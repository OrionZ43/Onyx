import 'package:flutter/material.dart';
import 'package:material_new_shapes/material_new_shapes.dart';

import '../../core/brand/onyx_fox.dart';
import '../../core/theme/onyx_tokens.dart';
import 'country_flag.dart' show PolygonClipper;

/// Логотип-надпись в стиле темы:
/// Onyx — «ONYX» Inter Tight с широким трекингом; Signal — JetBrains Mono;
/// Material — «печенька» primary + «Onyx» titleMedium.
class OnyxWordmark extends StatelessWidget {
  const OnyxWordmark({super.key, this.size = 13});
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    if (t.isMaterial) {
      final s = Theme.of(context).colorScheme;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: size * 1.45,
            child: ClipPath(
              clipper: PolygonClipper(MaterialShapes.cookie9Sided),
              child: ColoredBox(color: s.primary),
            ),
          ),
          SizedBox(width: size * 0.7),
          Text('Onyx', style: TextStyle(fontFamily: 'Roboto', fontSize: size * 1.1, fontWeight: FontWeight.w500, color: s.onSurface)),
        ],
      );
    }
    final text = Text(
      'ONYX',
      style: TextStyle(
        fontFamily: t.isSignal ? t.monoFont : t.displayFont,
        fontSize: size,
        fontWeight: FontWeight.w600,
        letterSpacing: size * (t.isSignal ? 0.32 : 0.42),
        color: t.text,
      ),
    );
    // Знак-лиса V1 рядом с надписью: Onyx — силуэт шампань, Signal — белый с красным носом.
    final m = size * 1.45;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox.square(
        dimension: m,
        child: CustomPaint(
          painter: OnyxFoxPainter(style: FoxStyle.silhouette, ink: t.isSignal ? t.text : t.accent),
          foregroundPainter: t.isSignal ? _RedNose() : null,
        ),
      ),
      SizedBox(width: size * 0.75),
      text,
    ]);
  }
}

class _RedNose extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    canvas.drawCircle(Offset(50 * s, 86 * s), 7 * s, Paint()..color = const Color(0xFFFF3B2F));
  }

  @override
  bool shouldRepaint(_RedNose oldDelegate) => false;
}
