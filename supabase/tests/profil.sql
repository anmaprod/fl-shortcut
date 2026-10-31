-- Essai de profil.sql (lancé par supabase/tests/run.sh, après policies.sql : Malo, et Léo administrateur, déjà là ; Malo
-- a 20 partages). Photo et pseudo seulement par leurs fonctions ; photos lisibles par les comptes connectés ;
-- signalements d'une photo ; retrait par un administrateur ; tout part avec le compte. Chaque vérification qui
-- échoue arrête tout (ON_ERROR_STOP) avec un message clair.
\set ON_ERROR_STOP on

-- Une photo d'essai : base64 d'un JPEG (commence par « /9j/ »).
create temporary table essai_photo as select '/9j/' || repeat('AbCd', 5000) as image;
grant select on essai_photo to anon, authenticated;

-- Sans compte : rien de lisible, rien de modifiable.
set role anon;
set request.jwt.claim.sub to '';
do $$
begin
  if (select count(*) from public.avatars) <> 0 then raise exception 'anon lit les photos'; end if;
  begin
    perform public.set_avatar((select image from essai_photo));
    raise exception 'anon pose une photo';
  exception when insufficient_privilege then null;
  end;
  begin
    perform public.set_username('pirate');
    raise exception 'anon change un pseudo';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- Malo pose sa photo ; seulement un JPEG en base64 de 96 Ko au plus ; jamais directement dans la table.
set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-00000000000a';
do $$
declare
  stamp timestamptz;
begin
  stamp := public.set_avatar((select image from essai_photo));
  if stamp is null or (select updated_at from public.avatars where user_id = '00000000-0000-0000-0000-00000000000a') <> stamp then
    raise exception 'photo de Malo non posée';
  end if;
  begin
    perform public.set_avatar((select image from essai_photo));
    raise exception 'photo changée deux fois de suite sans attendre';
  exception when raise_exception then
    if sqlerrm not like 'Attends quelques secondes%' then raise; end if;
  end;
end $$;
reset role;
-- (les essais suivants ne doivent pas attendre 5 s)
update public.avatars set updated_at = now() - interval '1 minute';
set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-00000000000a';
do $$
begin
  begin
    perform public.set_avatar('iVBORw0KGgoAAAANSUhEUg==');
    raise exception 'image qui n''est pas un JPEG acceptée';
  exception when check_violation then null;
  end;
  begin
    perform public.set_avatar('/9j/' || repeat('A', 98304));
    raise exception 'photo trop grande acceptée';
  exception when check_violation then null;
  end;
  begin
    perform public.set_avatar('/9j/<script>');
    raise exception 'texte qui n''est pas du base64 accepté';
  exception when check_violation then null;
  end;
  begin
    insert into public.avatars (user_id, image) values ('00000000-0000-0000-0000-00000000000b', '/9j/AAAA');
    raise exception 'photo posée directement, au nom d''un autre';
  exception when insufficient_privilege then null;
  end;
  update public.avatars set image = '/9j/BBBB';
  if (select image from public.avatars where user_id = '00000000-0000-0000-0000-00000000000a') = '/9j/BBBB' then
    raise exception 'photo modifiée sans passer par set_avatar';
  end if;
end $$;
reset role;

-- Léo voit la photo de Malo ; la signale une fois, jamais deux, jamais au nom d'un autre ; Malo ne signale pas la
-- sienne et ne lit pas les signalements.
set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-00000000000b';
do $$
begin
  if not exists (select 1 from public.avatars where user_id = '00000000-0000-0000-0000-00000000000a') then
    raise exception 'Léo ne voit pas la photo de Malo';
  end if;
  insert into public.avatar_reports (user_id, reason) values ('00000000-0000-0000-0000-00000000000a', '');
  begin
    insert into public.avatar_reports (user_id) values ('00000000-0000-0000-0000-00000000000a');
    raise exception 'photo signalée deux fois par le même compte';
  exception when unique_violation then null;
  end;
