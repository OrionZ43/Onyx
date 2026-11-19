import 'dart:convert';
import 'package:crypto/crypto.dart' show sha1;
import 'package:yaml/yaml.dart';
import 'entities/node.dart';

/// Парсит ответ подписки (или вставленный текст) в список [Node].
///
/// Поддерживаемые форматы:
///   • список ссылок (plain или base64-blob): vless://, hysteria2:// (hy2://),
///     tuic://, ss://, trojan://, anytls://;
///   • Clash / mihomo YAML (`proxies:`);
///   • sing-box JSON (`{"outbounds": [...]}`).
///
/// Ноды неподдерживаемых типов и битые строки молча пропускаются — одна
/// кривая строка не должна ронять всю подписку.
class SubscriptionParser {
  const SubscriptionParser();

  static const _schemes = [
    'vless://',
    'hysteria2://',
    'hy2://',
    'tuic://',
    'ss://',
    'trojan://',
    'anytls://',
  ];

  /// true, если текст похож на содержимое подписки, а не на URL подписки
  /// (пользователь вставил ссылки или base64 прямо в поле).
  static bool looksLikeContent(String input) {
    final t = input.trim();
    if (t.isEmpty) return false;
    if (_schemes.any((s) => t.startsWith(s))) return true;
    if (t.startsWith('{') || RegExp(r'^proxies\s*:', multiLine: true).hasMatch(t)) {
      return true;
    }
    if (t.startsWith('http://') || t.startsWith('https://')) return false;
    final decoded = _tryBase64(t);
    return decoded != null && _schemes.any(decoded.contains);
  }

  static const _supportedHint =
      'Вставьте ссылку vless://, hy2://, tuic://, ss://, trojan://, anytls:// или адрес подписки (https://…).';

  /// Понятная причина, если вставлен НЕПОДДЕРЖИВАЕМЫЙ формат (vpn:// Amnezia,
  /// vmess://, WireGuard, неизвестная схема). null — формат поддерживается
  /// или это не ссылка вовсе.
  static String? unsupportedReason(String input) {
    final first = input
        .trim()
        .split(RegExp(r'[\n\r]+'))
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');
    final m = RegExp(r'^([a-zA-Z][a-zA-Z0-9+.\-]*)://').firstMatch(first);
    if (m == null) return null;
    final scheme = m.group(1)!.toLowerCase();
    if (scheme == 'http' || scheme == 'https') return null;
    if (_schemes.contains('$scheme://')) return null;
    return switch (scheme) {
      'vpn' => 'Формат Amnezia (vpn://) не поддерживается. $_supportedHint',
      'vmess' => 'VMess (vmess://) не поддерживается. $_supportedHint',
      'ssr' => 'ShadowsocksR (ssr://) не поддерживается. $_supportedHint',
      'wireguard' || 'wg' || 'awg' =>
        'WireGuard / AmneziaWG не поддерживается. $_supportedHint',
      _ => 'Ссылка «$scheme://» не поддерживается. $_supportedHint',
    };
  }

  List<Node> parse(String raw) {
    var text = raw.trim();
    if (text.startsWith('﻿')) text = text.substring(1);
    if (text.isEmpty) return const [];

    if (text.startsWith('{')) {
      final nodes = _parseSingboxJson(text);
      if (nodes != null) return nodes;
    }
    if (RegExp(r'^proxies\s*:', multiLine: true).hasMatch(text)) {
      final nodes = _parseClashYaml(text);
      if (nodes != null) return nodes;
    }

    final decoded =
        _schemes.any(text.contains) ? text : (_tryBase64(text) ?? text);
    final nodes = <Node>[];
    for (final line in decoded.split(RegExp(r'[\n\r]+'))) {
      final node = parseLink(line.trim());
      if (node != null) nodes.add(node);
    }
    return nodes;
  }

  /// Разбирает одну ссылку. null — неподдерживаемая или битая.
  Node? parseLink(String line) {
    try {
      if (line.startsWith('vless://')) return _parseVless(line);
      if (line.startsWith('hysteria2://') || line.startsWith('hy2://')) {
        return _parseHysteria2(line);
      }
      if (line.startsWith('tuic://')) return _parseTuic(line);
      if (line.startsWith('ss://')) return _parseShadowsocks(line);
      if (line.startsWith('trojan://')) return _parseTrojan(line);
      if (line.startsWith('anytls://')) return _parseAnyTls(line);
    } catch (_) {
      // битая строка — пропускаем
    }
    return null;
  }

