import 'dart:io';
import 'package:onyx_service/service_host.dart';

void main(List<String> args) {
  // Инициализируем директорию для логов, если нужно (для отладки)
  final localAppData = Platform.environment['LOCALAPPDATA'];
  if (localAppData != null) {
    final logDir = Directory('$localAppData\\Onyx\\logs');
    if (!logDir.existsSync()) {
      logDir.createSync(recursive: true);
    }
  }

  // Запуск сервиса
  startServiceHost(args);
}
