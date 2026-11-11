import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../infrastructure/win_autostart.dart';

/// Переключатель «Запускать Onyx при входе в систему» (#58, Windows).
///
/// Состояние: null — ещё читаем реестр (или не Windows: переключатель не
/// показывать), true/false — включён ли автозапуск. Без прав администратора:
/// значение в HKCU\...\Run, то же, что ставит установщик.
class AutostartNotifier extends StateNotifier<bool?> {
  AutostartNotifier([WinAutostart? impl])
      : _impl = impl ?? WinAutostart(),
        super(null) {
    if (Platform.isWindows) _load();
  }

  final WinAutostart _impl;

  Future<void> _load() async {
    final on = await _impl.isEnabled();
    if (mounted) state = on;
  }

  /// Включить/выключить. Сразу показываем выбор, при ошибке — возвращаем
  /// фактическое состояние из реестра.
  Future<void> set(bool on) async {
    if (!Platform.isWindows) return;
    state = on;
    final ok = await _impl.setEnabled(on);
    if (!ok && mounted) state = await _impl.isEnabled();
  }
}

final autostartProvider = StateNotifierProvider<AutostartNotifier, bool?>(
  (ref) => AutostartNotifier(),
);
