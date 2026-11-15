// Пустое состояние «нет серверов» темы Material 3 Expressive: композиция форм
// M3 (EmptyState из «Расписания МИТСО»), заполненное поле M3 для ссылки и
// кнопка «Вставить из буфера». Ссылка из буфера распознаётся сама
// (https://…, vless://…), как в SubscriptionImport.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/m3/app_spacing.dart';
import '../../core/theme/m3/app_typography.dart';
import '../providers/subscription_provider.dart';
import '../widgets/m3/empty_state.dart';
import '../widgets/m3/m3_buttons.dart';
import '../widgets/m3/m3_loading_indicator.dart';
import 'm3_parts.dart';

class M3SubscriptionImport extends ConsumerStatefulWidget {
  const M3SubscriptionImport({super.key});

  @override
  ConsumerState<M3SubscriptionImport> createState() => _M3SubscriptionImportState();
}

class _M3SubscriptionImportState extends ConsumerState<M3SubscriptionImport> {
  final TextEditingController _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  static bool _looksLikeLink(String s) {
    final String v = s.trim();
    return v.startsWith('http://') || v.startsWith('https://') || v.contains('://');
  }

  Future<void> _paste() async {
    final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
    final String text = data?.text?.trim() ?? '';
    if (!mounted) return;
    if (!_looksLikeLink(text)) {
      showM3Message(context, 'В буфере нет ссылки на подписку');
      return;
    }
    _ctl.text = text;
    _submit();
  }

  void _submit() {
    final String url = _ctl.text.trim();
    if (!_looksLikeLink(url)) {
      showM3Message(context, 'Это не похоже на ссылку подписки');
      return;
    }
    HapticFeedback.lightImpact();
    ref.read(subscriptionProvider.notifier).loadFromUrl(url);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme s = context.colors;
    final SubscriptionState sub = ref.watch(subscriptionProvider);
    final bool loading = sub.status == SubStatus.fetching;

    final Widget form = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _ctl,
          enabled: !loading,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          style: context.text.bodyLarge,
          decoration: InputDecoration(
            labelText: 'Ссылка на подписку',
            hintText: 'https://… или vless://…',
            prefixIcon: const Icon(Symbols.link),
            suffixIcon: Padding(
              padding: const EdgeInsets.only(right: AppSpacing.space50),
              child: M3IconButton(
                onPressed: loading ? null : _submit,
                icon: const Icon(Symbols.check),
                tooltip: 'Добавить',
                color: M3IconButtonColor.standard,
              ),
            ),
            errorText: sub.status == SubStatus.error ? sub.error : null,
            errorMaxLines: 3,
          ),
        ),
        const SizedBox(height: AppSpacing.space300),
        Center(
          child: loading
              ? const M3LoadingIndicator(semanticsLabel: 'Загружаем подписку')
              : M3Button(
                  onPressed: _paste,
                  icon: const Icon(Symbols.content_paste),
                  color: M3ButtonColor.filled,
                  size: M3ButtonSize.medium,
                  child: const Text('Вставить из буфера'),
                ),
        ),
      ],
    );

    return Center(
      child: SingleChildScrollView(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: EmptyState(
            title: 'Добавьте серверы',
            description: 'Вставьте ссылку на подписку — Onyx проверит каждый сервер, '
                'отметит AI-совместимые и выберет лучший.',
            illustrationSize: const Size(148, 132),
            action: DefaultTextStyle.merge(style: TextStyle(color: s.onSurface), child: form),
          ),
        ),
      ),
    );
  }
}
