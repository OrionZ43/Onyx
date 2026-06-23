// lib/presentation/screens/home_screen.dart
//
// ИСПРАВЛЕНИЯ И РЕДИЗАЙН:
//  1. Убраны все WidgetsBinding.instance.addPostFrameCallback при навигации.
//     Используется if (!context.mounted) return; Navigator.of(context).push(...)
//  2. Логотип — чисто текстовый «ONYX» без щита.
//  3. Под логотипом кликабельная подпись «by Orion_Z43» → https://t.me/Orion_Z43
//  4. Desktop-first layout: ConstrainedBox maxWidth 820, центрирован.
//  5. _ServerCard использует nodeSelectionProvider — отображает выбранный сервер.
//  6. Логи и подписки открываются как элегантные десктопные диалоговые панели.

import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/glass_widget.dart';
import '../../core/cosmic_background.dart';
import '../../domain/entities/vpn_state.dart';
import '../providers/vpn_provider.dart';
import '../providers/subscription_provider.dart';
import '../providers/node_provider.dart';
import '../widgets/node_list_sheet.dart';
import 'log_screen.dart';
import 'subscription_manager_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});
  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  late AnimationController _bgCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _orbitCtrl;
  late AnimationController _connectedCtrl;

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 18),
    )..repeat();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
    _orbitCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
    _connectedCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    _pulseCtrl.dispose();
    _orbitCtrl.dispose();
    _connectedCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vpn = ref.watch(vpnControllerProvider);
    final sub = ref.watch(subscriptionProvider);
    final isConnected = vpn is VpnConnected;

    return Scaffold(
      backgroundColor: AppColors.void0,
      body: Stack(
        children: [
          RepaintBoundary(
            child: CosmicBackground(
              animation: _bgCtrl,
              intensity: isConnected ? 0.6 : 1.0,
            ),
          ),

          // Зелёное свечение при подключении
          if (isConnected)
            AnimatedBuilder(
              animation: _connectedCtrl,
              builder: (_, __) => Container(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(0, 0.2),
                    radius: 1.2,
                    colors: [
                      AppColors.accentGold.withValues(
                        alpha: 0.06 + 0.04 * _connectedCtrl.value,
                      ),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: Column(
                  children: [
                    // ── Топ-бар ─────────────────────────────────────────────
                    _TopBar(
                      onLogTap: () {
                        if (!context.mounted) return;
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const LogScreen()),
                        );
                      },
                      onSubTap: () {
                        if (!context.mounted) return;
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const SubscriptionManagerScreen(),
                          ),
                        );
                      },
                    ),

                    // ── Основной контент ─────────────────────────────────────
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Spacer(flex: 1),

                          // Статус
                          _StatusChip(state: vpn)
                              .animate()
                              .fadeIn(duration: 600.ms)
                              .slideY(begin: -0.3),

                          const SizedBox(height: 44),

                          // Главная кнопка
                          _EclipseButton(
                            state: vpn,
                            pulseCtrl: _pulseCtrl,
                            orbitCtrl: _orbitCtrl,
                            onTap: () => _handleTap(vpn, sub),
                          )
                              .animate()
                              .fadeIn(duration: 900.ms, delay: 100.ms)
                              .scale(begin: const Offset(0.85, 0.85)),

                          const SizedBox(height: 44),

                          // Селектор сервера
                          _ServerCard(sub: sub, vpn: vpn)
                              .animate()
                              .fadeIn(duration: 600.ms, delay: 200.ms)
                              .slideY(begin: 0.3),

                          const Spacer(flex: 1),

                          // Трафик (только при подключении)
                          if (vpn is VpnConnected)
                            _TrafficPanel(state: vpn)
                                .animate()
                                .fadeIn(duration: 500.ms)
                                .slideY(begin: 0.4),

                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _handleTap(VpnState state, SubscriptionState sub) {
    HapticFeedback.mediumImpact();
    final vpn = ref.read(vpnControllerProvider.notifier);
    switch (state) {
      case VpnDisconnected() || VpnError():
        // Приоритет: выбранный пользователем сервер → bestNode
        final picked = ref.read(nodeSelectionProvider);
        final node = picked ?? sub.bestNode;
        if (node != null) {
          vpn.connect(node);
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Нет доступных серверов')),
          );
        }
      case VpnConnected() || VpnConnecting() || VpnDisconnecting():
        vpn.disconnect();
    }
  }
}

// ── Top bar ────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  const _TopBar({required this.onLogTap, required this.onSubTap});
  final VoidCallback onLogTap;
  final VoidCallback onSubTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          // ── Логотип: чисто текстовый ONYX + by Orion_Z43 ──────────────
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ShaderMask(
                shaderCallback: (b) => AppColors.gradientGlass().createShader(
                  Rect.fromLTWH(0, 0, b.width, b.height),
                ),
                child: const Text(
                  'ONYX',
                  style: TextStyle(
                    fontFamily: 'Syne',
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 6,
                    color: Colors.white,
                  ),
                ),
              ),
              GestureDetector(
                onTap: () async {
                  final uri = Uri.parse('https://t.me/Orion_Z43');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                child: Text(
                  'by Orion_Z43',
                  style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 10,
                    color: AppColors.nebula2,
                    decoration: TextDecoration.underline,
                    decorationColor: AppColors.nebula2.withValues(alpha: 0.4),
                  ),
                ),
              ),
            ],
          ),

          const Spacer(),

          // ── Кнопки управления ──────────────────────────────────────────
          _GlassIconBtn(icon: Icons.terminal_rounded, onTap: onLogTap),
          const SizedBox(width: 8),
          _GlassIconBtn(icon: Icons.tune_rounded, onTap: onSubTap),
        ],
      ),
    );
  }
}

