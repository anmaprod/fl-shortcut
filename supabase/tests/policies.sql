-- Essai des règles de schema.sql (lancé par supabase/tests/run.sh, après supabase-stubs.sql et schema.sql) : chaque
-- vérification qui échoue arrête tout (ON_ERROR_STOP) avec un message clair.
\set ON_ERROR_STOP on

-- Comptes : le déclencheur crée le profil avec le nom d'utilisateur envoyé par l'app.
insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-00000000000a', 'malo@exemple.fr', '{"username":"malo"}'),
  ('00000000-0000-0000-0000-00000000000b', 'leo@exemple.fr', '{"username":"leo.beats"}');

do $$
begin
  if (select count(*) from public.profiles) <> 2 then raise exception 'profils non créés à l''inscription'; end if;
  -- Nom invalide ou déjà pris (sans tenir compte des majuscules) : inscription refusée.
  begin
    insert into auth.users (email, raw_user_meta_data) values ('x@exemple.fr', '{"username":"a b"}');
    raise exception 'nom invalide accepté';
  exception when check_violation then null;
  end;
  begin
    insert into auth.users (email, raw_user_meta_data) values ('y@exemple.fr', '{"username":"MALO"}');
    raise exception 'nom déjà pris accepté';
  exception when unique_violation then null;
  end;
end $$;

-- Visiteur sans compte (anon) : rien de lisible, rien de publiable ; seul « ce nom est-il libre ? ».
set role anon;
set request.jwt.claim.sub to '';
do $$
begin
  if (select count(*) from public.profiles) <> 0 then raise exception 'anon lit les profils'; end if;
  if not public.username_available('nouveau') then raise exception 'username_available faux pour un nom libre'; end if;
  if public.username_available('Malo') then raise exception 'username_available vrai pour un nom pris'; end if;
  begin
    insert into public.shares (author_id, kind, title, payload)
      values ('00000000-0000-0000-0000-00000000000a', 'macro', 'Essai', '{}');
    raise exception 'anon publie';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- Malo, connecté : publie en son nom, jamais au nom d'un autre ; lit tout.
set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-00000000000a';
insert into public.shares (kind, title, notes, payload) values ('macro', 'Armer la piste', 'Notes', '{"format":"x"}');
do $$
begin
  if (select author_id from public.shares limit 1) <> '00000000-0000-0000-0000-00000000000a' then
    raise exception 'auteur non rempli par défaut';
  end if;
  begin
    insert into public.shares (author_id, kind, title, payload)
      values ('00000000-0000-0000-0000-00000000000b', 'macro', 'Au nom de Léo', '{}');
    raise exception 'publication au nom d''un autre acceptée';
  exception when insufficient_privilege then null;
  end;
  -- Limites : titre de 3 à 80 caractères, genre connu, fichier de 256 Kio au plus.
  begin
    insert into public.shares (kind, title, payload) values ('macro', 'ab', '{}');
    raise exception 'titre trop court accepté';
  exception when check_violation then null;
  end;
  begin
    insert into public.shares (kind, title, payload) values ('script', 'Genre inconnu', '{}');
    raise exception 'genre inconnu accepté';
  exception when check_violation then null;
  end;
  begin
    insert into public.shares (kind, title, payload) values ('macro', 'Trop gros', repeat('x', 262145));
    raise exception 'fichier trop gros accepté';
  exception when check_violation then null;
  end;
  -- Personne ne réécrit un partage (aucune règle de mise à jour).
  update public.shares set title = 'Changé';
  if exists (select 1 from public.shares where title = 'Changé') then raise exception 'partage modifiable'; end if;
  if public.is_admin() then raise exception 'Malo administrateur sans être dans admins'; end if;
end $$;
reset role;

-- Léo, connecté : voit le partage de Malo, ne peut pas le supprimer ; le signale ; ne lit pas les signalements.
set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-00000000000b';
do $$
declare
  s uuid;
