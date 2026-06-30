import 'package:dio/dio.dart';
import '../core/log_service.dart';
import 'entities/node.dart';
import 'subscription_parser.dart';
import 'node_sanitizer.dart';

class SubscriptionResult {
  const SubscriptionResult({
    required this.nodes,
    required this.rawUrl,
    required this.fetchedAt,
    this.error,
  });
  final List<Node> nodes;
  final String rawUrl;
  final DateTime fetchedAt;
  final String? error;
  bool get isSuccess => error == null;
}

class SubscriptionService {
  SubscriptionService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 10),
                receiveTimeout: const Duration(seconds: 15),
                headers: {'User-Agent': 'Mozilla/5.0'},
              ),
            );

  final Dio _dio;
  final _parser = const SubscriptionParser();
  final _sanitizer = const NodeSanitizer();

  Future<SubscriptionResult> fetch(String url) async {
    final cleanUrl = url.trim();
    log.i('Начинаем загрузку подписки', tag: 'SUB');
    log.d('URL: $cleanUrl', tag: 'SUB');

    final isZieng2 = cleanUrl.contains('raw.githubusercontent.com/zieng2');
    final urlsToTry = [cleanUrl];

    if (isZieng2) {
      urlsToTry.addAll([
        'https://hub.mos.ru/zieng2/wl/raw/main/list_universal.txt',
        'https://gitverse.ru/api/repos/zieng2/wl/raw/branch/master/list_universal.txt',
      ]);
    }

    String? raw;
    String? lastErrorMsg;

    for (final currentUrl in urlsToTry) {
      try {
        log.i('Отправляем HTTP GET запрос к $currentUrl...', tag: 'SUB');
        raw = await _fetchRaw(currentUrl);
        log.i('Получено ${raw.length} символов', tag: 'SUB');
        break; // Успешно загрузили
      } on DioException catch (e) {
        lastErrorMsg = _humanizeDioError(e);
        log.e('DioException: $lastErrorMsg', tag: 'SUB');
        log.d(
          'Детали: type=${e.type}, status=${e.response?.statusCode}',
          tag: 'SUB',
        );
      } catch (e, stack) {
        lastErrorMsg = 'Ошибка: $e';
        log.e('Неожиданная ошибка: $e', tag: 'SUB');
        log.d('Stack: $stack', tag: 'SUB');
      }
    }

    if (raw == null) {
      return SubscriptionResult(
        nodes: [],
        rawUrl: cleanUrl,
        fetchedAt: DateTime.now(),
        error: lastErrorMsg ?? 'Не удалось загрузить подписку.',
      );
    }

    try {
      final parsed = _parser.parse(raw);
      log.i('Распарсено узлов: ${parsed.length}', tag: 'SUB');

      if (parsed.isEmpty) {
        log.e('Ни одного vless:// URI не найдено в ответе', tag: 'SUB');
        log.d(
          'Первые 200 символов ответа: ${raw.substring(0, raw.length.clamp(0, 200))}',
          tag: 'SUB',
        );
        return SubscriptionResult(
          nodes: [],
          rawUrl: cleanUrl,
          fetchedAt: DateTime.now(),
          error: 'Не найдено ни одного vless:// узла. Проверьте URL.',
        );
      }

      log.i(
        'Применяем ТСПУ-патчи к ${parsed.length} узлам...',
        tag: 'SANITIZER',
      );
      final sanitized = _sanitizer.sanitizeAll(parsed);

      // Логируем что именно изменили
      for (var i = 0; i < parsed.length; i++) {
        final raw_ = parsed[i];
        final san = sanitized[i];
        if (raw_.fingerprint != san.fingerprint) {
          log.d(
            '  [${san.name}] fp: ${raw_.fingerprint} → ${san.fingerprint}',
            tag: 'SANITIZER',
          );
        }
        if (raw_.flow != san.flow) {
          log.d(
            '  [${san.name}] flow убит: "${raw_.flow}" → ""',
            tag: 'SANITIZER',
          );
        }
        if (!raw_.muxEnabled && san.muxEnabled) {
          log.d(
            '  [${san.name}] mux включён: smux/32 streams',
            tag: 'SANITIZER',
          );
        }
        log.d('  [${san.name}] SNI сохранён: ${san.sni}', tag: 'SANITIZER');
      }

      log.i('Санитизация завершена. Готово к проверке.', tag: 'SANITIZER');

      return SubscriptionResult(
        nodes: sanitized,
        rawUrl: cleanUrl,
        fetchedAt: DateTime.now(),
      );
    } catch (e, stack) {
      log.e('Ошибка при парсинге: $e', tag: 'SUB');
      log.d('Stack: $stack', tag: 'SUB');
      return SubscriptionResult(
        nodes: [],
        rawUrl: cleanUrl,
        fetchedAt: DateTime.now(),
        error: 'Ошибка при обработке данных: $e',
      );
    }
  }

  Future<String> _fetchRaw(String url) async {
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      log.i('Не URL — пробуем как base64 напрямую', tag: 'SUB');
      return url;
    }
    final response = await _dio.get<String>(url);
    return response.data ?? '';
  }

  String _humanizeDioError(DioException e) => switch (e.type) {
        DioExceptionType.connectionTimeout => 'Таймаут подключения (10с)',
        DioExceptionType.receiveTimeout => 'Сервер не ответил (15с)',
        DioExceptionType.badResponse => 'HTTP ${e.response?.statusCode}',
        DioExceptionType.connectionError => 'Нет соединения с интернетом',
        _ => e.message ?? 'Неизвестная ошибка сети',
      };
}
