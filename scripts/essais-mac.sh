#!/bin/bash
# Essais automatiques de FL Shortcut sur le Mac de l'utilisateur, en une seule commande : aucun clic de Claude, aucune
# capture, aucune action dans le vrai FL Studio. Dans l'ordre : tests du script FL (Python), tests Swift, compilation,
# essais contre le FL simulé (choix du preset dans une vraie boîte « Open », macro « Enregistrement rapide » complète,
# macro en blocs, « Enregistrer des clics »), puis un résumé PASS / FAIL avec les durées.
# Les préférences de FL Shortcut (positions apprises, réglages) sont sauvegardées avant et remises après : l'essai de
# la macro efface les positions apprises. FL Studio peut rester ouvert ; ne touche pas la souris pendant les essais
# contre le FL simulé (environ 4 minutes) : ils cliquent dans sa fenêtre.
#
# Usage : scripts/essais-mac.sh [--vite] [--avec-mesure]
#   --vite        sans tests Swift ni recompilation (essaie ~/Applications/FL Shortcut.app tel quel)
#   --avec-mesure ajoute la mesure mémoire / processeur de l'interface (scripts/mesure-interface.sh, ~4 min de plus)
# Sorties : .essais/ (un fichier par essai, plus resume.txt), hors de dist/ que ./build.sh efface.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1

VITE=0; MESURE=0
for a in "$@"; do
  case "$a" in
    --vite) VITE=1 ;;
    --avec-mesure) MESURE=1 ;;
    *) echo "option inconnue : $a"; exit 2 ;;
  esac
done

# Xcode complet, sans changer le réglage du système (comme « Compiler FL Shortcut.command »).
XCODE=$(ls -d /Applications/Xcode*.app "$HOME"/Applications/Xcode*.app 2>/dev/null | head -1)
if [[ -n "$XCODE" && -d "$XCODE/Contents/Developer" ]]; then export DEVELOPER_DIR="$XCODE/Contents/Developer"; fi

OUT="$PWD/.essais"
rm -rf "$OUT"; mkdir -p "$OUT"
DOMAIN="app.flshortcut.FLShortcut"
APP="$HOME/Applications/FL Shortcut.app"
BIN="$APP/Contents/MacOS/FLShortcut"
RESUME="$OUT/resume.txt"
declare -a LIGNES=()

note() { LIGNES+=("$1"); echo "$1"; }

# Une étape : nom, fichier de sortie, commande. PASS si le code de sortie est 0.
etape() {
  local nom="$1" sortie="$2"; shift 2
  local t0=$SECONDS
  echo "▸ $nom"
  "$@" > "$sortie" 2>&1
  local code=$?
  local duree=$((SECONDS - t0))
  if [[ $code -eq 0 ]]; then note "PASS  $nom (${duree} s)"; else note "FAIL  $nom (${duree} s, code $code) → $sortie"; tail -15 "$sortie"; fi
  return $code
}

# Essai lancé en arrière-plan avec un chien de garde (arrêté dès la fin de l'essai, comme sur la CI).
essai() {
  local nom="$1" sortie="$2" delai="$3"; shift 3
  local t0=$SECONDS
  echo "▸ $nom"
  "$@" &
  local pid=$!
  ( sleep "$delai"; kill "$pid" 2>/dev/null ) &
  local chien=$!
  local code=0; wait "$pid" || code=$?
  kill "$chien" 2>/dev/null; wait "$chien" 2>/dev/null
  local duree=$((SECONDS - t0))
  if grep -Eq '^(PASS|SKIP)' "$sortie" 2>/dev/null; then
    note "$(grep -E '^(PASS|SKIP)' "$sortie" | head -1 | cut -c1-4)  $nom (${duree} s)"
  else
    note "FAIL  $nom (${duree} s, code $code) → $sortie"; tail -25 "$sortie" 2>/dev/null
  fi
}

