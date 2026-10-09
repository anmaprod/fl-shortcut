#!/bin/bash
# Construit "FL Shortcut.app" et un FLShortcut.dmg prêt à partager.
# Nécessite un Mac avec Xcode (ou lance le workflow GitHub Actions fourni).
set -euo pipefail
cd "$(dirname "$0")"

ARCHS=(--arch arm64 --arch x86_64)   # app universelle : Mac Apple Silicon + Intel
swift build -c release "${ARCHS[@]}"
BIN_DIR=$(swift build -c release "${ARCHS[@]}" --show-bin-path)

APP="dist/FL Shortcut.app"
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/FLShortcut" "$APP/Contents/MacOS/FLShortcut"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/device_FLShortcut.py "$APP/Contents/Resources/"

# Signature "ad hoc" (gratuite). Pour éviter l'avertissement Gatekeeper chez les autres,
# remplace "-" par ton identité "Developer ID Application: …" puis notarise l'app.
codesign --force --deep --sign "${SIGN_IDENTITY:--}" "$APP"

# Image disque avec raccourci vers Applications
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "FL Shortcut" -srcfolder "$STAGE" -ov -format UDZO dist/FLShortcut.dmg
rm -rf "$STAGE"

echo "✅ Terminé : dist/FL Shortcut.app et dist/FLShortcut.dmg"
