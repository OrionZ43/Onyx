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
import '../providers/node_provider.dart';
import '../providers/subscription_provider.dart';
import '../providers/vpn_provider.dart';
import '../screens/subscription_manager_screen.dart';
import '../util/country.dart';
import 'country_flag.dart';
import 'home_parts.dart';
import 'onyx_icon.dart';
import 'onyx_switch.dart';
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

enum _Filter { all, ai, verified }

class NodeListPanel extends ConsumerStatefulWidget {
  const NodeListPanel({super.key, this.inSheet = false});
  final bool inSheet;

  @override
  ConsumerState<NodeListPanel> createState() => _NodeListPanelState();
}

class _NodeListPanelState extends ConsumerState<NodeListPanel> {
  final _query = TextEditingController();
  _Filter _filter = _Filter.all;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _select(Node node) {
    HapticFeedback.selectionClick();
    ref.read(nodeSelectionProvider.notifier).select(node);
    final vpn = ref.read(vpnControllerProvider);
    if (vpn is VpnConnected && vpn.node.id != node.id) {
      // Смена сервера на ходу: переподключаемся к выбранному.
      final ctl = ref.read(vpnControllerProvider.notifier);
      ctl.disconnect().then((_) => ctl.connect(node));
    }
    if (widget.inSheet && mounted) Navigator.of(context).maybePop();
  }

  void _setAuto(bool auto) {
    final sub = ref.read(subscriptionProvider);
    if (auto) {
      ref.read(nodeSelectionProvider.notifier).clear();
    } else if (sub.bestNode != null) {
      ref.read(nodeSelectionProvider.notifier).select(sub.bestNode!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    final sub = ref.watch(subscriptionProvider);
    final picked = ref.watch(nodeSelectionProvider);
    final vpn = ref.watch(vpnControllerProvider);
    final current = vpn is VpnConnected ? vpn.node : (picked ?? sub.bestNode);
    final pad = t.isMaterial ? 16.0 : 20.0;

    if (sub.nodes.isEmpty && sub.status != SubStatus.fetching) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: pad),
        child: const SubscriptionImport(),
      );
    }

    final q = _query.text.trim().toLowerCase();
    final nodes = sub.nodes.where((n) {
      if (_filter == _Filter.ai && !n.aiReachable) return false;
      if (_filter == _Filter.verified && !n.isTrulyWorking) return false;
      if (q.isEmpty) return true;
      final c = countryOfName(n.name);
      return n.name.toLowerCase().contains(q) || c.name.toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) {
        if (a.isAlive != b.isAlive) return a.isAlive ? -1 : 1;
        return (a.latencyMs ?? 99999).compareTo(b.latencyMs ?? 99999);
      });

    // Группы по стране; порядок — по лучшему пингу в группе.
    final groups = <String, List<Node>>{};
    final names = <String, String>{};
    for (final n in nodes) {
      final c = countryOfName(n.name);
      groups.putIfAbsent(c.code, () => []).add(n);
      names[c.code] = c.name;
    }
    final aiCount = sub.nodes.where((n) => n.aiReachable).length;
    final verified = sub.nodes.where((n) => n.isTrulyWorking).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(
          pad: pad,
          busy: sub.status == SubStatus.fetching || sub.status == SubStatus.probing || sub.status == SubStatus.deepProbing,
          onRefresh: () {
            final url = ref.read(subscriptionProvider).url;
            if (url.isNotEmpty) ref.read(subscriptionProvider.notifier).loadFromUrl(url);
          },
          onAdd: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SubscriptionManagerScreen())),
        ),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: pad),
          child: TextField(
            controller: _query,
            onChanged: (_) => setState(() {}),
            style: TextStyle(fontFamily: t.bodyFont, fontSize: t.isMaterial ? 16 : 14, color: t.text),
            decoration: InputDecoration(
              hintText: t.isMaterial ? 'Страна, город, сервер' : 'Страна, город или сервер',
              isDense: !t.isMaterial,
              prefixIcon: Padding(
                padding: const EdgeInsets.only(left: 14, right: 10),
                child: OnyxIcon(OnyxGlyph.search, size: t.isMaterial ? 24 : 16, color: t.textFaint),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
            ),
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 12, pad, 4),
          child: _FilterRow(
            value: _filter,
            counts: {_Filter.all: sub.nodes.length, _Filter.ai: aiCount, _Filter.verified: verified},
            onChanged: (f) => setState(() => _filter = f),
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.only(top: 6, bottom: 16, left: t.isMaterial ? pad : 0, right: t.isMaterial ? pad : 0),
            children: [
              _AutoRow(pad: t.isMaterial ? 0 : pad, auto: picked == null, onChanged: _setAuto),
              for (final e in groups.entries) ...[
                _GroupHeader(name: names[e.key]!, count: e.value.length, pad: t.isMaterial ? 0 : pad),
                if (t.isMaterial)
                  _MaterialSegment(
                    children: [for (final n in e.value) _NodeRow(node: n, selected: n.id == current?.id, onTap: () => _select(n))],
                  )
                else
                  for (final n in e.value) _NodeRow(node: n, selected: n.id == current?.id, onTap: () => _select(n)),
              ],
              if (nodes.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text('Ничего не найдено', textAlign: TextAlign.center, style: TextStyle(fontFamily: t.bodyFont, color: t.textMuted)),
                ),
            ],
          ),
        ),
        _Footer(pad: pad, total: sub.nodes.length, ai: aiCount, fetchedAt: sub.lastFetchedAt),
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

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.value, required this.counts, required this.onChanged});
  final _Filter value;
  final Map<_Filter, int> counts;
  final ValueChanged<_Filter> onChanged;

  static const _labels = {_Filter.all: 'Все', _Filter.ai: 'AI', _Filter.verified: 'Проверенные'};

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    if (t.isMaterial) {
      return Wrap(spacing: 8, children: [
        for (final f in _Filter.values)
          FilterChip(
            label: Text(f == _Filter.ai ? 'AI-проба' : _labels[f]!),
            avatar: f == _Filter.ai && value != f ? const Icon(Icons.auto_awesome_outlined, size: 18) : null,
            selected: value == f,
            onSelected: (_) => onChanged(f),
          ),
      ]);
    }
    return Wrap(spacing: t.isSignal ? 8 : 6, runSpacing: 6, children: [
      for (final f in _Filter.values)
        GestureDetector(
          onTap: () => onChanged(f),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: EdgeInsets.symmetric(horizontal: 14, vertical: t.isSignal ? 8 : 7),
            decoration: BoxDecoration(
              color: value == f ? t.text : (t.isSignal ? t.surfaceHigh : Colors.transparent),
              borderRadius: BorderRadius.circular(18),
              border: t.isOnyx ? Border.all(color: value == f ? t.text : t.line) : null,
            ),
            child: Text(
              t.isSignal ? '${_labels[f]!.toUpperCase()} ${counts[f]}' : '${_labels[f]} · ${counts[f]}',
              style: t.isSignal
                  ? t.caps(size: 11, color: value == f ? t.bg : t.textMuted)
                  : TextStyle(fontFamily: t.bodyFont, fontSize: 12, fontWeight: FontWeight.w500, color: value == f ? t.bg : t.textMuted),
            ),
          ),
        ),
    ]);
  }
}

