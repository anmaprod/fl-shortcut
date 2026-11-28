-- Essai de communaute-suivre.sql (lancé par supabase/tests/run.sh, à la fin) : abonnements, compteurs tenus par le
-- serveur, ajouts, notes, classements, anti-spam, compte supprimé. Chaque vérification qui échoue arrête tout
-- (ON_ERROR_STOP) avec un message clair. Comptes d'essai à part (c, d, e), sans toucher aux autres essais.
\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data, email_confirmed_at) values
  ('00000000-0000-0000-0000-000000005c01', 'nina.test@exemple.fr', '{"username":"nina.test"}', now()),
  ('00000000-0000-0000-0000-000000005d01', 'sam.test@exemple.fr', '{"username":"sam.test"}', now()),
  ('00000000-0000-0000-0000-000000005e01', 'max.test@exemple.fr', '{"username":"max.test"}', now());

-- Sans compte : rien de lisible, rien de faisable.
set role anon;
set request.jwt.claim.sub to '';
do $$
begin
  if (select count(*) from public.follows) + (select count(*) from public.adds) + (select count(*) from public.ratings) <> 0 then
    raise exception 'anon lit les abonnements, ajouts ou notes';
  end if;
  begin
    perform public.record_add(gen_random_uuid());
    raise exception 'anon compte un ajout';
  exception when insufficient_privilege then null;
  end;
  begin
    perform * from public.rate_share(gen_random_uuid(), 5);
    raise exception 'anon note un partage';
  exception when insufficient_privilege then null;
  end;
  begin
    perform * from public.creators_to_follow(5);
    raise exception 'anon lit les créateurs à suivre';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- Nina (c) publie deux macros, Sam (d) une.
set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-000000005c01';
insert into public.shares (id, kind, title, payload, created_at) values
  ('00000000-0000-0000-0000-00005c010001', 'macro', 'Export rapide', '{}', now() - interval '2 minutes'),
  ('00000000-0000-0000-0000-00005c010002', 'macro', 'Ouvre un VST', '{}', now() - interval '1 minute');
set request.jwt.claim.sub to '00000000-0000-0000-0000-000000005d01';
insert into public.shares (id, kind, title, payload) values ('00000000-0000-0000-0000-00005d010001', 'macro', 'Armer', '{}');
reset role;

-- Sam suit Nina : le nombre d'abonnés de Nina monte ; jamais soi-même ni au nom d'un autre ; on ne voit que les siens.
set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-000000005d01';
insert into public.follows (followee_id) values ('00000000-0000-0000-0000-000000005c01');
do $$
begin
  if (select follower_count from public.profiles where id = '00000000-0000-0000-0000-000000005c01') <> 1 then
    raise exception 'abonné non compté';
  end if;
  begin
    insert into public.follows (followee_id) values ('00000000-0000-0000-0000-000000005d01');
    raise exception 'abonné à soi-même';
  exception when check_violation then null;
  end;
  begin
    insert into public.follows (follower_id, followee_id)
      values ('00000000-0000-0000-0000-000000005e01', '00000000-0000-0000-0000-000000005c01');
    raise exception 'abonnement au nom d''un autre';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.follows (followee_id) values ('00000000-0000-0000-0000-000000005c01');
    raise exception 'abonné deux fois';
  exception when unique_violation then null;
  end;
  -- Le compteur ne se modifie pas depuis l'app (aucune règle de mise à jour).
  update public.profiles set follower_count = 999 where id = '00000000-0000-0000-0000-000000005c01';
  update public.shares set add_count = 999, rating_sum = 999 where id = '00000000-0000-0000-0000-00005c010001';
  if (select follower_count from public.profiles where id = '00000000-0000-0000-0000-000000005c01') <> 1
     or (select add_count from public.shares where id = '00000000-0000-0000-0000-00005c010001') <> 0 then
    raise exception 'compteur modifié depuis l''app';
  end if;
  if (select count(*) from public.follows) <> 1 then raise exception 'Sam ne voit pas son abonnement'; end if;
end $$;
set request.jwt.claim.sub to '00000000-0000-0000-0000-000000005e01';
do $$
begin
  if (select count(*) from public.follows) <> 0 then raise exception 'Max voit les abonnements de Sam'; end if;
end $$;
reset role;

