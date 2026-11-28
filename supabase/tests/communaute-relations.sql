-- Liens entre tables vus par le serveur web de Supabase (PostgREST), lancé par supabase/tests/run.sh.
-- 12/11 (capture : « Could not embed because more than one relationship was found for 'shares' and 'profiles' »,
-- Communauté vide pour tout le monde) : PostgREST prend pour un lien direct entre deux tables toute table dont la
-- clé primaire contient ses références vers les deux (« table de jonction »). adds et ratings, à clé
-- (share_id, user_id), faisaient ainsi deux liens de plus entre partages et profils, et « author:profiles(username) »
-- de l'app ne savait plus lequel prendre. Cet essai suit la même règle que PostgREST : entre shares et profiles, un
-- seul lien doit rester (shares.author_id).
\set ON_ERROR_STOP on
do $$
declare
  directs int;
  junctions text;
begin
  -- Références directes, dans un sens ou dans l'autre.
  select count(*) into directs
    from pg_constraint
   where contype = 'f'
     and ((conrelid = 'public.shares'::regclass and confrelid = 'public.profiles'::regclass)
       or (conrelid = 'public.profiles'::regclass and confrelid = 'public.shares'::regclass));
  -- Tables de jonction : une référence vers shares et une vers profiles, toutes deux dans la clé primaire.
  select string_agg(distinct fk1.conrelid::regclass::text, ', ') into junctions
    from pg_constraint fk1
    join pg_constraint fk2 on fk2.conrelid = fk1.conrelid and fk2.contype = 'f'
                          and fk2.confrelid = 'public.profiles'::regclass
    join pg_constraint pk on pk.conrelid = fk1.conrelid and pk.contype = 'p'
   where fk1.contype = 'f' and fk1.confrelid = 'public.shares'::regclass
     and fk1.conkey <@ pk.conkey and fk2.conkey <@ pk.conkey;
  if junctions is not null then
    raise exception 'liens en double entre partages et profils (le serveur ne saura pas lequel prendre) par : %', junctions;
  end if;
  if directs <> 1 then
    raise exception 'partages et profils : % références directes, il en faut une seule (shares.author_id)', directs;
  end if;
end $$;

-- « Une fois par personne et par partage » tient toujours, sans la clé d'avant.
do $$
begin
  if not exists (select 1 from pg_constraint where conrelid = 'public.adds'::regclass and contype = 'u'
                   and conname = 'adds_une_fois') then
    raise exception 'adds : plus rien n''empêche deux ajouts de la même personne';
  end if;
  if not exists (select 1 from pg_constraint where conrelid = 'public.ratings'::regclass and contype = 'u'
                   and conname = 'ratings_une_fois') then
    raise exception 'ratings : plus rien n''empêche deux notes de la même personne';
  end if;
  if exists (select 1 from public.adds where id is null) or exists (select 1 from public.ratings where id is null) then
    raise exception 'une ligne sans numéro';
  end if;
end $$;
select 'liens entre tables : un seul entre partages et profils' as resultat;
