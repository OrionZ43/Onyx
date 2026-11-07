# Скачивает ядро для Windows-сборки Onyx (CI windows-latest) и проверяет SHA-256.
#   pwsh tools/core/fetch-core.ps1 -Out dist\core
# Версия и хэши — как в lib/infrastructure/binary_manager.dart.
param([string]$Out = "dist\core")
$ErrorActionPreference = "Stop"

$V = "1.14.4"
$ShaSingbox = "99185d75d314a07dbba4a130c8ad986cbeb629a07927975636b341ca61f991df"
$ShaWintun = "07c256185d6ee3652e09fa55c0b673e2624b565e02c4b9091c79ca7d2f24ef51"

$base = if ($env:RUNNER_TEMP) { $env:RUNNER_TEMP } else { $env:TEMP }
$tmp = New-Item -ItemType Directory -Force -Path (Join-Path $base "onyx-core")
New-Item -ItemType Directory -Force -Path $Out | Out-Null

function Fetch($url, $sha, $file) {
  Invoke-WebRequest -Uri $url -OutFile $file -UseBasicParsing
  $got = (Get-FileHash $file -Algorithm SHA256).Hash.ToLower()
  if ($got -ne $sha) { throw "SHA-256 не совпал для $url ($got)" }
}

$sbZip = Join-Path $tmp "sing-box.zip"
Fetch "https://github.com/SagerNet/sing-box/releases/download/v$V/sing-box-$V-windows-amd64.zip" $ShaSingbox $sbZip
Expand-Archive $sbZip -DestinationPath $tmp -Force
Copy-Item (Join-Path $tmp "sing-box-$V-windows-amd64\sing-box.exe") $Out -Force

$wtZip = Join-Path $tmp "wintun.zip"
Fetch "https://www.wintun.net/builds/wintun-0.14.1.zip" $ShaWintun $wtZip
Expand-Archive $wtZip -DestinationPath $tmp -Force
Copy-Item (Join-Path $tmp "wintun\bin\amd64\wintun.dll") $Out -Force

Write-Host "OK: $Out (sing-box $V + wintun 0.14.1)"
