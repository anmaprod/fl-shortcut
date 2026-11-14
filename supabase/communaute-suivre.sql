-- Communauté (11/11) : suivre des créateurs, « Ajoutée N fois » et des étoiles (1 à 5) par partage, note de chaque
-- créateur calculée par le serveur (moyenne bayésienne de toutes les notes de ses partages). Voir
-- docs/superpowers/specs/2026-11-11-communaute-suivre-design.md.
-- À coller dans Supabase › SQL Editor après schema.sql et profil.sql (voir supabase/README.md, étape 12). Peut être
-- recollé sans risque (les compteurs sont recalculés). Sans ce fichier, l'app garde la Communauté d'avant (ni Suivre
-- ni étoiles).
-- Tout est réservé aux comptes connectés (rôle « authenticated »). Chacun ne lit que SES abonnements, SES ajouts et
-- SES notes ; des autres, on ne voit que les nombres (abonnés, ajouts, moyenne), tenus par le serveur seul.

-- Compteurs, jamais modifiables depuis l'app (aucune règle de mise à jour sur profiles ni shares).
alter table public.profiles add column if not exists follower_count integer not null default 0;
alter table public.shares add column if not exists add_count integer not null default 0;
alter table public.shares add column if not exists rating_sum integer not null default 0;
alter table public.shares add column if not exists rating_count integer not null default 0;
create index if not exists shares_add_count on public.shares (add_count desc, created_at desc);
create index if not exists shares_author on public.shares (author_id, created_at desc);

-- ---------- Abonnements ----------

create table if not exists public.follows (
  follower_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  followee_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (follower_id, followee_id),
  check (follower_id <> followee_id)
);
create index if not exists follows_followee on public.follows (followee_id);
alter table public.follows enable row level security;
drop policy if exists "chacun lit ses abonnements" on public.follows;
create policy "chacun lit ses abonnements" on public.follows
  for select to authenticated using (follower_id = auth.uid());
drop policy if exists "chacun s'abonne en son nom" on public.follows;
create policy "chacun s'abonne en son nom" on public.follows
  for insert to authenticated with check (follower_id = auth.uid());
drop policy if exists "chacun se désabonne" on public.follows;
create policy "chacun se désabonne" on public.follows
  for delete to authenticated using (follower_id = auth.uid());

-- Anti-spam : 200 abonnements par heure et par compte.
create or replace function public.limit_follows() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from public.follows
      where follower_id = new.follower_id and created_at > now() - interval '1 hour') >= 200 then
    raise exception 'Trop d''abonnements en une heure : réessaie plus tard.';
  end if;
  return new;
end;
$$;
drop trigger if exists follows_limit on public.follows;
create trigger follows_limit before insert on public.follows
  for each row execute function public.limit_follows();

-- Nombre d'abonnés de chacun, tenu par le serveur.
create or replace function public.count_follows() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    update public.profiles set follower_count = follower_count + 1 where id = new.followee_id;
    return new;
  end if;
  update public.profiles set follower_count = greatest(follower_count - 1, 0) where id = old.followee_id;
  return old;
end;
$$;
drop trigger if exists follows_count on public.follows;
create trigger follows_count after insert or delete on public.follows
  for each row execute function public.count_follows();

-- ---------- Ajouts (« Ajoutée N fois ») ----------

