// lib/presentation/widgets/node_list_sheet.dart
//
// Список серверов в стиле активной темы (Onyx / Signal / Material 3 Expressive).
//
// * [NodeListSheet] — шторка на телефоне (showOnyxNodeSheet).
// * [NodeListPanel] — то же содержимое без шторки: правая колонка на Windows.
//
// Поведение прежнее: выбор сервера пишется в nodeSelectionProvider, шторка
// закрывается сразу (без addPostFrameCallback). Новое: поиск, фильтр «AI»,
// «Автовыбор» (сброс ручного выбора → bestNode), группировка по стране с
// флагами без emoji, импорт подписки в пустом состоянии.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_new_shapes/material_new_shapes.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/onyx_tokens.dart';
import '../../domain/entities/node.dart';
import '../../domain/entities/vpn_state.dart';
import '../providers/country_provider.dart';
import '../providers/groups_provider.dart';
import '../providers/node_provider.dart';
import '../providers/own_nodes_provider.dart';
import '../providers/sources_provider.dart';
import '../providers/subscription_provider.dart';
import '../providers/vpn_provider.dart';
import '../screens/groups_screen.dart';
import '../screens/subscription_manager_screen.dart';
import '../util/country.dart';
import '../util/vpn_actions.dart';
import 'add_source_sheet.dart';
import 'country_flag.dart';
import 'country_picker.dart';
import 'home_parts.dart';
import 'onyx_field.dart';
import 'onyx_icon.dart';
import 'onyx_switch.dart';
import 'onyx_toast.dart';
import 'subscription_import.dart';

/// Открывает шторку серверов.
Future<void> showOnyxNodeSheet(BuildContext context) {
  final t = OnyxTokens.of(context);
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: t.isMaterial ? null : (t.isSignal ? t.bg : t.surface),
    barrierColor: Colors.black.withValues(alpha: t.isMaterial ? 0.32 : 0.66),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(t.radiusSheet)),
      side: t.isOnyx ? BorderSide(color: t.lineStrong) : (t.isSignal ? BorderSide(color: t.lineStrong) : BorderSide.none),
    ),
    clipBehavior: Clip.antiAlias,
    builder: (_) => const NodeListSheet(),
  );
}

class NodeListSheet extends StatelessWidget {
  const NodeListSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.88,
      child: Column(
        children: [
          Container(
            width: t.isMaterial ? 32 : 36,
            height: 4,
            margin: EdgeInsets.only(top: t.isMaterial ? 22 : 10, bottom: 4),
            decoration: BoxDecoration(
              color: t.isMaterial ? Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.4) : t.lineStrong,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const Expanded(child: NodeListPanel(inSheet: true)),
        ],
      ),
    );
  }
}

/// Автофильтры листа: комбинируются (И), «Страны» — один выбранный код.
class _Facets {
  const _Facets({this.voice = false, this.ai = false, this.country});
  final bool voice, ai;
  final String? country;
  bool get any => voice || ai || country != null;
  _Facets copy({bool? voice, bool? ai, String? country, bool clearCountry = false}) => _Facets(
        voice: voice ?? this.voice,
        ai: ai ?? this.ai,
        country: clearCountry ? null : (country ?? this.country),
      );
}

/// Ключ секции «Свои» во «Все» — не код страны (те двухбуквенные).
const _ownSection = 'own';

class NodeListPanel extends ConsumerStatefulWidget {
  const NodeListPanel({super.key, this.inSheet = false});
  final bool inSheet;

  @override
  ConsumerState<NodeListPanel> createState() => _NodeListPanelState();
}

class _NodeListPanelState extends ConsumerState<NodeListPanel> {
  final _query = TextEditingController();
  _Facets _facets = const _Facets();

  /// Вкладка-группа: null — «Все», 'auto:fav' — «Избранное», 'auto:own' — «Свои»,
  /// иначе id группы.
  String? _tab;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _select(Node node) {
    HapticFeedback.selectionClick();
    // Выбор + переподключение на ходу — общая логика (util/vpn_actions.dart).
    chooseNode(ref, node);
    if (widget.inSheet && mounted) Navigator.of(context).maybePop();
  }

