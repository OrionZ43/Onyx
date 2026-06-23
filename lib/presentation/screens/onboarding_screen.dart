// lib/presentation/screens/onboarding_screen.dart
//
// ИСПРАВЛЕНИЯ И РЕДИЗАЙН:
//  1. Убраны WidgetsBinding.instance.addPostFrameCallback при навигации
//     (pushReplacement оставлен — он нужен, но теперь с корректной проверкой).
//  2. Исправлен Overflow текста «Один тап —»: добавлен FittedBox + softWrap.
//  3. Удалён ряд с фичами (_FeaturesRow) — для десктопа не нужен.
//  4. Логотип — чисто текстовый ONYX без щита (Icons.shield_rounded убран).
//  5. Под логотипом кликабельный текст «by Orion_Z43» → https://t.me/Orion_Z43
//  6. Desktop-first: ConstrainedBox maxWidth 560, центрированный.

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../core/glass_widget.dart';
import '../../core/cosmic_background.dart';
import '../providers/subscription_provider.dart';
import 'home_screen.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen>
    with TickerProviderStateMixin {
  final _urlCtrl   = TextEditingController();
  final _focusNode = FocusNode();

  late AnimationController _bgCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _shineCtrl;

  bool _loading = false;
  String? _error;

  static const _example =
      'https://raw.githubusercontent.com/zieng2/wl/main/vless_lite.txt';

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 20))..repeat();
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2200))
      ..repeat(reverse: true);
    _shineCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 3500))..repeat();
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    _pulseCtrl.dispose();
    _shineCtrl.dispose();
    _urlCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(subscriptionProvider, (_, next) {
      if (next.status == SubStatus.ready && next.nodes.isNotEmpty) {
        // Навигация: addPostFrameCallback здесь корректен — мы внутри
        // ref.listen (не в build-методе напрямую), но для надёжности
        // добавляем проверку mounted.
        if (!mounted) return;
        Navigator.of(context).pushReplacement(PageRouteBuilder(
          pageBuilder: (_, a, __) => const HomeScreen(),
          transitionsBuilder: (_, a, __, child) =>
              FadeTransition(opacity: a, child: child),
          transitionDuration: const Duration(milliseconds: 800),
        ));
      }
      if (next.status == SubStatus.error) {
        setState(() { _loading = false; _error = next.error; });
      }
      if (next.status == SubStatus.fetching
          || next.status == SubStatus.probing
          || next.status == SubStatus.deepProbing) {
        setState(() => _loading = true);
      }
    });

    final sub = ref.watch(subscriptionProvider);

    return Scaffold(
      backgroundColor: AppColors.void0,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          CosmicBackground(animation: _bgCtrl),

          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 56),

                      // ── Логотип: текст + by Orion_Z43 ─────────────────
                      _OnyxLogo(pulseCtrl: _pulseCtrl)
                          .animate().fadeIn(duration: 800.ms).slideY(begin: -0.3),

                      const SizedBox(height: 52),

                      // ── Заголовок (FIXED overflow) ─────────────────────
                      const _Headline()
                          .animate().fadeIn(duration: 700.ms, delay: 150.ms)
                          .slideY(begin: 0.2),

                      const SizedBox(height: 48),

                      // ── Поле ввода ─────────────────────────────────────
                      _UrlInput(
                        controller: _urlCtrl,
                        focusNode: _focusNode,
                        error: _error,
                        onPaste: () async {
                          final d = await Clipboard.getData('text/plain');
                          if (d?.text != null) {
                            _urlCtrl.text = d!.text!.trim();
                            setState(() => _error = null);
                          }
                        },
                        onExample: () {
                          _urlCtrl.text = _example;
                          setState(() => _error = null);
                        },
                      ).animate().fadeIn(duration: 700.ms, delay: 250.ms),

                      const SizedBox(height: 12),

                      // ── Прогресс ──────────────────────────────────────
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 400),
                        child: _loading
                            ? _ProgressBlock(state: sub)
                            .animate().fadeIn(duration: 300.ms)
                            : const SizedBox(height: 0),
                      ),

                      const SizedBox(height: 24),

                      // ── Кнопка подключения ─────────────────────────────
                      _ConnectButton(
                        loading: _loading,
                        shineCtrl: _shineCtrl,
                        onTap: _loading ? null : _connect,
                      ).animate().fadeIn(duration: 700.ms, delay: 350.ms),

                      // РЕДИЗАЙН: _FeaturesRow удалён — для десктопа не нужен

                      const SizedBox(height: 56),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _connect() {
    final url = _urlCtrl.text.trim();
    if (url.isEmpty) {
      setState(() => _error = 'Вставьте ссылку на подписку');
      return;
    }
    setState(() => _error = null);
    HapticFeedback.mediumImpact();
    ref.read(subscriptionProvider.notifier).loadFromUrl(url);
  }
}

