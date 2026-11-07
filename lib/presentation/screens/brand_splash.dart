import 'package:flutter/material.dart';

import '../../core/brand/onyx_fox.dart';
import '../../core/brand/onyx_fox_volume.dart';
import '../../core/theme/theme_kind.dart';

/// Сплэш на время инициализации (Windows и Android после нативного сплэша):
/// объёмная лиса V1 «Кабошон», в теме Signal — точечная с красным носом.
/// Без MaterialApp: показывается до того, как поднимется тема приложения.
class BrandSplash extends StatelessWidget {
  const BrandSplash({super.key, required this.kind});
  final AppThemeKind kind;

  @override
  Widget build(BuildContext context) {
    final signal = kind == AppThemeKind.signal;
    final bg = switch (kind) {
      AppThemeKind.signal => const Color(0xFF000000),
      AppThemeKind.material => const Color(0xFF141218),
      AppThemeKind.onyx => const Color(0xFF050506),
    };
    return Directionality(
      textDirection: TextDirection.ltr,
      child: ColoredBox(
        color: bg,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox.square(
              dimension: 132,
              child: CustomPaint(
                painter: signal ? OnyxFoxPainter(style: FoxStyle.dots) : FoxVolumePainter(),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              'ONYX',
              style: TextStyle(
                fontFamily: signal ? 'JetBrainsMono' : 'InterTight',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                letterSpacing: 15 * (signal ? .32 : .42),
                color: const Color(0xFFF3F1EC),
                decoration: TextDecoration.none,
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Корень: сплэш, пока идёт [init], затем приложение.
class OnyxBoot extends StatelessWidget {
  const OnyxBoot({super.key, required this.init, required this.kind, required this.app});
  final Future<void> init;
  final AppThemeKind kind;
  final Widget app;

  @override
  Widget build(BuildContext context) => FutureBuilder<void>(
        future: init,
        builder: (context, snap) => AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          child: snap.connectionState == ConnectionState.done ? app : BrandSplash(kind: kind),
        ),
      );
}
