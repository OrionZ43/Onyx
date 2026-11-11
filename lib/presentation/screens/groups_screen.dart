// «Группы» (#40): пользовательские группы серверов — создать, переименовать,
// удалить, менять порядок; состав — целые источники и отдельные ноды.
// Встроенные автогруппы («Все», «Избранное», «Голос», «AI») и группы-источники
// показаны справочно. Данные — groupsProvider / autoGroupProvider («Оникс»).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/onyx_tokens.dart';
import '../../domain/entities/node.dart';
import '../providers/country_provider.dart';
import '../providers/groups_provider.dart';
import '../providers/sources_provider.dart';
import '../providers/subscription_provider.dart';
import '../util/country.dart';
import '../widgets/country_flag.dart';
import '../widgets/onyx_icon.dart';
import '../widgets/onyx_switch.dart';

/// Встроенные автогруппы (спец-id домена).
const Map<String?, String> kAutoGroups = {
  null: 'Все',
  'auto:fav': 'Избранное',
  'auto:udp': 'Голос',
  'auto:ai': 'AI',
};

String groupLabel(String? id, List<NodeGroup> all) =>
    kAutoGroups[id] ?? all.where((g) => g.id == id).firstOrNull?.name ?? 'Все';

Future<String?> askGroupName(BuildContext context, {String initial = '', String title = 'Новая группа'}) {
  final ctl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: ctl,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'Например, «Игры»'),
        onSubmitted: (v) => Navigator.pop(c, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text('Отмена')),
        FilledButton(onPressed: () => Navigator.pop(c, ctl.text), child: const Text('Сохранить')),
      ],
    ),
  );
}

class GroupsScreen extends ConsumerWidget {
  const GroupsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = OnyxTokens.of(context);
    final groups = ref.watch(groupsProvider);
    final auto = ref.watch(autoGroupProvider);
    final pad = t.isMaterial ? 16.0 : 20.0;

    Future<void> create() async {
      final name = await askGroupName(context);
      if (name != null && name.trim().isNotEmpty) {
        final g = await ref.read(groupsProvider.notifier).create(name.trim());
        if (context.mounted) {
          Navigator.of(context).push(MaterialPageRoute(builder: (_) => GroupEditScreen(groupId: g.id)));
        }
      }
    }

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        leading: IconButton(
          tooltip: 'Назад',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: OnyxIcon(OnyxGlyph.back, size: t.isMaterial ? 24 : 18, color: t.isMaterial ? null : t.text),
        ),
        title: Text('Группы',
            style: t.isMaterial ? null : TextStyle(fontFamily: t.displayFont, fontSize: 20, fontWeight: t.isSignal ? FontWeight.w500 : FontWeight.w400, color: t.text)),
        actions: [
          IconButton(
            tooltip: 'Новая группа',
            onPressed: create,
            icon: OnyxIcon(OnyxGlyph.plus, size: t.isMaterial ? 24 : 18, color: t.isMaterial ? null : t.textMuted),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: CustomScrollView(slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, 8, pad, 8),
              sliver: SliverToBoxAdapter(child: _Caption('Автовыбор берёт лучший сервер из')),
            ),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: pad),
              sliver: SliverToBoxAdapter(
                child: Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final e in kAutoGroups.entries) _Pill(label: e.value, selected: auto == e.key, onTap: () => ref.read(autoGroupProvider.notifier).setAutoGroup(e.key)),
                  for (final g in groups) _Pill(label: g.name, selected: auto == g.id, onTap: () => ref.read(autoGroupProvider.notifier).setAutoGroup(g.id)),
                ]),
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(pad, 24, pad, 8),
              sliver: SliverToBoxAdapter(child: _Caption('Мои группы · ${groups.length}')),
            ),
            if (groups.isEmpty)
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: pad),
                sliver: SliverToBoxAdapter(
                  child: _EmptyGroups(onCreate: create),
                ),
              )
            else
              SliverPadding(
                padding: EdgeInsets.symmetric(horizontal: pad),
                sliver: SliverReorderableList(
                  itemCount: groups.length,
                  // onReorderItem даёт уже скорректированный индекс; домен ждёт семантику ReorderableListView.
                  onReorderItem: (a, b) => ref.read(groupsProvider.notifier).reorder(a, b > a ? b + 1 : b),
                  itemBuilder: (c, i) {
                    final g = groups[i];
                    final count = ref.watch(groupNodesProvider(g.id)).length;
                    return Padding(
                      key: ValueKey(g.id),
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _Card(
                        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => GroupEditScreen(groupId: g.id))),
                        child: Row(children: [
                          ReorderableDragStartListener(
                            index: i,
                            child: Padding(
                              padding: const EdgeInsets.only(right: 12),
                              child: Icon(Icons.drag_indicator_rounded, size: 18, color: t.textFaint),
                            ),
                          ),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              _Title(g.name),
                              const SizedBox(height: 2),
                              _Sub(_composition(g, count)),
                            ]),
                          ),
                          if (auto == g.id) ...[OnyxIcon(OnyxGlyph.zap, size: 14, color: t.accent), const SizedBox(width: 10)],
                          OnyxIcon(OnyxGlyph.chevronRight, size: t.isMaterial ? 24 : 16, color: t.textFaint),
                        ]),
                      ),
                    );
                  },
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ]),
        ),
      ),
    );
  }

  static String _composition(NodeGroup g, int count) {
    final parts = <String>[
      if (g.sourceIds.isNotEmpty) '${g.sourceIds.length} источн.',
      if (g.nodeIds.isNotEmpty) '${g.nodeIds.length} серв. вручную',
    ];
    return '$count серверов${parts.isEmpty ? ' · пусто' : ' · ${parts.join(' + ')}'}';
  }
}

