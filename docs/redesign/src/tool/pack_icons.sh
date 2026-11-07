#!/bin/bash
# Раскладывает PNG из generate_icons_test.dart (папка icons_out/) по проекту.
# usage: pack_icons.sh <icons_out> <repo>
set -e
I="$1"; R="$2"
# Windows: иконка exe/окна/панели задач — 16…256.
convert $I/app_{16,20,24,32,40,48,64,96,128,256}.png "$R/windows/runner/resources/app_icon.ico"
# Трей: моно-силуэт V1 в 4 состояниях.
for st in off ing on err; do convert $I/tray_${st}_{16,20,24,32,48,64}.png "$R/assets/tray/tray_$st.ico"; done
# Android: legacy-иконка, adaptive foreground и monochrome по плотностям.
A="$R/android/app/src/main/res"
declare -A L=( [mdpi]=48 [hdpi]=72 [xhdpi]=96 [xxhdpi]=144 [xxxhdpi]=192 )
declare -A F=( [mdpi]=108 [hdpi]=162 [xhdpi]=216 [xxhdpi]=324 [xxxhdpi]=432 )
for d in mdpi hdpi xhdpi xxhdpi xxxhdpi; do
  convert $I/app_1024.png -filter Lanczos -resize ${L[$d]}x${L[$d]} "$A/mipmap-$d/ic_launcher.png"
  convert $I/android_fg.png -filter Lanczos -resize ${F[$d]}x${F[$d]} "$A/mipmap-$d/ic_launcher_foreground.png"
  convert $I/android_mono.png -filter Lanczos -resize ${F[$d]}x${F[$d]} "$A/mipmap-$d/ic_launcher_monochrome.png"
done
mkdir -p "$A/drawable-nodpi"; cp $I/splash_fox.png "$A/drawable-nodpi/splash_fox.png"
# Фирменные файлы: favicon и крупные PNG знака.
mkdir -p "$R/docs/brand"
convert $I/app_{16,32,48}.png "$R/docs/brand/favicon.ico"
cp $I/app_1024.png "$R/docs/brand/onyx-app-icon-1024.png"
cp $I/onyx_fox_1024.png "$R/docs/brand/onyx-fox-1024.png"
cp $I/onyx_fox_dots_512.png "$R/docs/brand/onyx-fox-signal-512.png"
