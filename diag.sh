#!/bin/bash
# Diagnostic de performance (lecture seule) : charge processeur de FL Studio, FL Shortcut et du système.
echo "== $(date '+%H:%M:%S') top (2 échantillons)"
top -l 2 -s 2 -o cpu -n 12 -stats pid,command,cpu,threads,mem 2>/dev/null | tail -14
echo "== processus concernés"
ps -Ao pid,%cpu,%mem,rss,comm | grep -i -E "FLShortcut|FL Studio|OsxFL|Image-Line|WindowServer|appstoreagent|mds" | grep -v grep
P=$(pgrep -x FLShortcut | head -1)
[ -n "$P" ] && { echo "== threads FL Shortcut"; sample "$P" 1 -mayDie 2>/dev/null | grep -E "^ +[0-9]+ Thread_|EventTap" | head -12; }
F=$(pgrep -x OsxFL | head -1)
if [ -n "$F" ]; then
  echo "== échantillon FL Studio ($F) 3 s : part du script Python FL Shortcut"
  sample "$F" 3 -mayDie > /tmp/fl_sample.txt 2>/dev/null
  echo "lignes totales : $(wc -l < /tmp/fl_sample.txt)"
  grep -i -E "python|PyEval|_PyEval|device_FLShortcut" /tmp/fl_sample.txt | head -15
  grep -E "^ +[0-9]+ Thread_" /tmp/fl_sample.txt | head -20
fi
