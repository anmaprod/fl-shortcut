#!/bin/bash
APP="$HOME/Applications/FL Shortcut.app"
echo "== mesure (app arrêtée)"
pkill -x FLShortcut; sleep 1.5
"$APP/Contents/MacOS/FLShortcut" --mesure > /tmp/fls_mesure.txt 2>&1
tail -4 /tmp/fls_mesure.txt
open "$APP"; sleep 6
S="$HOME/Documents/Image-Line/FL Studio/Settings/Hardware/FL Shortcut/device_FLShortcut.py"
echo "== script installé dans FL : $(grep -c 'LOG_TO_OUTPUT = False' "$S" 2>/dev/null) (1 = nouvelle version)"
P=$(pgrep -x FLShortcut | head -1)
echo "== FL Shortcut pid $P"
sample "$P" 0.5 -mayDie 2>/dev/null | grep -E "^ +[0-9]+ Thread_" | sed 's/^ *[0-9]* //'
top -l 3 -s 1 -stats pid,command,cpu,idlew 2>/dev/null | awk '$2=="FLShortcut"||$2=="OsxFL"{print}' | tail -2
