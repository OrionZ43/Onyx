import 'package:path/path.dart' as path;
import '../infrastructure/binary_manager.dart';
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
        bool smartRouting = true,
        bool isAndroid = false,
      }) {
    return {
      'log': {'level': 'warn', 'timestamp': true},
      'dns': _buildDns(smartRouting: smartRouting, isAndroid: isAndroid),
      'inbounds': [_buildTun(isAndroid: isAndroid), _buildSocks(socksPort)],
      'outbounds': [
        _buildVless(node),
        {'type': 'direct', 'tag': 'direct'},
        {'type': 'block', 'tag': 'block'},
        {'type': 'dns', 'tag': 'dns-out'},
      ],
      'route': _buildRoute(
        node,
        resolvedServerIp: resolvedServerIp,
        smartRouting: smartRouting,
        isAndroid: isAndroid,
      ),
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

  Map<String, dynamic> _buildTun({bool isAndroid = false}) => {
    'type': 'tun',
    'tag': 'tun-in',
    'inet4_address': '172.19.0.1/30',
    'inet6_address': 'fdfe:dcba:9876::1/126',
    'mtu': isAndroid ? 9000 : 1400,
    'auto_route': true,
    'strict_route': isAndroid ? false : true,
    'stack': 'system',
    'sniff': true,
    'sniff_override_destination': true,
  };

  Map<String, dynamic> _buildSocks(int port) => {
    'type': 'mixed', // <--- ИЗМЕНЕНО: теперь принимает и HTTP, и SOCKS
    'tag': 'mixed-in',
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
  ///   dns-local → 77.88.8.8 (Яндекс.DNS) с detour: direct.
  ///   ИСПРАВЛЕНИЕ: заменяем 8.8.8.8 на Яндекс.DNS (77.88.8.8).
  ///   Причина: ТСПУ в РФ перехватывает UDP/TCP на 8.8.8.8:53 (DNS Hijacking),
  ///   подменяя ответы для RU-доменов. dns-local используется ТОЛЬКО для
  ///   разрешения адресов самих outbound-ов sing-box (правило outbound: any) —
  ///   это именно RU/СНГ-хосты VLESS-серверов. 77.88.8.8 не перехватывается
  ///   ТСПУ и корректно резолвит RU-домены без подмены.
  ///
  ///   На Windows авторитет: auto_detect_interface: true (в route) биндит
  ///   исходящие сокеты sing-box (в т.ч. dns-local) к физическому NIC,
  ///   исключая их из перехвата WinTUN. Петли не возникает.
  ///
  ///   Схема потоков:
  ///     Пользователь: DNS → TUN → sing-box DNS → dns-remote (DoH/proxy) ✓
  ///     sing-box сам: DNS для outbound → dns-local (Яндекс/direct/NIC)   ✓
  /// ──────────────────────────────────────────────────────────────────────────
  Map<String, dynamic> _buildDns({bool smartRouting = false, bool isAndroid = false}) => {
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
        //
        // ИСПРАВЛЕНИЕ: 8.8.8.8 → 77.88.8.8 (Яндекс.DNS).
        // 8.8.8.8 в РФ подвергается DNS Hijacking со стороны ТСПУ —
        // ответы для RU-доменов подменяются. Яндекс.DNS работает корректно
        // и не блокируется на уровне BGP.
        'tag': 'dns-local',
        'address': isAndroid ? 'local' : '77.88.8.8',
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
      // RU-домены резолвятся напрямую, не через proxy
      if (smartRouting) ...[
        {
          // ИСПРАВЛЕНИЕ: geosite-правила здесь корректны ТОЛЬКО если
          // в route присутствует блок geosite со ссылкой на geosite.db.
          // Без него sing-box молча игнорирует geosite-матчеры.
          // Fallback domain_suffix ниже работают всегда, без БД.
          'geosite': ['ru', 'yandex', 'vk', 'mailru'],
          'server': 'dns-local',
        },
        {
          // Хардкод-фолбэк для критичных CDN и сервисов СНГ.
          // Работает НЕЗАВИСИМО от наличия geosite.db.
          // Гарантирует прямой резолв даже если geosite-БД не загружена
          // или не содержит нужный домен.
          'domain_suffix': _ruCdnDomainSuffixes,
          'server': 'dns-local',
        },
      ],
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
  ///
  /// ИСПРАВЛЕНИЕ: добавлены блоки geoip и geosite в корень route.
  /// Без них sing-box не знает, где искать файлы БД, и молча игнорирует
  /// все правила с geosite/geoip матчерами. Файлы лежат рядом с sing-box.exe
  /// (workingDirectory: _binMgr.singboxExe.parent.path), поэтому пути
  /// относительные — sing-box ищет их в текущей рабочей директории.
  Map<String, dynamic> _buildRoute(
      Node node, {
        String? resolvedServerIp,
        bool smartRouting = true,
        bool isAndroid = false,
      }) {
    final serverIp =
        resolvedServerIp ?? (_isIpAddress(node.host) ? node.host : null);

    return {
      // ── ИСПРАВЛЕНИЕ: блоки geoip и geosite ──────────────────────────────
      //
      // sing-box v1.x ищет файлы БД в рабочей директории процесса.
      // sing-box.exe запускается с:
      //   workingDirectory: _binMgr.singboxExe.parent.path
      // Значит, относительные пути 'geoip.db' и 'geosite.db' указывают
      // прямо на скачанные BinaryManager-ом файлы. Явно указываем пути,
      // чтобы исключить зависимость от дефолтного поведения sing-box
      // в разных версиях.
      //
      // Без этих блоков все правила вида:
      //   {'geosite': ['ru', 'yandex'], 'outbound': 'direct'}
      // молча игнорируются — sing-box не знает, где лежит база.
      'geoip': {
        'path': isAndroid ? path.join(BinaryManager.instance.singboxExe.parent.path, 'geoip.db') : 'geoip.db',
        'download_url':
        'https://github.com/SagerNet/sing-geoip/releases/latest/download/geoip.db',
        'download_detour': 'direct',
      },
      'geosite': {
        'path': isAndroid ? path.join(BinaryManager.instance.singboxExe.parent.path, 'geosite.db') : 'geosite.db',
        'download_url':
        'https://github.com/SagerNet/sing-geosite/releases/latest/download/geosite.db',
        'download_detour': 'direct',
      },
      // ── Правила маршрутизации ─────────────────────────────────────────────
      'rules': [
        // DNS-трафик клиентов → модуль DNS sing-box
        {'protocol': 'dns', 'outbound': 'dns-out'},
        // Локальные адреса никогда не идут через прокси
        {'ip_is_private': true, 'outbound': 'direct'},
        // Обход VPN для RU-доменов и популярных сервисов
        if (smartRouting) ...[
          {
            'geosite': ['ru', 'yandex', 'vk', 'mailru'],
            'outbound': 'direct',
          },
          {
            'geoip': ['ru', 'by'],
            'outbound': 'direct',
          },
          // ИСПРАВЛЕНИЕ: хардкод domain_suffix для критичных CDN.
          // Работает независимо от geosite.db — гарантирует прямой bypass
          // для ключевых сервисов СНГ даже если:
          //   1. geosite.db ещё не скачан
          //   2. geosite.db устарел и не содержит новые CDN-домены
          //   3. Конкретный домен не попал в категорию 'ru' в БД
          {
            'domain_suffix': _ruCdnDomainSuffixes,
            'outbound': 'direct',
          },
        ],
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
      if (!isAndroid) 'auto_detect_interface': true,
      'final': 'proxy',
    };
  }

  // ── Хардкод-список CDN/сервисов СНГ ──────────────────────────────────────
  //
  // Используется как fallback в _buildDns и _buildRoute.
  // Обновляй этот список при появлении новых крупных CDN.
  static const List<String> _ruCdnDomainSuffixes = [
    // Яндекс — CDN и сервисы
    'yandex.ru',
    'yandex.com',
    'yandex.net',
    'yandex.st',
    'yastatic.net',    // главный Яндекс CDN (JS, CSS, изображения)
    'yandexapis.com',
    'ya.ru',
    'yandex-team.ru',

    // VK / Mail.ru Group
    'vk.com',
    'vk.me',
    'vkuseraudio.com',
    'vkuservideo.com',
    'vkontakte.ru',
    'userapi.com',     // VK CDN для медиа
    'mail.ru',
    'mailru.com',
    'mradx.net',       // Mail.ru рекламная сеть
    'mycdn.me',        // OK.ru CDN
    'odnoklassniki.ru',
    'ok.ru',

    // Wildberries
    'wildberries.ru',
    'wb.ru',
    'wbstatic.net',    // WB CDN для изображений товаров
    'wbx-ru.net',

    // Ozon
    'ozon.ru',
    'ozon-api.com',
    'ozoncdn.com',
    'cdnvideo.ru',     // Ozon видео CDN

    // Сбер / ФинТех
    'sber.ru',
    'sberbank.ru',
    'sberpay.ru',
    'domclick.ru',
    'sbercloud.ru',

    // Прочие крупные RU-сервисы
    'gosuslugi.ru',
    'mos.ru',
    'nalog.ru',
    'pfr.gov.ru',
    'tinkoff.ru',
    'raiffeisen.ru',
    'alfabank.ru',
    'vtb.ru',
    'avito.ru',
    'cian.ru',
    'hh.ru',
    'rbc.ru',
    'ria.ru',
    'kommersant.ru',

    // Стриминг
    'kinopoisk.ru',    // принадлежит Яндексу, но CDN отдельный
    'ivi.ru',
    'okko.tv',
    'more.tv',
    'premier.one',
  ];

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