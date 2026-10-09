#!/bin/bash
APP="$HOME/Applications/FL Shortcut.app"
echo "== signature"; codesign -dr - "$APP" 2>&1 | tail -1; codesign --verify "$APP" && echo "signature valide"
echo "== mesure du temps de réponse de FL"
pkill -x FLShortcut; sleep 1
"$APP/Contents/MacOS/FLShortcut" --mesure 2>&1 | grep -v -E "^\s*$" | tail -8
open "$APP"