# Préférences : sauvegardées, puis remises quoi qu'il arrive.
AVAIT_PREFS=0
if defaults export "$DOMAIN" "$OUT/preferences-avant.plist" 2>/dev/null; then AVAIT_PREFS=1; fi
remettre() {
  pkill -x FLShortcut 2>/dev/null
  mkdir -p "$OUT"
  # `defaults import` fusionne : le domaine est d'abord vidé, sinon une clé apprise pendant les essais (position sur
  # le FL simulé…) resterait et serait rejouée dans le vrai FL.
  defaults delete "$DOMAIN" 2>/dev/null
  if [[ $AVAIT_PREFS == 1 ]]; then defaults import "$DOMAIN" "$OUT/preferences-avant.plist"; fi
  { echo "Essais automatiques de FL Shortcut — $(date '+%d/%m/%Y %H:%M')"; echo "Commit : $(git rev-parse --short HEAD) ($(git rev-parse --abbrev-ref HEAD))"
    printf '%s\n' "${LIGNES[@]}"; } > "$RESUME"
  echo; echo "Résumé : $RESUME"; cat "$RESUME"
}
trap remettre EXIT

note "macOS $(sw_vers -productVersion) ($(uname -m)) · $(xcodebuild -version 2>/dev/null | head -1) · commit $(git rev-parse --short HEAD)"
FL=$(mdfind "kMDItemCFBundleIdentifier == 'com.image-line.flstudio'" 2>/dev/null | head -1)
[[ -n "$FL" ]] && note "FL Studio $(defaults read "$FL/Contents/Info" CFBundleShortVersionString 2>/dev/null) ($FL)"

etape "Tests du script FL (Python)" "$OUT/python.txt" python3 -m unittest discover -s Tests/python
if [[ $VITE == 0 ]]; then
  etape "Tests Swift" "$OUT/swift-test.txt" swift test
  grep -E "Executed [0-9]+ tests" "$OUT/swift-test.txt" | tail -1 | sed 's/^/      /'
  etape "Compilation et installation dans ~/Applications" "$OUT/build.txt" env FLS_NATIVE=1 FLS_SKIP_TESTS=1 ./build.sh \
    || { echo "Compilation impossible : arrêt."; exit 1; }
fi
[[ -x "$BIN" ]] || { note "FAIL  app introuvable : $APP"; exit 1; }

# L'app de la barre des menus est quittée : un seul FL Shortcut à la fois envoie des événements.
pkill -x FLShortcut 2>/dev/null; sleep 1

essai "Choix automatique du preset (vraie boîte « Open »)" "$OUT/selftest-preset.txt" 60 \
  "$BIN" --selftest-preset "$OUT/selftest-preset.txt"

ETAT="$OUT/fakefl.json"
"$BIN" --fake-fl "$ETAT" > "$OUT/fakefl.txt" 2>&1 &
FAUX=$!
sleep 3
essai "Macro « Enregistrement rapide » sur le FL simulé (6 passages)" "$OUT/selftest-macro.txt" 150 \
  "$BIN" --selftest-macro "$OUT/selftest-macro.txt" "$ETAT" "$FAUX"
essai "Macro construite en blocs (chemin du bouton « Tester »)" "$OUT/selftest-blocs.txt" 60 \
  "$BIN" --selftest-macro "$OUT/selftest-blocs.txt" "$ETAT" "$FAUX" --scenario blocs
essai "« Enregistrer des clics » puis rejeu" "$OUT/selftest-clics.txt" 90 \
  "$BIN" --selftest-macro "$OUT/selftest-clics.txt" "$ETAT" "$FAUX" --scenario clics
kill "$FAUX" 2>/dev/null; wait "$FAUX" 2>/dev/null

if [[ $MESURE == 1 ]]; then
  etape "Mesure mémoire / processeur de l'interface" "$OUT/mesure.txt" scripts/mesure-interface.sh "$APP" "$OUT/mesure"
fi

# L'app de la barre des menus est relancée telle que l'utilisateur l'avait (préférences remises par le piège).
trap - EXIT
remettre
open "$APP"
for ligne in "${LIGNES[@]}"; do [[ $ligne == FAIL* ]] && exit 1; done
exit 0
