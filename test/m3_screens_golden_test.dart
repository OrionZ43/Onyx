// Скриншоты темы Material 3 Expressive, которых нет у других тем: поиск,
// снекбар, раскадровка кнопки. Экраны M3 (главный, серверы, настройки,
// подписки, мини-панель…) снимает screens_golden_test.dart вместе с Onyx и
// Signal — файлы m3-*.
//
// Обновить: flutter test --update-goldens test/m3_screens_golden_test.dart
// PNG ложатся в test/goldens/m3-*.png и копируются в docs/redesign/screens/.
//
// Подмены (VPN, подписка, обновления), шрифты и съёмка — из
// screens_golden_test.dart, чтобы три темы снимались одинаково.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/core/theme/app_theme.dart';
import 'package:onyx/core/theme/theme_kind.dart';
import 'package:onyx/domain/entities/vpn_state.dart';
import 'package:onyx/presentation/m3/m3_server_list.dart';
import 'package:onyx/presentation/screens/home_screen.dart';
import 'package:onyx/presentation/widgets/hero/hero_state.dart';
import 'package:onyx/presentation/widgets/hero/m3_shape_button.dart';
import 'package:onyx/presentation/widgets/m3/m3_search.dart';
import 'package:onyx/presentation/widgets/m3/m3_snackbar.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens_golden_test.dart' show app, loadFonts, shot, vpnOf;

const AppThemeKind m3 = AppThemeKind.material;
const Size phone = Size(390, 844), desk = Size(1100, 720);

/// Тема читается из настроек: без этого ThemeKindNotifier в тесте
/// сбрасывается на Onyx (в приложении main.dart читает её до первого кадра).
const Map<String, Object> prefs = {'settings_theme_kind': 'material'};

/// Лист и поиск запускают пружины колбэком после кадра — нужна серия кадров.
Future<void> frames(WidgetTester tester, int ms) async {
  for (var t = 0; t < ms; t += 16) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues(prefs);
    await loadFonts();
  });

  testWidgets('m3 phone search', (tester) async {
    await shot(tester, 'm3-phone-search', app(m3, vpnOf('off'), const HomeScreen()), phone, then: () async {
      showM3ServerSheet(tester.element(find.byType(M3ShapeButton)));
      await frames(tester, 1200);
      await tester.tap(find.byType(M3SearchBar));
      await frames(tester, 800);
      await tester.enterText(find.byType(EditableText).last, 'амс');
      await frames(tester, 600);
    });
  });

  testWidgets('m3 phone switch', (tester) async {
    await shot(tester, 'm3-phone-switch', app(m3, vpnOf('on'), const HomeScreen()), phone, then: () async {
      tester.state<M3SnackbarHostState>(find.byType(M3SnackbarHost)).show('Переключились: Хельсинки HEL-02 → Амстердам AMS-03');
      await frames(tester, 800);
    });
  });

  // Раскадровка кнопки: покой, шесть кадров подключения через 325 мс
  // (полшага цикла LoadingIndicator), подключено, ошибка.
  testWidgets('m3 hero frames', (tester) async {
    tester.view.physicalSize = const Size(300, 300) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    Widget hero(HeroPhase p) => MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.build(m3),
          home: Scaffold(body: Center(child: M3ShapeButton(phase: p, size: 260, onTap: () {}))),
        );
    await tester.pumpWidget(hero(HeroPhase.off));
    await tester.pump(const Duration(seconds: 1));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/m3-hero-0-off.png'));
    await tester.pumpWidget(hero(HeroPhase.connecting));
    for (var i = 1; i <= 6; i++) {
      await tester.pump(const Duration(milliseconds: 325));
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/m3-hero-$i-ing.png'));
    }
    // Выход из цикла ждёт конца шага — нужны частые кадры, как на экране.
    await tester.pumpWidget(hero(HeroPhase.on));
    await frames(tester, 2000);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/m3-hero-7-on.png'));
    await tester.pumpWidget(hero(HeroPhase.error));
    await frames(tester, 2000);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/m3-hero-8-err.png'));
    await tester.pumpWidget(const SizedBox());
  });

  test('vpnOf покрывает все состояния кнопки', () {
    expect({for (final s in ['off', 'ing', 'on', 'err']) heroPhaseOf(vpnOf(s))}, HeroPhase.values.toSet());
    expect(vpnOf('on'), isA<VpnConnected>());
  });
}
