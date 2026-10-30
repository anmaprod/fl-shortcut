#!/bin/bash
# Mesure de l'interface sur un vrai macOS (CI GitHub, ou ton Mac) : mémoire (empreinte physique) et processeur
# de FL Shortcuts, barre des menus seule puis fenêtre ouverte, page Macros, créateur de macros ouvert (sur une macro
# d'exemple jamais enregistrée) puis refermé (3 cycles, avec le nombre de modèles du créateur vivants avant la
# première ouverture, témoin à 0, puis après chaque fermeture), page Mixer et recherche « e », avec et sans l'effet
# Liquid Glass. Détail de l'empreinte par catégorie (footprint) avant le créateur, créateur ouvert, refermé, recherche.
# Usage : scripts/mesure-interface.sh "dist/FL Shortcuts.app" dossier-de-sortie
# Résultat : tableau Markdown sur la sortie standard, captures d'écran dans le dossier de sortie.
# Ne touche à rien d'autre que les préférences de FL Shortcuts (restaurées à la fin).
set -uo pipefail

APP="${1:-dist/FL Shortcuts.app}"
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

# Vrai glisser-déposer à la souris, envoyé par ce script (le shell de la CI a le droit d'envoyer des événements ;
# l'app, elle, ne l'a pas) : DRAG x1 y1 x2 y2, points de l'écran (origine en haut à gauche, comme CGEvent).
DRAG="$(dirname "$POST")/fls_drag"
cat > "$DRAG.swift" <<'SWIFT'
import CoreGraphics
import Foundation
let n = CommandLine.arguments.dropFirst().compactMap { Double($0) }
guard n.count == 4 else { print("usage : fls_drag x1 y1 x2 y2 [vite]"); exit(2) }
// « vite » : comme une vraie main (25/10, « le drag and drop ne fonctionne pas » chez le propriétaire alors que
// l'essai lent passait) : la souris part aussitôt l'appui fait, sans pause, et lâche dès l'arrivée.
let quick = CommandLine.arguments.last == "vite"
let start = CGPoint(x: n[0], y: n[1])
let end = CGPoint(x: n[2], y: n[3])
func post(_ type: CGEventType, _ p: CGPoint) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}
post(.mouseMoved, start); usleep(quick ? 60_000 : 200_000)
post(.leftMouseDown, start); usleep(quick ? 8_000 : 300_000)
let steps = quick ? 12 : 30
for i in 1...steps {
    let t = Double(i) / Double(steps)
    post(.leftMouseDragged, CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t))
    usleep(quick ? 16_000 : 25_000)
}
usleep(quick ? 120_000 : 500_000)
post(.leftMouseUp, end)
print("glisser\(quick ? " vite" : "") (\(Int(start.x)),\(Int(start.y))) → (\(Int(end.x)),\(Int(end.y))) · envoi \(CGPreflightPostEventAccess() ? "autorisé" : "REFUSÉ")")
SWIFT
swiftc -O "$DRAG.swift" -o "$DRAG" 2>/dev/null || echo "fls_drag : compilation impossible" >&2

# Vrai clic à la souris (essai de la barre de recherche) : CLICK x y, points de l'écran (origine en haut à gauche).
CLICK="$(dirname "$POST")/fls_click"
cat > "$CLICK.swift" <<'SWIFT'
import CoreGraphics
import Foundation
let n = CommandLine.arguments.dropFirst().compactMap { Double($0) }
guard n.count == 2 else { print("usage : fls_click x y"); exit(2) }
let p = CGPoint(x: n[0], y: n[1])
func post(_ type: CGEventType) {
    CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: p, mouseButton: .left)?.post(tap: .cghidEventTap)
}
post(.mouseMoved); usleep(150_000)
post(.leftMouseDown); usleep(80_000)
post(.leftMouseUp)
SWIFT
swiftc -O "$CLICK.swift" -o "$CLICK" 2>/dev/null || echo "fls_click : compilation impossible" >&2

# Souris posée sans clic (survol des lignes) : MOVE x y, points de l'écran (origine en haut à gauche).
MOVE="$(dirname "$POST")/fls_move"
cat > "$MOVE.swift" <<'SWIFT'
import CoreGraphics
import Foundation
let n = CommandLine.arguments.dropFirst().compactMap { Double($0) }
guard n.count == 2 else { print("usage : fls_move x y"); exit(2) }
for dx in [-12.0, -6.0, 0.0] {          // la souris arrive sur la ligne, comme une vraie
    CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: CGPoint(x: n[0] + dx, y: n[1]),
            mouseButton: .left)?.post(tap: .cghidEventTap)
    usleep(60_000)
}
SWIFT
swiftc -O "$MOVE.swift" -o "$MOVE" 2>/dev/null || echo "fls_move : compilation impossible" >&2

