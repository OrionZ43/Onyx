// lib/presentation/screens/subscription_manager_screen.dart
//
// «Подписки и серверы» (#40): несколько источников — URL-подписки и наборы
// вставленных ссылок. Источники добавляются, а не заменяют друг друга;
// включаются/выключаются, обновляются, переименовываются, удаляются и
// сортируются перетаскиванием. Встроенные пресеты — внизу, добавляются
// одним касанием. Данные — sourcesProvider («Оникс», домен).
//
// Имя класса прежнее (SubscriptionManagerScreen), чтобы не менять навигацию.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/onyx_tokens.dart';
import '../../domain/entities/subscription_source.dart';
import '../../domain/subscription_presets.dart';
import '../providers/sources_provider.dart';
import '../providers/subscription_provider.dart';
import '../widgets/add_source_sheet.dart';
import '../widgets/country_flag.dart';
import '../widgets/onyx_icon.dart';
import '../widgets/onyx_switch.dart';
import '../widgets/onyx_toast.dart';
import '../widgets/preset_tile.dart';
import 'groups_screen.dart';

class SubscriptionManagerScreen extends ConsumerWidget {
  const SubscriptionManagerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = OnyxTokens.of(context);
    final sources = ref.watch(sourcesProvider);
    final nodes = ref.watch(subscriptionProvider.select((s) => s.nodes));
    final total = nodes.length;

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        leading: IconButton(
          tooltip: 'Назад',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: OnyxIcon(OnyxGlyph.back, size: t.isMaterial ? 24 : 18, color: t.isMaterial ? null : t.text),
        ),
        title: Text(
          'Подписки и серверы',
          style: t.isMaterial
              ? null
              : TextStyle(fontFamily: t.displayFont, fontSize: 20, fontWeight: t.isSignal ? FontWeight.w500 : FontWeight.w400, color: t.text),
        ),
        actions: [
          IconButton(
            tooltip: 'Обновить все',
            onPressed: () {
              HapticFeedback.lightImpact();
              ref.read(sourcesProvider.notifier).refreshAll();
            },
            icon: OnyxIcon(OnyxGlyph.refresh, size: t.isMaterial ? 24 : 18, color: t.isMaterial ? null : t.textMuted),
          ),
          PopupMenuButton<String>(
            tooltip: 'Ещё',
            icon: OnyxIcon(OnyxGlyph.more, size: t.isMaterial ? 24 : 18, color: t.isMaterial ? null : t.textMuted),
            color: t.isMaterial ? null : t.surfaceHigh,
            onSelected: (v) => _menu(context, ref, v),
            itemBuilder: (_) => [
              _item(t, 'groups', 'Группы'),
              _item(t, 'export', 'Скопировать настройки'),
              _item(t, 'import', 'Вставить настройки'),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.fromLTRB(t.isMaterial ? 16 : 20, 6, t.isMaterial ? 16 : 20, 0),
                sliver: SliverToBoxAdapter(child: _AddBar()),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(t.isMaterial ? 16 : 20, 20, t.isMaterial ? 16 : 20, 8),
                sliver: SliverToBoxAdapter(
                  child: Row(children: [
                    Expanded(child: _caption(context, 'Источники · ${sources.length}')),
                    _caption(context, '$total серверов'),
                  ]),
                ),
              ),
              if (sources.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
                    child: Text(
                      'Источников пока нет. Добавьте подписку по ссылке или вставьте ссылки серверов.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: t.bodyFont, fontSize: 13.5, color: t.textMuted),
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.symmetric(horizontal: t.isMaterial ? 16 : 20),
                  sliver: SliverReorderableList(
                    itemCount: sources.length,
                    // onReorderItem даёт уже скорректированный индекс; домен ждёт семантику ReorderableListView.
                    onReorderItem: (a, b) => ref.read(sourcesProvider.notifier).reorder(a, b > a ? b + 1 : b),
                    itemBuilder: (context, i) => ReorderableDelayedDragStartListener(
                      key: ValueKey(sources[i].id),
                      index: i,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _SourceTile(source: sources[i]),
                      ),
                    ),
                  ),
                ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(t.isMaterial ? 16 : 20, 20, t.isMaterial ? 16 : 20, 8),
                sliver: SliverToBoxAdapter(child: _caption(context, 'Встроенные')),
              ),
              SliverPadding(
                padding: EdgeInsets.fromLTRB(t.isMaterial ? 16 : 20, 0, t.isMaterial ? 16 : 20, 32),
                sliver: SliverList.separated(
                  itemCount: SubscriptionPresets.all.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => PresetTile(preset: SubscriptionPresets.all[i]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _item(OnyxTokens t, String v, String label) => PopupMenuItem(
        value: v,
        child: Text(label, style: TextStyle(fontFamily: t.bodyFont, color: t.text)),
      );

  Widget _caption(BuildContext context, String s) {
    final t = OnyxTokens.of(context);
    return Text(
      t.isMaterial ? s : s.toUpperCase(),
      style: t.isMaterial
          ? Theme.of(context).textTheme.titleSmall!.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)
          : t.caps(size: 10.5, color: t.textFaint),
    );
  }

  Future<void> _menu(BuildContext context, WidgetRef ref, String v) async {
    switch (v) {
      case 'groups':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GroupsScreen()));
      case 'export':
        await Clipboard.setData(ClipboardData(text: ref.read(sourcesProvider.notifier).exportJson()));
        if (context.mounted) showOnyxToast(context, 'Источники, группы и избранное скопированы', glyph: OnyxGlyph.copy);
      case 'import':
        final data = await Clipboard.getData(Clipboard.kTextPlain);
        final text = data?.text ?? '';
        if (text.trim().isEmpty) {
          if (context.mounted) showOnyxToast(context, 'В буфере пусто', glyph: OnyxGlyph.error);
          return;
        }
        final r = await ref.read(sourcesProvider.notifier).importJson(text);
        if (!context.mounted) return;
        showOnyxToast(
          context,
          r.error ?? 'Добавлено: источников ${r.sources}, групп ${r.groups}',
          glyph: r.error == null ? OnyxGlyph.check : OnyxGlyph.error,
        );
    }
  }
}

// ── Кнопки добавления ───────────────────────────────────────────────────────

class _AddBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    Widget btn(String label, OnyxGlyph g, AddSourceMode mode, {bool primary = false}) {
      final fg = primary ? (t.isMaterial ? Theme.of(context).colorScheme.onPrimary : t.bg) : t.text;
      final child = Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [
        OnyxIcon(g, size: t.isMaterial ? 20 : 16, color: fg),
        const SizedBox(width: 8),
        Flexible(child: Text(t.isSignal ? label.toUpperCase() : label, overflow: TextOverflow.ellipsis)),
      ]);
      void open() => showAddSourceSheet(context, mode: mode);
      if (t.isMaterial) {
        return primary ? FilledButton(onPressed: open, child: child) : FilledButton.tonal(onPressed: open, child: child);
      }
      return primary
          ? FilledButton(
              onPressed: open,
              style: FilledButton.styleFrom(
                backgroundColor: t.text,
                foregroundColor: t.bg,
                minimumSize: const Size(0, 44),
                shape: const StadiumBorder(),
                textStyle: t.isSignal ? t.caps(size: 11, weight: FontWeight.w600) : TextStyle(fontFamily: t.bodyFont, fontSize: 13.5, fontWeight: FontWeight.w500),
              ),
              child: child,
            )
          : OutlinedButton(
              onPressed: open,
              style: OutlinedButton.styleFrom(
                foregroundColor: t.text,
                backgroundColor: t.isSignal ? t.surfaceHigh : null,
                side: t.isOnyx ? BorderSide(color: t.line) : BorderSide.none,
                minimumSize: const Size(0, 44),
                shape: const StadiumBorder(),
                textStyle: t.isSignal ? t.caps(size: 11, weight: FontWeight.w600) : TextStyle(fontFamily: t.bodyFont, fontSize: 13.5, fontWeight: FontWeight.w500),
              ),
              child: child,
            );
    }

