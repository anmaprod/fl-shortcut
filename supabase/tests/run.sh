#!/bin/bash
# Essaie supabase/schema.sql sur un PostgreSQL ordinaire, dans une base jetable : ce que Supabase fournit
# (supabase-stubs.sql), le schéma tel qu'il sera collé dans Supabase, puis chaque règle d'accès (policies.sql).
# Usage : supabase/tests/run.sh [options de psql pour joindre le serveur, par ex. -h /tmp -p 5432 -U postgres]
set -euo pipefail
cd "$(dirname "$0")"
DB="fls_communaute_essai_$$"
createdb "$@" "$DB"
trap 'dropdb "$@" "$DB" >/dev/null 2>&1 || true' EXIT
for f in supabase-stubs.sql ../schema.sql policies.sql; do
  psql "$@" -d "$DB" -X -q -v ON_ERROR_STOP=1 -f "$f"
done
