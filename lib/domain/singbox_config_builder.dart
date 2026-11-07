import 'dart:convert';
import 'entities/node.dart';
import 'routing_domains.dart';
import 'routing_region.dart';

/// Параметры маршрутизации, общие для всех видов конфига.
class RoutingOptions {
  const RoutingOptions({
    this.smartRouting = true,
    this.region = RoutingRegion.russia,
    this.aiDirectLane = true,
    this.discordMode = true,
    this.ruleSetDir = '',
  });

  /// Обход туннеля для «домашних» сайтов региона [region].
  final bool smartRouting;
  final RoutingRegion region;

  /// Домены ИИ — строго через туннель и remote-DNS.
  final bool aiDirectLane;

  /// Режим Discord: домены Discord (и процесс Discord на Windows) — строго
  /// через туннель с наивысшим приоритетом, DNS — только через туннель.
  final bool discordMode;

  /// Папка с .srs rule-set файлами. Пусто = рабочая папка sing-box
  /// (Windows: sing-box запускается с workingDirectory = папка бинарников).
  final String ruleSetDir;
}

/// Собирает JSON-конфиг sing-box.
///
/// Формат — sing-box ≥ 1.12 (проверен `sing-box check` на 1.14.4):
///   • DNS-серверы нового вида ({type, server}), без legacy `address`;
///   • `route.rule_set` с локальными .srs вместо удалённых в 1.12 geoip/geosite;
///   • sniff и перехват DNS — route-actions (`sniff`, `hijack-dns`) вместо
///     удалённых полей inbound и outbound-а `dns`;
///   • TUN: `address` вместо `inet4_address`/`inet6_address`.
class SingboxConfigBuilder {
  const SingboxConfigBuilder();

  static const proxyTag = 'proxy';
  static const probeUrl = 'https://cp.cloudflare.com/generate_204';

  /// Имена rule-set файлов, которые приложение кладёт рядом с sing-box
  /// (бандл в assets/rules, см. BinaryManager).
  static const ruleSetFiles = <String>[
    'geosite-cn',
    'geoip-cn',
    'geosite-category-ru',
    'geosite-yandex',
    'geosite-vk',
    'geosite-mailru',
    'geoip-ru',
    'geoip-by',
  ];

  static const _ruGeosite = [
    'geosite-category-ru',
    'geosite-yandex',
    'geosite-vk',
    'geosite-mailru',
  ];
  static const _ruGeoip = ['geoip-ru', 'geoip-by'];
  static const _cnGeosite = ['geosite-cn'];
  static const _cnGeoip = ['geoip-cn'];

  // ── Публичные конфиги ────────────────────────────────────────────────────

  /// Windows: полный TUN-конфиг.
  ///
  /// [fallbacks] — другие транспорты того же сервера (например Hysteria2 к
  /// REALITY). Если они есть, outbound `proxy` становится `urltest`-группой:
  /// sing-box сам держит лучший живой транспорт и переключается при отказе,
  /// не обрывая уже открытые соединения (звонок не рвётся).
  ///
  /// [serverIps] — IP всех серверов из группы, резолвнутые ДО поднятия TUN:
  /// их трафик идёт напрямую (ip_cidr работает на сырых L3-пакетах TUN).
  Map<String, dynamic> buildTunConfig(
    Node node, {
    List<Node> fallbacks = const [],
    List<String> serverIps = const [],
    int socksPort = 2080,
    RoutingOptions routing = const RoutingOptions(),
    String clashSecret = '',
    int clashPort = 9090,
  }) {
    return {
      'log': {'level': 'warn', 'timestamp': true},
      'dns': _buildDns(routing),
      'inbounds': [
        {
          'type': 'tun',
          'tag': 'tun-in',
          'address': ['172.19.0.1/30', 'fdfe:dcba:9876::1/126'],
          'mtu': 1400,
          'auto_route': true,
          'strict_route': true,
          'stack': 'system',
        },
        {
          'type': 'mixed',
          'tag': 'mixed-in',
          'listen': '127.0.0.1',
          'listen_port': socksPort,
        },
      ],
      'outbounds': _buildProxyOutbounds(node, fallbacks),
      'route': _buildRoute(
        routing,
        serverIps: serverIps,
        withProcessRules: true,
        autoDetectInterface: true,
      ),
      'experimental': {
        'clash_api': {
          'external_controller': '127.0.0.1:$clashPort',
          'secret': clashSecret,
        },
        'cache_file': {'enabled': true},
      },
    };
  }

