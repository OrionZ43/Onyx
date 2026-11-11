import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:onyx/infrastructure/win_autostart.dart';

/// #58: автозапуск через HKCU\...\Run без прав. Своё имя значения — не
/// трогаем настоящий автозапуск пользователя.
void main() {
  final a = WinAutostart(valueName: 'OnyxTest58', exePath: r'C:\Users\U\AppData\Local\Onyx\onyx.exe');

  test('строка запуска: путь в кавычках и --autostart', () {
    expect(a.command, r'"C:\Users\U\AppData\Local\Onyx\onyx.exe" --autostart');
  });

  test('включить → есть в Run с нужной строкой; выключить → нет', () async {
    try {
      expect(await a.setEnabled(true), isTrue);
      expect(await a.isEnabled(), isTrue);
      expect(await a.readCommand(), a.command);
      expect(await a.setEnabled(false), isTrue);
      expect(await a.isEnabled(), isFalse);
      // Выключить уже выключенное — не ошибка.
      expect(await a.setEnabled(false), isTrue);
    } finally {
      await a.setEnabled(false);
    }
  }, skip: !Platform.isWindows);
}
