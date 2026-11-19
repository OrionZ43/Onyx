// «Свои» серверы и страна сервера в интерфейсе (#68). Признак Node.isOwn и
// страну выхода Node.exitCountry ставит домен («Оникс», его тесты — в
// test/own_nodes_*); здесь — как их читает UI. Только фейковые адреса.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/domain/entities/node.dart';
import 'package:onyx/presentation/providers/country_provider.dart';
import 'package:onyx/presentation/providers/own_nodes_provider.dart';
import 'package:onyx/presentation/providers/subscription_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeSub extends StateNotifier<SubscriptionState> implements SubscriptionController {
  _FakeSub(super.state);
  @override
  dynamic noSuchMethod(Invocation i) => Future<void>.value();
}

Node _node(String id, String name, String host, {bool own = false, String? exit}) => Node(
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
      isOwn: own,
      exitCountry: exit,
    );

void main() {
  final nodes = [
    _node('1', '🇳🇱 Амстердам AMS-03', '198.51.100.1'),
    _node('2', 'Riga-1 REALITY', '203.0.113.2', own: true),
    _node('3', 'home-vps', '203.0.113.3', own: true),
    _node('4', 'vps-2', '203.0.113.4', own: true, exit: 'de'),
    // Название говорит «Финляндия», а выход в Швеции — название важнее.
    _node('5', 'Finland HY2', '203.0.113.5', own: true, exit: 'se'),
  ];

  test('свои — по признаку домена Node.isOwn', () {
    final c = ProviderContainer(overrides: [
      subscriptionProvider.overrideWith((ref) => _FakeSub(SubscriptionState(nodes: nodes))),
    ]);
    addTearDown(c.dispose);
    expect(c.read(ownNodeIdsProvider), {'2', '3', '4', '5'});
  });

  test('страна: выбор пользователя → название → страна выхода', () {
    const cr = CountryResolver({'203.0.113.3': 'nl', '198.51.100.1': 'zz'});
    expect(cr.of(nodes[1]).code, 'lv'); // «Riga» в названии
    expect(cr.sourceOf(nodes[1]), CountrySource.name);
    expect(cr.of(nodes[2]).code, 'nl'); // выбрано вручную
    expect(cr.sourceOf(nodes[2]), CountrySource.picked);
    expect(cr.detected(nodes[2]).isKnown, isFalse); // home-vps: ни названия, ни проверки
    expect(cr.detectedHow(nodes[2]), isNull);
    expect(cr.of(nodes[3]).code, 'de'); // только страна выхода
    expect(cr.sourceOf(nodes[3]), CountrySource.probe);
    expect(cr.detectedHow(nodes[3]), 'по проверке сервера');
    expect(cr.of(nodes[4]).code, 'fi'); // название важнее страны выхода
    expect(cr.of(nodes[0]).code, 'nl'); // неизвестный код в выборе — по названию
    expect(cr.sourceOf(nodes[0]), CountrySource.name);
  });

  test('без названия и проверки — «уточнится после проверки»', () {
    const cr = CountryResolver({});
    expect(cr.sourceOf(nodes[2]), CountrySource.none);
    expect(CountrySource.none.label, contains('после проверки'));
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