end $$;
reset role;
set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-00000000000a';
do $$
begin
  begin
    insert into public.avatar_reports (user_id) values ('00000000-0000-0000-0000-00000000000a');
    raise exception 'Malo signale sa propre photo';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.avatar_reports (user_id, reporter_id)
      values ('00000000-0000-0000-0000-00000000000b', '00000000-0000-0000-0000-00000000000b');
    raise exception 'signalement au nom d''un autre';
  exception when insufficient_privilege then null;
  end;
  if (select count(*) from public.avatar_reports) <> 0 then raise exception 'signalements de photos lisibles par Malo'; end if;
  -- Malo n'est pas administrateur : il ne retire pas la photo des autres.
  begin
    perform public.admin_remove_avatar('00000000-0000-0000-0000-00000000000b');
    raise exception 'Malo retire une photo sans être administrateur';
  exception when raise_exception then
    if sqlerrm not like 'Réservé aux administrateurs%' then raise; end if;
  end;
end $$;
reset role;

-- Léo, administrateur : lit le signalement, retire la photo de Malo (le signalement est traité).
set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-00000000000b';
do $$
begin
  if (select count(*) from public.avatar_reports) <> 1 then raise exception 'administrateur sans le signalement de la photo'; end if;
  perform public.admin_remove_avatar('00000000-0000-0000-0000-00000000000a');
  if exists (select 1 from public.avatars where user_id = '00000000-0000-0000-0000-00000000000a') then
    raise exception 'photo signalée non retirée par l''administrateur';
  end if;
  if (select count(*) from public.avatar_reports) <> 0 then raise exception 'signalement gardé après le retrait'; end if;
  -- Sa propre photo, posée puis retirée.
  perform public.set_avatar((select image from essai_photo));
  perform public.remove_avatar();
  if exists (select 1 from public.avatars where user_id = '00000000-0000-0000-0000-00000000000b') then
    raise exception 'photo de Léo non retirée';
  end if;
end $$;
reset role;

-- Pseudo : Malo en change ; ses partages déjà publiés et son compte prennent le nouveau ; pris, invalide ou trop tôt :
-- refusé.
set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-00000000000a';
do $$
begin
  if public.set_username('Malo.Beats') <> 'Malo.Beats' then raise exception 'pseudo non renvoyé'; end if;
  if (select p.username from public.shares s join public.profiles p on p.id = s.author_id limit 1) <> 'Malo.Beats' then
    raise exception 'partages publiés sans le nouveau pseudo';
  end if;
  begin
    perform public.set_username('malo.beats2');
    raise exception 'pseudo changé deux fois dans la minute';
  exception when raise_exception then
    if sqlerrm not like 'Attends une minute%' then raise; end if;
  end;
end $$;
reset role;
do $$
begin
  if (select raw_user_meta_data ->> 'username' from auth.users where id = '00000000-0000-0000-0000-00000000000a')
     is distinct from 'Malo.Beats' then
    raise exception 'compte sans le nouveau pseudo';
  end if;
  if public.username_available('malo') is not true or public.username_available('MALO.BEATS') then
    raise exception 'username_available ne suit pas le nouveau pseudo';
  end if;
end $$;
set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-00000000000b';
do $$
begin
  begin
    perform public.set_username('malo.beats');
    raise exception 'pseudo d''un autre accepté (majuscules près)';
  exception when unique_violation then null;
  end;
  begin
    perform public.set_username('a b');
    raise exception 'pseudo invalide accepté';
  exception when check_violation then null;
  end;
  if (select username from public.profiles where id = '00000000-0000-0000-0000-00000000000b') <> 'leo.beats' then
    raise exception 'pseudo de Léo changé par un refus';
  end if;
  -- Personne ne réécrit un profil directement.
  update public.profiles set username = 'pirate';
  if exists (select 1 from public.profiles where username = 'pirate') then raise exception 'profil modifiable directement'; end if;
end $$;
reset role;

-- Le compte supprimé emporte sa photo et ses signalements.
insert into auth.users (id, email, raw_user_meta_data, email_confirmed_at) values
  ('00000000-0000-0000-0000-0000000000e1', 'zoe@exemple.fr', '{"username":"zoe"}', now());
set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-0000000000e1';
select public.set_avatar((select image from essai_photo));
insert into public.avatar_reports (user_id) values ('00000000-0000-0000-0000-00000000000a');
select public.delete_my_account();
reset role;
do $$
begin
  if exists (select 1 from public.avatars where user_id = '00000000-0000-0000-0000-0000000000e1')
     or exists (select 1 from public.avatar_reports where reporter_id = '00000000-0000-0000-0000-0000000000e1') then
    raise exception 'photo ou signalement gardés après la suppression du compte';
  end if;
end $$;
drop table essai_photo;
select 'photos et pseudo du profil : tout est conforme' as resultat;
