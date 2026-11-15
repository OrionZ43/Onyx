// Подписки в теме Material 3 Expressive: app bar M3, сегментированный список
// сохранённых подписок, extended FAB «Добавить», диалог M3.
//
// Хранение — как у SubscriptionManagerScreen: SharedPreferences
// `saved_subscriptions`, строки «имя||url». Нажатие по подписке загружает её и
// возвращает назад; удаление можно отменить из снекбара.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_new_shapes/material_new_shapes.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/m3/app_spacing.dart';
import '../../core/theme/m3/app_typography.dart';
import '../providers/subscription_provider.dart';
import '../widgets/m3/empty_state.dart';
import '../widgets/m3/m3_buttons.dart';
import '../widgets/m3/m3_fab.dart';
import '../widgets/m3/m3_flexible_app_bar.dart';
import '../widgets/m3/m3_loading_indicator.dart';
import '../widgets/m3/m3_snackbar.dart';
import '../widgets/m3/section_header.dart';
import '../widgets/m3/segmented_list.dart';
import 'm3_parts.dart';

class M3SubscriptionsScreen extends ConsumerStatefulWidget {
  const M3SubscriptionsScreen({super.key});

  @override
  ConsumerState<M3SubscriptionsScreen> createState() => _M3SubscriptionsScreenState();
}

String _servers(int n) {
  final int d = n % 10, h = n % 100;
  if (d == 1 && h != 11) return 'сервер';
  if (d >= 2 && d <= 4 && (h < 12 || h > 14)) return 'сервера';
  return 'серверов';
}

class _Entry {
  const _Entry(this.name, this.url);
  final String name, url;

  String get host => Uri.tryParse(url)?.host.isNotEmpty == true ? Uri.parse(url).host : url;
}

class _M3SubscriptionsScreenState extends ConsumerState<M3SubscriptionsScreen> {
  static const String _key = 'saved_subscriptions';

