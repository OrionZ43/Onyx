# Собирает установщик Onyx (Inno Setup 6.7+) из готовой папки приложения.
#
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\installer\build-installer.ps1 `
#       -SourceDir dist -Version 0.3.0 [-OutputDir build\installer] [-OutputName OnyxSetup_v0.3.0]
#
# SourceDir — сборка приложения (onyx.exe, *.dll, data\) и core\ (sing-box.exe +
# wintun.dll — tools\core\fetch-core.ps1; onyx-core.exe — dart compile exe
# tools\onyx_core\bin\onyx_core.dart, #55). OnyxService.exe от старых сборок,
# если лежит в SourceDir, в установщик не попадает.
param(
  [Parameter(Mandatory = $true)][string]$SourceDir,
  [Parameter(Mandatory = $true)][string]$Version,
  [string]$OutputDir = "build\installer",
  [string]$OutputName = "",
  [string]$IsccPath = ""
)
$ErrorActionPreference = "Stop"
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
if (-not $OutputName) { $OutputName = "OnyxSetup_v$Version" }
$SourceDir = (Resolve-Path $SourceDir).Path
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
$OutputDir = (Resolve-Path $OutputDir).Path

if (-not $IsccPath) {
  $candidates = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
  )
  $IsccPath = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
}
if (-not $IsccPath) { throw "Inno Setup 6 (ISCC.exe) не найден. Установите: choco install innosetup" }

foreach ($f in @("onyx.exe", "core\sing-box.exe", "core\wintun.dll", "core\onyx-core.exe")) {
  if (-not (Test-Path (Join-Path $SourceDir $f))) { throw "В $SourceDir нет $f" }
}

Write-Host "ISCC: $IsccPath"
& $IsccPath /Qp "/DAppVersion=$Version" "/DSourceDir=$SourceDir" "/DOutputDir=$OutputDir" "/DOutputName=$OutputName" (Join-Path $root "tools\installer\onyx.iss")
if ($LASTEXITCODE -ne 0) { throw "ISCC завершился с кодом $LASTEXITCODE" }
$exe = Join-Path $OutputDir "$OutputName.exe"
Write-Host ("OK: {0} ({1:N1} МБ)" -f $exe, ((Get-Item $exe).Length / 1MB))
