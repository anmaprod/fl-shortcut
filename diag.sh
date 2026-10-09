#!/bin/bash
sleep 4
P=$(pgrep -x FLShortcut | head -1)
echo "== processus : $(ps -o comm= -p $P)"
echo "== écoute clavier : $(sample "$P" 0.3 -mayDie 2>/dev/null | grep -q "FLShortcut.EventTap" && echo ACTIVE || echo inactive)"
echo "== FL au premier plan : $(lsappinfo info -only name "$(lsappinfo front)" 2>/dev/null | head -1)"
echo "== CPU sur 10 s"
top -l 10 -s 1 -stats pid,command,cpu 2>/dev/null | awk '$2=="FLShortcut"||$2=="OsxFL"{printf "%s %s  ", $2, $3} /^Processes/{print ""}' | tail -9