// ── Логотип: чисто текстовый ONYX + by Orion_Z43 ─────────────────────────

class _OnyxLogo extends StatelessWidget {
  const _OnyxLogo({required this.pulseCtrl});
  final AnimationController pulseCtrl;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: pulseCtrl,
      builder: (_, __) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Текстовый логотип ONYX — крупно, без щита
            ShaderMask(
              shaderCallback: (b) => AppColors.gradientPlasma
                  .createShader(Rect.fromLTWH(0, 0, b.width, b.height)),
              child: const Text(
                'ONYX',
                style: TextStyle(
                  fontFamily: 'Syne', fontSize: 48,
                  fontWeight: FontWeight.w800, letterSpacing: 10,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 4),

            // Кликабельная подпись
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
                  fontFamily: 'DM Sans', fontSize: 12,
                  color: AppColors.nebula2,
                  decoration: TextDecoration.underline,
                  decorationColor: AppColors.nebula2.withValues(alpha: 0.4),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

// ── Заголовок (FIXED overflow) ────────────────────────────────────────────

class _Headline extends StatelessWidget {
  const _Headline();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ИСПРАВЛЕНО: FittedBox предотвращает переполнение на узких экранах
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: const Text(
            'Один тап —',
            style: TextStyle(
              fontFamily: 'Syne', fontSize: 42,
              fontWeight: FontWeight.w800, color: AppColors.nebula0,
              height: 1.1,
            ),
          ),
        ),
        const SizedBox(height: 4),
        ShaderMask(
          shaderCallback: (b) => AppColors.gradientPlasma
              .createShader(Rect.fromLTWH(0, 0, b.width, b.height)),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: const Text(
              'полная защита.',
              style: TextStyle(
                fontFamily: 'Syne', fontSize: 42,
                fontWeight: FontWeight.w800, color: Colors.white,
                height: 1.1,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Вставьте ссылку на подписку — приложение\n'
              'выберет лучший сервер автоматически.',
          style: TextStyle(
            fontFamily: 'DM Sans', fontSize: 15,
            color: AppColors.nebula1, height: 1.55,
          ),
        ),
      ],
    );
  }
}

// ── URL input ─────────────────────────────────────────────────────────────

class _UrlInput extends StatefulWidget {
  const _UrlInput({
    required this.controller,
    required this.focusNode,
    required this.onPaste,
    required this.onExample,
    this.error,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onPaste, onExample;
  final String? error;

  @override
  State<_UrlInput> createState() => _UrlInputState();
}

class _UrlInputState extends State<_UrlInput> {
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    widget.focusNode.addListener(
            () => setState(() => _focused = widget.focusNode.hasFocus));
  }

  @override
  Widget build(BuildContext context) {
    final hasError = widget.error != null;
    final borderColor = hasError
        ? AppColors.nova
        : _focused
        ? AppColors.plasma
        : AppColors.glassBorder;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: _focused
                ? [BoxShadow(
                color: AppColors.plasmaGlow,
                blurRadius: 20, spreadRadius: -2)]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
              child: Container(
                decoration: BoxDecoration(
                  gradient: AppColors.gradientGlass(),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: borderColor, width: 1.0),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 16),
                    Icon(
                      Icons.link_rounded,
                      color: _focused ? AppColors.plasma : AppColors.nebula2,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: widget.controller,
                        focusNode: widget.focusNode,
                        style: const TextStyle(
                          fontFamily: 'DM Sans',
                          color: AppColors.nebula0, fontSize: 13,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'https://example.com/subscription',
                          hintStyle: TextStyle(
                            color: AppColors.nebula2, fontSize: 13,
                          ),
                          contentPadding:
                          EdgeInsets.symmetric(vertical: 16),
                        ),
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.content_paste_rounded,
                          color: AppColors.nebula2, size: 18),
                      onPressed: widget.onPaste,
                      tooltip: 'Вставить',
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
          ),
        ),

