// Главный экран темы Material 3 Expressive.
//
// * Компактное окно (< 840dp) — одна панель: small app bar, статус крупным
//   emphasized-текстом, кнопка-фигура (M3ShapeButton), текущий сервер пунктом
//   списка, группа переключателей. Список серверов — нижний лист.
// * Expanded и шире (≥ 840dp) — две панели по канону M3
//   (https://m3.material.io/foundations/layout/applying-layout): поля и
//   промежуток 24dp, справа фиксированная панель серверов 360dp.
//
// Поведение — как у HomeScreen: приоритет ручного выбора сервера над bestNode,
// хаптика по смыслу, автопереключение замечается по смене сервера без действия
// пользователя и показывается снекбаром M3.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/m3/app_shapes.dart';
import '../../core/theme/m3/app_spacing.dart';
import '../../core/theme/m3/app_typography.dart';
import '../../domain/entities/node.dart';
import '../../domain/entities/vpn_state.dart';
import '../providers/node_provider.dart';
import '../providers/subscription_provider.dart';
import '../providers/update_provider.dart';
import '../providers/vpn_provider.dart';
import '../screens/update_screen.dart';
import '../util/country.dart';
import '../util/platform_kind.dart';
import '../widgets/hero/hero_button.dart';
import '../widgets/hero/hero_state.dart';
import '../widgets/m3/m3_buttons.dart';
import '../widgets/m3/m3_flexible_app_bar.dart';
import '../widgets/m3/m3_snackbar.dart';
import 'm3_parts.dart';
import 'm3_server_list.dart';
import '../screens/settings_screen.dart';
import 'm3_subscription_import.dart';

class M3HomeScreen extends ConsumerStatefulWidget {
  const M3HomeScreen({super.key});

  /// Expanded window class (https://m3.material.io/foundations/layout/breakpoints).
  static const double expandedBreakpoint = 840;

  /// Фиксированная панель в expanded-окне.
  static const double paneWidth = 360;

  @override
  ConsumerState<M3HomeScreen> createState() => _M3HomeScreenState();
}

class _M3HomeScreenState extends ConsumerState<M3HomeScreen> {
  final GlobalKey<M3SnackbarHostState> _snackbars = GlobalKey();

  String? _lastConnectedId;
  int? _lastLatency;
  DateTime _userActionAt = DateTime.fromMillisecondsSinceEpoch(0);

  void _handleTap(VpnState state, SubscriptionState sub) {
    HapticFeedback.lightImpact();
    _userActionAt = DateTime.now();
    final vpn = ref.read(vpnControllerProvider.notifier);
    switch (state) {
      case VpnDisconnected() || VpnError():
        final Node? node = ref.read(nodeSelectionProvider) ?? sub.bestNode;
        if (node != null) {
          vpn.connect(node);
        } else {
          _snackbars.currentState?.show('Нет доступных серверов — добавьте подписку');
        }
      case VpnConnected() || VpnConnecting() || VpnDisconnecting():
        vpn.disconnect();
    }
  }

  void _onVpnChanged(VpnState? prev, VpnState next) {
    if (next is VpnConnected && prev is! VpnConnected) {
      HapticFeedback.mediumImpact();
    } else if (next is VpnError && prev is! VpnError) {
      HapticFeedback.heavyImpact();
    }

    if (next is VpnConnected) {
      final String id = next.node.id;
      final bool auto = DateTime.now().difference(_userActionAt) > const Duration(seconds: 20);
      if (_lastConnectedId != null && _lastConnectedId != id && auto) {
        final String to = displayNodeName(next.node.name);
        final int? lat = next.node.latencyMs;
        final String tail = lat == null
            ? ''
            : _lastLatency == null
                ? ' · $lat мс'
                : ' · $lat мс вместо $_lastLatency';
        _snackbars.currentState?.show('Автопереключение на $to$tail');
      }
      _lastConnectedId = id;
      _lastLatency = next.node.latencyMs;
    } else if (next is VpnDisconnected && DateTime.now().difference(_userActionAt) < const Duration(seconds: 20)) {
      _lastConnectedId = null;
    }
  }