  void _setAuto(bool auto) {
    final best = ref.read(autoNodeProvider);
    if (auto) {
      ref.read(nodeSelectionProvider.notifier).clear();
    } else if (best != null) {
      ref.read(nodeSelectionProvider.notifier).select(best);
    }
  }

  Future<void> _pickAutoGroup() async {
    final t = OnyxTokens.of(context);
    final groups = ref.read(groupsProvider);
    final cur = ref.read(autoGroupProvider);
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: t.isMaterial ? null : t.surface,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final e in [...autoGroupEntries(hasOwn: ref.read(ownNodeIdsProvider).isNotEmpty).map((e) => (e.key, e.value)), ...groups.map((g) => (g.id, g.name))])
            ListTile(
              title: Text(e.$2, style: TextStyle(fontFamily: t.bodyFont, color: t.text)),
              trailing: e.$1 == cur ? OnyxIcon(OnyxGlyph.check, size: 18, color: t.accent) : null,
              onTap: () => Navigator.pop(c, e.$1 ?? '*'),
            ),
        ]),
      ),
    );
    if (v != null) ref.read(autoGroupProvider.notifier).setAutoGroup(v == '*' ? null : v);
  }

  Future<void> _nodeMenu(Node node) async {
    final t = OnyxTokens.of(context);
    final groups = ref.read(groupsProvider);
    final cr = ref.read(countryResolverProvider);
    final country = cr.of(node);
    final v = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: t.isMaterial ? null : t.surface,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(displayNodeName(node.name), style: TextStyle(fontFamily: t.bodyFont, fontSize: 15, fontWeight: FontWeight.w500, color: t.text)),
          ),
          // Страна для флага (#68): если по названию не определилась или
          // определилась неверно — выбрать вручную.
          ListTile(
            leading: CountryFlag(code: country.code, size: 22),
            title: Text(country.isKnown ? 'Страна: ${country.name}' : 'Указать страну', style: TextStyle(fontFamily: t.bodyFont, color: t.text)),
            subtitle: Text(
              cr.sourceOf(node).label,
              style: TextStyle(fontFamily: t.bodyFont, fontSize: 12.5, color: t.textMuted),
            ),
            onTap: () => Navigator.pop(c, 'country'),
          ),
          for (final g in groups)
            ListTile(
              leading: OnyxIcon(g.nodeIds.contains(node.id) ? OnyxGlyph.check : OnyxGlyph.plus, size: 18, color: t.textMuted),
              title: Text(g.nodeIds.contains(node.id) ? 'Убрать из «${g.name}»' : 'В группу «${g.name}»', style: TextStyle(fontFamily: t.bodyFont, color: t.text)),
              onTap: () => Navigator.pop(c, g.id),
            ),
          ListTile(
            leading: OnyxIcon(OnyxGlyph.plus, size: 18, color: t.accent),
            title: Text('Новая группа…', style: TextStyle(fontFamily: t.bodyFont, color: t.accent)),
            onTap: () => Navigator.pop(c, '+'),
          ),
        ]),
      ),
    );
    if (v == null || !mounted) return;
    if (v == 'country') {
      final code = await showCountryPicker(
        context,
        serverName: displayNodeName(node.name),
        picked: ref.read(countryOverridesProvider)[node.serverKey],
        detected: cr.detected(node),
        detectedHow: cr.detectedHow(node),
      );
      if (code != null) await ref.read(countryOverridesProvider.notifier).set(node.serverKey, code);
      return;
    }
    final ctl = ref.read(groupsProvider.notifier);
    if (v == '+') {
      final name = await askGroupName(context);
      if (name == null || name.trim().isEmpty) return;
      final g = await ctl.create(name.trim());
      await ctl.addNodes(g.id, [node.id]);
      return;
    }
    final g = groups.firstWhere((x) => x.id == v);
    g.nodeIds.contains(node.id) ? ctl.removeNode(g.id, node.id) : ctl.addNodes(g.id, [node.id]);
  }

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    final sub = ref.watch(subscriptionProvider);
    final picked = ref.watch(nodeSelectionProvider);
    final vpn = ref.watch(vpnControllerProvider);
    final auto = ref.watch(autoNodeProvider);
    final current = vpn is VpnConnected ? vpn.node : (picked ?? auto);
    final favs = ref.watch(favoritesProvider);
    final userGroups = ref.watch(groupsProvider);
    final autoGroup = ref.watch(autoGroupProvider);
    final sourceCount = ref.watch(sourcesProvider.select((l) => l.length));
    // «Свои» (#68): серверы, добавленные пользователем ссылками.
    final own = ref.watch(ownNodeIdsProvider);
    final cr = ref.watch(countryResolverProvider);
    // Вкладка удалена (группу стёрли, свои серверы убрали) — возвращаемся во «Все».
    final tab = _tab == null ||
            _tab == 'auto:fav' ||
            (_tab == NodeGroup.ownId && own.isNotEmpty) ||
            userGroups.any((g) => g.id == _tab)
        ? _tab
        : null;
    final base = tab == null
        ? sub.nodes
        : ref.watch(groupNodesProvider(tab));
    final pad = t.isMaterial ? 16.0 : 20.0;

    if (sub.nodes.isEmpty && sub.status != SubStatus.fetching) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: pad),
        child: const SubscriptionImport(),
      );
    }

    final q = _query.text.trim().toLowerCase();
    final nodes = base.where((n) {
      final c = cr.of(n);
      if (_facets.voice && !n.udpSupported) return false;
      if (_facets.ai && !n.aiReachable) return false;
      if (_facets.country != null && c.code != _facets.country) return false;
      if (q.isEmpty) return true;
      return n.name.toLowerCase().contains(q) || c.name.toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) {
        if (a.isAlive != b.isAlive) return a.isAlive ? -1 : 1;
        return (a.latencyMs ?? 99999).compareTo(b.latencyMs ?? 99999);
      });

    // Во «Все» свои серверы — первой секцией (#68), остальные — группами по
    // стране; порядок стран — по лучшему пингу в группе.
    final groups = <String, List<Node>>{};
    final names = <String, String>{};
    if (tab == null) {
      final mine = [for (final n in nodes) if (own.contains(n.id)) n];
      if (mine.isNotEmpty) {
        groups[_ownSection] = mine;
        names[_ownSection] = 'Свои';
      }
    }
    for (final n in nodes) {
      if (groups.containsKey(_ownSection) && own.contains(n.id)) continue;
      final c = cr.of(n);
      groups.putIfAbsent(c.code, () => []).add(n);
      names[c.code] = c.name;
    }
    final aiCount = sub.nodes.where((n) => n.aiReachable).length;
    final voiceCount = sub.nodes.where((n) => n.udpSupported).length;
    final countries = <String, String>{};
    for (final n in sub.nodes) {
      final c = cr.of(n);
      countries[c.code] = c.name;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          pad: pad,
          busy: sub.status == SubStatus.fetching || sub.status == SubStatus.probing || sub.status == SubStatus.deepProbing,
          onRefresh: () async {
            // Итог — с причинами по источникам (RefreshReport, «Оникс» #45).
            final report = await ref.read(sourcesProvider.notifier).refreshAll();
            if (context.mounted) showOnyxToast(context, report.summary, glyph: report.allFailed ? OnyxGlyph.error : OnyxGlyph.refresh);
          },
          onAdd: () => showAddSourceSheet(context),
        ),
        _GroupTabs(
          pad: pad,
          value: tab,
          tabs: [
            (null, 'Все', sub.nodes.length),
            ('auto:fav', 'Избранное', favs.length),
            if (own.isNotEmpty) (NodeGroup.ownId, 'Свои', own.length),
            for (final g in userGroups) (g.id, g.name, ref.watch(groupNodesProvider(g.id)).length),
          ],
          onChanged: (v) => setState(() => _tab = v),
          onAdd: () async {
            final name = await askGroupName(context);
            if (name == null || name.trim().isEmpty) return;
            final g = await ref.read(groupsProvider.notifier).create(name.trim());
            if (mounted) setState(() => _tab = g.id);
          },
        ),
        const SizedBox(height: 12),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          child: TextField(
            controller: _query,
            onChanged: (_) => setState(() {}),
            style: TextStyle(fontFamily: t.bodyFont, fontSize: t.isMaterial ? 16 : 14, color: t.text),
            decoration: onyxInputDecoration(
              context,
              hint: t.isMaterial ? 'Страна, город, сервер' : 'Страна, город или сервер',
              prefix: OnyxIcon(OnyxGlyph.search, size: t.isMaterial ? 24 : 16, color: t.textFaint),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 12, pad, 4),
          child: _FacetRow(
            value: _facets,
            voiceCount: voiceCount,
            aiCount: aiCount,
            countries: countries,
            onChanged: (f) => setState(() => _facets = f),
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.only(top: 6, bottom: 16, left: t.isMaterial ? pad : 0, right: t.isMaterial ? pad : 0),
            children: [
              _AutoRow(
                pad: t.isMaterial ? 0 : pad,
                auto: picked == null,
                group: groupLabel(autoGroup, userGroups),
                onChanged: _setAuto,
                onPickGroup: _pickAutoGroup,
              ),
              if (tab == 'auto:fav' && base.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
                  child: Text('Отмечайте серверы звёздочкой — они соберутся здесь.', textAlign: TextAlign.center, style: TextStyle(fontFamily: t.bodyFont, color: t.textMuted)),
                ),
              for (final e in groups.entries) ...[
                _GroupHeader(name: names[e.key]!, count: e.value.length, pad: t.isMaterial ? 0 : pad),
                if (t.isMaterial)
                  _MaterialSegment(
                    children: [for (final n in e.value) _NodeRow(
                        node: n,
                        country: cr.of(n),
                        inOwnList: tab == NodeGroup.ownId || e.key == _ownSection,
                        selected: n.id == current?.id,
                        favorite: favs.contains(n.id),
                        onFavorite: () => ref.read(favoritesProvider.notifier).toggle(n.id),
                        onLongPress: () => _nodeMenu(n),
                        onTap: () => _select(n),
                        quarantined: sub.quarantined.contains(n.id),
                      )],
                  )
                else
                  for (final n in e.value) _NodeRow(
                        node: n,
                        country: cr.of(n),
                        inOwnList: tab == NodeGroup.ownId || e.key == _ownSection,
                        selected: n.id == current?.id,
                        favorite: favs.contains(n.id),
                        onFavorite: () => ref.read(favoritesProvider.notifier).toggle(n.id),
                        onLongPress: () => _nodeMenu(n),
                        onTap: () => _select(n),
                        quarantined: sub.quarantined.contains(n.id),
                      ),
              ],
              if (nodes.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text('Ничего не найдено', textAlign: TextAlign.center, style: TextStyle(fontFamily: t.bodyFont, color: t.textMuted)),
                ),
            ],
          ),
        ),
        _Footer(
          pad: pad,
          total: sub.nodes.length,
          sources: sourceCount,
          onSources: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SubscriptionManagerScreen())),
        ),
      ],
    );
  }
}

