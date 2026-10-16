#!/bin/bash
# Pilote de l'interface de FL Shortcut pour les essais sur le Mac, sans computer use (une app de la barre des menus,
# LSUIElement, n'y est pas proposée) : le mode capture de l'app (DebugSnapshot.swift, le même que la mesure de la CI)
# ouvre la fenêtre, change de page, ouvre le créateur, clique, redimensionne et photographie ses propres fenêtres.
# Usage : scripts/ui-pilote.sh <commande> [argument]
#   prepare            active le mode capture et relance l'app (la plus récente : /Applications, sinon ~/Applications)
#   open               ouvre la fenêtre principale
#   select <page>      general, transport, patterns, playlist, pianoRoll, channelRack, mixer, browser, custom, macros
#   search <texte>     recherche (texte vide : "" pour l'effacer)
#   macro open|close   créateur sur une macro d'exemple jamais enregistrée / retour aux raccourcis
#   click X,Y          vrai clic à X,Y (points depuis le coin haut-gauche de la fenêtre principale)
#   resize L,H         taille du contenu de la fenêtre principale (points)
#   snapshot <nom>     photo des fenêtres de l'app → ~/Library/Caches/app.flshortcut.FLShortcut/<nom>-<n>.png
#                      (+ <nom>-tailles.txt)
#   rapport            état exact de chaque fenêtre visible : cadre, écran, barre de titre, barre d'outils et ses
#                      éléments, boutons fermer / réduire / agrandir (visibles ou cachés, où)
#   fenetres           position et taille de chaque fenêtre de l'app, et des écrans
#   ecran <nom>        capture de tout l'écran → .essais/<nom>.png (barre de titre et boutons de la fenêtre compris)
#   fin                désactive le mode capture
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

DOMAIN="app.flshortcut.FLShortcut"
CACHE="$HOME/Library/Caches/app.flshortcut.FLShortcut"
OUT="$PWD/.essais"
mkdir -p "$OUT"
APP="/Applications/FL Shortcut.app"
[[ -d "$APP" ]] || APP="$HOME/Applications/FL Shortcut.app"

# Petit émetteur de notifications distribuées, compilé une fois.
POST="$OUT/fls_post"
if [[ ! -x "$POST" ]]; then
  cat > "$POST.swift" <<'SWIFT'
import Foundation
let args = CommandLine.arguments
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name(args[1]), object: args.count > 2 ? args[2] : nil, userInfo: nil, deliverImmediately: true)
SWIFT
  swiftc -O "$POST.swift" -o "$POST" 2>/dev/null || { echo "swiftc indisponible"; exit 1; }
fi

envoie() { "$POST" "app.flshortcut.debug.$1" ${2+"$2"}; }

cmd="${1:-}"; arg="${2-}"
case "$cmd" in
  prepare)
    defaults write "$DOMAIN" debugSnapshots -bool YES
    pkill -x FLShortcut 2>/dev/null; sleep 1
    open "$APP"; sleep 4
    echo "mode capture actif · app : $APP"
    ;;
  open) envoie open; sleep 2 ;;
  select) envoie select "$arg"; sleep 1 ;;
  search) envoie search "$arg"; sleep 1 ;;
  macro) envoie macro "$arg"; sleep 3 ;;
  click) envoie click "$arg"; sleep 1 ;;
  resize) envoie resize "$arg"; sleep 1 ;;
  snapshot)
    rm -f "$CACHE/$arg"-*.png
    envoie snapshot "$arg"; sleep 2
    ls "$CACHE/$arg"-*.png 2>/dev/null; cat "$CACHE/$arg-tailles.txt" 2>/dev/null; echo
    ;;
  rapport)
    envoie report; sleep 1
    cat "$CACHE/report.txt"
    ;;
  fenetres)
    osascript -e 'tell application "System Events" to tell (first process whose name is "FLShortcut") to get {name, position, size} of every window' 2>&1
    osascript -e 'tell application "Finder" to get bounds of window of desktop' 2>/dev/null
    system_profiler SPDisplaysDataType 2>/dev/null | grep -E "Resolution|Main Display" | sed 's/^ *//'
    ;;
  ecran) screencapture -x "$OUT/$arg.png" && echo "$OUT/$arg.png" ;;
  fin) defaults delete "$DOMAIN" debugSnapshots 2>/dev/null; echo "mode capture désactivé" ;;
  *) sed -n '2,20p' "$0"; exit 2 ;;
esac