// ── Редактор группы ─────────────────────────────────────────────────────────

class GroupEditScreen extends ConsumerWidget {
  const GroupEditScreen({super.key, required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = OnyxTokens.of(context);
    final g = ref.watch(groupsProvider).where((x) => x.id == groupId).firstOrNull;
    if (g == null) return Scaffold(backgroundColor: t.bg, appBar: AppBar(backgroundColor: t.bg));
    final ctl = ref.read(groupsProvider.notifier);
    final sources = ref.watch(sourcesProvider);
    final allNodes = ref.watch(subscriptionProvider.select((s) => s.nodes));
    final cr = ref.watch(countryResolverProvider);
    final byId = {for (final n in allNodes) n.id: n};
    final auto = ref.watch(autoGroupProvider) == g.id;
    final pad = t.isMaterial ? 16.0 : 20.0;

    return Scaffold(
      backgroundColor: t.bg,
      appBar: AppBar(
        backgroundColor: t.bg,
        leading: IconButton(
          tooltip: 'Назад',
          onPressed: () => Navigator.of(context).maybePop(),
          icon: OnyxIcon(OnyxGlyph.back, size: t.isMaterial ? 24 : 18, color: t.isMaterial ? null : t.text),
        ),
        title: Text(g.name,
            style: t.isMaterial ? null : TextStyle(fontFamily: t.displayFont, fontSize: 20, fontWeight: t.isSignal ? FontWeight.w500 : FontWeight.w400, color: t.text)),
        actions: [
          IconButton(
            tooltip: 'Переименовать',
            onPressed: () async {
              final name = await askGroupName(context, initial: g.name, title: 'Название группы');
              if (name != null && name.trim().isNotEmpty) ctl.rename(g.id, name.trim());
            },
            icon: OnyxIcon(OnyxGlyph.sliders, size: t.isMaterial ? 24 : 18, color: t.isMaterial ? null : t.textMuted),
          ),
          IconButton(
            tooltip: 'Удалить группу',
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: Text('Удалить «${g.name}»?'),
                  content: const Text('Серверы и источники останутся, удалится только группа.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Отмена')),
                    FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Удалить')),
                  ],
                ),
              );
              if (ok == true) {
                ctl.delete(g.id);
                if (context.mounted) Navigator.of(context).maybePop();
              }
            },
            icon: OnyxIcon(OnyxGlyph.trash, size: t.isMaterial ? 24 : 18, color: t.danger),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: ListView(padding: EdgeInsets.fromLTRB(pad, 8, pad, 32), children: [
            _Card(
              child: Row(children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const _Title('Автовыбор из этой группы'),
                    const SizedBox(height: 2),
                    const _Sub('Кнопка подключения берёт лучший сервер группы'),
                  ]),
                ),
                OnyxSwitch(
                  value: auto,
                  onChanged: (v) => ref.read(autoGroupProvider.notifier).setAutoGroup(v ? g.id : null),
                ),
              ]),
            ),
            const SizedBox(height: 22),
            _Caption('Состав'),
            const SizedBox(height: 8),
            if (g.sourceIds.isEmpty && g.nodeIds.isEmpty) const _Sub('Пусто. Добавьте целые источники или отдельные серверы.'),
            for (final sid in g.sourceIds)
              _MemberRow(
                lead: _KindChip('Источник'),
                title: sources.where((s) => s.id == sid).firstOrNull?.name ?? 'Удалённый источник',
                onRemove: () => ctl.removeSource(g.id, sid),
              ),
            for (final nid in g.nodeIds)
              _MemberRow(
                lead: CountryFlag(code: byId[nid] == null ? '' : cr.of(byId[nid]!).code, size: 26),
                title: byId[nid] == null ? 'Сервер недоступен' : displayNodeName(byId[nid]!.name),
                onRemove: () => ctl.removeNode(g.id, nid),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => showGroupMembersPicker(context, groupId: g.id),
                icon: OnyxIcon(OnyxGlyph.plus, size: 16, color: t.accent),
                label: Text('Добавить серверы или источник', style: TextStyle(fontFamily: t.bodyFont, color: t.accent)),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Выбор состава группы: источники целиком и отдельные серверы (отметками).
Future<void> showGroupMembersPicker(BuildContext context, {required String groupId}) {
  final t = OnyxTokens.of(context);
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: t.isMaterial ? null : t.surface,
    builder: (_) => SizedBox(height: MediaQuery.sizeOf(context).height * 0.8, child: _MembersPicker(groupId: groupId)),
  );
}