// ── Шапка ───────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.pad, required this.busy, required this.onRefresh, required this.onAdd});
  final double pad;
  final bool busy;
  final VoidCallback onRefresh, onAdd;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    final title = Text(
      'Серверы',
      style: t.isMaterial
          ? Theme.of(context).textTheme.titleLarge
          : TextStyle(
              fontFamily: t.displayFont,
              fontSize: t.isSignal ? 28 : 26,
              fontWeight: t.isSignal ? FontWeight.w500 : FontWeight.w400,
              letterSpacing: t.isSignal ? -0.9 : -0.5,
              color: t.text,
            ),
    );
    Widget btn(OnyxGlyph g, String tip, VoidCallback onTap) => Padding(
          padding: const EdgeInsets.only(left: 8),
          child: _RoundButton(glyph: g, tooltip: tip, onTap: onTap),
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, t.isMaterial ? 4 : 14, pad - (t.isMaterial ? 8 : 0), 12),
      child: Row(
        children: [
          Expanded(child: title),
          if (busy)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 1.5, color: t.accent)),
            )
          else
            btn(OnyxGlyph.refresh, 'Проверить серверы', onRefresh),
          btn(OnyxGlyph.plus, 'Подписки', onAdd),
        ],
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({required this.glyph, required this.tooltip, required this.onTap});
  final OnyxGlyph glyph;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    return IconButton(
      tooltip: tooltip,
      onPressed: onTap,
      icon: OnyxIcon(glyph, size: t.isMaterial ? 24 : (t.isSignal ? 18 : 16), color: t.isMaterial ? null : (t.isSignal ? t.text : t.textMuted)),
      style: IconButton.styleFrom(
        fixedSize: Size.square(t.isMaterial ? 48 : 40),
        backgroundColor: t.isSignal ? t.surfaceHigh : Colors.transparent,
        shape: CircleBorder(side: t.isOnyx ? BorderSide(color: t.line) : BorderSide.none),
      ),
    );
  }
}

