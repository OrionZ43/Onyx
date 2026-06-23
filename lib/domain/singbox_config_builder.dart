import 'dart:convert';
import 'entities/node.dart';

/// Собирает финальный JSON-конфиг sing-box.
class SingboxConfigBuilder {
  const SingboxConfigBuilder();

  /// [resolvedServerIp] — IP-адрес сервера, предварительно резолвнутый
  /// вызывающим кодом ДО создания TUN-интерфейса.
  Map<String, dynamic> buildTunConfig(
    Node node, {
    int socksPort = 2080,
    String? resolvedServerIp,
  }) {
    return {
      'log': {'level': 'info', 'timestamp': true},
      'dns': _buildDns(),
      'inbounds': [_buildTun(), _buildSocks(socksPort)],
      'outbounds': [
        _buildVless(node),
        {'type': 'direct', 'tag': 'direct'},
        {'type': 'block', 'tag': 'block'},
        {'type': 'dns', 'tag': 'dns-out'},
      ],
      'route': _buildRoute(node, resolvedServerIp: resolvedServerIp),
      'experimental': _buildExperimental(),
    };
  }

  Map<String, dynamic> buildProbeConfig(Node node, int proxyPort) {
    return {
      'log': {'level': 'error'},
      'inbounds': [
        {
          'type':
              'mixed', // <--- МАГИЯ ЗДЕСЬ: работает и как HTTP, и как SOCKS5
          'tag': 'mixed-in',
          'listen': '127.0.0.1',
          'listen_port': proxyPort,
        },
      ],
      'outbounds': [
        _buildVless(node),
        {'type': 'direct', 'tag': 'direct'},
      ],
      'route': {'final': 'proxy'},
    };
  }

  String buildJson(Map<String, dynamic> config) =>
      const JsonEncoder.withIndent('  ').convert(config);

  // ── Inbounds ───────────────────────────────────────────────────────────────

  Map<String, dynamic> _buildTun() => {
        'type': 'tun',
        'tag': 'tun-in',
        'inet4_address': '172.19.0.1/30',
        'inet6_address': 'fdfe:dcba:9876::1/126',
        'mtu': 1400,
        'auto_route': true,
        'strict_route': true,
        'stack': 'system',
        'sniff': true,
        'sniff_override_destination': true,
      };

  Map<String, dynamic> _buildSocks(int port) => {
        'type': 'socks',
        'tag': 'socks-in',
        'listen': '127.0.0.1',
        'listen_port': port,
        'sniff': true,
      };

  // ── Outbound ───────────────────────────────────────────────────────────────

  Map<String, dynamic> _buildVless(Node node) {
    final out = <String, dynamic>{
      'type': 'vless',
      'tag': 'proxy',
      'server': node.host,
      'server_port': node.port,
      'uuid': node.uuid,
      'tls': _buildTls(node),
    };

    if (node.flow.isNotEmpty) {
      out['flow'] = node.flow;
    }

    final transport = _buildTransport(node);
    if (transport != null) out['transport'] = transport;

    if (node.muxEnabled) {
      out['multiplex'] = {
        'enabled': true,
        'protocol': node.muxProtocol,
        'max_streams': node.muxMaxStreams,
      };
    }

    return out;
  }

  Map<String, dynamic> _buildTls(Node node) {
    final tls = <String, dynamic>{
      'enabled': node.security != 'none',
      'server_name': node.sni,
      'utls': {'enabled': true, 'fingerprint': node.fingerprint},
    };

    if (node.security == 'reality') {
      tls['reality'] = {
        'enabled': true,
        'public_key': node.realityPbk,
        'short_id': node.realitySid,
      };
    }

    return tls;
  }

  Map<String, dynamic>? _buildTransport(Node node) {
    return switch (node.network) {
      'ws' => {
          'type': 'ws',
          'path': node.path,
          'headers': {'Host': node.sni},
        },
      'grpc' => {'type': 'grpc', 'service_name': node.path.replaceAll('/', '')},
      'h2' => {
          'type': 'http',
          'host': [node.sni],
          'path': node.path,
        },
      _ => null,
    };
  }

  // ── DNS ────────────────────────────────────────────────────────────────────

