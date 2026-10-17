-- Communauté de FL Shortcuts : comptes (mail, mot de passe, nom d'utilisateur) et partages de macros / profils.
-- À coller une fois dans Supabase › SQL Editor (voir supabase/README.md). Rien n'est lisible sans compte :
-- toutes les règles visent le rôle « authenticated », jamais « anon ».

-- Profils publics : un par compte, créé par le déclencheur ci-dessous à l'inscription.
create table public.profiles (
  id uuid primary key references auth.users on delete cascade,
  username text not null check (username ~ '^[A-Za-z0-9_.-]{3,24}$'),
  created_at timestamptz not null default now()
);
-- Unique sans tenir compte des majuscules (« Malo » et « malo » sont le même nom).
create unique index profiles_username on public.profiles (lower(username));

-- Administrateurs (ajoutés à la main dans Table Editor) : peuvent supprimer n'importe quel partage et lire les
-- signalements. Aucune règle : la table n'est jamais lisible ni modifiable depuis l'app.
create table public.admins (
  user_id uuid primary key references auth.users on delete cascade
);

create table public.shares (
  id uuid primary key default gen_random_uuid(),
  author_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  kind text not null check (kind in ('macro', 'profile')),
  title text not null check (char_length(title) between 3 and 80),
  notes text not null default '' check (char_length(notes) <= 4000),
  -- Le fichier exporté (.flsmacro ou profil .json), relu par l'app avant tout import.
  payload text not null check (octet_length(payload) <= 262144),
  app_version text not null default '' check (char_length(app_version) <= 20),
  created_at timestamptz not null default now()
);
create index shares_created_at on public.shares (created_at desc);

create table public.reports (
  id uuid primary key default gen_random_uuid(),
  share_id uuid not null references public.shares (id) on delete cascade,
  reporter_id uuid not null default auth.uid() references public.profiles (id) on delete cascade,
  reason text not null check (char_length(reason) between 3 and 500),
  created_at timestamptz not null default now(),
  unique (share_id, reporter_id)
);

alter table public.profiles enable row level security;
alter table public.admins enable row level security;
alter table public.shares enable row level security;
alter table public.reports enable row level security;

create function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from public.admins where user_id = auth.uid())
$$;
-- Appelée par les règles ci-dessous et par l'app (menu « Supprimer » d'un administrateur).
revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated;

create policy "profils lisibles par les comptes" on public.profiles
  for select to authenticated using (true);

create policy "partages lisibles par les comptes" on public.shares
  for select to authenticated using (true);
create policy "chacun publie en son nom" on public.shares
  for insert to authenticated with check (author_id = auth.uid());
create policy "l'auteur ou un administrateur supprime" on public.shares
  for delete to authenticated using (author_id = auth.uid() or public.is_admin());

create policy "chacun signale en son nom" on public.reports
  for insert to authenticated with check (reporter_id = auth.uid());
create policy "signalements lus par les administrateurs" on public.reports
  for select to authenticated using (public.is_admin());

-- Inscription : le nom d'utilisateur vient des métadonnées envoyées par l'app ; invalide ou déjà pris, l'inscription
-- échoue (contrainte de la table).
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, username) values (new.id, new.raw_user_meta_data ->> 'username');
  return new;
end;
$$;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Nom d'utilisateur libre ? Appelé par l'app avant l'inscription, pour un message clair (sans compte : c'est la
-- seule chose que l'on peut demander sans être connecté, et elle ne révèle rien d'autre).
create function public.username_available(name text) returns boolean
language sql stable security definer set search_path = public as $$
  select not exists (select 1 from public.profiles where lower(username) = lower(name))
$$;
revoke all on function public.username_available(text) from public;
grant execute on function public.username_available(text) to anon, authenticated;

-- Au plus 20 partages par compte et par 24 h (contre le spam).
create function public.limit_shares() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from public.shares
      where author_id = new.author_id and created_at > now() - interval '24 hours') >= 20 then
    raise exception 'Trop de partages aujourd''hui (20 au plus par 24 h).';
  end if;
  return new;
end;
$$;
create trigger shares_limit before insert on public.shares
  for each row execute function public.limit_shares();

-- Aide : « Écrire à l'équipe » depuis la page Aide de l'app, avec ou sans compte. Lues seulement dans Supabase
-- (Table Editor › support_requests) : aucune règle de lecture, rien n'est relisible depuis l'app.
create table public.support_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid default auth.uid() references auth.users on delete set null,
  kind text not null check (kind in ('probleme', 'question', 'idee')),
  -- « FLS-3F9A2C », aussi dans le mail envoyé sans serveur : retrouver un message et y répondre.
  reference text not null default '' check (char_length(reference) <= 20),
  message text not null check (char_length(message) between 10 and 4000),
  -- Le message d'erreur signalé (bouton « Signaler ce problème » d'une macro qui échoue).
  error text not null default '' check (char_length(error) <= 2000),
  -- Pour répondre ; facultatif (sans mail, on ne peut pas répondre).
  email text check (email is null or (char_length(email) <= 254 and email ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$')),
  -- État de l'app, derniers problèmes et journal de la dernière macro, joints si l'utilisateur le laisse coché
  -- (jamais de touches, de noms de pistes ni de fichiers).
  diagnostic text not null default '' check (char_length(diagnostic) <= 12000),
  app_version text not null default '' check (char_length(app_version) <= 20),
  created_at timestamptz not null default now()
);
create index support_requests_created_at on public.support_requests (created_at desc);
alter table public.support_requests enable row level security;
create policy "chacun écrit à l'équipe" on public.support_requests
  for insert to anon, authenticated with check (user_id is null or user_id = auth.uid());

-- Anti-spam : 5 messages par heure pour un même mail ou un même compte, 100 par heure en tout.
create function public.limit_support() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from public.support_requests where created_at > now() - interval '1 hour') >= 100
     or ((new.email is not null or new.user_id is not null) and (select count(*) from public.support_requests
          where created_at > now() - interval '1 hour'
            and (lower(email) = lower(new.email) or user_id = new.user_id)) >= 5) then
    raise exception 'Trop de messages en ce moment : réessaie dans une heure.';
  end if;
  return new;
end;
$$;
create trigger support_limit before insert on public.support_requests
  for each row execute function public.limit_support();
