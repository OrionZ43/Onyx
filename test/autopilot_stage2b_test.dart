import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/domain/failover_policy.dart';
import 'package:onyx/domain/singbox_config_builder.dart';
import 'package:onyx/domain/smart_probe.dart';
import 'package:onyx/domain/subscription_parser.dart';
import 'package:onyx/infrastructure/geo_ip.dart';
import 'package:onyx/infrastructure/network_watcher.dart';
import 'package:onyx/presentation/providers/connect_phase.dart';
import 'package:onyx/presentation/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Этап 2 автопилота, доводка: пинг кандидатов под VPN (изнутри пробы),
/// сон и обрыв, страна по IP перед первым подключением.

/// Поддельный SOCKS5: отвечает на CONNECT через [delay] кодом [code]
/// (0 — успех). Записывает, куда просили подключиться.
Future<(ServerSocket, List<String>)> _fakeSocks({Duration delay = Duration.zero, int code = 0}) async {
  final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  final targets = <String>[];
  server.listen((c) {
    final buf = <int>[];
    var stage = 0;
    c.listen((d) async {
      buf.addAll(d);
      if (stage == 0 && buf.length >= 3) {
        buf.removeRange(0, 3);
        stage = 1;
        c.add([0x05, 0x00]);
      }
      if (stage == 1 && buf.length >= 5) {
        final atyp = buf[3];
        final need = atyp == 0x01 ? 10 : (atyp == 0x04 ? 22 : 7 + buf[4]);
        if (buf.length < need) return;
        final host = atyp == 0x01
            ? buf.sublist(4, 8).join('.')
            : atyp == 0x03
                ? String.fromCharCodes(buf.sublist(5, 5 + buf[4]))
                : 'ipv6';
        final port = (buf[need - 2] << 8) | buf[need - 1];
        targets.add('$host:$port');
        buf.removeRange(0, need);
        stage = 2;
        await Future<void>.delayed(delay);
        c.add([0x05, code, 0x00, 0x01, 0, 0, 0, 0, 0, 0]);
      }
    }, onError: (_) {});
  });
  return (server, targets);
}

void main() {
  group('TCP-пинг сервера изнутри пробы (под VPN)', () {
    test('время до ответа на CONNECT = TCP-рукопожатие сервера', () async {
      final (srv, targets) = await _fakeSocks(delay: const Duration(milliseconds: 150));
      addTearDown(srv.close);
      final ms = await DeepProbe.tcpPingViaSocks5(srv.port, '203.0.113.7', 443);
      expect(ms, inInclusiveRange(140, 900));
      expect(targets, ['203.0.113.7:443', '203.0.113.7:443']); // два замера, берётся лучший
    });

    test('домен сервера передаётся как домен', () async {
      final (srv, targets) = await _fakeSocks();
      addTearDown(srv.close);
      expect(await DeepProbe.tcpPingViaSocks5(srv.port, 'srv.example', 8443), greaterThanOrEqualTo(0));
      expect(targets.first, 'srv.example:8443');
    });

    test('сервер не ответил (ошибка SOCKS) — −1', () async {
      final (srv, _) = await _fakeSocks(code: 0x05);
      addTearDown(srv.close);
      expect(await DeepProbe.tcpPingViaSocks5(srv.port, '203.0.113.7', 443), -1);
    });

    test('прокси не слушает — −1, без исключений', () async {
      final s = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final port = s.port;
      await s.close();
      expect(await DeepProbe.tcpPingViaSocks5(port, '203.0.113.7', 443), -1);
    });

    test('конфиг пробы: свой сервер — напрямую (IP, IPv6, домен)', () {
      const b = SingboxConfigBuilder();
      const p = SubscriptionParser();
      Map rule(String link) =>
          ((b.buildProbeConfig(p.parseLink(link)!, 30000)['route'] as Map)['rules'] as List).single as Map;
      expect(rule('hy2://pw@203.0.113.7:443#a'), {'ip_cidr': ['203.0.113.7/32'], 'outbound': 'direct'});
      expect(rule('hy2://pw@[2001:db8::1]:443#a'), {'ip_cidr': ['2001:db8::1/128'], 'outbound': 'direct'});
      expect(rule('hy2://pw@srv.example:443#a'), {'domain': ['srv.example'], 'outbound': 'direct'});
      expect((b.buildProbeConfig(p.parseLink('hy2://pw@203.0.113.7:443#a')!, 30000)['route'] as Map)['final'], 'proxy');
    });
  });

  group('сон и обрыв', () {
    test('сон узнаём по разрыву между опросами', () {
      final t = DateTime(2026, 11, 11, 20);
      expect(NetworkWatcher.isSleepGap(null, t), isFalse);
      expect(NetworkWatcher.isSleepGap(t, t.add(const Duration(seconds: 6))), isFalse);
      expect(NetworkWatcher.isSleepGap(t, t.add(const Duration(minutes: 5))), isTrue);
    });

    test('восстановление: тот же сервер всегда; подбор заново — только в автопилоте', () {
      expect(RecoveryPolicy.plan(autoFailover: true, manualPick: false), RecoveryStep.sameNodeThenAuto);
      expect(RecoveryPolicy.plan(autoFailover: true, manualPick: true), RecoveryStep.sameNodeManual);
      expect(RecoveryPolicy.plan(autoFailover: false, manualPick: false), RecoveryStep.sameNodeAutoOff);
      // Оба сразу — называем ручной выбор: «выберите другой или «Автовыбор»».
      expect(RecoveryPolicy.plan(autoFailover: false, manualPick: true), RecoveryStep.sameNodeManual);
      expect(RecoveryStep.sameNodeThenAuto.sameNodeOnly, isFalse);
      expect(RecoveryStep.sameNodeManual.sameNodeOnly, isTrue);
      expect(RecoveryStep.sameNodeAutoOff.sameNodeOnly, isTrue);
    });

    test('оговорка несёт тон: по умолчанию info, явно — как задали', () {
      const plain = ConnectPhase.notice('x');
      const warn = ConnectPhase.notice('y', kind: NoticeKind.warning);
      expect((plain as ConnectNotice).kind, NoticeKind.info);
      expect((warn as ConnectNotice).kind, NoticeKind.warning);
      expect(warn.label, 'y');
    });
  });

  group('страна по IP', () {
    test('только HTTPS — по дороге не видно, что спрашиваем', () {
      expect(GeoIp.sources, isNotEmpty);
      for (final (url, _) in GeoIp.sources) {
        expect(url, startsWith('https://'));
      }
    });

    test('geoFresh: до ответа — нет, после — да', () async {
      SharedPreferences.setMockInitialValues({'settings_migrated_v2': true});
      SettingsNotifier.lookupCountry = () async => 'CN';
      addTearDown(() => SettingsNotifier.lookupCountry = GeoIp.countryCode);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(settingsProvider);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final n = c.read(settingsProvider.notifier);
      expect(n.geoFresh, isFalse);
      await n.refreshGeo(canLookup: () => true);
      expect(n.geoFresh, isTrue);
      expect(c.read(settingsProvider).detectedRegion, RoutingRegion.china);
    });
  });
}
