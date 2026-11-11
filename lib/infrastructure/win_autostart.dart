import 'dart:io';

import '../core/log_service.dart';

/// Автозапуск Onyx при входе в Windows (#58): значение в
/// `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` — без прав
/// администратора (onyx.exe больше не требует их при запуске, #55).
///
/// То же значение ставит и снимает установщик (галочка «Запускать Onyx при
/// входе в систему»), так что приложение и установщик не спорят. Старый
/// автозапуск — задачу планировщика с правами админа — убирает установщик.
class WinAutostart {
  WinAutostart({this.valueName = 'Onyx', String? exePath})
      : exePath = exePath ?? Platform.resolvedExecutable;

  /// Имя значения в Run (в тестах — своё, чтобы не трогать настоящее).
  final String valueName;
  final String exePath;

  static const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';

  /// Строка запуска: Onyx стартует сразу в трей.
  String get command => '"$exePath" --autostart';

  /// Включён ли автозапуск (есть значение в Run).
  Future<bool> isEnabled() async {
    if (!Platform.isWindows) return false;
    try {
      final r = await Process.run('reg', ['query', _runKey, '/v', valueName]);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Включить или выключить. true — получилось.
  Future<bool> setEnabled(bool on) async {
    if (!Platform.isWindows) return false;
    try {
      final r = on
          ? await Process.run('reg', ['add', _runKey, '/v', valueName, '/t', 'REG_SZ', '/d', command, '/f'])
          : await Process.run('reg', ['delete', _runKey, '/v', valueName, '/f']);
      // Удалять нечего — тоже «выключено».
      final ok = r.exitCode == 0 || (!on && !await isEnabled());
      log.i('Автозапуск ${on ? "включён" : "выключен"}: ${ok ? "ok" : "ошибка ${r.stderr}"}', tag: 'APP');
      return ok;
    } catch (e) {
      log.w('Автозапуск: $e', tag: 'APP');
      return false;
    }
  }

  /// Текущая строка запуска из реестра (для проверки и тестов).
  Future<String?> readCommand() async {
    if (!Platform.isWindows) return null;
    try {
      final r = await Process.run('reg', ['query', _runKey, '/v', valueName]);
      if (r.exitCode != 0) return null;
      final m = RegExp('$valueName\\s+REG_SZ\\s+(.+)').firstMatch('${r.stdout}');
      return m?.group(1)?.trim();
    } catch (_) {
      return null;
    }
  }
}
