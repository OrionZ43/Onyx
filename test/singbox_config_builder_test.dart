import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/domain/entities/node.dart';
import 'package:onyx/domain/routing_region.dart';
import 'package:onyx/domain/singbox_config_builder.dart';
import 'package:onyx/domain/subscription_parser.dart';

/// Конфиги дополнительно сохраняются в build/test_configs/*.json —
/// их проверяет настоящий sing-box (`sing-box check`, см. tools/server/README).
void main() {
  const b = SingboxConfigBuilder();
  const p = SubscriptionParser();
  const uuid = 'bf000d23-0752-40b4-affe-68f7707a9661';

  final reality = p.parseLink(
    'vless://$uuid@203.0.113.10:443?security=reality&type=tcp&sni=www.microsoft.com'
    '&flow=xtls-rprx-vision&fp=chrome&pbk=jNXHt1yRo0vDuchQlIP6Z0ZvjT3KtzVI-T4E7RoLJS0&sid=0123abcd#R',
  )!;
  final hy2 = p.parseLink(
    'hysteria2://pw@203.0.113.10:443?sni=www.microsoft.com&obfs=salamander'
    '&obfs-password=ob&insecure=1&mport=20000-50000#H',
  )!;
  final tuic = p.parseLink('tuic://$uuid:s@203.0.113.11:8443?alpn=h3&sni=t.example#T')!;
  final ss = p.parseLink(
    'ss://${base64Url.encode(utf8.encode('2022-blake3-aes-128-gcm:AAAAAAAAAAAAAAAAAAAAAA=='))}@203.0.113.12:8388#S',
  )!;
  final trojan = p.parseLink('trojan://pw@203.0.113.13:443?sni=tr.example&type=ws&path=%2Fws#TR')!;
  final anytls = p.parseLink('anytls://pw@203.0.113.14:443?sni=a.example#A')!;

  void dump(String name, Map<String, dynamic> cfg) {
    final dir = Directory('build/test_configs')..createSync(recursive: true);
    File('${dir.path}/$name.json').writeAsStringSync(b.buildJson(cfg));
  }

  List<Map<String, dynamic>> rules(Map<String, dynamic> cfg) =>
      ((cfg['route'] as Map)['rules'] as List).cast<Map<String, dynamic>>();

  test('Windows TUN: Китай + Discord + автопереключение REALITY/HY2', () {
    final cfg = b.buildTunConfig(
      reality,
      fallbacks: [hy2],
      serverIps: ['203.0.113.10'],
      routing: const RoutingOptions(region: RoutingRegion.china),
      clashSecret: 'secret',
    );
    dump('win_china_discord_failover', cfg);

    final outs = (cfg['outbounds'] as List).cast<Map<String, dynamic>>();
    expect(outs.first['type'], 'urltest');
    expect(outs.first['tag'], 'proxy');
    expect(outs.first['outbounds'], ['proxy-0', 'proxy-1']);
    expect(outs.first['interrupt_exist_connections'], false);
    final h = outs.firstWhere((o) => o['type'] == 'hysteria2');
    expect(h['server_ports'], ['20000:50000']);
    expect(h['obfs'], {'type': 'salamander', 'password': 'ob'});
    expect((h['tls'] as Map)['alpn'], ['h3']);
    expect((h['tls'] as Map)['insecure'], true);

    final r = rules(cfg);
    expect(r[0], {'action': 'sniff'});
    expect(r[1], {'protocol': 'dns', 'action': 'hijack-dns'});
    expect(r[2]['process_name'], contains('Discord.exe'));
    expect(r[3]['domain_suffix'], contains('discord.media'));
    expect(
      r.any((x) => (x['rule_set'] as List?)?.contains('geosite-cn') ?? false),
      isTrue,
    );
    expect((cfg['route'] as Map)['auto_detect_interface'], true);
    final dns = cfg['dns'] as Map;
    final local = (dns['servers'] as List).firstWhere((s) => s['tag'] == 'dns-local');
    expect(local['server'], '223.5.5.5');
    expect(((cfg['experimental'] as Map)['clash_api'] as Map)['secret'], 'secret');
  });

  test('Windows TUN: Россия/Беларусь без Discord', () {
    final cfg = b.buildTunConfig(
      reality,
      routing: const RoutingOptions(discordMode: false),
    );
    dump('win_russia', cfg);
    final outs = (cfg['outbounds'] as List).cast<Map<String, dynamic>>();
    expect(outs.first['type'], 'vless');
    expect(outs.first['packet_encoding'], 'xudp');
    final r = rules(cfg);
    expect(r.any((x) => x.containsKey('process_name')), isFalse);
    expect(
      r.any((x) => (x['rule_set'] as List?)?.contains('geoip-by') ?? false),
      isTrue,
    );
    final local = ((cfg['dns'] as Map)['servers'] as List)
        .firstWhere((s) => s['tag'] == 'dns-local');
    expect(local['server'], '77.88.8.8');
  });

  test('без умной маршрутизации rule-set не подключаются', () {
    final cfg = b.buildTunConfig(
      reality,
      routing: const RoutingOptions(smartRouting: false),
    );
    expect((cfg['route'] as Map).containsKey('rule_set'), isFalse);
  });

  test('Android-цепочка: mixed-inbound, без process_name и TUN', () {
    final cfg = b.buildChainConfig(
      hy2,
      fallbacks: [reality],
      routing: const RoutingOptions(region: RoutingRegion.china),
    );
    dump('android_chain_china', cfg);
    final ins = (cfg['inbounds'] as List).cast<Map<String, dynamic>>();
    expect(ins.single['type'], 'mixed');
    expect(ins.single['listen_port'], 2081);
    expect(rules(cfg).any((x) => x.containsKey('process_name')), isFalse);
    expect((cfg['route'] as Map).containsKey('auto_detect_interface'), isFalse);
  });

  test('outbound для каждого протокола', () {
    for (final (name, node) in [
      ('reality', reality),
      ('hy2', hy2),
      ('tuic', tuic),
      ('ss', ss),
      ('trojan', trojan),
      ('anytls', anytls),
    ]) {
      final cfg = b.buildProbeConfig(node, 2090);
      dump('probe_$name', cfg);
      final out = (cfg['outbounds'] as List).first as Map<String, dynamic>;
      expect(out['tag'], 'proxy');
      expect(out['server'], node.host);
    }
    expect(b.buildOutbound(ss, 'x')['method'], '2022-blake3-aes-128-gcm');
    expect(b.buildOutbound(tuic, 'x')['udp_relay_mode'], 'native');
    expect((b.buildOutbound(trojan, 'x')['transport'] as Map)['type'], 'ws');
    expect(b.buildOutbound(anytls, 'x')['type'], 'anytls');
  });

  test('parsePortRanges', () {
    expect(SingboxConfigBuilder.parsePortRanges('443,20000-50000'), ['443:443', '20000:50000']);
    expect(SingboxConfigBuilder.parsePortRanges('20000:30000'), ['20000:30000']);
    expect(SingboxConfigBuilder.parsePortRanges('bad,70000,5-1'), isEmpty);
    expect(SingboxConfigBuilder.parsePortRanges(''), isEmpty);
  });

  test('ноды Node без протокола (старый кэш) собираются как VLESS', () {
    final legacy = Node.fromJson({
      'id': 'x',
      'host': '203.0.113.10',
      'port': 443,
      'uuid': uuid,
      'security': 'reality',
      'sni': 'www.microsoft.com',
      'realityPbk': 'K',
      'flow': 'xtls-rprx-vision',
      'fingerprint': 'chrome',
      'network': 'tcp',
    });
    expect(b.buildOutbound(legacy, 'p')['type'], 'vless');
  });
}
