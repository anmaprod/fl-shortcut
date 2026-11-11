-- Recollage de communaute-suivre.sql (lancé par supabase/tests/run.sh juste après l'avoir recollé, à la fin de
-- communaute-suivre.sql qui fausse deux compteurs) : chaque compteur est recalculé d'après les lignes.
\set ON_ERROR_STOP on
do $$
begin
  if (select follower_count from public.profiles where id = '00000000-0000-0000-0000-000000005c01') <> 0 then
    raise exception 'abonnés non recalculés au recollage';
  end if;
  if (select array[add_count, rating_sum, rating_count] from public.shares where id = '00000000-0000-0000-0000-00005c010001')
     <> array[1, 4, 1] then
    raise exception 'ajouts ou notes non recalculés au recollage';
  end if;
  if exists (select 1 from public.shares s
              where s.add_count <> (select count(*) from public.adds a where a.share_id = s.id)
                 or s.rating_count <> (select count(*) from public.ratings r where r.share_id = s.id)) then
    raise exception 'un compteur ne suit pas ses lignes';
  end if;
end $$;
select 'communauté (suivre, ajouts, notes) : tout est conforme' as resultat;