  // ── Ссылки ───────────────────────────────────────────────────────────────

  Node? _parseVless(String uri) {
    // vless://UUID@host:port?params#name
    final u = Uri.parse(uri);
    final p = u.queryParameters;
    if (u.userInfo.isEmpty || u.host.isEmpty || u.port == 0) return null;
    final network = p['type'] ?? 'tcp';
    return Node(
      id: _nodeId('vless', u.host, u.port, u.userInfo),
      name: _name(u, u.host),
      host: u.host,
      port: u.port,
      uuid: u.userInfo,
      flow: p['flow'] ?? '',
      security: p['security'] ?? 'none',
      fingerprint: p['fp'] ?? 'chrome',
      sni: p['sni'] ?? u.host,
      path: p['path'] ?? p['serviceName'] ?? '/',
      network: network,
      realityPbk: p['pbk'] ?? '',
      realitySid: p['sid'] ?? '',
      insecure: _truthy(p['allowInsecure'] ?? p['insecure']),
    );
  }

  Node? _parseHysteria2(String uri) {
    // hysteria2://password@host:port[,ports]/?sni=&obfs=salamander&obfs-password=&insecure=1&mport=20000-50000#name
    var normalized = uri.replaceFirst(RegExp(r'^hy2://'), 'hysteria2://');
    // Мульти-порт в authority ("host:443,20000-50000") Uri.parse не понимает —
    // вырезаем его и переносим в serverPorts.
    String authorityPorts = '';
    final m = RegExp(r'^(hysteria2://[^@/?#]*@[^:/?#\[\]]+|hysteria2://[^@/?#]*@\[[^\]]+\]):([0-9,\-]+)')
        .firstMatch(normalized);
    var port = 443;
    if (m != null) {
      final portSpec = m.group(2)!;
      final parts = portSpec.split(',');
      final first = parts.first;
      if (first.contains('-')) {
        port = int.parse(first.split('-').first);
        authorityPorts = portSpec;
      } else {
        port = int.parse(first);
        if (parts.length > 1) authorityPorts = parts.skip(1).join(',');
      }
      normalized = '${m.group(1)}:$port${normalized.substring(m.end)}';
    }
    final u = Uri.parse(normalized);
    final p = u.queryParameters;
    final password = Uri.decodeComponent(u.userInfo);
    if (password.isEmpty || u.host.isEmpty) return null;
    if (u.hasPort) port = u.port;
    final ports = p['mport'] ?? p['ports'] ?? authorityPorts;
    return Node(
      protocol: NodeProtocol.hysteria2,
      id: _nodeId('hy2', u.host, port, password),
      name: _name(u, u.host),
      host: u.host,
      port: port,
      uuid: '',
      flow: '',
      security: 'tls',
      fingerprint: '',
      sni: p['sni'] ?? p['peer'] ?? u.host,
      path: '',
      network: 'udp',
      password: password,
      obfs: p['obfs'] ?? '',
      obfsPassword: p['obfs-password'] ?? p['obfs_password'] ?? '',
      serverPorts: ports,
      hopInterval: p['hop-interval'] ?? p['hopInterval'] ?? '',
      alpn: _list(p['alpn']),
      insecure: _truthy(p['insecure'] ?? p['allowInsecure']),
      upMbps: int.tryParse(p['upmbps'] ?? p['up'] ?? '') ?? 0,
      downMbps: int.tryParse(p['downmbps'] ?? p['down'] ?? '') ?? 0,
    );
  }

  Node? _parseTuic(String uri) {
    // tuic://uuid:password@host:port?congestion_control=bbr&alpn=h3&sni=&allow_insecure=1#name
    final u = Uri.parse(uri);
    final p = u.queryParameters;
    final info = Uri.decodeComponent(u.userInfo);
    final idx = info.indexOf(':');
    if (idx <= 0 || u.host.isEmpty || u.port == 0) return null;
    final uuid = info.substring(0, idx);
    final password = info.substring(idx + 1);
    return Node(
      protocol: NodeProtocol.tuic,
      id: _nodeId('tuic', u.host, u.port, uuid),
      name: _name(u, u.host),
      host: u.host,
      port: u.port,
      uuid: uuid,
      flow: '',
      security: 'tls',
      fingerprint: '',
      sni: p['sni'] ?? u.host,
      path: '',
      network: 'udp',
      password: password,
      congestion: p['congestion_control'] ?? p['congestion-control'] ?? 'bbr',
      alpn: _list(p['alpn'], fallback: const ['h3']),
      insecure: _truthy(p['allow_insecure'] ?? p['insecure'] ?? p['allowInsecure']),
    );
  }

