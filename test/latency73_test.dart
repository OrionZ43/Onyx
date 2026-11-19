import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/domain/entities/node.dart';
import 'package:onyx/domain/failover_policy.dart';
import 'package:onyx/domain/node_scorer.dart';
import 'package:onyx/domain/sources/node_pool.dart';
import 'package:onyx/domain/subscription_parser.dart';

/// #73: REALITY и HY2 сравниваются по одной шкале задержки (≈ 1 RTT), а в
/// режиме Discord голосу при сопоставимой задержке достаётся UDP-нативный
/// протокол. Случай из жизни (друг в Китае, 12.11): на тех же серверах
/// REALITY 218/273 мс (TCP-пинг), HY2 923/1051 мс (время HTTPS).
/// Только фейковые адреса (203.0.113.x).

const _uuid = 'bf000d23-0752-40b4-affe-68f7707a9661';

Node _reality(int last, String name, {int? ms, bool udp = true}) => const SubscriptionParser()
    .parseLink('vless://$_uuid@203.0.113.$last:443?security=reality&pbk=x&sid=1#$name')!
    .copyWith(latencyMs: ms, isAlive: true, isTrulyWorking: true, udpSupported: udp);

Node _hy2(int last, String name, {int? ms, bool udp = true}) => const SubscriptionParser()
    .parseLink('hy2://pw@203.0.113.$last:443#$name')!
    .copyWith(latencyMs: ms, isAlive: true, isTrulyWorking: true, udpSupported: udp);