begin
  select id into s from public.shares limit 1;
  if s is null then raise exception 'Léo ne voit pas le partage de Malo'; end if;
  delete from public.shares where id = s;
  if not exists (select 1 from public.shares where id = s) then raise exception 'Léo supprime le partage de Malo'; end if;
  insert into public.reports (share_id, reason) values (s, 'Ne fait pas ce que dit son explication');
  if (select count(*) from public.reports) <> 0 then raise exception 'signalements lisibles sans être administrateur'; end if;
  begin
    insert into public.reports (share_id, reason) values (s, 'Deuxième fois');
    raise exception 'double signalement accepté';
  exception when unique_violation then null;
  end;
end $$;
reset role;

-- Léo devient administrateur (ajouté à la main, comme dans le README) : lit les signalements, supprime tout.
insert into public.admins (user_id) values ('00000000-0000-0000-0000-00000000000b');
set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-00000000000b';
do $$
begin
  if not public.is_admin() then raise exception 'is_admin faux pour un administrateur'; end if;
  if (select count(*) from public.reports) <> 1 then raise exception 'administrateur sans les signalements'; end if;
  if (select count(*) from public.admins) <> 0 then raise exception 'table admins lisible depuis l''app'; end if;
  delete from public.shares;
  if exists (select 1 from public.shares) then raise exception 'administrateur sans suppression'; end if;
end $$;
reset role;

-- Anti-spam : 20 partages par compte et par 24 h, le 21e refusé.
set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-00000000000a';
do $$
begin
  for i in 1..20 loop
    insert into public.shares (kind, title, payload) values ('macro', 'Partage ' || i, '{}');
  end loop;
  begin
    insert into public.shares (kind, title, payload) values ('macro', 'Partage 21', '{}');
    raise exception '21e partage du jour accepté';
  exception when raise_exception then
    if sqlerrm not like 'Trop de partages%' then raise; end if;
  end;
end $$;
reset role;

-- Aide : écrire à l'équipe avec ou sans compte ; rien n'est relisible depuis l'app ; 5 messages par heure et par mail.
set role anon;
set request.jwt.claim.sub to '';
do $$
begin
  insert into public.support_requests (kind, message, email, diagnostic, app_version)
    values ('probleme', 'Mes raccourcis ne marchent plus depuis hier.', 'nina@exemple.fr', 'FL Shortcut 0.1.0', '0.1.0');
  if (select count(*) from public.support_requests) <> 0 then raise exception 'demandes d''aide lisibles par anon'; end if;
  begin
    insert into public.support_requests (user_id, kind, message)
      values ('00000000-0000-0000-0000-00000000000a', 'question', 'Au nom de Malo, sans être Malo.');
    raise exception 'demande d''aide au nom d''un compte acceptée';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.support_requests (kind, message) values ('probleme', 'Court');
    raise exception 'message trop court accepté';
  exception when check_violation then null;
  end;
  begin
    insert into public.support_requests (kind, message, email) values ('idee', 'Une idée sans mail valide.', 'pas-un-mail');
    raise exception 'mail invalide accepté';
  exception when check_violation then null;
  end;
  for i in 2..5 loop
    insert into public.support_requests (kind, message, email) values ('question', 'Question numéro ' || i, 'NINA@exemple.fr');
  end loop;
  begin
    insert into public.support_requests (kind, message, email) values ('question', 'Sixième question en une heure', 'nina@exemple.fr');
    raise exception '6e message de l''heure accepté';
  exception when raise_exception then
    if sqlerrm not like 'Trop de messages%' then raise; end if;
  end;
end $$;
reset role;
set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-00000000000b';
insert into public.support_requests (kind, message) values ('idee', 'Pouvoir trier les macros par dossier.');
reset role;
do $$
begin
  if (select count(*) from public.support_requests) <> 6 then raise exception 'demandes d''aide mal comptées'; end if;
  if (select user_id from public.support_requests where kind = 'idee') <> '00000000-0000-0000-0000-00000000000b' then
    raise exception 'compte non rempli par défaut';
  end if;
end $$;

select 'règles de la Communauté et de l''aide : tout est conforme' as resultat;
