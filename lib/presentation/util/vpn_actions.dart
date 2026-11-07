// Общие действия с подключением — одна логика для главного экрана, списка
// серверов, значка в трее и мини-панели (#46). Домен не дублируется: только
// вызовы VpnController / nodeSelection / autoGroup («Оникс»).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/node.dart';
import '../../domain/entities/vpn_state.dart';
import '../providers/groups_provider.dart';
import '../providers/node_provider.dart';
import '../providers/vpn_provider.dart';

/// Подключиться (выбранный вручную сервер → лучший из группы автовыбора) или
/// отключиться. Возвращает false, если подключаться не к чему.
Future<bool> toggleConnection(WidgetRef ref) async {
  final state = ref.read(vpnControllerProvider);
  final ctl = ref.read(vpnControllerProvider.notifier);
  switch (state) {
    case VpnConnected() || VpnConnecting() || VpnDisconnecting():
      await ctl.disconnect();
      return true;
    case VpnDisconnected() || VpnError():
      final node = ref.read(nodeSelectionProvider) ?? ref.read(autoNodeProvider);
      if (node == null) return false;
      await ctl.connect(node);
      return true;
  }
}

/// Выбрать сервер вручную; [node] == null — «Автовыбор». Если уже подключены
/// к другому серверу — переподключаемся к новому выбору.
Future<void> chooseNode(WidgetRef ref, Node? node) async {
  final sel = ref.read(nodeSelectionProvider.notifier);
  if (node == null) {
    sel.clear();
  } else {
    sel.select(node);
  }
  final v = ref.read(vpnControllerProvider);
  final target = node ?? ref.read(autoNodeProvider);
  if (v is VpnConnected && target != null && v.node.id != target.id) {
    final ctl = ref.read(vpnControllerProvider.notifier);
    await ctl.disconnect();
    await ctl.connect(target);
  }
}

/// «Автовыбор из группы [groupId]» (null — по всем): группа для автовыбора +
/// сброс ручного выбора.
Future<void> chooseAutoGroup(WidgetRef ref, String? groupId) async {
  await ref.read(autoGroupProvider.notifier).setAutoGroup(groupId);
  await chooseNode(ref, null);
}
