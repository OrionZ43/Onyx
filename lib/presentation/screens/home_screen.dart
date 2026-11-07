// lib/presentation/screens/home_screen.dart
//
// Главный экран — «одна кнопка» (#47): статус, «Линза» и этапы автопилота
// «Оникс» (обновляю подписку → проверяю серверы → подключаюсь; при отказе —
// причина и действия). Тумблеры (Discord, регион, автопереключение,
// AI-канал, маршруты, Kill switch) — только в Настройках. Вид — по активной
// теме (Onyx / Signal / Material 3 Expressive), см. docs/redesign/concepts.md.
//
// * Телефон и узкое окно — одна колонка: статус, «Линза», трафик, сервер.
// * Окно шире 860 — две колонки: слева «Линза» со статусом, справа панель
//   «Сервер / Скорость / Сессия / События» (по просьбе пользователя —
//   справочная, без переключателей) или список серверов.
//
// Из прежней версии сохранено: приоритет ручного выбора сервера над bestNode,
// баннеры обновления и устаревшей подписки, навигация без
// addPostFrameCallback. Анимированный космический фон и BackdropFilter
// убраны: в покое экран не перерисовывается.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/cosmic_background.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/onyx_tokens.dart';
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
import '../util/platform_kind.dart';
import '../util/vpn_actions.dart';
import '../widgets/add_source_sheet.dart';
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

  /// На Windows правая колонка может показывать список серверов.
  bool _showServers = false;

  Future<void> _handleTap() async {
    HapticFeedback.lightImpact();
    // Логика общая с мини-панелью трея (util/vpn_actions.dart): «Автовыбор» —
    // автопилот smartConnect(), ручной выбор — подключение к серверу; во
    // время автопилота тап — «Отмена».
    await toggleConnection(ref);
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
  }

  /// Оговорки автопилота («подключено, но без UDP», «переключились: A → B») —
  /// тихим тостом.
  void _onPhaseChanged(ConnectPhase? prev, ConnectPhase next) {
    if (next is ConnectNotice && mounted) {
      showOnyxToast(context, next.message, glyph: next.message.startsWith('Переключились') ? OnyxGlyph.zap : OnyxGlyph.info);
    }
  }

  /// Кнопки под «Линзой» при отказе автопилота. «Инструкция AWS» — когда
  /// у «Оникс» появится адрес инструкции.
  List<(String, VoidCallback)> _actionsFor(ConnectFailed f) => [
        for (final a in f.actions)
          if (a == ConnectAction.refresh)
            ('Обновить и повторить', () => ref.read(vpnControllerProvider.notifier).smartConnect())
          else if (a == ConnectAction.addServer)
            ('Добавить сервер', () => showAddSourceSheet(context)),
      ];

  Future<void> _refreshAll() async {
    final report = await ref.read(sourcesProvider.notifier).refreshAll();
    if (mounted) showOnyxToast(context, report.summary, glyph: report.allFailed ? OnyxGlyph.error : OnyxGlyph.refresh);
  }

  void _openSettings() {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<VpnState>(vpnControllerProvider, _onVpnChanged);
    ref.listen<ConnectPhase>(connectPhaseProvider, _onPhaseChanged);
    final t = OnyxTokens.of(context);
    final vpn = ref.watch(vpnControllerProvider);
    final sub = ref.watch(subscriptionProvider);
    final picked = ref.watch(nodeSelectionProvider);
    final updateInfo = ref.watch(updateControllerProvider).valueOrNull;
    final ap = AutopilotView.of(vpn, ref.watch(connectPhaseProvider));
    final Node? node = switch (vpn) {
      VpnConnected(node: final n) || VpnConnecting(node: final n) || VpnDisconnecting(node: final n) => n,
      _ => picked ?? ref.watch(autoNodeProvider),
    };
    final isConnected = vpn is VpnConnected;
    final showStale = sub.isSubscriptionStale &&
        sub.nodes.isNotEmpty &&
        !isConnected &&
        ap == null &&
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
                  if (showStale) _StaleBanner(onRefresh: _refreshAll),
                ];
                // Без источников — экран импорта, но не пока автопилот
                // объясняет, почему не подключился.
                final empty = sub.nodes.isEmpty && ref.watch(sourcesProvider).isEmpty && sub.status != SubStatus.fetching && ap == null;
                if (wide) {
                  return _wide(context, vpn, sub, node, ap, banners, empty);
                }
                return _narrow(context, vpn, sub, node, ap, banners, empty);
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Телефон ───────────────────────────────────────────────────────────────
  Widget _narrow(BuildContext context, VpnState vpn, SubscriptionState sub, Node? node, AutopilotView? ap, List<Widget> banners, bool empty) {
    final t = OnyxTokens.of(context);
    final h = MediaQuery.sizeOf(context).height;
    final heroSize = (h * 0.34).clamp(220.0, 300.0);
    final failure = ap?.failure;
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
                      StatusHeader(vpn: vpn, phase: ap?.phase, title: ap?.title, detail: ap?.detail),
                      const Spacer(),
                      HeroButton(
                        vpn: vpn,
                        phase: ap?.phase,
                        progress: ap?.progress,
                        size: t.isMaterial ? heroSize * 0.84 : heroSize,
                        onTap: _handleTap,
                      ),
                      if (t.isMaterial) ...[const SizedBox(height: 18), HeroCaption(phase: ap?.phase ?? heroPhaseOf(vpn))],
                      const Spacer(),
                      if (failure != null) ...[PhaseActions(actions: _actionsFor(failure)), const SizedBox(height: 18)],
                      if (vpn is VpnConnected) ...[
                        TrafficStats(state: vpn),
                        SizedBox(height: t.isOnyx ? 20 : 8),
                      ],
                      ServerCard(node: node, sub: sub, locked: vpn is VpnConnected, onTap: () => showOnyxNodeSheet(context)),
                      SizedBox(height: t.isSignal ? 20 : 28),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  // ── Окно Windows ──────────────────────────────────────────────────────────
  // Слева — «Линза» со статусом и этапами автопилота; справа — справочная
  // панель «Сервер / Скорость / Сессия / События» или список серверов.
  Widget _wide(BuildContext context, VpnState vpn, SubscriptionState sub, Node? node, AutopilotView? ap, List<Widget> banners, bool empty) {
    final t = OnyxTokens.of(context);
    final failure = ap?.failure;
    final left = empty
        ? const Padding(padding: EdgeInsets.all(32), child: SubscriptionImport())
        : LayoutBuilder(builder: (context, box) {
            // Кнопка — по высоте окна: в минимальном окне 800×600 всё помещается.
            final rest = failure != null ? 300.0 : 220.0;
            final hero = (box.maxHeight - rest).clamp(200.0, t.isMaterial ? 260.0 : 320.0);
            return Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    StatusHeader(vpn: vpn, phase: ap?.phase, title: ap?.title, detail: ap?.detail),
                    const SizedBox(height: 40),
                    HeroButton(vpn: vpn, phase: ap?.phase, progress: ap?.progress, size: hero, onTap: _handleTap),
                    if (t.isMaterial) ...[const SizedBox(height: 18), HeroCaption(phase: ap?.phase ?? heroPhaseOf(vpn))],
                    if (failure != null) ...[const SizedBox(height: 32), PhaseActions(actions: _actionsFor(failure))],
                  ]),
                ),
              ),
            );
          });
    final Widget right = _showServers || t.isMaterial
        ? const NodeListPanel()
        : _SidePanel(vpn: vpn, sub: sub, node: node, onServers: () => setState(() => _showServers = true));
    final panel = t.isMaterial
        ? Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 16, 16),
            child: Container(
              width: 420,
              decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerLow, borderRadius: BorderRadius.circular(28)),
              clipBehavior: Clip.antiAlias,
              child: Column(children: [
                if (vpn is VpnConnected) Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 4), child: TrafficStats(state: vpn)),
                const SizedBox(height: 8),
                Expanded(child: right),
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
              panel,
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