// ── «Автовыбор» ─────────────────────────────────────────────────────────────

class _AutoRow extends StatelessWidget {
  const _AutoRow({required this.pad, required this.auto, required this.onChanged});
  final double pad;
  final bool auto;
  final ValueChanged<bool> onChanged;

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
    final subtitle = 'Лучший по задержке и AI-пробе';
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
  const _NodeRow({required this.node, required this.selected, required this.onTap});
  final Node node;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    final c = countryOfName(node.name);
    final name = displayNodeName(node.name);
    final dead = !node.isAlive;

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
                if (node.aiReachable) ...[const AiBadge(), const SizedBox(width: 10)],
                PingIndicator(ms: dead ? null : node.latencyMs),
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
            if (node.aiReachable) ...[const AiBadge(), const SizedBox(width: 10)],
            PingText(ms: dead ? null : node.latencyMs, width: 36),
            const SizedBox(width: 8),
            PingIndicator(ms: dead ? null : node.latencyMs),
          ]),
        ),
      );
    }

    // Onyx
    return InkWell(
      onTap: onTap,
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
          if (node.aiReachable) ...[const AiBadge(), const SizedBox(width: 12)],
          PingText(ms: dead ? null : node.latencyMs, width: 52),
        ]),
      ),
    );
  }
}

// ── Подвал ──────────────────────────────────────────────────────────────────

class _Footer extends StatelessWidget {
  const _Footer({required this.pad, required this.total, required this.ai, required this.fetchedAt});
  final double pad;
  final int total, ai;
  final DateTime? fetchedAt;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    final ago = fetchedAt == null ? '' : _ago(DateTime.now().difference(fetchedAt!));
    final left = '$total серверов · $ai AI';
    final right = ago.isEmpty ? '' : 'Проверено $ago';
    final style = t.isSignal
        ? t.caps(size: 10, color: t.textFaint)
        : t.isMaterial
            ? Theme.of(context).textTheme.bodySmall!.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)
            : TextStyle(fontFamily: t.bodyFont, fontSize: 12, color: t.textMuted);
    return Container(
      padding: EdgeInsets.fromLTRB(pad, 12, pad, 14 + MediaQuery.paddingOf(context).bottom),
      decoration: t.isMaterial ? null : BoxDecoration(border: Border(top: BorderSide(color: t.line))),
      child: Row(children: [
        Expanded(child: Text(t.isSignal ? left.toUpperCase() : left, style: style)),
        Text(t.isSignal ? right.toUpperCase() : right, style: style),
      ]),
    );
  }

  static String _ago(Duration d) {
    if (d.inMinutes < 1) return 'только что';
    if (d.inHours < 1) return '${d.inMinutes} мин назад';
    if (d.inDays < 1) return '${d.inHours} ч назад';
    return '${d.inDays} дн назад';
  }
}