  void _openSettings() => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));

  @override
  Widget build(BuildContext context) {
    ref.listen<VpnState>(vpnControllerProvider, _onVpnChanged);
    final VpnState vpn = ref.watch(vpnControllerProvider);
    final SubscriptionState sub = ref.watch(subscriptionProvider);
    final Node? picked = ref.watch(nodeSelectionProvider);
    final updateInfo = ref.watch(updateControllerProvider).valueOrNull;
    final Node? node = switch (vpn) {
      VpnConnected(node: final n) || VpnConnecting(node: final n) || VpnDisconnecting(node: final n) => n,
      _ => picked ?? sub.bestNode,
    };
    final bool staleSub = sub.isSubscriptionStale &&
        sub.url.isNotEmpty &&
        vpn is! VpnConnected &&
        sub.status != SubStatus.fetching &&
        sub.status != SubStatus.probing &&
        sub.status != SubStatus.deepProbing;
    final bool empty = sub.nodes.isEmpty && sub.url.isEmpty && sub.status != SubStatus.fetching;

    final List<Widget> notices = [
      if (updateInfo != null)
        M3Notice(
          icon: Symbols.system_update,
          text: 'Доступно обновление: ${updateInfo.version}',
          action: 'Подробнее',
          onAction: () => showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => UpdateScreen(updateInfo: updateInfo),
          ),
        ),
      if (staleSub)
        M3Notice(
          icon: Symbols.refresh,
          text: 'Серверы могли устареть — обновите подписку',
          action: 'Обновить',
          onAction: () => ref.read(subscriptionProvider.notifier).loadFromUrl(sub.url),
        ),
    ];

    return LayoutBuilder(builder: (context, box) {
      final bool expanded = box.maxWidth >= M3HomeScreen.expandedBreakpoint;
      final Widget settingsButton = M3IconButton(
        onPressed: _openSettings,
        icon: const Icon(Symbols.settings),
        tooltip: 'Настройки',
        color: M3IconButtonColor.standard,
      );
      return Scaffold(
        appBar: expanded ? null : M3SmallAppBar(title: uiIsWindows ? '' : 'Onyx', actions: [settingsButton]),
        body: M3SnackbarHost(
          key: _snackbars,
          child: SafeArea(
            top: expanded,
            child: expanded
                ? _expanded(context, vpn, sub, node, notices, empty, settingsButton)
                : _compact(context, vpn, sub, node, notices, empty),
          ),
        ),
      );
    });
  }

  // ── Телефон и узкое окно ──────────────────────────────────────────────────

  Widget _compact(BuildContext context, VpnState vpn, SubscriptionState sub, Node? node, List<Widget> notices, bool empty) {
    final HeroPhase phase = heroPhaseOf(vpn);
    final double h = MediaQuery.sizeOf(context).height;
    final double heroSize = (h * 0.32).clamp(200.0, 300.0);
    return Column(children: [
      ...notices,
      Expanded(
        child: empty
            ? const M3SubscriptionImport()
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space200),
                child: Column(children: [
                  const SizedBox(height: AppSpacing.space300),
                  M3StatusHeadline(vpn: vpn),
                  const Spacer(),
                  HeroButton(vpn: vpn, size: heroSize, onTap: () => _handleTap(vpn, sub)),
                  const SizedBox(height: AppSpacing.space200),
                  M3HeroCaption(phase: phase),
                  const Spacer(),
                  if (vpn is VpnConnected) ...[
                    M3TrafficTiles(state: vpn),
                    const SizedBox(height: AppSpacing.space150),
                  ],
                  M3ServerCard(node: node, sub: sub, locked: vpn is VpnConnected, onTap: () => showM3ServerSheet(context)),
                  const SizedBox(height: AppSpacing.space200),
                  const M3FeatureToggles(),
                  const SizedBox(height: AppSpacing.space300),
                ]),
              ),
      ),
    ]);
  }

  // ── Окно Windows шире 840dp ───────────────────────────────────────────────

  Widget _expanded(BuildContext context, VpnState vpn, SubscriptionState sub, Node? node, List<Widget> notices, bool empty,
      Widget settingsButton) {
    final ColorScheme s = context.colors;
    final HeroPhase phase = heroPhaseOf(vpn);
    final Widget main = empty
        ? const M3SubscriptionImport()
        : Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space300, vertical: AppSpacing.space300),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  M3StatusHeadline(vpn: vpn),
                  const SizedBox(height: AppSpacing.space400),
                  HeroButton(vpn: vpn, size: 280, onTap: () => _handleTap(vpn, sub)),
                  const SizedBox(height: AppSpacing.space200),
                  M3HeroCaption(phase: phase),
                  const SizedBox(height: AppSpacing.space400),
                  if (vpn is VpnConnected) ...[
                    M3TrafficTiles(state: vpn),
                    const SizedBox(height: AppSpacing.space200),
                  ],
                  const M3FeatureToggles(),
                ]),
              ),
            ),
          );
    return Column(children: [
      ...notices,
      Expanded(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: Column(children: [
              SizedBox(
                height: 64,
                child: Row(children: [
                  const SizedBox(width: AppSpacing.space300),
                  if (!uiIsWindows) Text('Onyx', style: context.text.titleLarge),
                  const Spacer(),
                  settingsButton,
                  const SizedBox(width: AppSpacing.space50),
                ]),
              ),
              Expanded(child: main),
            ]),
          ),
          if (!empty)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, AppSpacing.space300, AppSpacing.space300, AppSpacing.space300),
              child: SizedBox(
                width: M3HomeScreen.paneWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(color: s.surfaceContainerLow, borderRadius: AppShapes.all(AppShapes.extraLarge)),
                  child: ClipRRect(borderRadius: AppShapes.all(AppShapes.extraLarge), child: const M3ServerList()),
                ),
              ),
            ),
        ]),
      ),
    ]);
  }
}