// ── Правая панель Windows: Сервер / Скорость / Сессия / События ────────────
//
// Справочная: только то, что полезно видеть, — без переключателей (они в
// Настройках). Данные — из провайдеров «Оникс» и activity_provider.dart.

class _SidePanel extends ConsumerWidget {
  const _SidePanel({required this.vpn, required this.sub, required this.node, required this.onServers});
  final VpnState vpn;
  final SubscriptionState sub;
  final Node? node;
  final VoidCallback onServers;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = OnyxTokens.of(context);
    final settings = ref.watch(settingsProvider);
    final speed = ref.watch(speedProvider);
    final events = ref.watch(activityProvider);
    final connected = vpn is VpnConnected;
    Widget section(String title, List<Widget> children, {Widget? trailing, bool last = false}) => Container(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
          decoration: BoxDecoration(border: last || t.isSignal ? null : Border(bottom: BorderSide(color: t.line))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            SizedBox(
              height: 20,
              child: Row(children: [
                Expanded(child: Text(title.toUpperCase(), style: t.caps(size: 10.5, color: t.textFaint))),
                if (trailing != null) trailing,
              ]),
            ),
            const SizedBox(height: 12),
            ...children,
          ]),
        );
    Widget kv(String k, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            Expanded(child: Text(k, style: TextStyle(fontFamily: t.bodyFont, fontSize: 13, color: t.textMuted))),
            Text(v, style: TextStyle(fontFamily: t.bodyFont, fontSize: 13, fontWeight: FontWeight.w500, color: t.text, fontFeatures: const [FontFeature.tabularFigures()])),
          ]),
        );
    final last = speed.isEmpty ? null : speed.last;
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        section('Сервер', [
          ServerCard(node: node, sub: sub, locked: connected, onTap: onServers),
          const SizedBox(height: 12),
          _StatusLine(node: node, autoFailover: settings.autoFailover),
        ], trailing: _PanelLink(label: 'Сменить', onTap: onServers)),
        section('Скорость', [
          Row(children: [
            Expanded(child: _Rate(glyph: OnyxGlyph.down, label: 'Приём', value: connected && last != null ? last.down : null)),
            Expanded(child: _Rate(glyph: OnyxGlyph.up, label: 'Отдача', value: connected && last != null ? last.up : null, muted: true)),
          ]),
          const SizedBox(height: 14),
          SpeedSparkline(samples: connected ? speed : const []),
        ], trailing: Text('60 с', style: t.caps(size: 10.5, color: t.textFaint))),
        section('Сессия', [
          SecondTicker(
            active: connected,
            builder: (_) => Column(children: [
              kv('Время', connected ? formatClock((vpn as VpnConnected).uptime) : '—'),
              kv('Получено', connected ? formatBytes((vpn as VpnConnected).rxBytes) : '—'),
              kv('Отправлено', connected ? formatBytes((vpn as VpnConnected).txBytes) : '—'),
              kv('Адрес сервера', node?.host ?? '—'),
            ]),
          ),
        ]),
        section('События', [
          if (events.isEmpty)
            Text('Пока тихо', style: TextStyle(fontFamily: t.bodyFont, fontSize: 12.5, color: t.textFaint))
          else
            for (final e in events.take(5)) _EventRow(event: e),
        ], last: true),
      ],
    );
  }
}

