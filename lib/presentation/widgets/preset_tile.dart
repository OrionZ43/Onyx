import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/onyx_tokens.dart';
import '../../domain/subscription_presets.dart';
import '../providers/settings_provider.dart';
import '../providers/subscription_provider.dart';
import 'country_flag.dart';
import 'onyx_icon.dart';
import 'onyx_toast.dart';

/// Загрузить встроенную подписку [preset].
///
/// Подписка в Onyx одна активная — если уже загружена другая, спрашиваем.
/// Для пресета Китая предлагаем включить регион «Китай» (сами не переключаем).
Future<bool> loadPreset(BuildContext context, WidgetRef ref, SubscriptionPreset preset) async {
  final sub = ref.read(subscriptionProvider);
  if (sub.url.isNotEmpty && sub.url != preset.url) {
    final current = SubscriptionPresets.byUrl(sub.url)?.title ?? 'текущую подписку';
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(preset.title),
        content: Text('Подписка в Onyx одна. «${preset.title}» заменит $current.\n\n${preset.subtitle}.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Заменить')),
        ],
      ),
    );
    if (ok != true) return false;
  }
  HapticFeedback.lightImpact();
  await ref.read(subscriptionProvider.notifier).loadFromUrl(preset.url);
  return true;
}

/// Плитка встроенной подписки: флаг, название, честная подпись, действие.
class PresetTile extends ConsumerWidget {
  const PresetTile({super.key, this.preset = SubscriptionPresets.chinaFree, this.dense = false});
  final SubscriptionPreset preset;
  final bool dense;

  bool get _isChina => preset.id == SubscriptionPresets.chinaFree.id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = OnyxTokens.of(context);
    final s = Theme.of(context).colorScheme;
    final sub = ref.watch(subscriptionProvider);
    final region = ref.watch(settingsProvider.select((x) => x.routingRegion));
    final active = sub.url == preset.url;
    final busy = active && sub.status == SubStatus.fetching;
    final needRegion = _isChina && region != RoutingRegion.china;

    final title = Text(
      preset.title,
      style: t.isMaterial
          ? Theme.of(context).textTheme.bodyLarge
          : TextStyle(fontFamily: t.bodyFont, fontSize: 14.5, fontWeight: FontWeight.w500, color: t.text),
    );
    final subtitle = Text(
      t.isSignal ? preset.subtitle.toUpperCase() : preset.subtitle,
      style: t.isMaterial
          ? Theme.of(context).textTheme.bodyMedium!.copyWith(color: s.onSurfaceVariant)
          : t.isSignal
              ? t.caps(size: 9.5, color: t.textFaint)
              : TextStyle(fontFamily: t.bodyFont, fontSize: 12, color: t.textMuted),
    );
    final Widget trailing = busy
        ? SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 1.6, color: t.accent))
        : active
            ? OnyxIcon(OnyxGlyph.check, size: t.isMaterial ? 24 : 16, color: t.accent)
            : OnyxIcon(OnyxGlyph.plus, size: t.isMaterial ? 24 : 16, color: t.textMuted);

    final radius = BorderRadius.circular(t.isMaterial ? 16 : (t.isSignal ? 20 : 18));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: t.isMaterial ? s.surfaceContainer : (t.isSignal ? t.surface : t.bg),
          borderRadius: radius,
          child: InkWell(
            borderRadius: radius,
            onTap: active ? null : () => loadPreset(context, ref, preset),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: dense ? 10 : 13),
              decoration: t.isOnyx ? BoxDecoration(borderRadius: radius, border: Border.all(color: t.line)) : null,
              child: Row(children: [
                CountryFlag(code: _isChina ? 'cn' : '', size: t.isMaterial ? 40 : (t.isSignal ? 26 : 30)),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [title, const SizedBox(height: 2), subtitle])),
                const SizedBox(width: 10),
                trailing,
              ]),
            ),
          ),
        ),
        if (active && needRegion) ...[
          const SizedBox(height: 8),
          _RegionHint(onEnable: () {
            ref.read(settingsProvider.notifier).setRoutingRegion(RoutingRegion.china);
            showOnyxToast(context, 'Регион «Китай» включён — применится при подключении', glyph: OnyxGlyph.globe);
          }),
        ],
      ],
    );
  }
}

class _RegionHint extends StatelessWidget {
  const _RegionHint({required this.onEnable});
  final VoidCallback onEnable;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    return Row(children: [
      const SizedBox(width: 4),
      OnyxIcon(OnyxGlyph.info, size: 14, color: t.textMuted),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          'Для Китая включите регион маршрутизации «Китай»: китайские сайты пойдут напрямую.',
          style: TextStyle(fontFamily: t.bodyFont, fontSize: 12, color: t.textMuted),
        ),
      ),
      TextButton(onPressed: onEnable, child: const Text('Включить')),
    ]);
  }
}
