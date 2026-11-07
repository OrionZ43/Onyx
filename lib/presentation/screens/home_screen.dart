// lib/presentation/screens/home_screen.dart
//
// Главный экран — «одна кнопка» (#47): статус, «Линза», трафик и текущий
// сервер. Тумблеры (Discord, регион, автопереключение, AI-канал, маршруты,
// Kill switch) — только в Настройках. Вид — по активной теме (Onyx / Signal /
// Material 3 Expressive), см. docs/redesign/concepts.md.
//
// * Телефон и узкое окно — одна колонка.
// * Окно шире 860 — та же колонка по центру; список серверов выезжает
//   справа по кнопке «Серверы» или по карточке сервера.
//
// Из прежней версии сохранено: приоритет ручного выбора сервера над bestNode,
// баннеры обновления и устаревшей подписки, навигация без
// addPostFrameCallback. Анимированный космический фон и BackdropFilter
// убраны: в покое экран не перерисовывается.


import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cosmic_background.dart';
import '../../core/theme/onyx_tokens.dart';
import '../../domain/entities/node.dart';
import '../../domain/entities/vpn_state.dart';
import '../providers/groups_provider.dart';
import '../providers/node_provider.dart';
import '../providers/sources_provider.dart';
import '../providers/subscription_provider.dart';
import '../providers/update_provider.dart';
import '../providers/vpn_provider.dart';
import '../util/country.dart';
import '../util/platform_kind.dart';
import '../util/vpn_actions.dart';
import '../widgets/hero/hero_button.dart';
import '../widgets/hero/hero_state.dart';
import '../widgets/home_parts.dart';
import '../widgets/node_list_sheet.dart';
import '../widgets/onyx_icon.dart';
import '../widgets/onyx_toast.dart';
import '../widgets/onyx_wordmark.dart';
import '../widgets/subscription_import.dart';
import '../widgets/update_banner.dart';
import 'settings_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  /// Ширина, с которой включается двухколоночная раскладка.
  static const double wideBreakpoint = 860;

  /// Последний сервер, к которому были подключены, — чтобы заметить
  /// автопереключение (сервер сменился без действия пользователя).
  String? _lastConnectedId;
  String? _lastConnectedName;
  int? _lastLatency;
  DateTime _userActionAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// На Windows правая колонка может показывать список серверов.
  bool _showServers = false;

  void _markUserAction() => _userActionAt = DateTime.now();

  Future<void> _handleTap(VpnState state, SubscriptionState sub) async {
    HapticFeedback.lightImpact();
    _markUserAction();
    // Приоритет: выбранный пользователем сервер → лучший из группы автовыбора.
    // Логика общая с мини-панелью трея (util/vpn_actions.dart).
    final ok = await toggleConnection(ref);
    if (!ok && mounted) {
      showOnyxToast(context, 'Нет доступных серверов — добавьте подписку', glyph: OnyxGlyph.error);
    }
  }

  void _onVpnChanged(VpnState? prev, VpnState next) {
    final t = OnyxTokens.of(context);
    // Хаптика по смыслу темы: Onyx — двойной мягкий тик, Signal — confirm,
    // ошибка — один «тяжёлый».
    if (next is VpnConnected && prev is! VpnConnected) {
      if (t.isOnyx) {
        HapticFeedback.lightImpact();
        Future.delayed(const Duration(milliseconds: 120), HapticFeedback.lightImpact);
      } else {
        HapticFeedback.mediumImpact();
      }
    } else if (next is VpnError && prev is! VpnError) {
      HapticFeedback.heavyImpact();
    }

    if (next is VpnConnected) {
      final id = next.node.id;
      final auto = DateTime.now().difference(_userActionAt) > const Duration(seconds: 20);
      if (_lastConnectedId != null && _lastConnectedId != id && auto) {
        final from = _lastConnectedName ?? '';
        final to = displayNodeName(next.node.name);
        final lat = next.node.latencyMs;
        final tail = (_lastLatency != null && lat != null) ? ' · $_lastLatency → $lat мс' : '';
        showOnyxToast(context, 'Автопереключение: $from → $to$tail', glyph: OnyxGlyph.zap);
      }
      _lastConnectedId = id;
      _lastConnectedName = displayNodeName(next.node.name);
      _lastLatency = next.node.latencyMs;
    } else if (next is VpnDisconnected && DateTime.now().difference(_userActionAt) < const Duration(seconds: 20)) {
      // Пользователь сам отключился — следующее подключение не автопереключение.
      _lastConnectedId = null;
    }
  }

  void _openServers(BuildContext context, bool wide) {
    if (wide) {
      setState(() => _showServers = !_showServers);
    } else {
      showOnyxNodeSheet(context);
    }
  }

  void _openSettings() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<VpnState>(vpnControllerProvider, _onVpnChanged);
    final t = OnyxTokens.of(context);
    final vpn = ref.watch(vpnControllerProvider);
    final sub = ref.watch(subscriptionProvider);
    final picked = ref.watch(nodeSelectionProvider);
    final updateInfo = ref.watch(updateControllerProvider).valueOrNull;
    final Node? node = switch (vpn) {
      VpnConnected(node: final n) || VpnConnecting(node: final n) || VpnDisconnecting(node: final n) => n,
      _ => picked ?? ref.watch(autoNodeProvider),
    };
    final phase = heroPhaseOf(vpn);
    final isConnected = vpn is VpnConnected;
    final showStale = sub.isSubscriptionStale &&
        sub.nodes.isNotEmpty &&
        !isConnected &&
        sub.status != SubStatus.fetching &&
        sub.status != SubStatus.probing &&
        sub.status != SubStatus.deepProbing;

    return Scaffold(
      backgroundColor: t.bg,
      body: Stack(
        children: [
          const Positioned.fill(child: CosmicBackground()),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, box) {
                final wide = box.maxWidth >= wideBreakpoint;
                final banners = [
                  if (updateInfo != null) UpdateBanner(updateInfo: updateInfo),
                  if (showStale) _StaleBanner(onRefresh: () => ref.read(sourcesProvider.notifier).refreshAll()),
                ];
                final empty = sub.nodes.isEmpty && ref.watch(sourcesProvider).isEmpty && sub.status != SubStatus.fetching;
                if (wide) {
                  return _wide(context, vpn, sub, node, phase, banners, empty);
                }
                return _narrow(context, vpn, sub, node, phase, banners, empty);
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Телефон ───────────────────────────────────────────────────────────────
  Widget _narrow(BuildContext context, VpnState vpn, SubscriptionState sub, Node? node, HeroPhase phase, List<Widget> banners, bool empty) {
    final t = OnyxTokens.of(context);
    final h = MediaQuery.sizeOf(context).height;
    final heroSize = (h * 0.34).clamp(220.0, 300.0);
    return Column(
      children: [
        ...banners,
        _TopBar(onSettings: _openSettings, showWordmark: !uiIsWindows),
        Expanded(
          child: empty
              ? const Padding(padding: EdgeInsets.symmetric(horizontal: 20), child: SubscriptionImport())
              : Padding(
                  padding: EdgeInsets.symmetric(horizontal: t.isMaterial ? 16 : 20),
                  child: Column(
                    children: [
                      SizedBox(height: t.isSignal ? 22 : 30),
                      StatusHeader(vpn: vpn),
                      const Spacer(),
                      HeroButton(
                        vpn: vpn,
                        size: t.isMaterial ? heroSize * 0.84 : heroSize,
                        onTap: () => _handleTap(vpn, sub),
                      ),
                      if (t.isMaterial) ...[const SizedBox(height: 18), HeroCaption(phase: phase)],
                      const Spacer(),
                      if (vpn is VpnConnected) ...[
                        TrafficStats(state: vpn),
                        SizedBox(height: t.isOnyx ? 20 : 8),
                      ],
                      ServerCard(node: node, sub: sub, locked: vpn is VpnConnected, onTap: () => _openServers(context, false)),
                      SizedBox(height: t.isSignal ? 20 : 28),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  // ── Окно Windows ──────────────────────────────────────────────────────────
  // «Одна кнопка» (#47): колонка по центру — статус, «Линза», трафик, сервер.
  // Список серверов — справа, по кнопке «Серверы» или по карточке сервера.
  // Тумблеры (Discord, регион, автопереключение…) — только в Настройках.
  Widget _wide(BuildContext context, VpnState vpn, SubscriptionState sub, Node? node, HeroPhase phase, List<Widget> banners, bool empty) {
    final t = OnyxTokens.of(context);
    final connected = vpn is VpnConnected;
    final left = empty
        ? const Padding(padding: EdgeInsets.all(32), child: SubscriptionImport())
        : LayoutBuilder(builder: (context, box) {
            // Кнопка — по высоте окна: в минимальном окне 800×600 всё помещается.
            final rest = t.isMaterial ? 210.0 : (connected ? 330.0 : 250.0);
            final hero = (box.maxHeight - rest).clamp(200.0, t.isMaterial ? 260.0 : 300.0);
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    StatusHeader(vpn: vpn),
                    SizedBox(height: t.isSignal ? 28 : 34),
                    HeroButton(vpn: vpn, size: hero, onTap: () => _handleTap(vpn, sub)),
                    if (t.isMaterial) ...[const SizedBox(height: 18), HeroCaption(phase: phase)],
                    if (!t.isMaterial) ...[
                      SizedBox(height: t.isSignal ? 28 : 34),
                      if (connected) ...[TrafficStats(state: vpn), SizedBox(height: t.isOnyx ? 20 : 8)],
                      ServerCard(node: node, sub: sub, locked: connected, onTap: () => setState(() => _showServers = !_showServers)),
                    ],
                  ]),
                ),
              ),
            );
          });
    final bool showPanel = _showServers || t.isMaterial;
    const Widget right = NodeListPanel();
    final Widget? panel = !showPanel
        ? null
        : t.isMaterial
            ? Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 16, 16),
                child: Container(
                  width: 420,
                  decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerLow, borderRadius: BorderRadius.circular(28)),
                  clipBehavior: Clip.antiAlias,
                  child: Column(children: [
                    if (vpn is VpnConnected) Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: TrafficStats(state: vpn)),
                    const SizedBox(height: 8),
                    const Expanded(child: right),
                  ]),
                ),
              )
            : Container(
                width: 392,
                decoration: BoxDecoration(
                  color: t.isSignal ? t.bg : const Color(0xFF08080A),
                  border: t.isOnyx ? Border(left: BorderSide(color: t.line)) : null,
                ),
                padding: t.isSignal ? const EdgeInsets.fromLTRB(0, 8, 16, 16) : EdgeInsets.zero,
                child: t.isSignal
                    ? Container(
                        decoration: BoxDecoration(color: t.surface, borderRadius: BorderRadius.circular(24)),
                        clipBehavior: Clip.antiAlias,
                        child: right,
                      )
                    : right,
              );
    return Column(
      children: [
        ...banners,
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(children: [
                  Positioned.fill(child: left),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Row(children: [
                      if (!t.isMaterial)
                        _TopIcon(
                          glyph: _showServers ? OnyxGlyph.close : OnyxGlyph.globe,
                          tooltip: _showServers ? 'Скрыть серверы' : 'Серверы',
                          onTap: () => setState(() => _showServers = !_showServers),
                        ),
                      _TopIcon(glyph: OnyxGlyph.settings, tooltip: 'Настройки', onTap: _openSettings),
                    ]),
                  ),
                ]),
              ),
              if (panel != null) panel,
            ],
          ),
        ),
      ],
    );
  }
}

