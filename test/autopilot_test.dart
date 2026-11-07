import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/domain/routing_region.dart';
import 'package:onyx/domain/subscription_parser.dart';
import 'package:onyx/presentation/providers/connect_phase.dart';
import 'package:onyx/presentation/providers/settings_provider.dart';
import 'package:onyx/presentation/providers/sources_provider.dart';
import 'package:onyx/presentation/providers/subscription_provider.dart';
import 'package:onyx/presentation/providers/vpn_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _uuid = 'bf000d23-0752-40b4-affe-68f7707a9661';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('регион «Авто»', () {
    test('Китай: UTC+8 и китайский пояс или локаль', () {
      expect(
        RoutingRegionLabel.detect(offset: const Duration(hours: 8), timeZoneName: 'China Standard Time', locale: 'en_US'),
        RoutingRegion.china,
      );
      expect(
        RoutingRegionLabel.detect(offset: const Duration(hours: 8), timeZoneName: 'CST', locale: 'zh_CN'),
        RoutingRegion.china,
      );
      expect(
        RoutingRegionLabel.detect(offset: const Duration(hours: 8), timeZoneName: 'GMT+08:00', locale: 'zh-Hans-CN'),
        RoutingRegion.china,
      );
    });

    test('не Китай: Сингапур (UTC+8), Минск, китайская локаль без UTC+8', () {
      expect(
        RoutingRegionLabel.detect(offset: const Duration(hours: 8), timeZoneName: 'Singapore Standard Time', locale: 'en_SG'),
        RoutingRegion.russia,
      );
      expect(
        RoutingRegionLabel.detect(offset: const Duration(hours: 3), timeZoneName: 'Belarus Standard Time', locale: 'ru_BY'),
        RoutingRegion.russia,
      );
      expect(
        RoutingRegionLabel.detect(offset: const Duration(hours: 3), timeZoneName: 'MSK', locale: 'zh_CN'),
        RoutingRegion.russia,
      );
    });

    test('resolve и parse: «Авто» по умолчанию', () {
      expect(RoutingRegion.auto.resolve(RoutingRegion.china), RoutingRegion.china);
      expect(RoutingRegion.russia.resolve(RoutingRegion.china), RoutingRegion.russia);
      expect(RoutingRegionLabel.parse(null), RoutingRegion.auto);
      expect(RoutingRegionLabel.parse('china'), RoutingRegion.china);
    });

    test('разовая миграция настроек: «Китай» и выключенный Discord → «Авто» и Discord вкл', () async {
      SharedPreferences.setMockInitialValues({
        'settings_routing_region': 'china',
        'settings_discord_mode': false,
      });
      SettingsNotifier.detectDevice = () => RoutingRegion.russia;
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(settingsProvider);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final s = c.read(settingsProvider);
      expect(s.routingRegion, RoutingRegion.auto);
      expect(s.effectiveRegion, RoutingRegion.russia);
      expect(s.discordMode, isTrue);
      // Повторно не сбрасывает: пользователь выбрал «Китай» вручную.
      await c.read(settingsProvider.notifier).setRoutingRegion(RoutingRegion.china);
      final c2 = ProviderContainer();
      addTearDown(c2.dispose);
      c2.read(settingsProvider);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(c2.read(settingsProvider).routingRegion, RoutingRegion.china);
    });
  });

  group('неподдерживаемые ссылки — понятная ошибка', () {
    test('unsupportedReason', () {
      expect(SubscriptionParser.unsupportedReason('vpn://AAAAeyJjb25maWc...'), contains('Amnezia'));
      expect(SubscriptionParser.unsupportedReason('vmess://abc'), contains('VMess'));
      expect(SubscriptionParser.unsupportedReason('awg://x'), contains('WireGuard'));
      expect(SubscriptionParser.unsupportedReason('foo://x'), contains('«foo://»'));
      expect(SubscriptionParser.unsupportedReason('https://a.example/sub'), isNull);
      expect(SubscriptionParser.unsupportedReason('hy2://pw@1.2.3.4:443'), isNull);
      expect(SubscriptionParser.unsupportedReason('просто текст'), isNull);
    });

    test('addSubscription(vpn://…) → null и lastError про Amnezia, источник не создан', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      c.read(subscriptionProvider);
      final src = c.read(sourcesProvider.notifier);
      await src.ready;
      expect(await src.addSubscription('vpn://AAAAeyJjb25maWdfdmVyc2lvbiI6Mn0'), isNull);
      expect(src.lastError, contains('Amnezia'));
      expect(await src.addLinks('vmess://eyJ2IjoiMiJ9'), isNull);
      expect(src.lastError, contains('VMess'));
      expect(c.read(sourcesProvider), isEmpty);
    });
  });

  group('автопилот smartConnect: честные отказы', () {
    late ProviderContainer c;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      c = ProviderContainer();
      c.read(subscriptionProvider);
      await c.read(sourcesProvider.notifier).ready;
    });
    tearDown(() => c.dispose());

    test('нет источников → noSources и предложение добавить сервер', () async {
      await c.read(vpnControllerProvider.notifier).smartConnect();
      final p = c.read(connectPhaseProvider);
      expect(p, isA<ConnectFailed>());
      p as ConnectFailed;
      expect(p.reason, ConnectFailure.noSources);
      expect(p.actions, contains(ConnectAction.addServer));
    });

    test('все серверы мёртвые → allDead, а не тишина', () async {
      await c.read(sourcesProvider.notifier).addLinks(
            'vless://$_uuid@127.0.0.1:1?security=reality#a\nvless://$_uuid@127.0.0.1:2?security=reality#b',
          );
      await c.read(vpnControllerProvider.notifier).smartConnect();
      final p = c.read(connectPhaseProvider);
      expect(p, isA<ConnectFailed>());
      expect((p as ConnectFailed).reason, ConnectFailure.allDead);
      expect(p.actions, contains(ConnectAction.refresh));
      expect(p.label, contains('Ни один сервер'));
    });

    test('ConnectPhase.label', () {
      expect(const ConnectPhase.checking(3, 20).label, 'Проверяю серверы… 3/20');
      expect(ConnectPhase.updating.busy, isTrue);
      expect(ConnectPhase.idle.busy, isFalse);
    });
  });
}
