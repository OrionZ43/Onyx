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
| Права | `PrivilegesRequired=lowest`: файлы приложения — в `%LOCALAPPDATA%\Onyx` без UAC (там же жила v0.2.0). **onyx.exe работает без прав администратора (#55)** — UAC при запуске нет. |
| Ядро туннеля (#55) | WinTUN требует админа, поэтому туннель поднимает `onyx-core.exe` из `C:\Program Files\Onyx\core` (туда пишет только администратор; рядом `sing-box.exe` и `wintun.dll`). Его запускает задача `\Onyx\OnyxCore_<пользователь>`: по требованию, наивысшие права, SDDL — пользователю только чтение и запуск, менять задачу он не может. Приложение запускает и снимает её без UAC (`schtasks /Run`, флаг `core.stop`). `onyx-core` считает конфиг пользователя недоверенным: пересобирает его по белому списку (`lib/domain/core_config_sanitizer.dart` — без путей записи `log.output`, `cache_file`, `external_ui`, `services`, `*_path`), пишет в `C:\Program Files\Onyx\run` (журнал — пользователям только чтение), пути берёт от собственного расположения, а не из переменных окружения. Туннель гаснет по `core.stop`, когда закрылся `onyx.exe` (PID + проверка имени) и вместе с `onyx-core` (задание Windows). |
| UAC | Один повышенный шаг (PowerShell через `runas`, команда в `-EncodedCommand`), только если нужно: поставить или обновить ядро (SHA-256 файлов в Program Files ≠ установщику или задачи нет), убрать следы старых версий (v0.2.0, старый автозапуск с правами админа), закрыть старый Onyx, запущенный с правами админа. Новый Onyx, его ядро и пробы закрываются без прав. Обычное обновление приложения — без UAC. Предупреждение — на странице «Всё готово к установке». |
| Автозапуск (#58) | Значение `Onyx` в `HKCU\Software\Microsoft\Windows\CurrentVersion\Run` (`"<папка>\onyx.exe" --autostart`) — без прав; его же переключает приложение (`lib/infrastructure/win_autostart.dart`). Галочка в установщике выставляется по факту (значение есть или был старый автозапуск); тихое обновление его не трогает. Старая задача `\Onyx\Onyx Autostart` с наивысшими правами (запускала exe из папки пользователя от имени админа) удаляется. |
| Наследие v0.2.0 | Задача `OnyxVpnService` (от SYSTEM), запись `HKLM\…\Uninstall\Onyx` (64-битное представление реестра: сам Setup 32-битный, его PowerShell тоже — ключ удаляется через `RegistryKey.OpenBaseKey(…, Registry64)`), `OnyxService.exe`, `.bak` старого апдейтера, ярлыки `Onyx.lnk` (заменяются). |
| Ярлыки | `Пуск\Onyx` с `AppUserModelID=Onyx` (так его ищет `local_notifier` — уведомления Windows), рабочий стол — по галочке. |
| Языки | ru (по умолчанию), en, zh (`lang/ChineseSimplified.isl`, неофициальный перевод Inno 6.5+). Выбор — по языку Windows, диалог только если язык не из трёх. |
| Оформление | `docs/brand/installer/` («Оникс Дизайн», #52), цвета — токены темы Onyx. |
| Деинсталлятор | Закрывает Onyx и sing-box (с UAC, если запущены) — только свои: процессы из папки установки и старой папки v0.2.0, а sing-box из папки данных — если его родитель свой `onyx.exe` или уже завершён (брошенные пробы). Соседнюю сборку с той же папкой данных не трогает. Убирает автозапуск, ярлыки, файлы; спрашивает «Удалить данные?» — по умолчанию нет. Данные: `%APPDATA%\z43.studios\onyx`. |
| Обновление поверх | Постоянный AppId `{0E682CBC-A702-4780-AFEB-87FA0B615378}` — **никогда не менять**. Папка и выбор задач запоминаются. |

## Сборка

```powershell
# 1. приложение + апдейтер + ядро в одну папку (то же, что payload)
flutter build windows --release --dart-define=APP_VERSION=0.3.0
dart compile exe tools\onyx_updater\bin\onyx_updater.dart -o build\OnyxUpdater.exe
# ...скопировать build\windows\x64\runner\Release\* и OnyxUpdater.exe в dist\
pwsh tools\core\fetch-core.ps1 -Out dist\core
# запускатель ядра с правами админа (#55) — в core\ рядом с sing-box
cd tools\onyx_core; dart pub get; cd ..\..
dart compile exe tools\onyx_core\bin\onyx_core.dart -o dist\core\onyx-core.exe
# #69: оконная подсистема — задача ядра не открывает окно консоли (иначе на
# Windows 11 при подключении всплывает Терминал, а закрыть его = уронить туннель)
dart run tool\pe_subsystem.dart --gui dist\core\onyx-core.exe
# 2. установщик
pwsh tools\installer\build-installer.ps1 -SourceDir dist -Version 0.3.0
```

В CI (`.github/workflows/release.yml`) это делает шаг «Build Installer (Inno Setup)»: в релиз уходят `OnyxSetup_<tag>.exe`, стабильное `onyx-setup-windows.exe` и, как раньше, `Onyx_<tag>_payload.zip` для встроенного апдейтера.

## Проверка без риска для установленного Onyx

Ключ `/ONYXTEST=1`: повышенный шаг не выполняется (PowerShell-команда пишется в журнал), ярлыки не создаются, при удалении данные не стираются. Тестовая установка регистрируется отдельно — «Onyx VPN (test)» (AppId + `.test`, ключ `HKCU\Software\Z43 Studios\Onyx (test)`) — и не трогает регистрацию настоящей. Её деинсталлятор узнаёт себя по метке `onyxtest.flag` в папке, даже если запустить его без ключа.

```powershell
OnyxSetup.exe /VERYSILENT /ONYXTEST=1 /DIR="%TEMP%\onyx-test" /LOG="%TEMP%\onyx-setup.log"
"%TEMP%\onyx-test\unins000.exe" /VERYSILENT /SUPPRESSMSGBOXES /ONYXTEST=1 /LOG="%TEMP%\onyx-uninstall.log"
```

Полезные ключи Inno: `/LANG=ru|en|zh`, `/TASKS="desktopicon,autostart"`, `/DIR=…`, `/SILENT`, `/VERYSILENT`, `/LOG=…`.

Без `/SUPPRESSMSGBOXES` тихий деинсталлятор всё равно покажет вопрос «Удалить также данные Onyx?» и будет ждать ответа.
