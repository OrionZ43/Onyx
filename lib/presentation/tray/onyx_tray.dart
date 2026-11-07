// Значок Onyx в трее Windows (#42).
//
// * иконка по состоянию: отключено (контур) / подключение (полупрозрачная) /
//   подключено (силуэт) / ошибка (красная метка); файлы — assets/tray/*.ico,
//   их генерирует docs/redesign/src/tool/generate_icons_test.dart;
// * тултип: состояние · сервер · пинг;
// * меню: Подключить/Отключить, сервер (Автовыбор + быстрые серверы),
//   Режим Discord, Регион, Открыть окно, Выход.
//
// Команды — те же, что у главного экрана (VpnController, nodeSelection,
// settings «Оникса»). Меню пересобирается только при смене того, что в нём
// видно, — не на каждый тик трафика.

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tray_manager/tray_manager.dart';

import '../../core/log_service.dart';
import '../../domain/entities/node.dart';
import '../../domain/entities/vpn_state.dart';
import '../providers/groups_provider.dart';
import '../providers/node_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/subscription_provider.dart';
import '../providers/vpn_provider.dart';
import '../screens/groups_screen.dart' show groupLabel;
import '../util/country.dart';

class OnyxTray {
  OnyxTray({required this.ref, required this.onShow, required this.onExit});

  final WidgetRef ref;
  final VoidCallback onShow;
  final Future<void> Function() onExit;

  String _lastSignature = '';
  String _lastIcon = '';

  static const int quickServers = 10;

  String _iconFor(VpnState s) => switch (s) {
        VpnConnected() => 'assets/tray/tray_on.ico',
        VpnConnecting() || VpnDisconnecting() => 'assets/tray/tray_ing.ico',
        VpnError() => 'assets/tray/tray_err.ico',
        _ => 'assets/tray/tray_off.ico',
      };

  /// Привести иконку, тултип и меню в соответствие с состоянием.
  Future<void> sync() async {
    try {
      final vpn = ref.read(vpnControllerProvider);
      final sub = ref.read(subscriptionProvider);
      final settings = ref.read(settingsProvider);
      final picked = ref.read(nodeSelectionProvider);
      final auto = ref.read(autoNodeProvider);
      final autoGroup = ref.read(autoGroupProvider);
      final groups = ref.read(groupsProvider);
      final current = switch (vpn) {
        VpnConnected(node: final n) || VpnConnecting(node: final n) || VpnDisconnecting(node: final n) => n,
        _ => picked ?? auto,
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
      final tip = 'Onyx — $state\n$serverName$ping';
      await trayManager.setToolTip(tip.length > 120 ? tip.substring(0, 120) : tip);

      final quick = [...sub.nodes.where((n) => n.isAlive)]..sort((a, b) => (a.latencyMs ?? 99999).compareTo(b.latencyMs ?? 99999));
      final top = quick.take(quickServers).toList();
      final signature = [
        vpn.runtimeType, current?.id, picked?.id, settings.discordMode, settings.routingRegion, settings.smartRouting,
        autoGroup, groups.length, for (final n in top) '${n.id}:${n.latencyMs}',
      ].join('|');
      if (signature == _lastSignature) return;
      _lastSignature = signature;
      await trayManager.setContextMenu(_menu(vpn, state, serverName, ping, current, picked, top, settings, groupLabel(autoGroup, groups)));
    } catch (e) {
      log.w('Трей: не удалось обновить ($e)', tag: 'TRAY');
    }
  }

  Menu _menu(VpnState vpn, String state, String serverName, String ping, Node? current, Node? picked, List<Node> top,
      SettingsState settings, String autoGroupName) {
    final connected = vpn is VpnConnected || vpn is VpnConnecting;
    final ctl = ref.read(vpnControllerProvider.notifier);
    final sel = ref.read(nodeSelectionProvider.notifier);
    final set = ref.read(settingsProvider.notifier);

    Future<void> reconnectTo(Node? node) async {
      final v = ref.read(vpnControllerProvider);
      final target = node ?? ref.read(autoNodeProvider);
      if (v is VpnConnected && target != null && v.node.id != target.id) {
        await ctl.disconnect();
        await ctl.connect(target);
      }
    }

    return Menu(items: [
      MenuItem(label: 'Onyx — $state', disabled: true),
      MenuItem(label: '$serverName$ping', disabled: true),
      MenuItem.separator(),
      MenuItem(
        label: connected ? 'Отключить' : 'Подключить',
        onClick: (_) async {
          if (connected) {
            await ctl.disconnect();
          } else {
            final node = ref.read(nodeSelectionProvider) ?? ref.read(autoNodeProvider);
            if (node != null) {
              await ctl.connect(node);
            } else {
              onShow();
            }
          }
          await sync();
        },
      ),
      MenuItem.submenu(
        label: 'Сервер',
        submenu: Menu(items: [
          MenuItem.checkbox(
            label: 'Автовыбор — из «$autoGroupName»',
            checked: picked == null,
            onClick: (_) async {
              sel.clear();
              await reconnectTo(null);
              await sync();
            },
          ),
          MenuItem.separator(),
          for (final n in top)
            MenuItem.checkbox(
              label: '${displayNodeName(n.name)}${n.latencyMs == null ? '' : ' · ${n.latencyMs} мс'}${n.aiReachable ? ' · AI' : ''}',
              checked: picked?.id == n.id,
              onClick: (_) async {
                sel.select(n);
                await reconnectTo(n);
                await sync();
              },
            ),
          if (top.isEmpty) MenuItem(label: 'Нет доступных серверов', disabled: true),
          MenuItem.separator(),
          MenuItem(label: 'Все серверы…', onClick: (_) => onShow()),
        ]),
      ),
      MenuItem.checkbox(
        label: 'Режим Discord',
        checked: settings.discordMode,
        onClick: (_) async {
          await set.toggleDiscordMode(!settings.discordMode);
          await sync();
        },
      ),
      if (settings.smartRouting)
        MenuItem.submenu(
          label: 'Регион',
          submenu: Menu(items: [
            for (final r in RoutingRegion.values)
              MenuItem.checkbox(
                label: r.label,
                checked: settings.routingRegion == r,
                onClick: (_) async {
                  await set.setRoutingRegion(r);
                  await sync();
                },
              ),
          ]),
        ),
      MenuItem.separator(),
      MenuItem(label: 'Открыть Onyx', onClick: (_) => onShow()),
      MenuItem(label: 'Выход', onClick: (_) => onExit()),
    ]);
  }
}
