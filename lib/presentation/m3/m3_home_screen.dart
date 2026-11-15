// Главный экран темы Material 3 Expressive — «одна кнопка» (#47).
//
// * Компактное окно (< 840dp) — одна панель: small app bar, статус крупным
//   emphasized-текстом (с этапами автопилота), кнопка-фигура (M3ShapeButton),
//   при отказе — действия, трафик, текущий сервер пунктом списка. Список
//   серверов — нижний лист. Тумблеры (Discord, регион, автопереключение…) —
//   только в Настройках.
// * Expanded и шире (≥ 840dp) — две панели по канону M3
//   (https://m3.material.io/foundations/layout/applying-layout): поля и
//   промежуток 24dp, справа фиксированная панель 360dp — «Обзор» (сервер,
//   голос и автопереключение, скорость, сессия, события) или «Серверы»;
//   переключатель — connected button group.
//
// Логика общая с темами Onyx и Signal: тап — toggleConnection (автопилот
// «Оникс» в режиме «Автовыбор»), этапы — AutopilotView, оговорки
// (ConnectNotice) — общим тостом showOnyxToast (снекбар M3).

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_new_shapes/material_new_shapes.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/theme/m3/app_shapes.dart';
import '../../core/theme/m3/app_spacing.dart';
import '../../core/theme/m3/app_typography.dart';
import '../../domain/entities/node.dart';
import '../../domain/entities/vpn_state.dart';
import '../providers/activity_provider.dart';
import '../providers/connect_phase.dart';
import '../providers/groups_provider.dart';
import '../providers/node_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/sources_provider.dart';
import '../providers/subscription_provider.dart';
import '../providers/update_provider.dart';
import '../providers/vpn_provider.dart';
import '../screens/home_screen.dart' show SpeedSparkline;
import '../screens/settings_screen.dart';
import '../screens/update_screen.dart';
import '../util/country.dart';
import '../util/platform_kind.dart';
import '../util/vpn_actions.dart';
import '../widgets/add_source_sheet.dart';
import '../widgets/hero/hero_button.dart';
import '../widgets/hero/hero_state.dart';
import '../widgets/home_parts.dart' show AutopilotView, SecondTicker, formatBytes, formatClock;
import '../widgets/m3/connected_button_group.dart';
import '../widgets/m3/m3_buttons.dart';
import '../widgets/m3/m3_flexible_app_bar.dart';
import '../widgets/m3/m3_snackbar.dart';
import '../widgets/m3/section_header.dart';
import '../widgets/m3/segmented_list.dart';
import '../widgets/onyx_toast.dart';
import 'm3_parts.dart';
import 'm3_server_list.dart';
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

/// Что показывает правая панель окна.
enum _Pane { overview, servers }

class _M3HomeScreenState extends ConsumerState<M3HomeScreen> {
  final GlobalKey<M3SnackbarHostState> _snackbars = GlobalKey();
  _Pane _pane = _Pane.overview;

  Future<void> _handleTap() async {
    HapticFeedback.lightImpact();
    // Логика общая со всеми темами и мини-панелью (util/vpn_actions.dart):
    // «Автовыбор» — автопилот, ручной выбор — подключение к серверу, во время
    // автопилота тап — «Отмена».
    await toggleConnection(ref);
  }

  void _onVpnChanged(VpnState? prev, VpnState next) {
    if (next is VpnConnected && prev is! VpnConnected) {
      HapticFeedback.mediumImpact();
    } else if (next is VpnError && prev is! VpnError) {
      HapticFeedback.heavyImpact();
    }
  }

  /// Оговорки автопилота («подключено, но без UDP», «Переключились: A → B»,
  /// «соединение восстановлено…») — тот же тост, что у Onyx и Signal
  /// (showOnyxToast: снекбар M3 через ScaffoldMessenger): виден и поверх
  /// Настроек, держится по длине текста, без флагов в именах.
  void _onPhaseChanged(ConnectPhase? prev, ConnectPhase next) {
    if (next is ConnectNotice && mounted) showOnyxToast(context, uiText(next.message));
  }

  Future<void> _refreshAll() async {
    final report = await ref.read(sourcesProvider.notifier).refreshAll();
    if (mounted) _snackbars.currentState?.show(report.summary);
  }

