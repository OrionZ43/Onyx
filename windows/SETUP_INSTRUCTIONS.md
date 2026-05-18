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
