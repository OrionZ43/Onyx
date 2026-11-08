import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/domain/entities/node.dart';
import 'package:onyx/domain/failover_policy.dart';
import 'package:onyx/domain/node_scorer.dart';
import 'package:onyx/domain/routing_region.dart';
import 'package:onyx/domain/sources/node_pool.dart';
import 'package:onyx/domain/subscription_parser.dart';

/// #60: автопереключение не прыгает на заведомо плохой сервер, не уводит с
/// ручного выбора и не скачет.
const _uuid = 'bf000d23-0752-40b4-affe-68f7707a9661';

Node _reality(String host, {required int ms, bool verified = true, bool udp = false, bool ai = false, String? name}) =>
    const SubscriptionParser()
        .parseLink('vless://$_uuid@$host:443?security=reality#${name ?? host}')!
        .copyWith(isAlive: true, latencyMs: ms, isTrulyWorking: verified, udpSupported: udp, aiReachable: ai);

Node _hy2(String host, {int? ms, bool verified = true}) =>
    const SubscriptionParser()
        .parseLink('hysteria2://pass@$host:443?sni=$host#hy2-$host')!
        .copyWith(isAlive: ms != null, latencyMs: ms, isTrulyWorking: verified);

void main() {
  tearDown(() {
    NodeScorer.region = RoutingRegion.russia;
    NodeScorer.preferUdp = false;
  });

  group('потолок задержки', () {
    test('TCP-пинг: 400 мс — ещё можно, выше — заведомо медленный', () {
      expect(FailoverPolicy.latencyAcceptable(_reality('1.1.1.1', ms: 400)), isTrue);
      expect(FailoverPolicy.latencyAcceptable(_reality('1.1.1.1', ms: 401)), isFalse);
      expect(FailoverPolicy.latencyAcceptable(_reality('1.1.1.1', ms: 2000)), isFalse);
    });

    test('QUIC: хранится время HTTPS-запроса — потолок 1200 мс', () {
      expect(FailoverPolicy.latencyAcceptable(_hy2('2.2.2.2', ms: 1100)), isTrue);
      expect(FailoverPolicy.latencyAcceptable(_hy2('2.2.2.2', ms: 1300)), isFalse);
    });

    test('нет данных о задержке — не отсекаем (будет свежий замер)', () {
      expect(FailoverPolicy.latencyAcceptable(_hy2('2.2.2.2')), isTrue);
    });
  });

  group('NodePool: медленные — только если нормальных нет', () {
    test('случай пользователя: REALITY+UDP на 2000 мс не обгоняет REALITY на 80 мс', () {
      NodeScorer.preferUdp = true; // режим Discord, по умолчанию включён
      final slowUdp = _reality('9.9.9.9', ms: 2000, udp: true, name: 'slow-udp');
      final fast = _reality('1.1.1.1', ms: 80, name: 'fast');
      // Раньше: −6000 против −4920 — выигрывал медленный.
      expect(NodeScorer.score(slowUdp), lessThan(NodeScorer.score(fast)));
      expect(NodePool.best([slowUdp, fast])?.id, fast.id);
    });

    test('в пределах потолка бонусы работают как раньше (UDP для Discord)', () {
      NodeScorer.preferUdp = true;
      final udp = _reality('2.2.2.2', ms: 300, udp: true);
      final fast = _reality('1.1.1.1', ms: 80);
      expect(NodePool.best([udp, fast])?.id, udp.id);
    });

    test('если быстрых нет — берём медленный, а не «ничего»', () {
      final slow = _reality('9.9.9.9', ms: 2000);
      expect(NodePool.best([slow])?.id, slow.id);
    });

    test('порядок rank: проверенные быстрые → живые быстрые → проверенные медленные', () {
      final vFast = _reality('1.1.1.1', ms: 100);
      final aliveFast = _reality('2.2.2.2', ms: 50, verified: false);
      final vSlow = _reality('3.3.3.3', ms: 900);
      expect(NodePool.rank([vSlow, aliveFast, vFast]).map((n) => n.id), [vFast.id, aliveFast.id, vSlow.id]);
    });
  });

  group('failoverShortlist', () {
    final cur = _reality('1.1.1.1', ms: 60, name: 'cur');
    final a = _reality('2.2.2.2', ms: 70, name: 'a');
    final b = _reality('3.3.3.3', ms: 90, name: 'b');
    final c = _reality('4.4.4.4', ms: 110, name: 'c');
    final d = _reality('5.5.5.5', ms: 130, ai: true, name: 'd');
    final slow = _reality('6.6.6.6', ms: 2000, name: 'slow');

    test('без текущего, без заведомо медленных, не больше трёх', () {
      final s = NodePool.failoverShortlist(excludeId: cur.id, groupNodes: [cur, a, b, c, d, slow], allNodes: [cur, a, b, c, d, slow]);
      expect(s.map((n) => n.name), ['a', 'b', 'c']);
    });

    test('сначала группа, потом все', () {
      final s = NodePool.failoverShortlist(excludeId: cur.id, groupNodes: [c], allNodes: [cur, a, b, c]);
      expect(s.map((n) => n.name), ['c', 'a', 'b']);
    });

    test('preferAi: хотя бы один ИИ-годный, если он есть', () {
      final s = NodePool.failoverShortlist(excludeId: cur.id, groupNodes: [a, b, c, d], allNodes: [a, b, c, d], preferAi: true);
      expect(s.map((n) => n.name), ['a', 'b', 'd']);
    });

    test('только медленные — список пуст: прыгать некуда', () {
      expect(NodePool.failoverShortlist(excludeId: cur.id, groupNodes: [cur, slow], allNodes: [cur, slow]), isEmpty);
    });

    test('карантин не попадает', () {
      final s = NodePool.failoverShortlist(excludeId: cur.id, groupNodes: [a, b], allNodes: [a, b], exclude: {a.id});
      expect(s.map((n) => n.name), ['b']);
    });
  });

  group('gate: когда можно прыгать', () {
    final now = DateTime(2026, 11, 8, 20);

    FailoverGate gate({
      bool auto = true,
      bool manual = false,
      bool dead = false,
      DateTime? lastSwitch,
      DateTime? noBetterUntil,
    }) =>
        FailoverPolicy.gate(
          autoFailover: auto,
          manualPick: manual,
          currentDead: dead,
          now: now,
          lastAutoSwitch: lastSwitch,
          noBetterUntil: noBetterUntil,
        );

    test('тумблер выключен — никогда', () {
      expect(gate(auto: false, dead: true), FailoverGate.disabled);
    });

    test('сервер выбран вручную — без спроса не уводим, даже если он мёртв', () {
      expect(gate(manual: true, dead: true), FailoverGate.manual);
    });

    test('недавно прыгали, а сервер отвечает — пауза', () {
      expect(gate(lastSwitch: now.subtract(const Duration(minutes: 1))), FailoverGate.cooldown);
    });

    test('недавно прыгали, но сервер не отвечает совсем — можно', () {
      expect(gate(dead: true, lastSwitch: now.subtract(const Duration(minutes: 1))), FailoverGate.allowed);
    });

    test('пауза прошла — можно', () {
      expect(gate(lastSwitch: now.subtract(const Duration(minutes: 4))), FailoverGate.allowed);
    });

    test('недавно искали и не нашли — не перемеряем', () {
      expect(gate(noBetterUntil: now.add(const Duration(seconds: 30))), FailoverGate.backoff);
      expect(gate(noBetterUntil: now.subtract(const Duration(seconds: 1))), FailoverGate.allowed);
    });
  });

  group('choose: по свежим замерам', () {
    final a = _reality('2.2.2.2', ms: 70, name: 'a');
    final b = _reality('3.3.3.3', ms: 90, udp: true, name: 'b');
    final c = _reality('4.4.4.4', ms: 110, ai: true, name: 'c');

    test('текущий мёртв: берём самого быстрого по свежему замеру, а не по старому', () {
      final next = FailoverPolicy.choose(candidates: [a, b, c], fresh: {a.id: 900, b.id: 300, c.id: 500}, currentMs: -1);
      expect(next?.name, 'b');
    });

    test('все кандидаты выше потолка 1200 мс — не прыгаем', () {
      final next = FailoverPolicy.choose(candidates: [a, b], fresh: {a.id: 2000, b.id: 1500}, currentMs: -1);
      expect(next, isNull);
    });

    test('кандидат не отвечает или замера нет — не кандидат', () {
      expect(FailoverPolicy.choose(candidates: [a, b], fresh: {a.id: -1}, currentMs: -1), isNull);
    });

    test('кандидат должен быть заметно быстрее текущего (≤ 75%)', () {
      expect(FailoverPolicy.choose(candidates: [a], fresh: {a.id: 800}, currentMs: 1000), isNull);
      expect(FailoverPolicy.choose(candidates: [a], fresh: {a.id: 700}, currentMs: 1000)?.name, 'a');
    });

    test('режим Discord: UDP-кандидат, если он не сильно медленнее', () {
      final fresh = {a.id: 200, b.id: 320};
      expect(FailoverPolicy.choose(candidates: [a, b], fresh: fresh, currentMs: -1, preferUdp: true)?.name, 'b');
      final tooSlow = {a.id: 200, b.id: 400}; // 400 > 200 × 1.5 + 50
      expect(FailoverPolicy.choose(candidates: [a, b], fresh: tooSlow, currentMs: -1, preferUdp: true)?.name, 'a');
    });

    test('ИИ-годный при preferAi — тоже только если не сильно медленнее', () {
      expect(
        FailoverPolicy.choose(candidates: [a, c], fresh: {a.id: 200, c.id: 250}, currentMs: -1, preferAi: true)?.name,
        'c',
      );
    });

    test('равные замеры — порядок приоритета', () {
      expect(FailoverPolicy.choose(candidates: [c, a], fresh: {a.id: 300, c.id: 300}, currentMs: -1)?.name, 'c');
    });
  });
}