// ── Фильтр ──────────────────────────────────────────────────────────────────

class _FacetRow extends StatelessWidget {
  const _FacetRow({required this.value, required this.voiceCount, required this.aiCount, required this.countries, required this.onChanged});
  final _Facets value;
  final int voiceCount, aiCount;

  /// Код → название; '' — «Другие».
  final Map<String, String> countries;
  final ValueChanged<_Facets> onChanged;

  Future<void> _pickCountry(BuildContext context) async {
    final t = OnyxTokens.of(context);
    final box = context.findRenderObject() as RenderBox?;
    final pos = box == null ? Offset.zero : box.localToGlobal(Offset.zero);
    final sorted = countries.entries.toList()..sort((a, b) => a.value.compareTo(b.value));
    final picked = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx + 120, pos.dy + 40, pos.dx + 360, 0),
      color: t.isMaterial ? null : t.surfaceHigh,
      items: [
        PopupMenuItem(value: '*', child: Text('Все страны', style: TextStyle(fontFamily: t.bodyFont, color: t.text))),
        for (final e in sorted)
          PopupMenuItem(
            value: e.key,
            child: Row(children: [
              CountryFlag(code: e.key, size: 20),
              const SizedBox(width: 10),
              Text(e.value, style: TextStyle(fontFamily: t.bodyFont, color: t.text)),
            ]),
          ),
      ],
    );
    if (picked == null) return;
    onChanged(picked == '*' ? value.copy(clearCountry: true) : value.copy(country: picked));
  }

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    final countryLabel = value.country == null ? 'Страны' : (countries[value.country] ?? 'Страна');
    final chips = <(String, bool, VoidCallback, OnyxGlyph?)>[
      ('Голос · $voiceCount', value.voice, () => onChanged(value.copy(voice: !value.voice)), OnyxGlyph.voice),
      ('AI · $aiCount', value.ai, () => onChanged(value.copy(ai: !value.ai)), null),
      (countryLabel, value.country != null, () => _pickCountry(context), OnyxGlyph.chevronDown),
    ];
    if (t.isMaterial) {
      return Wrap(spacing: 8, children: [
        for (final c in chips)
          FilterChip(
            label: Text(c.$1),
            avatar: c.$4 != null && !c.$2 ? Icon(c.$4!.material, size: 18) : null,
            selected: c.$2,
            onSelected: (_) => c.$3(),
          ),
      ]);
    }
    return Wrap(spacing: t.isSignal ? 8 : 6, runSpacing: 6, children: [
      for (final c in chips)
        GestureDetector(
          onTap: c.$3,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: t.isSignal ? 8 : 6),
            decoration: BoxDecoration(
              color: c.$2 && t.isSignal ? t.text : (t.isSignal ? t.surfaceHigh : Colors.transparent),
              borderRadius: BorderRadius.circular(16),
              border: t.isOnyx ? Border.all(color: c.$2 ? const Color(0xFF3A3326) : t.line) : null,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (c.$4 != null) ...[
                OnyxIcon(c.$4!, size: 12, color: c.$2 ? (t.isSignal ? t.bg : t.accent) : t.textFaint),
                const SizedBox(width: 6),
              ],
              Text(
                c.$1.toUpperCase(),
                style: t.caps(size: 10.5, color: c.$2 ? (t.isSignal ? t.bg : t.accent) : t.textMuted),
              ),
            ]),
          ),
        ),
    ]);
  }
}

