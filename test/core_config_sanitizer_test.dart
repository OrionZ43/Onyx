import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/domain/core_config_sanitizer.dart';
import 'package:onyx/domain/routing_region.dart';
import 'package:onyx/domain/singbox_config_builder.dart';
import 'package:onyx/domain/subscription_parser.dart';

/// #55: конфиг для sing-box с правами админа собирается заново по белому
/// списку — через него нельзя заставить ядро писать файлы куда угодно.
const _user = r'C:\Users\U\AppData\Roaming\z43.studios\onyx\singbox';
const _run = r'C:\Program Files\Onyx\run';

Map<String, dynamic> _ours() {
  const p = SubscriptionParser();
  final reality = p.parseLink(
    'vless://bf000d23-0752-40b4-affe-68f7707a9661@203.0.113.10:443?security=reality&sni=www.microsoft.com&fp=chrome&pbk=qRo0TfUYUdgZWdTFIR-GnBESqeaIen-mk-xCh7KSqhM&sid=b868&flow=xtls-rprx-vision#R',
  )!;
  final hy2 = p.parseLink('hysteria2://pw@203.0.113.10:443?sni=www.microsoft.com&insecure=1&obfs=salamander&obfs-password=ob&mport=20000-50000#H')!;
  final ws = p.parseLink('vless://bf000d23-0752-40b4-affe-68f7707a9661@203.0.113.11:443?security=tls&type=ws&path=%2Fws&host=a.example&sni=a.example#W')!;
  return jsonDecode(const SingboxConfigBuilder().buildJson(const SingboxConfigBuilder().buildTunConfig(
    reality,
    fallbacks: [hy2, ws],
    serverIps: ['203.0.113.10'],
    routing: const RoutingOptions(region: RoutingRegion.china),
    clashSecret: 's3cr3t',
  ))) as Map<String, dynamic>;
}

Map<String, dynamic> _sanitize(Object? cfg) => sanitizeCoreConfig(cfg, userSingboxDir: _user, runDir: _run);

