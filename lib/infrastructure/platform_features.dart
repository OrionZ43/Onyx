import 'dart:io';
import 'package:flutter/services.dart';
import '../core/log_service.dart';

/// Информация об установленном приложении (для split tunneling).
class InstalledApp {
  const InstalledApp({
    required this.packageName,
    required this.appName,
    required this.isSystem,
  });

  final String packageName;
  final String appName;
  final bool isSystem;
}

/// Доступ к платформенным функциям Onyx через общий MethodChannel
/// z43.studios.onyx/native (тот же, что использует BinaryManager и
/// VpnNotificationService). Только Android; на других платформах методы
/// возвращают безопасные заглушки.
class PlatformFeatures {
  PlatformFeatures._();
  static final instance = PlatformFeatures._();

  static const _channel = MethodChannel('z43.studios.onyx/native');

  /// Список установленных приложений, отсортированный по имени.
  /// Пустой список на не-Android платформах и при любой ошибке.
  Future<List<InstalledApp>> getInstalledApps() async {
    if (!Platform.isAndroid) return const [];
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'getInstalledApps',
      );
      if (raw == null) return const [];
      return raw
          .whereType<Map>()
          .map(
            (m) => InstalledApp(
              packageName: m['packageName'] as String? ?? '',
              appName: m['appName'] as String? ?? '',
              isSystem: m['isSystem'] as bool? ?? false,
            ),
          )
          .where((a) => a.packageName.isNotEmpty)
          .toList();
    } catch (e) {
      log.w('Не удалось получить список приложений: $e', tag: 'NATIVE');
      return const [];
    }
  }

  /// Открывает системные настройки VPN (Always-on VPN + системный
  /// Kill Switch "Блокировать соединения без VPN").
  Future<bool> openVpnSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      await _channel.invokeMethod('openVpnSettings');
      return true;
    } catch (e) {
      log.w('Не удалось открыть настройки VPN: $e', tag: 'NATIVE');
      return false;
    }
  }
}