  Node? _parseShadowsocks(String uri) {
    // SIP002: ss://base64url(method:password)@host:port/?plugin=...#name
    // Legacy: ss://base64(method:password@host:port)#name
    final hashIdx = uri.indexOf('#');
    final name = hashIdx >= 0 ? Uri.decodeComponent(uri.substring(hashIdx + 1)) : '';
    var body = uri.substring(5, hashIdx >= 0 ? hashIdx : uri.length);

    if (!body.contains('@')) {
      final decoded = _tryBase64(body.split('?').first);
      if (decoded == null) return null;
      body = decoded;
    }
    final u = Uri.parse('ss://$body');
    var info = Uri.decodeComponent(u.userInfo);
    if (!info.contains(':')) info = _tryBase64(info) ?? info;
    final idx = info.indexOf(':');
    if (idx <= 0 || u.host.isEmpty || u.port == 0) return null;
    final method = info.substring(0, idx);
    final password = info.substring(idx + 1);

    var plugin = '';
    var pluginOpts = '';
    final pluginParam = u.queryParameters['plugin'];
    if (pluginParam != null && pluginParam.isNotEmpty) {
      final semi = pluginParam.indexOf(';');
      plugin = semi < 0 ? pluginParam : pluginParam.substring(0, semi);
      pluginOpts = semi < 0 ? '' : pluginParam.substring(semi + 1);
    }

    return Node(
      protocol: NodeProtocol.shadowsocks,
      id: _nodeId('ss', u.host, u.port, '$method:$password'),
      name: name.isEmpty ? u.host : name,
      host: u.host,
      port: u.port,
      uuid: '',
      flow: '',
      security: 'none',
      fingerprint: '',
      sni: '',
      path: '',
      network: 'tcp',
      method: method,
      password: password,
      plugin: plugin,
      pluginOpts: pluginOpts,
    );
  }

  Node? _parseTrojan(String uri) {
    // trojan://password@host:port?sni=&type=ws&path=&host=&allowInsecure=1#name
    final u = Uri.parse(uri);
    final p = u.queryParameters;
    final password = Uri.decodeComponent(u.userInfo);
    if (password.isEmpty || u.host.isEmpty || u.port == 0) return null;
    return Node(
      protocol: NodeProtocol.trojan,
      id: _nodeId('trojan', u.host, u.port, password),
      name: _name(u, u.host),
      host: u.host,
      port: u.port,
      uuid: '',
      flow: '',
      security: p['security'] == 'none' ? 'none' : 'tls',
      fingerprint: p['fp'] ?? 'chrome',
      sni: p['sni'] ?? p['peer'] ?? p['host'] ?? u.host,
      path: p['path'] ?? p['serviceName'] ?? '/',
      network: p['type'] ?? 'tcp',
      password: password,
      alpn: _list(p['alpn']),
      insecure: _truthy(p['allowInsecure'] ?? p['insecure']),
    );
  }

  Node? _parseAnyTls(String uri) {
    // anytls://password@host:port?sni=&insecure=1#name
    final u = Uri.parse(uri);
    final p = u.queryParameters;
    final password = Uri.decodeComponent(u.userInfo);
    if (password.isEmpty || u.host.isEmpty || u.port == 0) return null;
    return Node(
      protocol: NodeProtocol.anytls,
      id: _nodeId('anytls', u.host, u.port, password),
      name: _name(u, u.host),
      host: u.host,
      port: u.port,
      uuid: '',
      flow: '',
      security: 'tls',
      fingerprint: p['fp'] ?? 'chrome',
      sni: p['sni'] ?? u.host,
      path: '',
      network: 'tcp',
      password: password,
      alpn: _list(p['alpn']),
      insecure: _truthy(p['insecure'] ?? p['allowInsecure']),
    );
  }

  // ── Clash / mihomo YAML ──────────────────────────────────────────────────

