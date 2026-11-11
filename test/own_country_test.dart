// «Свои» серверы и страна сервера (#68). Только фейковые адреса (RFC 5737).
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/domain/entities/node.dart';
import 'package:onyx/presentation/providers/country_provider.dart';
import 'package:onyx/presentation/providers/own_nodes_provider.dart';
import 'package:onyx/presentation/providers/sources_provider.dart';
import 'package:onyx/presentation/providers/subscription_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSources extends StateNotifier<List<SubscriptionSource>> implements SourcesController {
  _FakeSources(super.state);
  @override
  dynamic noSuchMethod(Invocation i) => Future<void>.value();
}

class _FakeSub extends StateNotifier<SubscriptionState> implements SubscriptionController {
  _FakeSub(super.state);
  @override
  dynamic noSuchMethod(Invocation i) => Future<void>.value();
}

Node _node(String id, String name, String host, List<String> src) => Node(
      id: id,
      name: name,
      host: host,
      port: 443,
      uuid: 'u',
      flow: '',
      security: 'reality',
      fingerprint: 'chrome',
      sni: 's',
      path: '',
      network: 'tcp',
      sourceIds: src,
    );

void main() {
  final nodes = [
    _node('1', '🇳🇱 Амстердам AMS-03', '198.51.100.1', ['sub']),
    _node('2', 'Riga-1 REALITY', '203.0.113.2', ['mine']),
    _node('3', 'home-vps', '203.0.113.3', ['mine']),
    // Есть и в подписке, и в ссылках — всё равно свой.
    _node('4', '🇫🇮 Helsinki', '198.51.100.4', ['sub', 'mine']),
  ];

  test('свои — серверы из источников-ссылок', () {
    final c = ProviderContainer(overrides: [
      sourcesProvider.overrideWith((ref) => _FakeSources(const [
            SubscriptionSource(id: 'sub', name: 'Подписка', kind: SourceKind.subscription, url: 'https://example.com/sub'),
            SubscriptionSource(id: 'mine', name: 'Мой VPS', kind: SourceKind.links),
          ])),
      subscriptionProvider.overrideWith((ref) => _FakeSub(SubscriptionState(nodes: nodes))),
    ]);
    addTearDown(c.dispose);
    expect(c.read(ownNodeIdsProvider), {'2', '3', '4'});
    expect(c.read(ownNodesProvider).map((n) => n.id), ['2', '3', '4']);
  });

  test('без источников-ссылок своих нет', () {
    final c = ProviderContainer(overrides: [
      sourcesProvider.overrideWith((ref) => _FakeSources(const [
            SubscriptionSource(id: 'sub', name: 'Подписка', kind: SourceKind.subscription, url: 'https://example.com/sub'),
          ])),
      subscriptionProvider.overrideWith((ref) => _FakeSub(SubscriptionState(nodes: nodes))),
    ]);
    addTearDown(c.dispose);
    expect(c.read(ownNodeIdsProvider), isEmpty);
  });

  test('страна: выбор пользователя → название → неизвестно', () {
    const cr = CountryResolver({'203.0.113.3': 'nl', '198.51.100.1': 'zz'});
    expect(cr.of(nodes[1]).code, 'lv'); // «Riga» в названии
    expect(cr.of(nodes[2]).code, 'nl'); // выбрано вручную
    expect(cr.isPicked(nodes[2]), isTrue);
    expect(cr.detected(nodes[2]).isKnown, isFalse); // home-vps без подсказок
    expect(cr.of(nodes[0]).code, 'nl'); // неизвестный код в выборе — по названию
  });

  test('выбор страны сохраняется и сбрасывается', () async {
    SharedPreferences.setMockInitialValues({});
    final a = CountryOverrides();
    await a.set('203.0.113.3', 'NL');
    expect(a.state, {'203.0.113.3': 'nl'});

    final b = CountryOverrides();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(b.state, {'203.0.113.3': 'nl'});

    await b.set('203.0.113.3', '');
    expect(b.state, isEmpty);
    a.dispose();
    b.dispose();
  });
}
