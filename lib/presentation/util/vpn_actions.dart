// Общие действия с подключением — одна логика для главного экрана, списка
// серверов, значка в трее и мини-панели (#46). Домен не дублируется: только
// вызовы VpnController / nodeSelection / autoGroup / connectPhase («Оникс»).

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/entities/node.dart';
import '../../domain/entities/vpn_state.dart';
import '../providers/connect_phase.dart';
import '../providers/groups_provider.dart';
import '../providers/node_provider.dart';
import '../providers/vpn_provider.dart';

/// Чем кончился тап по «Линзе».
enum ToggleResult {
  /// Подключаемся, отключаемся или автопилот запущен.
  done,

  /// Автопилот уже обновляет подписку или проверяет серверы: отмены у него
  /// нет, второй прогон не запускаем.
  busy,
}

/// Тап по «Линзе» (#47): подключено или подключаемся — отключиться; иначе в
/// режиме «Автовыбор» — автопилот «Оникс» smartConnect() (обновит подписку,
/// проверит серверы, подключит лучший; этапы и ошибки — в
/// connectPhaseProvider), а при ручном выборе сервера — подключиться к нему.
Future<ToggleResult> toggleConnection(WidgetRef ref) async {
  final state = ref.read(vpnControllerProvider);
  final ctl = ref.read(vpnControllerProvider.notifier);
  switch (state) {
    case VpnConnected() || VpnConnecting() || VpnDisconnecting():
      await ctl.disconnect();
      return ToggleResult.done;
    case VpnDisconnected() || VpnError():
      if (ref.read(connectPhaseProvider).busy) return ToggleResult.busy;
      final picked = ref.read(nodeSelectionProvider);
      if (picked == null) {
        unawaited(ctl.smartConnect());
        return ToggleResult.done;
      }
      clearConnectFailure(ref);
      await ctl.connect(picked);
      return ToggleResult.done;
  }
}

/// Убрать карточку «не удалось подключиться», когда пользователь сам
/// выбрал, что делать дальше (сервер, группу).
void clearConnectFailure(WidgetRef ref) {
  final phase = ref.read(connectPhaseProvider.notifier);
  if (phase.state is ConnectFailed) phase.state = ConnectPhase.idle;
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
  clearConnectFailure(ref);
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
