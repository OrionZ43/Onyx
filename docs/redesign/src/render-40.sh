#!/bin/bash
# #40: источники и группы, тема Onyx.
cd "$(dirname "$0")"; M=../mockups
for s in sources groups add grpedit; do f="$M/a2-sources-$s.png"; SCALE=2 ./shot.sh mock.html "d=a2s&s=$s&v=phone" 560 844 "$f" && convert "$f" -crop 780x1688+0+0 +repage "$f"; done
convert $M/a2-sources-{sources,groups,add,grpedit}.png -bordercolor '#222' -border 2 +append -resize 50% $M/overview-a2-sources.png
