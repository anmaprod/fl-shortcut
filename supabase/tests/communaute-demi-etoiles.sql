-- Essai des demi-étoiles (19/11, « des demi-étoiles comme dans Letterboxd »), lancé par supabase/tests/run.sh après
-- communaute-suivre.sql (recollé sur la base du 11/11, ou installé neuf) et ses essais : Sam (d) y a ajouté puis noté
-- l'« Export rapide » de Nina (c). Chaque vérification qui échoue arrête tout (ON_ERROR_STOP).
\set ON_ERROR_STOP on

-- Les notes d'avant ont leur demi-étoile (étoiles × 2), même celles écrites sans elle.
do $$
begin
  if exists (select 1 from public.ratings where half is null or half <> stars * 2) then
    raise exception 'notes sans leur demi-étoile';
  end if;
end $$;

set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-000000005d01';
do $$
declare
  r record;
  mine int;
  half_sum int;
  star_sum int;
  votes int;
begin
  select half into mine from public.ratings
   where share_id = '00000000-0000-0000-0000-00005c010001' and user_id = '00000000-0000-0000-0000-000000005d01';
  if mine is null then raise exception 'la note de Sam manque'; end if;
  select rating_half_sum, rating_sum, rating_count into half_sum, star_sum, votes
    from public.shares where id = '00000000-0000-0000-0000-00005c010001';

  -- 4 étoiles et demie : la somme en demi-étoiles suit ; en étoiles entières (versions d'avant), 4,5 compte 5.
  select * into r from public.rate_share_half('00000000-0000-0000-0000-00005c010001', 9);
  if r.rating_half_sum <> half_sum - mine + 9 or r.rating_count <> votes then
    raise exception 'demi-étoiles mal comptées : %', r;
  end if;
  if (select rating_sum from public.shares where id = '00000000-0000-0000-0000-00005c010001') <> star_sum - mine / 2 + 5 then
    raise exception 'étoiles entières des versions d''avant fausses';
  end if;
  begin
    perform * from public.rate_share_half('00000000-0000-0000-0000-00005c010001', 11);
    raise exception 'note de 5,5 étoiles acceptée';
  exception when check_violation then null;
  end;
  begin
    perform * from public.rate_share_half('00000000-0000-0000-0000-00005c010001', 0);
    raise exception 'note de 0 étoile acceptée';
  exception when check_violation then null;
  end;

  -- L'ancienne fonction (versions d'avant) écrit aussi la demi-étoile.
  perform * from public.rate_share('00000000-0000-0000-0000-00005c010001', 3);
  if (select half from public.ratings where share_id = '00000000-0000-0000-0000-00005c010001'
        and user_id = '00000000-0000-0000-0000-000000005d01') <> 6 then
    raise exception 'rate_share sans demi-étoile';
  end if;

  -- Retour à la note d'avant : les sommes reviennent.
  select * into r from public.rate_share_half('00000000-0000-0000-0000-00005c010001', mine);
  if r.rating_half_sum <> half_sum then raise exception 'demi-étoiles changées mal comptées : %', r; end if;
end $$;
reset role;

-- Sans avoir ajouté le partage : pas de note, même en demi-étoiles.
set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-000000005c01';
do $$
begin
  perform * from public.rate_share_half('00000000-0000-0000-0000-00005c010001', 7);
  raise exception 'Nina note son propre partage';
exception when raise_exception then
  if sqlerrm not like 'Tu ne peux pas noter%' then raise; end if;
end $$;
reset role;

select 'demi-étoiles : tout est conforme' as resultat;
