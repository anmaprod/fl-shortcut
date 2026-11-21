-- Essai de protection.sql (lancé par supabase/tests/run.sh, après mes-messages.sql) : plus de message sans compte,
-- tables pleines refusées, 10 captures par jour, captures effacées au bout de 180 jours. Comptes d'essai à part
-- (flshortcuts 0…0e1, Tom 0…0e2).
\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000e1', 'flshortcuts@exemple.fr', '{"username":"flshortcuts_essai"}'),
  ('00000000-0000-0000-0000-0000000000e2', 'tom2@exemple.fr', '{"username":"tom2_essai"}')
  on conflict (id) do nothing;
insert into public.profiles (id, username) values
  ('00000000-0000-0000-0000-0000000000e1', 'flshortcuts_essai'), ('00000000-0000-0000-0000-0000000000e2', 'tom2_essai')
  on conflict (id) do update set username = excluded.username;

-- 1. Sans compte : refusé. Avec un compte : accepté, à son nom seulement.
set role anon;
reset request.jwt.claim.sub;
do $$
begin
  insert into public.support_requests (kind, message) values ('question', 'Une question sans compte.');
  raise exception 'message sans compte accepté';
exception when insufficient_privilege then null;
end $$;
reset role;

set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-0000000000e1';
insert into public.support_requests (kind, message) values ('question', 'Une question avec mon compte.');
do $$
begin
  insert into public.support_requests (user_id, kind, message)
    values ('00000000-0000-0000-0000-0000000000e2', 'question', 'Au nom de quelqu''un d''autre.');
  raise exception 'message au nom d''un autre accepté';
exception when insufficient_privilege then null;
end $$;
reset role;

-- 2. Une table plus grosse que la limite est pleine ; la vraie limite (200 Mo) n'est pas atteinte ici.
do $$
begin
  if not public.fls_table_pleine('public.support_requests', 1) then raise exception 'table pleine pas vue'; end if;
  if public.fls_table_pleine('public.support_requests', 200 * 1024 * 1024) then raise exception 'table vide vue pleine'; end if;
end $$;

-- 10 captures par jour et par compte : la 11e est refusée (limite par heure de schema.sql mise de côté pour l'essai).
alter table public.support_requests disable trigger support_limit;
set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-0000000000e2';
do $$
begin
  for i in 1..10 loop
    insert into public.support_requests (kind, message, capture) values ('probleme', 'Capture numéro ' || i, '/9j/4AAQSkZJRg==');
  end loop;
  begin
    insert into public.support_requests (kind, message, capture) values ('probleme', 'Capture de trop.', '/9j/4AAQSkZJRg==');
    raise exception '11e capture du jour acceptée';
  exception when raise_exception then
    if sqlerrm not like 'Trop de captures%' then raise; end if;
  end;
  -- Sans capture, le message passe encore.
  insert into public.support_requests (kind, message) values ('probleme', 'Message sans capture.');
end $$;
reset role;
alter table public.support_requests enable trigger support_limit;

-- 3. Captures de plus de 180 jours effacées, messages gardés ; les récentes restent.
update public.support_requests set created_at = now() - interval '200 days'
  where user_id = '00000000-0000-0000-0000-0000000000e2' and message = 'Capture numéro 1';
do $$
declare
  n integer;
begin
  n := public.purge_old_captures();
  if n <> 1 then raise exception 'captures effacées : % (1 attendue)', n; end if;
  if (select capture from public.support_requests
      where user_id = '00000000-0000-0000-0000-0000000000e2' and message = 'Capture numéro 1') is not null then
    raise exception 'vieille capture gardée';
  end if;
  if (select count(*) from public.support_requests
      where user_id = '00000000-0000-0000-0000-0000000000e2' and capture is not null) <> 9 then
    raise exception 'captures récentes effacées';
  end if;
end $$;

-- Personne ne lance les fonctions de protection depuis l'app.
set role authenticated;
do $$
begin
  perform public.purge_old_captures();
  raise exception 'purge lancée depuis l''app';
exception when insufficient_privilege then null;
end $$;
reset role;

-- 4. Compte supprimé : ses messages et leurs réponses partent avec lui ; ceux des autres restent.
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000e3', 'parti@exemple.fr', '{"username":"parti_essai"}')
  on conflict (id) do nothing;
insert into public.support_requests (id, user_id, kind, message, email) values
  ('00000000-0000-0000-0000-00000000e3a1', '00000000-0000-0000-0000-0000000000e3', 'question', 'Un message avant de partir.', 'parti@exemple.fr');
insert into public.support_replies (request_id, team, message) values ('00000000-0000-0000-0000-00000000e3a1', true, 'Réponse.');
delete from auth.users where id = '00000000-0000-0000-0000-0000000000e3';
do $$
begin
  if exists (select 1 from public.support_requests where id = '00000000-0000-0000-0000-00000000e3a1') then
    raise exception 'message gardé après la suppression du compte';
  end if;
  if exists (select 1 from public.support_replies where request_id = '00000000-0000-0000-0000-00000000e3a1') then
    raise exception 'réponse gardée après la suppression du compte';
  end if;
  if not exists (select 1 from public.support_requests where user_id = '00000000-0000-0000-0000-0000000000e1') then
    raise exception 'messages des autres effacés';
  end if;
end $$;

select 'protection : tout est conforme' as resultat;
