# Настройка Windows-сборки Onyx

## 1. Права администратора (#55)

onyx.exe собирается с `asInvoker` — UAC при запуске нет. WinTUN требует прав
администратора: туннель поднимает `onyx-core.exe` из `C:\Program Files\Onyx\core`
через задачу планировщика `\Onyx\OnyxCore_<пользователь>` (её регистрирует
установщик, `tools/installer`). Запущенный «от имени администратора» Onyx
поднимает sing-box сам, как раньше.

Старый способ (требовать права при каждом запуске) — больше НЕ использовать:

```cmake
# UAC elevation manifest
set_target_properties(${BINARY_NAME} PROPERTIES
  LINK_FLAGS "/MANIFESTUAC:\"level='requireAdministrator' uiAccess='false'\""
)
```

Или вручную добавь в `windows/runner/Runner.rc`:
```rc
CREATEPROCESS_MANIFEST_RESOURCE_ID RT_MANIFEST "onyx.exe.manifest"
```

## 2. sing-box и WinTUN

sing-box (версия — `BinaryManager.singboxVersion`, сейчас 1.14.4, amd64) и
`wintun.dll` лежат в установщике (`core\`, `tools/core/fetch-core.ps1`) — из
интернета при установке и первом запуске ничего не качается. Только сборка без
`core\` рядом с onyx.exe скачивает их с GitHub (с зеркалами и проверкой SHA-256).

## 3. Отладка

Журнал приложения — «Диагностика» → «Журнал». Конфиг и рабочие файлы
sing-box — в `%APPDATA%\z43.studios\onyx\singbox\`; журнал ядра, запущенного
задачей (#55), — `C:\Program Files\Onyx\run\sing-box.log`.

## Сборка и выпуск

Подробно — `tools/installer/README.md`; в CI то же делает `.github/workflows/release.yml`.

1. Приложение: `flutter build windows --release --dart-define=APP_VERSION=<версия>`,
   содержимое `build\windows\x64\runner\Release\` — в `dist\`.
2. Ядро: `pwsh tools\core\fetch-core.ps1 -Out dist\core` и
   `dart compile exe tools\onyx_core\bin\onyx_core.dart -o dist\core\onyx-core.exe`.
3. Установщик: `pwsh tools\installer\build-installer.ps1 -SourceDir dist -Version <версия>`
   → `OnyxSetup_v<версия>.exe`.

Обновление из приложения (#54) качает `OnyxSetup_<tag>.exe` из последнего релиза,
сверяет SHA-256 и запускает его тихо (`/VERYSILENT … /ONYXUPDATE=1`).
Старые OnyxService, OnyxUpdater, onyx_installer и `Onyx_<tag>_payload.zip` больше
не собираются.