import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/domain/entities/node.dart';
import 'package:onyx/domain/entities/subscription_source.dart';
import 'package:onyx/domain/subscription_parser.dart';
import 'package:onyx/presentation/providers/groups_provider.dart';
import 'package:onyx/presentation/providers/sources_provider.dart';
import 'package:onyx/presentation/providers/subscription_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _uuid = 'bf000d23-0752-40b4-affe-68f7707a9661';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('перезапуск: результаты проб не теряются (гонка источников и кэша)', () async {
    const src = SubscriptionSource(id: 'links_x', name: 'X', kind: SourceKind.links, nodeCount: 1);
    final raw = const SubscriptionParser()
        .parseLink('vless://$_uuid@127.0.0.1:5?security=reality#Germany%20%236')!
        .copyWith(sourceIds: ['links_x']);
    final probed = raw.copyWith(isAlive: true, latencyMs: 90, isTrulyWorking: true, udpSupported: true);
    SharedPreferences.setMockInitialValues({
      'sources_migrated_v1': true,
      'sources_v1': jsonEncode([src.toJson()]),
      'source_nodes_links_x': [jsonEncode(raw.toJson())],
      'cached_nodes': [jsonEncode(probed.toJson())],
    });

    final c = ProviderContainer();
    addTearDown(c.dispose);
    c.read(subscriptionProvider);
    await c.read(sourcesProvider.notifier).ready;
    await Future<void>.delayed(const Duration(milliseconds: 200));

    final n = c.read(subscriptionProvider).nodes.single;
    expect(n.latencyMs, 90);
    expect(n.isTrulyWorking, isTrue);
    expect(n.udpSupported, isTrue);
    expect(c.read(autoNodeProvider)?.id, n.id); // автовыбор видит живой сервер сразу

    final prefs = await SharedPreferences.getInstance();
    final saved = Node.fromJson(
      jsonDecode(prefs.getStringList('cached_nodes')!.single) as Map<String, dynamic>,
    );
    expect(saved.isTrulyWorking, isTrue); // кэш не перезаписан «непроверенной» нодой
  });
}
