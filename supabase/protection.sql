-- Protection du serveur (21/11, « rendre ce logiciel très sécurisé ») : à coller dans Supabase › SQL Editor APRÈS
-- schema.sql, corrections-ia.sql et mes-messages.sql (supabase/README.md, étape 14). Peut être recollé sans risque ;
-- à recoller aussi après un recollage de schema.sql (la règle des messages y est écrite à l'ancienne).
--
-- 1. « Écrire à l'équipe » seulement avec un compte (l'app le demande depuis le 20/11, Mac et Windows). Sans compte,
--    n'importe qui pouvait envoyer 100 messages par heure (la limite de tout le monde) et bloquer l'aide de tous.
-- 2. La base gratuite (500 Mo) ne peut plus être remplie par une seule personne : une capture pèse jusqu'à 1 Mo, une
--    correction de l'IA jusqu'à 26 Ko ; au-delà d'une taille (200 Mo de messages, 150 Mo de corrections), plus rien
--    n'est ajouté (le reste du serveur continue de marcher) ; 10 captures par jour et par compte au plus.
-- 3. Les captures sont effacées 180 jours après le message (RGPD : rien n'est gardé sans durée), chaque nuit, par
--    pg_cron (Supabase › Integrations › Cron ; activé ici s'il est disponible).

-- Taille d'une table (données, index, TOAST) au-delà de `max_bytes` : rien n'y est plus ajouté.
create or replace function public.fls_table_pleine(tbl regclass, max_bytes bigint) returns boolean
language sql stable set search_path = '' as $$
  select pg_catalog.pg_total_relation_size(tbl) > max_bytes
$$;
revoke all on function public.fls_table_pleine(regclass, bigint) from public, anon, authenticated;

-- 1. Messages à l'équipe : un compte connecté, le sien.
drop policy if exists "chacun écrit à l'équipe" on public.support_requests;
create policy "chacun écrit à l'équipe" on public.support_requests
  for insert to authenticated with check (user_id = auth.uid());

-- 2. Taille des messages et des captures.
create or replace function public.limit_support_size() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.fls_table_pleine('public.support_requests', 200 * 1024 * 1024) then
    raise exception 'Trop de messages en ce moment : réessaie plus tard.';
  end if;
  if new.capture is not null and (select count(*) from public.support_requests
       where user_id = new.user_id and capture is not null and created_at > now() - interval '1 day') >= 10 then
    raise exception 'Trop de captures aujourd''hui : envoie ton message sans capture.';
  end if;
  return new;
end;
$$;
revoke all on function public.limit_support_size() from public, anon, authenticated;
drop trigger if exists support_size on public.support_requests;
create trigger support_size before insert on public.support_requests
  for each row execute function public.limit_support_size();

create or replace function public.limit_corrections_size() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if public.fls_table_pleine('public.corrections_ia', 150 * 1024 * 1024) then
    raise exception 'Merci ! Assez de corrections pour l''instant.';
  end if;
  return new;
end;
$$;
revoke all on function public.limit_corrections_size() from public, anon, authenticated;
drop trigger if exists corrections_size on public.corrections_ia;
create trigger corrections_size before insert on public.corrections_ia
  for each row execute function public.limit_corrections_size();

-- 3. Captures effacées au bout de 180 jours (le message reste). Rendu : le nombre de captures effacées.
create or replace function public.purge_old_captures() returns integer
language plpgsql security definer set search_path = public as $$
declare
  n integer;
begin
  update public.support_requests set capture = null
    where capture is not null and created_at < now() - interval '180 days';
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke all on function public.purge_old_captures() from public, anon, authenticated;

-- 4. « Supprimer mon compte » efface aussi ses messages à l'équipe et leurs réponses : depuis le 20/11, le mail du
--    compte y est joint tout seul ; il ne doit pas rester après la suppression (avant : messages gardés, sans lien).
alter table public.support_requests drop constraint if exists support_requests_user_id_fkey;
alter table public.support_requests add constraint support_requests_user_id_fkey
  foreign key (user_id) references auth.users (id) on delete cascade;

do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    create extension if not exists pg_cron;
    perform cron.unschedule(jobid) from cron.job where jobname = 'fls-captures-180-jours';
    perform cron.schedule('fls-captures-180-jours', '23 3 * * *', 'select public.purge_old_captures()');
  end if;
end $$;

-- 5. Conseils du Security Advisor de Supabase (24/11, 33 avertissements, aucune erreur) :
--    - les fonctions des déclencheurs ne s'appellent plus de dehors (/rest/v1/rpc/…) : un déclencheur les lance sans
--      ce droit (vérifié sur PostgreSQL 16) ;
--    - creator_score a un search_path fixe ;
--    - pg_net quitte le schéma public (il ne se déplace pas : retiré puis remis dans « extensions » ; ses fonctions
--      restent dans « net », le mail des messages à l'équipe continue de marcher).
--    Gardés exprès : is_admin (lu par les règles d'accès), username_available (pseudo libre, avant de créer son
--    compte), et les fonctions que l'app appelle avec un compte (noter, ajouter, pseudo, photo, supprimer son compte).
do $$
declare
  f text;
begin
  foreach f in array array['public.count_adds()', 'public.count_follows()', 'public.count_ratings()',
                           'public.handle_confirmed_user()', 'public.handle_new_user()', 'public.limit_corrections()',
                           'public.limit_follows()', 'public.limit_shares()', 'public.limit_support()',
                           'public.limit_support_size()', 'public.limit_corrections_size()', 'public.fill_rating_half()'] loop
    if to_regprocedure(f) is not null then
      execute format('revoke all on function %s from public, anon, authenticated', f);
    end if;
  end loop;
  if to_regprocedure('public.creator_score(bigint, bigint)') is not null then
    alter function public.creator_score(bigint, bigint) set search_path = '';
  end if;
end $$;

-- pg_net à part : si Supabase refuse de le retirer (il ne le doit pas), tout le reste ci-dessus est déjà fait.
do $$
begin
  if exists (select 1 from pg_extension where extname = 'pg_net' and extnamespace = 'public'::regnamespace)
     and exists (select 1 from pg_namespace where nspname = 'extensions') then
    drop extension pg_net;
    create extension pg_net with schema extensions;
  end if;
exception when others then
  raise notice 'pg_net laissé dans public (%), rien d''autre n''est touché', sqlerrm;
end $$;
