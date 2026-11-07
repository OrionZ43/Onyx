// Скриншоты реальных экранов по каждой теме (golden-тесты).
//
// Обновить: flutter test --update-goldens test/screens_golden_test.dart
// PNG ложатся в test/goldens/ и копируются в docs/redesign/screens/.
//
// Сеть и ядро не трогаются: контроллеры VPN, подписки и обновлений подменены.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/core/brand/onyx_fox.dart';
import 'package:onyx/core/theme/app_theme.dart';
import 'package:onyx/core/theme/theme_kind.dart';
import 'package:onyx/domain/entities/node.dart';
import 'package:onyx/domain/entities/vpn_state.dart';
import 'package:onyx/infrastructure/update_service.dart';
import 'package:onyx/presentation/providers/activity_provider.dart';
import 'package:onyx/presentation/providers/connect_phase.dart';
import 'package:onyx/presentation/providers/groups_provider.dart';
import 'package:onyx/presentation/providers/sources_provider.dart';
import 'package:onyx/presentation/providers/subscription_provider.dart';
import 'package:onyx/presentation/providers/theme_provider.dart';
import 'package:onyx/presentation/providers/update_provider.dart';
import 'package:onyx/presentation/providers/vpn_provider.dart';
import 'package:onyx/presentation/screens/about_screen.dart';
import 'package:onyx/presentation/screens/brand_splash.dart';
import 'package:onyx/presentation/screens/home_screen.dart';
import 'package:onyx/presentation/screens/faq_screen.dart';
import 'package:onyx/presentation/screens/onboarding_screen.dart';
import 'package:onyx/presentation/screens/groups_screen.dart';
import 'package:onyx/presentation/screens/settings_screen.dart';
import 'package:onyx/presentation/screens/setup_screen.dart';
import 'package:onyx/presentation/screens/subscription_manager_screen.dart';
import 'package:onyx/presentation/tray/tray_flyout.dart';
import 'package:onyx/presentation/widgets/add_source_sheet.dart';
import 'package:onyx/presentation/widgets/country_flag.dart';
import 'package:onyx/presentation/widgets/node_list_sheet.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Подмены ─────────────────────────────────────────────────────────────────

class FakeVpn extends StateNotifier<VpnState> implements VpnController {
  FakeVpn(super.state);

  /// Таймер сессии считается от настоящих часов, а тесты идут разное время:
  /// перед снимком сессия «началась» ровно 01:24:07 назад (+0,2 с запаса).
  void pinClock() {
    final s = state;
    if (s is! VpnConnected) return;
    state = VpnConnected(
      node: s.node,
      connectedAt: DateTime.now().subtract(const Duration(hours: 1, minutes: 24, seconds: 7, milliseconds: 200)),
      rxBytes: s.rxBytes,
      txBytes: s.txBytes,
    );
  }

  @override
  dynamic noSuchMethod(Invocation i) => Future<void>.value();
}

class FakeSub extends StateNotifier<SubscriptionState> implements SubscriptionController {
  FakeSub(super.state);
  @override
  dynamic noSuchMethod(Invocation i) => Future<void>.value();
}

class FakeSources extends StateNotifier<List<SubscriptionSource>> implements SourcesController {
  FakeSources(super.state);
  @override
  dynamic noSuchMethod(Invocation i) => Future<void>.value();
}

class FakeGroups extends StateNotifier<List<NodeGroup>> implements GroupsController {
  FakeGroups(super.state);
  @override
  dynamic noSuchMethod(Invocation i) => Future<void>.value();
}

class FakeFavorites extends StateNotifier<Set<String>> implements FavoritesController {
  FakeFavorites(super.state);
  @override
  dynamic noSuchMethod(Invocation i) => Future<void>.value();
}

class FakeAutoGroup extends StateNotifier<String?> implements AutoGroupController {
  FakeAutoGroup(super.state);
  @override
  dynamic noSuchMethod(Invocation i) => Future<void>.value();
}

