import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/onyx_tokens.dart';
import '../../domain/subscription_presets.dart';
import '../providers/sources_provider.dart';
import 'onyx_field.dart';
import 'onyx_icon.dart';
import 'onyx_toast.dart';
import 'preset_tile.dart';

enum AddSourceMode { subscription, links }

/// Шторка «Добавить»: подписка по URL или ссылки серверов вставкой. Источник
/// добавляется к остальным (ничего не заменяет).
Future<void> showAddSourceSheet(BuildContext context, {AddSourceMode mode = AddSourceMode.subscription, String? initial}) {
  final t = OnyxTokens.of(context);
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: t.isMaterial ? null : t.surface,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(t.radiusSheet)),
      side: t.isMaterial ? BorderSide.none : BorderSide(color: t.lineStrong),
    ),
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: AddSourcePanel(mode: mode, initial: initial),
    ),
  );
}

/// Сколько ссылок серверов в тексте (vless://, hysteria2://, …) — для подсказки.
int countLinks(String raw) => RegExp(r'^[a-z0-9+.-]+://', multiLine: true, caseSensitive: false)
    .allMatches(raw.trim())
    .where((m) => !m.group(0)!.startsWith('http'))
    .length;

/// Похоже на URL подписки (одна строка http(s)://…).
bool looksLikeSubscriptionUrl(String raw) {
  final v = raw.trim();
  return !v.contains('\n') && (v.startsWith('https://') || v.startsWith('http://'));
}

class AddSourcePanel extends ConsumerStatefulWidget {
  const AddSourcePanel({super.key, required this.mode, this.initial, this.inline = false});
  final AddSourceMode mode;
  final String? initial;

  /// true — без шапки шторки (встроено в экран).
  final bool inline;

  @override
  ConsumerState<AddSourcePanel> createState() => _AddSourcePanelState();
}

