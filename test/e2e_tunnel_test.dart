import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/domain/routing_region.dart';
import 'package:onyx/domain/singbox_config_builder.dart';
import 'package:onyx/domain/subscription_parser.dart';
import 'package:onyx/domain/udp_probe.dart';

/// Сквозная проверка с настоящим sing-box (не в CI).
///
///   ONYX_E2E_SINGBOX — путь к sing-box(.exe) клиента;
///   ONYX_E2E_LINKS   — файл со ссылками (вывод tools/server/onyx-server.sh);
///   ONYX_E2E_RULES   — папка с .srs (для конфига цепочки).
///
/// Для каждой ноды: поднимаем sing-box с mixed-inbound → HTTPS через прокси
/// → STUN/UDP через SOCKS5 UDP ASSOCIATE. Плюс конфиг Android-цепочки
/// (urltest REALITY+HY2, регион «Китай»).
void main() {
  final sb = Platform.environment['ONYX_E2E_SINGBOX'];
  final linksFile = Platform.environment['ONYX_E2E_LINKS'];
  final rulesDir = Platform.environment['ONYX_E2E_RULES'] ?? '';
  final skip = (sb == null || linksFile == null) ? 'ONYX_E2E_* не заданы' : false;

  const b = SingboxConfigBuilder();

  Future<(bool, UdpProbeResult)> runWith(Map<String, dynamic> cfg, int port) async {
    final dir = Directory.systemTemp.createTempSync('onyx_e2e');
    final f = File('${dir.path}/c.json')..writeAsStringSync(b.buildJson(cfg));
    final proc = await Process.start(sb!, ['run', '-c', f.path], workingDirectory: dir.path);
    final errs = StringBuffer();
    proc.stderr.transform(const SystemEncoding().decoder).listen(errs.write);
    try {
      await Future.delayed(const Duration(seconds: 2));
      final client = HttpClient()..findProxy = (_) => 'PROXY 127.0.0.1:$port';
      var httpOk = false;
      try {
        final req = await client.getUrl(Uri.parse(SingboxConfigBuilder.probeUrl));
        final resp = await req.close().timeout(const Duration(seconds: 10));
        httpOk = resp.statusCode == 204;
      } catch (e) {
        // ignore: avoid_print
        print('HTTP ошибка: $e\n$errs');
      } finally {
        client.close(force: true);
      }
      final udp = await UdpProbe.viaSocks5(port);
      return (httpOk, udp);
    } finally {
      proc.kill();
      await proc.exitCode;
      dir.deleteSync(recursive: true);
    }
  }

  test('каждый транспорт: HTTPS + UDP через туннель', () async {
    final nodes = const SubscriptionParser().parse(File(linksFile!).readAsStringSync());
    expect(nodes, isNotEmpty);
    var port = 2190;
    for (final n in nodes) {
      final (http, udp) = await runWith(b.buildProbeConfig(n, port), port);
      // ignore: avoid_print
      print('${n.name}: HTTPS=${http ? "ok" : "FAIL"}; ${udp.summary}');
      expect(http, isTrue, reason: n.name);
      expect(udp.ok, isTrue, reason: '${n.name}: ${udp.error}');
      port++;
    }
  }, skip: skip, timeout: const Timeout(Duration(minutes: 2)));

  test('цепочка Android: urltest HY2+REALITY, регион Китай', () async {
    final nodes = const SubscriptionParser().parse(File(linksFile!).readAsStringSync());
    final hy2 = nodes.firstWhere((n) => n.isQuic);
    final cfg = b.buildChainConfig(
      hy2,
      fallbacks: nodes.where((n) => n.id != hy2.id).toList(),
      listenPort: 2199,
      routing: RoutingOptions(region: RoutingRegion.china, ruleSetDir: rulesDir),
    );
    final (http, udp) = await runWith(cfg, 2199);
    // ignore: avoid_print
    print('chain: HTTPS=${http ? "ok" : "FAIL"}; ${udp.summary}');
    expect(http, isTrue);
    expect(udp.ok, isTrue);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 1)));
}
