#!/bin/bash
# Итерация A2 (задача #32). k=1 — «линза» (основной), k=2 — «галька».
cd "$(dirname "$0")"; M=../mockups
for s in off ing on err list; do
  f="$M/a2-phone-$s.png"; SCALE=2 ./shot.sh mock.html "d=a2&s=$s&v=phone&k=1" 560 844 "$f" && convert "$f" -crop 780x1688+0+0 +repage "$f"
done
for s in off ing on; do
  f="$M/a2v2-phone-$s.png"; SCALE=2 ./shot.sh mock.html "d=a2&s=$s&v=phone&k=2" 560 844 "$f" && convert "$f" -crop 780x1688+0+0 +repage "$f"
done
for s in off on; do SCALE=2 ./shot.sh mock.html "d=a2&s=$s&v=desk&k=1" 1100 720 "$M/a2-desktop-$s.png"; done
convert $M/a2-phone-{off,ing,on,list}.png -bordercolor '#222' -border 2 +append -resize 50% $M/overview-a2-phone.png
convert $M/a2v2-phone-{off,ing,on}.png $M/a2-phone-err.png -bordercolor '#222' -border 2 +append -resize 50% $M/overview-a2-variant2-and-error.png
