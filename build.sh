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

# Diagnostic à la demande : si le fichier .diag existe, on mesure au lieu de compiler.
if [[ -f .diag2 ]]; then rm -f .diag2; bash ./diag2.sh; exit 0; fi
if [[ -f .diag ]]; then rm -f .diag; bash ./diag.sh; exit 0; fi

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
# Version de la release (tag vX.Y.Z en CI) : affichée par le Finder et « À propos ».
if [[ -n "${FLS_VERSION:-}" ]]; then
  plutil -replace CFBundleShortVersionString -string "$FLS_VERSION" "$APP/Contents/Info.plist"
fi
# Communauté (supabase/README.md) : adresse du projet Supabase et sa clé publique « anon ». Sans elles, la page
# Communauté affiche « bientôt disponible » et l'app ne se connecte jamais à internet.
if [[ -n "${FLS_SUPABASE_URL:-}" && -n "${FLS_SUPABASE_ANON_KEY:-}" ]]; then
  plutil -replace FLSCommunityURL -string "$FLS_SUPABASE_URL" "$APP/Contents/Info.plist"
  plutil -replace FLSCommunityAnonKey -string "$FLS_SUPABASE_ANON_KEY" "$APP/Contents/Info.plist"
fi
cp Resources/device_FLShortcut.py "$APP/Contents/Resources/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
chmod -R go-w "$APP"

# Identité de signature locale, créée une seule fois dans un trousseau dédié (jamais le trousseau de session) :
# certificat auto-signé « FL Shortcut Dev », usage « signature de code » uniquement, valable sur ce Mac.
DEV_KC="$HOME/Library/Keychains/flshortcut-dev.keychain-db"
DEV_KC_PASS="flshortcut-dev"     # trousseau local de développement, ne protège que cette identité
dev_identity() {
  if [[ ! -f "$DEV_KC" ]]; then
    local t; t=$(mktemp -d)
    cat > "$t/cfg" <<'CFG'
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = FL Shortcut Dev
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CFG
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$t/cfg" \
      -keyout "$t/key.pem" -out "$t/cert.pem" >/dev/null 2>&1 \
    && openssl pkcs12 -export -inkey "$t/key.pem" -in "$t/cert.pem" -name "FL Shortcut Dev" \
      -out "$t/id.p12" -passout pass:"$DEV_KC_PASS" >/dev/null 2>&1 \
    && security create-keychain -p "$DEV_KC_PASS" "$DEV_KC" \
    && security set-keychain-settings "$DEV_KC" \
    && security unlock-keychain -p "$DEV_KC_PASS" "$DEV_KC" \
    && security import "$t/id.p12" -k "$DEV_KC" -P "$DEV_KC_PASS" -T /usr/bin/codesign >/dev/null \
    && security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$DEV_KC_PASS" "$DEV_KC" >/dev/null
    local ok=$?
    rm -rf "$t"
    [[ $ok -eq 0 ]] || { echo "  (identité locale impossible à créer : signature ad hoc)"; rm -f "$DEV_KC"; return 1; }
  fi
  security unlock-keychain -p "$DEV_KC_PASS" "$DEV_KC" 2>/dev/null || return 1
  DEV_ID=$(security find-certificate -c "FL Shortcut Dev" -Z "$DEV_KC" 2>/dev/null | awk '/SHA-1 hash/{print $3; exit}')
  [[ -n "$DEV_ID" ]]
}

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  echo "▸ Signature Developer ID + Hardened Runtime"
  # Aucun entitlement : pas de disable-library-validation ni d'allow-dyld-environment-variables (SEC-08).
  # Pas de --deep : l'app ne contient qu'un exécutable, signé explicitement.
  codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$APP/Contents/MacOS/$EXE"
  codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$APP"
  codesign --verify --strict --verbose=2 "$APP"
  codesign --display --verbose=2 "$APP" 2>&1 | grep -q "flags=0x10000(runtime)" \
    || { echo "✗ Hardened Runtime absent" >&2; exit 1; }
elif [[ "${FLS_NATIVE:-}" == "1" ]] && dev_identity; then
  # Compilation locale : identité de développement stable. macOS garde alors la permission Accessibilité
  # d'une compilation à l'autre (avec une signature ad hoc, chaque compilation est une « nouvelle » app).
  echo "▸ Signature de développement locale (FL Shortcut Dev)"
  codesign --force --keychain "$DEV_KC" --sign "$DEV_ID" "$APP" \
    || { echo "  (refusée : signature ad hoc)"; codesign --force --sign - "$APP"; }