  /// Android: sing-box как локальный SOCKS/HTTP-прокси за Xray.
  ///
  /// Цепочка: VpnService → tun2socks → Xray (socks-inbound) → socks-outbound
  /// → этот mixed-inbound → протокол ноды (Hysteria2/TUIC/…). Процесс
  /// sing-box принадлежит приложению, а приложение исключено из VPN, поэтому
  /// его исходящие сокеты (к серверу и `direct`) идут мимо туннеля — петли нет.
  Map<String, dynamic> buildChainConfig(
    Node node, {
    List<Node> fallbacks = const [],
    int listenPort = 2081,
    RoutingOptions routing = const RoutingOptions(),
    String cacheFilePath = '',
  }) {
    return {
      'log': {'level': 'warn', 'timestamp': true},
      'dns': _buildDns(routing),
      'inbounds': [
        {
          'type': 'mixed',
          'tag': 'mixed-in',
          'listen': '127.0.0.1',
          'listen_port': listenPort,
        },
      ],
      'outbounds': _buildProxyOutbounds(node, fallbacks),
      'route': _buildRoute(routing),
      'experimental': {
        'cache_file': {
          'enabled': true,
          if (cacheFilePath.isNotEmpty) 'path': cacheFilePath,
        },
      },
    };
  }

  /// Конфиг для проверки ноды: mixed-inbound → нода, без маршрутизации.
  Map<String, dynamic> buildProbeConfig(Node node, int proxyPort) {
    return {
      'log': {'level': 'error'},
      'inbounds': [
        {
          'type': 'mixed',
          'tag': 'mixed-in',
          'listen': '127.0.0.1',
          'listen_port': proxyPort,
        },
      ],
      'outbounds': [
        buildOutbound(node, proxyTag),
        {'type': 'direct', 'tag': 'direct'},
      ],
      'route': {'final': proxyTag},
    };
  }

  String buildJson(Map<String, dynamic> config) =>
      const JsonEncoder.withIndent('  ').convert(config);

