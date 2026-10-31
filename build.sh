#!/bin/bash
# Construit « FL Shortcuts.app » et FLShortcuts.dmg (app universelle Apple Silicon + Intel).
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

APP_NAME="FL Shortcuts"
OLD_APP_NAME="FL Shortcut"       # nom d'avant : ses copies sont retirées à l'installation
EXE="FLShortcut"
APP="dist/${APP_NAME}.app"
DMG="dist/FLShortcuts.dmg"
ARCHS=(--arch arm64 --arch x86_64)
# FLS_NATIVE=1 : architecture de cette machine seulement (suffit pour tester ; marche aussi sans Xcode complet).
if [[ "${FLS_NATIVE:-0}" == "1" ]]; then ARCHS=(); fi

if [[ "${FLS_SKIP_TESTS:-0}" != "1" ]]; then
  echo "▸ Tests"
  swift test
fi

# Kit de compilation : celui de macOS 26, comme GitHub (Xcode 26.6) pour toutes les versions d'avant. Avec le kit 27
# (Xcode 27 sur le Mac du propriétaire), macOS 27 dessine l'app autrement (boutons en rectangle arrondi, barres…) :
# s'il est le kit par défaut et qu'un kit 26 est installé (outils en ligne de commande, Xcode), on prend le 26.
# SDKROOT=… : ce kit-là ; FLS_SDK=defaut : garder le kit par défaut.
KIT="${SDKROOT:-}"
if [[ -z "$KIT" && "${FLS_SDK:-}" != "defaut" ]]; then
  DEFAULT_SDK=$(xcrun --sdk macosx --show-sdk-version 2>/dev/null || echo 0)
  if (( ${DEFAULT_SDK%%.*} > 26 )); then
    KIT=$(ls -d /Library/Developer/CommandLineTools/SDKs/MacOSX26.*.sdk \
                "$(xcode-select -p 2>/dev/null)"/Platforms/MacOSX.platform/Developer/SDKs/MacOSX26.*.sdk 2>/dev/null \
          | sort -V | tail -1 || true)
    [[ -n "$KIT" ]] || echo "  (aucun kit de macOS 26 installé : kit $DEFAULT_SDK, l'app aura un autre aspect)"
  fi
fi

echo "▸ Compilation release"
if [[ -n "$KIT" ]]; then
  # Une architecture à la fois, avec le système de compilation propre à SwiftPM (« native ») : il prend ce kit et
  # inscrit sa version dans l'app. Celui d'Xcode compilait avec ce kit mais inscrivait « sdk 13.0 », et celui de
  # Swift 6.4 (Xcode 27, par défaut) rangeait les deux architectures au même endroit.
  echo "  kit : $KIT"
  PARTS=()
  for A in arm64 x86_64; do
    if [[ "${FLS_NATIVE:-0}" == "1" && "$A" != "$(uname -m)" ]]; then continue; fi
    SDKROOT="$KIT" swift build -c release --build-system native --arch "$A"
    P="$(SDKROOT="$KIT" swift build -c release --build-system native --arch "$A" --show-bin-path)/$EXE"
    [[ "$(lipo -archs "$P")" == "$A" ]] || { echo "✗ $P n'est pas pour $A ($(lipo -archs "$P"))" >&2; exit 1; }
    PARTS+=("$P")
  done
  BIN_DIR=".build/universel"
  mkdir -p "$BIN_DIR"
  lipo -create -output "$BIN_DIR/$EXE" "${PARTS[@]}"
else
  swift build -c release ${ARCHS[@]+"${ARCHS[@]}"}
  BIN_DIR=$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)
fi

