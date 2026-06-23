// ИСПРАВЛЕНО: удалён ненужный 'import dart:ui' — все элементы из него
// уже предоставляются через 'package:flutter/material.dart'
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';
import '../../core/glass_widget.dart';
import '../../core/cosmic_background.dart';
import '../../infrastructure/singbox_bridge_windows.dart';

/// Экран первого запуска — скачивает sing-box и wintun.
/// Показывается только если бинарники не найдены.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key, required this.onComplete});
  final VoidCallback onComplete;

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen>
    with TickerProviderStateMixin {
  late AnimationController _bgCtrl;
  late AnimationController _pulseCtrl;

  _SetupStep _step = _SetupStep.idle;
  String _status = '';
  double? _progress;
  String? _error;

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.void0,
      body: Stack(
        children: [
          CosmicBackground(animation: _bgCtrl),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Иконка
                  AnimatedBuilder(
                    animation: _pulseCtrl,
                    builder: (_, __) => Container(
                      width: 96,
                      height: 96,
                      decoration: BoxDecoration(
                        gradient: AppColors.gradientGlass(),
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accentSilver.withValues(
                              alpha: 0.3 + 0.2 * _pulseCtrl.value,
                            ),
                            blurRadius: 32 + 16 * _pulseCtrl.value,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.download_rounded,
                        color: Colors.white,
                        size: 48,
                      ),
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 600.ms)
                      .scale(begin: const Offset(0.8, 0.8)),

                  const SizedBox(height: 32),

                  // Заголовок
                  const Text(
                    'Первый запуск',
                    style: TextStyle(
                      fontFamily: 'Syne',
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: AppColors.nebula0,
                    ),
                  ).animate().fadeIn(duration: 600.ms, delay: 100.ms),

                  const SizedBox(height: 12),

                  const Text(
                    'Onyx загрузит необходимые компоненты:\n'
                    'движок sing-box и драйвер WinTUN.\n\n'
                    'Потребуются права администратора\nдля создания VPN-туннеля.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 14,
                      color: AppColors.nebula1,
                      height: 1.6,
                    ),
                  ).animate().fadeIn(duration: 600.ms, delay: 200.ms),

                  const SizedBox(height: 48),

                  // Статус / прогресс
                  if (_step != _SetupStep.idle)
                    GlassCard(
                      padding: const EdgeInsets.all(20),
                      borderRadius: 20,
                      child: Column(
                        children: [
                          Row(
                            children: [
                              if (_step == _SetupStep.downloading)
                                const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.accentSilver,
                                  ),
                                )
                              else if (_step == _SetupStep.done)
                                const Icon(
                                  Icons.check_circle_rounded,
                                  color: AppColors.accentGold,
                                  size: 16,
                                )
                              else
                                const Icon(
                                  Icons.error_outline_rounded,
                                  color: AppColors.nova,
                                  size: 16,
                                ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  _status,
                                  style: const TextStyle(
                                    fontFamily: 'DM Sans',
                                    fontSize: 13,
                                    color: AppColors.nebula1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (_progress != null) ...[
                            const SizedBox(height: 12),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: _progress,
                                backgroundColor: AppColors.void3,
                                color: AppColors.accentSilver,
                                minHeight: 4,
                              ),
                            ),
                          ],
                          if (_error != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              _error!,
                              maxLines: 3, // <--- ДОБАВИЛИ
                              overflow: TextOverflow.ellipsis, // <--- ДОБАВИЛИ
                              style: const TextStyle(
                                fontFamily: 'DM Mono',
                                fontSize: 11,
                                color: AppColors.nova,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ).animate().fadeIn(duration: 400.ms),

                  if (_step == _SetupStep.idle ||
                      _step == _SetupStep.error) ...[
                    const SizedBox(height: 24),
                    GestureDetector(
                      onTap: _download,
                      child: Container(
                        width: double.infinity,
                        height: 56,
                        decoration: BoxDecoration(
                          gradient: AppColors.gradientGlass(),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [
                            BoxShadow(
                              color:
                                  AppColors.accentSilver.withValues(alpha: 0.4),
                              blurRadius: 20,
                            ),
                          ],
                        ),
                        child: Center(
                          child: Text(
                            _step == _SetupStep.error
                                ? 'Попробовать снова'
                                : 'Загрузить компоненты',
                            style: const TextStyle(
                              fontFamily: 'Syne',
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ).animate().fadeIn(duration: 600.ms, delay: 300.ms),
                  ],

                  // Инфо о размере
                  if (_step == _SetupStep.idle) ...[
                    const SizedBox(height: 16),
                    const Text(
                      '≈ 25 МБ · только один раз',
                      style: TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 12,
                        color: AppColors.nebula2,
                      ),
                    ).animate().fadeIn(duration: 600.ms, delay: 400.ms),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _download() async {
    setState(() {
      _step = _SetupStep.downloading;
      _error = null;
      _status = 'Подготовка...';
      _progress = 0;
    });

    try {
      await SingboxBridgeWindows.instance.ensureBinaries(
        onStatus: (status, progress) {
          if (mounted) {
            setState(() {
              _status = status;
              _progress = progress;
            });
          }
        },
      );

      setState(() {
        _step = _SetupStep.done;
        _status = 'Всё готово!';
        _progress = 1.0;
      });

      await Future.delayed(const Duration(milliseconds: 800));
      widget.onComplete();
    } catch (e) {
      setState(() {
        _step = _SetupStep.error;
        _status = 'Ошибка загрузки';
        _error = e.toString();
      });
    }
  }
}

enum _SetupStep { idle, downloading, done, error }