  List<_Entry> _entries = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final List<String> saved = prefs.getStringList(_key) ?? const [];
    if (!mounted) return;
    setState(() {
      _entries = [
        for (final String s in saved)
          if (s.split('||') case [final String name, final String url, ...]) _Entry(name, url) else _Entry('Подписка', s),
      ];
      _loading = false;
    });
  }

  Future<void> _save() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_key, [for (final _Entry e in _entries) '${e.name}||${e.url}']);
  }

  void _apply(_Entry e) {
    HapticFeedback.lightImpact();
    ref.read(subscriptionProvider.notifier).loadFromUrl(e.url);
    Navigator.of(context).maybePop();
  }

  Future<void> _edit({int? index}) async {
    final _Entry? existing = index == null ? null : _entries[index];
    final _Entry? result = await showDialog<_Entry>(
      context: context,
      builder: (_) => _SubscriptionDialog(existing: existing),
    );
    if (result == null || !mounted) return;
    setState(() {
      final List<_Entry> next = [..._entries];
      if (index == null) {
        next.add(result);
      } else {
        next[index] = result;
      }
      _entries = next;
    });
    await _save();
  }

  Future<void> _delete(BuildContext context, int index) async {
    final _Entry removed = _entries[index];
    setState(() => _entries = [..._entries]..removeAt(index));
    await _save();
    if (!context.mounted) return;
    showM3Message(context, 'Подписка «${removed.name}» удалена', actionLabel: 'Вернуть', onAction: () async {
      if (!mounted) return;
      setState(() => _entries = [..._entries]..insert(index.clamp(0, _entries.length), removed));
      await _save();
    });
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme s = context.colors;
    final SubscriptionState sub = ref.watch(subscriptionProvider);
    final double margin = AppSpacing.screenMargin(context);
    final bool busy = sub.status == SubStatus.fetching || sub.status == SubStatus.probing || sub.status == SubStatus.deepProbing;

    Widget leading(bool active) => M3ShapeIcon(
          icon: Symbols.rss_feed,
          shape: MaterialShapes.cookie4Sided,
          color: active ? s.primaryContainer : s.secondaryContainer,
          onColor: active ? s.onPrimaryContainer : s.onSecondaryContainer,
        );

    final bool currentSaved = _entries.any((e) => e.url == sub.url);
    final List<Widget> children = [
      if (sub.url.isNotEmpty && !currentSaved) ...[
        const SectionHeader('Сейчас'),
        SegmentedList(children: [
          M3ListItem(
            leading: leading(true),
            headline: Text(Uri.tryParse(sub.url)?.host ?? sub.url, maxLines: 1, overflow: TextOverflow.ellipsis),
            supporting: Text('${sub.nodes.length} серв. · ${sub.aiReachableCount} с AI'),
            trailing: busy
                ? const M3LoadingIndicator(semanticsLabel: 'Обновляем')
                : M3IconButton(
                    onPressed: () => ref.read(subscriptionProvider.notifier).loadFromUrl(sub.url),
                    icon: const Icon(Symbols.refresh),
                    tooltip: 'Обновить',
                    color: M3IconButtonColor.standard,
                  ),
          ),
        ]),
      ],
      const SectionHeader('Сохранённые'),
      if (_loading)
        const Padding(padding: EdgeInsets.all(AppSpacing.space400), child: Center(child: M3LoadingIndicator()))
      else if (_entries.isEmpty)
        EmptyState(
          title: 'Сохранённых подписок нет',
          description: 'Добавьте ссылку — потом её можно будет включить одним нажатием.',
          action: M3Button(
            onPressed: () => _edit(),
            icon: const Icon(Symbols.add),
            color: M3ButtonColor.tonal,
            child: const Text('Добавить подписку'),
          ),
        )
      else
        SegmentedList(children: [
          for (var i = 0; i < _entries.length; i++)
            Builder(builder: (context) {
              final _Entry e = _entries[i];
              final bool active = e.url == sub.url;
              return M3ListItem(
                leading: leading(active),
                headline: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                supporting: Text(
                  active ? 'Включена · ${sub.nodes.length} ${_servers(sub.nodes.length)}' : e.host,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  M3IconButton(
                    onPressed: () => _edit(index: i),
                    icon: const Icon(Symbols.edit),
                    tooltip: 'Изменить',
                    color: M3IconButtonColor.standard,
                  ),
                  M3IconButton(
                    onPressed: () => _delete(context, i),
                    icon: const Icon(Symbols.delete),
                    tooltip: 'Удалить',
                    color: M3IconButtonColor.standard,
                  ),
                ]),
                selected: active,
                onTap: () => _apply(e),
                semanticsLabel: '${e.name}, ${active ? 'включена' : e.host}',
              );
            }),
        ]),
      // Место под FAB, чтобы он не закрывал последнюю строку.
      const SizedBox(height: 96),
    ];

    return Scaffold(
      appBar: M3SmallAppBar(
        title: 'Подписки',
        leading: M3IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const Icon(Symbols.arrow_back),
          tooltip: 'Назад',
          color: M3IconButtonColor.standard,
        ),
      ),
      floatingActionButton: M3ExtendedFab(
        onPressed: () => _edit(),
        icon: const Icon(Symbols.add),
        label: 'Добавить',
      ),
      body: M3SnackbarHost(
        bottomPadding: 80,
        child: M3AppBarSettle(
          child: CustomScrollView(slivers: [
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: margin),
              sliver: SliverList.list(children: children),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Диалог M3 (basic dialog): заголовок headlineSmall, два заполненных поля,
/// действия — текстовые кнопки (https://m3.material.io/components/dialogs).
class _SubscriptionDialog extends StatefulWidget {
  const _SubscriptionDialog({this.existing});
  final _Entry? existing;

  @override
  State<_SubscriptionDialog> createState() => _SubscriptionDialogState();
}

class _SubscriptionDialogState extends State<_SubscriptionDialog> {
  late final TextEditingController _name = TextEditingController(text: widget.existing?.name ?? '');
  late final TextEditingController _url = TextEditingController(text: widget.existing?.url ?? '');

  @override
  void dispose() {
    _name.dispose();
    _url.dispose();
    super.dispose();
  }

  void _done() {
    final String url = _url.text.trim();
    if (url.isEmpty) return;
    final String name = _name.text.trim();
    Navigator.of(context).pop(_Entry(name.isEmpty ? 'Подписка' : name, url));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'Новая подписка' : 'Подписка'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(
          controller: _name,
          autofocus: widget.existing == null,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(labelText: 'Название', hintText: 'Мой VPN'),
        ),
        const SizedBox(height: AppSpacing.space200),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          onSubmitted: (_) => _done(),
          decoration: const InputDecoration(labelText: 'Ссылка', hintText: 'https://…'),
        ),
      ]),
      actions: [
        M3Button(onPressed: () => Navigator.of(context).pop(), color: M3ButtonColor.text, child: const Text('Отмена')),
        M3Button(onPressed: _done, color: M3ButtonColor.text, child: const Text('Сохранить')),
      ],
    );
  }
}
