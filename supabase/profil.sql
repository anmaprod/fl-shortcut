-- Profil public : pseudo modifiable et photo de profil (page Mon compte › Modifier le profil), visibles par les
-- comptes connectés (Communauté : cartes des partages, page d'un auteur). Une photo peut être signalée par les autres ;
-- un administrateur (table admins) peut la retirer.
-- À coller dans Supabase › SQL Editor après schema.sql et inscription.sql (voir supabase/README.md, étape 10). Peut
-- être relancé sans risque. Sans ce fichier, l'app garde l'initiale de couleur et dit que les photos et le
-- changement de pseudo ne sont pas encore ouverts.

-- Photo : préparée par l'app (carré de 256 × 256, JPEG, ≈ 20 à 40 Ko), gardée en base64. Une ligne par compte qui en a
-- une ; lisible par les comptes connectés seulement, jamais modifiable directement (fonctions ci-dessous).
create table if not exists public.avatars (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  image text not null check (octet_length(image) <= 98304 and left(image, 4) = '/9j/' and image ~ '^[A-Za-z0-9+/]+={0,2}$'),
  updated_at timestamptz not null default now()
);
alter table public.avatars enable row level security;
drop policy if exists "photos lisibles par les comptes" on public.avatars;
create policy "photos lisibles par les comptes" on public.avatars
  for select to authenticated using (true);

-- Signalement d'une photo (« Signaler la photo… » sur la page d'un auteur) : un par photo et par compte, jamais la
-- sienne ; lus par les administrateurs seulement.
create table if not exists public.avatar_reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  reporter_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  reason text not null default '' check (char_length(reason) <= 500),
  created_at timestamptz not null default now(),
  unique (user_id, reporter_id)
);
alter table public.avatar_reports enable row level security;
drop policy if exists "chacun signale une photo en son nom" on public.avatar_reports;
create policy "chacun signale une photo en son nom" on public.avatar_reports
  for insert to authenticated with check (reporter_id = auth.uid() and user_id <> auth.uid());
drop policy if exists "signalements de photos lus par les administrateurs" on public.avatar_reports;
create policy "signalements de photos lus par les administrateurs" on public.avatar_reports
  for select to authenticated using (public.is_admin());

-- Sa photo : posée ou remplacée (date de la photo renvoyée : l'app s'en sert pour ne pas la recharger).
create or replace function public.set_avatar(p_image text) returns timestamptz
language plpgsql security definer set search_path = public as $$
declare
  stamp timestamptz := clock_timestamp();
begin
  if auth.uid() is null then raise exception 'Connexion requise.'; end if;
  if not exists (select 1 from public.profiles where id = auth.uid()) then raise exception 'Profil introuvable.'; end if;
  if exists (select 1 from public.avatars where user_id = auth.uid() and updated_at > now() - interval '5 seconds') then
    raise exception 'Attends quelques secondes avant de changer encore ta photo.';
  end if;
  insert into public.avatars (user_id, image, updated_at) values (auth.uid(), p_image, stamp)
    on conflict (user_id) do update set image = excluded.image, updated_at = excluded.updated_at;
  return stamp;
end;
$$;
revoke all on function public.set_avatar(text) from public, anon;
grant execute on function public.set_avatar(text) to authenticated;

-- Sa photo retirée (« Retirer » : l'initiale de couleur revient).
create or replace function public.remove_avatar() returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Connexion requise.'; end if;
  delete from public.avatars where user_id = auth.uid();
end;
$$;
revoke all on function public.remove_avatar() from public, anon;
grant execute on function public.remove_avatar() to authenticated;

-- Administrateur : retire la photo d'un membre (après un signalement) ; ses signalements sont traités.
create or replace function public.admin_remove_avatar(p_user uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then raise exception 'Réservé aux administrateurs.'; end if;
  delete from public.avatars where user_id = p_user;
  delete from public.avatar_reports where user_id = p_user;
end;
$$;
revoke all on function public.admin_remove_avatar(uuid) from public, anon;
grant execute on function public.admin_remove_avatar(uuid) to authenticated;

-- Pseudo : changé depuis Mon compte. Les partages déjà publiés prennent le nouveau (ils montrent le profil de leur
-- auteur) ; le compte aussi (métadonnées : l'app le relit à la connexion). Une fois par minute au plus.
alter table public.profiles add column if not exists username_changed_at timestamptz;

create or replace function public.set_username(p_name text) returns text
language plpgsql security definer set search_path = public as $$
declare
  me uuid := auth.uid();
begin
  if me is null then raise exception 'Connexion requise.'; end if;
  if p_name is null or p_name !~ '^[A-Za-z0-9_.-]{3,24}$' then
    raise exception 'Pseudo invalide.' using errcode = 'check_violation';
  end if;
  if exists (select 1 from public.profiles where lower(username) = lower(p_name) and id <> me) then
    raise exception 'Pseudo déjà pris.' using errcode = 'unique_violation';
  end if;
  if exists (select 1 from public.profiles where id = me and username_changed_at > now() - interval '1 minute') then
    raise exception 'Attends une minute avant de changer encore de pseudo.';
  end if;
  update public.profiles set username = p_name, username_changed_at = now() where id = me;
  if not found then raise exception 'Profil introuvable.'; end if;
  update auth.users
     set raw_user_meta_data = coalesce(raw_user_meta_data, '{}'::jsonb) || jsonb_build_object('username', p_name)
   where id = me;
  return p_name;
end;
$$;
revoke all on function public.set_username(text) from public, anon;
grant execute on function public.set_username(text) to authenticated;
