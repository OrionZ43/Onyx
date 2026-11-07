#!/usr/bin/env bash
# Скачивает ядро sing-box для сборок Onyx и проверяет SHA-256.
#
#   tools/core/fetch-core.sh android   → android/app/src/main/jniLibs/arm64-v8a/libsingbox.so
#   tools/core/fetch-core.sh windows   → dist/core/sing-box.exe + dist/core/wintun.dll
#                                        (папка core\ попадает в payload установщика)
#
# Версия и хэши должны совпадать с lib/infrastructure/binary_manager.dart.
# Бинарники в git не храним (Android-бинарник 1.14 весит ~80 МБ).
set -euo pipefail

V="1.14.4"
SHA_ANDROID_ARM64="fb3a6c5197f4044f82c8fd75e01ce14c28b6abdd4c3df84bb987d41a962a320f"
SHA_WINDOWS_AMD64="99185d75d314a07dbba4a130c8ad986cbeb629a07927975636b341ca61f991df"
SHA_WINTUN="07c256185d6ee3652e09fa55c0b673e2624b565e02c4b9091c79ca7d2f24ef51"

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fetch() { # url sha out
  curl -fsSL --retry 3 -o "$3" "$1"
  echo "$2  $3" | sha256sum -c --status || { echo "SHA-256 не совпал: $1" >&2; exit 1; }
}

case "${1:-}" in
  android)
    f="sing-box-$V-android-arm64.tar.gz"
    fetch "https://github.com/SagerNet/sing-box/releases/download/v$V/$f" "$SHA_ANDROID_ARM64" "$TMP/$f"
    tar -xzf "$TMP/$f" -C "$TMP"
    out="$ROOT/android/app/src/main/jniLibs/arm64-v8a"
    mkdir -p "$out"
    install -m 0755 "$TMP/sing-box-$V-android-arm64/sing-box" "$out/libsingbox.so"
    echo "OK: $out/libsingbox.so (sing-box $V)"
    ;;
  windows)
    f="sing-box-$V-windows-amd64.zip"
    fetch "https://github.com/SagerNet/sing-box/releases/download/v$V/$f" "$SHA_WINDOWS_AMD64" "$TMP/$f"
    fetch "https://www.wintun.net/builds/wintun-0.14.1.zip" "$SHA_WINTUN" "$TMP/wintun.zip"
    out="$ROOT/dist/core"
    mkdir -p "$out"
    (cd "$TMP" && unzip -q -o "$f" && unzip -q -o wintun.zip)
    cp "$TMP/sing-box-$V-windows-amd64/sing-box.exe" "$out/"
    cp "$TMP/wintun/bin/amd64/wintun.dll" "$out/"
    echo "OK: $out/{sing-box.exe,wintun.dll}"
    ;;
  *)
    echo "usage: $0 android|windows" >&2; exit 1 ;;
esac
