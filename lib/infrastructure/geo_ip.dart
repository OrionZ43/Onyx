import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../core/log_service.dart';
import '../domain/routing_region.dart';

/// Страна по внешнему IP — для региона «Авто» (этап 2 автопилота).
///
/// Часовой пояс и локаль иногда врут: английская Windows, пояс UTC или
/// «Гонконг» у человека в материковом Китае. IP точнее. Запрос идёт
/// напрямую, поэтому только когда сокеты приложения идут мимо туннеля: VPN
/// выключен или Android-цепочка (иначе узнали бы страну сервера). Результат
/// кэшируется на 6 ч; перед первым подключением в регионе «Авто» Onyx ждёт
/// ответа до 4 с.
abstract final class GeoIp {
  static const timeout = Duration(seconds: 3);

  /// Только HTTPS: по дороге не видно, что и у кого спрашиваем. В Китае
  /// часть адресов может не открываться — пробуем по очереди.
  static final sources = <(String, String? Function(String))>[
    ('https://www.cloudflare.com/cdn-cgi/trace', parseTrace),
    ('https://cloudflare.com/cdn-cgi/trace', parseTrace),
    ('https://api.ip.sb/geoip', parseIpSb),
  ];

  /// ISO-код страны («CN», «BY»…) или null, если ни один сервис не ответил.
  static Future<String?> countryCode() async {
    for (final (url, parse) in sources) {
      final body = await _get(url);
      final cc = body == null ? null : parse(body);
      if (cc != null) {
        log.i('Страна по IP: $cc ($url)', tag: 'GEO');
        return cc;
      }
    }
    log.d('Страна по IP не определена', tag: 'GEO');
    return null;
  }

  /// Регион маршрутизации для страны: CN — «Китай», RU/BY — «Россия/
  /// Беларусь». Для остальных null — остаёмся на определении по часовому
  /// поясу и локали (Гонконг, Тайвань и Макао — не за «великим файрволом»).
  static RoutingRegion? regionFor(String? countryCode) => switch (countryCode?.toUpperCase()) {
        'CN' => RoutingRegion.china,
        'RU' || 'BY' => RoutingRegion.russia,
        _ => null,
      };

  /// Cloudflare trace: строки «ключ=значение», нужна loc=XX.
  static String? parseTrace(String body) {
    for (final line in const LineSplitter().convert(body)) {
      if (line.startsWith('loc=')) return _code(line.substring(4));
    }
    return null;
  }

  /// ip-api.com/line: одна строка с кодом страны.
  static String? parseLine(String body) => _code(body.trim());

  /// api.ip.sb/geoip: JSON с country_code.
  static String? parseIpSb(String body) {
    try {
      final j = jsonDecode(body);
      return j is Map ? _code('${j['country_code'] ?? ''}') : null;
    } catch (_) {
      return null;
    }
  }

  static String? _code(String s) {
    final c = s.trim().toUpperCase();
    return RegExp(r'^[A-Z]{2}$').hasMatch(c) && c != 'XX' && c != 'T1' ? c : null;
  }

  static Future<String?> _get(String url) async {
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..findProxy = (_) => 'DIRECT';
    try {
      final req = await client.getUrl(Uri.parse(url));
      // Обезличенный User-Agent: не сообщаем сервису, какое приложение спрашивает.
      req.headers.set(HttpHeaders.userAgentHeader, 'Mozilla/5.0');
      final resp = await req.close().timeout(timeout);
      if (resp.statusCode != 200) return null;
      return await resp.transform(const Utf8Decoder(allowMalformed: true)).join().timeout(timeout);
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
