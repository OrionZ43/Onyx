// Мини-панель Onyx у значка в трее (#46) — вместо стандартного меню Windows.
//
// Показывается в том же окне приложения, переведённом в «режим панели»
// (см. main.dart: маленькое окно поверх всех, без кнопки на панели задач,
// у значка трея; скругление и тень даёт Windows 11). Поэтому провайдеры и
// логика общие с главным экраном — здесь только вид.
//
// Страницы: главная — «одна кнопка» (статус, мини-«Линза», таймер и трафик,
// сервер, «Открыть Onyx», «Выход»; Discord и регион — только в Настройках,
// #47) и выбор сервера (группы, автовыбор, список).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/onyx_tokens.dart';
import '../../domain/entities/node.dart';
import '../../domain/entities/vpn_state.dart';
import '../providers/connect_phase.dart';
import '../providers/groups_provider.dart';
import '../providers/node_provider.dart';
import '../providers/subscription_provider.dart';
import '../providers/vpn_provider.dart';
import '../screens/groups_screen.dart' show kAutoGroups, groupLabel;
import '../util/country.dart';
import '../util/vpn_actions.dart';
import '../widgets/country_flag.dart';
import '../widgets/hero/hero_button.dart';
import '../widgets/hero/hero_state.dart';
import '../widgets/home_parts.dart';
import '../widgets/onyx_icon.dart';
import '../widgets/onyx_toast.dart';
import '../widgets/onyx_wordmark.dart';

class TrayFlyout extends ConsumerStatefulWidget {
  const TrayFlyout({
    super.key,
    required this.onOpenApp,
    required this.onExit,
    required this.onDismiss,
    this.showId = 0,
  });

  /// Открыть полное окно Onyx.
  final VoidCallback onOpenApp;
  final VoidCallback onExit;

  /// Спрятать панель (Esc).
  final VoidCallback onDismiss;

  /// Меняется при каждом показе — перезапускает анимацию появления.
  final int showId;

  static const Size size = Size(360, 396);

  @override
  ConsumerState<TrayFlyout> createState() => _TrayFlyoutState();
}

class _TrayFlyoutState extends ConsumerState<TrayFlyout> with SingleTickerProviderStateMixin {
  late final AnimationController _in = AnimationController(vsync: this, duration: const Duration(milliseconds: 220))..forward();
  bool _servers = false;

