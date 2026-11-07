// Значок Onyx в трее Windows (#42, #46).
//
// * иконка по состоянию: отключено (контур) / подключение (полупрозрачная) /
//   подключено (силуэт с меткой) / ошибка (красная метка); файлы —
//   assets/tray/*.ico из фирменной геометрии (docs/redesign/src/tool);
// * тултип: состояние · сервер · пинг.
//
// Меню у значка — не системное контекстное, а своя мини-панель Onyx
// (tray_flyout.dart, #46); показ и скрытие — в main.dart.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';

import '../../core/log_service.dart';
import '../../domain/entities/vpn_state.dart';
import '../providers/groups_provider.dart';
import '../providers/node_provider.dart';
import '../providers/vpn_provider.dart';
import '../util/country.dart';

class OnyxTray {
  OnyxTray({required this.ref});

  final WidgetRef ref;

  String _lastIcon = '';
  String _lastTip = '';

  String _iconFor(VpnState s) => switch (s) {
        VpnConnected() => 'assets/tray/tray_on.ico',
        VpnConnecting() || VpnDisconnecting() => 'assets/tray/tray_ing.ico',
        VpnError() => 'assets/tray/tray_err.ico',
        _ => 'assets/tray/tray_off.ico',
      };

  /// Привести иконку и тултип в соответствие с состоянием.
  Future<void> sync() async {
    try {
      final vpn = ref.read(vpnControllerProvider);
      final current = switch (vpn) {
        VpnConnected(node: final n) || VpnConnecting(node: final n) || VpnDisconnecting(node: final n) => n,
        _ => ref.read(nodeSelectionProvider) ?? ref.read(autoNodeProvider),
      };

      final icon = _iconFor(vpn);
      if (icon != _lastIcon) {
        _lastIcon = icon;
        await trayManager.setIcon(icon);
      }

      final state = switch (vpn) {
        VpnConnected() => 'Защищено',
        VpnConnecting() => 'Подключение…',
        VpnDisconnecting() => 'Отключение…',
        VpnError() => 'Нет соединения',
        _ => 'Не защищено',
      };
      final serverName = current == null ? 'нет сервера' : displayNodeName(current.name);
      final ping = current?.latencyMs == null ? '' : ' · ${current!.latencyMs} мс';
      // Windows обрезает тултип трея до 127 символов.
      var tip = 'Onyx — $state\n$serverName$ping';
      if (tip.length > 120) tip = tip.substring(0, 120);
      if (tip != _lastTip) {
        _lastTip = tip;
        await trayManager.setToolTip(tip);
      }
    } catch (e) {
      log.w('Трей: не удалось обновить ($e)', tag: 'TRAY');
    }
  }
}
