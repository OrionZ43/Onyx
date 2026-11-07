import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/onyx_tokens.dart';
import '../providers/settings_provider.dart';
import '../providers/sources_provider.dart';
import 'country_flag.dart';
import 'onyx_icon.dart';
import 'onyx_toast.dart';

/// Добавить встроенную подписку [preset] как ещё один источник (#40):
/// ничего не заменяет; повторное добавление возвращает существующий.
Future<bool> loadPreset(BuildContext context, WidgetRef ref, SubscriptionPreset preset) async {
  HapticFeedback.lightImpact();
  final src = await ref.read(sourcesProvider.notifier).addPreset(preset);
  if (src == null && context.mounted) {
    showOnyxToast(context, ref.read(sourcesProvider.notifier).lastError ?? 'Не удалось загрузить «»', glyph: OnyxGlyph.error);
  }
  return src != null;
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
    final sources = ref.watch(sourcesProvider);
    // «Авто» может уже развернуться в Китай — смотрим на итоговый регион.
    final region = ref.watch(settingsProvider.select((x) => x.effectiveRegion));
    final src = sources.where((x) => x.presetId == preset.id).firstOrNull;
    final active = src != null;
    final busy = src?.status == SourceStatus.fetching;
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
