#!/bin/bash
# M3 Expressive, каноничная версия (d=m3b): эталонные MaterialShapes + токены m3.material.io.
cd "$(dirname "$0")"; M=../mockups
ph(){ f="$M/$2.png"; SCALE=2 ./shot.sh mock.html "$1&v=phone" 560 844 "$f" && convert "$f" -crop 780x1688+0+0 +repage "$f"; }
dk(){ SCALE=2 ./shot.sh mock.html "$1" 1100 720 "$M/$2.png"; }
for s in off ing on err list; do ph "d=m3b&s=$s" "m3c-phone-$s"; done
for s in off on; do dk "d=m3b&s=$s&v=desk" "m3c-desktop-$s"; done
dk "d=m3b&s=off&v=det" details-m3c
SCALE=2 ./shot.sh mock.html "d=m3b&s=off&v=chk" 1100 920 "$M/m3c-checklist.png"
convert $M/m3c-phone-{off,ing,on,err,list}.png -bordercolor '#222' -border 2 +append -resize 50% $M/overview-m3c-phone.png
