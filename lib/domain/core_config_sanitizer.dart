// Чистый Dart без Flutter: этот файл компилируется и в приложение, и в
// onyx-core.exe (tools/onyx_core), который работает с правами администратора.

/// Пересборка конфига sing-box для запуска с правами администратора (#55).
///
/// Конфиг пишет приложение без прав в папку пользователя, поэтому он
/// НЕДОВЕРЕННЫЙ: любой процесс этого пользователя может его подменить. А
/// sing-box умеет писать файлы туда, куда скажут (`log.output`,
/// `cache_file.path`, `external_ui` + `external_ui_download_url`,
/// `services`…), — от имени администратора это готовая лазейка для
/// повышения прав. Поэтому конфиг не «чистится», а собирается заново по
/// белому списку того, что выдаёт SingboxConfigBuilder:
///
/// * log — только уровень и метка времени (вывод — в журнал onyx-core);
/// * inbounds — только tun и mixed/socks/http на 127.0.0.1;
/// * outbounds, dns, route — как есть, но без путей к файлам (`*_path`:
///   сертификаты, ECH и т. п.; `output`, `directory`, `external_ui*`), кроме
///   сопоставлений `process_path*`; `path` у транспортов ws/http — путь URL;
/// * rule_set — только local и remote; путь local — имя .srs в папке
///   пользователя (чтение);
/// * experimental — только clash_api на 127.0.0.1 и cache_file в папке
///   ядра;
/// * всё остальное (services, endpoints, certificate, ntp, v2ray_api…) —
///   выбрасывается.
///
/// Бросает [FormatException], если конфиг не похож на наш.
Map<String, dynamic> sanitizeCoreConfig(
  Object? input, {
  required String userSingboxDir,
  required String runDir,
}) {
  if (input is! Map) throw const FormatException('конфиг — не объект');
  final out = <String, dynamic>{};

  // ── log ──
  final log = input['log'];
  const levels = {'trace', 'debug', 'info', 'warn', 'error', 'fatal', 'panic'};
  out['log'] = <String, dynamic>{
    'level': (log is Map && levels.contains(log['level'])) ? log['level'] : 'warn',
    'timestamp': log is Map && log['timestamp'] == true,
  };

  // ── dns ──
  final dns = input['dns'];
  if (dns is Map) {
    final d = _scrub(dns) as Map<String, dynamic>;
    final servers = d['servers'];
    if (servers is List) {
      d['servers'] = [
        for (final s in servers)
          if (s is Map && _dnsTypes.contains(s['type'] ?? 'udp')) s,
      ];
    }
    out['dns'] = d;
  }

  // ── inbounds ──
  final inbounds = input['inbounds'];
  if (inbounds is! List) throw const FormatException('нет inbounds');
  final ins = <Map<String, dynamic>>[];
  for (final i in inbounds) {
    if (i is! Map) continue;
    final type = i['type'];
    if (type == 'tun') {
      ins.add({
        for (final k in _tunKeys)
          if (i.containsKey(k)) k: _scrub(i[k]),
        'type': 'tun',
      });
    } else if (type == 'mixed' || type == 'socks' || type == 'http') {
      final listen = i['listen'];
      final port = i['listen_port'];
      if ((listen == '127.0.0.1' || listen == '::1') && port is int && port > 0 && port < 65536) {
        ins.add({
          'type': type,
          if (i['tag'] is String) 'tag': i['tag'],
          'listen': listen,
          'listen_port': port,
        });
      }
    }
  }
  if (ins.isEmpty) throw const FormatException('нет допустимых inbounds');
  out['inbounds'] = ins;

  // ── outbounds ──
  final outbounds = input['outbounds'];
  if (outbounds is! List) throw const FormatException('нет outbounds');
  out['outbounds'] = [
    for (final o in outbounds)
      if (o is Map && _outboundTypes.contains(o['type'])) _scrub(o),
  ];

  // ── route ──
  final route = input['route'];
  if (route is Map) {
    final r = <String, dynamic>{};
    for (final k in _routeKeys) {
      if (route.containsKey(k)) r[k] = _scrub(route[k]);
    }
    final sets = route['rule_set'];
    if (sets is List) {
      final rs = <Map<String, dynamic>>[];
      for (final s in sets) {
        final x = s is Map ? _ruleSet(s, userSingboxDir) : null;
        if (x != null) rs.add(x);
      }
      r['rule_set'] = rs;
    }
    out['route'] = r;
  }

  // ── experimental ──
  final exp = input['experimental'];
  final e = <String, dynamic>{};
  if (exp is Map) {
    final clash = exp['clash_api'];
    if (clash is Map) {
      final ctl = clash['external_controller'];
      if (ctl is String && RegExp(r'^127\.0\.0\.1:\d{1,5}$').hasMatch(ctl)) {
        e['clash_api'] = {
          'external_controller': ctl,
          if (clash['secret'] is String) 'secret': clash['secret'],
        };
      }
    }
    final cache = exp['cache_file'];
    if (cache is Map && cache['enabled'] == true) {
      e['cache_file'] = {'enabled': true, 'path': '$runDir${_sep(runDir)}cache.db'};
    }
  }
  if (e.isNotEmpty) out['experimental'] = e;
  return out;
}

