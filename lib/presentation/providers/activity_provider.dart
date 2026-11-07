// Лента событий и история скорости для правой панели окна Windows (#47).
//
// Только вид: слушают состояние VPN и этапы автопилота «Оникс»
// (vpnControllerProvider, connectPhaseProvider) и ничего не меняют. Создаются
// при старте приложения (main.dart), чтобы события копились и при окне,
// спрятанном в трей.

import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/vpn_state.dart';
import '../util/country.dart';
import 'connect_phase.dart';
import 'vpn_provider.dart';

enum ActivityKind { connected, disconnected, switched, checked, warning, error }

class ActivityEvent {
  const ActivityEvent(this.at, this.text, this.kind);
  final DateTime at;
  final String text;
  final ActivityKind kind;
}

class ActivityLog extends StateNotifier<List<ActivityEvent>> {
  ActivityLog([super.state = const []]);

  static const int limit = 12;

  void add(String text, ActivityKind kind) {
    if (state.isNotEmpty && state.first.text == text) return;
    state = [ActivityEvent(DateTime.now(), text, kind), ...state.take(limit - 1)];
  }
}

final activityProvider = StateNotifierProvider<ActivityLog, List<ActivityEvent>>((ref) {
  final log = ActivityLog();
  ref.listen<VpnState>(vpnControllerProvider, (prev, next) {
    switch (next) {
      case VpnConnected(:final node) when prev is! VpnConnected:
        log.add('Подключено · ${displayNodeName(node.name)}', ActivityKind.connected);
      case VpnDisconnected() when prev is VpnConnected || prev is VpnDisconnecting:
        log.add('Отключено', ActivityKind.disconnected);
      case VpnError(:final message) when prev is! VpnError:
        log.add(message.isEmpty ? 'Ошибка подключения' : message, ActivityKind.error);
      default:
        break;
    }
  });
  ref.listen<ConnectPhase>(connectPhaseProvider, (prev, next) {
    if (prev is ConnectChecking && next is! ConnectChecking && prev.total > 0) {
      log.add('Проверено серверов: ${prev.total}', ActivityKind.checked);
    }
    switch (next) {
      case ConnectSwitching(:final from, :final to):
        log.add('Переключение: ${displayNodeName(from)} → ${displayNodeName(to)}', ActivityKind.switched);
      case ConnectNotice(:final message):
        if (!message.startsWith('Переключились')) log.add(message, ActivityKind.warning);
      case ConnectFailed(:final message):
        log.add(message, ActivityKind.error);
      default:
        break;
    }
  });
  return log;
});

/// Скорость за секунду: приём и отдача, байт/с.
class SpeedSample {
  const SpeedSample(this.down, this.up);
  final double down, up;
}

class SpeedHistory extends StateNotifier<List<SpeedSample>> {
  SpeedHistory([super.state = const []]);

  /// Последняя минута при статистике раз в секунду.
  static const int limit = 60;

  int? _rx, _tx;
  DateTime? _at;

  void sample(int rx, int tx) {
    final now = DateTime.now();
    if (_rx != null && _at != null) {
      final dt = now.difference(_at!).inMilliseconds / 1000;
      if (dt < 0.4) return;
      final s = SpeedSample(math.max(0, rx - _rx!) / dt, math.max(0, tx - _tx!) / dt);
      final next = [...state, s];
      state = next.length > limit ? next.sublist(next.length - limit) : next;
    }
    _rx = rx;
    _tx = tx;
    _at = now;
  }

  void reset() {
    _rx = _tx = null;
    _at = null;
    if (state.isNotEmpty) state = const [];
  }
}

final speedProvider = StateNotifierProvider<SpeedHistory, List<SpeedSample>>((ref) {
  final h = SpeedHistory();
  ref.listen<VpnState>(vpnControllerProvider, (prev, next) {
    if (next is VpnConnected) {
      if (prev is! VpnConnected || prev.connectedAt != next.connectedAt) h.reset();
      h.sample(next.rxBytes, next.txBytes);
    } else if (prev is VpnConnected) {
      h.reset();
    }
  });
  return h;
});
