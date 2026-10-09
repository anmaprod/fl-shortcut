#!/bin/bash
# Comparaison A/B : charge de FL Studio avec puis sans FL Shortcut (l'app est relancée à la fin).
m() { top -l 4 -s 1 -stats pid,command,cpu 2>/dev/null | awk '$2=="OsxFL"{print $3}' | tail -3 | tr '\n' ' '; }
echo "AVEC FL Shortcut   : OsxFL % CPU = $(m)"
pkill -x FLShortcut; sleep 3
echo "SANS FL Shortcut   : OsxFL % CPU = $(m)"
open "$HOME/Applications/FL Shortcut.app" 2>/dev/null || open "dist/FL Shortcut.app"
sleep 3
echo "AVEC (relancé)     : OsxFL % CPU = $(m)"
