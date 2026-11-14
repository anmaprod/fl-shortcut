-- Sauvegarde en ligne du compte : les raccourcis et les macros de chacun, lisibles et modifiables par lui seul.
-- À coller dans Supabase › SQL Editor APRÈS schema.sql (une fois ; voir supabase/README.md). L'app envoie la
-- sauvegarde quelques secondes après chaque changement, la reprend à la connexion (sur ce Mac ou un autre) et
-- vide le Mac à la déconnexion (Sources/FLShortcut/AccountBackup.swift).

create table public.backups (
  user_id uuid primary key default auth.uid() references auth.users on delete cascade,
  -- Les fichiers de l'app, tels quels : profile.json (raccourcis) et macros.json (macros en blocs).
  profile text not null check (octet_length(profile) <= 2097152),
  macros text not null check (octet_length(macros) <= 6291456),
  -- +1 à chaque enregistrement : un Mac n'écrase jamais une sauvegarde plus récente faite ailleurs sans le savoir.
  revision bigint not null default 1,
  app_version text not null default '' check (char_length(app_version) <= 20),
  updated_at timestamptz not null default now()
);
alter table public.backups enable row level security;
create policy "sa sauvegarde : lire" on public.backups
  for select to authenticated using (user_id = auth.uid());
create policy "sa sauvegarde : créer" on public.backups
  for insert to authenticated with check (user_id = auth.uid());
create policy "sa sauvegarde : modifier" on public.backups
  for update to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());
create policy "sa sauvegarde : supprimer" on public.backups
  for delete to authenticated using (user_id = auth.uid());

-- Enregistre la sauvegarde si elle n'a pas changé depuis la révision `p_base` (la dernière que ce Mac a lue ou
-- écrite ; 0 : aucune encore). Sinon refus « Sauvegarde plus récente… », sauf `p_force` (l'utilisateur a choisi
-- de garder ce qu'il y a sur ce Mac). Renvoie la nouvelle révision. Règles d'accès appliquées (security invoker).
create function public.save_backup(p_profile text, p_macros text, p_base bigint, p_force boolean default false,
                                   p_app_version text default '')
returns bigint
language plpgsql security invoker set search_path = public as $$
declare
  current_revision bigint;
begin
  if auth.uid() is null then raise exception 'Connexion requise.'; end if;
  select revision into current_revision from public.backups where user_id = auth.uid() for update;
  if current_revision is null then
    insert into public.backups (user_id, profile, macros, revision, app_version)
      values (auth.uid(), p_profile, p_macros, 1, left(p_app_version, 20));
    return 1;
  end if;
  if current_revision <> p_base and not p_force then
    raise exception 'Sauvegarde plus récente sur le compte (révision %).', current_revision;
  end if;
  update public.backups
     set profile = p_profile, macros = p_macros, revision = current_revision + 1,
         app_version = left(p_app_version, 20), updated_at = now()
   where user_id = auth.uid();
  return current_revision + 1;
end;
$$;
revoke all on function public.save_backup(text, text, bigint, boolean, text) from public, anon;
grant execute on function public.save_backup(text, text, bigint, boolean, text) to authenticated;

-- « Supprimer mon compte » (page Mon compte) : le compte et tout ce qui en dépend (profil public, partages,
-- signalements, sauvegarde) ; les messages à l'équipe restent, sans lien avec le compte.
create function public.delete_my_account() returns void
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Connexion requise.'; end if;
  delete from auth.users where id = auth.uid();
end;
$$;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
