-- Essai de messages-par-mail.sql recollé tel quel, sans rien remplacer (lancé par supabase/tests/run.sh après
-- messages-par-mail.sql) : la vraie clé et la vraie adresse restent ; un message envoyé connecté dit le pseudo.
\set ON_ERROR_STOP on

-- pg_net remis (l'essai d'avant l'avait coupé).
create or replace function net.http_post(url text, body jsonb default '{}', params jsonb default '{}',
                                         headers jsonb default '{}', timeout_milliseconds integer default 5000)
returns bigint language sql as $$
  insert into net.calls (url, body, headers) values (url, body, headers) returning id
$$;

do $$
begin
  if (select decrypted_secret from vault.decrypted_secrets where name = 'fls_resend_key') <> 're_essai' then
    raise exception 'clé effacée en recollant le fichier';
  end if;
  if (select decrypted_secret from vault.decrypted_secrets where name = 'fls_support_to') <> 'flshortcuts@exemple.fr' then
    raise exception 'adresse effacée en recollant le fichier';
  end if;
end $$;

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000f', 'mail.essai@exemple.fr', '{"username":"mail_essai"}')
  on conflict (id) do nothing;
insert into public.profiles (id, username) values ('00000000-0000-0000-0000-00000000000f', 'mail_essai')
  on conflict (id) do update set username = excluded.username;

set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-00000000000f';
insert into public.support_requests (kind, message, app_version) values ('question', 'Connecté, ça se voit ?', '0.2.0');
reset role;
set request.jwt.claim.sub to '';

do $$
declare
  appel record;
begin
  select * into appel from net.calls order by id desc limit 1;
  if position('Compte : connecté (mail_essai)' in appel.body ->> 'text') = 0 then
    raise exception 'compte ou pseudo absent du mail : %', appel.body ->> 'text';
  end if;
end $$;
select 'messages par mail recollés : tout est conforme' as resultat;
