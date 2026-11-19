import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/domain/entities/node.dart';
import 'package:onyx/domain/node_scorer.dart';
import 'package:onyx/domain/smart_probe.dart';
import 'package:onyx/domain/subscription_parser.dart';
import 'package:onyx/presentation/providers/subscription_provider.dart';

/// #41: нагрузка проб на реальном наборе больших бесплатных подписок
/// (Pawdroid + zieng2 + jichangx/free18). Не в CI, ходит в интернет:
///
///   ONYX_E2E_SINGBOX — путь к sing-box(.exe);
///   ONYX_E2E_LOAD=1  — включить.
///
/// Меряет: сколько нод, время TCP-пинга всех, сколько нод прошло Deep Probe
/// при бюджете и за какое время, сколько рабочих и с UDP.
const _subs = {
  'Pawdroid': [
    'https://raw.githubusercontent.com/Pawdroid/Free-servers/main/sub',
    'https://fastly.jsdelivr.net/gh/Pawdroid/Free-servers@main/sub',
  ],
  'zieng2': ['https://raw.githubusercontent.com/zieng2/wl/main/vless_universal.txt'],
  'jichangx': [
    'https://cdn.jsdelivr.net/gh/free18/v2ray@main/v.txt',
    'https://raw.githubusercontent.com/free18/v2ray/refs/heads/main/v.txt',
  ],
};

Future<String?> _fetch(String url) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    final req = await client.getUrl(Uri.parse(url));
    final resp = await req.close().timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) return null;
    return await resp.transform(const SystemEncoding().decoder).join();
  } catch (_) {
    return null;
  } finally {
    client.close(force: true);
  }
}

void main() {
  final sb = Platform.environment['ONYX_E2E_SINGBOX'];
  final on = Platform.environment['ONYX_E2E_LOAD'] == '1';
  final skip = (sb == null || !on) ? 'ONYX_E2E_LOAD=1 и ONYX_E2E_SINGBOX не заданы' : false;

  test('реальный набор: TCP-пинг всех + Deep Probe с бюджетом', () async {
    final nodes = <String, Node>{};
    for (final e in _subs.entries) {
      String? body;
      for (final url in e.value) {
        body = await _fetch(url);
        if (body != null) break;
      }
      final parsed = body == null ? const <Node>[] : const SubscriptionParser().parse(body);
      // ignore: avoid_print
      print('${e.key}: ${parsed.length} нод');
      for (final n in parsed) {
        nodes.putIfAbsent(n.id, () => n);
      }
    }
    expect(nodes, isNotEmpty);

    NodeScorer.preferUdp = true; // режим Discord по умолчанию
    final sw = Stopwatch()..start();
    final probed = await const SmartProbe().probeAll(nodes.values.toList());
    final tcpTime = sw.elapsed;
    final alive = probed.where((n) => n.isAlive).length;

    final results = <String, Node>{};
    var launched = 0;
    sw
      ..reset()
      ..start();
    await DeepProbe(singboxExePath: sb!).probeAllNodes(
      SubscriptionController.deepOrder(probed),
      minNodes: SubscriptionController.deepMinNodes,
      maxNodes: SubscriptionController.deepMaxNodes,
      enough: () => SubscriptionController.deepEnough(results.values, discord: true),
      onNodeResult: (u) {
        launched++;
        results[u.id] = u;
      },
    );
    final deepTime = sw.elapsed;
    final ok = results.values.where((n) => n.isTrulyWorking).toList();
    final udp = ok.where((n) => n.udpSupported).length;

    // ignore: avoid_print
    print('ИТОГО: нод ${nodes.length}, живых по TCP $alive, TCP-пинг ${tcpTime.inSeconds} с; '
        'Deep Probe: запусков sing-box $launched (бюджет ${SubscriptionController.deepMinNodes}–'
        '${SubscriptionController.deepMaxNodes}), ${deepTime.inSeconds} с, рабочих ${ok.length}, с UDP $udp');

    expect(launched, lessThanOrEqualTo(SubscriptionController.deepMaxNodes));
    // 16 воркеров × таймаут 4 с: даже 1000 мёртвых нод — не больше ~250 с.
    expect(tcpTime, lessThan(Duration(seconds: (nodes.length / 16 * 4).ceil() + 30)));
  }, skip: skip, timeout: const Timeout(Duration(minutes: 20)));
}
