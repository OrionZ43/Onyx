import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/domain/entities/node.dart';
import 'package:onyx/domain/node_sanitizer.dart';
import 'package:onyx/domain/subscription_parser.dart';

void main() {
  const parser = SubscriptionParser();
  const uuid = 'bf000d23-0752-40b4-affe-68f7707a9661';

  group('ссылки', () {
    test('vless reality', () {
      final n = parser.parseLink(
        'vless://$uuid@1.2.3.4:443?security=reality&type=tcp&sni=www.microsoft.com'
        '&flow=xtls-rprx-vision&fp=chrome&pbk=PUBKEY&sid=abcd#%F0%9F%87%AF%F0%9F%87%B5%20Tokyo',
      )!;
      expect(n.protocol, NodeProtocol.vless);
      expect(n.host, '1.2.3.4');
      expect(n.port, 443);
      expect(n.uuid, uuid);
      expect(n.security, 'reality');
      expect(n.realityPbk, 'PUBKEY');
      expect(n.realitySid, 'abcd');
      expect(n.name, '🇯🇵 Tokyo');
    });

    test('vless id совместим со старым форматом', () {
      // Старый парсер: sha1("host:port:uuid")[:12] — избранное не теряется.
      final n = parser.parseLink('vless://$uuid@h.example:443?security=tls#x')!;
      expect(n.id.length, 12);
      final again = parser.parseLink('vless://$uuid@h.example:443?security=reality#y')!;
      expect(again.id, n.id);
    });

    test('hysteria2 с salamander и port hopping в query', () {
      final n = parser.parseLink(
        'hysteria2://p%40ss@srv.example.com:443/?sni=www.bing.com&obfs=salamander'
        '&obfs-password=ob&insecure=1&mport=20000-50000#HY2',
      )!;
      expect(n.protocol, NodeProtocol.hysteria2);
      expect(n.isQuic, isTrue);
      expect(n.password, 'p@ss');
      expect(n.port, 443);
      expect(n.sni, 'www.bing.com');
      expect(n.obfs, 'salamander');
      expect(n.obfsPassword, 'ob');
      expect(n.insecure, isTrue);
      expect(n.serverPorts, '20000-50000');
      expect(n.name, 'HY2');
    });

    test('hy2:// с мульти-портом в authority', () {
      final n = parser.parseLink('hy2://pw@1.2.3.4:443,20000-30000?sni=a.com#m')!;
      expect(n.protocol, NodeProtocol.hysteria2);
      expect(n.port, 443);
      expect(n.serverPorts, '20000-30000');
      expect(n.host, '1.2.3.4');
    });

    test('tuic', () {
      final n = parser.parseLink(
        'tuic://$uuid:secret@t.example:8443?congestion_control=bbr&alpn=h3&sni=t.example&allow_insecure=1#T',
      )!;
      expect(n.protocol, NodeProtocol.tuic);
      expect(n.uuid, uuid);
      expect(n.password, 'secret');
      expect(n.congestion, 'bbr');
      expect(n.alpn, ['h3']);
      expect(n.insecure, isTrue);
    });

    test('ss SIP002 (base64 userinfo)', () {
      final info = base64Url.encode(utf8.encode('2022-blake3-aes-128-gcm:AAAAAAAAAAAAAAAAAAAAAA=='));
      final n = parser.parseLink('ss://$info@5.6.7.8:8388#SS')!;
      expect(n.protocol, NodeProtocol.shadowsocks);
      expect(n.method, '2022-blake3-aes-128-gcm');
      expect(n.password, 'AAAAAAAAAAAAAAAAAAAAAA==');
      expect(n.port, 8388);
    });

    test('ss legacy (всё в base64)', () {
      final body = base64.encode(utf8.encode('aes-256-gcm:pw@5.6.7.8:8388'));
      final n = parser.parseLink('ss://$body#old')!;
      expect(n.method, 'aes-256-gcm');
      expect(n.password, 'pw');
      expect(n.host, '5.6.7.8');
    });

    test('trojan ws', () {
      final n = parser.parseLink(
        'trojan://pw@tr.example:443?sni=tr.example&type=ws&path=%2Fws&allowInsecure=1#TR',
      )!;
      expect(n.protocol, NodeProtocol.trojan);
      expect(n.network, 'ws');
      expect(n.path, '/ws');
      expect(n.insecure, isTrue);
    });

    test('anytls', () {
      final n = parser.parseLink('anytls://pw@a.example:443?sni=a.example#A')!;
      expect(n.protocol, NodeProtocol.anytls);
      expect(n.password, 'pw');
    });

    test('битые и неизвестные ссылки пропускаются', () {
      expect(parser.parseLink('vmess://xxx'), isNull);
      expect(parser.parseLink('hysteria2://@:0'), isNull);
      expect(parser.parseLink('garbage'), isNull);
    });
  });

  group('форматы подписок', () {
    final links = [
      'vless://$uuid@1.2.3.4:443?security=reality&type=tcp&sni=a.com&pbk=K&sid=1#v',
      'hysteria2://pw@1.2.3.4:443?sni=a.com&obfs=salamander&obfs-password=o#h',
      'trojan://pw@9.9.9.9:443?sni=b.com#t',
      'это не ссылка',
    ].join('\n');

    test('plain-текст', () {
      final nodes = parser.parse(links);
      expect(nodes.map((n) => n.protocol),
          [NodeProtocol.vless, NodeProtocol.hysteria2, NodeProtocol.trojan]);
    });

    test('base64-blob', () {
      final nodes = parser.parse(base64.encode(utf8.encode(links)));
      expect(nodes.length, 3);
    });

    test('Clash YAML', () {
      const yaml = '''
port: 7890
proxies:
  - name: "JP REALITY"
    type: vless
    server: 1.2.3.4
    port: 443
    uuid: bf000d23-0752-40b4-affe-68f7707a9661
    network: tcp
    tls: true
    flow: xtls-rprx-vision
    servername: www.microsoft.com
    client-fingerprint: chrome
    reality-opts:
      public-key: PUB
      short-id: abcd
  - name: HY2
    type: hysteria2
    server: 1.2.3.4
    port: 443
    ports: 20000-50000
    password: pw
    obfs: salamander
    obfs-password: ob
    sni: www.bing.com
    skip-cert-verify: true
    up: "50 Mbps"
    down: 200
  - name: TUIC
    type: tuic
    server: t.example
    port: 8443
    uuid: bf000d23-0752-40b4-affe-68f7707a9661
    password: s
    alpn: [h3]
  - name: SS
    type: ss
    server: 5.6.7.8
    port: 8388
    cipher: aes-128-gcm
    password: pw
  - name: VMESS-не-поддерживается
    type: vmess
    server: 1.1.1.1
    port: 1
proxy-groups: []
''';
      final nodes = parser.parse(yaml);
      expect(nodes.length, 4);
      final v = nodes[0];
      expect(v.security, 'reality');
      expect(v.realityPbk, 'PUB');
      expect(v.sni, 'www.microsoft.com');
      final h = nodes[1];
      expect(h.protocol, NodeProtocol.hysteria2);
      expect(h.serverPorts, '20000-50000');
      expect(h.upMbps, 50);
      expect(h.downMbps, 200);
      expect(h.insecure, isTrue);
      expect(nodes[2].protocol, NodeProtocol.tuic);
      expect(nodes[3].method, 'aes-128-gcm');
    });

    test('sing-box JSON', () {
      final json = jsonEncode({
        'outbounds': [
          {
            'type': 'hysteria2',
            'tag': 'hy',
            'server': '1.2.3.4',
            'server_port': 443,
            'server_ports': ['20000:50000'],
            'password': 'pw',
            'obfs': {'type': 'salamander', 'password': 'o'},
            'tls': {'enabled': true, 'server_name': 'a.com', 'insecure': true},
          },
          {
            'type': 'vless',
            'tag': 'v',
            'server': '1.2.3.4',
            'server_port': 443,
            'uuid': uuid,
            'flow': 'xtls-rprx-vision',
            'tls': {
              'enabled': true,
              'server_name': 'a.com',
              'reality': {'enabled': true, 'public_key': 'K', 'short_id': 's'},
            },
          },
          {'type': 'direct', 'tag': 'direct'},
        ],
      });
      final nodes = parser.parse(json);
      expect(nodes.length, 2);
      expect(nodes[0].serverPorts, '20000-50000');
      expect(nodes[1].security, 'reality');
    });

    test('looksLikeContent отличает URL от вставленных ссылок', () {
      expect(SubscriptionParser.looksLikeContent('https://example.com/sub'), isFalse);
      expect(SubscriptionParser.looksLikeContent('hy2://pw@1.2.3.4:443#x'), isTrue);
      expect(SubscriptionParser.looksLikeContent(base64.encode(utf8.encode(links))), isTrue);
    });
  });

  group('round-trip и санитайзер', () {
    test('toJson/fromJson сохраняет поля hysteria2', () {
      final n = parser.parseLink(
        'hysteria2://pw@1.2.3.4:443?sni=a.com&obfs=salamander&obfs-password=o&mport=20000-50000&alpn=h3#h',
      )!;
      final back = Node.fromJson(jsonDecode(jsonEncode(n.toJson())) as Map<String, dynamic>);
      expect(back.protocol, NodeProtocol.hysteria2);
      expect(back.obfs, 'salamander');
      expect(back.serverPorts, '20000-50000');
      expect(back.alpn, ['h3']);
    });

    test('старый JSON без protocol читается как vless', () {
      final back = Node.fromJson({'id': 'x', 'host': 'h', 'port': 1, 'uuid': uuid});
      expect(back.protocol, NodeProtocol.vless);
    });

    test('санитайзер не трогает не-VLESS', () {
      final n = parser.parseLink('anytls://pw@a.example:443?sni=a.example&fp=firefox#A')!;
      final s = const NodeSanitizer().sanitize(n);
      expect(s.fingerprint, 'firefox');
      expect(s.flow, '');
    });
  });

  // Ручная проверка на живой публичной подписке (не в CI):
  //   ONYX_SUB_FILE=путь\к\файлу flutter test test/subscription_parser_test.dart
  final live = Platform.environment['ONYX_SUB_FILE'];
  test('живой файл подписки (ONYX_SUB_FILE)', () {
    final nodes = parser.parse(File(live!).readAsStringSync());
    // ignore: avoid_print
    print('Распознано ${nodes.length} нод: '
        '${nodes.map((n) => NodeProtocol.label(n.protocol)).toSet()}');
    expect(nodes, isNotEmpty);
  }, skip: live == null ? 'ONYX_SUB_FILE не задан' : false);
}
