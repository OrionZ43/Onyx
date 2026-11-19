import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/domain/entities/node.dart';
import 'package:onyx/domain/entities/node_group.dart';
import 'package:onyx/domain/entities/subscription_source.dart';
import 'package:onyx/domain/failover_policy.dart';
import 'package:onyx/domain/smart_probe.dart';
import 'package:onyx/domain/sources/node_pool.dart';
import 'package:onyx/domain/subscription_parser.dart';

/// #68 (доменная часть): «свои» серверы (добавлены ссылками) — приоритет в
/// автовыборе и автопереключении, автогруппа «Свои», страна выхода.
/// Только фейковые адреса (203.0.113.x).

const _uuid = 'bf000d23-0752-40b4-affe-68f7707a9661';

Node _vless(int last, String name, {int? ms, bool working = true, bool own = false}) => const SubscriptionParser()
    .parseLink('vless://$_uuid@203.0.113.$last:443?security=reality&pbk=x&sid=1#$name')!
    .copyWith(latencyMs: ms, isAlive: true, isTrulyWorking: working, isOwn: own);

Node _hy2(int last, String name, {int? ms, bool own = false}) => const SubscriptionParser()
    .parseLink('hy2://pw@203.0.113.$last:443#$name')!
    .copyWith(latencyMs: ms, isAlive: true, isTrulyWorking: true, isOwn: own);

void main() {
  group('склейка источников', () {
    const sub = SubscriptionSource(id: 'sub', name: 'Подписка', kind: SourceKind.subscription, nodeCount: 2);
    const links = SubscriptionSource(id: 'links', name: 'Мои', kind: SourceKind.links, nodeCount: 2);

    test('нода из ссылок — своя, из подписки — чужая, общая — своя', () {
      final a = _vless(1, 'a'), b = _vless(2, 'b'), shared = _vless(3, 'shared');
      final merged = NodePool.merge([sub, links], {
        'sub': [a, shared],
        'links': [b, shared],
      });
      final byName = {for (final n in merged) n.name: n};
      expect(byName['a']!.isOwn, isFalse);
      expect(byName['b']!.isOwn, isTrue);
      expect(byName['shared']!.isOwn, isTrue);
      expect(byName['shared']!.sourceIds, ['sub', 'links']);
    });

    test('страна выхода переносится из прошлых результатов проб', () {
      final b = _vless(2, 'b');
      final merged = NodePool.merge([links], {'links': [b]}, previous: [b.copyWith(exitCountry: 'fi')]);
      expect(merged.single.exitCountry, 'fi');
    });
  });

  test('автогруппа «Свои» — только свои', () {
    final nodes = [_vless(1, 'a'), _vless(2, 'b', own: true)];
    expect(NodePool.nodesOf(NodeGroup.ownId, nodes).map((n) => n.name), ['b']);
  });

  group('автовыбор: свои при прочих равных раньше чужих', () {
    test('своя в пределах 133 % от лучшей чужой — первая', () {
      final ranked = NodePool.rank([_vless(1, 'free', ms: 90), _vless(2, 'own', ms: 115, own: true)]);
      expect(ranked.first.name, 'own'); // 115 ≤ 90 / 0,75 = 120
      expect(NodePool.best([_vless(1, 'free', ms: 90), _vless(2, 'own', ms: 115, own: true)])!.name, 'own');
    });

    test('своя заметно медленнее — чужая первая', () {
      final ranked = NodePool.rank([_vless(1, 'free', ms: 90), _vless(2, 'own', ms: 200, own: true)]);
      expect(ranked.map((n) => n.name), ['free', 'own']);
    });

    test('ярусы и потолки #60 не ломаются', () {
      // Своя «заведомо медленная» (выше потолка 400 мс) не обгоняет чужую быструю.
      expect(NodePool.rank([_vless(1, 'free', ms: 120), _vless(2, 'own', ms: 450, own: true)]).first.name, 'free');
      // Проверенная чужая — раньше непроверенной своей.
      expect(NodePool.rank([_vless(1, 'free', ms: 120), _vless(2, 'own', ms: 100, working: false, own: true)]).first.name, 'free');
    });

    test('QUIC сравнивается по RTT: время HTTPS ≈ 4 RTT (#73)', () {
      // Своя HY2: 330 мс HTTPS ≈ 83 мс RTT (÷4, #73), чужая REALITY: 90 мс TCP.
      expect(NodePool.rank([_vless(1, 'free', ms: 90), _hy2(2, 'own', ms: 330, own: true)]).first.name, 'own');
      expect(_hy2(2, 'x', ms: 330).rttMs, 83);
    });

    test('нет своих или только свои — порядок как раньше', () {
      final a = _vless(1, 'a', ms: 90), b = _vless(2, 'b', ms: 120);
      expect(NodePool.rank([b, a]).map((n) => n.name), ['a', 'b']);
      expect(NodePool.ownFirst([a.copyWith(isOwn: true), b.copyWith(isOwn: true)]).map((n) => n.name), ['a', 'b']);
    });
  });

  group('автопереключение: свой кандидат при прочих равных', () {
    final free = _vless(1, 'free'), own = _vless(2, 'own', own: true), udp = _vless(3, 'udp').copyWith(udpSupported: true);

    test('свой в пределах 133 % от самого быстрого — выбран', () {
      final next = FailoverPolicy.choose(candidates: [free, own], fresh: {free.id: 300, own.id: 390}, currentMs: -1);
      expect(next!.name, 'own');
    });

    test('свой заметно медленнее — самый быстрый', () {
      final next = FailoverPolicy.choose(candidates: [free, own], fresh: {free.id: 300, own.id: 600}, currentMs: -1);
      expect(next!.name, 'free');
    });

    test('UDP для голоса важнее «своего»', () {
      final next = FailoverPolicy.choose(
        candidates: [own, udp],
        fresh: {own.id: 300, udp.id: 320},
        currentMs: -1,
        preferUdp: true,
      );
      expect(next!.name, 'udp');
    });
  });

  group('страна выхода', () {
    test('в кэше сохраняется, «свой» — нет (вычисляется при склейке)', () {
      final n = _vless(1, 'a', own: true).copyWith(exitCountry: 'lv');
      final back = Node.fromJson(jsonDecode(jsonEncode(n.toJson())) as Map<String, dynamic>);
      expect(back.exitCountry, 'lv');
      expect(back.isOwn, isFalse);
      expect(_vless(1, 'b').toJson().containsKey('exitCountry'), isFalse);
    });

    test('проба не слушает — null без исключений', () async {
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = s.port;
      await s.close();
      expect(await DeepProbe.exitCountryViaProxy(port), isNull);
    });
  });
}
