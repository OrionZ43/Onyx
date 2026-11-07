#!/bin/bash
# Собирает .ico из PNG, сгенерированных generate_icons_test.dart (папка icons_out/).
# usage: pack_icons.sh <icons_out> <repo>
I="$1"; R="$2"
for st in off ing on err; do convert $I/tray_${st}_{16,20,24,32,48,64}.png "$R/assets/tray/tray_$st.ico"; done
convert $I/app_{16,24,32,48,64,128,256}.png "$R/windows/runner/resources/app_icon.ico"
