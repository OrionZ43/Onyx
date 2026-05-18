import 'dart:async';
// ИСПРАВЛЕНО: удалён неиспользуемый 'import dart:convert'
import 'package:dio/dio.dart';
import '../core/log_service.dart';

/// Клиент к REST API sing-box (Clash-совместимый).
/// Включается в конфиге через experimental.clash_api.
class SingboxApiClient {
  SingboxApiClient({this.host = '127.0.0.1', this.port = 9090});

  final String host;
  final int port;

  late final Dio _dio = Dio(BaseOptions(
    baseUrl: 'http://$host:$port',
    connectTimeout: const Duration(seconds: 3),
    receiveTimeout: const Duration(seconds: 3),
  ));

  String get baseUrl => 'http://$host:$port';

  /// Проверяет что API отвечает (sing-box запущен и готов)
  Future<bool> isReady() async {
    try {
      final r = await _dio.get('/version');
      return r.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Ждёт пока sing-box поднимет API (до [timeout])
  Future<bool> waitReady({
    Duration timeout  = const Duration(seconds: 10),
    Duration interval = const Duration(milliseconds: 300),
  }) async {
    final deadline = DateTime.now().add(timeout);
    log.d('Ожидаем готовности API sing-box...', tag: 'API');

    while (DateTime.now().isBefore(deadline)) {
      if (await isReady()) {
        log.i('API sing-box готов', tag: 'API');
        return true;
      }
      await Future.delayed(interval);
    }

    log.e('Таймаут ожидания API sing-box', tag: 'API');
    return false;
  }

  /// Возвращает текущую скорость трафика (байт/с)
  Future<TrafficStats?> getTraffic() async {
    try {
      final r = await _dio.get('/traffic');
      if (r.statusCode == 200 && r.data is Map) {
        return TrafficStats.fromJson(r.data as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  /// Поток трафик-статистики (polling каждую секунду)
  Stream<TrafficStats> trafficStream() async* {
    while (true) {
      await Future.delayed(const Duration(seconds: 1));
      final stats = await getTraffic();
      if (stats != null) yield stats;
    }
  }

  /// Общий входящий/исходящий трафик через /connections
  Future<(int rx, int tx)> getTotalBytes() async {
    try {
      final r = await _dio.get('/connections');
      if (r.statusCode == 200 && r.data is Map) {
        final data = r.data as Map<String, dynamic>;
        final downloadTotal = data['downloadTotal'] as int? ?? 0;
        final uploadTotal   = data['uploadTotal']   as int? ?? 0;
        return (downloadTotal, uploadTotal);
      }
    } catch (_) {}
    return (0, 0);
  }

  /// Версия sing-box
  Future<String?> getVersion() async {
    try {
      final r = await _dio.get('/version');
      if (r.statusCode == 200) {
        return (r.data as Map<String, dynamic>)['version'] as String?;
      }
    } catch (_) {}
    return null;
  }
}

class TrafficStats {
  const TrafficStats({required this.upBytes, required this.downBytes});

  final int upBytes;
  final int downBytes;

  factory TrafficStats.fromJson(Map<String, dynamic> json) => TrafficStats(
    upBytes:   (json['up']   as num?)?.toInt() ?? 0,
    downBytes: (json['down'] as num?)?.toInt() ?? 0,
  );
}