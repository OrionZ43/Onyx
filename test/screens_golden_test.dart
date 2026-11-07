// Скриншоты реальных экранов по каждой теме (golden-тесты).
//
// Обновить: flutter test --update-goldens test/screens_golden_test.dart
// PNG ложатся в test/goldens/ и копируются в docs/redesign/screens/.
//
// Сеть и ядро не трогаются: контроллеры VPN, подписки и обновлений подменены.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/core/theme/app_theme.dart';
import 'package:onyx/core/theme/theme_kind.dart';
import 'package:onyx/domain/entities/node.dart';
import 'package:onyx/domain/entities/vpn_state.dart';
import 'package:onyx/infrastructure/update_service.dart';
import 'package:onyx/presentation/providers/subscription_provider.dart';
import 'package:onyx/presentation/providers/theme_provider.dart';
import 'package:onyx/presentation/providers/update_provider.dart';
import 'package:onyx/presentation/providers/vpn_provider.dart';
import 'package:onyx/presentation/screens/home_screen.dart';
import 'package:onyx/presentation/screens/settings_screen.dart';
import 'package:onyx/presentation/widgets/country_flag.dart';
import 'package:onyx/presentation/widgets/node_list_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Подмены ─────────────────────────────────────────────────────────────────

class FakeVpn extends StateNotifier<VpnState> implements VpnController {
  FakeVpn(super.state);
  @override
  dynamic noSuchMethod(Invocation i) => Future<void>.value();
}

class FakeSub extends StateNotifier<SubscriptionState> implements SubscriptionController {
  FakeSub(super.state);
  @override
  dynamic noSuchMethod(Invocation i) => Future<void>.value();
}

class FakeUpdate extends UpdateController {
  @override
  Future<UpdateInfo?> build() async => null;
}

Node node(String id, String name, int? ping, {bool ai = false, bool alive = true, bool verified = true}) => Node(
      id: id,
      name: name,
      host: 'h',
      port: 443,
      uuid: 'u',
      flow: '',
      security: 'reality',
      fingerprint: 'chrome',
      sni: 's',
      path: '',
      network: 'tcp',
      latencyMs: ping,
      isAlive: alive,
      isTrulyWorking: verified,
      aiReachable: ai,
    );

final nodes = [
  node('1', '🇳🇱 Амстердам AMS-03', 38, ai: true),
  node('2', '🇳🇱 Амстердам AMS-01', 44, ai: true),
  node('3', '🇳🇱 Роттердам RTM-02', 52),
  node('4', '🇫🇮 Хельсинки HEL-02', 29, ai: true),
  node('5', '🇩🇪 Франкфурт FRA-01', 41, ai: true),
  node('6', '🇩🇪 Франкфурт FRA-04', 63),
  node('7', '🇸🇪 Стокгольм STO-01', 47),
  node('8', '🇵🇱 Варшава WAW-01', 55, ai: true),
  node('9', '🇺🇸 Нью-Йорк NYC-02', 118, ai: true),
  node('10', '🇯🇵 Токио TYO-01', 212),
];

final sub = SubscriptionState(
  status: SubStatus.ready,
  nodes: nodes,
  url: 'https://example.com/sub',
  lastFetchedAt: DateTime.now().subtract(const Duration(minutes: 2)),
);

VpnState vpnOf(String s) => switch (s) {
      'on' => VpnConnected(
          node: nodes.first,
          connectedAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 24, seconds: 7)),
          rxBytes: 1954000000,
          txBytes: 224400000,
        ),
      'ing' => VpnConnecting(node: nodes.first),
      'err' => VpnError(message: 'AMS-03 не ответил за 10 с', node: nodes.first),
      _ => const VpnDisconnected(),
    };

// ── Шрифты ──────────────────────────────────────────────────────────────────

Future<void> loadFonts() async {
  final manifest = json.decode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
  for (final f in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(f['family'] as String);
    for (final a in (f['fonts'] as List).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(a['asset'] as String));
    }
    await loader.load();
  }
}

// ── Сборка ──────────────────────────────────────────────────────────────────

Widget app(AppThemeKind kind, VpnState vpn, Widget home, {SubscriptionState? s}) => ProviderScope(
      overrides: [
        themeKindProvider.overrideWith((ref) => ThemeKindNotifier(kind)),
        vpnControllerProvider.overrideWith((ref) => FakeVpn(vpn)),
        subscriptionProvider.overrideWith((ref) => FakeSub(s ?? sub)),
        updateControllerProvider.overrideWith(FakeUpdate.new),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.build(kind),
        home: home,
      ),
    );

Future<void> shot(WidgetTester tester, String name, Widget w, Size size, {bool android = true, Future<void> Function()? then}) async {
  await tester.runAsync(() => precacheDotFlags(['nl', 'fi', 'de', 'se', 'pl', 'us', 'jp']));
  debugDefaultTargetPlatformOverride = android ? TargetPlatform.android : TargetPlatform.windows;
  tester.view.physicalSize = size * 2;
  tester.view.devicePixelRatio = 2;
  await tester.pumpWidget(w);
  await tester.pump(const Duration(milliseconds: 50));
  // Векторные ассеты (флаги, иконки) грузятся асинхронно.
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 400)));
  await tester.pump(const Duration(seconds: 2));
  if (then != null) await then();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  await tester.pump(const Duration(milliseconds: 600));
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
  debugDefaultTargetPlatformOverride = null;
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await loadFonts();
  });

  const phone = Size(390, 844), desk = Size(1100, 720);
  final kinds = [AppThemeKind.onyx, AppThemeKind.signal];

  for (final k in kinds) {
    for (final s in ['off', 'ing', 'on', 'err']) {
      testWidgets('${k.name} phone $s', (tester) async {
        await shot(tester, '${k.name}-phone-$s', app(k, vpnOf(s), const HomeScreen()), phone);
      });
    }
    testWidgets('${k.name} phone list', (tester) async {
      await shot(tester, '${k.name}-phone-list', app(k, vpnOf('off'), const HomeScreen()), phone, then: () async {
        final ctx = tester.element(find.byType(HomeScreen));
        showOnyxNodeSheet(ctx);
        await tester.pump(const Duration(seconds: 1));
      });
    });
    testWidgets('${k.name} phone empty', (tester) async {
      await shot(tester, '${k.name}-phone-empty', app(k, vpnOf('off'), const HomeScreen(), s: const SubscriptionState()), phone);
    });
    testWidgets('${k.name} phone settings', (tester) async {
      await shot(tester, '${k.name}-phone-settings', app(k, vpnOf('off'), const SettingsScreen()), phone);
    });
    for (final s in ['off', 'on']) {
      testWidgets('${k.name} desktop $s', (tester) async {
        await shot(tester, '${k.name}-desktop-$s', app(k, vpnOf(s), const HomeScreen()), desk, android: false);
      });
    }
  }
}