  @override
  void didUpdateWidget(TrayFlyout old) {
    super.didUpdateWidget(old);
    if (old.showId != widget.showId) {
      _servers = false;
      _in.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _in.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    final bg = switch (t.kind.name) {
      'signal' => const Color(0xFF000000),
      'material' => Theme.of(context).colorScheme.surfaceContainerLow,
      _ => const Color(0xFF0A0A0C),
    };
    final curved = CurvedAnimation(parent: _in, curve: Curves.easeOutCubic);
    return Focus(
      autofocus: true,
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.escape) {
          if (_servers) {
            setState(() => _servers = false);
          } else {
            widget.onDismiss();
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Material(
        color: bg,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: t.isOnyx ? Border.all(color: t.line) : null,
            gradient: t.isOnyx
                ? const RadialGradient(center: Alignment(0, -1.3), radius: 1.2, colors: [Color(0xFF19191C), Color(0xFF0A0A0C)])
                : null,
          ),
          child: FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween(begin: const Offset(0, .025), end: Offset.zero).animate(curved),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                switchInCurve: Curves.easeOutCubic,
                transitionBuilder: (child, a) => FadeTransition(
                  opacity: a,
                  child: SlideTransition(position: Tween(begin: const Offset(.04, 0), end: Offset.zero).animate(a), child: child),
                ),
                child: _servers
                    ? _ServerPage(key: const ValueKey('servers'), onBack: () => setState(() => _servers = false))
                    : _MainPage(
                        key: const ValueKey('main'),
                        onServers: () => setState(() => _servers = true),
                        onOpenApp: widget.onOpenApp,
                        onExit: widget.onExit,
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Главная страница ────────────────────────────────────────────────────────

class _MainPage extends ConsumerWidget {
  const _MainPage({super.key, required this.onServers, required this.onOpenApp, required this.onExit});
  final VoidCallback onServers, onOpenApp, onExit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = OnyxTokens.of(context);
    final vpn = ref.watch(vpnControllerProvider);
    final picked = ref.watch(nodeSelectionProvider);
    final auto = ref.watch(autoNodeProvider);
    final autoGroup = ref.watch(autoGroupProvider);
    final groups = ref.watch(groupsProvider);
    // Этап автопилота (обновляю / проверяю / не удалось) поверх состояния VPN.
    final ap = AutopilotView.of(vpn, ref.watch(connectPhaseProvider));
    final failure = ap?.failure;
    final phase = ap?.phase ?? heroPhaseOf(vpn);
    final Node? node = switch (vpn) {
      VpnConnected(node: final n) || VpnConnecting(node: final n) || VpnDisconnecting(node: final n) => n,
      _ => picked ?? auto,
    };

    final (String key, Color keyColor) = switch (phase) {
      HeroPhase.on => (t.isSignal ? 'Защита активна' : 'Защищено', t.isSignal ? t.text : t.accent),
      HeroPhase.connecting => (vpn is VpnDisconnecting ? 'Отключение' : 'Подключение', t.isSignal ? t.text : t.accentMuted),
      HeroPhase.error => ('Нет соединения', t.danger),
      HeroPhase.off => ('Не защищено', t.textMuted),
    };
    final dot = switch (phase) {
      HeroPhase.on => t.isSignal ? AppTheme.signalRec : t.accent,
      HeroPhase.error => t.danger,
      HeroPhase.connecting => t.accentMuted,
      HeroPhase.off => t.textFaint,
    };

    Future<void> toggle() async {
      HapticFeedback.lightImpact();
      final r = await toggleConnection(ref);
      if (r == ToggleResult.busy && context.mounted) showOnyxToast(context, 'Onyx уже подключается — пара секунд', glyph: OnyxGlyph.clock);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Шапка: знак и статус.
        Row(children: [
          const OnyxWordmark(size: 11),
          const Spacer(),
          Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: dot, boxShadow: phase == HeroPhase.on ? [BoxShadow(color: dot, blurRadius: 8)] : null)),
          const SizedBox(width: 7),
          Text(key.toUpperCase(), style: t.caps(size: 10, color: keyColor)),
        ]),
        const Spacer(),
        // «Одна кнопка» и под ней — таймер с трафиком или состояние.
        Center(child: HeroButton(vpn: vpn, phase: ap?.phase, progress: ap?.progress, label: ap?.label, size: failure != null ? 104 : 128, compact: true, onTap: toggle)),
        const SizedBox(height: 14),
        if (vpn is VpnConnected) ...[
          SecondTicker(active: true, builder: (_) => Text(formatClock(vpn.uptime), textAlign: TextAlign.center, style: t.numbers(size: 26))),
          const SizedBox(height: 4),
          Text('↓ ${formatBytes(vpn.rxBytes)}   ↑ ${formatBytes(vpn.txBytes)}',
              textAlign: TextAlign.center,
              style: t.caps(size: 10, color: t.textMuted).copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        ] else ...[
          Text(
            ap?.title ??
                switch (phase) {
                  HeroPhase.connecting => node == null ? '…' : displayNodeName(node.name),
                  HeroPhase.error => 'Сервер не ответил',
                  _ => 'Трафик открыт',
                },
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: t.displayFont, fontSize: 20, height: 1.2, fontWeight: t.isSignal ? FontWeight.w500 : FontWeight.w300, letterSpacing: -0.4, color: t.text),
          ),
          const SizedBox(height: 4),
          Text(
            ap?.detail ??
                (phase == HeroPhase.off
                    ? 'Нажмите, чтобы подключиться'
                    : (phase == HeroPhase.error ? 'Нажмите, чтобы повторить' : 'Нажмите, чтобы отменить')),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: t.bodyFont, fontSize: 12, height: 1.3, color: t.textMuted),
          ),
          // Отказ автопилота: повторить отсюда; добавить сервер — в окне Onyx.
          if (failure != null && failure.actions.contains(ConnectAction.refresh)) ...[
            const SizedBox(height: 10),
            PhaseActions(actions: [('Обновить и повторить', () => ref.read(vpnControllerProvider.notifier).smartConnect())]),
          ],
        ],
        const Spacer(),
        // Сервер → выбор. При отказе автопилота места нет — сервер меняют в
        // окне Onyx («Открыть Onyx» ниже).
        if (failure == null) ...[
        _Tile(
          onTap: onServers,
          child: Row(children: [
            CountryFlag(code: node == null ? '' : countryOfName(node.name).code, size: t.isSignal ? 24 : 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(node == null ? 'Нет серверов' : displayNodeName(node.name),
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontFamily: t.bodyFont, fontSize: 14, fontWeight: FontWeight.w500, color: t.text)),
                const SizedBox(height: 2),
                Text(
                  picked == null ? 'Автовыбор · из «${groupLabel(autoGroup, groups)}»' : 'Выбран вручную',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.isSignal ? t.caps(size: 9.5, color: t.textFaint) : TextStyle(fontFamily: t.bodyFont, fontSize: 11.5, color: t.textMuted),
                ),
              ]),
            ),
            if (node != null) PingText(ms: node.latencyMs),
            const SizedBox(width: 6),
            OnyxIcon(OnyxGlyph.chevronRight, size: 14, color: t.textFaint),
          ]),
        ),
        const SizedBox(height: 12),
        ],
        // Низ: открыть приложение / выход.
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onOpenApp,
              icon: OnyxIcon(OnyxGlyph.globe, size: 15, color: t.text),
              label: Text(t.isSignal ? 'ОТКРЫТЬ ONYX' : 'Открыть Onyx'),
              style: OutlinedButton.styleFrom(
                foregroundColor: t.text,
                backgroundColor: t.isSignal ? t.surfaceHigh : null,
                side: t.isOnyx ? BorderSide(color: t.line) : BorderSide.none,
                minimumSize: const Size(0, 40),
                shape: const StadiumBorder(),
                textStyle: t.isSignal ? t.caps(size: 10.5, weight: FontWeight.w600) : TextStyle(fontFamily: t.bodyFont, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: onExit,
            style: TextButton.styleFrom(foregroundColor: t.textMuted, minimumSize: const Size(0, 40), shape: const StadiumBorder()),
            child: Text(t.isSignal ? 'ВЫХОД' : 'Выход', style: t.isSignal ? t.caps(size: 10.5) : TextStyle(fontFamily: t.bodyFont, fontSize: 13)),
          ),
        ]),
      ]),
    );
  }
}