// ── «Автовыбор» ─────────────────────────────────────────────────────────────

class _AutoRow extends StatelessWidget {
  const _AutoRow({required this.pad, required this.auto, required this.group, required this.onChanged, required this.onPickGroup});
  final double pad;
  final bool auto;
  final ValueChanged<bool> onChanged;

  /// Из какой группы автовыбор берёт сервер.
  final String group;
  final VoidCallback onPickGroup;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    final s = Theme.of(context).colorScheme;
    final Widget lead = t.isMaterial
        ? SizedBox.square(
            dimension: 40,
            child: Stack(alignment: Alignment.center, children: [
              ClipPath(clipper: PolygonClipper(MaterialShapes.softBurst), child: ColoredBox(color: s.tertiaryContainer, child: const SizedBox.expand())),
              Icon(Icons.bolt_rounded, size: 20, color: s.onTertiaryContainer),
            ]),
          )
        : t.isSignal
            ? OnyxIcon(OnyxGlyph.zap, size: 20, color: t.text)
            : Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF3A3326))),
                alignment: Alignment.center,
                child: OnyxIcon(OnyxGlyph.zap, size: 15, color: t.accent),
              );
    final subtitle = 'Из «$group» · лучший по пингу и AI';
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 6, pad, 4),
      child: Material(
        color: t.isMaterial ? s.surfaceContainer : (t.isSignal ? t.surface : t.bg),
        borderRadius: BorderRadius.circular(t.isMaterial ? 20 : (t.isSignal ? 20 : 18)),
        child: InkWell(
          borderRadius: BorderRadius.circular(t.isMaterial ? 20 : 18),
          onTap: () => onChanged(!auto),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: t.isMaterial ? 12 : 16, vertical: t.isMaterial ? 12 : 13),
            decoration: t.isOnyx ? BoxDecoration(borderRadius: BorderRadius.circular(18), border: Border.all(color: t.line)) : null,
            child: Row(children: [
              lead,
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Автовыбор',
                      style: t.isMaterial
                          ? Theme.of(context).textTheme.titleMedium
                          : TextStyle(fontFamily: t.bodyFont, fontSize: 14.5, fontWeight: FontWeight.w500, color: t.text)),
                  const SizedBox(height: 2),
                  Text(t.isSignal ? subtitle.toUpperCase() : subtitle,
                      style: t.isMaterial
                          ? Theme.of(context).textTheme.bodyMedium!.copyWith(color: s.onSurfaceVariant)
                          : t.isSignal
                              ? t.caps(size: 9.5, color: t.textFaint)
                              : TextStyle(fontFamily: t.bodyFont, fontSize: 12, color: t.textMuted)),
                ]),
              ),
              IconButton(
                tooltip: 'Группа для автовыбора',
                visualDensity: VisualDensity.compact,
                onPressed: onPickGroup,
                icon: OnyxIcon(OnyxGlyph.sliders, size: t.isMaterial ? 22 : 16, color: t.textMuted),
              ),
              OnyxSwitch(value: auto, onChanged: onChanged),
            ]),
          ),
        ),
      ),
    );
  }

}

