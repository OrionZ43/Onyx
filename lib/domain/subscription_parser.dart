import 'dart:convert';
import 'package:crypto/crypto.dart' show sha1;
import 'entities/node.dart';

/// Парсит raw-ответ подписки в список [Node].
/// Поддерживает base64-blob и plain-text форматы.
class SubscriptionParser {
  const SubscriptionParser();

  List<Node> parse(String raw) {
    final decoded = _tryBase64(raw.trim()) ?? raw.trim();
    final lines   = decoded
        .split(RegExp(r'[\n\r]+'))
        .map((l) => l.trim())
        .where((l) => l.startsWith('vless://'))
        .toList();

    final nodes = <Node>[];
    for (final line in lines) {
      final node = _parseVlessUri(line);
      if (node != null) nodes.add(node);
    }
    return nodes;
  }

  // ── Приватные ────────────────────────────────────────────────────────────

  String? _tryBase64(String input) {
    try {
      var padded = input.replaceAll('-', '+').replaceAll('_', '/');
      // ИСПРАВЛЕНО: добавлены фигурные скобки в while
      while (padded.length % 4 != 0) {
        padded += '=';
      }
      return utf8.decode(base64.decode(padded));
    } catch (_) {
      return null;
    }
  }

  Node? _parseVlessUri(String uri) {
    try {
      // vless://UUID@host:port?params#name
      final u      = Uri.parse(uri);
      final uuid   = u.userInfo;
      final host   = u.host;
      final port   = u.port;
      final params = u.queryParameters;
      final name   = Uri.decodeComponent(
          u.fragment.isEmpty ? host : u.fragment);

      if (uuid.isEmpty || host.isEmpty || port == 0) return null;

      return Node(
        id:          _nodeId(host, port, uuid),
        name:        name,
        host:        host,
        port:        port,
        uuid:        uuid,
        flow:        params['flow']        ?? '',
        security:    params['security']    ?? 'none',
        fingerprint: params['fp']          ?? 'chrome',
        sni:         params['sni']         ?? host,
        path:        params['path']        ?? params['serviceName'] ?? '/',
        network:     params['type']        ?? 'tcp',
        // Reality-специфичные параметры
        realityPbk:  params['pbk']         ?? '',
        realitySid:  params['sid']         ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  String _nodeId(String host, int port, String uuid) {
    final bytes = utf8.encode('$host:$port:$uuid');
    return sha1.convert(bytes).toString().substring(0, 12);
  }
}