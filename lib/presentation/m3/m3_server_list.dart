// Список серверов темы Material 3 Expressive.
//
// * [showM3ServerSheet] — модальный нижний лист M3 (телефон).
// * [M3ServerList] — то же содержимое панелью (окно Windows шире 840dp).
//
// Поведение — как у NodeListPanel: выбор сервера пишется в nodeSelectionProvider,
// при подключении — переподключение к выбранному; «Автовыбор» сбрасывает
// ручной выбор (→ bestNode); группировка по стране, порядок — живые и по пингу.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_new_shapes/material_new_shapes.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/m3/app_spacing.dart';
import '../../core/theme/m3/app_typography.dart';
import '../../domain/entities/node.dart';
import '../../domain/entities/vpn_state.dart';
import '../providers/node_provider.dart';
import '../providers/subscription_provider.dart';
import '../providers/vpn_provider.dart';
import '../util/country.dart';
import '../widgets/m3/m3_bottom_sheet.dart';
import '../widgets/m3/m3_buttons.dart';
import '../widgets/m3/m3_filter_chip.dart';
import '../widgets/m3/m3_loading_indicator.dart';
import '../widgets/m3/m3_search.dart';
import '../widgets/m3/m3_switch.dart';
import '../widgets/m3/section_header.dart';
import '../widgets/m3/segmented_list.dart';
import 'm3_parts.dart';
import 'm3_subscription_import.dart';
import '../screens/subscription_manager_screen.dart';

/// Модальный нижний лист со списком серверов: ручка перетаскивания,
/// раскрытие до полного экрана (`M3BottomSheet`, порт Compose `ModalBottomSheet`).
Future<void> showM3ServerSheet(BuildContext context) => showM3ModalBottomSheet<void>(
      context: context,
      builder: (context, scrollController) => M3ServerList(inSheet: true, scrollController: scrollController),
    );

enum M3ServerFilter { all, ai, verified }

class M3ServerList extends ConsumerStatefulWidget {
  const M3ServerList({super.key, this.inSheet = false, this.scrollController});

  /// В листе выбор закрывает лист.
  final bool inSheet;
  final ScrollController? scrollController;

  @override
  ConsumerState<M3ServerList> createState() => _M3ServerListState();
}

class _M3ServerListState extends ConsumerState<M3ServerList> {
  final TextEditingController _query = TextEditingController();
  M3ServerFilter _filter = M3ServerFilter.all;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _select(Node node) {
    HapticFeedback.selectionClick();
    ref.read(nodeSelectionProvider.notifier).select(node);
    final VpnState vpn = ref.read(vpnControllerProvider);
    if (vpn is VpnConnected && vpn.node.id != node.id) {
      // Смена сервера на ходу: переподключаемся к выбранному.
      final ctl = ref.read(vpnControllerProvider.notifier);
      ctl.disconnect().then((_) => ctl.connect(node));
    }
    if (widget.inSheet && mounted) Navigator.of(context).maybePop();
  }

  void _setAuto(bool auto) {
    final SubscriptionState sub = ref.read(subscriptionProvider);
    if (auto) {
      ref.read(nodeSelectionProvider.notifier).clear();
    } else if (sub.bestNode != null) {
      ref.read(nodeSelectionProvider.notifier).select(sub.bestNode!);
    }
  }

  void _refresh() {
    final String url = ref.read(subscriptionProvider).url;
    if (url.isNotEmpty) ref.read(subscriptionProvider.notifier).loadFromUrl(url);
  }

  static List<Node> sorted(Iterable<Node> nodes) => nodes.toList()
    ..sort((a, b) {
      if (a.isAlive != b.isAlive) return a.isAlive ? -1 : 1;
      return (a.latencyMs ?? 99999).compareTo(b.latencyMs ?? 99999);
    });

