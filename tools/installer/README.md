# Установщик Onyx для Windows (Inno Setup)

Один файл `OnyxSetup_v<версия>.exe`: приложение, ядро sing-box и драйвер WinTUN внутри — из интернета при установке ничего не качается (важно для Китая). Сделано в #51 вместо самописного Flutter-распаковщика `tools/onyx_installer` (одна кнопка, только английский, без деинсталлятора).

## Почему Inno Setup

- Готовы из коробки: деинсталлятор, запись в «Программы и компоненты», обновление поверх по постоянному AppId, тихий режим (`/VERYSILENT`), журнал установки, многоязычность, сжатие LZMA2 (установщик 32,6 МБ против 61 МБ zip-бандла).
- Inno Setup 6.7 умеет тёмный мастер (`WizardStyle=modern dark`), свой цвет фона и PNG с прозрачностью — без дефолтного серого вида.
- Pascal Script позволяет точечно попросить права администратора только для нужного шага.
- Тот же подход, что в Protogenix: per-user, постоянный AppId.

## Устройство

| Что | Как |
|---|---|
| Права | `PrivilegesRequired=lowest`: файлы в `%LOCALAPPDATA%\Onyx` без UAC (там же жила v0.2.0). |
| UAC | Один повышенный шаг (PowerShell через `runas`, команда в `-EncodedCommand`), только если нужно: закрыть запущенный Onyx (он работает с правами админа), убрать следы v0.2.0, включить или выключить автозапуск. Без этих условий UAC нет совсем. Предупреждение — на странице «Всё готово к установке». |
| Автозапуск | Задача планировщика `\Onyx\Onyx Autostart` «при входе пользователя», наивысшие права: ключ `Run` не запускает программы, которым нужен админ. Аргумент `--autostart`. |
| Наследие v0.2.0 | Задача `OnyxVpnService` (от SYSTEM), запись `HKLM\…\Uninstall\Onyx`, `OnyxService.exe`, `.bak` старого апдейтера, ярлыки `Onyx.lnk` (заменяются). |
| Ярлыки | `Пуск\Onyx` с `AppUserModelID=Onyx` (так его ищет `local_notifier` — уведомления Windows), рабочий стол — по галочке. |
| Языки | ru (по умолчанию), en, zh (`lang/ChineseSimplified.isl`, неофициальный перевод Inno 6.5+). Выбор — по языку Windows, диалог только если язык не из трёх. |
| Оформление | `docs/brand/installer/` («Оникс Дизайн», #52), цвета — токены темы Onyx. |
| Деинсталлятор | Закрывает Onyx и sing-box (с UAC, если запущены), убирает автозапуск, ярлыки, файлы; спрашивает «Удалить данные?» — по умолчанию нет. Данные: `%APPDATA%\z43.studios\onyx`. |
| Обновление поверх | Постоянный AppId `{0E682CBC-A702-4780-AFEB-87FA0B615378}` — **никогда не менять**. Папка и выбор задач запоминаются. |

## Сборка

```powershell
# 1. приложение + апдейтер + ядро в одну папку (то же, что payload)
flutter build windows --release --dart-define=APP_VERSION=0.3.0
dart compile exe tools\onyx_updater\bin\onyx_updater.dart -o build\OnyxUpdater.exe
# ...скопировать build\windows\x64\runner\Release\* и OnyxUpdater.exe в dist\
pwsh tools\core\fetch-core.ps1 -Out dist\core
# 2. установщик
pwsh tools\installer\build-installer.ps1 -SourceDir dist -Version 0.3.0
```

В CI (`.github/workflows/release.yml`) это делает шаг «Build Installer (Inno Setup)»: в релиз уходят `OnyxSetup_<tag>.exe`, стабильное `onyx-setup-windows.exe` и, как раньше, `Onyx_<tag>_payload.zip` для встроенного апдейтера.

## Проверка без риска для установленного Onyx

Ключ `/ONYXTEST=1`: повышенный шаг не выполняется (PowerShell-команда пишется в журнал), ярлыки не создаются, при удалении данные не стираются.

```powershell
OnyxSetup.exe /VERYSILENT /ONYXTEST=1 /DIR="%TEMP%\onyx-test" /LOG="%TEMP%\onyx-setup.log"
"%TEMP%\onyx-test\unins000.exe" /VERYSILENT /ONYXTEST=1 /LOG="%TEMP%\onyx-uninstall.log"
```

Полезные ключи Inno: `/LANG=ru|en|zh`, `/TASKS="desktopicon,autostart"`, `/DIR=…`, `/SILENT`, `/VERYSILENT`, `/LOG=…`.
