#!/bin/bash
# Рендер всех мокапов в ../mockups/ (2x). Запуск из docs/redesign/src.
# Окно Edge не бывает уже ~500px, поэтому телефон рендерим в 560px и обрезаем до 390.
cd "$(dirname "$0")"
for d in ${DIRS:-a b c}; do for s in ${SCREENS:-off on list}; do
  f="../mockups/$d-phone-$s.png"
  SCALE=2 ./shot.sh mock.html "d=$d&s=$s&v=phone" 560 844 "$f" && convert "$f" -crop 780x1688+0+0 +repage "$f"
  SCALE=2 ./shot.sh mock.html "d=$d&s=$s&v=desk" 1100 720 "../mockups/$d-desktop-$s.png"
done; done
