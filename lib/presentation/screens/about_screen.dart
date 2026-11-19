import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/brand/onyx_fox.dart';
import '../../core/brand/onyx_fox_volume.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/onyx_tokens.dart';
import '../../infrastructure/update_service.dart';
import '../widgets/onyx_icon.dart';

/// «О программе»: знак-лиса в стиле темы, название, версия, ссылки.
class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    final s = Theme.of(context).colorScheme;
    final version = UpdateService.currentVersion;
    final Widget mark = switch (t.kind.name) {
      'signal' => const OnyxFox(size: 132, style: FoxStyle.dots),
      'material' => OnyxFox(size: 132, style: FoxStyle.monoline, ink: s.primary, accent: s.tertiary),
      _ => SizedBox.square(dimension: 170, child: CustomPaint(painter: FoxVolumePainter(accent: t.accent))),
    };
    final name = t.isMaterial
        ? Text('Onyx', style: Theme.of(context).textTheme.displaySmall)
        : Text(
            'ONYX',
            style: TextStyle(
              fontFamily: t.isSignal ? t.monoFont : t.displayFont,
              fontSize: 26,
              fontWeight: FontWeight.w600,
              letterSpacing: 26 * (t.isSignal ? .32 : .42),
              color: t.text,
            ),
          );
    final caption = TextStyle(fontFamily: t.bodyFont, fontSize: 13, color: t.textMuted, height: 1.5);

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        leading: IconButton(
          tooltip: 'Назад',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: OnyxIcon(OnyxGlyph.back, size: t.isMaterial ? 24 : 18, color: t.isMaterial ? null : t.text),
        ),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Знак на «камне» — как линза главной кнопки.
              Container(
                width: 220,
                height: 220,
                decoration: t.isOnyx
                    ? BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const RadialGradient(center: Alignment(0, -1), radius: 1.1, colors: [Color(0xFF17171A), Color(0xFF050506)]),
                        border: Border.all(color: t.line),
                      )
                    : null,
                alignment: Alignment.center,
                child: mark,
              ),
              const SizedBox(height: 28),
              name,
              const SizedBox(height: 8),
              Text(
                t.isSignal ? 'ВЕРСИЯ $version' : 'Версия $version',
                style: t.isSignal ? t.caps(size: 11) : caption.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
              ),
              const SizedBox(height: 20),
              Text(
                'Клиент для приватности на ядре sing-box:\nVLESS · REALITY · Hysteria2 · TUIC.\nZ43 Studios · by Orion_Z43',
                textAlign: TextAlign.center,
                style: caption,
              ),
              const SizedBox(height: 24),
              Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                OutlinedButton(
                  onPressed: () => launchUrl(Uri.parse('https://t.me/Orion_Z43'), mode: LaunchMode.externalApplication),
                  child: const Text('Telegram автора'),
                ),
                OutlinedButton(
                  onPressed: () => launchUrl(Uri.parse('https://github.com/OrionZ43/Onyx'), mode: LaunchMode.externalApplication),
                  child: const Text('GitHub'),
                ),
                OutlinedButton(
                  onPressed: () => showLicensePage(context: context, applicationName: 'Onyx', applicationVersion: version),
                  child: const Text('Лицензии'),
                ),
              ]),
              if (t.isSignal) ...[
                const SizedBox(height: 24),
                Container(width: 8, height: 8, decoration: const BoxDecoration(shape: BoxShape.circle, color: AppTheme.signalRec)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