  void _openSettings() => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen()));

  @override
  Widget build(BuildContext context) {
    ref.listen<VpnState>(vpnControllerProvider, _onVpnChanged);
    ref.listen<ConnectPhase>(connectPhaseProvider, _onPhaseChanged);
    final VpnState vpn = ref.watch(vpnControllerProvider);
    final SubscriptionState sub = ref.watch(subscriptionProvider);
    final Node? picked = ref.watch(nodeSelectionProvider);
    final updateInfo = ref.watch(updateControllerProvider).valueOrNull;
    final AutopilotView? ap = AutopilotView.of(vpn, ref.watch(connectPhaseProvider));
    final Node? node = switch (vpn) {
      VpnConnected(node: final n) || VpnConnecting(node: final n) || VpnDisconnecting(node: final n) => n,
      _ => picked ?? ref.watch(autoNodeProvider),
    };
    final bool staleSub = sub.isSubscriptionStale &&
        sub.nodes.isNotEmpty &&
        vpn is! VpnConnected &&
        ap == null &&
        sub.status != SubStatus.fetching &&
        sub.status != SubStatus.probing &&
        sub.status != SubStatus.deepProbing;
    // Без источников — импорт, но не пока автопилот объясняет отказ.
    final bool empty = sub.nodes.isEmpty && ref.watch(sourcesProvider).isEmpty && sub.status != SubStatus.fetching && ap == null;

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
          onAction: _refreshAll,
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
                ? _expanded(context, vpn, sub, node, ap, notices, empty, settingsButton)
                : _compact(context, vpn, sub, node, ap, notices, empty),
          ),
        ),
      );
    });
  }

  /// Кнопка, подпись и действия при отказе — одинаковы в обеих раскладках.
  List<Widget> _hero(VpnState vpn, AutopilotView? ap, double size) {
    final HeroPhase phase = ap?.phase ?? heroPhaseOf(vpn);
    final ConnectFailed? failure = ap?.failure;
    return [
      HeroButton(vpn: vpn, phase: ap?.phase, progress: ap?.progress, size: size, onTap: _handleTap),
      const SizedBox(height: AppSpacing.space200),
      M3HeroCaption(phase: phase),
      if (failure != null) ...[
        const SizedBox(height: AppSpacing.space200),
        M3PhaseActions(
          failure: failure,
          onRefresh: () => ref.read(vpnControllerProvider.notifier).smartConnect(),
          onAddServer: () => showAddSourceSheet(context),
        ),
      ],
    ];
  }

  // ── Телефон и узкое окно ──────────────────────────────────────────────────

  Widget _compact(BuildContext context, VpnState vpn, SubscriptionState sub, Node? node, AutopilotView? ap, List<Widget> notices,
      bool empty) {
    final double h = MediaQuery.sizeOf(context).height;
    final double heroSize = (h * 0.30).clamp(200.0, 280.0);
    return Column(children: [
      ...notices,
      Expanded(
        child: empty
            ? const M3SubscriptionImport()
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space200),
                child: Column(children: [
                  const SizedBox(height: AppSpacing.space300),
                  M3StatusHeadline(vpn: vpn, autopilot: ap),
                  const Spacer(),
                  ..._hero(vpn, ap, heroSize),
                  const Spacer(),
                  if (vpn is VpnConnected) ...[
                    M3TrafficTiles(state: vpn),
                    const SizedBox(height: AppSpacing.space150),
                  ],
                  M3ServerCard(node: node, sub: sub, locked: vpn is VpnConnected, onTap: () => showM3ServerSheet(context)),
                  const SizedBox(height: AppSpacing.space300),
                ]),
              ),
      ),
    ]);
  }

  // ── Окно Windows шире 840dp ───────────────────────────────────────────────

  Widget _expanded(BuildContext context, VpnState vpn, SubscriptionState sub, Node? node, AutopilotView? ap, List<Widget> notices,
      bool empty, Widget settingsButton) {
    final ColorScheme s = context.colors;
    final Widget main = empty
        ? const M3SubscriptionImport()
        : LayoutBuilder(builder: (context, box) {
            // Кнопка — по высоте окна: в минимальном окне 800×600 всё помещается.
            final double hero = (box.maxHeight - (ap?.failure != null ? 300 : 230)).clamp(200.0, 280.0);
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(AppSpacing.space300),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    M3StatusHeadline(vpn: vpn, autopilot: ap),
                    const SizedBox(height: AppSpacing.space400),
                    ..._hero(vpn, ap, hero),
                  ]),
                ),
              ),
            );
          });
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
                  child: ClipRRect(
                    borderRadius: AppShapes.all(AppShapes.extraLarge),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(AppSpacing.space200, AppSpacing.space200, AppSpacing.space200, 0),
                        child: ConnectedButtonGroup<_Pane>(
                          values: _Pane.values,
                          labelOf: (p) => p == _Pane.overview ? 'Обзор' : 'Серверы',
                          selected: _pane,
                          onSelected: (p) {
                            HapticFeedback.selectionClick();
                            setState(() => _pane = p);
                          },
                        ),
                      ),
                      Expanded(
                        child: _pane == _Pane.servers
                            ? const M3ServerList()
                            : _M3Overview(
                                vpn: vpn,
                                sub: sub,
                                node: node,
                                onServers: () => setState(() => _pane = _Pane.servers),
                              ),
                      ),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ),
    ]);
  }
}

// ── Правая панель окна: обзор ───────────────────────────────────────────────

/// Справочная панель окна (как у Onyx и Signal, без переключателей): сервер
/// (нажатие — к списку), голос (UDP) и автопереключение, скорость за минуту, сессия,
/// лента событий. Разделы — SectionHeader и сегментированные списки.
class _M3Overview extends ConsumerWidget {
  const _M3Overview({required this.vpn, required this.sub, required this.node, required this.onServers});
  final VpnState vpn;
  final SubscriptionState sub;
  final Node? node;
  final VoidCallback onServers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ColorScheme s = context.colors;
    final bool connected = vpn is VpnConnected;
    final settings = ref.watch(settingsProvider);
    final bool autoActive = ref.watch(autoFailoverActiveProvider);
    final List<SpeedSample> speed = ref.watch(speedProvider);
    final List<ActivityEvent> events = ref.watch(activityProvider);
    final SpeedSample? last = connected && speed.isNotEmpty ? speed.last : null;
    String two(int v) => v.toString().padLeft(2, '0');
    final TextStyle value = context.text.bodyLarge!.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

