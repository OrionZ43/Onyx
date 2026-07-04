import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsState {
  const SettingsState({
    this.smartRouting = true,
    this.aiDirectLane = true,
    this.splitTunnelingEnabled = false,
    this.excludedApps = const <String>{},
    this.autoFailover = true,
  });

  final bool smartRouting;

  /// AI Direct Lane: домены ИИ-сервисов всегда идут строго через туннель,
  /// а их DNS резолвится только через зашифрованный remote-DNS внутри
  /// туннеля. Исключает "Access Denied" из-за утечки DNS/гео.
  /// Работает на обеих платформах.
  final bool aiDirectLane;

  /// Split tunneling (только Android): приложения из [excludedApps]
  /// работают в обход VPN через VpnService.addDisallowedApplication.
  final bool splitTunnelingEnabled;

  /// Package name'ы приложений, исключённых из туннеля.
  final Set<String> excludedApps;

  /// Автопереключение при деградации: если активный сервер начал подвисать
  /// (пинг улетел, uplink захлёбывается) или отвалился — приложение само
  /// перейдёт на лучшую рабочую ноду с уведомлением. Выключи, если не
  /// хочешь, чтобы соединение рвалось без спроса (например, в звонке
  /// секундный разрыв нежелателен).
  final bool autoFailover;

  SettingsState copyWith({
    bool? smartRouting,
    bool? aiDirectLane,
    bool? splitTunnelingEnabled,
    Set<String>? excludedApps,
    bool? autoFailover,
  }) =>
      SettingsState(
        smartRouting: smartRouting ?? this.smartRouting,
        aiDirectLane: aiDirectLane ?? this.aiDirectLane,
        splitTunnelingEnabled:
            splitTunnelingEnabled ?? this.splitTunnelingEnabled,
        excludedApps: excludedApps ?? this.excludedApps,
        autoFailover: autoFailover ?? this.autoFailover,
      );
}

class SettingsNotifier extends StateNotifier<SettingsState> {
  SettingsNotifier() : super(const SettingsState()) {
    _load();
  }

  static const _keySmartRouting = 'settings_smart_routing';
  static const _keyAiDirectLane = 'settings_ai_direct_lane';
  static const _keySplitTunneling = 'settings_split_tunneling';
  static const _keyExcludedApps = 'settings_excluded_apps';
  static const _keyAutoFailover = 'settings_auto_failover';

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    state = state.copyWith(
      smartRouting: prefs.getBool(_keySmartRouting) ?? true,
      aiDirectLane: prefs.getBool(_keyAiDirectLane) ?? true,
      splitTunnelingEnabled: prefs.getBool(_keySplitTunneling) ?? false,
      excludedApps:
          (prefs.getStringList(_keyExcludedApps) ?? const []).toSet(),
      autoFailover: prefs.getBool(_keyAutoFailover) ?? true,
    );
  }

  Future<void> toggleSmartRouting(bool value) async {
    state = state.copyWith(smartRouting: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySmartRouting, value);
  }

  Future<void> toggleAiDirectLane(bool value) async {
    state = state.copyWith(aiDirectLane: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAiDirectLane, value);
  }

  Future<void> toggleSplitTunneling(bool value) async {
    state = state.copyWith(splitTunnelingEnabled: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySplitTunneling, value);
  }

  Future<void> toggleAutoFailover(bool value) async {
    state = state.copyWith(autoFailover: value);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyAutoFailover, value);
  }

  Future<void> setAppExcluded(String packageName, bool excluded) async {
    final updated = Set<String>.from(state.excludedApps);
    if (excluded) {
      updated.add(packageName);
    } else {
      updated.remove(packageName);
    }
    state = state.copyWith(excludedApps: updated);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_keyExcludedApps, updated.toList()..sort());
  }
}

final settingsProvider = StateNotifierProvider<SettingsNotifier, SettingsState>(
      (ref) => SettingsNotifier(),
);
