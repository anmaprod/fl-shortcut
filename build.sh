#!/bin/bash
# Construit "FL Remap.app" et un FLRemap.dmg prêt à partager.
# Nécessite un Mac avec Xcode (ou lance le workflow GitHub Actions fourni).
set -euo pipefail
cd "$(dirname "$0")"

ARCHS=(--arch arm64 --arch x86_64)   # app universelle : Mac Apple Silicon + Intel
swift build -c release "${ARCHS[@]}"
BIN_DIR=$(swift build -c release "${ARCHS[@]}" --show-bin-path)

APP="dist/FL Remap.app"
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/FLRemap" "$APP/Contents/MacOS/FLRemap"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/device_FLRemap.py "$APP/Contents/Resources/"

# Signature "ad hoc" (gratuite). Pour éviter l'avertissement Gatekeeper chez les autres,
# remplace "-" par ton identité "Developer ID Application: …" puis notarise l'app.
codesign --force --deep --sign "${SIGN_IDENTITY:--}" "$APP"

# Image disque avec raccourci vers Applications
STAGE=$(mktemp -d)
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "FL Remap" -srcfolder "$STAGE" -ov -format UDZO dist/FLRemap.dmg
rm -rf "$STAGE"

echo "✅ Terminé : dist/FL Remap.app et dist/FLRemap.dmg"
