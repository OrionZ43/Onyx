#!/bin/bash
# Задача #33: доведённый Signal (c2), Material 3 Expressive (m3), листы деталей, Onyx с флагами.
cd "$(dirname "$0")"; M=../mockups
ph(){ f="$M/$2.png"; SCALE=2 ./shot.sh mock.html "$1&v=phone" 560 844 "$f" && convert "$f" -crop 780x1688+0+0 +repage "$f"; }
dk(){ SCALE=2 ./shot.sh mock.html "$1" 1100 720 "$M/$2.png"; }
for d in ${DIRS:-c2 m3}; do
  for s in off ing on err list; do ph "d=$d&s=$s" "$d-phone-$s"; done
  for s in off on; do dk "d=$d&s=$s&v=desk" "$d-desktop-$s"; done
  convert $M/$d-phone-{off,ing,on,err,list}.png -bordercolor '#222' -border 2 +append -resize 50% $M/overview-$d-phone.png
done
if [ -z "$DIRS" ]; then
  for d in a2 c2 m3; do dk "d=$d&s=off&v=det" "details-$d"; done
  ph "d=a2&s=list&flags=1" a2-phone-list-flags; ph "d=a2&s=on&flags=1" a2-phone-on-flags
fi
