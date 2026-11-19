import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/domain/entities/node.dart';
import 'package:onyx/domain/subscription_parser.dart';
import 'package:onyx/infrastructure/sources_store.dart';
import 'package:onyx/presentation/providers/groups_provider.dart';
import 'package:onyx/presentation/providers/sources_provider.dart';
import 'package:onyx/presentation/providers/subscription_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _uuid = 'bf000d23-0752-40b4-affe-68f7707a9661';

// Порты 127.0.0.1:1..N закрыты — TCP-пинг мгновенно «мёртв», сеть не нужна.
String _link(int port, {String name = 'n'}) =>
    'vless://$_uuid@127.0.0.1:$port?security=reality&sni=a.com#$name$port';

Future<void> _settle() => Future<void>.delayed(const Duration(milliseconds: 300));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SourcesStore: миграция с диска', () {
    test('старые ключи → источники; второй запуск читает новые; старые ключи сохранены', () async {
      final cached = const SubscriptionParser().parseLink(_link(1))!.copyWith(isAlive: true, latencyMs: 33);
      SharedPreferences.setMockInitialValues({
        'sub_url': 'https://my.example/sub',
        'saved_subscriptions': ['Мой||https://my.example/sub', 'Второй||https://two.example/s'],
        'cached_nodes': [jsonEncode(cached.toJson())],
        'subscription_last_fetched': 1700000000000,
      });
      final store = SourcesStore();
      final first = await store.loadOrMigrate();
      expect(first.sources.map((s) => s.name), ['Мой', 'Второй']);
      expect(first.sources.map((s) => s.enabled), [true, false]);
      expect(first.nodesBySource[first.sources.first.id]!.single.latencyMs, 33);

      final again = await SourcesStore().loadOrMigrate();
      expect(again.sources.map((s) => s.id), first.sources.map((s) => s.id));
      expect(again.nodesBySource[first.sources.first.id]!.length, 1);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('sub_url'), 'https://my.example/sub'); // откат возможен
      expect(prefs.getBool('sources_migrated_v1'), isTrue);
    });
  });

  group('провайдеры', () {
    late ProviderContainer c;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      c = ProviderContainer();
      c.read(subscriptionProvider); // поднимает и sourcesProvider
      await c.read(sourcesProvider.notifier).ready;
    });
    tearDown(() => c.dispose());

    test('ссылки из двух источников склеиваются; выключение убирает ноды', () async {
      final src = c.read(sourcesProvider.notifier);
      final s1 = await src.addLinks('${_link(1)}\n${_link(2)}', name: 'Первый');
      final s2 = await src.addLinks('${_link(2)}\n${_link(3)}');
      expect(s1, isNotNull);
      expect(s2!.name, 'Ссылки (2)');
      await _settle();

      var nodes = c.read(subscriptionProvider).nodes;
      expect(nodes.length, 3); // :2 — дубль
      final dup = nodes.firstWhere((n) => n.port == 2);
      expect(dup.sourceIds, [s1!.id, s2.id]);

      await src.setEnabled(s1.id, false);
      nodes = c.read(subscriptionProvider).nodes;
      expect(nodes.map((n) => n.port).toSet(), {2, 3});
      expect(nodes.firstWhere((n) => n.port == 2).sourceIds, [s2.id]);

      // повторная вставка того же текста — тот же источник
      final again = await src.addLinks('${_link(2)}\n${_link(3)}');
      expect(again!.id, s2.id);
      expect(c.read(sourcesProvider).length, 2);
    });

    test('мусор не добавляется, причина в lastError', () async {
      final src = c.read(sourcesProvider.notifier);
      expect(await src.addLinks('просто текст'), isNull);
      expect(src.lastError, isNotNull);
      expect(c.read(sourcesProvider), isEmpty);
    });

    test('rename, reorder, remove чистит группы', () async {
      final src = c.read(sourcesProvider.notifier);
      final a = (await src.addLinks(_link(1)))!;
      final b = (await src.addLinks(_link(2)))!;
      await src.rename(a.id, 'Домашний');
      await src.reorder(1, 0);
      expect(c.read(sourcesProvider).map((s) => s.id), [b.id, a.id]);
      expect(c.read(sourcesProvider).last.name, 'Домашний');

      final g = await c.read(groupsProvider.notifier).create('Discord');
      await c.read(groupsProvider.notifier).addSource(g.id, a.id);
      await src.remove(a.id);
      expect(c.read(groupsProvider).single.sourceIds, isEmpty);
      expect(c.read(subscriptionProvider).nodes.single.port, 2);
    });

    test('группы, избранное, автогруппа и autoNodeProvider', () async {
      final src = c.read(sourcesProvider.notifier);
      final s = (await src.addLinks('${_link(1)}\n${_link(2)}\n${_link(3)}'))!;
      await _settle();
      final ids = c.read(subscriptionProvider).nodes.map((n) => n.id).toList();

      final groups = c.read(groupsProvider.notifier);
      final g = await groups.create('Для Discord');
      await groups.addNodes(g.id, [ids[2]]);
      expect(c.read(groupNodesProvider(g.id)).single.port, 3);
      expect(c.read(groupNodesProvider('src:${s.id}')).length, 3);
      expect(c.read(allGroupsProvider).map((x) => x.id), [g.id, 'src:${s.id}']);

      await c.read(favoritesProvider.notifier).toggleFavorite(ids[0]);
      expect(c.read(groupNodesProvider(NodeGroup.favoritesId)).single.port, 1);

      await c.read(autoGroupProvider.notifier).setAutoGroup(g.id);
      expect(c.read(autoGroupProvider), g.id);
      // Все мёртвые (порты закрыты) → лучшей ноды нет ни в группе, ни по всем.
      expect(c.read(autoNodeProvider), isNull);

      await groups.rename(g.id, 'Discord');
      await groups.removeNode(g.id, ids[2]);
      expect(c.read(groupNodesProvider(g.id)), isEmpty);
      await groups.delete(g.id);
      expect(c.read(groupsProvider), isEmpty);
    });

    test('экспорт → импорт в чистый контейнер', () async {
      final src = c.read(sourcesProvider.notifier);
      final s = (await src.addLinks(_link(5), name: 'Ссылка'))!;
      final g = await c.read(groupsProvider.notifier).create('Работа');
      await c.read(groupsProvider.notifier).addSource(g.id, s.id);
      await c.read(favoritesProvider.notifier).toggleFavorite('fav1');
      final json = src.exportJson();

      SharedPreferences.setMockInitialValues({});
      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      c2.read(subscriptionProvider);
      await c2.read(sourcesProvider.notifier).ready;
      final r = await c2.read(sourcesProvider.notifier).importJson(json);
      expect(r.ok, isTrue);
      expect(r.sources, 1);
      expect(r.groups, 1);
      expect(c2.read(sourcesProvider).single.name, 'Ссылка');
      expect(c2.read(favoritesProvider), contains('fav1'));
      await _settle();
      expect(c2.read(subscriptionProvider).nodes.single.port, 5);

      final bad = await c2.read(sourcesProvider.notifier).importJson('мусор');
      expect(bad.ok, isFalse);
    });

    test('Node.sourceIds сохраняется в JSON', () {
      final n = const SubscriptionParser().parseLink(_link(9))!.copyWith(sourceIds: ['a', 'b']);
      final back = Node.fromJson(jsonDecode(jsonEncode(n.toJson())) as Map<String, dynamic>);
      expect(back.sourceIds, ['a', 'b']);
      expect(back.sourceId, 'a');
    });
  });
}
