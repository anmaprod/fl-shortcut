#!/bin/bash
# Essaie supabase/schema.sql, inscription.sql et sauvegarde.sql sur un PostgreSQL ordinaire, dans une base jetable :
# ce que Supabase fournit (supabase-stubs.sql), les fichiers tels qu'ils seront collés dans Supabase, puis chaque
# règle (policies.sql, regles-sauvegarde.sql, inscription.sql).
# Usage : supabase/tests/run.sh [options de psql pour joindre le serveur, par ex. -h /tmp -p 5432 -U postgres]
set -euo pipefail
cd "$(dirname "$0")"
DB="fls_communaute_essai_$$"
createdb "$@" "$DB"
trap 'dropdb "$@" "$DB" >/dev/null 2>&1 || true' EXIT
for f in supabase-stubs.sql ../schema.sql ../inscription.sql ../sauvegarde.sql policies.sql regles-sauvegarde.sql \
         inscription.sql; do
  psql "$@" -d "$DB" -X -q -v ON_ERROR_STOP=1 -f "$f"
done
