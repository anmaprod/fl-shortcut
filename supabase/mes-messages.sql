-- Aide › Mes messages (20/11, maquette « Minimal ») : chacun relit les messages qu'il a envoyés à l'équipe avec son
-- compte, voit la réponse de l'équipe et peut répondre à son tour. Un message peut avoir une capture d'écran
-- (facultative) et le genre « Autre ».
-- À coller dans Supabase › SQL Editor après schema.sql (voir supabase/README.md, étape 13). Peut être relancé sans
-- risque. Sans ce fichier, l'app envoie les messages comme avant et dit que « Mes messages » n'est pas encore ouvert.
--
-- RÉPONDRE À QUELQU'UN (toi, dans SQL Editor) : la référence est dans le sujet du mail (« FLS-3F9A2C ») ; écris ta
-- réponse entre les $$, apostrophes comprises :
--   select public.repondre('FLS-3F9A2C', $$Merci ! C'est corrigé dans la prochaine version.$$);
-- La personne la voit dans Aide › Mes messages (point rouge). Un message envoyé sans compte : réponds par mail.

-- Genre « Autre » en plus de problème, question et idée.
alter table public.support_requests drop constraint if exists support_requests_kind_check;
alter table public.support_requests add constraint support_requests_kind_check
  check (kind in ('probleme', 'question', 'idee', 'autre'));

-- Capture facultative : préparée par l'app (JPEG, 1600 points de large au plus), gardée en base64.
alter table public.support_requests add column if not exists capture text;
alter table public.support_requests drop constraint if exists support_requests_capture_ok;
alter table public.support_requests add constraint support_requests_capture_ok
  check (capture is null or (octet_length(capture) <= 1048576 and left(capture, 4) = '/9j/'
                             and capture ~ '^[A-Za-z0-9+/]+={0,2}$'));

-- Chacun relit les messages envoyés avec son compte (jamais ceux des autres, jamais ceux envoyés sans compte).
drop policy if exists "chacun lit ses messages" on public.support_requests;
create policy "chacun lit ses messages" on public.support_requests
  for select to authenticated using (user_id = auth.uid());

-- Les réponses : celles de l'équipe (écrites depuis Supabase, `team` vrai) et celles de la personne.
create table if not exists public.support_replies (
  id uuid primary key default gen_random_uuid(),
  request_id uuid not null references public.support_requests (id) on delete cascade,
  team boolean not null default false,
  message text not null check (char_length(message) between 1 and 4000),
  created_at timestamptz not null default now()
);
create index if not exists support_replies_request on public.support_replies (request_id, created_at);
alter table public.support_replies enable row level security;
drop policy if exists "chacun lit les réponses à ses messages" on public.support_replies;
create policy "chacun lit les réponses à ses messages" on public.support_replies
  for select to authenticated
  using (exists (select 1 from public.support_requests r where r.id = request_id and r.user_id = auth.uid()));
drop policy if exists "chacun répond à ses messages" on public.support_replies;
create policy "chacun répond à ses messages" on public.support_replies
  for insert to authenticated
  with check (team = false
              and exists (select 1 from public.support_requests r where r.id = request_id and r.user_id = auth.uid()));

-- Qui écrit : depuis l'app (rôles anon, authenticated), jamais l'équipe ; depuis Supabase (SQL Editor, Table Editor,
-- repondre), toujours l'équipe. Anti-spam : 20 réponses par heure et par compte.
create or replace function public.support_reply_author() returns trigger
language plpgsql set search_path = public as $$
begin
  if current_user in ('anon', 'authenticated') then
    new.team := false;
    if (select count(*) from public.support_replies p join public.support_requests r on r.id = p.request_id
         where r.user_id = auth.uid() and not p.team and p.created_at > now() - interval '1 hour') >= 20 then
      raise exception 'Trop de messages en ce moment : réessaie dans une heure.';
    end if;
  else
    new.team := true;
  end if;
  new.message := btrim(new.message);
  return new;
end;
$$;
drop trigger if exists support_reply_author on public.support_replies;
create trigger support_reply_author before insert on public.support_replies
  for each row execute function public.support_reply_author();

-- Répondre à un message, depuis SQL Editor (voir en haut) : la référence du mail, puis ta réponse.
create or replace function public.repondre(p_reference text, p_message text) returns text
language plpgsql security definer set search_path = public as $$
declare
  rid uuid;
  owner uuid;
begin
  select id, user_id into rid, owner from public.support_requests
   where upper(reference) = upper(btrim(p_reference)) order by created_at desc limit 1;
  if rid is null then raise exception 'Aucun message « % ».', p_reference; end if;
  if owner is null then raise exception 'Ce message a été envoyé sans compte : réponds-lui par mail.'; end if;
  if coalesce(btrim(p_message), '') = '' then raise exception 'Ta réponse est vide.'; end if;
  insert into public.support_replies (request_id, team, message) values (rid, true, p_message);
  return 'Réponse envoyée : la personne la voit dans Aide › Mes messages.';
end;
$$;
revoke all on function public.repondre(text, text) from public, anon, authenticated;
