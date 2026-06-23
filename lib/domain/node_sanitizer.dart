import 'entities/node.dart';

/// Умный ТСПУ-aware sanitizer.
class NodeSanitizer {
  const NodeSanitizer();

  static const _safeFp = 'chrome';

  /// Максимальное количество потоков smux для Reality/TCP-серверов.
  static const _muxMaxStreams = 8;

  Node sanitize(Node raw) {
    Node node = raw;

    // 1. Нормализация отпечатка браузера
    node = _patchFingerprint(node);

    // 2. УМНАЯ ЛОГИКА ТСПУ:
    final isTcp = node.network == 'tcp' || node.network == 'raw';

    if (isTcp && node.security == 'reality') {
      // ПРАВИЛО А: Обычные TCP Reality серверы.
      // Требуют vision, иначе сбросят соединение. MUX их убьёт.
      node = node.copyWith(flow: 'xtls-rprx-vision', muxEnabled: false);
    } else {
      // ПРАВИЛО Б: Публичные WS / gRPC / xhttp серверы.
      //
      // ⚠️  КРИТИЧЕСКИ ВАЖНО: MUX ОТКЛЮЧЁН.
      //
      // Причина: публичные серверы из подписок (WS, gRPC) в подавляющем
      // большинстве НЕ поддерживают smux на серверной стороне.
      // Что происходит при muxEnabled: true:
      //   1. sing-box устанавливает TLS-соединение (OK)
      //   2. Пытается открыть smux-сессию внутри туннеля (отправляет smux SYN)
      //   3. Сервер ждёт VLESS-заголовок, получает мусор (smux-фрейм)
      //   4. Сервер разрывает соединение — интернет пропадает немедленно
      //
      // Если у тебя приватный сервер с поддержкой smux —
      // включи MUX вручную в настройках ноды после подключения.
      node = node.copyWith(
        flow: '',
        muxEnabled: false, // ← ИСПРАВЛЕНО: было true, ломало публичные серверы
      );
    }

    return node;
  }

  List<Node> sanitizeAll(List<Node> nodes) => nodes.map(sanitize).toList();

  Node _patchFingerprint(Node node) {
    if (node.fingerprint == _safeFp) return node;
    return node.copyWith(fingerprint: _safeFp);
  }
}
