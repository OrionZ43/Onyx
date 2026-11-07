import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_new_shapes/material_new_shapes.dart';

import '../../core/theme/onyx_tokens.dart';
import '../providers/sources_provider.dart';
import '../providers/subscription_provider.dart';
import 'country_flag.dart' show PolygonClipper;
import 'add_source_sheet.dart' show looksLikeSubscriptionUrl;
import 'onyx_field.dart';
import 'onyx_toast.dart';
import 'onyx_icon.dart';
import 'preset_tile.dart';
import 'signal/dot_matrix.dart';

/// Пустое состояние «нет серверов»: вставить ссылку на подписку.
///
/// Ссылка из буфера распознаётся автоматически (https://…, vless://…).
class SubscriptionImport extends ConsumerStatefulWidget {
  const SubscriptionImport({super.key, this.compact = false});
  final bool compact;

  @override
  ConsumerState<SubscriptionImport> createState() => _SubscriptionImportState();
}

class _SubscriptionImportState extends ConsumerState<SubscriptionImport> {
  final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  // Подходит URL подписки, сами ссылки серверов (vless://, hysteria2://…)
  // и base64-блок — разбирает SubscriptionService.
  bool _looksLikeLink(String s) => s.trim().length >= 12;

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (!_looksLikeLink(text)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('В буфере нет подписки или ссылок серверов')));
      return;
    }
    _ctl.text = text;
    _submit();
  }

  // Добавляет источник (#40): URL — подписка, иначе — набор ссылок.
  Future<void> _submit() async {
    final raw = _ctl.text.trim();
    if (!_looksLikeLink(raw)) return;
    HapticFeedback.lightImpact();
    final ctl = ref.read(sourcesProvider.notifier);
    final res = looksLikeSubscriptionUrl(raw) ? await ctl.addSubscription(raw) : await ctl.addLinks(raw);
    if (!mounted) return;
    if (res == null) {
      showOnyxToast(context, 'Не удалось добавить: проверьте ссылку', glyph: OnyxGlyph.error);
    } else {
      _ctl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    final sub = ref.watch(subscriptionProvider);
    final s = Theme.of(context).colorScheme;
    final loading = sub.status == SubStatus.fetching;

    final Widget art = switch (t.kind.name) {
      'signal' => DotMatrixText('+', dot: 10, gap: 4, on: t.text, off: const Color(0xFF141414)),
      'material' => SizedBox(
          width: 150,
          height: 130,
          child: Stack(children: [
            Positioned(left: 0, top: 6, child: _shape(MaterialShapes.cookie9Sided, 96, s.primaryContainer)),
            Positioned(right: 0, bottom: 0, child: _shape(MaterialShapes.clover4Leaf, 60, s.tertiaryContainer)),
            Positioned(right: 26, top: 6, child: _shape(MaterialShapes.circle, 26, s.secondaryContainer)),
            Positioned(left: 30, top: 38, child: Icon(Icons.link_rounded, size: 34, color: s.onPrimaryContainer)),
          ]),
        ),
      _ => Container(
          width: 104,
          height: 104,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(center: Alignment(0, -1), radius: 1.1, colors: [Color(0xFF1D1D21), Color(0xFF070708)]),
            border: Border.all(color: const Color(0xFF26262A)),
          ),
          alignment: Alignment.center,
          child: OnyxIcon(OnyxGlyph.link, size: 30, color: t.textMuted),
        ),
    };

    final title = Text(
      t.isSignal ? 'Нет серверов' : 'Добавьте серверы',
      textAlign: TextAlign.center,
      style: t.isMaterial
          ? Theme.of(context).textTheme.headlineSmall
          : TextStyle(fontFamily: t.displayFont, fontSize: 26, fontWeight: t.isSignal ? FontWeight.w500 : FontWeight.w300, letterSpacing: -0.6, color: t.text),
    );
    final body = Text(
      'Вставьте ссылку на подписку или сами ссылки серверов — Onyx проверит каждый сервер, отметит AI-совместимые и выберет лучший.',
      textAlign: TextAlign.center,
      style: t.isMaterial
          ? Theme.of(context).textTheme.bodyMedium!.copyWith(color: s.onSurfaceVariant)
          : TextStyle(fontFamily: t.bodyFont, fontSize: 13.5, height: 1.45, color: t.textMuted),
    );

    final pasteLabel = t.isSignal ? 'ВСТАВИТЬ ИЗ БУФЕРА' : 'Вставить из буфера';
    final Widget pasteBtn = t.isMaterial
        ? FilledButton.icon(onPressed: loading ? null : _paste, icon: const Icon(Icons.content_paste_rounded, size: 18), label: Text(pasteLabel))
        : FilledButton.icon(
            onPressed: loading ? null : _paste,
            icon: OnyxIcon(OnyxGlyph.paste, size: 16, color: t.bg),
            label: Text(pasteLabel, style: t.isSignal ? t.caps(size: 11, color: t.bg, weight: FontWeight.w600) : null),
            style: FilledButton.styleFrom(
              backgroundColor: t.text,
              foregroundColor: t.bg,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              textStyle: TextStyle(fontFamily: t.bodyFont, fontSize: 13.5, fontWeight: FontWeight.w500),
              shape: const StadiumBorder(),
            ),
          );

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              art,
              const SizedBox(height: 24),
              title,
              const SizedBox(height: 10),
              body,
              const SizedBox(height: 22),
              TextField(
                controller: _ctl,
                onSubmitted: (_) => _submit(),
                style: TextStyle(fontFamily: t.bodyFont, fontSize: 14, color: t.text),
                decoration: onyxInputDecoration(
                  context,
                  hint: 'Ссылка на подписку или vless://…',
                  prefix: OnyxIcon(OnyxGlyph.link, size: t.isMaterial ? 22 : 16, color: t.textFaint),
                  suffix: IconButton(
                    tooltip: 'Добавить',
                    onPressed: loading ? null : _submit,
                    icon: OnyxIcon(OnyxGlyph.check, size: t.isMaterial ? 22 : 16, color: t.textMuted),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (loading)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 1.6, color: t.accent)),
                )
              else
                pasteBtn,
              const SizedBox(height: 22),
              Row(children: [
                Expanded(child: Divider(color: t.line)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(t.isSignal ? 'ИЛИ' : 'или', style: t.isSignal ? t.caps(size: 10, color: t.textFaint) : TextStyle(fontFamily: t.bodyFont, fontSize: 12, color: t.textFaint)),
                ),
                Expanded(child: Divider(color: t.line)),
              ]),
              const SizedBox(height: 14),
              const PresetTile(),
              if (sub.error != null && sub.status == SubStatus.error) ...[
                const SizedBox(height: 12),
                Text(sub.error!, textAlign: TextAlign.center, style: TextStyle(fontFamily: t.bodyFont, fontSize: 12.5, color: t.danger)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _shape(RoundedPolygon p, double size, Color c) => SizedBox.square(
        dimension: size,
        child: ClipPath(clipper: PolygonClipper(p), child: ColoredBox(color: c)),
      );
}
