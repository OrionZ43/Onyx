import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/domain/entities/node.dart';
import 'package:onyx/domain/sources/node_pool.dart';
import 'package:onyx/domain/subscription_parser.dart';
import 'package:onyx/domain/udp_probe.dart';
import 'package:onyx/presentation/providers/groups_provider.dart';
import 'package:onyx/presentation/providers/sources_provider.dart';
import 'package:onyx/presentation/providers/subscription_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _uuid = 'bf000d23-0752-40b4-affe-68f7707a9661';
Node _n(String host) =>
    const SubscriptionParser().parseLink('vless://$_uuid@$host:443?security=reality#$host')!;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('отбраковка мёртвых нод (#45)', () {
    final dead = _n('43.163.112.174').copyWith(isAlive: true, isTrulyWorking: true, latencyMs: 40);
    final live = _n('202.50.253.36').copyWith(isAlive: true, isTrulyWorking: true, latencyMs: 300);

    test('карантинная нода не выбирается, даже если «зелёная» и быстрее', () {
      expect(NodePool.best([dead, live])?.id, dead.id);
      expect(NodePool.best([dead, live], exclude: {dead.id})?.id, live.id);
      expect(NodePool.best([dead], exclude: {dead.id}), isNull);
    });

    test('failover пропускает карантин и в группе, и по всем', () {
      final third = _n('1.2.3.4').copyWith(isAlive: true, latencyMs: 90);
      expect(
        NodePool.failover(
          excludeId: live.id,
          groupNodes: [dead, live],
          allNodes: [dead, live, third],
          exclude: {dead.id},
        )?.id,
        third.id,
      );
    });

    test('markNodeAsDead ставит на карантин; autoNodeProvider его пропускает', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(subscriptionProvider);
      await c.read(sourcesProvider.notifier).ready;
      final sub = c.read(subscriptionProvider.notifier);
      sub.markNodeAsDead('abc');
      expect(c.read(subscriptionProvider).quarantined, contains('abc'));
      expect(c.read(subscriptionProvider).bestNode, isNull);
      expect(c.read(autoNodeProvider), isNull);
    });
  });

  group('честная подпись UDP (#45)', () {
    test('сервер недоступен ≠ UDP заблокирован', () {
      const dead = UdpProbeResult.unreachable(sent: 5);
      expect(dead.serverUnreachable, isTrue);
      expect(dead.summary, contains('Сервер недоступен'));
      expect(dead.summary, isNot(contains('заблокирован')));
      const blocked = UdpProbeResult(ok: false, sent: 5, received: 0);
      expect(blocked.summary, contains('заблокирован'));
    });

    test('Node.udpStatus', () {
      final n = _n('9.9.9.9');
      expect(n.udpStatus, UdpStatus.unknown);
      expect(n.copyWith(latencyMs: 50, isAlive: true).udpStatus, UdpStatus.unreachable);
      expect(n.copyWith(isAlive: false, latencyMs: 100).udpStatus, UdpStatus.unreachable);
      expect(n.copyWith(isAlive: true, isTrulyWorking: true).udpStatus, UdpStatus.blocked);
      expect(n.copyWith(isAlive: true, isTrulyWorking: true, udpSupported: true).udpStatus, UdpStatus.ok);
    });
  });

  group('«Обновить» (#45)', () {
    test('RefreshReport.summary', () {
      expect(const RefreshReport().summary, contains('Нет включённых'));
      expect(const RefreshReport(ok: 2).summary, contains('Обновлено источников: 2'));
      const bad = RefreshReport(failed: ['Китай: Нет соединения с интернетом']);
      expect(bad.allFailed, isTrue);
      expect(bad.summary, contains('Не удалось обновить: Китай'));
    });

    test('refreshAll обновляет источники, перепроверяет ноды, отчёт честный', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(subscriptionProvider);
      final src = c.read(sourcesProvider.notifier);
      await src.ready;
      await src.addLinks('vless://$_uuid@127.0.0.1:1?security=reality#a');
      final r = await src.refreshAll();
      expect(r.ok, 1);
      expect(r.failed, isEmpty);
      // Ни одного включённого — честное сообщение, а не тишина.
      await src.setEnabled(c.read(sourcesProvider).single.id, false);
      final none = await src.refreshAll();
      expect(none.summary, contains('Нет включённых'));
    });
  });
}
