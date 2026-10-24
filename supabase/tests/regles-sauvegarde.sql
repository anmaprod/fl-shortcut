-- Essai des règles de sauvegarde.sql (lancé par supabase/tests/run.sh, après policies.sql : comptes de Malo et
-- de Léo déjà créés). Chaque vérification qui échoue arrête tout (ON_ERROR_STOP) avec un message clair.
\set ON_ERROR_STOP on

-- Sans compte : rien de lisible, rien d'enregistrable.
set role anon;
set request.jwt.claim.sub to '';
do $$
begin
  if (select count(*) from public.backups) <> 0 then raise exception 'anon lit les sauvegardes'; end if;
  begin
    perform public.save_backup('{}', '{}', 0);
    raise exception 'anon enregistre une sauvegarde';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- Malo : première sauvegarde (révision 1), puis 2 ; un Mac resté à la révision 1 est refusé, sauf s'il force.
set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-00000000000a';
do $$
declare r bigint;
begin
  r := public.save_backup('{"profil":1}', '{"macros":1}', 0, false, '0.2.0');
  if r <> 1 then raise exception 'première sauvegarde : révision % au lieu de 1', r; end if;
  r := public.save_backup('{"profil":2}', '{"macros":2}', 1);
  if r <> 2 then raise exception 'deuxième sauvegarde : révision % au lieu de 2', r; end if;
  begin
    perform public.save_backup('{"profil":"ancien Mac"}', '{}', 1);
    raise exception 'sauvegarde plus récente écrasée sans le savoir';
  exception when raise_exception then
    if sqlerrm not like 'Sauvegarde plus récente%' then raise; end if;
  end;
  if (select profile from public.backups) <> '{"profil":2}' then raise exception 'sauvegarde modifiée par un refus'; end if;
  r := public.save_backup('{"profil":3}', '{"macros":3}', 1, true);
  if r <> 3 then raise exception 'sauvegarde forcée : révision % au lieu de 3', r; end if;
  if (select app_version from public.backups) <> '' then raise exception 'version de l''app non remplacée'; end if;
  -- 2 Mo au plus pour les raccourcis.
  begin
    perform public.save_backup(repeat('x', 2097153), '{}', 3);
    raise exception 'sauvegarde trop grande acceptée';
  exception when check_violation then null;
  end;
end $$;
reset role;

-- Léo : ne voit ni ne modifie la sauvegarde de Malo ; a la sienne.
set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-00000000000b';
do $$
begin
  if (select count(*) from public.backups) <> 0 then raise exception 'Léo lit la sauvegarde de Malo'; end if;
  update public.backups set profile = 'pirate' where user_id = '00000000-0000-0000-0000-00000000000a';
  delete from public.backups where user_id = '00000000-0000-0000-0000-00000000000a';
  begin
    insert into public.backups (user_id, profile, macros) values ('00000000-0000-0000-0000-00000000000a', 'x', 'y');
    raise exception 'sauvegarde créée au nom d''un autre';
  exception when insufficient_privilege or unique_violation then null;
  end;
  if public.save_backup('{"leo":1}', '{}', 0) <> 1 then raise exception 'sauvegarde de Léo : révision attendue 1'; end if;
end $$;
reset role;
do $$
begin
  if (select profile from public.backups where user_id = '00000000-0000-0000-0000-00000000000a') <> '{"profil":3}' then
    raise exception 'la sauvegarde de Malo a été modifiée par Léo';
  end if;
end $$;

-- Léo supprime son compte : compte, profil, partages, signalements et sauvegarde effacés ; ses messages à l'équipe
-- restent, sans lien avec le compte. Rien ne change pour Malo.
set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-00000000000b';
select public.delete_my_account();
reset role;
do $$
begin
  if exists (select 1 from auth.users where id = '00000000-0000-0000-0000-00000000000b') then
    raise exception 'compte de Léo toujours là';
  end if;
  if exists (select 1 from public.profiles where id = '00000000-0000-0000-0000-00000000000b') then
    raise exception 'profil de Léo toujours là';
  end if;
  if exists (select 1 from public.backups where user_id = '00000000-0000-0000-0000-00000000000b') then
    raise exception 'sauvegarde de Léo toujours là';
  end if;
  if exists (select 1 from public.support_requests where user_id = '00000000-0000-0000-0000-00000000000b') then
    raise exception 'message à l''équipe encore lié au compte supprimé';
  end if;
  if (select count(*) from public.support_requests where kind = 'idee' and user_id is null) = 0 then
    raise exception 'message à l''équipe de Léo effacé';
  end if;
  if not exists (select 1 from auth.users where id = '00000000-0000-0000-0000-00000000000a')
     or not exists (select 1 from public.backups where user_id = '00000000-0000-0000-0000-00000000000a') then
    raise exception 'le compte de Malo a été touché';
  end if;
end $$;

-- Sans compte, impossible de supprimer quoi que ce soit.
set role anon;
set request.jwt.claim.sub to '';
do $$
begin
  begin
    perform public.delete_my_account();
    raise exception 'anon supprime un compte';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

select 'règles de la sauvegarde en ligne : tout est conforme' as resultat;