  /// DNS-конфигурация с защитой от перехвата ТСПУ.
  ///
  /// ──────────────────────────────────────────────────────────────────────────
  /// ПРОБЛЕМА (старый вариант с detour: direct):
  ///
  ///   В России ТСПУ (Технические Средства Противодействия Угрозам)
  ///   перехватывает UDP/TCP-запросы к 8.8.8.8:53 и подменяет ответы —
  ///   возвращает заблокированные IP или свои адреса вместо настоящих.
  ///   Итог: даже при работающем VPN-туннеле DNS отравлен, сайты не открываются.
  ///
  /// ──────────────────────────────────────────────────────────────────────────
  /// РЕШЕНИЕ (новый вариант):
  ///
  ///   dns-remote → DoH (https://8.8.8.8/dns-query) с detour: proxy.
  ///   DNS-запросы клиентов шифруются внутри VLESS-туннеля и доходят до
  ///   Google DNS уже по ту сторону фильтра. ТСПУ видит лишь TLS-поток.
  ///
  ///   dns-local  → 8.8.8.8 (plaintext) с detour: direct.
  ///   Используется ТОЛЬКО для разрешения адресов самого VLESS-сервера
  ///   (правило outbound: any). Это предотвращает chicken-and-egg рекурсию:
  ///     "sing-box хочет подключиться к серверу → нужен IP → DNS идёт через
  ///      прокси → прокси не запущен → hang forever".
  ///   С правилом outbound: any sing-box резолвит адреса своих outbound-ов
  ///   напрямую (direct), а пользовательский трафик — через зашифрованный DoH.
  ///
  ///   На Windows авторитет: auto_detect_interface: true (в route) биндит
  ///   исходящие сокеты sing-box (в т.ч. dns-local) к физическому NIC,
  ///   исключая их из перехвата WinTUN. Петли не возникает.
  ///
  ///   Схема потоков:
  ///     Пользователь: DNS → TUN → sing-box DNS → dns-remote (DoH/proxy) ✓
  ///     sing-box сам: DNS для outbound → dns-local (direct/физ.NIC)     ✓
  /// ──────────────────────────────────────────────────────────────────────────
  Map<String, dynamic> _buildDns() => {
        'servers': [
          {
            // Основной: DoH через зашифрованный прокси — ТСПУ не видит запросы
            'tag': 'dns-remote',
            'address': 'https://8.8.8.8/dns-query',
            'detour': 'proxy',
          },
          {
            // Служебный: plaintext DNS только для разрешения адресов outbound-ов
            // самого sing-box (см. rules ниже). Биндится к физическому NIC через
            // auto_detect_interface, поэтому ТСПУ его не перехватывает.
            'tag': 'dns-local',
            'address': '8.8.8.8',
            'detour': 'direct',
          },
        ],
        'rules': [
          {
            // Когда sing-box резолвит адрес для своего outbound-соединения
            // (например, IP VLESS-сервера), использовать прямой DNS, а не прокси.
            // Предотвращает бесконечную рекурсию: прокси → DNS → прокси → ...
            'outbound': 'any',
            'server': 'dns-local',
          },
        ],
        // Весь остальной DNS (запросы клиентских приложений) → DoH через прокси
        'final': 'dns-remote',
        'independent_cache': true,
      };

  // ── Route ──────────────────────────────────────────────────────────────────

  /// Маршрутизация трафика.
  ///
  /// Ключевое требование: bypass VLESS-сервера через ip_cidr (а не domain),
  /// потому что TUN работает на уровне L3 — в сырых IP-пакетах нет имени
  /// домена. Правило domain молча игнорируется, пакет летит в proxy → петля.
  Map<String, dynamic> _buildRoute(Node node, {String? resolvedServerIp}) {
    final serverIp =
        resolvedServerIp ?? (_isIpAddress(node.host) ? node.host : null);

    return {
      'rules': [
        // DNS-трафик клиентов → модуль DNS sing-box
        {'protocol': 'dns', 'outbound': 'dns-out'},
        // Локальные адреса никогда не идут через прокси
        {'ip_is_private': true, 'outbound': 'direct'},
        // Bypass сервера: ip_cidr работает с сырыми L3-пакетами TUN
        if (serverIp != null)
          {
            'ip_cidr': ['$serverIp/32'],
            'outbound': 'direct',
          },
      ],
      // На Windows ОБЯЗАТЕЛЕН: привязывает исходящие сокеты sing-box
      // (VLESS outbound, dns-local) к физическому адаптеру (Wi-Fi/Ethernet),
      // исключая их из захвата WinTUN.
      'auto_detect_interface': true,
      'final': 'proxy',
    };
  }

  bool _isIpAddress(String host) {
    if (RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host)) return true;
    if (host.contains(':')) return true;
    return false;
  }

  Map<String, dynamic> _buildExperimental() => {
        'clash_api': {'external_controller': '127.0.0.1:9090', 'secret': ''},
        'cache_file': {'enabled': true},
      };
}
