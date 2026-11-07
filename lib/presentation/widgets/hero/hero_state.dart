import 'dart:math' as math;

import '../../../domain/entities/vpn_state.dart';

/// Состояние главной кнопки — общее для трёх тем.
enum HeroPhase { off, connecting, on, error }

HeroPhase heroPhaseOf(VpnState s) => switch (s) {
      VpnDisconnected() => HeroPhase.off,
      VpnConnecting() || VpnDisconnecting() => HeroPhase.connecting,
      VpnConnected() => HeroPhase.on,
      VpnError() => HeroPhase.error,
    };

/// Подпись действия внутри/под кнопкой.
String heroActionLabel(HeroPhase p) => switch (p) {
      HeroPhase.off => 'Подключить',
      HeroPhase.connecting => 'Отмена',
      HeroPhase.on => 'Отключить',
      HeroPhase.error => 'Повторить',
    };

/// Прогресс подключения без данных от ядра: быстро растёт и асимптотически
/// подходит к 90 %, чтобы не «застревать» визуально и не врать о 100 %.
double connectingProgress(Duration elapsed) {
  final s = elapsed.inMilliseconds / 1000;
  return 0.9 * (1 - math.exp(-s / 2.2));
}