class _GlassIconBtn extends StatelessWidget {
  const _GlassIconBtn({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.glass,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.glassBorder, width: 1),
              ),
              child: Icon(icon, size: 18, color: AppColors.nebula1),
            ),
          ),
        ),
      );
}

// ── Статусный чип ──────────────────────────────────────────────────────────

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.state});
  final VpnState state;

  @override
  Widget build(BuildContext context) {
    final (label, sub, color) = switch (state) {
      VpnDisconnected() => ('Не защищён', 'Трафик открыт', AppColors.nova),
      VpnConnecting() => (
          'Подключение...',
          'Устанавливаем туннель',
          AppColors.accentSilver,
        ),
      VpnConnected() => ('Защищён', 'Трафик зашифрован', AppColors.accentGold),
      VpnDisconnecting() => (
          'Отключение...',
          'Закрываем туннель',
          AppColors.accentSilver,
        ),
      VpnError(message: final msg) => ('Ошибка', msg, AppColors.nova),
    };

    final isLoading = state is VpnConnecting || state is VpnDisconnecting;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      transitionBuilder: (child, anim) => FadeTransition(
        opacity: anim,
        child: ScaleTransition(scale: anim, child: child),
      ),
      child: GlassPill(
        key: ValueKey(state.runtimeType),
        color: color,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLoading)
              SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: color,
                ),
              )
            else
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.8),
                      blurRadius: 6,
                    ),
                  ],
                ),
              ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontFamily: 'Syne',
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
                Text(
                  sub,
                  style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 10,
                    color: color.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ── Затмение (Кнопка подключения) ───────────────────────────────────────────

class _EclipseButton extends StatelessWidget {
  const _EclipseButton({
    required this.state,
    required this.pulseCtrl,
    required this.orbitCtrl,
    required this.onTap,
  });
  final VpnState state;
  final AnimationController pulseCtrl, orbitCtrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isConnected = state is VpnConnected;
    final isConnecting = state is VpnConnecting || state is VpnDisconnecting;
    final activeColor =
        isConnected ? AppColors.accentGold : AppColors.accentSilver;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedBuilder(
        animation: Listenable.merge([pulseCtrl, orbitCtrl]),
        builder: (_, __) {
          final pulse = pulseCtrl.value;
          return SizedBox(
            width: 240,
            height: 240,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Пульсирующее свечение
                Container(
                  width: 180 + 40 * pulse,
                  height: 180 + 40 * pulse,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                          color: activeColor.withValues(
                              alpha: isConnected ? 0.15 : 0.05),
                          blurRadius: 60)
                    ],
                  ),
                ),
                // Вращающийся аккреционный диск (только при подключении)
                if (isConnected || isConnecting)
                  Transform.rotate(
                    angle: orbitCtrl.value * 2 * math.pi,
                    child: Container(
                      width: 200, height: 200,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: SweepGradient(
                          colors: [
                            Colors.transparent,
                            activeColor.withValues(alpha: 0.8),
                            Colors.transparent
                          ],
                          stops: const [0.0, 0.5, 1.0],
                        ),
                      ),
                      padding: const EdgeInsets.all(2), // толщина кольца
                      child: Container(
                        decoration: const BoxDecoration(
                            shape: BoxShape.circle, color: AppColors.void0),
                      ),
                    ),
                  )
                else
                  Container(
                    width: 196,
                    height: 196,
                    decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border:
                            Border.all(color: AppColors.glassBorder, width: 1)),
                  ),
                // Само ядро (Черная дыра / Матовый камень Onyx)
                Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.void1,
                    boxShadow: const [
                      BoxShadow(color: Colors.black54, blurRadius: 20)
                    ],
                  ),
                  child: Center(
                    child: isConnecting
                        ? const CircularProgressIndicator(
                            color: AppColors.accentGold, strokeWidth: 2)
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.power_settings_new_rounded,
                                  color: isConnected
                                      ? AppColors.accentGold
                                      : AppColors.nebula1,
                                  size: 42),
                              const SizedBox(height: 12),
                              Text(isConnected ? 'СВЯЗЬ УСТАНОВЛЕНА' : 'ЗАПУСК',
                                  style: TextStyle(
                                      fontFamily: 'Syne',
                                      fontSize: 10,
                                      letterSpacing: 3,
                                      fontWeight: FontWeight.w800,
                                      color: isConnected
                                          ? AppColors.accentGold
                                          : AppColors.nebula1)),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Карточка сервера ───────────────────────────────────────────────────────

