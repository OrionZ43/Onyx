import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/core/log_service.dart';
import 'package:onyx/domain/entities/node.dart';
import 'package:onyx/domain/failover_policy.dart';
import 'package:onyx/domain/smart_probe.dart';
import 'package:onyx/domain/subscription_parser.dart';
import 'package:onyx/infrastructure/network_watcher.dart';
import 'package:onyx/presentation/providers/sources_provider.dart';
import 'package:onyx/presentation/providers/subscription_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// #69: test4 сам сменил сервер через ~1,5 мин после подключения.
///
/// По журналу Windows: туннель поднялся в 00:00:27 и в 00:01:46 был снят,
/// в 00:01:55 поднят на другом сервере. Перед этим (23:59:05) выключили
/// AmneziaVPN — для Onyx это «смена сети», и он запустил перепроверку
/// серверов (десятки sing-box). Она ещё шла под туннелем: пробы здоровья
/// через туннель стали медленными, три подряд выше 2,5 с — автопереключение.

const _uuid = 'bf000d23-0752-40b4-affe-68f7707a9661';
final _t0 = DateTime(2026, 11, 12, 0, 0, 27);

/// TCP-пинг, во время которого «поднимается туннель»: все ноды «живы»
/// за 1 мс — так выглядит рукопожатие, закончившееся локально в TUN.
class _TunnelUpMidwayProbe extends SmartProbe {
  const _TunnelUpMidwayProbe();
  @override
  Future<List<Node>> probeAll(List<Node> nodes, {void Function(int done, int total)? onProgress}) async {
    SubscriptionController.tunActive = () => true;
    return [for (final n in nodes) n.copyWith(isAlive: true, latencyMs: 1)];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('первые минуты после подключения', () {
    FailoverGate gate({required Duration since, bool dead = false}) => FailoverPolicy.gate(
          autoFailover: true,
          manualPick: false,
          currentDead: dead,
          now: _t0.add(since),
          connectedAt: _t0,
        );

    test('сервер отвечает — не прыгаем первые 3 минуты', () {
      expect(gate(since: const Duration(seconds: 79)), FailoverGate.settling); // случай из test4
      expect(gate(since: const Duration(minutes: 2, seconds: 59)), FailoverGate.settling);
      expect(gate(since: const Duration(minutes: 3, seconds: 1)), FailoverGate.allowed);
    });

    test('сервер не отвечает вовсе — менять можно сразу', () {
      expect(gate(since: const Duration(seconds: 30), dead: true), FailoverGate.allowed);
    });

    test('ручной выбор и выключенный тумблер сильнее всего', () {
      final at = _t0.add(const Duration(minutes: 10));
      expect(
        FailoverPolicy.gate(autoFailover: false, manualPick: false, currentDead: true, now: at, connectedAt: _t0),
        FailoverGate.disabled,
      );
      expect(
        FailoverPolicy.gate(autoFailover: true, manualPick: true, currentDead: true, now: at, connectedAt: _t0),
        FailoverGate.manual,
      );
    });
  });

  group('проба здоровья', () {
    test('медленная, пока идёт своя проверка серверов, — не в счёт; неответ — в счёт всегда', () {
      expect(FailoverPolicy.healthSampleBad(3100, thresholdMs: 2500, probesBusy: true), isFalse);
      expect(FailoverPolicy.healthSampleBad(3100, thresholdMs: 2500, probesBusy: false), isTrue);
      expect(FailoverPolicy.healthSampleBad(-1, thresholdMs: 2500, probesBusy: true), isTrue);
      expect(FailoverPolicy.healthSampleBad(800, thresholdMs: 2500, probesBusy: false), isFalse);
    });

    test('пробы считаются: без них счётчик 0', () {
      expect(DeepProbe.inFlight, 0);
    });
  });

  group('своё переподключение — не «смена сети»', () {
    final t = DateTime(2026, 11, 12, 0, 1, 46);

    test('во время тишины ни смены сети, ни «проснулись»', () {
      final quiet = t.add(const Duration(seconds: 20));
      expect(
        NetworkWatcher.decide(prevSig: 'eth=192.0.2.5', sig: 'eth=192.0.2.5,amn=10.8.1.2', prevPoll: t, now: t.add(const Duration(seconds: 5)), quietUntil: quiet),
        isNull,
      );
      expect(
        NetworkWatcher.decide(prevSig: 'a', sig: 'a', prevPoll: t, now: t.add(const Duration(seconds: 15)), quietUntil: quiet),
        isNull,
      );
    });

    test('после тишины смена сети снова событие', () {
      expect(
        NetworkWatcher.decide(prevSig: 'a', sig: 'b', prevPoll: t, now: t.add(const Duration(seconds: 25)), quietUntil: t.add(const Duration(seconds: 20))),
        NetEvent.changed,
      );
      expect(
        NetworkWatcher.decide(prevSig: 'a', sig: 'a', prevPoll: t, now: t.add(const Duration(minutes: 3))),
        NetEvent.resumed,
      );
      expect(NetworkWatcher.decide(prevSig: null, sig: 'a', prevPoll: null, now: t), isNull); // первый опрос
    });

    test('свой TUN (tun0, 172.19.0.x) в подпись сети не попадает', () {
      final base = NetworkWatcher.signature(const [NetAddr('Ethernet', '192.0.2.5')]);
      expect(
        NetworkWatcher.signature(const [NetAddr('Ethernet', '192.0.2.5'), NetAddr('tun0', '172.19.0.1')]),
        base,
      );
    });
  });

  test('туннель поднялся во время TCP-пинга — его «1 мс» не записываются', () async {
    const src = SubscriptionSource(id: 'links_x', name: 'X', kind: SourceKind.links, nodeCount: 1);
    final raw = const SubscriptionParser()
        .parseLink('vless://$_uuid@203.0.113.7:443?security=reality#Germany%20%236')!
        .copyWith(sourceIds: ['links_x']);
    final probed = raw.copyWith(isAlive: true, latencyMs: 90, isTrulyWorking: true);
    SharedPreferences.setMockInitialValues({
      'sources_migrated_v1': true,
      'sources_v1': jsonEncode([src.toJson()]),
      'source_nodes_links_x': [jsonEncode(raw.toJson())],
      'cached_nodes': [jsonEncode(probed.toJson())],
    });
    final tun0 = SubscriptionController.tunActive;
    final engine0 = SubscriptionController.probeEngine;
    SubscriptionController.tunActive = () => false;
    SubscriptionController.probeEngine = () => const _TunnelUpMidwayProbe();
    addTearDown(() {
      SubscriptionController.tunActive = tun0;
      SubscriptionController.probeEngine = engine0;
    });

    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(subscriptionProvider);
    await c.read(sourcesProvider.notifier).ready;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(c.read(subscriptionProvider).nodes.single.latencyMs, 90);

    SubscriptionController.tunActive = () => false; // проход начинается без VPN
    await c.read(subscriptionProvider.notifier).reprobe();

    expect(c.read(subscriptionProvider).nodes.single.latencyMs, 90, reason: 'замер «через TUN» отброшен');
  });

  group('журнал в файле', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('onyx_log69_'));
    tearDown(() {
      log.detachFile();
      LogService.maxFileBytes = 1024 * 1024;
      dir.deleteSync(recursive: true);
    });

    test('строки пишутся с датой, секреты вымараны, дамп конфига не пишется', () {
      log.persistTo(dir);
      log.w('Health: нода деградировала (3 плохих проб подряд)', tag: 'VPN');
      log.d('{"uuid": "$_uuid"}', tag: 'CFG');
      log.i('outbound {"uuid":"$_uuid"}', tag: 'BRIDGE');
      final text = File('${dir.path}${Platform.pathSeparator}onyx.log').readAsStringSync();
      expect(text, contains('[WRN][VPN] Health: нода деградировала'));
      expect(text, matches(RegExp(r'\d{4}-\d{2}-\d{2} \[\d{2}:\d{2}:\d{2}')));
      expect(text, isNot(contains(_uuid)));
      expect(text, isNot(contains('[CFG]')));
    });

    test('больше лимита — файл уходит в .1, на диске не больше двух', () {
      LogService.maxFileBytes = 2000;
      log.persistTo(dir);
      for (var i = 0; i < 100; i++) {
        log.i('строка $i ${'x' * 40}', tag: 'TEST');
      }
      final files = dir.listSync().map((f) => f.uri.pathSegments.last).toList()..sort();
      expect(files, ['onyx.log', 'onyx.log.1']);
      expect(File('${dir.path}${Platform.pathSeparator}onyx.log').lengthSync(), lessThan(2200));
      expect(File('${dir.path}${Platform.pathSeparator}onyx.log').readAsStringSync(), contains('строка 99'));
    });
  });
}