/// «Сменить ›» в шапке секции.
class _PanelLink extends StatelessWidget {
  const _PanelLink({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    final c = t.isSignal ? t.text : t.accent;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(t.isSignal ? label.toUpperCase() : label,
              style: t.isSignal ? t.caps(size: 10.5, color: c) : TextStyle(fontFamily: t.bodyFont, fontSize: 12.5, fontWeight: FontWeight.w500, color: c)),
          const SizedBox(width: 2),
          OnyxIcon(OnyxGlyph.chevronRight, size: 13, color: c),
        ]),
      ),
    );
  }
}

/// Мини-строка статуса: голос (UDP) и автопереключение — только чтение.
class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.node, required this.autoFailover});
  final Node? node;
  final bool autoFailover;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    final good = t.isSignal ? t.text : t.accent;
    final (String voice, Color voiceColor) = switch (node?.udpStatus) {
      UdpStatus.ok => ('Голос · UDP работает', good),
      UdpStatus.blocked => ('Голос · UDP заблокирован', t.danger),
      UdpStatus.unreachable => ('Сервер не отвечает', t.danger),
      _ => ('Голос · не проверен', t.textFaint),
    };
    Widget pill(String text, Color dot) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: t.isSignal ? t.surfaceHigh : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: t.isOnyx ? Border.all(color: t.line) : null,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 6, height: 6, decoration: BoxDecoration(shape: BoxShape.circle, color: dot)),
            const SizedBox(width: 7),
            Text(t.isSignal ? text.toUpperCase() : text,
                style: t.isSignal ? t.caps(size: 9.5, color: t.textMuted) : TextStyle(fontFamily: t.bodyFont, fontSize: 11.5, color: t.textMuted)),
          ]),
        );
    return Wrap(spacing: 6, runSpacing: 6, children: [
      pill(voice, voiceColor),
      pill(autoFailover ? 'Автопереключение' : 'Автопереключение выкл', autoFailover ? good : t.textFaint),
    ]);
  }
}

/// Текущая скорость: «↓ 4.2 МБ/с».
class _Rate extends StatelessWidget {
  const _Rate({required this.glyph, required this.label, required this.value, this.muted = false});
  final OnyxGlyph glyph;
  final String label;
  final double? value;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    final v = value;
    final text = v == null ? '—' : formatBytes(v.round());
    final i = text.lastIndexOf(' ');
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text.rich(TextSpan(children: [
        TextSpan(text: i < 0 ? text : text.substring(0, i), style: t.numbers(size: 22, weight: t.isSignal ? FontWeight.w500 : null)),
        if (i >= 0)
          TextSpan(
            text: ' ${text.substring(i + 1)}/с',
            style: TextStyle(fontFamily: t.isSignal ? t.monoFont : t.displayFont, fontSize: 12, color: t.textMuted),
          ),
      ])),
      const SizedBox(height: 4),
      Row(children: [
        Container(width: 8, height: 2, color: muted ? (t.isSignal ? const Color(0xFF5A5A5A) : t.textFaint) : (t.isSignal ? t.text : t.accent)),
        const SizedBox(width: 6),
        OnyxIcon(glyph, size: 10, color: t.textFaint),
        const SizedBox(width: 4),
        Text(label.toUpperCase(), style: t.caps(size: 10, color: t.textFaint)),
      ]),
    ]);
  }
}