// ── Выбор сервера ───────────────────────────────────────────────────────────

class _ServerPage extends ConsumerStatefulWidget {
  const _ServerPage({super.key, required this.onBack});
  final VoidCallback onBack;

  @override
  ConsumerState<_ServerPage> createState() => _ServerPageState();
}

class _ServerPageState extends ConsumerState<_ServerPage> {
  late String? _group = ref.read(autoGroupProvider);

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    final userGroups = ref.watch(groupsProvider);
    final picked = ref.watch(nodeSelectionProvider);
    final autoGroup = ref.watch(autoGroupProvider);
    final vpn = ref.watch(vpnControllerProvider);
    final current = vpn is VpnConnected ? vpn.node : picked;
    final base = _group == null ? ref.watch(subscriptionProvider.select((s) => s.nodes)) : ref.watch(groupNodesProvider(_group!));
    final nodes = [...base.where((n) => n.isAlive)]..sort((a, b) => (a.latencyMs ?? 99999).compareTo(b.latencyMs ?? 99999));
    final chips = <(String?, String)>[
      ...kAutoGroups.entries.map((e) => (e.key, e.value)),
      ...userGroups.map((g) => (g.id, g.name)),
    ];
    final autoHere = picked == null && autoGroup == _group;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          IconButton(
            tooltip: 'Назад',
            onPressed: widget.onBack,
            icon: OnyxIcon(OnyxGlyph.back, size: 16, color: t.text),
          ),
          Text('Сервер',
              style: TextStyle(fontFamily: t.displayFont, fontSize: 18, fontWeight: t.isSignal ? FontWeight.w500 : FontWeight.w400, color: t.text)),
        ]),
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              for (final c in chips) ...[
                _Chip(label: c.$2, selected: c.$1 == _group, onTap: () => setState(() => _group = c.$1)),
                const SizedBox(width: 6),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        _Row(
          selected: autoHere,
          onTap: () async {
            HapticFeedback.selectionClick();
            await chooseAutoGroup(ref, _group);
            widget.onBack();
          },
          lead: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: t.isOnyx ? const Color(0xFF3A3326) : t.lineStrong)),
            alignment: Alignment.center,
            child: OnyxIcon(OnyxGlyph.zap, size: 13, color: t.isSignal ? t.text : t.accent),
          ),
          title: 'Автовыбор',
          subtitle: 'Лучший из «${groupLabel(_group, userGroups)}»',
        ),
        Expanded(
          child: nodes.isEmpty
              ? Center(child: Text('В группе нет доступных серверов', style: TextStyle(fontFamily: t.bodyFont, fontSize: 12.5, color: t.textMuted)))
              : ListView.builder(
                  padding: EdgeInsets.zero,
                  itemCount: nodes.length,
                  itemBuilder: (_, i) {
                    final n = nodes[i];
                    return _Row(
                      selected: n.id == current?.id && picked != null,
                      onTap: () async {
                        HapticFeedback.selectionClick();
                        await chooseNode(ref, n);
                        widget.onBack();
                      },
                      lead: CountryFlag(code: countryOfName(n.name).code, size: t.isSignal ? 20 : 26),
                      title: displayNodeName(n.name),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [NodeBadges(node: n), const SizedBox(width: 8), PingText(ms: n.latencyMs, width: 44)]),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

// ── Детали ──────────────────────────────────────────────────────────────────

class _Tile extends StatelessWidget {
  const _Tile({required this.child, this.onTap});
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    final r = BorderRadius.circular(t.isMaterial ? 16 : 14);
    return Material(
      color: t.isMaterial ? Theme.of(context).colorScheme.surfaceContainer : (t.isSignal ? t.surface : const Color(0xFF111114)),
      borderRadius: r,
      child: InkWell(
        borderRadius: r,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: t.isOnyx ? BoxDecoration(borderRadius: r, border: Border.all(color: t.line)) : null,
          child: child,
        ),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.selected, required this.onTap, required this.lead, required this.title, this.subtitle, this.trailing});
  final bool selected;
  final VoidCallback onTap;
  final Widget lead;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: selected
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: t.isSignal ? t.surface : t.accent.withValues(alpha: .06),
                border: t.isOnyx ? Border.all(color: const Color(0xFF3A3326)) : null,
              )
            : null,
        child: Row(children: [
          lead,
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontFamily: t.bodyFont, fontSize: 13.5, fontWeight: FontWeight.w500, color: selected && t.isOnyx ? t.accent : t.text)),
              if (subtitle != null)
                Text(subtitle!, style: TextStyle(fontFamily: t.bodyFont, fontSize: 11.5, color: t.textMuted)),
            ]),
          ),
          if (trailing != null) trailing!,
          if (selected) ...[
            const SizedBox(width: 6),
            OnyxIcon(OnyxGlyph.check, size: 14, color: t.isSignal ? AppTheme.signalRec : t.accent),
          ],
        ]),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    if (t.isMaterial) return ChoiceChip(label: Text(label), selected: selected, onSelected: (_) => onTap());
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? t.text : (t.isSignal ? t.surfaceHigh : Colors.transparent),
          borderRadius: BorderRadius.circular(16),
          border: t.isOnyx ? Border.all(color: selected ? t.text : t.line) : null,
        ),
        child: Text(
          t.isSignal ? label.toUpperCase() : label,
          style: t.isSignal
              ? t.caps(size: 10, color: selected ? t.bg : t.textMuted)
              : TextStyle(fontFamily: t.bodyFont, fontSize: 12, fontWeight: FontWeight.w500, color: selected ? t.bg : t.textMuted),
        ),
      ),
    );
  }
}
