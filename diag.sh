#!/bin/bash
defaults write app.flshortcut.FLShortcut debugSnapshots -bool YES
C="$HOME/Library/Caches/app.flshortcut.FLShortcut"; rm -f "$C"/*.png
pkill -x FLShortcut; sleep 1.5; open "$HOME/Applications/FL Shortcuts.app"; sleep 5
/tmp/fls_post app.flshortcut.debug.open; sleep 3
/tmp/fls_post app.flshortcut.debug.snapshot avant; sleep 1
# Clic réel sur « Piano Roll » puis « Mixer » dans la barre latérale (points depuis le haut-gauche de la fenêtre)
/tmp/fls_post app.flshortcut.debug.click "100,200"; sleep 1.5
/tmp/fls_post app.flshortcut.debug.snapshot clic-pianoroll; sleep 1
/tmp/fls_post app.flshortcut.debug.click "100,260"; sleep 1.5
/tmp/fls_post app.flshortcut.debug.snapshot clic-mixer; sleep 1
defaults delete app.flshortcut.FLShortcut debugSnapshots
rm -f .transfert/*.png; cp "$C"/*.png .transfert/; ls .transfert/*.png
