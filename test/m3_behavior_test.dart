// Поведение экранов Material 3 там, где оно должно совпадать с Onyx и Signal
// (#105, находки ревью): выбор группы и «Автовыбора» не переподключает VPN,
// импорт принимает то же, что SubscriptionImport, выбор в поиске закрывает
// лист, кнопки строк доступны скринридеру.

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:onyx/core/theme/theme_kind.dart';
import 'package:onyx/domain/entities/node.dart';
import 'package:onyx/domain/entities/vpn_state.dart';
import 'package:onyx/presentation/m3/m3_server_list.dart';
import 'package:onyx/presentation/providers/node_provider.dart';
import 'package:onyx/presentation/providers/sources_provider.dart';
import 'package:onyx/presentation/providers/subscription_provider.dart';
import 'package:onyx/presentation/screens/home_screen.dart';
import 'package:onyx/presentation/widgets/m3/m3_search.dart';
import 'package:onyx/presentation/widgets/m3/segmented_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens_golden_test.dart' show FakeSources, FakeVpn, app, loadFonts, nodes, settle;

const AppThemeKind m3 = AppThemeKind.material;

/// Экраны M3 — в раскладке телефона (Android).
final TargetPlatformVariant android = TargetPlatformVariant.only(TargetPlatform.android);

/// VPN, который запоминает вызовы (connect, disconnect…).
class RecordingVpn extends FakeVpn {
  RecordingVpn(super.state);
  final List<String> calls = [];

  @override
  dynamic noSuchMethod(Invocation i) {
    calls.add(i.memberName.toString());
    return Future<void>.value();
  }
}

/// Источники, которые запоминают, чем добавляли.
class RecordingSources extends FakeSources {
  RecordingSources() : super(const []);
  final List<String> calls = [];

  @override
  String? get lastError => 'Не удалось';

  @override
  set lastError(String? _) {}

  @override
  Future<SubscriptionSource?> addSubscription(String url, {String? name}) async {
    calls.add('subscription');
    return null;
  }

  @override
  Future<SubscriptionSource?> addLinks(String raw, {String? name}) async {
    calls.add('links');
    return null;
  }
}

Future<void> frames(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 16) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

ProviderContainer containerOf(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(MaterialApp)), listen: false);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'settings_theme_kind': 'material'});
    await loadFonts();
  });

  Future<void> pumpList(WidgetTester tester, VpnState state, RecordingVpn vpn) async {
    tester.view.physicalSize = const Size(390, 844) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(m3, state, const Scaffold(body: M3ServerList()), vpnCtl: vpn));
    await settle(tester);
  }

  final Node manual = nodes.firstWhere((n) => n.id == '5'); // Франкфурт FRA-01

  testWidgets('M3: группа автовыбора не сбрасывает ручной выбор и не переподключает (как Onyx)', (tester) async {
    final VpnState on = VpnConnected(node: manual, connectedAt: DateTime.now());
    final RecordingVpn vpn = RecordingVpn(on);
    await pumpList(tester, on, vpn);
    containerOf(tester).read(nodeSelectionProvider.notifier).select(manual);
    await settle(tester);

    // Кнопка группы — в пункте «Автовыбор» (такая же иконка у «Подписок» внизу).
    await tester.tap(find.descendant(
      of: find.ancestor(of: find.text('Автовыбор'), matching: find.byType(M3ListItem)).first,
      matching: find.byIcon(Symbols.tune),
    ));
    await frames(tester, 900);
    expect(find.text('Автовыбор из группы'), findsOneWidget);
    await tester.tap(find.text('Голос').last);
    await frames(tester, 900);

    expect(containerOf(tester).read(nodeSelectionProvider)?.id, manual.id);
    expect(vpn.calls.where((c) => c.contains('connect')), isEmpty);
  }, variant: android);

  testWidgets('M3: «Автовыбор» снимает ручной выбор без переподключения (как Onyx)', (tester) async {
    final VpnState on = VpnConnected(node: manual, connectedAt: DateTime.now());
    final RecordingVpn vpn = RecordingVpn(on);
    await pumpList(tester, on, vpn);
    containerOf(tester).read(nodeSelectionProvider.notifier).select(manual);
    await settle(tester);

    await tester.tap(find.text('Автовыбор'));
    await settle(tester);

    expect(containerOf(tester).read(nodeSelectionProvider), isNull);
    expect(vpn.calls.where((c) => c.contains('connect')), isEmpty);
  }, variant: android);

  testWidgets('M3: импорт принимает base64 без «://» — как SubscriptionImport', (tester) async {
    tester.view.physicalSize = const Size(390, 844) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final RecordingSources sources = RecordingSources();
    await tester.pumpWidget(app(m3, const VpnDisconnected(), const HomeScreen(), s: const SubscriptionState(), sourcesCtl: sources));
    await settle(tester);

    // base64 от «vless://…» — ни «://», ни http.
    await tester.enterText(find.byType(TextField), 'dmxlc3M6Ly9hYmNAMjAzLjAuMTEzLjc6NDQz');
    await tester.tap(find.byIcon(Symbols.check));
    await settle(tester);
    expect(sources.calls, ['links']);

    await tester.enterText(find.byType(TextField), 'https://sub.example.com/abc');
    await tester.tap(find.byIcon(Symbols.check));
    await settle(tester);
    expect(sources.calls, ['links', 'subscription']);
  }, variant: android);

  testWidgets('M3: выбор в поиске закрывает и поиск, и лист серверов', (tester) async {
    tester.view.physicalSize = const Size(390, 844) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app(m3, const VpnDisconnected(), const HomeScreen()));
    await settle(tester);

    showM3ServerSheet(tester.element(find.byType(HomeScreen)));
    await frames(tester, 1200);
    expect(find.byType(M3ServerList), findsOneWidget);
    await tester.tap(find.byType(M3SearchBar));
    await frames(tester, 800);
    await tester.enterText(find.byType(EditableText).last, 'стокгольм');
    await frames(tester, 600);
    await tester.tap(find.text('Стокгольм STO-01').last);
    await frames(tester, 2000);

    expect(find.byType(M3ServerList), findsNothing);
    expect(containerOf(tester).read(nodeSelectionProvider)?.id, '7');
  }, variant: android);

  testWidgets('M3: звезда и группа автовыбора — действия пункта для скринридера', (tester) async {
    final SemanticsHandle semantics = tester.ensureSemantics();
    final RecordingVpn vpn = RecordingVpn(const VpnDisconnected());
    await pumpList(tester, const VpnDisconnected(), vpn);

    Set<String> actionsOf(String text) {
      final Finder item = find.ancestor(of: find.text(text).first, matching: find.byType(M3ListItem)).first;
      final SemanticsData data = tester.getSemantics(item).getSemanticsData();
      return {
        for (final int id in data.customSemanticsActionIds ?? const <int>[]) CustomSemanticsAction.getAction(id)!.label!,
      };
    }

    expect(actionsOf('Автовыбор'), contains('Группа для автовыбора'));
    expect(actionsOf('Riga-1 REALITY'), contains('В избранное'));
    expect(actionsOf('Хельсинки HEL-02'), contains('Убрать из избранного'));
    semantics.dispose();
  }, variant: android);
}