  // ── Outbounds ────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> _buildProxyOutbounds(
    Node node,
    List<Node> fallbacks,
  ) {
    final extra = fallbacks.where((f) => f.id != node.id).toList();
    if (extra.isEmpty) {
      return [
        buildOutbound(node, proxyTag),
        {'type': 'direct', 'tag': 'direct'},
      ];
    }
    final members = [node, ...extra];
    final tags = [for (var i = 0; i < members.length; i++) 'proxy-$i'];
    return [
      {
        'type': 'urltest',
        'tag': proxyTag,
        'outbounds': tags,
        'url': probeUrl,
        'interval': '1m',
        'tolerance': 150,
        'idle_timeout': '30m',
        'interrupt_exist_connections': false,
      },
      for (var i = 0; i < members.length; i++) buildOutbound(members[i], tags[i]),
      {'type': 'direct', 'tag': 'direct'},
    ];
  }

  /// Outbound для одной ноды любого поддерживаемого протокола.
  Map<String, dynamic> buildOutbound(Node node, String tag) {
    final base = <String, dynamic>{
      'tag': tag,
      'server': node.host,
      'server_port': node.port,
    };
    switch (node.protocol) {
      case NodeProtocol.hysteria2:
        final ports = parsePortRanges(node.serverPorts);
        return {
          'type': 'hysteria2',
          ...base,
          if (ports.isNotEmpty) 'server_ports': ports,
          if (ports.isNotEmpty)
            'hop_interval': node.hopInterval.isEmpty ? '30s' : node.hopInterval,
          if (node.upMbps > 0) 'up_mbps': node.upMbps,
          if (node.downMbps > 0) 'down_mbps': node.downMbps,
          if (node.obfs.isNotEmpty)
            'obfs': {'type': node.obfs, 'password': node.obfsPassword},
          'password': node.password,
          'tls': _buildTls(node, defaultAlpn: const ['h3'], utls: false),
        };
      case NodeProtocol.tuic:
        return {
          'type': 'tuic',
          ...base,
          'uuid': node.uuid,
          'password': node.password,
          'congestion_control':
              node.congestion.isEmpty ? 'bbr' : node.congestion,
          'udp_relay_mode': 'native',
          'tls': _buildTls(node, defaultAlpn: const ['h3'], utls: false),
        };
      case NodeProtocol.shadowsocks:
        return {
          'type': 'shadowsocks',
          ...base,
          'method': node.method,
          'password': node.password,
          if (node.plugin.isNotEmpty) 'plugin': node.plugin,
          if (node.plugin.isNotEmpty) 'plugin_opts': node.pluginOpts,
        };
      case NodeProtocol.trojan:
        final transport = _buildTransport(node);
        return {
          'type': 'trojan',
          ...base,
          'password': node.password,
          if (node.security != 'none') 'tls': _buildTls(node),
          if (transport != null) 'transport': transport,
        };
      case NodeProtocol.anytls:
        return {
          'type': 'anytls',
          ...base,
          'password': node.password,
          'tls': _buildTls(node),
        };
      default:
        return _buildVless(node, base);
    }
  }

  Map<String, dynamic> _buildVless(Node node, Map<String, dynamic> base) {
    final out = <String, dynamic>{
      'type': 'vless',
      ...base,
      'uuid': node.uuid,
      // UDP (голос Discord) внутри VLESS — XUDP: каждый UDP-поток
      // мультиплексируется в один TCP-туннель с сохранением адресов.
      'packet_encoding': 'xudp',
    };
    if (node.security != 'none') out['tls'] = _buildTls(node);
    if (node.flow.isNotEmpty) out['flow'] = node.flow;
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

  Map<String, dynamic> _buildTls(
    Node node, {
    List<String> defaultAlpn = const [],
    bool utls = true,
  }) {
    final alpn = node.alpn.isNotEmpty ? node.alpn : defaultAlpn;
    final tls = <String, dynamic>{
      'enabled': true,
      'server_name': node.sni.isEmpty ? node.host : node.sni,
      if (node.insecure) 'insecure': true,
      if (alpn.isNotEmpty) 'alpn': alpn,
      if (utls && node.fingerprint.isNotEmpty)
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

  /// "443,20000-50000" → ["443:443", "20000:50000"] (формат sing-box).
  static List<String> parsePortRanges(String spec) {
    final out = <String>[];
    for (final raw in spec.split(',')) {
      final part = raw.trim();
      if (part.isEmpty) continue;
      final m = RegExp(r'^(\d+)(?:[-:](\d+))?$').firstMatch(part);
      if (m == null) continue;
      final a = int.parse(m.group(1)!);
      final b = m.group(2) == null ? a : int.parse(m.group(2)!);
      if (a < 1 || b > 65535 || a > b) continue;
      out.add('$a:$b');
    }
    return out;
  }

  // ── DNS ──────────────────────────────────────────────────────────────────

  /// DNS:
  ///   • dns-remote — DoH 8.8.8.8 ВНУТРИ туннеля: ни провайдер, ни GFW/ТСПУ
  ///     не видят и не подменяют запросы;
  ///   • dns-local — прямой DNS региона для «домашних» доменов и для
  ///     резолва адресов самих серверов (route.default_domain_resolver):
  ///       Россия/Беларусь → 77.88.8.8 (Яндекс, не подменяется ТСПУ);
  ///       Китай → 223.5.5.5 (AliDNS: правильные CN-адреса и CDN).
  Map<String, dynamic> _buildDns(RoutingOptions r) {
    final localServer =
        r.region == RoutingRegion.china ? '223.5.5.5' : '77.88.8.8';
    final remoteOnly = <String>[
      if (r.discordMode) ...kDiscordDomainSuffixes,
      if (r.aiDirectLane) ...kAiDomainSuffixes,
    ];
    return {
      'servers': [
        {
          'type': 'https',
          'tag': 'dns-remote',
          'server': '8.8.8.8',
          'detour': proxyTag,
        },
        {'type': 'udp', 'tag': 'dns-local', 'server': localServer},
      ],
      'rules': [
        if (remoteOnly.isNotEmpty)
          {'domain_suffix': remoteOnly, 'server': 'dns-remote'},
        if (r.smartRouting && r.region == RoutingRegion.russia) ...[
          {'rule_set': _ruGeosite, 'server': 'dns-local'},
          {'domain_suffix': kRuCdnDomainSuffixes, 'server': 'dns-local'},
        ],
        if (r.smartRouting && r.region == RoutingRegion.china)
          {'rule_set': _cnGeosite, 'server': 'dns-local'},
      ],
      'final': 'dns-remote',
      // Только IPv4 (A-записи). Иначе приложения (Discord: стрим-серверы)
      // выбирают IPv6: на Android VpnService IPv6 не захватывает — трафик
      // идёт мимо VPN и режется GFW; на Windows уходит в туннель, а у
      // многих серверов нет IPv6 → таймауты, Discord 2007 «Stream is
      // reconnecting».
      'strategy': 'ipv4_only',
    };
  }

  // ── Route ────────────────────────────────────────────────────────────────

  Map<String, dynamic> _buildRoute(
    RoutingOptions r, {
    List<String> serverIps = const [],
    bool withProcessRules = false,
    bool autoDetectInterface = false,
  }) {
    final usedSets = <String>[
      if (r.smartRouting && r.region == RoutingRegion.russia) ...[
        ..._ruGeosite,
        ..._ruGeoip,
      ],
      if (r.smartRouting && r.region == RoutingRegion.china) ...[
        ..._cnGeosite,
        ..._cnGeoip,
      ],
    ];
    return {
      if (usedSets.isNotEmpty)
        'rule_set': [
          for (final tag in usedSets)
            {
              'tag': tag,
              'type': 'local',
              'format': 'binary',
              'path': r.ruleSetDir.isEmpty ? '$tag.srs' : '${r.ruleSetDir}/$tag.srs',
            },
        ],
      'rules': [
        // Определяем протокол и домен (TLS SNI, HTTP Host, QUIC, DNS),
        // не подменяя IP назначения: работают и доменные, и IP-правила.
        {'action': 'sniff'},
        // Перехват DNS строго по порту 53. Раньше было protocol: dns —
        // тогда в DNS-модуль попадали и не-DNS пакеты на :53 (в логах
        // «bad question name / overflow uint16»), а сниффер теоретически
        // мог принять за DNS короткие UDP-пакеты на других портах.
        {'port': 53, 'action': 'hijack-dns'},
        // ── Режим Discord: наивысший приоритет ─────────────────────────
        // На Windows ловим сам процесс: так в туннель гарантированно
        // попадает и голос/видео (UDP на IP voice-серверов, у которых в
        // пакетах нет домена).
        if (r.discordMode && withProcessRules)
          {'process_name': kDiscordProcessNames, 'outbound': proxyTag},
        if (r.discordMode)
          {'domain_suffix': kDiscordDomainSuffixes, 'outbound': proxyTag},
        if (r.aiDirectLane)
          {'domain_suffix': kAiDomainSuffixes, 'outbound': proxyTag},
        {'ip_is_private': true, 'outbound': 'direct'},
        if (r.smartRouting && r.region == RoutingRegion.russia) ...[
          {
            'rule_set': [..._ruGeosite, ..._ruGeoip],
            'outbound': 'direct',
          },
          {'domain_suffix': kRuCdnDomainSuffixes, 'outbound': 'direct'},
        ],
        if (r.smartRouting && r.region == RoutingRegion.china)
          {
            'rule_set': [..._cnGeosite, ..._cnGeoip],
            'outbound': 'direct',
          },
        if (serverIps.isNotEmpty)
          {
            'ip_cidr': [
              for (final ip in serverIps) ip.contains(':') ? '$ip/128' : '$ip/32',
            ],
            'outbound': 'direct',
          },
      ],
      'final': proxyTag,
      // Windows: исходящие сокеты sing-box привязываются к физическому
      // адаптеру, мимо WinTUN — иначе петля.
      if (autoDetectInterface) 'auto_detect_interface': true,
      'default_domain_resolver': {'server': 'dns-local', 'strategy': 'prefer_ipv4'},
    };
  }
}
