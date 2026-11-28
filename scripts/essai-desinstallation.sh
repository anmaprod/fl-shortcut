#!/bin/bash
# Essai de la désinstallation sur la machine de la CI, comme chez un utilisateur : le .pkg installe les apps dans
# /Applications (au système), une ancienne app « FL Shortcut » traîne dans /Applications et dans ~/Applications, et
# toutes les traces que l'app laisse sont semées, sous le nom actuel et l'ancien nom. Puis la désinstallation tourne
# sans fenêtre (le mot de passe passe par sudo -n), et ce script revérifie lui-même, chemin par chemin, que plus rien
# ne reste… sauf ce qui n'est pas à nous. RÉSERVÉ À UNE MACHINE JETABLE : il efface tout ce qui touche à l'app.
# Mode « fenetre » : la vraie fenêtre de désinstallation, comme chez un utilisateur (l'app lancée depuis
# /Applications, « Désinstaller » cliqué, captures d'écran de chaque étape) ; l'app doit se fermer toute seule, sans
# aucune demande de mot de passe (le .pkg lui a donné l'app et a oublié son reçu).
# Usage (CI) : scripts/essai-desinstallation.sh dist dist/mesure/desinstallation.txt [fenetre]
set -uo pipefail
[[ "${CI:-}" == "true" ]] || { echo "Réservé à la CI (machine jetable) : il efface les données de l'app."; exit 2; }
DIST="${1:-dist}"
OUT="${2:-dist/mesure/desinstallation.txt}"
MODE="${3:-sans-fenetre}"
SHOTS="$(dirname "$OUT")"
H="$HOME"
L="$H/Library"
HW="$H/Documents/Image-Line/FL Studio/Settings/Hardware"
mkdir -p "$(dirname "$OUT")"
: > "$OUT"
say() { echo "$*" | tee -a "$OUT"; }
# Durée maximale d'une commande (une fenêtre de macOS sans personne pour répondre bloquerait l'essai) : code 142.
limit() { local s=$1; shift; perl -e 'alarm shift; exec @ARGV or die "exec: $!\n"' "$s" "$@"; }
pkill -x FLShortcut 2>/dev/null || true

# 0. Trousseau à part, ouvert, seul dans la liste : les étapes d'avant ont pu y ranger la clé avec une autre
# compilation de l'app, et la lire ou la changer ferait demander un mot de passe à l'écran.
KC="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/essai-desinstallation.keychain-db"
security delete-keychain "$KC" >/dev/null 2>&1 || true
limit 20 security create-keychain -p essai "$KC" && limit 20 security set-keychain-settings "$KC" \
  && limit 20 security unlock-keychain -p essai "$KC" && security list-keychains -d user -s "$KC" \
  && security default-keychain -d user -s "$KC" || say "(Trousseau d'essai impossible : Trousseau de session gardé)"

# 1. Une ancienne app « FL Shortcut » et un ancien désinstalleur à part au système, puis le .pkg : son script d'après
# installation doit les retirer, et il n'installe plus que l'app (on désinstalle depuis son menu).
sudo cp -R "$DIST/FL Shortcuts.app" "/Applications/FL Shortcut.app"
sudo cp -R "$DIST/FL Shortcuts.app" "/Applications/Désinstaller FL Shortcuts.app"
sudo /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier app.flshortcut.Uninstaller" \
  "/Applications/Désinstaller FL Shortcuts.app/Contents/Info.plist"
limit 300 sudo installer -pkg "$DIST/FLShortcuts.pkg" -target / >/dev/null \
  || { say "FAIL: installation du .pkg impossible"; exit 1; }
for old in "FL Shortcut.app" "Désinstaller FL Shortcuts.app"; do
  if [[ -e "/Applications/$old" ]]; then say "FAIL: le .pkg a laissé /Applications/$old"; exit 1; fi
done
[[ -d "/Applications/FL Shortcuts.app" ]] || { say "FAIL: le .pkg n'a pas installé l'app"; exit 1; }
say "ok .pkg : l'app seule installée, ancienne app et ancien désinstalleur retirés"
owner=$(stat -f%Su "/Applications/FL Shortcuts.app")
[[ "$owner" == "$(id -un)" ]] && say "ok l'app installée appartient à $owner (désinstallation sans mot de passe)" \
  || say "(l'app installée appartient à $owner)"
for i in $(seq 1 20); do pkgutil --pkg-info app.flshortcut.pkg >/dev/null 2>&1 || break; sleep 1; done
pkgutil --pkg-info app.flshortcut.pkg >/dev/null 2>&1 && say "(reçu du .pkg encore là après 20 s)" \
  || say "ok reçu du .pkg oublié après l'installation"

# 2. Toutes les traces, sous les deux noms (ancienne compilation locale dans ~/Applications comprise).
mkdir -p "$H/Applications"
cp -R "$DIST/FL Shortcuts.app" "$H/Applications/FL Shortcut.app"
cp -R "$DIST/FL Shortcuts.app" "$H/Applications/Désinstaller FL Shortcut.app"     # ancien désinstalleur à part
for n in "FL Shortcuts" "FL Shortcut"; do
  mkdir -p "$L/Application Support/$n" "$L/Logs/$n" "$H/Desktop/$n – captures" "$H/Documents/$n/Macros" "$HW/$n"
  echo '{}' > "$L/Application Support/$n/profile.json"
  echo 'RUN' > "$L/Logs/$n/macro.log"
  echo 'png' > "$H/Desktop/$n – captures/capture.png"
  echo '{}' > "$H/Documents/$n/Macros/Voix.flsmacro"
  echo "# name=$n" > "$HW/$n/device_FLShortcut.py"
