#!/bin/bash
# Captures de l'app en anglais (langue de l'app réglée sur l'anglais, comme un Mac en anglais) : page principale,
# Macros, créateur, Organiser, Aide, Mon compte, guide. Rien d'autre n'est touché ; préférences remises à la fin.
# Usage : scripts/captures-anglais.sh "dist/FL Shortcuts.app" dossier-de-sortie
set -uo pipefail
APP="${1:-dist/FL Shortcuts.app}"
OUT="${2:-dist/mesure/anglais}"
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
had_onb=$(defaults read "$DOMAIN" didOnboard 2>/dev/null || echo "")
defaults write "$DOMAIN" debugSnapshots -bool YES
defaults write "$DOMAIN" didOnboard -bool YES
defaults write "$DOMAIN" AppleLanguages -array en

shot() { sleep "${2:-3}"; screencapture -x "$OUT/$1.png" 2>/dev/null || true; }

pkill -x FLShortcut 2>/dev/null; sleep 1
open "$APP"; sleep 6
"$POST" app.flshortcut.debug.open; sleep 4
"$POST" app.flshortcut.debug.resize "960,640"
"$POST" app.flshortcut.debug.select general; shot general
"$POST" app.flshortcut.debug.select macros; shot macros
"$POST" app.flshortcut.debug.macro open; shot createur 5
"$POST" app.flshortcut.debug.macro close; sleep 2
for screen in installer page apercu fini; do
  "$POST" app.flshortcut.debug.organizer "$screen"; shot "organiser-$screen"
done
"$POST" app.flshortcut.debug.organizer fermer; sleep 1
"$POST" app.flshortcut.debug.select aide
for screen in aide ecrire; do "$POST" app.flshortcut.debug.help "$screen"; shot "aide-$screen"; done
"$POST" app.flshortcut.debug.select compte
"$POST" app.flshortcut.debug.account connexion; shot compte
"$POST" app.flshortcut.debug.select community
"$POST" app.flshortcut.debug.community liste; shot communaute
for n in 0 1 2; do "$POST" app.flshortcut.debug.guide "$n"; shot "guide-$n" 2; done
"$POST" app.flshortcut.debug.guide fin; sleep 1
pkill -x FLShortcut 2>/dev/null; sleep 1

defaults delete "$DOMAIN" AppleLanguages 2>/dev/null
if [[ -n "$had_snap" ]]; then defaults write "$DOMAIN" debugSnapshots -bool "$had_snap"; else defaults delete "$DOMAIN" debugSnapshots 2>/dev/null; fi
if [[ -n "$had_onb" ]]; then defaults write "$DOMAIN" didOnboard -bool "$had_onb"; else defaults delete "$DOMAIN" didOnboard 2>/dev/null; fi
echo "$(ls "$OUT" | wc -l | tr -d ' ') captures en anglais dans $OUT"
