import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/glass_widget.dart';
import '../../infrastructure/platform_features.dart';
import '../providers/settings_provider.dart';
import 'split_tunneling_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      backgroundColor: AppColors.void0,
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF0D0420), Color(0xFF03020A)],
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 700),
                child: Column(
                  children: [
                    ClipRect(
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 14,
                          ),
                          decoration: const BoxDecoration(
                            color: Color(0x99050410),
                            border: Border(
                              bottom: BorderSide(color: AppColors.glassBorder),
                            ),
                          ),
                          child: Row(
                            children: [
                              GestureDetector(
                                onTap: () {
                                  if (!context.mounted) return;
                                  Navigator.of(context).pop();
                                },
                                child: Container(
                                  width: 36,
                                  height: 36,
                                  decoration: BoxDecoration(
                                    color: AppColors.glass,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: AppColors.glassBorder,
                                    ),
                                  ),
                                  child: const Icon(
                                    Icons.arrow_back_ios_rounded,
                                    size: 14,
                                    color: AppColors.nebula1,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              const Text(
                                'Настройки',
                                style: TextStyle(
                                  fontFamily: 'Syne',
                                  fontSize: 18,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.nebula0,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListView(
                        padding: const EdgeInsets.all(24),
                        children: [
                          GlassCard(
                            padding: const EdgeInsets.all(20),
                            borderRadius: 18,
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 2),
                                  child: Icon(
                                    Icons.alt_route_rounded,
                                    color: AppColors.plasma,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Умная маршрутизация',
                                        style: TextStyle(
                                          fontFamily: 'Syne',
                                          fontSize: 16,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.nebula0,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      const Text(
                                        'При включении российские сайты (Госуслуги, Сбербанк, Яндекс, ВКонтакте и др.) будут работать напрямую в обход VPN. Это устраняет проблемы с блокировкой по гео-IP и ускоряет загрузку локальных сервисов.',
                                        style: TextStyle(
                                          fontFamily: 'DM Sans',
                                          fontSize: 13,
                                          color: AppColors.nebula1,
                                          height: 1.4,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Switch.adaptive(
                                  value: settings.smartRouting,
                                  activeThumbColor: AppColors.plasma,
                                  onChanged: (val) => ref
                                      .read(settingsProvider.notifier)
                                      .toggleSmartRouting(val),
                                ),
                              ],
                            ),
                          ),
                          // ── AI Direct Lane ───────────────────────────
                          const SizedBox(height: 16),
                          _SettingSwitchCard(
                            icon: Icons.smart_toy_rounded,
                            title: 'Приоритет для ИИ-сервисов',
                            description:
                                'Домены ChatGPT, Claude, Gemini, Grok и других '
                                'ИИ всегда идут строго через VPN, а их DNS '
                                'резолвится в зашифрованном виде внутри '
                                'туннеля. Устраняет ошибку «Access Denied» '
                                'из-за утечки DNS или геолокации.',
                            value: settings.aiDirectLane,
                            onChanged: (val) => ref
                                .read(settingsProvider.notifier)
                                .toggleAiDirectLane(val),
                          ),

                          // ── Автопереключение серверов ────────────────
                          const SizedBox(height: 16),
                          _SettingSwitchCard(
                            icon: Icons.swap_horiz_rounded,
                            title: 'Автопереключение серверов',
                            description:
                                'Если активный сервер начал подвисать (пинг '
                                'улетел, звонок заикается) или отвалился — '
                                'Onyx сам перейдёт на лучший рабочий сервер '
                                'и покажет уведомление. Переключение занимает '
                                'пару секунд.',
                            value: settings.autoFailover,
                            onChanged: (val) => ref
                                .read(settingsProvider.notifier)
                                .toggleAutoFailover(val),
                          ),

                          if (Platform.isAndroid) ...[
                            const SizedBox(height: 16),
                            _SettingSwitchCard(
                              icon: Icons.call_split_rounded,
                              title: 'Раздельный туннель',
                              description:
                                  'Выбранные приложения работают в обход VPN '
                                  'напрямую. Удобно для банковских приложений '
                                  'и локальных сервисов, которые не любят '
                                  'иностранный IP.',
                              value: settings.splitTunnelingEnabled,
                              onChanged: (val) => ref
                                  .read(settingsProvider.notifier)
                                  .toggleSplitTunneling(val),
                            ),
                            if (settings.splitTunnelingEnabled) ...[
                              const SizedBox(height: 12),
                              _NavCard(
                                icon: Icons.apps_rounded,
                                title: 'Приложения в обход VPN',
                                trailing: settings.excludedApps.isEmpty
                                    ? 'Не выбраны'
                                    : '${settings.excludedApps.length} выбрано',
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const SplitTunnelingScreen(),
                                    ),
                                  );
                                },
                              ),
                            ],

                            // ── Kill Switch (системный, Android) ───────
                            const SizedBox(height: 16),
                            _NavCard(
                              icon: Icons.gpp_maybe_rounded,
                              title: 'Kill Switch',
                              description:
                                  'Открыть системные настройки VPN. Включите '
                                  '«Always-on VPN» и «Блокировать соединения '
                                  'без VPN», чтобы трафик никогда не уходил в '
                                  'открытую сеть при обрыве туннеля.',
                              trailing: 'Настроить',
                              onTap: () =>
                                  PlatformFeatures.instance.openVpnSettings(),
                            ),
                          ],
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
}
// ── Переиспользуемые карточки настроек ───────────────────────────────────────

/// Карточка настройки с тумблером. Повторяет визуал карточки «Умная
/// маршрутизация»: иконка + заголовок Syne + описание DM Sans + Switch.
class _SettingSwitchCard extends StatelessWidget {
  const _SettingSwitchCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(20),
      borderRadius: 18,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, color: AppColors.plasma, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontFamily: 'Syne',
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.nebula0,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: const TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 13,
                    color: AppColors.nebula1,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Switch.adaptive(
            value: value,
            activeThumbColor: AppColors.plasma,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// Карточка-навигация: тап открывает экран или системное действие.
class _NavCard extends StatelessWidget {
  const _NavCard({
    required this.icon,
    required this.title,
    this.description,
    this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? description;
  final String? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: GlassCard(
        padding: const EdgeInsets.all(20),
        borderRadius: 18,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, color: AppColors.plasma, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontFamily: 'Syne',
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColors.nebula0,
                    ),
                  ),
                  if (description != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      description!,
                      style: const TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 13,
                        color: AppColors.nebula1,
                        height: 1.4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Row(
              children: [
                if (trailing != null)
                  Text(
                    trailing!,
                    style: const TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 13,
                      color: AppColors.plasmaLight,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.nebula1,
                  size: 20,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