else
  echo "▸ Signature ad hoc (développement uniquement — ne pas distribuer)"
  codesign --force --sign - "$APP"
fi

# Désinstalleur fourni dans le .dmg : même exécutable, identifiant à part, clé FLSUninstaller (Uninstaller.swift).
UNINSTALLER="dist/Désinstaller ${APP_NAME}.app"
echo "▸ Désinstalleur"
mkdir -p "$UNINSTALLER/Contents/MacOS" "$UNINSTALLER/Contents/Resources"
cp "$BIN_DIR/$EXE" "$UNINSTALLER/Contents/MacOS/$EXE"
cp Resources/AppIcon.icns "$UNINSTALLER/Contents/Resources/AppIcon.icns"
cp Resources/Info.plist "$UNINSTALLER/Contents/Info.plist"
plutil -replace CFBundleIdentifier -string "app.flshortcut.Uninstaller" "$UNINSTALLER/Contents/Info.plist"
plutil -replace CFBundleName -string "Désinstaller ${APP_NAME}" "$UNINSTALLER/Contents/Info.plist"
plutil -replace CFBundleDisplayName -string "Désinstaller ${APP_NAME}" "$UNINSTALLER/Contents/Info.plist"
plutil -replace LSUIElement -bool NO "$UNINSTALLER/Contents/Info.plist"
plutil -insert FLSUninstaller -bool YES "$UNINSTALLER/Contents/Info.plist"
chmod -R go-w "$UNINSTALLER"
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --timestamp --options runtime --sign "$SIGN_IDENTITY" "$UNINSTALLER"
elif [[ -n "${DEV_ID:-}" ]]; then
  codesign --force --keychain "$DEV_KC" --sign "$DEV_ID" "$UNINSTALLER" || codesign --force --sign - "$UNINSTALLER"
else
  codesign --force --sign - "$UNINSTALLER"
fi

echo "▸ Image disque"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp -R "$APP" "$STAGE/"
cp -R "$UNINSTALLER" "$STAGE/"
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

echo "▸ Paquet d'installation (.pkg) : FL Shortcut et son désinstalleur dans /Applications, en un double-clic"
PKG="dist/FLShortcut.pkg"
PKG_ROOT=$(mktemp -d)
PKG_PLIST=$(mktemp -d)/component.plist
cp -R "$APP" "$UNINSTALLER" "$PKG_ROOT/"
pkgbuild --analyze --root "$PKG_ROOT" "$PKG_PLIST" >/dev/null
# Toujours dans /Applications : sans cela, Installer « met à jour » une autre copie du même identifiant
# (par exemple un build de développement dans ~/Applications) au lieu d'installer celle-ci.
n=0
while plutil -extract "$n" xml1 -o /dev/null "$PKG_PLIST" 2>/dev/null; do
  plutil -replace "$n.BundleIsRelocatable" -bool NO "$PKG_PLIST"
  n=$((n + 1))
done
PKG_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
pkgbuild --root "$PKG_ROOT" --component-plist "$PKG_PLIST" --install-location /Applications \
  --identifier app.flshortcut.pkg --version "$PKG_VERSION" "dist/FLShortcut-component.pkg" >/dev/null
if [[ -n "${INSTALLER_SIGN_IDENTITY:-}" ]]; then
  productbuild --package "dist/FLShortcut-component.pkg" --sign "$INSTALLER_SIGN_IDENTITY" "$PKG"
else
  productbuild --package "dist/FLShortcut-component.pkg" "$PKG"
fi
rm -rf "$PKG_ROOT" "dist/FLShortcut-component.pkg"

echo "▸ Empreintes"
(cd dist && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256" \
  && shasum -a 256 "$(basename "$PKG")" > "$(basename "$PKG").sha256")
cat "$DMG.sha256" "$PKG.sha256"

echo "✅ Terminé : $APP, $DMG et $PKG"

# Build local (FLS_NATIVE=1) : copie aussi l'app dans ~/Applications pour la lancer comme une vraie app.
if [[ "${FLS_NATIVE:-0}" == "1" ]]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/${APP_NAME}.app"
  cp -R "$APP" "$HOME/Applications/"
  echo "▸ Installé dans ~/Applications"
fi