    M3ListItem kv(IconData icon, String k, Widget v) => M3ListItem(
          leading: Icon(icon),
          headline: Text(k),
          trailing: DefaultTextStyle.merge(style: value, child: v),
        );

    final (String voice, String voiceHint) = switch (node?.udpStatus) {
      UdpStatus.ok => ('Работает', 'UDP проходит — голос Discord и звонки'),
      UdpStatus.blocked => ('Заблокирован', 'Голос Discord и звонки не пойдут'),
      UdpStatus.unreachable => ('Недоступен', 'Сервер не прошёл проверку через туннель'),
      _ => ('Не проверен', 'Проверится при подключении'),
    };

    Widget rate(IconData icon, String label, double? v) {
      final String text = v == null ? '—' : '${formatBytes(v.round())}/с';
      return Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 16, color: s.onSurfaceVariant),
            const SizedBox(width: AppSpacing.space50),
            Text(label, style: context.text.labelMedium!.copyWith(color: s.onSurfaceVariant)),
          ]),
          Text(text, style: context.text.titleLarge!.emphasized.copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.space200, 0, AppSpacing.space200, AppSpacing.space200),
      children: [
        const SectionHeader('Сервер'),
        M3ServerCard(
          node: node,
          sub: sub,
          locked: connected,
          onTap: onServers,
        ),
        const SizedBox(height: AppSpacing.space100),
        SegmentedList(children: [
          M3ListItem(
            leading: const Icon(Symbols.mic),
            headline: Text('Голос · $voice'),
            supporting: Text(voiceHint),
          ),
          M3ListItem(
            leading: const Icon(Symbols.bolt),
            headline: Text(autoActive ? 'Автопереключение' : (settings.autoFailover ? 'Ручной выбор' : 'Автопереключение выкл')),
            supporting: Text(autoActive
                ? 'Сменит сервер, если он начнёт подвисать'
                : (settings.autoFailover ? 'Выбранный вручную сервер Onyx не меняет' : 'Включается в Настройках')),
          ),
        ]),
        const SectionHeader('Скорость'),
        Container(
          padding: const EdgeInsets.all(AppSpacing.space200),
          decoration: BoxDecoration(color: s.surfaceContainer, borderRadius: AppShapes.all(AppShapes.large)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              rate(Symbols.arrow_downward, 'Приём', last?.down),
              rate(Symbols.arrow_upward, 'Отдача', last?.up),
            ]),
            const SizedBox(height: AppSpacing.space150),
            SpeedSparkline(samples: connected ? speed : const []),
          ]),
        ),
        const SectionHeader('Сессия'),
        SecondTicker(
          active: connected,
          builder: (_) => SegmentedList(children: [
            kv(Symbols.schedule, 'Время', Text(connected ? formatClock((vpn as VpnConnected).uptime) : '—')),
            kv(Symbols.arrow_downward, 'Получено', Text(connected ? formatBytes((vpn as VpnConnected).rxBytes) : '—')),
            kv(Symbols.arrow_upward, 'Отправлено', Text(connected ? formatBytes((vpn as VpnConnected).txBytes) : '—')),
            kv(Symbols.dns, 'Адрес сервера', Text(node?.host ?? '—')),
          ]),
        ),
        const SectionHeader('События'),
        if (events.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.space200, vertical: AppSpacing.space100),
            child: Text('Пока тихо', style: context.text.bodyMedium!.copyWith(color: s.onSurfaceVariant)),
          )
        else
          SegmentedList(children: [
            for (final ActivityEvent e in events.take(5))
              M3ListItem(
                leading: M3ShapeIcon(
                  icon: switch (e.kind) {
                    ActivityKind.connected => Symbols.check,
                    ActivityKind.switched => Symbols.swap_horiz,
                    ActivityKind.warning || ActivityKind.error => Symbols.error,
                    _ => Symbols.info,
                  },
                  shape: MaterialShapes.circle,
                  color: switch (e.kind) {
                    ActivityKind.warning || ActivityKind.error => s.errorContainer,
                    ActivityKind.connected => s.primaryContainer,
                    _ => s.surfaceContainerHighest,
                  },
                  onColor: switch (e.kind) {
                    ActivityKind.warning || ActivityKind.error => s.onErrorContainer,
                    ActivityKind.connected => s.onPrimaryContainer,
                    _ => s.onSurfaceVariant,
                  },
                  size: 32,
                ),
                overline: Text('${two(e.at.hour)}:${two(e.at.minute)}'),
                headline: Text(e.text, maxLines: 2, overflow: TextOverflow.ellipsis),
              ),
          ]),
      ],
    );
  }
}