-- Ajouts : une fois par personne, jamais pour son propre partage.
set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-000000005d01';
do $$
begin
  if public.record_add('00000000-0000-0000-0000-00005c010001') <> 1 then raise exception 'ajout non compté'; end if;
  if public.record_add('00000000-0000-0000-0000-00005c010001') <> 1 then raise exception 'ajout compté deux fois'; end if;
  if public.record_add('00000000-0000-0000-0000-00005d010001') <> 0 then raise exception 'son propre partage compté'; end if;
  begin
    perform public.record_add(gen_random_uuid());
    raise exception 'ajout d''un partage qui n''existe pas';
  exception when raise_exception then
    if sqlerrm <> 'Partage introuvable.' then raise; end if;
  end;
end $$;
set request.jwt.claim.sub to '00000000-0000-0000-0000-000000005e01';
do $$
begin
  if public.record_add('00000000-0000-0000-0000-00005c010001') <> 2 then raise exception 'deuxième ajout non compté'; end if;
  if (select count(*) from public.adds) <> 1 then raise exception 'Max voit les ajouts des autres'; end if;
end $$;
reset role;

-- Notes : seulement après un ajout, jamais le sien, de 1 à 5, une par personne (modifiable).
set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-000000005d01';
do $$
declare
  r record;
begin
  select * into r from public.rate_share('00000000-0000-0000-0000-00005c010001', 5);
  if r.rating_sum <> 5 or r.rating_count <> 1 then raise exception 'première note fausse : %', r; end if;
  begin
    perform * from public.rate_share('00000000-0000-0000-0000-00005c010002', 4);
    raise exception 'note sans ajout';
  exception when raise_exception then
    if sqlerrm not like 'Ajoute-le%' then raise; end if;
  end;
  begin
    perform * from public.rate_share('00000000-0000-0000-0000-00005d010001', 5);
    raise exception 'son propre partage noté';
  exception when raise_exception then
    if sqlerrm not like 'Tu ne peux pas noter%' then raise; end if;
  end;
  begin
    perform * from public.rate_share('00000000-0000-0000-0000-00005c010001', 6);
    raise exception 'note de 6 étoiles';
  exception when check_violation then null;
  end;
end $$;
set request.jwt.claim.sub to '00000000-0000-0000-0000-000000005e01';
do $$
declare
  r record;
begin
  select * into r from public.rate_share('00000000-0000-0000-0000-00005c010001', 3);
  if r.rating_sum <> 8 or r.rating_count <> 2 then raise exception 'deuxième note fausse : %', r; end if;
  if (select count(*) from public.ratings) <> 1 then raise exception 'Max voit les notes des autres'; end if;
end $$;
set request.jwt.claim.sub to '00000000-0000-0000-0000-000000005d01';
do $$
declare
  r record;
begin
  select * into r from public.rate_share('00000000-0000-0000-0000-00005c010001', 4);   -- Sam change sa note
  if r.rating_sum <> 7 or r.rating_count <> 2 then raise exception 'note changée mal comptée : %', r; end if;
end $$;
reset role;

-- Classements.
do $$
begin
  if public.creator_score(5, 1) >= public.creator_score(4000, 1000) then
    raise exception '1 note à 5 étoiles passe devant 1 000 notes à 4 étoiles';
  end if;
  if public.creator_score(0, 0) <> 3.5 then raise exception 'note d''un créateur sans note'; end if;
end $$;
set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-000000005d01';
do $$
begin
  -- Partages des gens suivis (Nina), les plus récents d'abord.
  if array(select id from public.followed_shares(50)) <> array['00000000-0000-0000-0000-00005c010002',
                                                               '00000000-0000-0000-0000-00005c010001']::uuid[] then
    raise exception 'partages des abonnements faux';
  end if;
  -- Les plus ajoutés : seulement ceux ajoutés au moins une fois.
  if array(select id from public.most_added(null, 50)) <> array['00000000-0000-0000-0000-00005c010001']::uuid[] then
    raise exception 'les plus ajoutés faux';
  end if;
  if exists (select 1 from public.most_added('profile', 50)) then raise exception 'sorte non filtrée'; end if;
  -- Créateurs à suivre : ni soi ni ceux déjà suivis.
  if exists (select 1 from public.creators_to_follow(20) where id in ('00000000-0000-0000-0000-000000005c01',
                                                                       '00000000-0000-0000-0000-000000005d01')) then
    raise exception 'créateurs à suivre : soi-même ou déjà suivi';
  end if;