// ── Группа и строка ─────────────────────────────────────────────────────────

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.name, required this.count, required this.pad});
  final String name;
  final int count;
  final double pad;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    if (t.isMaterial) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Text(name, style: Theme.of(context).textTheme.titleSmall!.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 16, pad, 6),
      child: Row(children: [
        Expanded(child: Text(name.toUpperCase(), style: t.caps(size: 10.5, color: t.textFaint))),
        Text(t.isSignal ? count.toString().padLeft(2, '0') : '$count', style: t.caps(size: 10.5, color: t.textFaint)),
      ]),
    );
  }
}

class _MaterialSegment extends StatelessWidget {
  const _MaterialSegment({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 2),
          _SegmentPosition(first: i == 0, last: i == children.length - 1, child: children[i]),
        ],
      ]);
}

/// Позиция строки в сегментированной группе (радиусы 20 по краям, 4 внутри).
class _SegmentPosition extends InheritedWidget {
  const _SegmentPosition({required this.first, required this.last, required super.child});
  final bool first, last;

  static _SegmentPosition? of(BuildContext c) => c.dependOnInheritedWidgetOfExactType<_SegmentPosition>();

  BorderRadius get radius => BorderRadius.vertical(
        top: Radius.circular(first ? 20 : 4),
        bottom: Radius.circular(last ? 20 : 4),
      );

