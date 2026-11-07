import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/core/theme/app_colors.dart';
import 'package:onyx/core/theme/app_theme.dart';
import 'package:onyx/core/theme/onyx_tokens.dart';
import 'package:onyx/core/theme/theme_kind.dart';
import 'package:onyx/presentation/providers/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('каждая тема несёт токены своего вида и выставляет AppColors', () {
    for (final k in AppThemeKind.values) {
      final theme = AppTheme.build(k);
      final t = theme.extension<OnyxTokens>()!;
      expect(t.kind, k);
      expect(AppColors.active.kind, k);
      expect(theme.colorScheme.brightness, Brightness.dark);
    }
  });

  test('Material берёт динамическую схему, если она есть', () {
    final dyn = ColorScheme.fromSeed(seedColor: Colors.green, brightness: Brightness.dark);
    final t = AppTheme.build(AppThemeKind.material, dynamicDark: dyn).extension<OnyxTokens>()!;
    expect(t.accent, dyn.primary);
  });

  test('выбор темы сохраняется', () async {
    SharedPreferences.setMockInitialValues({});
    final n = ThemeKindNotifier();
    await n.set(AppThemeKind.signal);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(ThemeKindNotifier.key), 'signal');
    expect(AppThemeKind.byName('nope'), AppThemeKind.onyx);
  });
}
