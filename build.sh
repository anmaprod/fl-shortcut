#!/bin/bash
# Construit « FL Shortcut.app » et FLShortcut.dmg (app universelle Apple Silicon + Intel).
# Audit : SEC-08 (Hardened Runtime, Developer ID, notarisation, pas de --deep), SEC-09 / SUP (empreinte SHA-256).
#
# Usage :
#   ./build.sh                       → build de développement, signature ad hoc (ta machine uniquement)
#   SIGN_IDENTITY="Developer ID Application: Nom (TEAMID)" ./build.sh
#                                    → build signé avec Hardened Runtime
#   + NOTARY_PROFILE="flshortcut"    → notarisation et agrafage (profil créé une fois avec
#                                      `xcrun notarytool store-credentials flshortcut …`)
#   + NOTARY_KEY / NOTARY_KEY_ID / NOTARY_ISSUER → notarisation avec une clé API (CI)
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="FL Shortcut"
EXE="FLShortcut"
APP="dist/${APP_NAME}.app"
DMG="dist/FLShortcut.dmg"
ARCHS=(--arch arm64 --arch x86_64)
# FLS_NATIVE=1 : architecture de cette machine seulement (suffit pour tester ; marche aussi sans Xcode complet).
if [[ "${FLS_NATIVE:-0}" == "1" ]]; then ARCHS=(); fi

if [[ "${FLS_SKIP_TESTS:-0}" != "1" ]]; then
  echo "▸ Tests"
  swift test
fi

echo "▸ Compilation release"
swift build -c release ${ARCHS[@]+"${ARCHS[@]}"}
BIN_DIR=$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)

echo "▸ Assemblage de l'app"
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXE" "$APP/Contents/MacOS/$EXE"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/device_FLShortcut.py "$APP/Contents/Resources/"
chmod -R go-w "$APP"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "▸ Signature Developer ID + Hardened Runtime"
  # Aucun entitlement : pas de disable-library-validation ni d'allow-dyld-environment-variables (SEC-08).
  # Pas de --deep : l'app ne contient qu'un exécutable, signé explicitement.
  codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$APP/Contents/MacOS/$EXE"
  codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
  codesign --display --verbose=2 "$APP" 2>&1 | grep -q "flags=0x10000(runtime)" \
    || { echo "✗ Hardened Runtime absent" >&2; exit 1; }
else
  echo "▸ Signature ad hoc (développement uniquement — ne pas distribuer)"
  codesign --force --sign - "$APP"
fi

echo "▸ Image disque"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"

  NOTARY_ARGS=()
  if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    NOTARY_ARGS=(--keychain-profile "$NOTARY_PROFILE")
  elif [[ -n "${NOTARY_KEY:-}" && -n "${NOTARY_KEY_ID:-}" && -n "${NOTARY_ISSUER:-}" ]]; then
    NOTARY_ARGS=(--key "$NOTARY_KEY" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER")
  fi

  if [[ ${#NOTARY_ARGS[@]} -gt 0 ]]; then
    echo "▸ Notarisation Apple"
    xcrun notarytool submit "$DMG" "${NOTARY_ARGS[@]}" --wait
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
    spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"
  else
    echo "⚠︎ Pas d'identifiants de notarisation : le .dmg est signé mais pas notarisé."
  fi
fi

echo "▸ Empreinte"
(cd dist && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256")
cat "$DMG.sha256"

echo "✅ Terminé : $APP et $DMG"

# Build local (FLS_NATIVE=1) : copie aussi l'app dans ~/Applications pour la lancer comme une vraie app.
if [[ "${FLS_NATIVE:-0}" == "1" ]]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/${APP_NAME}.app"
  cp -R "$APP" "$HOME/Applications/"
  echo "▸ Installé dans ~/Applications"
fi