// ── Верхняя строка (телефон) ────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onSettings, this.showWordmark = true});
  final VoidCallback onSettings;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    return SizedBox(
      height: t.isMaterial ? 64 : 56,
      child: Padding(
        padding: EdgeInsets.only(left: t.isMaterial ? 16 : 20, right: t.isMaterial ? 4 : 14),
        child: Row(children: [
          if (showWordmark) OnyxWordmark(size: t.isMaterial ? 20 : 13),
          const Spacer(),
          _TopIcon(glyph: t.isSignal ? OnyxGlyph.more : OnyxGlyph.settings, tooltip: 'Настройки', onTap: onSettings),
        ]),
      ),
    );
  }
}

class _TopIcon extends StatelessWidget {
  const _TopIcon({required this.glyph, required this.tooltip, required this.onTap});
  final OnyxGlyph glyph;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: OnyxIcon(glyph, size: t.isMaterial ? 24 : 18, color: t.isMaterial ? null : (t.isSignal ? t.text : t.textMuted)),
        style: IconButton.styleFrom(
          fixedSize: Size.square(t.isMaterial ? 48 : 40),
          backgroundColor: t.isSignal ? t.surfaceHigh : Colors.transparent,
          shape: CircleBorder(side: t.isOnyx ? BorderSide(color: t.line) : BorderSide.none),
        ),
      ),
    );
  }
}

// ── Баннер устаревшей подписки ──────────────────────────────────────────────

class _StaleBanner extends StatelessWidget {
  const _StaleBanner({required this.onRefresh});
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(t.isMaterial ? 16 : 14),
        border: t.isOnyx ? Border.all(color: t.line) : null,
      ),
      child: Row(children: [
        OnyxIcon(OnyxGlyph.refresh, size: 15, color: t.textMuted),
        const SizedBox(width: 10),
        Expanded(
          child: Text('Серверы могли устареть — обновите подписку',
              style: TextStyle(fontFamily: t.bodyFont, fontSize: 12.5, color: t.textMuted)),
        ),
        TextButton(onPressed: onRefresh, child: const Text('Обновить')),
      ]),
    );
  }
}

