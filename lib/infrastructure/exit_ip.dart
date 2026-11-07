import 'dart:async';
import 'dart:io';

/// Внешний IP выхода через поднятый туннель.
///
/// Запрос идёт через локальный прокси sing-box, чтобы получить адрес
/// именно ТУННЕЛЯ, а не физической сети:
///   • Windows — mixed-inbound 127.0.0.1:2080;
///   • Android, режим цепочки — mixed-inbound sing-box 127.0.0.1:2081
///     (приложение там исключено из VPN, прямой запрос показал бы домашний IP);
///   • Android, режим Xray — напрямую: трафик приложения и так в VPN.
abstract final class ExitIp {
  static const _services = ['https://api.ipify.org', 'https://ifconfig.me/ip'];

  static Future<String?> fetch() async {
    final proxies = Platform.isWindows
        ? ['PROXY 127.0.0.1:2080']
        : ['PROXY 127.0.0.1:2081', 'DIRECT'];
    for (final proxy in proxies) {
      if (proxy.startsWith('PROXY') && !await _listening(int.parse(proxy.split(':').last))) {
        continue;
      }
      for (final url in _services) {
        final ip = await _get(url, proxy);
        if (ip != null) return ip;
      }
    }
    return null;
  }

  static Future<bool> _listening(int port) async {
    try {
      final s = await Socket.connect('127.0.0.1', port, timeout: const Duration(milliseconds: 500));
      s.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<String?> _get(String url, String proxy) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 5)
      ..findProxy = (_) => proxy;
    try {
      final req = await client.getUrl(Uri.parse(url));
      final resp = await req.close().timeout(const Duration(seconds: 6));
      if (resp.statusCode != 200) return null;
      final body = (await resp.transform(const SystemEncoding().decoder).join()).trim();
      final ok = RegExp(r'^(\d{1,3}(\.\d{1,3}){3}|[0-9a-fA-F:]+)$').hasMatch(body);
      return ok ? body : null;
    } catch (_) {
      return null;
    } finally {
      client.close(force: true);
    }
  }
}
