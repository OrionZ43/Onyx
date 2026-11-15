// Список серверов темы Material 3 Expressive.
//
// * [showM3ServerSheet] — модальный нижний лист M3 (телефон).
// * [M3ServerList] — то же содержимое панелью (окно Windows шире 840dp).
//
// Поведение — как у NodeListPanel (темы Onyx и Signal), провайдеры общие:
// вкладки «Все / Избранное / Свои / группы» (groupNodesProvider), фильтры
// «Голос», «AI», «Страна»; «Автовыбор» с выбором группы (autoGroupProvider);
// во «Все» секция «Свои» первой (#68), остальные — по странам
// (countryResolverProvider); выбор сервера — chooseNode (переподключение на
// ходу); долгое нажатие — меню: страна, группы.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_new_shapes/material_new_shapes.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/m3/app_spacing.dart';
import '../../core/theme/m3/app_typography.dart';
import '../../domain/entities/node.dart';
import '../../domain/entities/vpn_state.dart';
import '../providers/country_provider.dart';
import '../providers/groups_provider.dart';
import '../providers/node_provider.dart';
import '../providers/own_nodes_provider.dart';
import '../providers/sources_provider.dart';
import '../providers/subscription_provider.dart';
import '../providers/vpn_provider.dart';
import '../screens/groups_screen.dart' show askGroupName, autoGroupEntries, groupLabel;
import '../screens/subscription_manager_screen.dart';
import '../util/country.dart';
import '../util/vpn_actions.dart';
import '../widgets/add_source_sheet.dart';
import '../widgets/m3/m3_bottom_sheet.dart';
import '../widgets/m3/m3_buttons.dart';
import '../widgets/m3/m3_filter_chip.dart';
import '../widgets/m3/m3_loading_indicator.dart';
import '../widgets/m3/m3_search.dart';
import '../widgets/m3/m3_switch.dart';
import '../widgets/m3/section_header.dart';
import '../widgets/m3/segmented_list.dart';
import 'm3_country_picker.dart';
import 'm3_parts.dart';
import 'm3_subscription_import.dart';

/// Модальный нижний лист со списком серверов: ручка перетаскивания,
/// раскрытие до полного экрана (`M3BottomSheet`, порт Compose `ModalBottomSheet`).
Future<void> showM3ServerSheet(BuildContext context) => showM3ModalBottomSheet<void>(
      context: context,
      builder: (context, scrollController) => M3ServerList(inSheet: true, scrollController: scrollController),
    );

