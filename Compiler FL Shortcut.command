#!/bin/bash
# FL Shortcut — boucle de compilation pour Claude.
# Lance-la d'un double-clic : elle attend une demande (fichier .demande) et n'exécute
# que 4 commandes fixes dans ce dossier : test, build, run, stop. Ferme la fenêtre pour arrêter.
cd "$(dirname "$0")" || exit 1
# Xcode complet (nécessaire pour SwiftUI sur macOS 27) : utilisé sans changer le réglage du système.
XCODE=$(ls -d /Applications/Xcode*.app "$HOME"/Applications/Xcode*.app 2>/dev/null | head -1)
if [ -n "$XCODE" ] && [ -d "$XCODE/Contents/Developer" ]; then
  export DEVELOPER_DIR="$XCODE/Contents/Developer"
fi
echo "FL Shortcut : compilation automatique pour Claude."
echo "Laisse cette fenêtre ouverte. Ferme-la quand tu veux pour tout arrêter."
{ echo "== macOS"; sw_vers; uname -m; echo "== outils"; echo "DEVELOPER_DIR=$DEVELOPER_DIR"; xcodebuild -version; swift --version; } > .env.txt 2>&1
cat .env.txt
rm -f .demande
while true; do
  if [ -f .demande ]; then
    cmd=$(head -c 10 .demande | tr -cd 'a-z'); rm -f .demande
    echo "--- $(date '+%H:%M:%S') : $cmd"
    case "$cmd" in
      test)  swift test ;;
      build) FLS_NATIVE=1 FLS_SKIP_TESTS=1 ./build.sh ;;
      run)   pkill -x "FL Shortcut" 2>/dev/null; sleep 1; open "dist/FL Shortcut.app" ;;
      stop)  pkill -x "FL Shortcut" ;;
      *)     echo "demande inconnue : $cmd" ;;
    esac > .journal.txt 2>&1
    echo "code=$?" >> .journal.txt
    tail -3 .journal.txt
    date '+%s' > .fini
  fi
  sleep 2
done