class _ServerCard extends ConsumerWidget {
  const _ServerCard({required this.sub, required this.vpn});
  final SubscriptionState sub;
  final VpnState vpn;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Приоритет: выбранный пользователем → bestNode
    final picked = ref.watch(nodeSelectionProvider);
    final best = picked ?? sub.bestNode;
    final locked = vpn is VpnConnected;
    final alive = sub.aliveNodes.length;
    final total = sub.nodes.length;
    final isDeepProbing = sub.status == SubStatus.deepProbing;

    return GestureDetector(
      onTap: locked
          ? null
          : () {
              if (!context.mounted) return;
              showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (_) => const NodeListSheet(),
              );
            },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          borderRadius: 20,
          glowColor: best?.isTrulyWorking == true
              ? AppColors.accentGold.withValues(alpha: 0.25)
              : best != null
                  ? AppColors.accentSilver.withValues(alpha: 0.15)
                  : null,
          child: Row(
            children: [
              // Индикатор
              AnimatedContainer(
                duration: const Duration(milliseconds: 400),
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: best?.isTrulyWorking == true
                      ? AppColors.accentGold
                      : best != null
                          ? AppColors.accentGold
                          : AppColors.nebula2,
                  boxShadow: best != null
                      ? [
                          BoxShadow(
                            color: AppColors.accentGold.withValues(alpha: 0.6),
                            blurRadius: 8,
                          ),
                        ]
                      : null,
                ),
              ),
              const SizedBox(width: 14),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      best?.name ?? 'Серверы не загружены',
                      style: const TextStyle(
                        fontFamily: 'Syne',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppColors.nebula0,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (total > 0) ...[
                      const SizedBox(height: 2),
                      if (isDeepProbing)
                        _DeepProbeProgress(
                          done: sub.deepProbedCount,
                          total: sub.deepProbeTotal,
                        )
                      else
                        Text(
                          '$alive из $total серверов доступно',
                          style: const TextStyle(
                            fontFamily: 'DM Sans',
                            fontSize: 11,
                            color: AppColors.nebula2,
                          ),
                        ),
                    ],
                  ],
                ),
              ),

              if (best?.isTrulyWorking == true) ...[
                _LiveBadge(),
                const SizedBox(width: 8),
              ] else if (best?.latencyMs != null) ...[
                _LatencyBadge(ms: best!.latencyMs!),
                const SizedBox(width: 8),
              ],

              if (!locked)
                const Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: AppColors.nebula2,
                  size: 20,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeepProbeProgress extends StatelessWidget {
  const _DeepProbeProgress({required this.done, required this.total});
  final int done, total;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: AppColors.accentGold,
              value: total > 0 ? done / total : null,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            'Глубокая проверка $done/$total...',
            style: const TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 11,
              color: AppColors.accentGold,
            ),
          ),
        ],
      );
}

