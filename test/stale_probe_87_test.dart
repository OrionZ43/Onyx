import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/domain/entities/node.dart';
import 'package:onyx/domain/smart_probe.dart';
import 'package:onyx/domain/sources/node_pool.dart';
import 'package:onyx/domain/subscription_parser.dart';

/// #87: проваленная проверка не оставляет на экране старый пинг и «живость».
/// Случай из жизни (13.11): друг сменил сеть на China Telecom, HY2 не доходил
/// ни до одного сервера, а в списке France HY2 показывал вчерашние 1051 мс.
/// Только фейковые адреса (203.0.113.x) и loopback.

const _uuid = 'bf000d23-0752-40b4-affe-68f7707a9661';

Node _hy2(int last, {int? ms, bool alive = true, bool working = true}) => const SubscriptionParser()
    .parseLink('hy2://pw@203.0.113.$last:443#hy2-$last')!
    .copyWith(latencyMs: ms, isAlive: alive, isTrulyWorking: working, udpSupported: true, aiReachable: true);

Node _reality(int last, {int? ms, bool alive = true, bool working = true}) => const SubscriptionParser()
    .parseLink('vless://$_uuid@203.0.113.$last:443?security=reality&pbk=x&sid=1#r-$last')!
    .copyWith(latencyMs: ms, isAlive: alive, isTrulyWorking: working);

void main() {
  group('Node', () {
    test('copyWith: null оставляет пинг, clearLatency — стирает', () {
      final n = _reality(1, ms: 200);
      expect(n.copyWith().latencyMs, 200);
      expect(n.copyWith(isAlive: false).latencyMs, 200);
      expect(n.copyWith(clearLatency: true).latencyMs, isNull);
    });

    test('у мёртвой ноды пинга нет — ни цифры, ни «≈»', () {
      final dead = _hy2(1, ms: 1051, alive: false);
      expect(dead.latencyMs, 1051); // сырое значение (кэш) не трогаем
      expect(dead.rttMs, isNull);
      expect(dead.rttIsEstimate, isFalse);
      expect(dead.quality, NodeQuality.dead);
      expect(_hy2(2, ms: 1000).rttMs, 250);
      expect(_hy2(2, ms: 1000).rttIsEstimate, isTrue);
    });
  });

  group('итог полной проверки (DeepProbe.outcome)', () {
    test('HY2 не прошла: мёртвая, вчерашний пинг стёрт, UDP и ИИ — нет', () {
      final r = DeepProbe.outcome(_hy2(1, ms: 1051), basicOk: false);
      expect(r.isAlive, isFalse);
      expect(r.isTrulyWorking, isFalse);
      expect(r.latencyMs, isNull);
      expect(r.udpSupported, isFalse);
      expect(r.aiReachable, isFalse);
    });

    test('HY2 прошла: жива, пинг — время HTTPS', () {
      final r = DeepProbe.outcome(_hy2(1, ms: 1051, alive: false, working: false), basicOk: true, httpsMs: 980, udpOk: true);
      expect(r.isAlive, isTrue);
      expect(r.isTrulyWorking, isTrue);
      expect(r.latencyMs, 980);
      expect(r.rttMs, 245);
      expect(r.udpSupported, isTrue);
    });

    test('TCP-нода: TCP-пинга в пробе не было — живость и пинг этапа 1 остаются', () {
      final r = DeepProbe.outcome(_reality(1, ms: 220), basicOk: false);
      expect(r.isAlive, isTrue);
      expect(r.latencyMs, 220);
      expect(r.isTrulyWorking, isFalse);
    });

    test('TCP-нода под VPN: решает TCP-пинг изнутри пробы', () {
      final silent = DeepProbe.outcome(_reality(1, ms: 220), basicOk: false, tcpMs: -1);
      expect(silent.isAlive, isFalse);
      expect(silent.latencyMs, isNull);
      final answered = DeepProbe.outcome(_reality(2, ms: 220), basicOk: false, tcpMs: 240);
      expect(answered.isAlive, isTrue);
      expect(answered.latencyMs, 240);
    });

    test('TCP-нода прошла без TCP-пинга: прежний пинг, а если его нет — HTTPS ÷ 4 (#73)', () {
      expect(DeepProbe.outcome(_reality(1), basicOk: true, httpsMs: 900).latencyMs, 225);
      expect(DeepProbe.outcome(_reality(2, ms: 210), basicOk: true, httpsMs: 900).latencyMs, 210);
    });
  });

  group('слияние с пулом', () {
    test('случай друга: вчерашний HY2 1051 мс → сегодня провал → недоступен и в автовыбор не идёт', () {
      final yesterday = _hy2(1, ms: 1051); // вчера жил и работал
      // Этап 1: TCP-пинга у QUIC нет — нода остаётся кандидатом на проверку.
      final stage1 = DeepProbe.mergeTcp(yesterday, yesterday.copyWith(isAlive: true));
      expect(stage1.isAlive, isTrue);
      // Полная проверка не прошла.
      final now = DeepProbe.mergeDeep(stage1, DeepProbe.outcome(stage1, basicOk: false));
      expect(now.isAlive, isFalse);
      expect(now.latencyMs, isNull);
      expect(now.rttMs, isNull);
      expect(now.isTrulyWorking, isFalse);
      expect(NodePool.rank([now, _reality(2, ms: 222)]).map((n) => n.name), ['r-2']);
    });

    test('TCP-нода вне VPN: провал проверки не делает её мёртвой (живость — по TCP-пингу)', () {
      final cur = _reality(1, ms: 220);
      final m = DeepProbe.mergeDeep(cur, DeepProbe.outcome(cur, basicOk: false));
      expect(m.isAlive, isTrue);
      expect(m.latencyMs, 220);
      expect(m.isTrulyWorking, isFalse);
    });

    test('под VPN живость — из пробы, и у TCP, и у QUIC', () {
      final r = _reality(1, ms: 220);
      expect(DeepProbe.mergeDeep(r, DeepProbe.outcome(r, basicOk: false, tcpMs: -1), underTun: true).isAlive, isFalse);
      final h = _hy2(2, ms: 1051);
      final ok = DeepProbe.mergeDeep(h, DeepProbe.outcome(h, basicOk: true, httpsMs: 900), underTun: true);
      expect(ok.isAlive, isTrue);
      expect(ok.latencyMs, 900);
    });

    test('страна выхода не стирается проваленной проверкой (#68)', () {
      final h = _hy2(1, ms: 900).copyWith(exitCountry: 'fr');
      expect(DeepProbe.mergeDeep(h, DeepProbe.outcome(h, basicOk: false)).exitCountry, 'fr');
    });

    test('TCP-пинг не ответил: старый пинг стёрт, «работает» сброшено', () async {
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = s.port;
      await s.close();
      final node = const SubscriptionParser()
          .parseLink('vless://$_uuid@127.0.0.1:$port?security=reality&pbk=x&sid=1#local')!
          .copyWith(latencyMs: 180, isAlive: true, isTrulyWorking: true);
      final upd = await const SmartProbe().probeOne(node);
      expect(upd.isAlive, isFalse);
      expect(upd.latencyMs, isNull);
      final m = DeepProbe.mergeTcp(node, upd);
      expect(m.latencyMs, isNull);
      expect(m.isTrulyWorking, isFalse);
    });
  });
}