/// График скорости за минуту: Onyx — линия с шампань-заливкой, Signal —
/// точки, как кольцо кнопки.
class SpeedSparkline extends StatelessWidget {
  const SpeedSparkline({super.key, required this.samples, this.height = 64});
  final List<SpeedSample> samples;
  final double height;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    return RepaintBoundary(
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: CustomPaint(
          painter: _SparkPainter(
            samples: samples,
            down: t.isSignal ? t.text : t.accent,
            up: t.isSignal ? const Color(0xFF5A5A5A) : t.textFaint,
            grid: t.isSignal ? const Color(0xFF1C1C1C) : t.line,
            dots: t.isSignal,
          ),
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({required this.samples, required this.down, required this.up, required this.grid, required this.dots});
  final List<SpeedSample> samples;
  final Color down, up, grid;
  final bool dots;

  @override
  void paint(Canvas canvas, Size size) {
    const n = SpeedHistory.limit;
    final w = size.width, h = size.height;
    // Сетка: три пунктирные горизонтали.
    final g = Paint()..color = grid;
    for (var k = 0; k < 3; k++) {
      final y = (h - 1) * k / 2;
      for (var x = 0.0; x < w; x += 6) {
        canvas.drawRect(Rect.fromLTWH(x, y, 2, 1), g);
      }
    }
    if (samples.isEmpty) return;
    var top = 64 * 1024.0;
    for (final s in samples) {
      top = math.max(top, math.max(s.down, s.up));
    }
    top *= 1.15;
    double x(int i) => w * (i + n - samples.length) / (n - 1);
    double y(double v) => h - 1 - (v / top) * (h - 4);
    if (dots) {
      final pd = Paint()..color = down;
      final pu = Paint()..color = up;
      for (var i = 0; i < samples.length; i++) {
        canvas.drawCircle(Offset(x(i), y(samples[i].up)), 1.3, pu);
        canvas.drawCircle(Offset(x(i), y(samples[i].down)), 1.8, pd);
      }
      return;
    }
    Path line(double Function(SpeedSample) f) {
      final p = Path()..moveTo(x(0), y(f(samples[0])));
      for (var i = 1; i < samples.length; i++) {
        final x0 = x(i - 1), x1 = x(i);
        final y0 = y(f(samples[i - 1])), y1 = y(f(samples[i]));
        p.cubicTo((x0 + x1) / 2, y0, (x0 + x1) / 2, y1, x1, y1);
      }
      return p;
    }

    final dl = line((s) => s.down);
    final fill = Path.from(dl)
      ..lineTo(x(samples.length - 1), h)
      ..lineTo(x(0), h)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [down.withValues(alpha: .22), down.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(line((s) => s.up), Paint()
      ..color = up
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2);
    canvas.drawPath(dl, Paint()
      ..color = down
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6);
  }

  @override
  bool shouldRepaint(_SparkPainter o) => o.samples != samples || o.down != down || o.dots != dots;
}

/// Строка ленты событий: время, метка, текст.
class _EventRow extends StatelessWidget {
  const _EventRow({required this.event});
  final ActivityEvent event;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    String two(int v) => v.toString().padLeft(2, '0');
    final good = t.isSignal ? t.text : t.accent;
    final dot = switch (event.kind) {
      ActivityKind.connected => good,
      ActivityKind.switched => t.isSignal ? AppTheme.signalRec : t.accentMuted,
      ActivityKind.warning => t.accentMuted,
      ActivityKind.error => t.danger,
      _ => t.textFaint,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 42,
          child: Text('${two(event.at.hour)}:${two(event.at.minute)}',
              style: TextStyle(fontFamily: t.monoFont, fontSize: 11.5, color: t.textFaint, fontFeatures: const [FontFeature.tabularFigures()])),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 5, right: 9),
          child: Container(width: 5, height: 5, decoration: BoxDecoration(shape: BoxShape.circle, color: dot)),
        ),
        Expanded(
          child: Text(event.text,
              maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontFamily: t.bodyFont, fontSize: 12.5, height: 1.3, color: t.textMuted)),
        ),
      ]),
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
