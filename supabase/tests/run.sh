#!/bin/bash
# Essaie supabase/schema.sql, inscription.sql, sauvegarde.sql, corrections-ia.sql, profil.sql et messages-par-mail.sql sur un PostgreSQL
# ordinaire, dans une base jetable : ce que Supabase fournit (supabase-stubs.sql), les fichiers tels qu'ils seront
# collés dans Supabase (corrections-ia.sql et profil.sql deux fois : ils doivent pouvoir être recollés), puis chaque
# règle (policies.sql, profil.sql, regles-sauvegarde.sql, inscription.sql, corrections-ia.sql).
# Usage : supabase/tests/run.sh [options de psql pour joindre le serveur, par ex. -h /tmp -p 5432 -U postgres]
set -euo pipefail
cd "$(dirname "$0")"
DB="fls_communaute_essai_$$"
createdb "$@" "$DB"
trap 'dropdb "$@" "$DB" >/dev/null 2>&1 || true' EXIT
# messages-par-mail.sql : sans la ligne de pg_net (absent d'un PostgreSQL ordinaire : supabase-stubs-mail.sql le
# remplace), collé deux fois (il doit pouvoir être recollé).
MAIL="$(mktemp)"
trap 'rm -f "$MAIL"; dropdb "$@" "$DB" >/dev/null 2>&1 || true' EXIT
sed '/^create extension if not exists pg_net;/d' ../messages-par-mail.sql > "$MAIL"
for f in supabase-stubs.sql supabase-stubs-mail.sql ../schema.sql ../inscription.sql ../sauvegarde.sql \
         ../corrections-ia.sql ../corrections-ia.sql ../profil.sql ../profil.sql "$MAIL" "$MAIL" policies.sql \
         profil.sql regles-sauvegarde.sql inscription.sql corrections-ia.sql messages-par-mail.sql "$MAIL" \
         messages-par-mail-recolle.sql communaute-suivre-11-11.sql communaute-suivre.sql ../communaute-suivre.sql \
         ../communaute-suivre.sql communaute-relations.sql communaute-suivre-recolle.sql; do
  psql "$@" -d "$DB" -X -q -v ON_ERROR_STOP=1 -f "$f"
done
# Ci-dessus, la base du propriétaire : communaute-suivre.sql collé le 11/11 (copie communaute-suivre-11-11.sql), ses
# essais avec des lignes, puis le fichier d'aujourd'hui recollé dessus (12/11 : il doit réparer les liens entre
# partages et profils sans rien perdre). Ici, une installation neuve : le fichier d'aujourd'hui seul.
NEUVE="${DB}_neuve"
createdb "$@" "$NEUVE"
trap 'rm -f "$MAIL"; dropdb "$@" "$DB" >/dev/null 2>&1 || true; dropdb "$@" "$NEUVE" >/dev/null 2>&1 || true' EXIT
for f in supabase-stubs.sql ../schema.sql ../inscription.sql ../profil.sql ../communaute-suivre.sql \
         ../communaute-suivre.sql communaute-suivre.sql communaute-relations.sql; do
  psql "$@" -d "$NEUVE" -X -q -v ON_ERROR_STOP=1 -f "$f"
done
