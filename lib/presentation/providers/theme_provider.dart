import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme/theme_kind.dart';

/// Выбранная тема оформления; хранится в SharedPreferences.
class ThemeKindNotifier extends StateNotifier<AppThemeKind> {
  ThemeKindNotifier([super.state = AppThemeKind.onyx]) {
    _load();
  }

  static const key = 'settings_theme_kind';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final saved = AppThemeKind.byName(prefs.getString(key));
    if (saved != state) state = saved;
  }

  Future<void> set(AppThemeKind kind) async {
    if (kind == state) return;
    state = kind;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, kind.name);
  }
}

final themeKindProvider =
    StateNotifierProvider<ThemeKindNotifier, AppThemeKind>(
  (ref) => ThemeKindNotifier(),
);