  @override
  bool updateShouldNotify(_SegmentPosition old) => old.first != first || old.last != last;
}

class _NodeRow extends StatelessWidget {
  const _NodeRow({
    required this.node,
    required this.country,
    required this.selected,
    required this.favorite,
    required this.onFavorite,
    required this.onLongPress,
    required this.onTap,
    this.quarantined = false,
    this.inOwnList = false,
  });
  final Node node;

  /// Строка во вкладке или секции «Свои»: значок «СВОЙ» там лишний — заголовок
  /// уже это говорит, а место нужно имени.
  final bool inOwnList;

  /// Страна для флага: выбор пользователя → название (CountryResolver, #68).
  final Country country;
  final bool selected;

  /// Не поднялся при подключении — автовыбор пропускает его 30 мин (#45).
  final bool quarantined;
  final VoidCallback onTap;
  final bool favorite;
  final VoidCallback onFavorite, onLongPress;

  Widget _star(OnyxTokens t) => IconButton(
        tooltip: favorite ? 'Убрать из избранного' : 'В избранное',
        visualDensity: VisualDensity.compact,
        onPressed: () {
          HapticFeedback.selectionClick();
          onFavorite();
        },
        icon: favorite
            ? Icon(Icons.star_rounded, size: t.isMaterial ? 22 : 16, color: t.isSignal ? t.text : t.accent)
            : OnyxIcon(OnyxGlyph.star, size: t.isMaterial ? 22 : 16, color: t.isSignal ? t.lineStrong : t.line),
      );

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    final c = country;
    final name = displayNodeName(node.name);
    final dead = !node.isAlive || quarantined;

    if (t.isMaterial) {
      final s = Theme.of(context).colorScheme;
      final text = Theme.of(context).textTheme;
      final r = selected ? BorderRadius.circular(20) : (_SegmentPosition.of(context)?.radius ?? BorderRadius.circular(20));
      return Material(
        color: selected ? s.secondaryContainer : s.surfaceContainer,
        borderRadius: r,
        child: InkWell(
          borderRadius: r,
          onTap: onTap,
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 64),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
              child: Row(children: [
                Opacity(opacity: dead ? 0.4 : 1, child: CountryFlag(code: c.code, size: 40)),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleMedium!.copyWith(color: selected ? s.onSecondaryContainer : s.onSurface)),
                    Text(node.latencyMs == null ? (dead ? 'Недоступен' : '—') : '${node.latencyMs} мс',
                        style: text.bodyMedium!.copyWith(color: s.onSurfaceVariant)),
                  ]),
                ),
                NodeBadges(node: node, showOwn: !inOwnList),
                const SizedBox(width: 10),
                PingIndicator(ms: dead ? null : node.latencyMs),
                _star(t),
                if (selected) ...[const SizedBox(width: 10), Icon(Icons.check_rounded, size: 22, color: s.onSecondaryContainer)],
              ]),
            ),
          ),
        ),
      );
    }

    if (t.isSignal) {
      return InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          color: selected ? t.surface : null,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? AppTheme.signalRec : null,
                border: selected ? null : Border.all(color: t.textFaint, width: 1.5),
              ),
            ),
            const SizedBox(width: 12),
            Opacity(opacity: dead ? 0.35 : 1, child: CountryFlag(code: c.code, size: 22)),
            const SizedBox(width: 14),
            Expanded(
              child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: t.bodyFont, fontSize: 16, color: dead ? t.textFaint : t.text)),
            ),
            NodeBadges(node: node, showOwn: !inOwnList),
            const SizedBox(width: 10),
            PingText(ms: dead ? null : node.latencyMs, width: 36),
            const SizedBox(width: 8),
            PingIndicator(ms: dead ? null : node.latencyMs),
            _star(t),
          ]),
        ),
      );
    }

    // Onyx
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: selected
            ? BoxDecoration(
                gradient: LinearGradient(colors: [t.accent.withValues(alpha: 0.07), t.accent.withValues(alpha: 0)], stops: const [0, 0.7]),
                border: Border(left: BorderSide(color: t.accent, width: 2)),
              )
            : null,
        child: Row(children: [
          Opacity(opacity: dead ? 0.4 : 1, child: CountryFlag(code: c.code, size: 30)),
          const SizedBox(width: 14),
          Expanded(
            child: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontFamily: t.bodyFont, fontSize: 15, color: selected ? t.accent : (dead ? t.textFaint : t.text))),
          ),
          NodeBadges(node: node, showOwn: !inOwnList),
          const SizedBox(width: 12),
          PingText(ms: dead ? null : node.latencyMs, width: 52),
          _star(t),
        ]),
      ),
    );
  }
}