const _dnsTypes = {'udp', 'tcp', 'tls', 'https', 'quic', 'h3', 'local', 'fakeip'};

const _tunKeys = [
  'tag',
  'interface_name',
  'address',
  'mtu',
  'auto_route',
  'strict_route',
  'route_address',
  'route_exclude_address',
  'stack',
  'endpoint_independent_nat',
  'udp_timeout',
];

const _outboundTypes = {
  'direct',
  'block',
  'selector',
  'urltest',
  'vless',
  'vmess',
  'trojan',
  'shadowsocks',
  'hysteria',
  'hysteria2',
  'tuic',
  'anytls',
  'socks',
  'http',
  'shadowtls',
};

const _routeKeys = [
  'rules',
  'final',
  'auto_detect_interface',
  'override_android_vpn',
  'default_interface',
  'default_domain_resolver',
  'default_network_strategy',
  'find_process',
];

/// local — только имя файла .srs (без каталогов), читается из папки
/// пользователя; remote — URL, загрузка в кэш ядра.
Map<String, dynamic>? _ruleSet(Map s, String userSingboxDir) {
  final tag = s['tag'];
  if (tag is! String) return null;
  final format = s['format'] == 'source' ? 'source' : 'binary';
  if (s['type'] == 'local') {
    final path = s['path'];
    if (path is! String) return null;
    final name = path.split(RegExp(r'[\\/]')).last;
    if (!RegExp(r'^[A-Za-z0-9._-]+\.(srs|json)$').hasMatch(name) || name.startsWith('.')) return null;
    return {
      'tag': tag,
      'type': 'local',
      'format': format,
      'path': '$userSingboxDir${_sep(userSingboxDir)}$name',
    };
  }
  if (s['type'] == 'remote') {
    final url = s['url'];
    if (url is! String || !url.startsWith('https://')) return null;
    return {
      'tag': tag,
      'type': 'remote',
      'format': format,
      'url': url,
      if (s['download_detour'] is String) 'download_detour': s['download_detour'],
      if (s['update_interval'] is String) 'update_interval': s['update_interval'],
    };
  }
  return null;
}

String _sep(String dir) => dir.contains('\\') ? '\\' : '/';

/// Глубокая копия без ключей, ведущих к файлам.
Object? _scrub(Object? v) {
  if (v is Map) {
    return <String, dynamic>{
      for (final e in v.entries)
        if (e.key is String && !_forbiddenKey(e.key as String)) e.key as String: _scrub(e.value),
    };
  }
  if (v is List) return [for (final x in v) _scrub(x)];
  return v;
}

bool _forbiddenKey(String k) {
  // process_path — сопоставление с процессом, не файл. «path» без суффикса
  // тоже не трогаем: у транспортов ws/http это путь URL; файловые «path»
  // (log, cache_file, rule_set) собираются заново выше.
  if (k == 'process_path' || k == 'process_path_regex') return false;
  return k.endsWith('_path') ||
      k == 'output' ||
      k == 'directory' ||
      k == 'external_ui' ||
      k.startsWith('external_ui_');
}
