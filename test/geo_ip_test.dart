import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/infrastructure/geo_ip.dart';
import 'package:onyx/presentation/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Этап 2: регион «Авто» по внешнему IP.
void main() {
  test('Cloudflare trace: loc=', () {
    const body = 'fl=123\nh=www.cloudflare.com\nip=203.0.113.5\nts=1\nvisit_scheme=https\nloc=CN\ntls=TLSv1.3\n';
    expect(GeoIp.parseTrace(body), 'CN');
    expect(GeoIp.parseTrace('loc=XX\n'), isNull); // неизвестно
    expect(GeoIp.parseTrace('loc=T1\n'), isNull); // Tor
    expect(GeoIp.parseTrace('ip=1.2.3.4\n'), isNull);
  });

  test('ip-api line и ip.sb JSON', () {
    expect(GeoIp.parseLine('BY\n'), 'BY');
    expect(GeoIp.parseLine('<html>'), isNull);
    expect(GeoIp.parseIpSb('{"country_code":"ru","ip":"1.2.3.4"}'), 'RU');
    expect(GeoIp.parseIpSb('не json'), isNull);
  });

  test('страна → регион: CN — Китай, RU/BY — Россия/Беларусь, прочие — по часовому поясу', () {
    expect(GeoIp.regionFor('CN'), RoutingRegion.china);
    expect(GeoIp.regionFor('by'), RoutingRegion.russia);
    expect(GeoIp.regionFor('RU'), RoutingRegion.russia);
    expect(GeoIp.regionFor('HK'), isNull); // Гонконг — не за файрволом
    expect(GeoIp.regionFor('DE'), isNull);
    expect(GeoIp.regionFor(null), isNull);
  });

  group('настройки: регион «Авто» по IP', () {
    late ProviderContainer c;

    setUp(() {
      SharedPreferences.setMockInitialValues({'settings_migrated_v2': true});
      SettingsNotifier.detectDevice = () => RoutingRegion.russia; // часовой пояс «не Китай»
      c = ProviderContainer();
    });

    tearDown(() {
      c.dispose();
      SettingsNotifier.lookupCountry = GeoIp.countryCode;
    });

    Future<SettingsNotifier> ready() async {
      c.read(settingsProvider);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      return c.read(settingsProvider.notifier);
    }

    test('IP в Китае — «Авто» становится «Китай», хоть часовой пояс и не китайский', () async {
      SettingsNotifier.lookupCountry = () async => 'CN';
      final n = await ready();
      expect(c.read(settingsProvider).effectiveRegion, RoutingRegion.russia);
      await n.refreshGeo(canLookup: () => true);
      expect(c.read(settingsProvider).effectiveRegion, RoutingRegion.china);
    });

    test('туннель поднят (canLookup = false) — в сеть не ходим', () async {
      var calls = 0;
      SettingsNotifier.lookupCountry = () async {
        calls++;
        return 'CN';
      };
      final n = await ready();
      await n.refreshGeo(canLookup: () => false);
      expect(calls, 0);
      expect(c.read(settingsProvider).effectiveRegion, RoutingRegion.russia);
    });

    test('подключились, пока шёл запрос, — ответ выбрасываем (это страна сервера)', () async {
      var connected = false;
      SettingsNotifier.lookupCountry = () async {
        connected = true; // за время запроса пользователь подключился
        return 'CN';
      };
      final n = await ready();
      await n.refreshGeo(canLookup: () => !connected);
      expect(c.read(settingsProvider).effectiveRegion, RoutingRegion.russia);
    });

    test('не чаще раза в 6 часов, если не force', () async {
      var calls = 0;
      SettingsNotifier.lookupCountry = () async {
        calls++;
        return 'BY';
      };
      final n = await ready();
      await n.refreshGeo(canLookup: () => true);
      await n.refreshGeo(canLookup: () => true);
      expect(calls, 1);
      await n.refreshGeo(canLookup: () => true, force: true);
      expect(calls, 2);
    });
  });
}
