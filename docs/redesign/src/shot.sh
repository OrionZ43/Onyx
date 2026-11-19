#!/bin/bash
# usage: shot.sh <html> <hash> <w> <h> <out.png>   — рендер через headless Edge (Windows) из WSL
EDGE="/mnt/c/Program Files (x86)/Microsoft/Edge/Application/msedge.exe"
WP=$(wslpath -w "$(realpath "$1")"); WP="${WP//\\//}"
OUTDIR=$(realpath "$(dirname "$5")"); OUT="$(wslpath -w "$OUTDIR")\\$(basename "$5")"
timeout 90 "$EDGE" --headless=new --disable-gpu --hide-scrollbars --allow-file-access-from-files \
  --force-device-scale-factor=${SCALE:-1} --virtual-time-budget=4000 \
  --user-data-dir='C:\Windows\Temp\onyxmock' --window-size=$3,$4 \
  --screenshot="$OUT" "file:${WP}#$2" >/dev/null 2>&1
