#!/bin/bash
# Attend (4 min max) FL ouvert + écoute clavier active, puis mesure.
APP="$HOME/Applications/FL Shortcuts.app"
tap=0; fl=0
for i in $(seq 1 80); do
  P=$(pgrep -x FLShortcut | head -1)
  [ -n "$P" ] && sample "$P" 0.2 -mayDie 2>/dev/null | grep -q "FLShortcut.EventTap" && tap=1
  pgrep -x OsxFL >/dev/null && fl=1
  [ $tap = 1 ] && [ $fl = 1 ] && break
  sleep 3
done
echo "écoute clavier : $([ $tap = 1 ] && echo ACTIVE || echo inactive) · FL : $([ $fl = 1 ] && echo ouvert || echo fermé)"
if [ $fl = 1 ]; then
  sleep 12      # laisse FL finir de charger
  pkill -x FLShortcut; sleep 1.5
  "$APP/Contents/MacOS/FLShortcut" --mesure > /tmp/fls_mesure.txt 2>&1
  tail -3 /tmp/fls_mesure.txt
  open "$APP"; sleep 5
  P=$(pgrep -x FLShortcut | head -1)
  sample "$P" 0.3 -mayDie 2>/dev/null | grep -q "FLShortcut.EventTap" && echo "écoute clavier après relance : ACTIVE" || echo "écoute clavier après relance : inactive"
  top -l 4 -s 1 -stats pid,command,cpu 2>/dev/null | awk '$2=="FLShortcut"||$2=="OsxFL"{print}' | tail -2
fi
