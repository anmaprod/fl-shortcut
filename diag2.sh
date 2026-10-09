#!/bin/bash
# Comparaison A/B : charge de FL Studio avec puis sans FL Shortcut (l'app est relancée à la fin),
# et coût de FL Shortcut au repos (CPU, réveils par seconde).
m() { top -l 6 -s 1 -stats pid,command,cpu 2>/dev/null | awk '$2=="OsxFL"{print $3}' | tail -5 | tr '\n' ' '; }
me() { top -l 6 -s 1 -stats pid,command,cpu,idlew 2>/dev/null | awk '$2=="FLShortcut"{print $3"%/"$4"rév"}' | tail -5 | tr '\n' ' '; }
echo "FL au premier plan : $(osascript -e 'tell application "System Events" to get name of first process whose frontmost is true' 2>/dev/null)"
echo "FL Shortcut au repos (CPU / réveils) : $(me)"
echo "AVEC FL Shortcut   : OsxFL % CPU = $(m)"
pkill -x FLShortcut; sleep 3
echo "SANS FL Shortcut   : OsxFL % CPU = $(m)"
open "$HOME/Applications/FL Shortcut.app" 2>/dev/null || open "dist/FL Shortcut.app"
sleep 4
echo "AVEC (relancé)     : OsxFL % CPU = $(m)"
