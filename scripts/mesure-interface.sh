#!/bin/bash
# Mesure de l'interface sur un vrai macOS (CI GitHub, ou ton Mac) : mémoire (empreinte physique) et processeur
# de FL Shortcut, barre des menus seule puis fenêtre ouverte, page Macros, créateur de macros ouvert (sur une macro
# d'exemple jamais enregistrée) puis refermé (3 cycles, avec le nombre de modèles du créateur encore vivants après
# chaque fermeture), avec et sans l'effet Liquid Glass ; puis la recherche « e » sur une app relancée avec les pages
# en List au lieu du Form groupé (clé debugPagesAsList), pour savoir d'où vient la mémoire de la recherche.
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
had_list=$(defaults read "$DOMAIN" debugPagesAsList 2>/dev/null || echo "")
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

restore() { if [[ -n "$2" ]]; then defaults write "$DOMAIN" "$1" -bool "$2"; else defaults delete "$DOMAIN" "$1" 2>/dev/null; fi; }

report() {   # $1 : nom du fichier gardé dans $OUT ; rapport de l'app (affiché dans le journal), nombre de modèles du créateur vivants
  local f="$HOME/Library/Caches/$DOMAIN/report.txt" r
  rm -f "$f"
  "$POST" app.flshortcut.debug.report; sleep 1
  r=$(cat "$f" 2>/dev/null || echo "editorModels=? windows=?")
  cp "$f" "$OUT/$1-report.txt" 2>/dev/null || true
  echo "rapport $1 : $r" >&2
  echo "$r" | sed -n 's/.*editorModels=\([0-9?]*\).*/\1/p'
}