-- Un ajout par personne et par partage, jamais pour son propre partage ; seulement par record_add.
-- Un numéro à elle et « une fois » à part (comme reports) : une clé (share_id, user_id) ferait d'adds un lien direct
-- entre partages et profils pour le serveur web, et la Communauté entière tomberait (12/11, voir plus bas).
create table if not exists public.adds (
  id uuid primary key default gen_random_uuid(),
  share_id uuid not null references public.shares (id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint adds_une_fois unique (share_id, user_id)
);
create index if not exists adds_user on public.adds (user_id);
alter table public.adds enable row level security;
drop policy if exists "chacun lit ses ajouts" on public.adds;
create policy "chacun lit ses ajouts" on public.adds
  for select to authenticated using (user_id = auth.uid());

create or replace function public.count_adds() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    update public.shares set add_count = add_count + 1 where id = new.share_id;
    return new;
  end if;
  update public.shares set add_count = greatest(add_count - 1, 0) where id = old.share_id;
  return old;
end;
$$;
drop trigger if exists adds_count on public.adds;
create trigger adds_count after insert or delete on public.adds
  for each row execute function public.count_adds();

-- « Ajouter à mes macros » / « Utiliser ces raccourcis » : compté une fois par personne, jamais pour son propre
-- partage ; rend le nombre d'ajouts du partage.
create or replace function public.record_add(p_share uuid) returns integer
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
  total integer;
begin
  if me is null then raise exception 'Connexion requise.'; end if;
  if not exists (select 1 from public.shares where id = p_share) then raise exception 'Partage introuvable.'; end if;
  insert into public.adds (share_id, user_id)
    select p_share, me where not exists (select 1 from public.shares where id = p_share and author_id = me)
    on conflict do nothing;
  select add_count into total from public.shares where id = p_share;
  return total;
end;
$$;
revoke all on function public.record_add(uuid) from public, anon;
grant execute on function public.record_add(uuid) to authenticated;

-- ---------- Notes (1 à 5 étoiles) ----------

-- Une note par personne et par partage, modifiable ; seulement par rate_share.
create table if not exists public.ratings (
  id uuid primary key default gen_random_uuid(),
  share_id uuid not null references public.shares (id) on delete cascade,
  user_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  stars smallint not null check (stars between 1 and 5),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint ratings_une_fois unique (share_id, user_id)
);

-- 12/11 (capture : « Could not embed because more than one relationship was found for 'shares' and 'profiles' »,
-- Communauté vide pour tout le monde) : les tables collées le 11/11 avaient la clé (share_id, user_id), que le serveur
-- web de Supabase (PostgREST) prend pour un lien direct entre partages et profils ; « author:profiles(username) » de
-- l'app en trouvait alors trois. Ici elles prennent la forme d'au-dessus, sans rien perdre : un numéro à chaque ligne,
-- « une fois par personne » posé avant que l'ancienne clé parte. Sans effet sur une base déjà à la bonne forme.
do $$
declare
  t text;
  old_key name;
begin
  foreach t in array array['adds', 'ratings'] loop
    execute format('alter table public.%I add column if not exists id uuid not null default gen_random_uuid()', t);
    if not exists (select 1 from pg_constraint where conrelid = format('public.%I', t)::regclass
                     and conname = t || '_une_fois') then
      execute format('alter table public.%I add constraint %I unique (share_id, user_id)', t, t || '_une_fois');
    end if;
    select c.conname into old_key
      from pg_constraint c
     where c.conrelid = format('public.%I', t)::regclass and c.contype = 'p'
       and c.conkey <> array[(select a.attnum from pg_attribute a where a.attrelid = c.conrelid and a.attname = 'id')];
    if old_key is not null then
      execute format('alter table public.%I drop constraint %I', t, old_key);
    end if;
    if not exists (select 1 from pg_constraint where conrelid = format('public.%I', t)::regclass and contype = 'p') then
      execute format('alter table public.%I add primary key (id)', t);
    end if;
  end loop;
end $$;
create index if not exists ratings_user on public.ratings (user_id, updated_at desc);
alter table public.ratings enable row level security;
drop policy if exists "chacun lit ses notes" on public.ratings;
create policy "chacun lit ses notes" on public.ratings
  for select to authenticated using (user_id = auth.uid());

create or replace function public.count_ratings() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then
    update public.shares set rating_sum = rating_sum + new.stars, rating_count = rating_count + 1 where id = new.share_id;
    return new;
  elsif tg_op = 'UPDATE' then
    update public.shares set rating_sum = rating_sum - old.stars + new.stars where id = new.share_id;
    return new;
  end if;
  update public.shares set rating_sum = greatest(rating_sum - old.stars, 0), rating_count = greatest(rating_count - 1, 0)
   where id = old.share_id;
  return old;
end;
$$;
drop trigger if exists ratings_count on public.ratings;
create trigger ratings_count after insert or update of stars or delete on public.ratings
  for each row execute function public.count_ratings();

-- Noter un partage : seulement après l'avoir ajouté, jamais le sien ; une nouvelle note remplace l'ancienne ; 200 notes
-- par heure et par compte au plus. Rend la somme et le nombre de notes du partage (moyenne = somme / nombre).
create or replace function public.rate_share(p_share uuid, p_stars integer)
returns table (rating_sum integer, rating_count integer)
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
begin
  if me is null then raise exception 'Connexion requise.'; end if;
  if p_stars is null or p_stars < 1 or p_stars > 5 then
    raise exception 'Une note de 1 à 5 étoiles.' using errcode = 'check_violation';
  end if;
  if not exists (select 1 from public.shares s where s.id = p_share) then raise exception 'Partage introuvable.'; end if;
  if exists (select 1 from public.shares s where s.id = p_share and s.author_id = me) then
    raise exception 'Tu ne peux pas noter ton propre partage.';
  end if;
  if not exists (select 1 from public.adds a where a.share_id = p_share and a.user_id = me) then
    raise exception 'Ajoute-le d''abord, puis note-le.';
  end if;
  if (select count(*) from public.ratings r where r.user_id = me and r.updated_at > now() - interval '1 hour') >= 200 then
    raise exception 'Trop de notes en une heure : réessaie plus tard.';
  end if;
  insert into public.ratings as r (share_id, user_id, stars) values (p_share, me, p_stars)
    on conflict (share_id, user_id) do update set stars = excluded.stars, updated_at = now();
  return query select s.rating_sum, s.rating_count from public.shares s where s.id = p_share;
end;
$$;
revoke all on function public.rate_share(uuid, integer) from public, anon;
grant execute on function public.rate_share(uuid, integer) to authenticated;

-- ---------- Classements ----------

-- Note d'un créateur : moyenne bayésienne de toutes les notes de ses partages (3 notes « fantômes » à 3,5) : une seule
-- note à 5 ★ ≈ 3,9 ; 1 000 notes à 4 ★ = 4,0. Personne n'est mis en avant pour une seule bonne note.
create or replace function public.creator_score(p_sum bigint, p_count bigint) returns numeric
language sql immutable as $$
  select round((3 * 3.5 + coalesce(p_sum, 0)) / (3 + coalesce(p_count, 0)), 3)
$$;

-- Partages des gens que l'on suit, les plus récents d'abord (onglet « Abonnements », rangée « De tes abonnements »).
create or replace function public.followed_shares(p_limit integer default 50) returns setof public.shares
language sql stable set search_path = public as $$
  select s.* from public.shares s
    join public.follows f on f.followee_id = s.author_id and f.follower_id = auth.uid()
   order by s.created_at desc
   limit least(greatest(coalesce(p_limit, 50), 1), 100)
$$;
revoke all on function public.followed_shares(integer) from public, anon;
grant execute on function public.followed_shares(integer) to authenticated;

-- Les plus ajoutés (déjà ajoutés au moins une fois), à égalité la meilleure note du créateur, puis les plus récents ;
-- `p_kind` : « macro » ou « profile », null pour tous.
create or replace function public.most_added(p_kind text default null, p_limit integer default 50) returns setof public.shares
language sql stable set search_path = public as $$
  with scores as (
    select author_id, public.creator_score(sum(rating_sum), sum(rating_count)) as score
      from public.shares group by author_id
  )
  select s.* from public.shares s join scores c on c.author_id = s.author_id
   where s.add_count > 0 and (p_kind is null or s.kind = p_kind)
   order by s.add_count desc, c.score desc, s.created_at desc
   limit least(greatest(coalesce(p_limit, 50), 1), 100)
$$;
revoke all on function public.most_added(text, integer) from public, anon;
grant execute on function public.most_added(text, integer) to authenticated;

-- Créateurs à suivre : ceux qui ont publié, ni soi ni ceux qu'on suit déjà ; meilleure note d'abord, puis le plus
-- d'ajouts, puis le plus d'abonnés.
create or replace function public.creators_to_follow(p_limit integer default 5)
returns table (id uuid, username text, follower_count integer, score numeric, adds bigint)
language sql stable set search_path = public as $$
  select p.id, p.username, p.follower_count,
         public.creator_score(sum(s.rating_sum), sum(s.rating_count)) as score, sum(s.add_count) as adds
    from public.profiles p join public.shares s on s.author_id = p.id
   where p.id <> auth.uid()
     and not exists (select 1 from public.follows f where f.follower_id = auth.uid() and f.followee_id = p.id)
   group by p.id, p.username, p.follower_count
   order by score desc, adds desc, p.follower_count desc, p.username
   limit least(greatest(coalesce(p_limit, 5), 1), 20)
$$;
revoke all on function public.creators_to_follow(integer) from public, anon;
grant execute on function public.creators_to_follow(integer) to authenticated;

-- Recollé : compteurs recalculés d'après les lignes (jamais faux après une panne).
update public.profiles p set follower_count = (select count(*) from public.follows f where f.followee_id = p.id)
 where follower_count <> (select count(*) from public.follows f where f.followee_id = p.id);
update public.shares s set add_count = (select count(*) from public.adds a where a.share_id = s.id),
       rating_sum = coalesce((select sum(stars) from public.ratings r where r.share_id = s.id), 0),
       rating_count = (select count(*) from public.ratings r where r.share_id = s.id);