class _MembersPicker extends ConsumerWidget {
  const _MembersPicker({required this.groupId});
  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = OnyxTokens.of(context);
    final g = ref.watch(groupsProvider).where((x) => x.id == groupId).firstOrNull;
    if (g == null) return const SizedBox();
    final ctl = ref.read(groupsProvider.notifier);
    final cr = ref.watch(countryResolverProvider);
    final sources = ref.watch(sourcesProvider);
    final nodes = [...ref.watch(subscriptionProvider.select((s) => s.nodes))]
      ..sort((a, b) => cr.of(a).name.compareTo(cr.of(b).name));
    Widget check(bool v) => Icon(v ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded, size: 22, color: v ? t.accent : t.textFaint);
    return ListView(padding: const EdgeInsets.fromLTRB(8, 0, 8, 24), children: [
      Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 8), child: _Caption('Источники целиком')),
      for (final s in sources)
        ListTile(
          leading: _KindChip('Источник'),
          title: Text(s.name, style: TextStyle(fontFamily: t.bodyFont, color: t.text)),
          subtitle: Text('${s.nodeCount} серверов, включая будущие', style: TextStyle(fontFamily: t.bodyFont, fontSize: 12, color: t.textMuted)),
          trailing: check(g.sourceIds.contains(s.id)),
          onTap: () {
            HapticFeedback.selectionClick();
            g.sourceIds.contains(s.id) ? ctl.removeSource(g.id, s.id) : ctl.addSource(g.id, s.id);
          },
        ),
      Padding(padding: const EdgeInsets.fromLTRB(12, 16, 12, 8), child: _Caption('Отдельные серверы')),
      for (final Node n in nodes)
        ListTile(
          leading: CountryFlag(code: cr.of(n).code, size: 26),
          title: Text(displayNodeName(n.name), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: t.bodyFont, color: t.text)),
          trailing: check(g.nodeIds.contains(n.id)),
          onTap: () {
            HapticFeedback.selectionClick();
            g.nodeIds.contains(n.id) ? ctl.removeNode(g.id, n.id) : ctl.addNodes(g.id, [n.id]);
          },
        ),
    ]);
  }
}

// ── Мелкие части ────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  const _Card({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    final r = BorderRadius.circular(t.isMaterial ? 16 : 18);
    return Material(
      color: t.isMaterial ? Theme.of(context).colorScheme.surfaceContainer : t.surface,
      borderRadius: r,
      child: InkWell(
        borderRadius: r,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: t.isOnyx ? BoxDecoration(borderRadius: r, border: Border.all(color: t.line)) : null,
          child: child,
        ),
      ),
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.lead, required this.title, required this.onRemove});
  final Widget lead;
  final String title;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        lead,
        const SizedBox(width: 12),
        Expanded(child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: t.bodyFont, fontSize: 14, color: t.text))),
        IconButton(tooltip: 'Убрать', onPressed: onRemove, icon: OnyxIcon(OnyxGlyph.close, size: 14, color: t.textFaint)),
      ]),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    if (t.isMaterial) return ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap());
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? t.text : (t.isSignal ? t.surfaceHigh : Colors.transparent),
          borderRadius: BorderRadius.circular(16),
          border: t.isOnyx ? Border.all(color: selected ? t.text : t.line) : null,
        ),
        child: Text(
          t.isSignal ? label.toUpperCase() : label,
          style: t.isSignal
              ? t.caps(size: 10.5, color: selected ? t.bg : t.textMuted)
              : TextStyle(fontFamily: t.bodyFont, fontSize: 12.5, fontWeight: FontWeight.w500, color: selected ? t.bg : t.textMuted),
        ),
      ),
    );
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: t.lineStrong), borderRadius: BorderRadius.circular(6)),
      child: Text(label.toUpperCase(), style: t.caps(size: 8.5, color: t.textMuted)),
    );
  }
}

class _EmptyGroups extends StatelessWidget {
  const _EmptyGroups({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    return _Card(
      onTap: onCreate,
      child: Row(children: [
        OnyxIcon(OnyxGlyph.plus, size: 18, color: t.accent),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: const [
            _Title('Создать группу'),
            SizedBox(height: 2),
            _Sub('Например, «Игры» или «Работа»: свои серверы и источники в одном месте'),
          ]),
        ),
      ]),
    );
  }
}

class _Caption extends StatelessWidget {
  const _Caption(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    return Text(
      t.isMaterial ? text : text.toUpperCase(),
      style: t.isMaterial
          ? Theme.of(context).textTheme.titleSmall!.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)
          : t.caps(size: 10.5, color: t.textFaint),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    return Text(text,
        style: t.isMaterial
            ? Theme.of(context).textTheme.bodyLarge
            : TextStyle(fontFamily: t.bodyFont, fontSize: 15, fontWeight: FontWeight.w500, color: t.text));
  }
}

class _Sub extends StatelessWidget {
  const _Sub(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    return Text(text,
        style: t.isMaterial
            ? Theme.of(context).textTheme.bodyMedium!.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)
            : TextStyle(fontFamily: t.bodyFont, fontSize: 12.5, color: t.textMuted));
  }
}