/// Ключ секции «Свои» во «Все» — не код страны (те двухбуквенные).
const String _ownSection = 'own';

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

  /// Вкладка: null — «Все», иначе id группы (в том числе auto:fav, auto:own).
  String? _tab;
  bool _voice = false, _ai = false;
  String? _country;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  /// [after] — сначала дождаться этого (закрытия поиска над листом), потом
  /// закрыть лист: иначе maybePop попадёт в маршрут поиска, и лист останется.
  void _select(Node node, {Future<Object?>? after}) {
    HapticFeedback.selectionClick();
    // Выбор и переподключение на ходу — общая логика (util/vpn_actions.dart).
    chooseNode(ref, node);
    if (!widget.inSheet) return;
    void close() {
      if (mounted) Navigator.of(context).maybePop();
    }

    after == null ? close() : after.then((_) => close());
  }

  /// Как в Onyx (node_list_sheet): только режим выбора, соединение не
  /// трогаем — лучший сервер возьмётся при следующем подключении.
  void _setAuto(bool auto) {
    final Node? best = ref.read(autoNodeProvider);
    if (auto) {
      ref.read(nodeSelectionProvider.notifier).clear();
    } else if (best != null) {
      ref.read(nodeSelectionProvider.notifier).select(best);
    }
  }

  Future<void> _refresh() async {
    HapticFeedback.lightImpact();
    // Итог — с причинами по источникам (RefreshReport).
    final report = await ref.read(sourcesProvider.notifier).refreshAll();
    if (mounted) showM3Message(context, report.summary);
  }

  /// Выбор из списка в нижнем листе M3: пункты сегментированного списка,
  /// выбранный — отметкой.
  Future<T?> _pick<T>(String title, List<(T, String, Widget?)> options, T? current) => showM3ModalBottomSheet<T>(
        context: context,
        builder: (context, controller) => ListView(
          controller: controller,
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(AppSpacing.space200, 0, AppSpacing.space200, AppSpacing.space300),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.space100, 0, AppSpacing.space100, AppSpacing.space150),
              child: Text(title, style: context.text.titleLarge),
            ),
            SegmentedList(children: [
              for (final (T v, String label, Widget? lead) in options)
                M3ListItem(
                  leading: lead,
                  headline: Text(label),
                  trailing: v == current ? Icon(Symbols.check, color: context.colors.onSecondaryContainer) : null,
                  selected: v == current,
                  onTap: () => Navigator.of(context).pop(v),
                ),
            ]),
          ],
        ),
      );

  Future<void> _pickAutoGroup() async {
    final List<NodeGroup> groups = ref.read(groupsProvider);
    final String? cur = ref.read(autoGroupProvider);
    final bool hasOwn = ref.read(ownNodeIdsProvider).isNotEmpty;
    final String? v = await _pick<String>(
      'Автовыбор из группы',
      [
        for (final e in autoGroupEntries(hasOwn: hasOwn)) (e.key ?? '*', e.value, null),
        for (final NodeGroup g in groups) (g.id, g.name, null),
      ],
      cur ?? '*',
    );
    // Как в Onyx: меняется только группа, ручной выбор и соединение — нет.
    if (v == null || !mounted) return;
    await ref.read(autoGroupProvider.notifier).setAutoGroup(v == '*' ? null : v);
  }

  Future<void> _pickCountry(Map<String, String> countries) async {
    final List<MapEntry<String, String>> list = countries.entries.where((e) => e.key.isNotEmpty).toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final String? v = await _pick<String>(
      'Страна',
      [
        ('*', 'Все страны', null),
        for (final MapEntry<String, String> e in list) (e.key, e.value, M3Flag(code: e.key, size: 32)),
        // Страна не определилась — «Другие», как в Onyx.
        if (countries.containsKey('')) ('', Country.unknown.name, const M3Flag(code: '', size: 32)),
      ],
      _country ?? '*',
    );
    if (v == null || !mounted) return;
    setState(() => _country = v == '*' ? null : v);
  }

  Future<void> _newGroup({String? withNode}) async {
    final String? name = await askGroupName(context);
    if (name == null || name.trim().isEmpty || !mounted) return;
    final GroupsController ctl = ref.read(groupsProvider.notifier);
    final NodeGroup g = await ctl.create(name.trim());
    if (withNode != null) {
      await ctl.addNodes(g.id, [withNode]);
    } else if (mounted) {
      setState(() => _tab = g.id);
    }
  }

  /// Долгое нажатие на сервер: страна (если определилась неверно) и группы.
  Future<void> _menu(Node node) async {
    final CountryResolver cr = ref.read(countryResolverProvider);
    final Country country = cr.of(node);
    final List<NodeGroup> groups = ref.read(groupsProvider);
    final String? v = await showM3ModalBottomSheet<String>(
      context: context,
      builder: (context, controller) => ListView(
        controller: controller,
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(AppSpacing.space200, 0, AppSpacing.space200, AppSpacing.space300),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.space100, 0, AppSpacing.space100, AppSpacing.space150),
            child: Text(displayNodeName(node.name), style: context.text.titleLarge),
          ),
          SegmentedList(children: [
            M3ListItem(
              leading: M3Flag(code: country.code),
              headline: Text(country.isKnown ? 'Страна: ${country.name}' : 'Указать страну'),
              supporting: Text(cr.sourceOf(node).label),
              onTap: () => Navigator.of(context).pop('country'),
            ),
          ]),
          const SectionHeader('Группы'),
          SegmentedList(children: [
            for (final NodeGroup g in groups)
              M3ListItem(
                leading: Icon(g.nodeIds.contains(node.id) ? Symbols.check : Symbols.add),
                headline: Text(g.nodeIds.contains(node.id) ? 'Убрать из «${g.name}»' : 'В группу «${g.name}»'),
                onTap: () => Navigator.of(context).pop(g.id),
              ),
            M3ListItem(
              leading: const Icon(Symbols.create_new_folder),
              headline: const Text('Новая группа…'),
              onTap: () => Navigator.of(context).pop('+'),
            ),
          ]),
        ],
      ),
    );
    if (v == null || !mounted) return;
    if (v == 'country') {
      final String? code = await showM3CountryPicker(
        context,
        serverName: displayNodeName(node.name),
        picked: ref.read(countryOverridesProvider)[node.serverKey],
        detected: cr.detected(node),
        detectedHow: cr.detectedHow(node),
      );
      if (code != null && mounted) await ref.read(countryOverridesProvider.notifier).set(node.serverKey, code);
      return;
    }
    if (v == '+') return _newGroup(withNode: node.id);
    final GroupsController ctl = ref.read(groupsProvider.notifier);
    final NodeGroup g = groups.firstWhere((x) => x.id == v);
    g.nodeIds.contains(node.id) ? ctl.removeNode(g.id, node.id) : ctl.addNodes(g.id, [node.id]);
  }

  static List<Node> sorted(Iterable<Node> nodes) => nodes.toList()
    ..sort((a, b) {
      if (a.isAlive != b.isAlive) return a.isAlive ? -1 : 1;
      return (a.rttMs ?? 99999).compareTo(b.rttMs ?? 99999);
    });

  @override
  Widget build(BuildContext context) {
    final ColorScheme s = context.colors;
    final SubscriptionState sub = ref.watch(subscriptionProvider);
    final Node? picked = ref.watch(nodeSelectionProvider);
    final VpnState vpn = ref.watch(vpnControllerProvider);
    final Node? current = vpn is VpnConnected ? vpn.node : (picked ?? ref.watch(autoNodeProvider));
    final Set<String> favs = ref.watch(favoritesProvider);
    final List<NodeGroup> userGroups = ref.watch(groupsProvider);
    final String? autoGroup = ref.watch(autoGroupProvider);
    final Set<String> own = ref.watch(ownNodeIdsProvider);
    final CountryResolver cr = ref.watch(countryResolverProvider);
    final int sourceCount = ref.watch(sourcesProvider.select((l) => l.length));
    const double margin = AppSpacing.space200;

    if (sub.nodes.isEmpty && sub.status != SubStatus.fetching) {
      return const M3SubscriptionImport();
    }

    // Вкладка удалена (группу стёрли, своих серверов не осталось) — во «Все».
    final String? tab = _tab == null ||
            _tab == NodeGroup.favoritesId ||
            (_tab == NodeGroup.ownId && own.isNotEmpty) ||
            userGroups.any((g) => g.id == _tab)
        ? _tab
        : null;
    final List<Node> base = tab == null ? sub.nodes : ref.watch(groupNodesProvider(tab));
    final bool busy = sub.status == SubStatus.fetching || sub.status == SubStatus.probing || sub.status == SubStatus.deepProbing;

    final List<Node> nodes = sorted(base.where((n) {
      if (_voice && !n.udpSupported) return false;
      if (_ai && !n.aiReachable) return false;
      if (_country != null && cr.of(n).code != _country) return false;
      return true;
    }));

    // Во «Все» свои серверы — первой секцией, остальные — по странам.
    final Map<String, List<Node>> sections = {};
    final Map<String, String> names = {};
    if (tab == null) {
      final List<Node> mine = [for (final Node n in nodes) if (own.contains(n.id)) n];
      if (mine.isNotEmpty) {
        sections[_ownSection] = mine;
        names[_ownSection] = 'Свои';
      }
    }
    for (final Node n in nodes) {
      if (sections.containsKey(_ownSection) && own.contains(n.id)) continue;
      final Country c = cr.of(n);
      sections.putIfAbsent(c.code, () => []).add(n);
      names[c.code] = c.name;
    }
    final Map<String, String> countries = {for (final Node n in sub.nodes) cr.of(n).code: cr.of(n).name};

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
            tooltip: 'Обновить и проверить',
            color: M3IconButtonColor.standard,
          ),
        M3IconButton(
          onPressed: () => showAddSourceSheet(context),
          icon: const Icon(Symbols.add),
          tooltip: 'Добавить подписку или ссылки',
          color: M3IconButtonColor.standard,
        ),
      ]),
    );

    final Widget search = Padding(
      padding: const EdgeInsets.symmetric(horizontal: margin),
      child: M3SearchBar(
        hintText: 'Страна, город или сервер',
        controller: _query,
        contentBuilder: (context, query) {
          final String q = query.trim().toLowerCase();
          return _SearchResults(
            nodes: sorted(sub.nodes.where((n) => q.isEmpty || n.name.toLowerCase().contains(q) || cr.of(n).name.toLowerCase().contains(q))),
            current: current,
            onSelect: (n) {
              // Поиск — свой маршрут поверх листа: сначала он сворачивается,
              // лист закрываем, когда маршрут поиска снят.
              final Future<Object?>? searchClosed = ModalRoute.of(context)?.popped;
              M3SearchScope.of(context).close();
              _select(n, after: searchClosed);
            },
            onMenu: _menu,
          );
        },
      ),
    );

    // Ряды чипов прокручиваются вбок, а не переносятся (Chips → Behavior:
    // «chips can scroll horizontally»).
    Widget chipRow(List<Widget> chips, {double top = AppSpacing.space150}) => SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.fromLTRB(margin, top, margin, 0),
          child: Row(children: [
            for (int i = 0; i < chips.length; i++) ...[if (i > 0) const SizedBox(width: AppSpacing.space100), chips[i]],
          ]),
        );

    final Widget tabs = chipRow([
      for (final (String? id, String label, int count) in [
        (null, 'Все', sub.nodes.length),
        (NodeGroup.favoritesId, 'Избранное', favs.length),
        if (own.isNotEmpty) (NodeGroup.ownId, 'Свои', own.length),
        for (final NodeGroup g in userGroups) (g.id, g.name, ref.watch(groupNodesProvider(g.id)).length),
      ])
        M3FilterChip(
          label: Text('$label · $count'),
          selected: tab == id,
          onSelected: (_) => setState(() => _tab = id),
        ),
      M3IconButton(
        onPressed: _newGroup,
        icon: const Icon(Symbols.add),
        tooltip: 'Новая группа',
        color: M3IconButtonColor.standard,
      ),
    ]);

    final Widget facets = chipRow([
      M3FilterChip(
        leading: const Icon(Symbols.mic),
        label: Text('Голос · ${sub.nodes.where((n) => n.udpSupported).length}'),
        selected: _voice,
        onSelected: (v) => setState(() => _voice = v),
      ),
      M3FilterChip(
        leading: const Icon(Symbols.auto_awesome),
        label: Text('AI · ${sub.nodes.where((n) => n.aiReachable).length}'),
        selected: _ai,
        onSelected: (v) => setState(() => _ai = v),
      ),
      M3FilterChip(
        leading: const Icon(Symbols.public),
        label: Text(_country == null ? 'Страна' : (countries[_country] ?? 'Страна')),
        selected: _country != null,
        onSelected: (_) => _pickCountry(countries),
      ),
    ], top: AppSpacing.space100);

    final Widget list = ListView(
      controller: widget.scrollController,
      padding: const EdgeInsets.fromLTRB(margin, AppSpacing.space150, margin, AppSpacing.space200),
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
            supporting: Text('Из «${groupLabel(autoGroup, userGroups)}» · лучший по пингу и AI'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              M3IconButton(
                onPressed: _pickAutoGroup,
                icon: const Icon(Symbols.tune),
                tooltip: 'Группа для автовыбора',
                color: M3IconButtonColor.standard,
              ),
              ExcludeSemantics(child: M3Switch(value: picked == null, onChanged: _setAuto)),
            ]),
            onTap: () => _setAuto(picked != null),
            semanticsLabel: 'Автовыбор из «${groupLabel(autoGroup, userGroups)}», ${picked == null ? 'включено' : 'выключено'}',
            semanticsActions: {const CustomSemanticsAction(label: 'Группа для автовыбора'): _pickAutoGroup},
          ),
        ]),
        if (tab == NodeGroup.favoritesId && base.isEmpty)
          Padding(
            padding: const EdgeInsets.all(AppSpacing.space300),
            child: Text('Отмечайте серверы звёздочкой — они соберутся здесь.',
                textAlign: TextAlign.center, style: context.text.bodyLarge!.copyWith(color: s.onSurfaceVariant)),
          ),
        for (final MapEntry<String, List<Node>> e in sections.entries) ...[
          SectionHeader('${names[e.key]!} · ${e.value.length}'),
          SegmentedList(children: [
            for (final Node n in e.value)
              _ServerItem(
                node: n,
                country: cr.of(n),
                selected: n.id == current?.id,
                favorite: favs.contains(n.id),
                // В «Своих» значок «свой» не повторяется — это говорит заголовок.
                showOwn: own.contains(n.id) && tab != NodeGroup.ownId && e.key != _ownSection,
                quarantined: sub.quarantined.contains(n.id),
                onTap: () => _select(n),
                onLongPress: () => _menu(n),
                onFavorite: () => ref.read(favoritesProvider.notifier).toggle(n.id),
              ),
          ]),
        ],
        if (nodes.isEmpty && !(tab == NodeGroup.favoritesId && base.isEmpty))
          Padding(
            padding: const EdgeInsets.all(AppSpacing.space400),
            child: Text('Под фильтр ничего не подходит',
                textAlign: TextAlign.center, style: context.text.bodyLarge!.copyWith(color: s.onSurfaceVariant)),
          ),
      ],
    );

    final Widget footer = Padding(
      padding: const EdgeInsets.fromLTRB(margin + AppSpacing.space50, 0, AppSpacing.space100, AppSpacing.space50),
      child: Row(children: [
        Expanded(
          child: Text(
            '${sub.nodes.length} ${_plural(sub.nodes.length, 'сервер', 'сервера', 'серверов')} · '
            '$sourceCount ${_plural(sourceCount, 'источник', 'источника', 'источников')}',
            style: context.text.bodySmall!.copyWith(color: s.onSurfaceVariant),
          ),
        ),
        M3Button(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SubscriptionManagerScreen())),
          color: M3ButtonColor.text,
          size: M3ButtonSize.small,
          icon: const Icon(Symbols.tune),
          child: const Text('Подписки'),
        ),
      ]),
    );

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      header,
      search,
      tabs,
      facets,
      Expanded(child: list),
      footer,
    ]);
  }

  static String _plural(int n, String one, String few, String many) {
    final int d = n % 10, h = n % 100;
    if (d == 1 && h != 11) return one;
    if (d >= 2 && d <= 4 && (h < 12 || h > 14)) return few;
    return many;
  }
}

