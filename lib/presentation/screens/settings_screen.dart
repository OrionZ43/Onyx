import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../core/glass_widget.dart';
import '../providers/settings_provider.dart';

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
                                  activeColor: AppColors.plasma,
                                  onChanged: (val) => ref
                                      .read(settingsProvider.notifier)
                                      .toggleSmartRouting(val),
                                ),
                              ],
                            ),
                          ),
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