final sources = [
  SubscriptionSource(id: 'z', name: 'Белые списки (РФ)', kind: SourceKind.subscription, url: 'https://z', presetId: 'zieng2', nodeCount: 7, autoUpdateHours: 6, lastUpdatedAt: DateTime.now().subtract(const Duration(minutes: 2))),
  const SubscriptionSource(id: 'c', name: 'Бесплатные (Китай)', kind: SourceKind.subscription, url: 'https://c', presetId: 'china-free', nodeCount: 38, status: SourceStatus.fetching),
  SubscriptionSource(id: 'v', name: 'Мой VPS', kind: SourceKind.links, nodeCount: 3, lastUpdatedAt: DateTime.now().subtract(const Duration(hours: 1))),
  const SubscriptionSource(id: 'w', name: 'Рабочая подписка', kind: SourceKind.subscription, url: 'https://sub.example.com/abc', nodeCount: 12, enabled: false, status: SourceStatus.error, error: 'HTTP 403'),
];

const groups = [
  NodeGroup(id: 'g1', name: 'Игры', nodeIds: ['4', '5'], sourceIds: ['v']),
  NodeGroup(id: 'g2', name: 'Работа', sourceIds: ['w']),
];

class FakeUpdate extends UpdateController {
  @override
  Future<UpdateInfo?> build() async => null;
}

Node node(String id, String name, int? ping, {bool ai = false, bool alive = true, bool verified = true, String proto = 'vless', bool udp = false}) => Node(
      id: id,
      name: name,
      host: '185.212.47.${10 + int.parse(id)}',
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
      protocol: proto,
      udpSupported: udp,
      sourceIds: [int.parse(id) <= 7 ? 'z' : 'v'],
    );

final nodes = [
  node('1', '🇳🇱 Амстердам AMS-03', 38, ai: true, udp: true),
  node('2', '🇳🇱 Амстердам AMS-01', 44, ai: true),
  node('3', '🇳🇱 Роттердам RTM-02', 52),
  node('4', '🇫🇮 Хельсинки HEL-02', 29, ai: true, proto: 'hysteria2', udp: true),
  node('5', '🇩🇪 Франкфурт FRA-01', 41, ai: true),
  node('6', '🇩🇪 Франкфурт FRA-04', 63, proto: 'tuic', udp: true),
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
          // Перед снимком shot() подводит время (FakeVpn.pinClock).
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

Widget app(AppThemeKind kind, VpnState vpn, Widget home, {SubscriptionState? s, ConnectPhase phase = ConnectPhase.idle}) => ProviderScope(
      overrides: [
        connectPhaseProvider.overrideWith((ref) => phase),
        activityProvider.overrideWith((ref) => ActivityLog(activity)),
        speedProvider.overrideWith((ref) => SpeedHistory(speedSamples)),
        themeKindProvider.overrideWith((ref) => ThemeKindNotifier(kind)),
        vpnControllerProvider.overrideWith((ref) => FakeVpn(vpn)),
        subscriptionProvider.overrideWith((ref) => FakeSub(s ?? sub)),
        updateControllerProvider.overrideWith(FakeUpdate.new),
        sourcesProvider.overrideWith((ref) => FakeSources(sources)),
        groupsProvider.overrideWith((ref) => FakeGroups(groups)),
        favoritesProvider.overrideWith((ref) => FakeFavorites({'1', '4'})),
        autoGroupProvider.overrideWith((ref) => FakeAutoGroup(null)),
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
  final app = find.byType(MaterialApp);
  if (find.byType(ProviderScope).evaluate().isNotEmpty && app.evaluate().isNotEmpty) {
    final vpn = ProviderScope.containerOf(tester.element(app.first), listen: false).read(vpnControllerProvider.notifier);
    if (vpn is FakeVpn) vpn.pinClock();
  }
  await tester.pump(const Duration(milliseconds: 600));
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/$name.png'));
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 1));
  debugDefaultTargetPlatformOverride = null;
}