had_snap=$(defaults read "$DOMAIN" debugSnapshots 2>/dev/null || echo "")
had_glass=$(defaults read "$DOMAIN" liquidGlass 2>/dev/null || echo "")
had_onb=$(defaults read "$DOMAIN" didOnboard 2>/dev/null || echo "")
had_guide=$(defaults read "$DOMAIN" guideSeen 2>/dev/null || echo "")
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

categories() {   # $1 pid, $2 nom du fichier : détail de l'empreinte par catégorie (malloc, IOSurface, __DATA…)
  footprint "$1" > "$OUT/$2-footprint.txt" 2>&1 || true
}

restore() { if [[ -n "$2" ]]; then defaults write "$DOMAIN" "$1" -bool "$2"; else defaults delete "$DOMAIN" "$1" 2>/dev/null; fi; }

report() {   # $1 : nom du fichier gardé dans $OUT ; rapport de l'app (affiché dans le journal), nombre de modèles du créateur vivants
  local f="$HOME/Library/Caches/$DOMAIN/report.txt" r
  rm -f "$f"
  "$POST" app.flshortcut.debug.report; sleep 1
  r=$(cat "$f" 2>/dev/null || echo "editorModels=? windows=? visible=?")
  cp "$f" "$OUT/$1-report.txt" 2>/dev/null || true
  echo "rapport $1 : $r" >&2
  echo "$r" | sed -n 's/.*editorModels=\([0-9?]*\).*/\1/p'
}

fits() {   # $1 : rapport gardé ; les colonnes de la fenêtre principale tiennent-elles dans sa hauteur ?
  local f="$OUT/$1-report.txt" h c
  h=$(sed -nE 's/^  contenu \(-?[0-9]+,-?[0-9]+ [0-9]+[^0-9]+([0-9]+)\).*/\1/p' "$f" 2>/dev/null | tail -1)
  c=$(sed -nE 's/^  colonnes \(-?[0-9]+,(-?[0-9]+) [0-9]+[^0-9]+([0-9]+)\).*/\1 \2/p' "$f" 2>/dev/null | head -1)
  [[ -z "$h" || -z "$c" ]] && { echo "?"; return; }
  set -- $c
  if (( $1 >= 0 && $1 + $2 <= h )); then echo "oui"; else echo "NON ($2 pt pour $h)"; fi
}

origin() {   # $1 : rapport gardé ; « x y » du coin haut-gauche de la fenêtre de l'app sur l'écran (origine en haut)
  local f="$OUT/$1-report.txt" sh pos
  sh=$(sed -nE 's/^écran 0: frame \(-?[0-9]+,-?[0-9]+ [0-9]+[^0-9]+([0-9]+)\).*/\1/p' "$f" 2>/dev/null | head -1)
  pos=$(grep -A1 '^fenêtre AppKitWindow' "$f" 2>/dev/null \
    | sed -nE 's/^  cadre \((-?[0-9]+),(-?[0-9]+) [0-9]+[^0-9]+([0-9]+)\).*/\1 \2 \3/p' | head -1)
  [[ -z "$sh" || -z "$pos" ]] && return 1
  set -- $pos
  echo "$1 $(( sh - $2 - $3 ))"
}

drag() {   # $1 : rapport gardé (position de la fenêtre) ; $2..$5 : x1 y1 x2 y2 dans la fenêtre (depuis son coin haut-gauche) ; $6 : « vite »
  local ox oy
  read -r ox oy < <(origin "$1") || { echo "glisser : position de la fenêtre inconnue" >&2; return; }
  "$DRAG" $(( ox + $2 )) $(( oy + $3 )) $(( ox + $4 )) $(( oy + $5 )) ${6:-} >&2
}

rows() {   # $1 : rapport gardé ; lignes de la liste des blocs du créateur (la plus large des listes)
  sed -nE 's/^  liste \(-?[0-9]+,-?[0-9]+ ([0-9]+)[^0-9]+[0-9]+\) · ([0-9]+) lignes.*/\1 \2/p' "$OUT/$1-report.txt" 2>/dev/null \
    | sort -n | tail -1 | awk '{print $2}'
}