void main() {
  test('наш конфиг проходит без потерь: туннель, серверы, маршруты, DNS', () {
    final cfg = _ours();
    final s = _sanitize(cfg);
    expect(s['inbounds'], cfg['inbounds']);
    expect(s['outbounds'], cfg['outbounds']);
    expect(s['dns'], cfg['dns']);
    expect((s['route'] as Map)['rules'], (cfg['route'] as Map)['rules']);
    expect((s['route'] as Map)['final'], 'proxy');
    // ws-путь транспорта — путь URL, а не файл: остаётся.
    final ws = (s['outbounds'] as List).firstWhere((o) => (o as Map)['transport'] != null) as Map;
    expect((ws['transport'] as Map)['path'], '/ws');
    // rule_set — абсолютный путь к .srs в папке пользователя.
    final sets = (s['route'] as Map)['rule_set'] as List;
    expect(sets, isNotEmpty);
    for (final r in sets) {
      expect((r as Map)['path'], startsWith('$_user\\'));
      expect(r['path'], endsWith('.srs'));
    }
    // clash_api на 127.0.0.1 с секретом; кэш — в папке ядра.
    expect((s['experimental'] as Map)['clash_api'], {'external_controller': '127.0.0.1:9090', 'secret': 's3cr3t'});
    expect((s['experimental'] as Map)['cache_file'], {'enabled': true, 'path': '$_run\\cache.db'});
    expect(() => jsonEncode(s), returnsNormally);
  });

  test('пути записи вырезаются: log.output, cache_file.path, external_ui, *_path', () {
    final cfg = _ours();
    cfg['log'] = {'level': 'debug', 'output': r'C:\Windows\System32\drivers\etc\hosts'};
    (cfg['experimental'] as Map)['cache_file'] = {'enabled': true, 'path': r'C:\Windows\evil.db'};
    (cfg['experimental'] as Map)['clash_api'] = {
      'external_controller': '127.0.0.1:9090',
      'external_ui': r'C:\Windows\System32',
      'external_ui_download_url': 'https://evil.example/ui.zip',
    };
    (cfg['experimental'] as Map)['v2ray_api'] = {'listen': '0.0.0.0:1'};
    ((cfg['outbounds'] as List)[1] as Map)['tls'] = {
      'enabled': true,
      'certificate_path': r'C:\Windows\System32\config\SAM',
      'ech': {'enabled': true, 'config_path': r'C:\secret'},
    };
    final s = _sanitize(cfg);
    final txt = jsonEncode(s);
    expect(s['log'], {'level': 'debug', 'timestamp': false});
    expect(txt, isNot(contains('Windows')));
    expect(txt, isNot(contains('evil')));
    expect(txt, isNot(contains('external_ui')));
    expect(txt, isNot(contains('_path')));
    expect((s['experimental'] as Map).containsKey('v2ray_api'), isFalse);
    expect((s['experimental'] as Map)['cache_file'], {'enabled': true, 'path': '$_run\\cache.db'});
  });

  test('чужие разделы и входы выбрасываются', () {
    final cfg = _ours();
    cfg['services'] = [
      {'type': 'derp', 'config_path': r'C:\x'},
    ];
    cfg['endpoints'] = [
      {'type': 'wireguard'},
    ];
    cfg['certificate'] = {'store': 'none'};
    (cfg['inbounds'] as List).addAll([
      {'type': 'mixed', 'listen': '0.0.0.0', 'listen_port': 1080}, // наружу — нельзя
      {'type': 'redirect', 'listen': '127.0.0.1', 'listen_port': 1081},
      {'type': 'shadowsocks', 'listen': '127.0.0.1', 'listen_port': 1082},
    ]);
    (cfg['outbounds'] as List).add({'type': 'ssh', 'tag': 'x', 'private_key_path': r'C:\k'});
    (cfg['dns'] as Map)['servers'] = [
      ...((cfg['dns'] as Map)['servers'] as List),
      {'type': 'hosts', 'tag': 'h', 'path': [r'C:\Windows\System32\drivers\etc\hosts']},
    ];
    final s = _sanitize(cfg);
    for (final k in ['services', 'endpoints', 'certificate']) {
      expect(s.containsKey(k), isFalse, reason: k);
    }
    expect((s['inbounds'] as List).map((i) => (i as Map)['type']), ['tun', 'mixed']);
    expect((s['outbounds'] as List).any((o) => (o as Map)['type'] == 'ssh'), isFalse);
    expect(((s['dns'] as Map)['servers'] as List).any((d) => (d as Map)['type'] == 'hosts'), isFalse);
  });

  test('rule_set: обход каталогов и чужие пути — только имя файла в папке пользователя', () {
    final cfg = _ours();
    (cfg['route'] as Map)['rule_set'] = [
      {'tag': 'a', 'type': 'local', 'format': 'binary', 'path': r'..\..\..\Windows\System32\a.srs'},
      {'tag': 'b', 'type': 'local', 'format': 'binary', 'path': r'C:\Windows\b.srs'},
      {'tag': 'c', 'type': 'local', 'format': 'binary', 'path': r'C:\Windows\System32\config\SAM'},
      {'tag': 'd', 'type': 'remote', 'format': 'binary', 'url': 'http://insecure.example/d.srs'},
      {'tag': 'e', 'type': 'remote', 'format': 'binary', 'url': 'https://ok.example/e.srs', 'path': r'C:\x'},
    ];
    final sets = ((_sanitize(cfg)['route'] as Map)['rule_set'] as List).cast<Map>();
    expect(sets.map((r) => r['tag']), ['a', 'b', 'e']);
    expect(sets[0]['path'], '$_user\\a.srs');
    expect(sets[1]['path'], '$_user\\b.srs');
    expect(sets[2].containsKey('path'), isFalse);
  });

  test('clash_api только на 127.0.0.1', () {
    final cfg = _ours();
    (cfg['experimental'] as Map)['clash_api'] = {'external_controller': '0.0.0.0:9090'};
    expect((_sanitize(cfg)['experimental'] as Map).containsKey('clash_api'), isFalse);
  });

  test('мусор вместо конфига — FormatException', () {
    expect(() => _sanitize('не объект'), throwsFormatException);
    expect(() => _sanitize({'inbounds': []}), throwsFormatException);
    expect(
      () => _sanitize({
        'inbounds': [
          {'type': 'mixed', 'listen': '0.0.0.0', 'listen_port': 1},
        ],
        'outbounds': [],
      }),
      throwsFormatException,
    );
  });
}