/// Мокап-композиция мини-панели: угол рабочего стола, панель задач с треем,
/// над значком Onyx — панель (скругление и тень как у окон Windows 11).
Widget flyoutScene(int frame) => Builder(builder: (context) {
      return Stack(children: [
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF1B2433), Color(0xFF2B2235), Color(0xFF14161C)]),
            ),
          ),
        ),
        Positioned(
          left: 0, right: 0, bottom: 0, height: 48,
          child: Container(
            color: const Color(0xFF1C1F26),
            padding: const EdgeInsets.only(right: 16),
            child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              for (final c in [const Color(0xFF6B7280), const Color(0xFF9CA3AF), const Color(0xFF60A5FA)])
                Container(margin: const EdgeInsets.symmetric(horizontal: 7), width: 16, height: 16, decoration: BoxDecoration(color: c.withValues(alpha: .7), borderRadius: BorderRadius.circular(3))),
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: .08), borderRadius: BorderRadius.circular(4)),
                child: SizedBox.square(dimension: 16, child: CustomPaint(painter: OnyxFoxPainter(style: FoxStyle.silhouette, badge: const Color(0xFFD2B98F)))),
              ),
              const SizedBox(width: 18),
              const Text('23:30\n08.11.2026', textAlign: TextAlign.right, style: TextStyle(fontFamily: 'Inter', fontSize: 11, color: Colors.white, height: 1.3)),
            ]),
          ),
        ),
        Positioned(
          right: 40, bottom: 60,
          width: TrayFlyout.size.width, height: TrayFlyout.size.height,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 32, offset: Offset(0, 12))],
            ),
            clipBehavior: Clip.antiAlias,
            child: TrayFlyout(onOpenApp: () {}, onExit: () {}, onDismiss: () {}, showId: frame),
          ),
        ),
      ]);
    });
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await loadFonts();
  });

  const phone = Size(390, 844), desk = Size(1100, 720);
  final kinds = [AppThemeKind.onyx, AppThemeKind.signal];

  for (final k in kinds) {
    for (final s in ['off', 'on']) {
      testWidgets('${k.name} flyout $s', (tester) async {
        await shot(tester, '${k.name}-flyout-$s', app(k, vpnOf(s), Scaffold(body: flyoutScene(0))), const Size(760, 620), android: false);
      });
    }
    testWidgets('${k.name} flyout servers', (tester) async {
      await shot(tester, '${k.name}-flyout-servers', app(k, vpnOf('on'), Scaffold(body: flyoutScene(0))), const Size(760, 620), android: false, then: () async {
        await tester.tap(find.text('Автовыбор · из «Все»').first, warnIfMissed: false);
        await tester.pump(const Duration(milliseconds: 400));
      });
    });
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
    for (final e in {'onboarding': const OnboardingScreen(), 'subs': const SubscriptionManagerScreen(), 'faq': const FaqScreen()}.entries) {
      testWidgets('${k.name} phone ${e.key}', (tester) async {
        await shot(tester, '${k.name}-phone-${e.key}', app(k, vpnOf('off'), e.value), phone);
      });
    }
    testWidgets('${k.name} phone sources', (tester) async {
      await shot(tester, '${k.name}-phone-sources', app(k, vpnOf('off'), const SubscriptionManagerScreen()), phone);
    });
    testWidgets('${k.name} phone groups', (tester) async {
      await shot(tester, '${k.name}-phone-groups', app(k, vpnOf('off'), const GroupsScreen()), phone);
    });
    testWidgets('${k.name} phone add', (tester) async {
      await shot(tester, '${k.name}-phone-add', app(k, vpnOf('off'), const Scaffold(body: SafeArea(child: AddSourcePanel(mode: AddSourceMode.links, inline: true, initial: 'vless://8f1c@203.0.113.7:443?security=reality#Мой VPS\nhysteria2://k3y@203.0.113.7:8443#VPS HY2')))), phone);
    });
    testWidgets('${k.name} phone splash', (tester) async {
      await shot(tester, '${k.name}-phone-splash', app(k, vpnOf('off'), BrandSplash(kind: k)), phone);
    });
    testWidgets('${k.name} phone about', (tester) async {
      await shot(tester, '${k.name}-phone-about', app(k, vpnOf('off'), const AboutScreen()), phone);
    });
    testWidgets('${k.name} phone setup', (tester) async {
      await shot(tester, '${k.name}-phone-setup', app(k, vpnOf('off'), SetupScreen(onComplete: () {})), phone);
    });
    testWidgets('${k.name} phone settings', (tester) async {
      await shot(tester, '${k.name}-phone-settings', app(k, vpnOf('off'), const SettingsScreen()), phone);
    });
    testWidgets('${k.name} phone settings protection', (tester) async {
      await shot(tester, '${k.name}-phone-settings-protection', app(k, vpnOf('on'), const SettingsScreen()), phone, then: () async {
        await tester.drag(find.byType(ListView).first, const Offset(0, -330));
        await tester.pump(const Duration(milliseconds: 500));
      });
    });
    for (final s in ['off', 'on']) {
      testWidgets('${k.name} desktop $s', (tester) async {
        await shot(tester, '${k.name}-desktop-$s', app(k, vpnOf(s), const HomeScreen()), desk, android: false);
      });
    }
    testWidgets('${k.name} desktop servers', (tester) async {
      await shot(tester, '${k.name}-desktop-servers', app(k, vpnOf('on'), const HomeScreen()), desk, android: false, then: () async {
        await tester.tap(find.byTooltip('Серверы'));
        await tester.pump(const Duration(milliseconds: 500));
      });
    });
    testWidgets('${k.name} phone settings region', (tester) async {
      await shot(tester, '${k.name}-phone-settings-region', app(k, vpnOf('on'), const SettingsScreen()), phone, then: () async {
        await tester.drag(find.byType(ListView).first, const Offset(0, -330));
        await tester.pump(const Duration(milliseconds: 500));
        await tester.tap(find.text('Регион маршрутизации'));
        await tester.pump(const Duration(milliseconds: 600));
      });
    });
    // Этапы автопилота «Оникс» (#47): настоящий HomeScreen, этап — подменой
    // connectPhaseProvider.
    for (final (name, ph) in autopilotPhases) {
      testWidgets('${k.name} phone autopilot $name', (tester) async {
        await shot(tester, '${k.name}-phone-autopilot-$name', app(k, const VpnDisconnected(), const HomeScreen(), phase: ph), phone);
      });
      testWidgets('${k.name} desktop autopilot $name', (tester) async {
        await shot(tester, '${k.name}-desktop-autopilot-$name', app(k, const VpnDisconnected(), const HomeScreen(), phase: ph), desk, android: false);
      });
    }
    testWidgets('${k.name} flyout failed', (tester) async {
      await shot(tester, '${k.name}-flyout-failed', app(k, const VpnDisconnected(), Scaffold(body: flyoutScene(0)), phase: autopilotPhases.last.$2),
          const Size(760, 620), android: false);
    });
  }
}