order() {   # $1 : rapport gardé ; ordre des blocs du créateur (genres seulement)
  sed -n 's/^créateur : //p' "$OUT/$1-report.txt" 2>/dev/null | head -1
}

# Essai de la barre de recherche à vrais clics (retour du propriétaire : elle reste active après un clic ailleurs,
# dans l'app comme dehors) : après chaque clic, qui a la main dans la fenêtre (rapport de l'app) et une photo.
# Résultat : $OUT/recherche-essai.txt (+ recherche-<étape>.png).
search_step() {   # $1 : étape ; $2 $3 : point du clic (écran, origine en haut à gauche) ou rien
  local f="$OUT/recherche-essai.txt"
  if [[ -n "${2:-}" ]]; then "$CLICK" "$2" "$3"; fi
  sleep 1.2
  report "recherche-$1" >/dev/null
  screencapture -x "$OUT/recherche-$1.png" 2>/dev/null || true
  { echo "== $1${2:+ (clic $2,$3)}"
    grep -E '^fenêtre AppKitWindow|^  (recherche|répondant|garde) :|clé : ' "$OUT/recherche-$1-report.txt" 2>/dev/null \
      | grep -A99 '^fenêtre AppKitWindow' | grep -E '^  (recherche|répondant|garde) :|clé : '
  } >> "$f"
}

search_test() {   # $1 : rapport gardé (position de la fenêtre)
  local ox oy sx sy f="$OUT/recherche-essai.txt"
  : > "$f"
  read -r ox oy < <(origin "$1") || { echo "recherche : position de la fenêtre inconnue" >> "$f"; return; }
  # Le premier champ reconnu par la garde (le 25/10, la première ligne était la garde elle-même, qui couvre toute la
  # fenêtre : le clic tombait au milieu de la page).
  read -r sx sy < <(sed -nE 's/^  recherche : .*\[champ .* centre-cg (-?[0-9]+) (-?[0-9]+).*/\1 \2/p' "$OUT/$1-report.txt" | head -1)
  if [[ -z "${sx:-}" ]]; then
    read -r sx sy < <(grep -v 'SearchFocusGuard' "$OUT/$1-report.txt" \
      | sed -nE 's/^  recherche : [A-Za-z_]*Search[A-Za-z_]* .*écran .* centre-cg (-?[0-9]+) (-?[0-9]+).*/\1 \2/p' | head -1)
  fi
  echo "fenêtre en $ox,$oy · recherche en ${sx:-?},${sy:-?}" >> "$f"
  [[ -z "${sx:-}" ]] && { echo "recherche introuvable dans le rapport" >> "$f"; return; }
  search_step 0-depart
  search_step 1-clic-dedans "$sx" "$sy"
  search_step 2-barre-de-titre $(( ox + 520 )) $(( oy + 26 ))
  search_step 3-clic-dedans "$sx" "$sy"
  search_step 4-en-tete-de-page $(( ox + 600 )) $(( oy + 140 ))
  search_step 5-clic-dedans "$sx" "$sy"
  search_step 6-bureau 20 400
  search_step 7-retour-barre-de-titre $(( ox + 520 )) $(( oy + 26 ))
  search_step 8-clic-dedans "$sx" "$sy"
  search_step 9-ligne-de-la-barre-laterale $(( ox + 120 )) $(( oy + 330 ))
  cat "$f" >&2
  # Survol (demande du 25/10) : sur la page Mixer, la 1re ligne puis « Playlist » dans la barre latérale ; le contour
  # est de la couleur, rien de gris ne le dépasse, les couleurs de la ligne ne changent pas.
  "$MOVE" $(( ox + 560 )) $(( oy + 267 )); sleep 1.2
  screencapture -x "$OUT/survol-ligne.png" 2>/dev/null || true
  "$MOVE" $(( ox + 90 )) $(( oy + 229 )); sleep 1.2
  screencapture -x "$OUT/survol-barre-laterale.png" 2>/dev/null || true
  "$MOVE" 20 400
}

