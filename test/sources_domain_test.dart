import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/domain/entities/node.dart';
import 'package:onyx/domain/entities/node_group.dart';
import 'package:onyx/domain/entities/subscription_source.dart';
import 'package:onyx/domain/node_scorer.dart';
import 'package:onyx/domain/routing_region.dart';
import 'package:onyx/domain/sources/node_pool.dart';
import 'package:onyx/domain/sources/sources_codec.dart';
import 'package:onyx/domain/subscription_parser.dart';
import 'package:onyx/domain/subscription_presets.dart';

const _uuid = 'bf000d23-0752-40b4-affe-68f7707a9661';
Node _n(String host, {int port = 443, String name = 'n'}) =>
    const SubscriptionParser().parseLink('vless://$_uuid@$host:$port?security=reality#$name')!;

SubscriptionSource _src(String id, {bool enabled = true}) =>
    SubscriptionSource(id: id, name: id, kind: SourceKind.links, enabled: enabled);

void main() {
  tearDown(() {
    NodeScorer.region = RoutingRegion.russia;
    NodeScorer.preferUdp = false;
  });

  group('NodePool.merge', () {
    final a = _n('1.1.1.1', name: 'A из s1');
    final aDup = _n('1.1.1.1', name: 'A из s2'); // тот же server:port+uuid
    final b = _n('2.2.2.2', name: 'B');
    final c = _n('3.3.3.3', name: 'C');

    test('дубли склеиваются, источники копятся, параметры — из первого', () {
      final merged = NodePool.merge(
        [_src('s1'), _src('s2')],
        {'s1': [a, b], 's2': [aDup, c]},
      );
      expect(merged.map((n) => n.host), ['1.1.1.1', '2.2.2.2', '3.3.3.3']);
      expect(merged.first.name, 'A из s1');
      expect(merged.first.sourceIds, ['s1', 's2']);
      expect(merged[2].sourceIds, ['s2']);
    });

    test('выключенный источник не участвует', () {
      final merged = NodePool.merge(
        [_src('s1', enabled: false), _src('s2')],
        {'s1': [a, b], 's2': [c]},
      );
      expect(merged.map((n) => n.host), ['3.3.3.3']);
    });

    test('порядок источников решает, чьи параметры у дубля', () {
      final merged = NodePool.merge(
        [_src('s2'), _src('s1')],
        {'s1': [a], 's2': [aDup]},
      );
      expect(merged.single.name, 'A из s2');
      expect(merged.single.sourceIds, ['s2', 's1']);
    });

    test('результаты проб переносятся из previous', () {
      final probed = a.copyWith(isAlive: true, latencyMs: 42, isTrulyWorking: true, udpSupported: true);
      final merged = NodePool.merge([_src('s1')], {'s1': [a]}, previous: [probed]);
      expect(merged.single.latencyMs, 42);
      expect(merged.single.isTrulyWorking, isTrue);
      expect(merged.single.udpSupported, isTrue);
    });
  });

  group('группы и выбор', () {
    final x = _n('1.1.1.1', name: 'x').copyWith(sourceIds: ['s1'], isAlive: true, latencyMs: 300, isTrulyWorking: true);
    final y = _n('2.2.2.2', name: 'y').copyWith(sourceIds: ['s1'], isAlive: true, latencyMs: 50, udpSupported: true);
    final z = _n('3.3.3.3', name: 'z').copyWith(sourceIds: ['s2'], isAlive: true, latencyMs: 80, aiReachable: true, isTrulyWorking: true);
    final dead = _n('4.4.4.4', name: 'd').copyWith(sourceIds: ['s2']);
    final all = [x, y, z, dead];
    final user = NodeGroup(id: 'g1', name: 'Discord', nodeIds: [y.id], sourceIds: ['s2']);

    test('nodesOf: все, источник, спец-группы, пользовательская', () {
      expect(NodePool.nodesOf(null, all), all);
      expect(NodePool.nodesOf('src:s1', all), [x, y]);
      expect(NodePool.nodesOf(NodeGroup.udpId, all), [y]);
      expect(NodePool.nodesOf(NodeGroup.aiId, all), [z]);
      expect(NodePool.nodesOf(NodeGroup.favoritesId, all, favorites: {x.id}), [x]);
      expect(NodePool.nodesOf('g1', all, groups: [user]), [y, z, dead]);
      expect(NodePool.nodesOf('нет-такой', all, groups: [user]), isEmpty);
    });

    test('sourceGroups: по группе на источник, виртуальные', () {
      final g = NodePool.sourceGroups([_src('s1'), _src('s2')]);
      expect(g.map((e) => e.id), ['src:s1', 'src:s2']);
      expect(g.every((e) => e.isVirtual), isTrue);
    });

    test('best: проверенные важнее живых, мёртвые не выбираются', () {
      expect(NodePool.best(all)?.id, z.id); // проверенная, 80 мс
      expect(NodePool.best([y, dead])?.id, y.id); // только живая по TCP
      expect(NodePool.best([dead]), isNull);
    });

    test('best в режиме Discord предпочитает UDP', () {
      NodeScorer.preferUdp = true;
      final yv = y.copyWith(isTrulyWorking: true, latencyMs: 400);
      expect(NodePool.best([yv, z])?.id, yv.id);
    });

    test('failover: сначала группа, потом все; preferAi', () {
      final group = NodePool.nodesOf('src:s1', all);
      expect(NodePool.failover(excludeId: x.id, groupNodes: group, allNodes: all)?.id, y.id);
      expect(NodePool.failover(excludeId: x.id, groupNodes: [x], allNodes: all)?.id, z.id);
      expect(
        NodePool.failover(excludeId: x.id, groupNodes: group, allNodes: all, preferAi: true)?.id,
        y.id, // группа важнее AI: в группе AI-нод нет — берём лучшую из группы
      );
      expect(
        NodePool.failover(excludeId: x.id, groupNodes: [x, y, z], allNodes: all, preferAi: true)?.id,
        z.id,
      );
      expect(NodePool.failover(excludeId: x.id, groupNodes: [x], allNodes: [x]), isNull);
    });
  });

  group('миграция со старой схемы', () {
    const active = 'https://my-vpn.example/sub';
    final cached = [_n('1.1.1.1').copyWith(isAlive: true, latencyMs: 70), _n('2.2.2.2')];

    test('активная подписка → включённый источник с кэшем, сохранённые → выключенные', () {
      final r = SourcesCodec.migrate(LegacyState(
        subUrl: active,
        savedSubscriptions: [
          'Мой VPN||$active',
          'Запасной||https://backup.example/s',
          'https://bare.example/x',
        ],
        cachedNodes: cached,
        lastFetchedMs: 1700000000000,
      ));
      expect(r.sources.length, 3);
      final first = r.sources.first;
      expect(first.url, active);
      expect(first.name, 'Мой VPN'); // имя из сохранённых
      expect(first.enabled, isTrue);
      expect(first.nodeCount, 2);
      expect(first.lastUpdatedAt, DateTime.fromMillisecondsSinceEpoch(1700000000000));
      expect(r.sources[1].name, 'Запасной');
      expect(r.sources[1].enabled, isFalse);
      expect(r.sources[2].name, 'bare.example');
      final nodes = r.nodesBySource[first.id]!;
      expect(nodes.length, 2);
      expect(nodes.first.latencyMs, 70); // результаты проб не потерялись
      expect(nodes.every((n) => n.sourceIds.single == first.id), isTrue);
    });

    test('пресет распознаётся по URL', () {
      final r = SourcesCodec.migrate(LegacyState(subUrl: SubscriptionPresets.zieng2.url));
      expect(r.sources.single.presetId, 'zieng2');
      expect(r.sources.single.mirrors, isNotEmpty);
      expect(r.sources.single.id, 'preset_zieng2');
    });

    test('пустое состояние → пусто; только сохранённые → все выключены', () {
      expect(SourcesCodec.migrate(const LegacyState()).sources, isEmpty);
      final r = SourcesCodec.migrate(const LegacyState(savedSubscriptions: ['a||https://a.example/1']));
      expect(r.sources.single.enabled, isFalse);
      expect(r.nodesBySource, isEmpty);
    });
  });

  group('экспорт/импорт', () {
    final backup = SourcesBackup(
      sources: [
        SourcesCodec.newSubscription('https://a.example/sub', name: 'A'),
        SourcesCodec.newLinks('vless://$_uuid@1.1.1.1:443#x', count: 1),
      ],
      groups: const [NodeGroup(id: 'g1', name: 'Discord', nodeIds: ['n1'], sourceIds: ['s1'])],
      favorites: const {'n1', 'n2'},
    );

    test('JSON туда-обратно', () {
      final b = SourcesCodec.import(SourcesCodec.exportJson(backup));
      expect(b.sources.map((s) => s.id), backup.sources.map((s) => s.id));
      expect(b.sources[1].rawLinks, contains('vless://'));
      expect(b.groups.single.nodeIds, ['n1']);
      expect(b.favorites, {'n1', 'n2'});
    });

    test('ссылка onyx://import/ туда-обратно', () {
      final link = SourcesCodec.exportLink(backup);
      expect(link, startsWith('onyx://import/'));
      expect(SourcesCodec.import(link).sources.length, 2);
    });

    test('чужой текст — FormatException', () {
      expect(() => SourcesCodec.import('{"foo":1}'), throwsFormatException);
      expect(() => SourcesCodec.import('не json'), throwsFormatException);
    });
  });

  test('isDue: автообновление только для включённых подписок', () {
    final now = DateTime(2026, 11, 7, 12);
    final s = SourcesCodec.newSubscription('https://a.example/s');
    expect(s.isDue(now), isTrue); // ни разу не обновлялась
    expect(s.copyWith(lastUpdatedAt: now.subtract(const Duration(hours: 1))).isDue(now), isFalse);
    expect(s.copyWith(lastUpdatedAt: now.subtract(const Duration(hours: 7))).isDue(now), isTrue);
    expect(s.copyWith(enabled: false).isDue(now), isFalse);
    expect(s.copyWith(autoUpdateHours: 0).isDue(now), isFalse);
  });
}