// ── Подвал ──────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  const _Footer({required this.pad, required this.total, required this.sources, required this.onSources});
  final double pad;
  final int total, sources;
  final VoidCallback onSources;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    final left = '$total серверов · $sources ${sources == 1 ? 'источник' : (sources > 1 && sources < 5 ? 'источника' : 'источников')}';
    final style = t.isSignal
        ? t.caps(size: 10, color: t.textFaint)
        : t.isMaterial
            ? Theme.of(context).textTheme.bodySmall!.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)
            : TextStyle(fontFamily: t.bodyFont, fontSize: 12, color: t.textMuted);
    return Container(
      padding: EdgeInsets.fromLTRB(pad, 4, pad - 8, 6 + MediaQuery.paddingOf(context).bottom),
      decoration: t.isMaterial ? null : BoxDecoration(border: Border(top: BorderSide(color: t.line))),
      child: Row(children: [
        Expanded(child: Text(t.isSignal ? left.toUpperCase() : left, style: style)),
        TextButton.icon(
          onPressed: onSources,
          icon: OnyxIcon(OnyxGlyph.sliders, size: 14, color: t.textMuted),
          label: Text(t.isSignal ? 'ПОДПИСКИ' : 'Подписки и серверы', style: style),
        ),
      ]),
    );
  }
}

// ── Вкладки групп ───────────────────────────────────────────────────────────

class _GroupTabs extends StatelessWidget {
  const _GroupTabs({required this.pad, required this.value, required this.tabs, required this.onChanged, required this.onAdd});
  final double pad;
  final String? value;
  final List<(String?, String, int)> tabs;
  final ValueChanged<String?> onChanged;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    Widget tab((String?, String, int) e) {
      final on = e.$1 == value;
      if (t.isMaterial) {
        return ChoiceChip(label: Text('${e.$2} · ${e.$3}'), selected: on, onSelected: (_) => onChanged(e.$1));
      }
      return GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onChanged(e.$1);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: t.isSignal ? 8 : 7),
          decoration: BoxDecoration(
            color: on ? t.text : (t.isSignal ? t.surfaceHigh : Colors.transparent),
            borderRadius: BorderRadius.circular(18),
            border: t.isOnyx ? Border.all(color: on ? t.text : t.line) : null,
          ),
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: t.isSignal ? e.$2.toUpperCase() : e.$2),
              TextSpan(text: '  ${e.$3}', style: TextStyle(color: on ? t.textFaint : t.textFaint)),
            ]),
            style: t.isSignal
                ? t.caps(size: 11, color: on ? t.bg : t.textMuted)
                : TextStyle(fontFamily: t.bodyFont, fontSize: 12.5, fontWeight: FontWeight.w500, color: on ? t.bg : t.textMuted),
          ),
        ),
      );
    }

    return SizedBox(
      height: t.isMaterial ? 40 : 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: pad),
        children: [
          for (final e in tabs) ...[tab(e), const SizedBox(width: 6)],
          Tooltip(
            message: 'Новая группа',
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: onAdd,
              child: Container(
                width: t.isMaterial ? 40 : 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: t.isSignal ? t.surfaceHigh : null,
                  border: t.isOnyx || t.isMaterial ? Border.all(color: t.line) : null,
                ),
                child: OnyxIcon(OnyxGlyph.plus, size: 14, color: t.textMuted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
