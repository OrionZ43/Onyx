import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import '../core/log_service.dart';

/// Управляет собственным persistent-уведомлением Android со статусом VPN,
/// живой скоростью трафика и кнопкой "Отключить".
///
/// Это НЕ то уведомление, что создаёт flutter_v2ray внутри своего
/// VpnService (тот всё ещё есть — Android требует foreground-уведомление
/// для любого активного VpnService, это системное ограничение и убрать
/// его нельзя). Это ВТОРОЕ, отдельное уведомление, полностью под нашим
/// контролем: наш текст, наш дизайн частот обновления, и, самое главное —
/// наша кнопка "Отключить", которая реально дёргает VpnController, а не
/// только native VpnService.
///
/// Только для Android. На Windows все методы — no-op.
class VpnNotificationService {
  VpnNotificationService._();
  static final instance = VpnNotificationService._();

  static const _methodChannel = MethodChannel('z43.studios.onyx/native');
  static const _eventChannel =
  EventChannel('z43.studios.onyx/notification_events');

  StreamSubscription? _eventSub;
  final _disconnectRequestedCtrl = StreamController<void>.broadcast();

  /// Эмитит событие каждый раз, когда пользователь жмёт "Отключить"
  /// в системном уведомлении из шторки.
  Stream<void> get onDisconnectRequested => _disconnectRequestedCtrl.stream;

  bool _listening = false;

  /// Подписывается на события кнопки уведомления. Вызывать один раз при
  /// старте приложения (например в main.dart или в VpnController).
  void startListening() {
    if (!Platform.isAndroid || _listening) return;
    _listening = true;

    _eventSub = _eventChannel.receiveBroadcastStream().listen(
          (event) {
        if (event == 'disconnect_requested') {
          log.i('Нажата кнопка "Отключить" в уведомлении', tag: 'NOTIF');
          _disconnectRequestedCtrl.add(null);
        }
      },
      onError: (e) {
        log.w('Ошибка event channel уведомлений: $e', tag: 'NOTIF');
      },
    );
  }

  void stopListening() {
    _eventSub?.cancel();
    _eventSub = null;
    _listening = false;
  }

  /// Показывает/обновляет уведомление. Безопасно вызывать часто (каждую
  /// секунду вместе со statsStream) — NotificationCompat.setOnlyAlertOnce
  /// на нативной стороне гарантирует, что это не будет дёргать
  /// звук/вибрацию при каждом обновлении цифр трафика.
  Future<void> show({
    required String nodeName,
    required int rxBytes,
    required int txBytes,
    required bool connected,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      await _methodChannel.invokeMethod('showVpnNotification', {
        'nodeName': nodeName,
        'rxBytes': rxBytes,
        'txBytes': txBytes,
        'connected': connected,
      });
    } catch (e) {
      log.w('Не удалось показать уведомление: $e', tag: 'NOTIF');
    }
  }

  /// Убирает уведомление (VPN отключён).
  Future<void> cancel() async {
    if (!Platform.isAndroid) return;
    try {
      await _methodChannel.invokeMethod('cancelVpnNotification');
    } catch (e) {
      log.w('Не удалось убрать уведомление: $e', tag: 'NOTIF');
    }
  }

  void dispose() {
    _eventSub?.cancel();
    _disconnectRequestedCtrl.close();
  }
}