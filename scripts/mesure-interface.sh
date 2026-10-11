#!/bin/bash
# Mesure de l'interface sur un vrai macOS (CI GitHub, ou ton Mac) : mémoire (empreinte physique) et processeur
# de FL Shortcut, barre des menus seule puis fenêtre ouverte, avec et sans l'effet Liquid Glass.
# Usage : scripts/mesure-interface.sh "dist/FL Shortcut.app" dossier-de-sortie
# Résultat : tableau Markdown sur la sortie standard, captures d'écran dans le dossier de sortie.
# Ne touche à rien d'autre que les préférences de FL Shortcut (restaurées à la fin).
set -uo pipefail

APP="${1:-dist/FL Shortcut.app}"
OUT="${2:-dist/mesure}"
DOMAIN="app.flshortcut.FLShortcut"
mkdir -p "$OUT"

POST="$(mktemp -d)/fls_post"
cat > "$POST.swift" <<'SWIFT'
import Foundation
let args = CommandLine.arguments
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name(args[1]), object: args.count > 2 ? args[2] : nil, userInfo: nil, deliverImmediately: true)
SWIFT
swiftc -O "$POST.swift" -o "$POST" 2>/dev/null || { echo "swiftc indisponible"; exit 1; }

had_snap=$(defaults read "$DOMAIN" debugSnapshots 2>/dev/null || echo "")
had_glass=$(defaults read "$DOMAIN" liquidGlass 2>/dev/null || echo "")
had_onb=$(defaults read "$DOMAIN" didOnboard 2>/dev/null || echo "")
defaults write "$DOMAIN" debugSnapshots -bool YES
defaults write "$DOMAIN" didOnboard -bool YES

mem_mb() {   # empreinte physique (ce que le Moniteur d'activité appelle « Mémoire »)
  local p=$1 v
  v=$(footprint "$p" 2>/dev/null | awk -F': *' '/[Pp]hys_footprint:/{print $2; exit}')
  [[ -n "$v" ]] && { echo "$v"; return; }
  echo "$(( $(ps -o rss= -p "$p") / 1024 )) MB (RSS)"
}

cpu_avg() {  # moyenne du processeur sur 8 s, au repos
  local p=$1
  top -l 9 -s 1 -pid "$p" -stats pid,cpu 2>/dev/null \
    | awk -v p="$p" '$1==p {n++; if (n>1) {s+=$2; c++}} END{if (c) printf "%.1f %%", s/c; else print "?"}'
}

run() {   # $1 : libellé, $2 : YES/NO effet verre
  local label=$1 glass=$2 p
  pkill -x FLShortcut 2>/dev/null; sleep 1
  defaults write "$DOMAIN" liquidGlass -bool "$glass"
  open "$APP"; sleep 6
  p=$(pgrep -x FLShortcut | head -1)
  [[ -z "$p" ]] && { echo "| $label | ne démarre pas | | | |"; return; }
  local m0 c0 m1 c1
  m0=$(mem_mb "$p"); c0=$(cpu_avg "$p")
  "$POST" app.flshortcut.debug.open; sleep 5
  "$POST" app.flshortcut.debug.select general; sleep 2
  screencapture -x "$OUT/$label.png" 2>/dev/null || true
  # Rendu interne de la fenêtre (toute sa hauteur, même si l'écran de test est petit).
  rm -f "$HOME/Library/Caches/$DOMAIN/$label-"*
  "$POST" app.flshortcut.debug.snapshot "$label-fenetre"; sleep 2
  cp "$HOME/Library/Caches/$DOMAIN/$label-fenetre-"* "$OUT/" 2>/dev/null || true
  cat "$HOME/Library/Caches/$DOMAIN/$label-fenetre-tailles.txt" >&2 2>/dev/null || true
  echo "fenêtres : $(osascript -e 'tell application "System Events" to get size of every window of (first process whose name is "FLShortcut")' 2>/dev/null)" >&2
  m1=$(mem_mb "$p"); c1=$(cpu_avg "$p")
  echo "| $label | $m0 | $c0 | $m1 | $c1 |"
}

echo "| Effet | Mémoire (barre des menus) | Processeur | Mémoire (fenêtre ouverte) | Processeur (fenêtre ouverte, au repos) |"
echo "|---|---|---|---|---|"
run "verre" YES
run "sans-verre" NO
pkill -x FLShortcut 2>/dev/null

restore() { if [[ -n "$2" ]]; then defaults write "$DOMAIN" "$1" -bool "$2"; else defaults delete "$DOMAIN" "$1" 2>/dev/null; fi; }
restore debugSnapshots "$had_snap"; restore liquidGlass "$had_glass"; restore didOnboard "$had_onb"
echo
echo "macOS $(sw_vers -productVersion), $(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
