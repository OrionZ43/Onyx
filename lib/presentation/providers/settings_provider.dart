import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsState {
  const SettingsState({this.smartRouting = true});
  final bool smartRouting;

  SettingsState copyWith({bool? smartRouting}) =>
      SettingsState(smartRouting: smartRouting ?? this.smartRouting);
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier() : super(const SettingsState()) {
    _load();
  }

  static const _keySmartRouting = 'settings_smart_routing';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final smartRouting = prefs.getBool(_keySmartRouting) ?? true;
    state = state.copyWith(smartRouting: smartRouting);
  }

  Future<void> toggleSmartRouting(bool value) async {
    state = state.copyWith(smartRouting: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySmartRouting, value);
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>(
  (ref) => SettingsNotifier(),
);
