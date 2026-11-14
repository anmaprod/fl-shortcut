-- Ce que Supabase fournit déjà, pour essayer schema.sql sur un PostgreSQL ordinaire (supabase/tests/run.sh) :
-- rôles anon et authenticated, auth.users, auth.uid() lu dans le jeton (request.jwt.claim.sub), droits par défaut
-- de Supabase (tout est accordé à anon et authenticated : ce sont les règles RLS qui protègent).
-- Rôles communs à tout le serveur PostgreSQL : créés une fois (un deuxième essai les retrouve).
do $$
begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end $$;
grant anon, authenticated to current_user;

create schema auth;
grant usage on schema auth to anon, authenticated;
create table auth.users (
  id uuid primary key default gen_random_uuid(),
  email text,
  raw_user_meta_data jsonb not null default '{}',
  email_confirmed_at timestamptz,
  created_at timestamptz not null default now()
);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;
grant execute on function auth.uid() to anon, authenticated;

grant usage on schema public to anon, authenticated;
alter default privileges in schema public grant all on tables to anon, authenticated;
alter default privileges in schema public grant all on sequences to anon, authenticated;
alter default privileges in schema public grant execute on functions to anon, authenticated;