done
mkdir -p "$HW/Autre controleur"
echo '# name=Autre' > "$HW/Autre controleur/device_autre.py"          # pas à nous : doit rester
for id in app.flshortcut.FLShortcut app.flshortcut.Uninstaller; do
  defaults write "$id" essai -bool true
  mkdir -p "$L/Caches/$id" "$L/Saved Application State/$id.savedState" "$L/HTTPStorages/$id"
done
limit 20 security create-keychain -p essai "$L/Keychains/flshortcut-dev.keychain-db" >/dev/null 2>&1 || true
[[ -f "$KC" ]] && security list-keychains -d user -s "$KC"         # create-keychain l'a ajouté à la liste
limit 20 security add-generic-password -A -U -s app.flshortcut.FLShortcut -a fl-script-key \
  -w 00112233445566778899aabbccddeeff >/dev/null 2>&1 || say "(Trousseau indisponible ici : clé non semée)"
limit 20 security add-generic-password -A -U -s app.flshortcut.FLShortcut -a community-session -w '{}' >/dev/null 2>&1 \
  || true
say "ok traces semées"

# 3. Désinstallation, lancée depuis l'app installée par le .pkg.
if [[ "$MODE" == fenetre ]]; then
  D=app.flshortcut.FLShortcut
  defaults write "$D" debugSnapshots -bool YES
  defaults write "$D" didOnboard -bool YES
  defaults write "$D" guideSeen -bool YES
  POST="$(mktemp -d)/fls_post"
  cat > "$POST.swift" <<'SWIFT'
import Foundation
let args = CommandLine.arguments
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name(args[1]), object: args.count > 2 ? args[2] : nil, userInfo: nil, deliverImmediately: true)
SWIFT
  swiftc -O "$POST.swift" -o "$POST" 2>/dev/null || { say "FAIL: swiftc indisponible"; exit 1; }
  FLS_ESSAI_DESINSTALLATION=1 "/Applications/FL Shortcuts.app/Contents/MacOS/FLShortcut" >/dev/null 2>&1 &
  pid=$!
  sleep 8
  kill -0 "$pid" 2>/dev/null || { say "FAIL: l'app ne démarre pas"; exit 1; }
  "$POST" app.flshortcut.debug.uninstall reel
  # Fenêtre, « Désinstaller » cliqué 1,5 s après, suppression, bilan, fermeture seule 2,5 s après le bilan.
  for i in $(seq -w 1 16); do screencapture -x "$SHOTS/desinstallation-fenetre-$i.png" 2>/dev/null; sleep 0.5; done
  for i in $(seq 1 40); do kill -0 "$pid" 2>/dev/null || break; sleep 0.5; done
  if kill -0 "$pid" 2>/dev/null; then
    screencapture -x "$SHOTS/desinstallation-fenetre-bloquee.png" 2>/dev/null
    say "FAIL: l'app ne s'est pas fermée toute seule après la désinstallation"
    kill "$pid" 2>/dev/null
    status=1
  else
    wait "$pid"; status=$?
    say "ok l'app s'est fermée toute seule (code $status), sans demander de mot de passe"
  fi
else
  limit 180 env FLS_ESSAI_DESINSTALLATION=1 FLS_ESSAI_SUDO=1 \
    "/Applications/FL Shortcuts.app/Contents/MacOS/FLShortcut" --essai-desinstallation 2>&1 | tee -a "$OUT"
  status=${PIPESTATUS[0]}
  [[ $status -eq 142 ]] && say "FAIL: désinstallation bloquée plus de 3 minutes (une fenêtre de macOS attendait ?)"
fi
sleep 2                                                             # cfprefsd a fini d'écrire

# 4. Vérification indépendante.
left=0
check() { if [[ -e "$1" || -L "$1" ]]; then say "RESTE (vu par le script) : $1"; left=1; fi; }
for a in "FL Shortcuts.app" "Désinstaller FL Shortcuts.app" "FL Shortcut.app" "Désinstaller FL Shortcut.app"; do
  check "/Applications/$a"; check "$H/Applications/$a"
done
[[ "$MODE" == fenetre ]] && defaults delete app.flshortcut.FLShortcut debugSnapshots >/dev/null 2>&1
for n in "FL Shortcuts" "FL Shortcut"; do
  check "$L/Application Support/$n"; check "$L/Logs/$n"; check "$H/Desktop/$n – captures"; check "$H/Documents/$n"
  check "$HW/$n"
done
for id in app.flshortcut.FLShortcut app.flshortcut.Uninstaller; do
  check "$L/Preferences/$id.plist"; check "$L/Caches/$id"; check "$L/Saved Application State/$id.savedState"
  check "$L/HTTPStorages/$id"
  if [[ -n "$(defaults read "$id" 2>/dev/null)" ]]; then say "RESTE : réglages $id"; left=1; fi
done
check "$L/Keychains/flshortcut-dev.keychain-db"
if security find-generic-password -s app.flshortcut.FLShortcut >/dev/null 2>&1; then say "RESTE : élément du Trousseau"; left=1; fi
if pkgutil --pkg-info app.flshortcut.pkg >/dev/null 2>&1; then say "RESTE : reçu du .pkg"; left=1; fi
if [[ ! -f "$HW/Autre controleur/device_autre.py" ]]; then say "FAIL: un dossier qui n'est pas à nous a été supprimé"; left=1; fi
if [[ $status -eq 0 && $left -eq 0 ]]; then
  say "PASS: désinstallation complète, plus aucune trace (apps du .pkg, ancien nom, données, Trousseau, script FL, reçu)"
  exit 0
fi
say "FAIL: désinstallation incomplète (code $status)"
exit 1