        if (hasError) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.error_outline_rounded,
                  color: AppColors.nova, size: 14),
              const SizedBox(width: 6),
              Expanded(
                child: Text(widget.error!,
                    style: const TextStyle(color: AppColors.nova,
                        fontFamily: 'DM Sans', fontSize: 12)),
              ),
            ],
          ),
        ],

        const SizedBox(height: 10),

        GestureDetector(
          onTap: widget.onExample,
          child: Row(
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  color: AppColors.plasma, size: 12),
              const SizedBox(width: 6),
              Text('Вставить тестовую подписку',
                  style: TextStyle(
                    fontFamily: 'DM Sans', fontSize: 12,
                    color: AppColors.plasma.withValues(alpha: 0.8),
                    decoration: TextDecoration.underline,
                    decorationColor:
                    AppColors.plasma.withValues(alpha: 0.4),
                  )),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Progress block ────────────────────────────────────────────────────────

class _ProgressBlock extends StatelessWidget {
  const _ProgressBlock({required this.state});
  final SubscriptionState state;

  @override
  Widget build(BuildContext context) {
    final isProbing      = state.status == SubStatus.probing;
    final isDeepProbing  = state.status == SubStatus.deepProbing;

    final String label;
    final double? progress;

    if (isDeepProbing) {
      label    = 'Глубокая проверка топ-${state.deepProbeTotal} нод... '
          '${state.deepProbedCount}/${state.deepProbeTotal}';
      progress = state.deepProbeTotal > 0
          ? state.deepProbedCount / state.deepProbeTotal
          : null;
    } else if (isProbing) {
      label    = 'Проверяем серверы... ${state.probedCount}/${state.nodes.length}';
      progress = state.nodes.isNotEmpty
          ? state.probedCount / state.nodes.length
          : null;
    } else {
      label    = 'Загружаем список серверов...';
      progress = null;
    }

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      borderRadius: 14,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              SizedBox(
                width: 14, height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5, color: AppColors.plasma,
                  value: progress,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                      fontFamily: 'DM Sans', fontSize: 12,
                      color: AppColors.nebula1,
                    )),
              ),
            ],
          ),
          if (isProbing && progress != null) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: AppColors.void3,
                color: AppColors.plasma,
                minHeight: 3,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Connect button ────────────────────────────────────────────────────────

class _ConnectButton extends StatelessWidget {
  const _ConnectButton({
    required this.loading,
    required this.shineCtrl,
    this.onTap,
  });
  final bool loading;
  final AnimationController shineCtrl;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedBuilder(
        animation: shineCtrl,
        builder: (_, __) {
          final shine = shineCtrl.value;
          return Container(
            height: 58,
            decoration: BoxDecoration(
              gradient: onTap != null
                  ? AppColors.gradientPlasma
                  : const LinearGradient(
                  colors: [AppColors.void3, AppColors.void3]),
              borderRadius: BorderRadius.circular(18),
              boxShadow: onTap != null
                  ? [BoxShadow(
                color: AppColors.plasma.withValues(alpha: 0.4),
                blurRadius: 24, spreadRadius: -2,
              )]
                  : null,
            ),
            child: Stack(
              children: [
                if (onTap != null)
                  Positioned(
                    left: (shine * 2 - 0.5) * 300 - 60,
                    top: 0, bottom: 0,
                    child: Container(
                      width: 60,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(colors: [
                          Colors.transparent,
                          Color(0x1FFFFFFF),
                          Colors.transparent,
                        ]),
                      ),
                    ),
                  ),
                Center(
                  child: loading
                      ? const SizedBox(
                    width: 22, height: 22,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                      : const Text('Подключиться',
                      style: TextStyle(
                        fontFamily: 'Syne', fontSize: 16,
                        fontWeight: FontWeight.w700, color: Colors.white,
                      )),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}