echo "▸ Assemblage de l'app"
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/$EXE" "$APP/Contents/MacOS/$EXE"
# Kit inscrit dans l'app, celui qui décide de son aspect sur macOS 26 et plus (chaque architecture). Un kit choisi
# qui n'est pas celui inscrit arrête tout : l'app n'aurait pas l'aspect voulu.
if command -v vtool >/dev/null 2>&1; then
  INSCRIT=$(vtool -show-build "$APP/Contents/MacOS/$EXE" 2>/dev/null | awk '$1 == "sdk" { print $2 }' | sort -u | tr '\n' ' ')
  echo "  kit inscrit dans l'app : macOS ${INSCRIT:-?}"
  if [[ -n "$KIT" ]]; then
    VOULU=$(basename "$KIT" .sdk)
    VOULU=${VOULU#MacOSX}
    for V in $INSCRIT; do
      [[ "${V%%.*}" == "${VOULU%%.*}" ]] || { echo "✗ kit inscrit ($V) différent du kit choisi ($VOULU)" >&2; exit 1; }
    done
  fi
fi
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
# Aide : adresse de l'équipe pour « Envoyer par mail » quand le serveur n'est pas branché (ou en cas d'échec).
if [[ -n "${FLS_SUPPORT_EMAIL:-}" ]]; then
  plutil -replace FLSSupportEmail -string "$FLS_SUPPORT_EMAIL" "$APP/Contents/Info.plist"
fi
cp Resources/device_FLShortcut.py "$APP/Contents/Resources/"
# Textes de l'app dans la langue du Mac (anglais pour toute langue autre que le français).
cp -R Resources/en.lproj Resources/fr.lproj "$APP/Contents/Resources/"
# Un fichier illisible par macOS ferait tout retomber en français : la compilation s'arrête.
plutil -lint -s "$APP"/Contents/Resources/*.lproj/*.strings
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Les icônes de FL (grille « Change icon… »), pour le choix d'icône de l'Organiser et du bloc « Nom et couleur ».
cp Resources/FLIcons.png "$APP/Contents/Resources/FLIcons.png"
cp Resources/MIDISettings.png "$APP/Contents/Resources/MIDISettings.png"   # fenêtre MIDI Settings entourée (lien avec FL)
# IA intégrée de l'Organiser (famille et sorte des sons) : le modèle Core ML compilé ici ; sans compilateur (outils
# sans Xcode), le paquet est copié tel quel et l'app le compile à sa première écoute.
if [[ -d Resources/ClasseurSons.mlpackage ]]; then
  if xcrun coremlcompiler compile Resources/ClasseurSons.mlpackage "$APP/Contents/Resources/" >/dev/null 2>&1; then
    echo "▸ IA intégrée : modèle compilé"
  else
    cp -R Resources/ClasseurSons.mlpackage "$APP/Contents/Resources/"
    echo "▸ IA intégrée : modèle copié (compilé par l'app à la première écoute)"
  fi
  cp ia/modele/CREDITS.md "$APP/Contents/Resources/ClasseurSons-CREDITS.md"
  cp ia/modele/LICENCE-YAMNET.txt "$APP/Contents/Resources/ClasseurSons-LICENCE-YAMNET.txt"
fi
chmod -R go-w "$APP"

# Identité de signature locale, créée une seule fois dans un trousseau dédié (jamais le trousseau de session) :
# certificat auto-signé « FL Shortcut Dev », usage « signature de code » uniquement, valable sur ce Mac.
# Ancien nom de l'app gardé exprès : une autre identité ferait redemander l'autorisation Accessibilité.
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

echo "▸ Paquet d'installation (.pkg) : FL Shortcuts dans /Applications, en un double-clic"
PKG="dist/FLShortcuts.pkg"
PKG_ROOT=$(mktemp -d)
PKG_PLIST=$(mktemp -d)/component.plist
cp -R "$APP" "$PKG_ROOT/"
pkgbuild --analyze --root "$PKG_ROOT" "$PKG_PLIST" >/dev/null
# Toujours dans /Applications : sans cela, Installer « met à jour » une autre copie du même identifiant
# (par exemple un build de développement dans ~/Applications) au lieu d'installer celle-ci.
n=0
# (Sortie lue sur la sortie standard puis jetée : avec « -o /dev/null », le plutil de macOS 27 écrivait
# « write: Permission denied » à chaque entrée.)
while plutil -extract "$n" xml1 -o - "$PKG_PLIST" >/dev/null 2>&1; do
  plutil -replace "$n.BundleIsRelocatable" -bool NO "$PKG_PLIST"
  n=$((n + 1))
done
# Après l'installation : retire les copies à l'ancien nom (« FL Shortcut ») et les anciens désinstalleurs à part
# (on désinstalle maintenant depuis le menu de l'app), seulement si ce sont bien les nôtres (identifiant vérifié).
PKG_SCRIPTS=$(mktemp -d)
cat > "$PKG_SCRIPTS/postinstall" <<SCRIPT
#!/bin/bash
for pair in "${OLD_APP_NAME}.app:app.flshortcut.FLShortcut" "Désinstaller ${OLD_APP_NAME}.app:app.flshortcut.Uninstaller" \
            "Désinstaller ${APP_NAME}.app:app.flshortcut.Uninstaller"; do
  app="\${3%/}/Applications/\${pair%%:*}"
  [[ -d "\$app" && ! -L "\$app" ]] || continue
  id=\$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "\$app/Contents/Info.plist" 2>/dev/null)
  [[ "\$id" == "\${pair##*:}" ]] && rm -rf "\$app"
done
# L'app appartient à la personne connectée, comme une app glissée depuis un .dmg : elle la désinstalle sans mot de
# passe. Le reçu du .pkg (écrit par Installer après ce script) est oublié juste après : rien ne reste au système.
user=\$(/usr/bin/stat -f%Su /dev/console 2>/dev/null)
app="\${3%/}/Applications/${APP_NAME}.app"
if [[ -n "\$user" && "\$user" != root && -d "\$app" && ! -L "\$app" ]]; then
  /usr/sbin/chown -R "\$user":staff "\$app"
fi
( sleep 8; /usr/sbin/pkgutil --forget app.flshortcut.pkg ) </dev/null >/dev/null 2>&1 &
disown 2>/dev/null || true
exit 0
SCRIPT
chmod 755 "$PKG_SCRIPTS/postinstall"
PKG_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
pkgbuild --root "$PKG_ROOT" --component-plist "$PKG_PLIST" --install-location /Applications \
  --scripts "$PKG_SCRIPTS" \
  --identifier app.flshortcut.pkg --version "$PKG_VERSION" "dist/FLShortcuts-component.pkg" >/dev/null
if [[ -n "${INSTALLER_SIGN_IDENTITY:-}" ]]; then
  productbuild --package "dist/FLShortcuts-component.pkg" --sign "$INSTALLER_SIGN_IDENTITY" "$PKG"
else
  productbuild --package "dist/FLShortcuts-component.pkg" "$PKG"
fi
rm -rf "$PKG_ROOT" "$PKG_SCRIPTS" "dist/FLShortcuts-component.pkg"

echo "▸ Empreintes"
(cd dist && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256" \
  && shasum -a 256 "$(basename "$PKG")" > "$(basename "$PKG").sha256")
cat "$DMG.sha256" "$PKG.sha256"

echo "✅ Terminé : $APP, $DMG et $PKG"

# Build local (FLS_NATIVE=1) : copie aussi l'app dans ~/Applications pour la lancer comme une vraie app.
if [[ "${FLS_NATIVE:-0}" == "1" ]]; then
  mkdir -p "$HOME/Applications"
  rm -rf "$HOME/Applications/${APP_NAME}.app" "$HOME/Applications/${OLD_APP_NAME}.app"
  cp -R "$APP" "$HOME/Applications/"
  echo "▸ Installé dans ~/Applications"
fi