    return Row(children: [
      Expanded(child: btn('Подписка', OnyxGlyph.plus, AddSourceMode.subscription, primary: true)),
      const SizedBox(width: 8),
      Expanded(child: btn('Ссылки', OnyxGlyph.link, AddSourceMode.links)),
    ]);
  }
}

// ── Плитка источника ────────────────────────────────────────────────────────

class _SourceTile extends ConsumerWidget {
  const _SourceTile({required this.source});
  final SubscriptionSource source;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = OnyxTokens.of(context);
    final s = Theme.of(context).colorScheme;
    final ctl = ref.read(sourcesProvider.notifier);
    final nodes = ref.watch(subscriptionProvider.select((x) => x.nodes));
    final mine = nodes.where((n) => n.sourceIds.contains(source.id));
    final alive = mine.where((n) => n.isAlive).length;
    final busy = source.status == SourceStatus.fetching;
    final err = source.status == SourceStatus.error;

    final kindLabel = source.kind == SourceKind.links ? 'Ссылки' : 'Подписка';
    final meta = source.isPreset
        ? (SubscriptionPresets.all.where((p) => p.id == source.presetId).firstOrNull?.subtitle ?? 'встроенная')
        : source.kind == SourceKind.links
            ? '${source.nodeCount} ${_plural(source.nodeCount, 'ссылка', 'ссылки', 'ссылок')}'
            : (Uri.tryParse(source.url ?? '')?.host ?? source.url ?? '');
    final status = err
        ? 'Ошибка${source.error == null ? '' : ': ${source.error}'}'
        : busy
            ? 'Обновляется…'
            : '$alive из ${source.nodeCount} работают${source.lastUpdatedAt == null ? '' : ' · ${_ago(DateTime.now().difference(source.lastUpdatedAt!))}'}';

