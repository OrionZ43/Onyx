# Настройка Windows-сборки Onyx

## 1. UAC Elevation (права администратора)

Для работы WinTUN нужны права администратора.
В файле `windows/runner/CMakeLists.txt` добавь после `add_executable`:

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

## 2. Проверка установки WinTUN

WinTUN скачивается автоматически при первом запуске.
Если не работает — скачай вручную: https://www.wintun.net
и положи `wintun.dll` рядом с `sing-box.exe` в папке:
`%APPDATA%\Onyx\singbox\`

## 3. Sing-box версия

Используется sing-box v1.10.1 (amd64).
Скачивается автоматически с GitHub Releases.

## 4. Отладка

Все логи sing-box видны в консоли приложения (кнопка ⌨ в правом верхнем углу).
Конфиг записывается в: `%APPDATA%\Onyx\singbox\config.json`

## Build & Deploy Pipeline

1. **Build OnyxService**:
   `cd tools/onyx_service && dart compile exe bin/onyx_service.dart -o build/OnyxService.exe`
2. **Build OnyxUpdater**:
   `cd tools/onyx_updater && dart compile exe bin/onyx_updater.dart -o build/OnyxUpdater.exe`
3. **Build main app**:
   `flutter build windows --release`
4. **Build installer**:
   `cd tools/onyx_installer && flutter build windows --release`
5. **Package payload ZIP**:
   Zip together `build\windows\x64\runner\Release\*` + `tools\onyx_service\build\OnyxService.exe` + `tools\onyx_updater\build\OnyxUpdater.exe` → `Onyx_v0.1.0_payload.zip`
6. **Package installer**:
   Place `OnyxInstaller.exe` + `Onyx_v0.1.0_payload.zip` in same folder and distribute.