run() {   # $1 : libellé, $2 : YES/NO effet verre
  local label=$1 glass=$2 p
  pkill -x FLShortcut 2>/dev/null; sleep 1
  defaults write "$DOMAIN" liquidGlass -bool "$glass"
  open "$APP"; sleep 6
  p=$(pgrep -x FLShortcut | head -1)
  [[ -z "$p" ]] && { echo "| $label | ne démarre pas | | | | | |"; return; }
  local m0 c0 m1 c1
  m0=$(mem_mb "$p"); c0=$(cpu_avg "$p")
  "$POST" app.flshortcut.debug.open; sleep 5
  "$POST" app.flshortcut.debug.select general; sleep 1
  "$POST" app.flshortcut.debug.resize "960,640"; sleep 2
  screencapture -x "$OUT/$label.png" 2>/dev/null || true
  # Rendu interne de la fenêtre (toute sa hauteur, même si l'écran de test est petit).
  rm -f "$HOME/Library/Caches/$DOMAIN/$label-"*
  "$POST" app.flshortcut.debug.snapshot "$label-fenetre"; sleep 2
  cp "$HOME/Library/Caches/$DOMAIN/$label-fenetre-"* "$OUT/" 2>/dev/null || true
  cat "$HOME/Library/Caches/$DOMAIN/$label-fenetre-tailles.txt" >&2 2>/dev/null || true
  echo "fenêtres : $(osascript -e 'tell application "System Events" to get size of every window of (first process whose name is "FLShortcut")' 2>/dev/null)" >&2
  m1=$(mem_mb "$p"); c1=$(cpu_avg "$p")
  # Créateur de macros : page Macros, puis la fenêtre du créateur ouverte sur un exemple (jamais enregistré),
  # mesurée au repos, photographiée, puis fermée (la mémoire doit revenir).
  "$POST" app.flshortcut.debug.select macros; sleep 2
  rm -f "$HOME/Library/Caches/$DOMAIN/$label-macros-"*
  "$POST" app.flshortcut.debug.snapshot "$label-macros"; sleep 2
  cp "$HOME/Library/Caches/$DOMAIN/$label-macros-"*.png "$OUT/" 2>/dev/null || true
  mb=$(mem_mb "$p")
  "$POST" app.flshortcut.debug.macro open; sleep 5
  screencapture -x "$OUT/$label-createur.png" 2>/dev/null || true
  rm -f "$HOME/Library/Caches/$DOMAIN/$label-createur-"*
  "$POST" app.flshortcut.debug.snapshot "$label-createur"; sleep 2
  cp "$HOME/Library/Caches/$DOMAIN/$label-createur-"*.png "$OUT/" 2>/dev/null || true
  mc=$(mem_mb "$p"); cc=$(cpu_avg "$p")
  "$POST" app.flshortcut.debug.macro close; sleep 4
  md=$(mem_mb "$p")
  # Deux autres cycles (ouvrir, mesurer, fermer, attendre 3 s, mesurer) : la mémoire refermée doit rester au même
  # niveau. Le rapport de l'app dit combien de modèles du créateur vivent encore après chaque fermeture.
  local n
  local -a co cf nm
  nm[1]=$(report "$label-cycle1")
  for n in 2 3; do
    "$POST" app.flshortcut.debug.macro open; sleep 5
    co[$n]=$(mem_mb "$p")
    "$POST" app.flshortcut.debug.macro close; sleep 3
    cf[$n]=$(mem_mb "$p")
    nm[$n]=$(report "$label-cycle$n")
  done
  # Plus grosse page, puis une recherche qui affiche presque toutes les lignes : la mémoire doit rester stable.
  "$POST" app.flshortcut.debug.select mixer; sleep 3
  m2=$(mem_mb "$p")
  "$POST" app.flshortcut.debug.search e; sleep 4
  m3=$(mem_mb "$p")
  "$POST" app.flshortcut.debug.search ""; sleep 1
  # Même recherche sur une app neuve, pages en List (paresseuse) et sans créateur : si la mémoire tombe, c'est le
  # Form groupé (non paresseux) qui la coûtait.
  pkill -x FLShortcut 2>/dev/null; sleep 1
  defaults write "$DOMAIN" debugPagesAsList -bool YES
  open "$APP"; sleep 6
  local ml="?"
  p=$(pgrep -x FLShortcut | head -1)
  if [[ -n "$p" ]]; then
    "$POST" app.flshortcut.debug.open; sleep 5
    "$POST" app.flshortcut.debug.select general; sleep 1
    "$POST" app.flshortcut.debug.resize "960,640"; sleep 2
    "$POST" app.flshortcut.debug.select mixer; sleep 3
    "$POST" app.flshortcut.debug.search e; sleep 4
    ml=$(mem_mb "$p")
    "$POST" app.flshortcut.debug.search ""; sleep 1
  fi
  restore debugPagesAsList "$had_list"
  echo "| $label | $m0 | $c0 | $m1 | $c1 | $mb | $mc | $cc | $md | $m2 | $m3 | ${co[2]} | ${cf[2]} | ${co[3]} | ${cf[3]} | ${nm[1]} / ${nm[2]} / ${nm[3]} | $ml |"
}

echo "| Effet | Mémoire (barre des menus) | Processeur | Mémoire (fenêtre ouverte) | Processeur (fenêtre ouverte, au repos) | Mémoire (page Macros) | Mémoire (créateur ouvert) | Processeur (créateur ouvert, au repos) | Mémoire (créateur refermé) | Mémoire (page Mixer) | Mémoire (recherche « e », presque tout) | Mémoire (créateur cycle 2 ouvert) | Mémoire (créateur cycle 2 refermé) | Mémoire (créateur cycle 3 ouvert) | Mémoire (créateur cycle 3 refermé) | Modèles du créateur vivants après fermeture (cycles 1 / 2 / 3) | Mémoire (recherche « e » en List) |"
echo "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"
run "verre" YES
run "sans-verre" NO
pkill -x FLShortcut 2>/dev/null

restore debugSnapshots "$had_snap"; restore liquidGlass "$had_glass"; restore didOnboard "$had_onb"; restore debugPagesAsList "$had_list"
echo
echo "macOS $(sw_vers -productVersion), $(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