  static bool matches(Node n, String q) {
    if (q.isEmpty) return true;
    final Country c = countryOfName(n.name);
    return n.name.toLowerCase().contains(q) || c.name.toLowerCase().contains(q);
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme s = context.colors;
    final SubscriptionState sub = ref.watch(subscriptionProvider);
    final Node? picked = ref.watch(nodeSelectionProvider);
    final VpnState vpn = ref.watch(vpnControllerProvider);
    final Node? current = vpn is VpnConnected ? vpn.node : (picked ?? sub.bestNode);
    const double margin = AppSpacing.space200;

    if (sub.nodes.isEmpty && sub.status != SubStatus.fetching) {
      return const M3SubscriptionImport();
    }

    final bool busy = sub.status == SubStatus.fetching || sub.status == SubStatus.probing || sub.status == SubStatus.deepProbing;
    final int aiCount = sub.nodes.where((n) => n.aiReachable).length;
    final int verified = sub.nodes.where((n) => n.isTrulyWorking).length;

    final List<Node> nodes = sorted(sub.nodes.where((n) => switch (_filter) {
          M3ServerFilter.all => true,
          M3ServerFilter.ai => n.aiReachable,
          M3ServerFilter.verified => n.isTrulyWorking,
        }));

    // Группы по стране; порядок — по лучшему серверу группы.
    final Map<String, List<Node>> groups = {};
    final Map<String, String> names = {};
    for (final Node n in nodes) {
      final Country c = countryOfName(n.name);
      groups.putIfAbsent(c.code, () => []).add(n);
      names[c.code] = c.name;
    }

    final Widget header = Padding(
      padding: EdgeInsets.fromLTRB(margin + AppSpacing.space50, widget.inSheet ? 0 : AppSpacing.space150, AppSpacing.space100, AppSpacing.space100),
      child: Row(children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text('Серверы', style: context.text.headlineSmall!.emphasized),
          ),
        ),
        if (busy)
          const SizedBox.square(
            dimension: 48,
            child: Center(child: M3LoadingIndicator(semanticsLabel: 'Проверяем серверы')),
          )
        else
          M3IconButton(
            onPressed: _refresh,
            icon: const Icon(Symbols.refresh),
            tooltip: 'Проверить серверы',
            color: M3IconButtonColor.standard,
          ),
        M3IconButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SubscriptionManagerScreen())),
          icon: const Icon(Symbols.add),
          tooltip: 'Подписки',
          color: M3IconButtonColor.standard,
        ),
      ]),
    );

    final Widget search = Padding(
      padding: const EdgeInsets.symmetric(horizontal: margin),
      child: M3SearchBar(
        hintText: 'Страна, город или сервер',
        controller: _query,
        contentBuilder: (context, query) => _SearchResults(
          nodes: sorted(sub.nodes.where((n) => matches(n, query.trim().toLowerCase()))),
          current: current,
          onSelect: (n) {
            M3SearchScope.of(context).close();
            _select(n);
          },
        ),
      ),
    );

    // Ряд чипов прокручивается вбок, а не переносится (Chips → Behavior:
    // «chips can scroll horizontally»).
    final Widget filters = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.fromLTRB(margin, AppSpacing.space150, margin, AppSpacing.space50),
      child: Row(children: [
        for (final (M3ServerFilter f, String label, int count) in [
          (M3ServerFilter.all, 'Все', sub.nodes.length),
          (M3ServerFilter.ai, 'AI-проба', aiCount),
          (M3ServerFilter.verified, 'Проверенные', verified),
        ]) ...[
          if (f != M3ServerFilter.all) const SizedBox(width: AppSpacing.space100),
          M3FilterChip(
            label: Text('$label · $count'),
            selected: _filter == f,
            onSelected: (_) => setState(() => _filter = f),
          ),
        ],
      ]),
    );

    final Widget list = ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(margin, AppSpacing.space100, margin, AppSpacing.space200),
      children: [
        SegmentedList(children: [
          M3ListItem(
            leading: M3ShapeIcon(
              icon: Symbols.bolt,
              shape: MaterialShapes.softBurst,
              color: s.tertiaryContainer,
              onColor: s.onTertiaryContainer,
            ),
            headline: const Text('Автовыбор'),
            supporting: const Text('Лучший по задержке и AI-пробе'),
            trailing: ExcludeSemantics(child: M3Switch(value: picked == null, onChanged: _setAuto)),
            onTap: () => _setAuto(picked != null),
            semanticsLabel: 'Автовыбор, лучший по задержке и AI-пробе, ${picked == null ? 'включено' : 'выключено'}',
          ),
        ]),
        for (final MapEntry<String, List<Node>> e in groups.entries) ...[
          SectionHeader('${names[e.key]!} · ${e.value.length}'),
          SegmentedList(children: [
            for (final Node n in e.value) _ServerItem(node: n, selected: n.id == current?.id, onTap: () => _select(n)),
          ]),
        ],
        if (nodes.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.space400),
            child: Text('Под фильтр ничего не подходит', textAlign: TextAlign.center, style: context.text.bodyLarge!.copyWith(color: s.onSurfaceVariant)),
          ),
      ],
    );

    final DateTime? at = sub.lastFetchedAt;
    final String ago = at == null ? '' : ' · обновлено ${_ago(DateTime.now().difference(at))}';
    final Widget footer = Padding(
      padding: const EdgeInsets.fromLTRB(margin + AppSpacing.space50, AppSpacing.space50, margin, AppSpacing.space150),
      child: Text(
        '${sub.nodes.length} ${_servers(sub.nodes.length)} · $aiCount с AI$ago',
        style: context.text.bodySmall!.copyWith(color: s.onSurfaceVariant),
      ),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      header,
      search,
      filters,
      Expanded(child: list),
      footer,
    ]);
  }

  static String _servers(int n) {
    final int d = n % 10, h = n % 100;
    if (d == 1 && h != 11) return 'сервер';
    if (d >= 2 && d <= 4 && (h < 12 || h > 14)) return 'сервера';
    return 'серверов';
  }

  static String _ago(Duration d) {
    if (d.inMinutes < 1) return 'только что';
    if (d.inHours < 1) return '${d.inMinutes} мин назад';
    if (d.inDays < 1) return '${d.inHours} ч назад';
    return '${d.inDays} дн назад';
  }
}