class _LiveBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.accentGold.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: AppColors.accentGold.withValues(alpha: 0.4),
            width: 0.8,
          ),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_rounded, size: 10, color: AppColors.accentGold),
            SizedBox(width: 3),
            Text(
              'LIVE',
              style: TextStyle(
                fontFamily: 'DM Mono',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: AppColors.accentGold,
              ),
            ),
          ],
        ),
      );
}

class _LatencyBadge extends StatelessWidget {
  const _LatencyBadge({required this.ms});
  final int ms;

  Color get _color => ms < 150
      ? AppColors.accentGold
      : ms < 400
          ? AppColors.accentSilver
          : AppColors.nova;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: _color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _color.withValues(alpha: 0.3), width: 0.8),
        ),
        child: Text(
          '$msмс',
          style: TextStyle(
            fontFamily: 'DM Sans',
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: _color,
          ),
        ),
      );
}

// ── Панель трафика ─────────────────────────────────────────────────────────

class _TrafficPanel extends StatelessWidget {
  const _TrafficPanel({required this.state});
  final VpnConnected state;

  String _bytes(int b) {
    if (b < 1024) return '${b}Б';
    if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)}КБ';
    if (b < 1024 * 1024 * 1024)
      return '${(b / (1024 * 1024)).toStringAsFixed(1)}МБ';
    return '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)}ГБ';
  }

  String _time(Duration d) => '${d.inHours.toString().padLeft(2, '0')}:'
      '${(d.inMinutes % 60).toString().padLeft(2, '0')}:'
      '${(d.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        borderRadius: 22,
        glowColor: AppColors.accentGold.withValues(alpha: 0.08),
        child: Row(
          children: [
            _Stat(
              icon: Icons.arrow_downward_rounded,
              color: AppColors.accentGold,
              label: 'Получено',
              value: _bytes(state.rxBytes),
            ),
            const _Divider(),
            _Stat(
              icon: Icons.access_time_rounded,
              color: AppColors.nebula1,
              label: 'Время',
              value: _time(state.uptime),
            ),
            const _Divider(),
            _Stat(
              icon: Icons.arrow_upward_rounded,
              color: AppColors.accentSilver,
              label: 'Отправлено',
              value: _bytes(state.txBytes),
            ),
          ],
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final Color color;
  final String label, value;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 15),
            const SizedBox(height: 6),
            Text(
              value,
              style: TextStyle(
                fontFamily: 'Syne',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.nebula0,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 10,
                color: AppColors.nebula2,
              ),
            ),
          ],
        ),
      );
}

class _Divider extends StatelessWidget {
  const _Divider();
  @override
  Widget build(BuildContext context) =>
      Container(width: 1, height: 36, color: AppColors.horizon);
}
