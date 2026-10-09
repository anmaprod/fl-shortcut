#!/bin/bash
pkill -x FLShortcut; sleep 1.5
open "$HOME/Applications/FL Shortcut.app"; sleep 6
P=$(pgrep -x FLShortcut | head -1)
echo "== FL Shortcut : $(ps -o comm= -p $P)"
sample "$P" 0.5 -mayDie 2>/dev/null > /tmp/fls_s.txt
echo "== threads"; grep -E "^ +[0-9]+ Thread_" /tmp/fls_s.txt | sed 's/^ *[0-9]* //'
echo "== CoreMIDI chargé : $(grep -c -i "CoreMIDI\|MIDIClient" /tmp/fls_s.txt) lignes"
echo "== ports MIDI « FL Shortcut » visibles :"; system_profiler SPMIDIDataType 2>/dev/null | grep -i -c "FL Shortcut"
echo "== CPU (8 s)"
top -l 8 -s 1 -stats pid,command,cpu 2>/dev/null | awk '$2=="FLShortcut"||$2=="OsxFL"{printf "%s %s  ", $2, $3} /^Processes/{print ""}' | tail -7
