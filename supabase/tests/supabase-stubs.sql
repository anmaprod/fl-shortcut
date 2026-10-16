-- Ce que Supabase fournit déjà, pour essayer schema.sql sur un PostgreSQL ordinaire (supabase/tests/run.sh) :
-- rôles anon et authenticated, auth.users, auth.uid() lu dans le jeton (request.jwt.claim.sub), droits par défaut
-- de Supabase (tout est accordé à anon et authenticated : ce sont les règles RLS qui protègent).
create role anon nologin;
create role authenticated nologin;
grant anon, authenticated to current_user;

create schema auth;
grant usage on schema auth to anon, authenticated;
create table auth.users (
  id uuid primary key default gen_random_uuid(),
  email text,
  raw_user_meta_data jsonb not null default '{}'
);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
grant execute on function auth.uid() to anon, authenticated;

grant usage on schema public to anon, authenticated;
alter default privileges in schema public grant all on tables to anon, authenticated;
alter default privileges in schema public grant all on sequences to anon, authenticated;
alter default privileges in schema public grant execute on functions to anon, authenticated;
