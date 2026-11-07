import 'package:flutter/material.dart';
import 'package:material_new_shapes/material_new_shapes.dart';

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
    return Text(
      'ONYX',
      style: TextStyle(
        fontFamily: t.isSignal ? t.monoFont : t.displayFont,
        fontSize: size,
        fontWeight: FontWeight.w600,
        letterSpacing: size * (t.isSignal ? 0.32 : 0.42),
        color: t.text,
      ),
    );
  }
}