/// Строка сервера: флаг в форме, имя, пинг и свойства; значки «Свой» и AI,
/// звезда избранного; выбранный — отметка и выбранное состояние пункта
/// (`secondaryContainer`). Сервер на карантине (не поднялся при подключении)
/// и недоступный — приглушены.
class _ServerItem extends StatelessWidget {
  const _ServerItem({
    required this.node,
    required this.country,
    required this.selected,
    required this.favorite,
    required this.showOwn,
    required this.quarantined,
    required this.onTap,
    required this.onLongPress,
    required this.onFavorite,
  });

  final Node node;
  final Country country;
  final bool selected, favorite, showOwn, quarantined;
  final VoidCallback onTap, onLongPress, onFavorite;

  @override
  Widget build(BuildContext context) {
    final ColorScheme s = context.colors;
    final String name = displayNodeName(node.name);
    // Приглушён, но не выключен: как в Onyx и Signal, такой сервер можно
    // выбрать вручную и открыть его меню (страна, группы).
    final bool dimmed = !node.isAlive || quarantined;
    return M3ListItem(
      leading: Opacity(opacity: dimmed ? 0.38 : 1, child: M3Flag(code: country.code)),
      headline: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: dimmed && !selected ? TextStyle(color: s.onSurfaceVariant) : null,
      ),
      supporting: M3NodeMeta(node: node),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (showOwn) ...[const M3OwnBadge(), const SizedBox(width: AppSpacing.space50)],
        if (node.aiReachable) const M3AiBadge(),
        M3IconButton(
          onPressed: () {
            HapticFeedback.selectionClick();
            onFavorite();
          },
          icon: Icon(Symbols.star, fill: favorite ? 1 : 0, color: favorite ? s.primary : s.onSurfaceVariant),
          tooltip: favorite ? 'Убрать из избранного' : 'В избранное',
          color: M3IconButtonColor.standard,
        ),
        if (selected) Icon(Symbols.check, color: s.onSecondaryContainer),
      ]),
      selected: selected,
      onTap: onTap,
      onLongPress: onLongPress,
      semanticsLabel: [
        name,
        if (node.rttMs != null) '${node.rttIsEstimate ? 'около ' : ''}${node.rttMs} мс',
        if (showOwn) 'свой',
        if (node.aiReachable) 'AI-проба пройдена',
        if (favorite) 'в избранном',
        if (!node.isAlive) 'недоступен',
        if (quarantined) 'временно пропускается',
        if (selected) 'выбран',
      ].join(', '),
      semanticsActions: {CustomSemanticsAction(label: favorite ? 'Убрать из избранного' : 'В избранное'): onFavorite},
    );
  }
}

