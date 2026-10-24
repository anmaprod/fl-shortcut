-- Inscription en deux temps : le compte n'existe pour FL Shortcuts (profil, nom d'utilisateur) qu'une fois le code
-- du mail entré dans l'app. Avant, rien n'est gardé : ni le nom (libre pour les autres), ni l'inscription, effacée
-- au bout de 24 h si le code n'est jamais entré (le mail redevient libre).
-- À coller dans Supabase › SQL Editor après schema.sql (nouveau projet), ou seul sur un projet déjà installé : il
-- remplace l'ancienne création du profil dès l'inscription. Peut être relancé sans risque.
-- Supabase garde l'inscription en attente dans auth.users (sans elle, pas de code à envoyer) : elle ne peut ni se
-- connecter, ni publier, ni sauvegarder tant que le code n'est pas entré.

-- Inscription : nom d'utilisateur valide et libre, sinon refusée tout de suite (message clair dans l'app). Le profil
-- n'est créé ici que pour un compte déjà confirmé (créé à la main dans Supabase, ou « Confirm email » désactivé).
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  name text := new.raw_user_meta_data ->> 'username';
begin
  if name is null or name !~ '^[A-Za-z0-9_.-]{3,24}$' then
    raise exception 'nom d''utilisateur invalide' using errcode = 'check_violation';
  end if;
  if exists (select 1 from public.profiles where lower(username) = lower(name)) then
    raise exception 'nom d''utilisateur déjà pris' using errcode = 'unique_violation';
  end if;
  if new.email_confirmed_at is not null then
    insert into public.profiles (id, username) values (new.id, name);
  end if;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Code du mail entré (adresse confirmée) : le profil est créé avec le nom choisi. Pris entre-temps par quelqu'un qui
-- a confirmé avant : le même nom suivi de 4 caractères (« nina_3f2a »), jamais une confirmation qui échoue.
create or replace function public.handle_confirmed_user() returns trigger
language plpgsql security definer set search_path = public as $$
declare
  wanted text := new.raw_user_meta_data ->> 'username';
  name text := wanted;
begin
  if old.email_confirmed_at is not null or new.email_confirmed_at is null
     or exists (select 1 from public.profiles where id = new.id) then
    return new;
  end if;
  if name is null or name !~ '^[A-Za-z0-9_.-]{3,24}$' then name := 'membre'; end if;
  if exists (select 1 from public.profiles where lower(username) = lower(name)) then
    name := left(name, 19) || '_' || left(replace(new.id::text, '-', ''), 4);
  end if;
  insert into public.profiles (id, username) values (new.id, name);
  if name is distinct from wanted then
    new.raw_user_meta_data := coalesce(new.raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('username', name);
  end if;
  return new;
end;
$$;
drop trigger if exists on_auth_user_confirmed on auth.users;
create trigger on_auth_user_confirmed before update on auth.users
  for each row execute function public.handle_confirmed_user();

-- Inscriptions jamais confirmées : effacées au bout de 24 h. Lancé toutes les heures par pg_cron (ci-dessous) ;
-- jamais par l'app ni par un visiteur.
create or replace function public.forget_unconfirmed_signups() returns integer
language sql security definer set search_path = public as $$
  with gone as (
    delete from auth.users
    where email_confirmed_at is null and created_at < now() - interval '24 hours'
    returning 1
  )
  select count(*)::integer from gone
$$;
revoke all on function public.forget_unconfirmed_signups() from public, anon, authenticated;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron with schema pg_catalog;
    perform cron.unschedule(jobid) from cron.job where jobname = 'fls-inscriptions-non-confirmees';
    perform cron.schedule('fls-inscriptions-non-confirmees', '17 * * * *',
                          'select public.forget_unconfirmed_signups()');
  else
    raise notice 'pg_cron absent : les inscriptions non confirmées ne sont pas effacées toutes seules.';
  end if;
exception when others then
  raise notice 'pg_cron non programmé (%) : active « Cron » dans Supabase › Integrations, puis relance ce fichier.', sqlerrm;
end $$;

-- Projet déjà installé : les noms gardés par des inscriptions jamais confirmées redeviennent libres.
delete from public.profiles p using auth.users u where p.id = u.id and u.email_confirmed_at is null;
