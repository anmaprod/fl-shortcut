-- Ce que Supabase fournit pour messages-par-mail.sql, sur un PostgreSQL ordinaire (supabase/tests/run.sh) : le coffre
-- (vault : secrets, create_secret, update_secret, decrypted_secrets, sans vrai chiffrement ici) et pg_net
-- (net.http_post), qui ne fait que noter l'appel dans net.calls.
create schema vault;
create table vault.secrets (
  id uuid primary key default gen_random_uuid(),
  name text unique,
  description text not null default '',
  secret text not null
);
create function vault.create_secret(new_secret text, new_name text default null, new_description text default '')
returns uuid language sql as $$
  insert into vault.secrets (secret, name, description) values (new_secret, new_name, new_description) returning id
$$;
create function vault.update_secret(secret_id uuid, new_secret text default null, new_name text default null,
                                    new_description text default null)
returns void language sql as $$
  update vault.secrets set secret = coalesce(new_secret, secret), name = coalesce(new_name, name),
                           description = coalesce(new_description, description) where id = secret_id
$$;
create view vault.decrypted_secrets as select id, name, description, secret as decrypted_secret from vault.secrets;

create schema net;
create table net.calls (id bigserial primary key, url text, body jsonb, headers jsonb);
create function net.http_post(url text, body jsonb default '{}', params jsonb default '{}',
                              headers jsonb default '{}', timeout_milliseconds integer default 5000)
returns bigint language sql as $$
  insert into net.calls (url, body, headers) values (url, body, headers) returning id
$$;