# En-tête de la page (maquette du 28/10) : le bouton Mon compte (capsule en haut à droite, sous la barre de titre de
# 52 points qui ne laisse passer aucun clic) répond à un vrai clic en haut (y 62) et au milieu (y 78). Fenêtre de 960
# points : centre du bouton à 960 − 8 − 26 − 3 − 22 = 901. Résultat : $OUT/entete-essai.txt (titre de la fenêtre après chaque clic) + photos.
header_test() {   # $1 : rapport gardé (position de la fenêtre)
  local ox oy y f="$OUT/entete-essai.txt"
  : > "$f"
  read -r ox oy < <(origin "$1") || { echo "en-tête : position de la fenêtre inconnue" >> "$f"; return; }
  for y in 62 78; do
    "$POST" app.flshortcut.debug.select general; sleep 1.5
    "$CLICK" $(( ox + 901 )) $(( oy + y )) >/dev/null 2>&1; sleep 1.5
    report "entete-$y" >/dev/null
    screencapture -x "$OUT/entete-$y.png" 2>/dev/null || true
    echo "clic sur Mon compte à y $y : $(grep -m1 '^fenêtre AppKitWindow' "$OUT/entete-$y-report.txt" 2>/dev/null)" >> "$f"
  done
  "$MOVE" 20 400
}

