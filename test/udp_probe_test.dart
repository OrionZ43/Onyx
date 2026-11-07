import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/domain/node_scorer.dart';
import 'package:onyx/domain/routing_region.dart';
import 'package:onyx/domain/subscription_parser.dart';
import 'package:onyx/domain/udp_probe.dart';

void main() {
  final tx = Uint8List.fromList(List.generate(12, (i) => i + 1));

  test('STUN Binding Request: 20 байт, magic cookie, transaction id', () {
    final req = UdpProbe.buildStunRequest(tx);
    expect(req.length, 20);
    expect(req.sublist(0, 4), [0x00, 0x01, 0x00, 0x00]);
    expect(req.sublist(4, 8), [0x21, 0x12, 0xA4, 0x42]);
    expect(req.sublist(8), tx);
  });

  test('STUN Binding Response распознаётся, запрос — нет', () {
    final resp = Uint8List.fromList([
      0x01, 0x01, 0x00, 0x00, 0x21, 0x12, 0xA4, 0x42, ...tx,
    ]);
    expect(UdpProbe.parseStunResponse(resp), '0102030405060708090a0b0c');
    expect(UdpProbe.parseStunResponse(UdpProbe.buildStunRequest(tx)), isNull);
    expect(UdpProbe.parseStunResponse(Uint8List(5)), isNull);
  });

  test('SOCKS5 UDP: кодирование домена и разбор ответа с IPv4', () {
    final payload = Uint8List.fromList([9, 9, 9]);
    final enc = UdpProbe.encodeSocksUdp('stun.l.google.com', 19302, payload);
    expect(enc.sublist(0, 5), [0, 0, 0, 3, 17]);
    expect(enc.sublist(enc.length - 5), [0x4B, 0x66, 9, 9, 9]);
    // Ответ от сервера: ATYP=1 (IPv4).
    final reply = Uint8List.fromList([0, 0, 0, 1, 74, 125, 0, 1, 0x4B, 0x66, 7, 7]);
    expect(UdpProbe.decodeSocksUdp(reply), [7, 7]);
    // Разбор того, что сами закодировали (ATYP=3).
    expect(UdpProbe.decodeSocksUdp(enc), payload);
    // Фрагментированные датаграммы не поддерживаем.
    expect(UdpProbe.decodeSocksUdp(Uint8List.fromList([0, 0, 1, 1, 0, 0, 0, 0, 0, 0])), isNull);
  });

  test('summary понятен человеку', () {
    expect(
      const UdpProbeResult(ok: true, sent: 5, received: 5, rttMs: 84).summary,
      contains('голос Discord пойдёт'),
    );
    expect(
      const UdpProbeResult(ok: false, sent: 5, received: 0).summary,
      contains('не проходит'),
    );
    expect(const UdpProbeResult.failed('VPN не подключён').summary,
        contains('VPN не подключён'));
  });

  group('NodeScorer по региону', () {
    const p = SubscriptionParser();
    const uuid = 'bf000d23-0752-40b4-affe-68f7707a9661';
    final de = p
        .parseLink('vless://$uuid@1.1.1.1:443?security=reality#🇩🇪 Frankfurt')!
        .copyWith(isAlive: true, latencyMs: 100);
    final hk = p
        .parseLink('vless://$uuid@2.2.2.2:443?security=reality#🇭🇰 Hong Kong')!
        .copyWith(isAlive: true, latencyMs: 100);

    tearDown(() {
      NodeScorer.region = RoutingRegion.russia;
      NodeScorer.preferUdp = false;
    });

    test('Россия: Европа впереди', () {
      NodeScorer.region = RoutingRegion.russia;
      expect(NodeScorer.compare(de, hk), lessThan(0));
    });

    test('Китай: Гонконг впереди', () {
      NodeScorer.region = RoutingRegion.china;
      expect(NodeScorer.compare(hk, de), lessThan(0));
    });

    test('режим Discord предпочитает ноды с UDP', () {
      NodeScorer.region = RoutingRegion.china;
      NodeScorer.preferUdp = true;
      final hkNoUdp = hk;
      final hkUdp = hk.copyWith(udpSupported: true, latencyMs: 300);
      expect(NodeScorer.compare(hkUdp, hkNoUdp), lessThan(0));
    });
  });
}