void main() {
  group('одна шкала задержки', () {
    test('TCP-пинг как есть, время HTTPS у QUIC — делим на 4', () {
      expect(_reality(1, 'r', ms: 218).rttMs, 218);
      expect(_hy2(2, 'h', ms: 923).rttMs, 231); // ≈ REALITY того же сервера
      expect(_hy2(3, 'h', ms: 1051).rttMs, 263);
      expect(_hy2(4, 'h').rttMs, isNull);
      expect(_hy2(5, 'h', ms: 900).rttIsEstimate, isTrue);
      expect(_reality(6, 'r', ms: 200).rttIsEstimate, isFalse);
    });

    test('потолок #60 один для всех протоколов (400 мс RTT)', () {
      expect(FailoverPolicy.latencyAcceptable(_hy2(1, 'h', ms: 1500)), isTrue); // ≈ 375
      expect(FailoverPolicy.latencyAcceptable(_hy2(2, 'h', ms: 1700)), isFalse); // ≈ 425
      expect(FailoverPolicy.latencyAcceptable(_reality(3, 'r', ms: 380)), isTrue);
      expect(FailoverPolicy.latencyAcceptable(_reality(4, 'r', ms: 420)), isFalse);
      expect(FailoverPolicy.quicCeilingMs, FailoverPolicy.tcpCeilingMs * Node.httpsRttFactor);
      // Потолок свежего замера (время HTTPS у всех) — в той же шкале.
      expect(FailoverPolicy.freshCeilingMs, FailoverPolicy.quicCeilingMs);
    });

    test('замерить нельзя — сохранённая задержка в единицах свежего замера', () {
      expect(FailoverPolicy.storedAsFreshMs(_reality(1, 'r', ms: 250)), 1000);
      expect(FailoverPolicy.storedAsFreshMs(_hy2(2, 'h', ms: 1000)), 1000);
      expect(FailoverPolicy.storedAsFreshMs(_hy2(3, 'h')), 0);
      // Раньше: REALITY 250 против HY2 1000 — HY2 «вчетверо медленнее».
      final r = _reality(1, 'r', ms: 250), h = _hy2(2, 'h', ms: 900);
      final fresh = {for (final n in [r, h]) n.id: FailoverPolicy.storedAsFreshMs(n)};
      expect(FailoverPolicy.choose(candidates: [r, h], fresh: fresh, currentMs: -1)!.name, 'h');
    });

    test('качество HY2 — по RTT: 1000 мс HTTPS ≈ 250 мс — «хорошо», а не «плохо»', () {
      expect(_hy2(1, 'h', ms: 1000).quality, NodeQuality.good);
      expect(_reality(2, 'r', ms: 250).quality, NodeQuality.good);
    });

    test('NodeScorer считает задержку по RTT', () {
      final h = _hy2(1, 'node', ms: 1000);
      final r = _reality(2, 'node', ms: 250);
      // Протокольные бонусы прежние, разница теперь только в них, а не в ×4 задержке.
      expect(NodeScorer.score(r) - NodeScorer.score(h), -1000);
    });
  });

  group('режим Discord: UDP-нативный протокол при сопоставимой задержке', () {
    // Тот же сервер, одинаковый RTT: REALITY 250 мс TCP-пинга, HY2 1000 мс HTTPS.
    final r = _reality(1, 'Finland REALITY', ms: 250);
    final h = _hy2(1, 'Finland HY2', ms: 1000);

    test('вне Discord — как раньше (REALITY первым)', () {
      expect(NodePool.rank([h, r]).first.name, 'Finland REALITY');
    });

    test('в Discord — HY2 первым', () {
      expect(NodePool.rank([r, h], preferUdpNative: true).first.name, 'Finland HY2');
      expect(NodePool.best([r, h], preferUdpNative: true)!.name, 'Finland HY2');
    });

    test('HY2 без подтверждённого UDP или заметно медленнее — не вперёд', () {
      final hNoUdp = _hy2(2, 'HY2 без UDP', ms: 1000, udp: false);
      expect(NodePool.rank([r, hNoUdp], preferUdpNative: true).first.name, 'Finland REALITY');
      final hSlow = _hy2(3, 'HY2 медленный', ms: 1600); // ≈ 400 > 250 / 0,75
      expect(NodePool.rank([r, hSlow], preferUdpNative: true).first.name, 'Finland REALITY');
    });

    test('свои по-прежнему раньше чужих, внутри своих — HY2', () {
      final freeHy2 = _hy2(9, 'free HY2', ms: 800);
      final ownR = r.copyWith(isOwn: true);
      final ownH = h.copyWith(isOwn: true);
      expect(NodePool.rank([freeHy2, ownR, ownH], preferUdpNative: true).map((n) => n.name).take(2), ['Finland HY2', 'Finland REALITY']);
    });

    test('автопереключение в Discord: HY2 в пределах трети — выбран', () {
      final next = FailoverPolicy.choose(candidates: [r, h], fresh: {r.id: 900, h.id: 1000}, currentMs: -1, preferUdp: true);
      expect(next!.name, 'Finland HY2'); // 1000 × 0,75 ≤ 900
      expect(FailoverPolicy.choose(candidates: [r, h], fresh: {r.id: 900, h.id: 1000}, currentMs: -1)!.name, 'Finland REALITY');
      expect(FailoverPolicy.choose(candidates: [r, h], fresh: {r.id: 900, h.id: 1300}, currentMs: -1, preferUdp: true)!.name, 'Finland REALITY');
    });

    test('автопереключение в Discord: среди HY2 свой раньше чужого', () {
      final free = _hy2(9, 'free HY2');
      final own = _hy2(1, 'Finland HY2').copyWith(isOwn: true);
      final next = FailoverPolicy.choose(candidates: [free, r, own], fresh: {free.id: 800, r.id: 850, own.id: 1000}, currentMs: -1, preferUdp: true);
      expect(next!.name, 'Finland HY2'); // 1000 × 0,75 ≤ 800
    });

    test('автопереключение в Discord: HY2 без UDP — как раньше', () {
      final hNoUdp = _hy2(2, 'HY2 без UDP', udp: false);
      expect(FailoverPolicy.choose(candidates: [r, hNoUdp], fresh: {r.id: 900, hNoUdp.id: 950}, currentMs: -1, preferUdp: true)!.name, 'Finland REALITY');
    });
  });
}