/// Этапы автопилота для снимков: проверка серверов и отказ.
const autopilotPhases = <(String, ConnectPhase)>[
  ('checking', ConnectPhase.checking(7, 20)),
  (
    'failed',
    ConnectPhase.failed(
      ConnectFailure.allDead,
      'Ни один сервер сейчас не отвечает. Обновите список позже или добавьте свой сервер.',
      [ConnectAction.refresh, ConnectAction.addServer, ConnectAction.awsGuide],
    ),
  ),
];

/// Скорость за минуту и лента событий — для правой панели окна.
final speedSamples = [
  for (var i = 0; i < 60; i++)
    SpeedSample(
      (2.4 + 1.3 * math.sin(i / 4.5) + 0.5 * math.sin(i / 1.7)).abs() * 1024 * 1024,
      (170 + 80 * math.sin(i / 3.1 + 1)).abs() * 1024,
    ),
];
final activity = [
  ActivityEvent(DateTime(2026, 11, 8, 1, 12), 'Подключено · Амстердам AMS-03', ActivityKind.connected),
  ActivityEvent(DateTime(2026, 11, 8, 1, 11), 'Переключение: Хельсинки HEL-02 → Амстердам AMS-03', ActivityKind.switched),
  ActivityEvent(DateTime(2026, 11, 8, 0, 58), 'Проверено серверов: 20', ActivityKind.checked),
  ActivityEvent(DateTime(2026, 11, 8, 0, 57), 'Подключено · Хельсинки HEL-02', ActivityKind.connected),
];
