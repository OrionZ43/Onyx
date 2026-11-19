import 'package:flutter/material.dart';

import '../../../core/theme/onyx_tokens.dart';
import '../../../core/theme/theme_kind.dart';
import '../../../domain/entities/vpn_state.dart';
import 'hero_state.dart';
import 'm3_shape_button.dart';
import 'onyx_lens_button.dart';
import 'signal_ring_button.dart';

/// Главная кнопка подключения — своя для каждой темы.
class HeroButton extends StatelessWidget {
  const HeroButton({super.key, required this.vpn, required this.onTap, required this.size, this.compact = false, this.phase, this.progress});

  final VpnState vpn;
  final VoidCallback onTap;
  final double size;

  /// Мини-версия без подписей (панель в трее).
  final bool compact;

  /// Этап поверх состояния VPN — автоподключение (#47): пока Onyx обновляет
  /// подписку и проверяет серверы, VPN ещё выключен, а «Линза» уже крутится.
  final HeroPhase? phase;

  /// Настоящий прогресс этапа 0..1 (проверено серверов из всех) — null,
  /// если этап без счётчика.
  final double? progress;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    final phase = this.phase ?? heroPhaseOf(vpn);
    return switch (t.kind) {
      AppThemeKind.onyx => OnyxLensButton(phase: phase, onTap: onTap, size: size, compact: compact, progress: progress),
      AppThemeKind.signal => SignalRingButton(
          phase: phase,
          onTap: onTap,
          size: size,
          compact: compact,
          progress: progress,
          connectedAt: vpn is VpnConnected ? (vpn as VpnConnected).connectedAt : null,
        ),
      AppThemeKind.material => M3ShapeButton(phase: phase, onTap: onTap, size: size),
    };
  }
}
