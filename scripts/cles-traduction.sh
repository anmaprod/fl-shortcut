#!/bin/bash
# Textes de l'app à traduire, tels que le compilateur les voit (Text("…"), String(localized: "…")…), comparés à
# Resources/en.lproj : combien sont traduits, lesquels manquent. Compilation à part (.build/loc), sans toucher au
# reste. Usage : scripts/cles-traduction.sh dossier-de-sortie [--strict]
set -uo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-dist/mesure}"
shift || true
LOC="$PWD/.build/loc-strings"
rm -rf "$LOC"
mkdir -p "$LOC" "$OUT"

build() { swift build --scratch-path .build/loc "$@" > "$OUT/cles-compilation.txt" 2>&1; }
build -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$LOC"
if [[ -z "$(find "$LOC" -name '*.stringsdata' -print -quit)" ]]; then
  # Option passée directement au compilateur de chaque fichier (anciens pilotes swiftc).
  build -Xswiftc -Xfrontend -Xswiftc -emit-localized-strings \
        -Xswiftc -Xfrontend -Xswiftc -emit-localized-strings-path -Xswiftc -Xfrontend -Xswiftc "$LOC"
fi
if ! python3 scripts/localisation.py extraire "$LOC" "$OUT/cles.json" >&2; then
  echo "Aucune clé extraite : voir cles-compilation.txt" >&2
  tail -40 "$OUT/cles-compilation.txt" >&2
  exit 1
fi
python3 scripts/localisation.py verifier "$OUT/cles.json" "$@"