end $$;
set request.jwt.claim.sub to '00000000-0000-0000-0000-000000005e01';
do $$
begin
  if exists (select 1 from public.followed_shares(50)) then raise exception 'abonnements sans abonnement'; end if;
  -- Nina (2 ajouts) avant Sam (aucun) à note égale.
  if (select array_agg(username order by ordinality) from public.creators_to_follow(20) with ordinality
       where username in ('nina.test', 'sam.test')) <> array['nina.test', 'sam.test'] then
    raise exception 'ordre des créateurs à suivre faux';
  end if;
end $$;
reset role;

-- Se désabonner : le nombre d'abonnés redescend.
set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-000000005d01';
delete from public.follows where followee_id = '00000000-0000-0000-0000-000000005c01';
reset role;
do $$
begin
  if (select follower_count from public.profiles where id = '00000000-0000-0000-0000-000000005c01') <> 0 then
    raise exception 'désabonnement non compté';
  end if;
end $$;

-- Anti-spam : 200 abonnements par heure, le 201e refusé.
insert into auth.users (id, email, raw_user_meta_data, email_confirmed_at)
  select ('00000000-0000-0000-0000-0005f000' || lpad(i::text, 4, '0'))::uuid, 'fan' || i || '@exemple.fr',
         jsonb_build_object('username', 'fan.test' || i), now()
    from generate_series(1, 201) i;
insert into public.follows (follower_id, followee_id)
  select '00000000-0000-0000-0000-000000005e01', ('00000000-0000-0000-0000-0005f000' || lpad(i::text, 4, '0'))::uuid
    from generate_series(1, 200) i;
set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-000000005e01';
do $$
begin
  insert into public.follows (followee_id) values ('00000000-0000-0000-0000-0005f0000201');
  raise exception '201e abonnement de l''heure accepté';
exception when raise_exception then
  if sqlerrm not like 'Trop d''abonnements%' then raise; end if;
end $$;
reset role;

-- Anti-spam : 200 notes par heure, la 201e refusée (partages anciens : la limite de 20 partages par jour ne compte pas).
insert into public.shares (id, author_id, kind, title, payload, created_at)
  select ('00000000-0000-0000-0000-0005a000' || lpad(i::text, 4, '0'))::uuid, '00000000-0000-0000-0000-0005f0000001',
         'macro', 'Partage ' || i, '{}', now() - interval '2 days'
    from generate_series(1, 201) i;
insert into public.adds (share_id, user_id)
  select ('00000000-0000-0000-0000-0005a000' || lpad(i::text, 4, '0'))::uuid, '00000000-0000-0000-0000-000000005e01'
    from generate_series(1, 201) i;
insert into public.ratings (share_id, user_id, stars)
  select ('00000000-0000-0000-0000-0005a000' || lpad(i::text, 4, '0'))::uuid, '00000000-0000-0000-0000-000000005e01', 4
    from generate_series(1, 199) i;
set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-000000005e01';
do $$
begin
  perform * from public.rate_share('00000000-0000-0000-0000-0005a0000200', 5);     -- la 200e passe
  perform * from public.rate_share('00000000-0000-0000-0000-0005a0000201', 5);
  raise exception '201e note de l''heure acceptée';
exception when raise_exception then
  if sqlerrm not like 'Trop de notes%' then raise; end if;
end $$;
reset role;

-- Compte supprimé : ses abonnements, ajouts et notes partent, les compteurs suivent.
delete from auth.users where id = '00000000-0000-0000-0000-000000005e01';
do $$
begin
  if (select add_count from public.shares where id = '00000000-0000-0000-0000-00005c010001') <> 1
     or (select rating_sum from public.shares where id = '00000000-0000-0000-0000-00005c010001') <> 4
     or (select rating_count from public.shares where id = '00000000-0000-0000-0000-00005c010001') <> 1 then
    raise exception 'compteurs faux après un compte supprimé';
  end if;
  if (select follower_count from public.profiles where id = '00000000-0000-0000-0000-0005f0000001') <> 0 then
    raise exception 'abonnés faux après un compte supprimé';
  end if;
end $$;

-- Pour le recollage (communaute-suivre-recolle.sql) : des compteurs faussés, que le fichier recollé doit réparer.
update public.profiles set follower_count = 42 where id = '00000000-0000-0000-0000-000000005c01';
update public.shares set add_count = 42, rating_sum = 42, rating_count = 42 where id = '00000000-0000-0000-0000-00005c010001';
