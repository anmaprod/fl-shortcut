-- Essai des règles de corrections-ia.sql (lancé par supabase/tests/run.sh, en dernier) : partage avec ou sans
-- compte, rien de relisible, formes refusées, limite par compte.
\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data, email_confirmed_at) values
  ('c0ffee00-0000-4000-8000-0000000c0de1', 'essai.ia@exemple.fr', '{"username":"essai.ia"}', now());

set role anon;
set request.jwt.claim.sub to '';
do $$
declare
  une text := repeat('AAAA', 811);                    -- 1 tranche : 2432 octets → 3244 caractères en base64
begin
  insert into public.corrections_ia (famille_ia, sorte_ia, famille_avant, famille, sorte, tranches, mesures, raisons,
                                     modele, app_version)
    values ('melodie', 'lead', 'melodie', 'voix', 'vocalLead', 1, une, 'voice,kind', 2, '0.1.0');
  if (select count(*) from public.corrections_ia) <> 0 then raise exception 'corrections lisibles par anon'; end if;
  begin
    insert into public.corrections_ia (user_id, famille_ia, famille, tranches, mesures)
      values ('c0ffee00-0000-4000-8000-0000000c0de1', 'fx', 'voix', 1, une);
    raise exception 'correction au nom d''un compte acceptée';
  exception when insufficient_privilege then null;
  end;
  begin
    insert into public.corrections_ia (famille_ia, famille, tranches, mesures) values ('fx', 'vocals', 1, une);
    raise exception 'famille inconnue acceptée';
  exception when check_violation then null;
  end;
  begin
    insert into public.corrections_ia (famille_ia, famille, tranches, mesures) values ('fx', 'voix', 2, une);
    raise exception 'mesures de la mauvaise taille acceptées';
  exception when check_violation then null;
  end;
  begin
    insert into public.corrections_ia (famille_ia, famille, tranches, mesures) values ('fx', 'voix', 9, repeat('A', 29184));
    raise exception 'plus de 8 tranches acceptées';
  exception when check_violation then null;
  end;
  begin
    insert into public.corrections_ia (famille_ia, famille, sorte, tranches, mesures)
      values ('fx', 'voix', 'Voix lead', 1, une);
    raise exception 'sorte avec une espace acceptée (un nom de son ?)';
  exception when check_violation then null;
  end;
  begin
    insert into public.corrections_ia (famille_ia, famille, tranches, mesures, raisons)
      values ('fx', 'voix', 1, une, 'ma voix est rangée en FX');
    raise exception 'texte libre accepté dans les raisons';
  exception when check_violation then null;
  end;
end $$;
reset role;

-- Avec un compte : rempli par défaut ; 300 par heure au plus.
set role authenticated;
set request.jwt.claim.sub to 'c0ffee00-0000-4000-8000-0000000c0de1';
do $$
declare
  une text := repeat('AAAA', 811);
begin
  for i in 1..300 loop
    insert into public.corrections_ia (famille_ia, famille, tranches, mesures, raisons)
      values ('drums', 'drums', 1, une, 'apercu');
  end loop;
  begin
    insert into public.corrections_ia (famille_ia, famille, tranches, mesures) values ('drums', 'basse', 1, une);
    raise exception '301e correction de l''heure acceptée';
  exception when raise_exception then
    if sqlerrm not like 'Trop de corrections%' then raise; end if;
  end;
  if (select count(*) from public.corrections_ia) <> 0 then raise exception 'corrections lisibles par un compte'; end if;
end $$;
reset role;
do $$
begin
  if (select count(*) from public.corrections_ia) <> 301 then raise exception 'corrections mal comptées'; end if;
  if (select count(*) from public.corrections_ia where user_id = 'c0ffee00-0000-4000-8000-0000000c0de1') <> 300 then
    raise exception 'compte non rempli par défaut';
  end if;
end $$;

select 'règles des corrections de l''IA : tout est conforme' as resultat;