    final title = Row(children: [
      Flexible(
        child: Text(
          source.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: t.isMaterial
              ? Theme.of(context).textTheme.bodyLarge
              : TextStyle(fontFamily: t.bodyFont, fontSize: 15, fontWeight: FontWeight.w500, color: t.text),
        ),
      ),
      const SizedBox(width: 8),
      _KindBadge(label: kindLabel),
    ]);

    final Widget lead = source.presetId == SubscriptionPresets.chinaFree.id
        ? CountryFlag(code: 'cn', size: t.isMaterial ? 40 : 34)
        : Container(
            width: t.isMaterial ? 40 : 34,
            height: t.isMaterial ? 40 : 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: t.isMaterial ? s.secondaryContainer : t.surfaceHigh,
              border: t.isOnyx ? Border.all(color: t.lineStrong) : null,
            ),
            alignment: Alignment.center,
            child: OnyxIcon(source.kind == SourceKind.links ? OnyxGlyph.link : OnyxGlyph.globe,
                size: 16, color: t.isMaterial ? s.onSecondaryContainer : t.textMuted),
          );

    final radius = BorderRadius.circular(t.isMaterial ? 16 : 18);
    return Opacity(
      opacity: source.enabled ? 1 : 0.55,
      child: Material(
        color: t.isMaterial ? s.surfaceContainer : t.surface,
        borderRadius: radius,
        child: InkWell(
          borderRadius: radius,
          onTap: () => _actions(context, ref),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 12),
            decoration: t.isOnyx ? BoxDecoration(borderRadius: radius, border: Border.all(color: t.line)) : null,
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              lead,
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  title,
                  const SizedBox(height: 2),
                  Text(meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.isMaterial
                          ? Theme.of(context).textTheme.bodyMedium!.copyWith(color: s.onSurfaceVariant)
                          : TextStyle(fontFamily: t.bodyFont, fontSize: 12, color: t.textMuted)),
                  if (busy) ...[
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: LinearProgressIndicator(minHeight: 2, color: t.accent, backgroundColor: t.line),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(shape: BoxShape.circle, color: err ? t.danger : (busy ? t.accentMuted : t.accent)),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        t.isMaterial ? status : status.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: t.isMaterial
                            ? Theme.of(context).textTheme.labelMedium!.copyWith(color: err ? s.error : s.onSurfaceVariant)
                            : t.caps(size: 10, color: err ? t.danger : t.textFaint),
                      ),
                    ),
                  ]),
                ]),
              ),
              const SizedBox(width: 8),
              Column(children: [
                OnyxSwitch(value: source.enabled, onChanged: (v) => ctl.setEnabled(source.id, v)),
                const SizedBox(height: 10),
                IconButton(
                  tooltip: 'Действия',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _actions(context, ref),
                  icon: OnyxIcon(OnyxGlyph.more, size: 16, color: t.textFaint),
                ),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Future<void> _actions(BuildContext context, WidgetRef ref) async {
    final t = OnyxTokens.of(context);
    final ctl = ref.read(sourcesProvider.notifier);
    final v = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: t.isMaterial ? null : t.surface,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final (key, label, glyph) in [
            ('refresh', 'Обновить', OnyxGlyph.refresh),
            ('rename', 'Переименовать', OnyxGlyph.sliders),
            ('auto', 'Автообновление: ${source.autoUpdateHours == 0 ? 'выкл' : 'каждые ${source.autoUpdateHours} ч'}', OnyxGlyph.clock),
            if (source.url != null) ('copy', 'Скопировать ссылку', OnyxGlyph.copy),
            ('delete', 'Удалить', OnyxGlyph.trash),
          ])
            ListTile(
              leading: OnyxIcon(glyph, size: 20, color: key == 'delete' ? t.danger : t.textMuted),
              title: Text(label, style: TextStyle(fontFamily: t.bodyFont, color: key == 'delete' ? t.danger : t.text)),
              onTap: () => Navigator.pop(c, key),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (v == null || !context.mounted) return;
    switch (v) {
      case 'refresh':
        ctl.refresh(source.id);
      case 'rename':
        final name = await _askName(context, source.name);
        if (name != null && name.trim().isNotEmpty) ctl.rename(source.id, name.trim());
      case 'auto':
        final next = switch (source.autoUpdateHours) { 0 => 6, 6 => 24, _ => 0 };
        ctl.setAutoUpdate(source.id, next);
        showOnyxToast(context, next == 0 ? 'Автообновление выключено' : 'Обновлять каждые $next ч', glyph: OnyxGlyph.clock);
      case 'copy':
        await Clipboard.setData(ClipboardData(text: source.url!));
        if (context.mounted) showOnyxToast(context, 'Ссылка скопирована', glyph: OnyxGlyph.copy);
      case 'delete':
        final ok = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text('Удалить «${source.name}»?'),
            content: Text('Серверы этого источника пропадут из списка и групп.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
              FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Удалить')),
            ],
          ),
        );
        if (ok == true) ctl.remove(source.id);
    }
  }
}

Future<String?> _askName(BuildContext context, String current) {
  final ctl = TextEditingController(text: current);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text('Название'),
      content: TextField(controller: ctl, autofocus: true, onSubmitted: (v) => Navigator.pop(c, v)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('Сохранить')),
      ],
    ),
  );
}

class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    if (t.isMaterial) {
      return Text(label, style: Theme.of(context).textTheme.labelSmall!.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant));
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(border: Border.all(color: t.lineStrong), borderRadius: BorderRadius.circular(t.isSignal ? 4 : 6)),
      child: Text(label.toUpperCase(), style: t.caps(size: 8.5, color: t.textMuted)),
    );
  }
}

String _plural(int n, String one, String few, String many) {
  final m10 = n % 10, m100 = n % 100;
  if (m10 == 1 && m100 != 11) return one;
  if (m10 >= 2 && m10 <= 4 && (m100 < 12 || m100 > 14)) return few;
  return many;
}

String _ago(Duration d) {
  if (d.inMinutes < 1) return 'только что';
  if (d.inHours < 1) return '${d.inMinutes} мин назад';
  if (d.inDays < 1) return '${d.inHours} ч назад';
  return '${d.inDays} дн назад';
}
