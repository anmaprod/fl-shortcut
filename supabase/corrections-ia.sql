-- IA intégrée de l'Organiser : corrections partagées avec l'accord de la personne (bouton « Pas content ? » et
-- changements faits dans l'aperçu) pour le prochain apprentissage de l'IA de tout le monde (ia/corrections.py).
-- Des nombres et des noms de familles et de sortes seulement : jamais le son, son nom ni un texte tapé.
-- Avec ou sans compte ; aucune règle de lecture : lues seulement dans Supabase (Table Editor › corrections_ia, export
-- CSV) ou par ia/corrections.py avec la clé secrète, donnée au moment de s'en servir, JAMAIS écrite dans le dépôt.
-- À coller dans Supabase › SQL Editor, après schema.sql (voir supabase/README.md). Peut être recollé sans risque :
-- ce qui existe déjà est gardé (corrections comprises), le reste est créé ou remis à jour.

create table if not exists public.corrections_ia (
  id uuid primary key default gen_random_uuid(),
  user_id uuid default auth.uid() references auth.users on delete set null,
  -- Ce que l'IA intégrée avait entendu, ce que l'Organiser avait décidé, et la bonne réponse (noms de ia/commun.py).
  famille_ia text not null check (famille_ia in ('voix', 'melodie', 'basse', 'drums', 'fx')),
  sorte_ia text check (sorte_ia ~ '^[A-Za-z0-9]{1,20}$'),
  famille_avant text not null default '' check (famille_avant in ('', 'voix', 'melodie', 'basse', 'drums', 'fx')),
  sorte_avant text check (sorte_avant ~ '^[A-Za-z0-9]{1,20}$'),
  famille text not null check (famille in ('voix', 'melodie', 'basse', 'drums', 'fx')),
  sorte text check (sorte ~ '^[A-Za-z0-9]{1,20}$'),
  -- Les 1216 nombres de chaque tranche (8 au plus), en 16 bits, en base64 : la taille va avec le nombre de tranches.
  tranches int not null check (tranches between 1 and 8),
  mesures text not null check (char_length(mesures) = 4 * ceil(tranches * 2432 / 3.0)::int
                               and mesures ~ '^[A-Za-z0-9+/]+={0,2}$'),
  -- Cases cochées dans « Pas content ? » (« voice,kind ») ou « apercu ».
  raisons text not null default '' check (raisons ~ '^[a-z,]{0,80}$'),
  modele int not null default 0 check (modele between 0 and 1000),
  app_version text not null default '' check (char_length(app_version) <= 20),
  created_at timestamptz not null default now()
);
create index if not exists corrections_ia_created_at on public.corrections_ia (created_at desc);
alter table public.corrections_ia enable row level security;
drop policy if exists "chacun partage ses corrections" on public.corrections_ia;
create policy "chacun partage ses corrections" on public.corrections_ia
  for insert to anon, authenticated with check (user_id is null or user_id = auth.uid());

-- Anti-spam : 3000 corrections par heure en tout, 300 par heure pour un même compte.
create or replace function public.limit_corrections() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from public.corrections_ia where created_at > now() - interval '1 hour') >= 3000
     or (new.user_id is not null and (select count(*) from public.corrections_ia
          where created_at > now() - interval '1 hour' and user_id = new.user_id) >= 300) then
    raise exception 'Trop de corrections en ce moment : réessaie dans une heure.';
  end if;
  return new;
end;
$$;
drop trigger if exists corrections_limit on public.corrections_ia;
create trigger corrections_limit before insert on public.corrections_ia
  for each row execute function public.limit_corrections();