class _AddSourcePanelState extends ConsumerState<AddSourcePanel> {
  late AddSourceMode _mode = widget.mode;
  late final _text = TextEditingController(text: widget.initial ?? '');
  final _name = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final d = await Clipboard.getData(Clipboard.kTextPlain);
    final v = d?.text?.trim() ?? '';
    if (!mounted) return;
    if (v.isEmpty) {
      showOnyxToast(context, 'В буфере пусто', glyph: OnyxGlyph.error);
      return;
    }
    setState(() {
      _text.text = v;
      _mode = looksLikeSubscriptionUrl(v) ? AddSourceMode.subscription : AddSourceMode.links;
    });
  }

  Future<void> _submit() async {
    final raw = _text.text.trim();
    if (raw.isEmpty || _busy) return;
    setState(() => _busy = true);
    final ctl = ref.read(sourcesProvider.notifier);
    final name = _name.text.trim().isEmpty ? null : _name.text.trim();
    final res = _mode == AddSourceMode.subscription && looksLikeSubscriptionUrl(raw)
        ? await ctl.addSubscription(raw, name: name)
        : await ctl.addLinks(raw, name: name);
    if (!mounted) return;
    setState(() => _busy = false);
    if (res == null) {
      showOnyxToast(context, 'Не удалось добавить: проверьте ссылку', glyph: OnyxGlyph.error);
      return;
    }
    HapticFeedback.lightImpact();
    showOnyxToast(context, 'Добавлено: «${res.name}» · ${res.nodeCount} серв.', glyph: OnyxGlyph.check);
    if (!widget.inline) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    final s = Theme.of(context).colorScheme;
    final links = _mode == AddSourceMode.links;
    final n = countLinks(_text.text);
    final hint = links
        ? (n > 0 ? 'Распознано: $n ${n == 1 ? 'ссылка' : (n < 5 ? 'ссылки' : 'ссылок')}' : 'vless://, hysteria2://, tuic://, ss://, trojan:// — по одной на строку, или base64')
        : 'https://… — ссылка на подписку';

    final seg = t.isMaterial
        ? SegmentedButton<AddSourceMode>(
            segments: const [
              ButtonSegment(value: AddSourceMode.subscription, label: Text('Подписка')),
              ButtonSegment(value: AddSourceMode.links, label: Text('Ссылки')),
            ],
            selected: {_mode},
            onSelectionChanged: (v) => setState(() => _mode = v.first),
          )
        : _Segments(value: _mode, onChanged: (m) => setState(() => _mode = m));

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(t.isMaterial ? 16 : 20, widget.inline ? 0 : 8, t.isMaterial ? 16 : 20, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!widget.inline) ...[
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: t.isMaterial ? s.onSurfaceVariant.withValues(alpha: 0.4) : t.lineStrong, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Text(
              'Добавить',
              style: t.isMaterial
                  ? Theme.of(context).textTheme.titleLarge
                  : TextStyle(fontFamily: t.displayFont, fontSize: 26, fontWeight: t.isSignal ? FontWeight.w500 : FontWeight.w400, letterSpacing: -0.5, color: t.text),
            ),
            const SizedBox(height: 14),
          ],
          seg,
          const SizedBox(height: 12),
          TextField(
            controller: _text,
            onChanged: (_) => setState(() {}),
            minLines: links ? 4 : 1,
            maxLines: links ? 8 : 1,
            style: TextStyle(fontFamily: links ? 'JetBrainsMono' : t.bodyFont, fontSize: links ? 12.5 : 14, color: t.text),
            decoration: onyxInputDecoration(
              context,
              hint: links ? 'Вставьте ссылки серверов' : 'https://…',
              prefix: links ? null : OnyxIcon(OnyxGlyph.link, size: t.isMaterial ? 22 : 16, color: t.textFaint),
            ),
          ),
          const SizedBox(height: 8),
          Text(hint, style: TextStyle(fontFamily: t.bodyFont, fontSize: 12, color: n > 0 && links ? t.accent : t.textMuted)),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            style: TextStyle(fontFamily: t.bodyFont, fontSize: 14, color: t.text),
            decoration: onyxInputDecoration(
              context,
              hint: 'Название (необязательно)',
              prefix: OnyxIcon(OnyxGlyph.sliders, size: t.isMaterial ? 22 : 16, color: t.textFaint),
            ),
          ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _paste,
                icon: OnyxIcon(OnyxGlyph.paste, size: 16, color: t.text),
                label: Text(t.isSignal ? 'ИЗ БУФЕРА' : 'Из буфера'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: t.text,
                  minimumSize: const Size(0, 46),
                  shape: const StadiumBorder(),
                  side: t.isMaterial ? null : BorderSide(color: t.line),
                  textStyle: t.isSignal ? t.caps(size: 11, weight: FontWeight.w600) : TextStyle(fontFamily: t.bodyFont, fontSize: 13.5, fontWeight: FontWeight.w500),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: _busy || _text.text.trim().isEmpty ? null : _submit,
                style: t.isMaterial
                    ? null
                    : FilledButton.styleFrom(
                        backgroundColor: t.text,
                        foregroundColor: t.bg,
                        minimumSize: const Size(0, 46),
                        shape: const StadiumBorder(),
                        textStyle: t.isSignal ? t.caps(size: 11, weight: FontWeight.w600) : TextStyle(fontFamily: t.bodyFont, fontSize: 13.5, fontWeight: FontWeight.w500),
                      ),
                child: _busy
                    ? SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 1.6, color: t.bg))
                    : Text(t.isSignal ? 'ДОБАВИТЬ' : 'Добавить источник'),
              ),
            ),
          ]),
          const SizedBox(height: 22),
          Text(t.isSignal ? 'ВСТРОЕННЫЕ' : 'Встроенные', style: t.caps(size: 10.5, color: t.textFaint)),
          const SizedBox(height: 10),
          for (final p in SubscriptionPresets.all) ...[PresetTile(preset: p), const SizedBox(height: 10)],
        ],
      ),
    );
  }
}

class _Segments extends StatelessWidget {
  const _Segments({required this.value, required this.onChanged});
  final AddSourceMode value;
  final ValueChanged<AddSourceMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: t.isSignal ? t.surfaceHigh : t.bg,
        borderRadius: BorderRadius.circular(t.isSignal ? 18 : 12),
        border: t.isOnyx ? Border.all(color: t.line) : null,
      ),
      child: Row(children: [
        for (final (m, label) in [(AddSourceMode.subscription, 'Подписка'), (AddSourceMode.links, 'Ссылки')])
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(m),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(vertical: 9),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: m == value ? (t.isSignal ? t.text : t.surfaceTop) : Colors.transparent,
                  borderRadius: BorderRadius.circular(t.isSignal ? 15 : 9),
                  border: m == value && t.isOnyx ? Border.all(color: t.lineStrong) : null,
                ),
                child: Text(
                  t.isSignal ? label.toUpperCase() : label,
                  style: t.isSignal
                      ? t.caps(size: 10.5, color: m == value ? t.bg : t.textMuted)
                      : TextStyle(fontFamily: t.bodyFont, fontSize: 13, fontWeight: FontWeight.w500, color: m == value ? t.text : t.textMuted),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
