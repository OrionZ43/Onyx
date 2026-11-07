import 'package:flutter/material.dart';

import '../../../core/theme/onyx_tokens.dart';
import '../../../core/theme/theme_kind.dart';
import '../../../domain/entities/vpn_state.dart';
import 'hero_state.dart';
import 'm3_cookie_button.dart';
import 'onyx_lens_button.dart';
import 'signal_ring_button.dart';

/// Главная кнопка подключения — своя для каждой темы.
class HeroButton extends StatelessWidget {
  const HeroButton({super.key, required this.vpn, required this.onTap, required this.size});

  final VpnState vpn;
  final VoidCallback onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final t = OnyxTokens.of(context);
    final phase = heroPhaseOf(vpn);
    return switch (t.kind) {
      AppThemeKind.onyx => OnyxLensButton(phase: phase, onTap: onTap, size: size),
      AppThemeKind.signal => SignalRingButton(
          phase: phase,
          onTap: onTap,
          size: size,
          connectedAt: vpn is VpnConnected ? (vpn as VpnConnected).connectedAt : null,
        ),
      AppThemeKind.material => M3CookieButton(phase: phase, onTap: onTap, size: size),
    };
  }
}