run() {   # $1 : libellé, $2 : YES/NO effet verre
  local label=$1 glass=$2 p
  pkill -x FLShortcut 2>/dev/null; sleep 1
  defaults write "$DOMAIN" liquidGlass -bool "$glass"
  open "$APP"; sleep 6
  p=$(pgrep -x FLShortcut | head -1)
  [[ -z "$p" ]] && { echo "| $label | ne démarre pas | | | | | |"; return; }
  local m0 c0 m1 c1 fit drop moved
  m0=$(mem_mb "$p"); c0=$(cpu_avg "$p")
  "$POST" app.flshortcut.debug.open; sleep 5
  "$POST" app.flshortcut.debug.select general; sleep 1
  "$POST" app.flshortcut.debug.resize "960,640"; sleep 2
  screencapture -x "$OUT/$label.png" 2>/dev/null || true
  # État exact de la fenêtre au moment de la photo (cadre, barre de titre, boutons, listes défilées ou non).
  report "$label-fenetre" >/dev/null
  fit="$(fits "$label-fenetre")"
  if [[ "$label" == verre ]]; then
    search_test "$label-fenetre"
    "$POST" app.flshortcut.debug.search ""; "$POST" app.flshortcut.debug.select general; sleep 2
    header_test "$label-fenetre"
    "$POST" app.flshortcut.debug.select general; sleep 2
  fi
  # Rendu interne de la fenêtre (toute sa hauteur, même si l'écran de test est petit).
  rm -f "$HOME/Library/Caches/$DOMAIN/$label-"*
  "$POST" app.flshortcut.debug.snapshot "$label-fenetre"; sleep 2
  cp "$HOME/Library/Caches/$DOMAIN/$label-fenetre-"* "$OUT/" 2>/dev/null || true
  cat "$HOME/Library/Caches/$DOMAIN/$label-fenetre-tailles.txt" >&2 2>/dev/null || true
  echo "fenêtres : $(osascript -e 'tell application "System Events" to get size of every window of (first process whose name is "FLShortcut")' 2>/dev/null)" >&2
  m1=$(mem_mb "$p"); c1=$(cpu_avg "$p")
  # Même fenêtre, 10 s plus tard (après la capture interne et la question Accessibilité ci-dessus), et ce que fait
  # l'app pendant 3 s : le processeur au repos doit retomber à 0.
  sleep 10
  c1b=$(cpu_avg "$p")
  sample "$p" 3 -file "$OUT/$label-fenetre-sample.txt" >/dev/null 2>&1 || true
  # Créateur de macros : page Macros, puis la fenêtre du créateur ouverte sur un exemple (jamais enregistré),
  # mesurée au repos, photographiée, puis fermée (la mémoire doit revenir).
  "$POST" app.flshortcut.debug.select macros; sleep 2
  # Vraie photo de la page Macros (flèches, « + » : à la même place que dans le créateur ?).
  screencapture -x "$OUT/$label-macros-ecran.png" 2>/dev/null || true
  report "$label-macros" >/dev/null
  fit+=" / $(fits "$label-macros")"
  rm -f "$HOME/Library/Caches/$DOMAIN/$label-macros-"*
  "$POST" app.flshortcut.debug.snapshot "$label-macros"; sleep 2
  cp "$HOME/Library/Caches/$DOMAIN/$label-macros-"*.png "$OUT/" 2>/dev/null || true
  # Page Macros remplie (maquette du 30/10) : macros d'exemple en mémoire, jamais enregistrées ; puis la vraie remise.
  if [[ "$label" == verre ]]; then
    "$POST" app.flshortcut.debug.macros exemples; sleep 2
    screencapture -x "$OUT/macros-exemples.png" 2>/dev/null || true
    "$POST" app.flshortcut.debug.macros vide; sleep 2
  fi
  mb=$(mem_mb "$p")
  # Page Communauté, avec des exemples et sans réseau : chaque écran photographié (une seule fois, avec le verre).
  if [[ "$label" == verre ]]; then
    "$POST" app.flshortcut.debug.select community; sleep 2
    for screen in connexion inscription liste vide detail partager signaler membres auteur; do
      "$POST" app.flshortcut.debug.community "$screen"; sleep 3
      screencapture -x "$OUT/communaute-$screen.png" 2>/dev/null || true
    done
    "$POST" app.flshortcut.debug.community liste; sleep 2
    # Guide de l'appli, page par page.
    for n in 0 1 2 3 4; do
      "$POST" app.flshortcut.debug.guide "$n"; sleep 2
      screencapture -x "$OUT/guide-$n.png" 2>/dev/null || true
    done
    # « Bienvenue » → première partie au ralenti (10 fois plus lent) : le morph photographié en cours de route.
    "$POST" app.flshortcut.debug.guide 0; sleep 2
    "$POST" app.flshortcut.debug.guide "1 lent"
    for i in 1 2 3 4 5 6; do
      sleep 0.7; screencapture -x "$OUT/guide-morph-$i.png" 2>/dev/null || true
    done
    sleep 4
    report guide-morph >/dev/null
    "$POST" app.flshortcut.debug.guide fin; sleep 2
    # Menu de l'icône (fond noir plein, 29/10) : ouvert par l'app comme un clic sur son icône, photographié, refermé.
    "$POST" app.flshortcut.debug.menu ouvrir; sleep 2
    screencapture -x "$OUT/menu-icone.png" 2>/dev/null || true
    "$POST" app.flshortcut.debug.menu fermer; sleep 1
    # Accueil au ralenti : ouverture (écran du clavier), clavier autorisé, puis passage au guide dans la même fenêtre.
    "$POST" app.flshortcut.debug.onboarding "clavier lent"
    for i in 1 2 3 4; do
      sleep 0.8; screencapture -x "$OUT/accueil-ouverture-$i.png" 2>/dev/null || true
    done
    sleep 4
    "$POST" app.flshortcut.debug.onboarding autorise; sleep 5
    screencapture -x "$OUT/accueil-clavier-ok.png" 2>/dev/null || true
    "$POST" app.flshortcut.debug.onboarding "guide lent"
    for i in 1 2 3 4 5 6; do
      sleep 0.7; screencapture -x "$OUT/accueil-guide-$i.png" 2>/dev/null || true
    done
    sleep 5
    screencapture -x "$OUT/accueil-guide.png" 2>/dev/null || true
    "$POST" app.flshortcut.debug.onboarding "partie 2 lent"
    for i in 1 2 3 4; do
      sleep 0.9; screencapture -x "$OUT/accueil-partie-$i.png" 2>/dev/null || true
    done
    sleep 4
    "$POST" app.flshortcut.debug.onboarding fin; sleep 2
    # Page Aide : questions fréquentes, recherche, « Écrire à l'équipe », message envoyé.
    "$POST" app.flshortcut.debug.select aide; sleep 2
    for screen in aide recherche ecrire envoye; do
      "$POST" app.flshortcut.debug.help "$screen"; sleep 3
      screencapture -x "$OUT/aide-$screen.png" 2>/dev/null || true
    done
    # Page Mon compte (sauvegarde en ligne), avec des exemples et sans réseau.
    "$POST" app.flshortcut.debug.select compte; sleep 2
    for screen in connexion inscription code oubli connecte profil attente choix; do
      "$POST" app.flshortcut.debug.account "$screen"; sleep 3
      screencapture -x "$OUT/compte-$screen.png" 2>/dev/null || true
    done
    # Fenêtre de désinstallation en 3 étapes, avec des exemples : rien n'est demandé ni supprimé.
    for screen in confirmer compte fini reste; do
      "$POST" app.flshortcut.debug.uninstall "$screen"; sleep 3
      screencapture -x "$OUT/desinstaller-$screen.png" 2>/dev/null || true
    done
    "$POST" app.flshortcut.debug.uninstall fermer; sleep 1
    # Organiser, avec des sons d'exemple (sans FL) : chaque écran, puis le passage de l'un à l'autre.
    for screen in tuto installer attente aide ecoute apercu fini; do
      "$POST" app.flshortcut.debug.organizer "$screen"
      # L'aperçu figeait l'app une quinzaine de secondes (photos restées sur l'écoute) : où l'app passe son temps.
      if [[ "$screen" == apercu ]]; then
        (sample FLShortcut 4 -file "$OUT/organiser-apercu-sample.txt" >/dev/null 2>&1 &)
      fi
      sleep 3
      screencapture -x "$OUT/organiser-$screen.png" 2>/dev/null || true
      if [[ "$screen" == apercu ]]; then
        sleep 12
        screencapture -x "$OUT/organiser-apercu-tard.png" 2>/dev/null || true
      fi
      # Pendant l'écoute : la carte « Organiser · 3 sons sur 8 » en haut du menu de l'icône (maquette du 28/10).
      if [[ "$screen" == ecoute ]]; then
        "$POST" app.flshortcut.debug.menu ouvrir; sleep 2
        screencapture -x "$OUT/menu-icone-organiser.png" 2>/dev/null || true
        "$POST" app.flshortcut.debug.menu fermer; sleep 1
      fi
      # L'app a-t-elle redémarré (plantage relancé) pendant cet écran ? (« apercu » et « fini » restaient sur l'écoute)
      echo "organiser $screen : pid $(pgrep -x FLShortcut | tr '\n' ' ')" >> "$OUT/organiser-pid.txt"
    done
    cp ~/Library/Logs/DiagnosticReports/FLShortcut*.ips "$OUT/" 2>/dev/null || true
    tail -40 ~/Library/Logs/"FL Shortcuts"/macro.log > "$OUT/organiser-journal.txt" 2>/dev/null || true
    "$POST" app.flshortcut.debug.organizer fermer; sleep 1
    # Question « Tu gardes la version organisée ? » (après l'Organiser), avec un exemple : aucun fichier touché.
    for screen in question travail erreur; do
      "$POST" app.flshortcut.debug.approval "$screen"; sleep 3
      screencapture -x "$OUT/version-organisee-$screen.png" 2>/dev/null || true
    done
    "$POST" app.flshortcut.debug.approval fermer; sleep 1
    # Changement de page au ralenti (10 fois) : Général → Mixer, photographié en route (barre au-dessus du titre ?).
    "$POST" app.flshortcut.debug.select general; sleep 2
    "$POST" app.flshortcut.debug.select "mixer lent"
    for i in 1 2 3 4 5 6 7 8; do
      sleep 0.5; screencapture -x "$OUT/page-change-$i.png" 2>/dev/null || true
    done
    sleep 5
    "$POST" app.flshortcut.debug.select general; sleep 2
    # Créateur de macros au ralenti (10 fois) : ouverture depuis la page Macros, puis retour, photographiés en route.
    "$POST" app.flshortcut.debug.select macros; sleep 2
    "$POST" app.flshortcut.debug.macro "open lent"
    for i in 1 2 3 4 5 6 7 8; do
      sleep 0.5; screencapture -x "$OUT/createur-ouverture-$i.png" 2>/dev/null || true
    done
    sleep 4
    "$POST" app.flshortcut.debug.macro "close lent"
    for i in 1 2 3 4 5 6; do
      sleep 0.5; screencapture -x "$OUT/createur-retour-$i.png" 2>/dev/null || true
    done
    sleep 5
    "$POST" app.flshortcut.debug.macro close; sleep 1
    "$POST" app.flshortcut.debug.select macros; sleep 2
  fi
  # Témoin : aucun modèle du créateur avant sa première ouverture (fenêtres : toutes, et visibles seulement).
  local n0
  n0=$(report "$label-avant-createur")
  categories "$p" "$label-avant-createur"
  "$POST" app.flshortcut.debug.macro open; sleep 5
  screencapture -x "$OUT/$label-createur.png" 2>/dev/null || true
  report "$label-createur-ouvert" >/dev/null
  fit+=" / $(fits "$label-createur-ouvert")"
  # Vrai glisser-déposer à la souris : « Touche ou raccourci » de la palette (1er bloc de Clavier, sous les 10 blocs
  # de FL Studio), lâché entre les blocs 4 et 5 de l'exemple ; la liste des blocs doit gagner une ligne.
  drag "$label-createur-ouvert" 113 420 465 376; sleep 2
  report "$label-createur-glisse" >/dev/null
  screencapture -x "$OUT/$label-createur-glisse.png" 2>/dev/null || true
  drop="$(rows "$label-createur-ouvert") → $(rows "$label-createur-glisse")"
  # Puis un bloc de la liste déplacé à la souris : « Clic droit » (2e ligne, sur son nom, sous le bandeau
  # « Enregistrer clics et touches ») lâché entre les lignes 6 et 7 ; l'ordre des blocs doit changer.
  drag "$label-createur-ouvert" 400 256 400 472; sleep 2
  report "$label-createur-deplace" >/dev/null
  screencapture -x "$OUT/$label-createur-deplace.png" 2>/dev/null || true
  if [[ -z "$(order "$label-createur-glisse")" ]]; then moved="?"
  elif [[ "$(order "$label-createur-glisse")" != "$(order "$label-createur-deplace")" ]]; then moved="oui"
  else moved="NON"; fi
  # Les mêmes gestes faits vite, comme une vraie main (appui puis départ aussitôt) : la liste doit encore gagner une
  # ligne, puis l'ordre changer. Résultat dans glisser-essai.txt.
  drag "$label-createur-ouvert" 113 420 465 424 vite; sleep 2
  report "$label-createur-glisse-vite" >/dev/null
  screencapture -x "$OUT/$label-createur-glisse-vite.png" 2>/dev/null || true
  drag "$label-createur-ouvert" 400 256 400 472 vite; sleep 2
  report "$label-createur-deplace-vite" >/dev/null
  { echo "$label : palette → liste lent $(rows "$label-createur-ouvert") → $(rows "$label-createur-glisse"), vite → $(rows "$label-createur-glisse-vite")"
    if [[ "$(order "$label-createur-glisse-vite")" != "$(order "$label-createur-deplace-vite")" ]]; then
      echo "$label : bloc rangé vite : oui"
    else
      echo "$label : bloc rangé vite : NON"
    fi
  } >> "$OUT/glisser-essai.txt"
  rm -f "$HOME/Library/Caches/$DOMAIN/$label-createur-"*
  "$POST" app.flshortcut.debug.snapshot "$label-createur"; sleep 2
  cp "$HOME/Library/Caches/$DOMAIN/$label-createur-"*.png "$OUT/" 2>/dev/null || true
  mc=$(mem_mb "$p"); cc=$(cpu_avg "$p")
  categories "$p" "$label-createur-ouvert"
  "$POST" app.flshortcut.debug.macro close; sleep 4
  md=$(mem_mb "$p")
  categories "$p" "$label-createur-referme"
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
  categories "$p" "$label-recherche"
  "$POST" app.flshortcut.debug.search ""; sleep 1
  echo "| $label | $m0 | $c0 | $m1 | $c1 | $c1b | $mb | $mc | $cc | $md | $m2 | $m3 | ${co[2]} | ${cf[2]} | ${co[3]} | ${cf[3]} | $n0 ; ${nm[1]} / ${nm[2]} / ${nm[3]} | $fit | $drop | $moved |"
}

echo "| Effet | Mémoire (barre des menus) | Processeur | Mémoire (fenêtre ouverte) | Processeur (fenêtre ouverte, au repos) | Processeur (fenêtre, 10 s plus tard) | Mémoire (page Macros) | Mémoire (créateur ouvert) | Processeur (créateur ouvert, au repos) | Mémoire (créateur refermé) | Mémoire (page Mixer) | Mémoire (recherche « e », presque tout) | Mémoire (créateur cycle 2 ouvert) | Mémoire (créateur cycle 2 refermé) | Mémoire (créateur cycle 3 ouvert) | Mémoire (créateur cycle 3 refermé) | Modèles du créateur vivants (avant ouverture ; après fermeture, cycles 1 / 2 / 3) | Colonnes dans la fenêtre (Général / Macros / créateur) | Bloc glissé de la palette (lignes avant → après) | Bloc déplacé dans la liste (ordre changé) |"
echo "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"
run "verre" YES
run "sans-verre" NO
pkill -x FLShortcut 2>/dev/null

restore debugSnapshots "$had_snap"; restore liquidGlass "$had_glass"; restore didOnboard "$had_onb"; restore guideSeen "$had_guide"
echo
echo "macOS $(sw_vers -productVersion), $(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