/// Результаты открытого поиска — плоский список без групп.
class _SearchResults extends ConsumerWidget {
  const _SearchResults({required this.nodes, required this.current, required this.onSelect, required this.onMenu});

  final List<Node> nodes;
  final Node? current;
  final ValueChanged<Node> onSelect;

  /// Долгое нажатие — то же меню сервера, что в списке (страна, группы).
  final ValueChanged<Node> onMenu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (nodes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(AppSpacing.space400),
        child: Text('Ничего не нашлось',
            textAlign: TextAlign.center, style: context.text.bodyLarge!.copyWith(color: context.colors.onSurfaceVariant)),
      );
    }
    final CountryResolver cr = ref.watch(countryResolverProvider);
    final Set<String> favs = ref.watch(favoritesProvider);
    final Set<String> own = ref.watch(ownNodeIdsProvider);
    final Set<String> quarantined = ref.watch(subscriptionProvider.select((s) => s.quarantined));
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space200),
      children: [
        SegmentedList(children: [
          for (final Node n in nodes)
            _ServerItem(
              node: n,
              country: cr.of(n),
              selected: n.id == current?.id,
              favorite: favs.contains(n.id),
              showOwn: own.contains(n.id),
              quarantined: quarantined.contains(n.id),
              onTap: () => onSelect(n),
              onLongPress: () => onMenu(n),
              onFavorite: () => ref.read(favoritesProvider.notifier).toggle(n.id),
            ),
        ]),
      ],
    );
  }
}
