-- Essai de l'inscription en deux temps (supabase/inscription.sql), lancé en dernier par supabase/tests/run.sh : pas de
-- profil ni de nom gardé avant le code du mail, profil créé au code, inscriptions jamais confirmées effacées.
\set ON_ERROR_STOP on
reset role;

do $$
declare
  forgotten integer;
begin
  -- Inscription sans le code : aucun profil, le nom reste libre pour les autres.
  insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-0000-0000-0000000000c1', 'nina@exemple.fr', '{"username":"nina"}');
  if exists (select 1 from public.profiles where id = '00000000-0000-0000-0000-0000000000c1') then
    raise exception 'profil créé avant le code du mail';
  end if;
  if not public.username_available('nina') then raise exception 'nom gardé par une inscription non confirmée'; end if;

  -- Une autre inscription prend « Nina » et entre son code la première : son profil est créé à ce moment-là.
  insert into auth.users (id, email, raw_user_meta_data) values
    ('00000000-0000-0000-0000-0000000000c2', 'nina2@exemple.fr', '{"username":"Nina"}');
  update auth.users set email_confirmed_at = now() where id = '00000000-0000-0000-0000-0000000000c2';
  if (select username from public.profiles where id = '00000000-0000-0000-0000-0000000000c2') is distinct from 'Nina' then
    raise exception 'profil non créé au code du mail';
  end if;

  -- La première entre son code ensuite : jamais refusée, le nom suivi de 4 caractères (et l'app le reçoit).
  update auth.users set email_confirmed_at = now() where id = '00000000-0000-0000-0000-0000000000c1';
  if (select username from public.profiles where id = '00000000-0000-0000-0000-0000000000c1') is distinct from 'nina_0000'
     or (select raw_user_meta_data ->> 'username' from auth.users where id = '00000000-0000-0000-0000-0000000000c1')
        is distinct from 'nina_0000' then
    raise exception 'nom pris entre l''inscription et le code : confirmation mal faite';
  end if;

  -- Les mises à jour suivantes (connexion, nouveau mot de passe…) ne touchent plus au profil.
  update auth.users set email = 'nina@exemple.fr', email_confirmed_at = now()
    where id = '00000000-0000-0000-0000-0000000000c1';
  if (select count(*) from public.profiles where id = '00000000-0000-0000-0000-0000000000c1') <> 1 then
    raise exception 'profil recréé à une mise à jour';
  end if;

  -- Nom déjà pris par un compte confirmé : inscription refusée tout de suite.
  begin
    insert into auth.users (email, raw_user_meta_data) values ('z@exemple.fr', '{"username":"NINA"}');
    raise exception 'nom déjà pris accepté';
  exception when unique_violation then null;
  end;

  -- Jamais confirmées : effacées après 24 h, pas avant ; les comptes confirmés jamais.
  insert into auth.users (id, email, raw_user_meta_data, created_at) values
    ('00000000-0000-0000-0000-0000000000d1', 'ancien@exemple.fr', '{"username":"ancien"}', now() - interval '25 hours'),
    ('00000000-0000-0000-0000-0000000000d2', 'recent@exemple.fr', '{"username":"recent"}', now() - interval '2 hours');
  update auth.users set created_at = now() - interval '30 days' where id = '00000000-0000-0000-0000-0000000000c2';
  forgotten := public.forget_unconfirmed_signups();
  if forgotten <> 1
     or exists (select 1 from auth.users where id = '00000000-0000-0000-0000-0000000000d1')
     or not exists (select 1 from auth.users where id = '00000000-0000-0000-0000-0000000000d2')
     or not exists (select 1 from auth.users where id = '00000000-0000-0000-0000-0000000000c2') then
    raise exception 'ménage des inscriptions non confirmées incorrect (% effacée(s))', forgotten;
  end if;
end $$;

-- Le ménage n'est lancé ni par un visiteur ni par un compte.
set role anon;
do $$
begin
  perform public.forget_unconfirmed_signups();
  raise exception 'un visiteur efface des inscriptions';
exception when insufficient_privilege then null;
end $$;
set role authenticated;
do $$
begin
  perform public.forget_unconfirmed_signups();
  raise exception 'un compte efface des inscriptions';
exception when insufficient_privilege then null;
end $$;
reset role;

select 'inscription en deux temps : tout est conforme' as resultat;