  List<Node>? _parseClashYaml(String text) {
    final Object? doc;
    try {
      doc = loadYaml(text);
    } catch (_) {
      return null;
    }
    if (doc is! YamlMap || doc['proxies'] is! YamlList) return null;
    final nodes = <Node>[];
    for (final item in doc['proxies'] as YamlList) {
      if (item is! YamlMap) continue;
      try {
        final n = _fromClash(_plain(item) as Map<String, dynamic>);
        if (n != null) nodes.add(n);
      } catch (_) {}
    }
    return nodes;
  }

  Node? _fromClash(Map<String, dynamic> m) {
    final type = (m['type'] ?? '').toString();
    final server = (m['server'] ?? '').toString();
    final port = _int(m['port']);
    final name = (m['name'] ?? server).toString();
    if (server.isEmpty || port == 0) return null;
    final sni = (m['servername'] ?? m['sni'] ?? '').toString();
    final insecure = m['skip-cert-verify'] == true;
    final alpn = (m['alpn'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];

    switch (type) {
      case 'vless':
        final uuid = (m['uuid'] ?? '').toString();
        if (uuid.isEmpty) return null;
        final reality = m['reality-opts'] as Map?;
        final network = (m['network'] ?? 'tcp').toString();
        final ws = m['ws-opts'] as Map?;
        final grpc = m['grpc-opts'] as Map?;
        final tls = m['tls'] == true;
        return Node(
          id: _nodeId('vless', server, port, uuid),
          name: name,
          host: server,
          port: port,
          uuid: uuid,
          flow: (m['flow'] ?? '').toString(),
          security: reality != null ? 'reality' : (tls ? 'tls' : 'none'),
          fingerprint: (m['client-fingerprint'] ?? 'chrome').toString(),
          sni: sni.isNotEmpty
              ? sni
              : ((ws?['headers'] as Map?)?['Host']?.toString() ?? server),
          path: network == 'grpc'
              ? (grpc?['grpc-service-name'] ?? '').toString()
              : (ws?['path'] ?? '/').toString(),
          network: network,
          realityPbk: (reality?['public-key'] ?? '').toString(),
          realitySid: (reality?['short-id'] ?? '').toString(),
          insecure: insecure,
        );
      case 'hysteria2':
        final password = (m['password'] ?? m['auth'] ?? '').toString();
        if (password.isEmpty) return null;
        return Node(
          protocol: NodeProtocol.hysteria2,
          id: _nodeId('hy2', server, port, password),
          name: name,
          host: server,
          port: port,
          uuid: '',
          flow: '',
          security: 'tls',
          fingerprint: '',
          sni: sni.isEmpty ? server : sni,
          path: '',
          network: 'udp',
          password: password,
          obfs: (m['obfs'] ?? '').toString(),
          obfsPassword: (m['obfs-password'] ?? '').toString(),
          serverPorts: (m['ports'] ?? '').toString(),
          hopInterval: m['hop-interval'] == null ? '' : '${m['hop-interval']}s',
          alpn: alpn,
          insecure: insecure,
          upMbps: _mbps(m['up']),
          downMbps: _mbps(m['down']),
        );
      case 'tuic':
        final uuid = (m['uuid'] ?? '').toString();
        final password = (m['password'] ?? '').toString();
        if (uuid.isEmpty) return null;
        return Node(
          protocol: NodeProtocol.tuic,
          id: _nodeId('tuic', server, port, uuid),
          name: name,
          host: server,
          port: port,
          uuid: uuid,
          flow: '',
          security: 'tls',
          fingerprint: '',
          sni: sni.isEmpty ? server : sni,
          path: '',
          network: 'udp',
          password: password,
          congestion: (m['congestion-controller'] ?? 'bbr').toString(),
          alpn: alpn.isEmpty ? const ['h3'] : alpn,
          insecure: insecure,
        );
      case 'ss':
        final method = (m['cipher'] ?? '').toString();
        final password = (m['password'] ?? '').toString();
        if (method.isEmpty) return null;
        var plugin = (m['plugin'] ?? '').toString();
        var opts = '';
        final po = m['plugin-opts'];
        if (po is Map) {
          // Clash: plugin: obfs, plugin-opts: {mode: tls, host: ...}
          if (plugin == 'obfs') plugin = 'obfs-local';
          opts = [
            if (po['mode'] != null) 'obfs=${po['mode']}',
            if (po['host'] != null) 'obfs-host=${po['host']}',
          ].join(';');
        }
        return Node(
          protocol: NodeProtocol.shadowsocks,
          id: _nodeId('ss', server, port, '$method:$password'),
          name: name,
          host: server,
          port: port,
          uuid: '',
          flow: '',
          security: 'none',
          fingerprint: '',
          sni: '',
          path: '',
          network: 'tcp',
          method: method,
          password: password,
          plugin: plugin,
          pluginOpts: opts,
        );
      case 'trojan':
        final password = (m['password'] ?? '').toString();
        if (password.isEmpty) return null;
        final network = (m['network'] ?? 'tcp').toString();
        final ws = m['ws-opts'] as Map?;
        final grpc = m['grpc-opts'] as Map?;
        return Node(
          protocol: NodeProtocol.trojan,
          id: _nodeId('trojan', server, port, password),
          name: name,
          host: server,
          port: port,
          uuid: '',
          flow: '',
          security: 'tls',
          fingerprint: (m['client-fingerprint'] ?? 'chrome').toString(),
          sni: sni.isEmpty ? server : sni,
          path: network == 'grpc'
              ? (grpc?['grpc-service-name'] ?? '').toString()
              : (ws?['path'] ?? '/').toString(),
          network: network,
          password: password,
          alpn: alpn,
          insecure: insecure,
        );
      case 'anytls':
        final password = (m['password'] ?? '').toString();
        if (password.isEmpty) return null;
        return Node(
          protocol: NodeProtocol.anytls,
          id: _nodeId('anytls', server, port, password),
          name: name,
          host: server,
          port: port,
          uuid: '',
          flow: '',
          security: 'tls',
          fingerprint: (m['client-fingerprint'] ?? 'chrome').toString(),
          sni: sni.isEmpty ? server : sni,
          path: '',
          network: 'tcp',
          password: password,
          alpn: alpn,
          insecure: insecure,
        );
    }
    return null;
  }

  // ── sing-box JSON ────────────────────────────────────────────────────────

  List<Node>? _parseSingboxJson(String text) {
    final Object? doc;
    try {
      doc = jsonDecode(text);
    } catch (_) {
      return null;
    }
    if (doc is! Map || doc['outbounds'] is! List) return null;
    final nodes = <Node>[];
    for (final o in doc['outbounds'] as List) {
      if (o is! Map) continue;
      try {
        final n = _fromSingbox(Map<String, dynamic>.from(o));
        if (n != null) nodes.add(n);
      } catch (_) {}
    }
    return nodes;
  }

  Node? _fromSingbox(Map<String, dynamic> o) {
    final type = (o['type'] ?? '').toString();
    final server = (o['server'] ?? '').toString();
    final port = _int(o['server_port']);
    final name = (o['tag'] ?? server).toString();
    if (server.isEmpty || port == 0) return null;
    final tls = (o['tls'] as Map?) ?? const {};
    final sni = (tls['server_name'] ?? server).toString();
    final insecure = tls['insecure'] == true;
    final alpn = (tls['alpn'] as List?)?.map((e) => e.toString()).toList() ?? const <String>[];
    final utls = tls['utls'] as Map?;
    final fp = (utls?['fingerprint'] ?? 'chrome').toString();
    final transport = (o['transport'] as Map?) ?? const {};
    final tType = (transport['type'] ?? 'tcp').toString();
    final network = tType == 'http' ? 'h2' : tType;
    final tPath = tType == 'grpc'
        ? (transport['service_name'] ?? '').toString()
        : (transport['path'] ?? '/').toString();

    switch (type) {
      case 'vless':
        final uuid = (o['uuid'] ?? '').toString();
        if (uuid.isEmpty) return null;
        final reality = tls['reality'] as Map?;
        final realityOn = reality?['enabled'] == true;
        return Node(
          id: _nodeId('vless', server, port, uuid),
          name: name,
          host: server,
          port: port,
          uuid: uuid,
          flow: (o['flow'] ?? '').toString(),
          security: realityOn ? 'reality' : (tls['enabled'] == true ? 'tls' : 'none'),
          fingerprint: fp,
          sni: sni,
          path: tPath,
          network: network,
          realityPbk: (reality?['public_key'] ?? '').toString(),
          realitySid: (reality?['short_id'] ?? '').toString(),
          insecure: insecure,
        );
      case 'hysteria2':
        final password = (o['password'] ?? '').toString();
        final obfs = (o['obfs'] as Map?) ?? const {};
        final ports = (o['server_ports'] as List?)
                ?.map((e) => e.toString().replaceAll(':', '-'))
                .join(',') ??
            '';
        return Node(
          protocol: NodeProtocol.hysteria2,
          id: _nodeId('hy2', server, port, password),
          name: name,
          host: server,
          port: port,
          uuid: '',
          flow: '',
          security: 'tls',
          fingerprint: '',
          sni: sni,
          path: '',
          network: 'udp',
          password: password,
          obfs: (obfs['type'] ?? '').toString(),
          obfsPassword: (obfs['password'] ?? '').toString(),
          serverPorts: ports,
          hopInterval: (o['hop_interval'] ?? '').toString(),
          alpn: alpn,
          insecure: insecure,
          upMbps: _int(o['up_mbps']),
          downMbps: _int(o['down_mbps']),
        );
      case 'tuic':
        final uuid = (o['uuid'] ?? '').toString();
        return Node(
          protocol: NodeProtocol.tuic,
          id: _nodeId('tuic', server, port, uuid),
          name: name,
          host: server,
          port: port,
          uuid: uuid,
          flow: '',
          security: 'tls',
          fingerprint: '',
          sni: sni,
          path: '',
          network: 'udp',
          password: (o['password'] ?? '').toString(),
          congestion: (o['congestion_control'] ?? 'bbr').toString(),
          alpn: alpn.isEmpty ? const ['h3'] : alpn,
          insecure: insecure,
        );
      case 'shadowsocks':
        final method = (o['method'] ?? '').toString();
        final password = (o['password'] ?? '').toString();
        return Node(
          protocol: NodeProtocol.shadowsocks,
          id: _nodeId('ss', server, port, '$method:$password'),
          name: name,
          host: server,
          port: port,
          uuid: '',
          flow: '',
          security: 'none',
          fingerprint: '',
          sni: '',
          path: '',
          network: 'tcp',
          method: method,
          password: password,
          plugin: (o['plugin'] ?? '').toString(),
          pluginOpts: (o['plugin_opts'] ?? '').toString(),
        );
      case 'trojan':
      case 'anytls':
        final password = (o['password'] ?? '').toString();
        return Node(
          protocol: type == 'trojan' ? NodeProtocol.trojan : NodeProtocol.anytls,
          id: _nodeId(type, server, port, password),
          name: name,
          host: server,
          port: port,
          uuid: '',
          flow: '',
          security: 'tls',
          fingerprint: fp,
          sni: sni,
          path: type == 'trojan' ? tPath : '',
          network: type == 'trojan' ? network : 'tcp',
          password: password,
          alpn: alpn,
          insecure: insecure,
        );
    }
    return null;
  }

  // ── Утилиты ──────────────────────────────────────────────────────────────

  static String? _tryBase64(String input) {
    try {
      var padded = input
          .replaceAll(RegExp(r'\s'), '')
          .replaceAll('-', '+')
          .replaceAll('_', '/');
      while (padded.length % 4 != 0) {
        padded += '=';
      }
      return utf8.decode(base64.decode(padded));
    } catch (_) {
      return null;
    }
  }

  static String _name(Uri u, String fallback) {
    if (u.fragment.isEmpty) return fallback;
    try {
      return Uri.decodeComponent(u.fragment);
    } catch (_) {
      return u.fragment;
    }
  }

  static bool _truthy(String? v) =>
      v != null && (v == '1' || v.toLowerCase() == 'true');

  static List<String> _list(String? v, {List<String> fallback = const []}) {
    if (v == null || v.isEmpty) return fallback;
    return v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  static int _int(Object? v) =>
      v is int ? v : int.tryParse(v?.toString() ?? '') ?? 0;

  /// Clash пишет up/down как "100 Mbps" или просто числом.
  static int _mbps(Object? v) {
    if (v == null) return 0;
    final m = RegExp(r'\d+').firstMatch(v.toString());
    return m == null ? 0 : int.parse(m.group(0)!);
  }

  static Object? _plain(Object? v) {
    if (v is YamlMap) {
      return <String, dynamic>{
        for (final e in v.entries) e.key.toString(): _plain(e.value),
      };
    }
    if (v is YamlList) return v.map(_plain).toList();
    return v;
  }

  String _nodeId(String proto, String host, int port, String cred) {
    // Для vless сохраняем прежний формат id (host:port:uuid), чтобы
    // избранное/последняя нода у существующих пользователей не потерялись.
    final key = proto == 'vless' ? '$host:$port:$cred' : '$proto:$host:$port:$cred';
    return sha1.convert(utf8.encode(key)).toString().substring(0, 12);
  }
}