/// Строка сервера: флаг в форме, имя, пинг; AI-бейдж; выбранный — отметка
/// и выбранное состояние пункта списка (`secondaryContainer`, углы 16dp).
class _ServerItem extends StatelessWidget {
  const _ServerItem({required this.node, required this.selected, required this.onTap});

  final Node node;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ColorScheme s = context.colors;
    final Country c = countryOfName(node.name);
    final String name = displayNodeName(node.name);
    return M3ListItem(
      leading: M3Flag(code: c.code),
      headline: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
      supporting: M3Ping(ms: node.latencyMs, alive: node.isAlive),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (node.aiReachable) const M3AiBadge(),
        if (selected) ...[
          const SizedBox(width: AppSpacing.space100),
          Icon(Symbols.check, color: s.onSecondaryContainer),
        ],
      ]),
      selected: selected,
      enabled: node.isAlive,
      onTap: onTap,
      semanticsLabel: [
        name,
        if (node.latencyMs != null) '${node.latencyMs} мс',
        if (node.aiReachable) 'AI-проба пройдена',
        if (!node.isAlive) 'недоступен',
        if (selected) 'выбран',
      ].join(', '),
    );
  }
}

/// Результаты открытого поиска — плоский список без групп.
class _SearchResults extends StatelessWidget {
  const _SearchResults({required this.nodes, required this.current, required this.onSelect});

  final List<Node> nodes;
  final Node? current;
  final ValueChanged<Node> onSelect;

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.space400),
        child: Text('Ничего не нашлось', textAlign: TextAlign.center, style: context.text.bodyLarge!.copyWith(color: context.colors.onSurfaceVariant)),
      );
    }
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space200),
      children: [
        SegmentedList(children: [
          for (final Node n in nodes) _ServerItem(node: n, selected: n.id == current?.id, onTap: () => onSelect(n)),
        ]),
      ],
    );
  }
}
