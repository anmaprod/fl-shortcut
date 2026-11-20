-- Essai de mes-messages.sql (lancé par supabase/tests/run.sh, après messages-par-mail.sql recollé) : genre « Autre »,
-- capture, chacun ne relit que ses messages, réponses de l'équipe et de la personne, repondre(), mails des réponses.
-- Comptes d'essai à part (Mia 0…0d1, Tom 0…0d2).
\set ON_ERROR_STOP on

insert into auth.users (id, email, raw_user_meta_data) values
  ('00000000-0000-0000-0000-0000000000d1', 'mia@exemple.fr', '{"username":"mia_essai"}'),
  ('00000000-0000-0000-0000-0000000000d2', 'tom@exemple.fr', '{"username":"tom_essai"}')
  on conflict (id) do nothing;
insert into public.profiles (id, username) values
  ('00000000-0000-0000-0000-0000000000d1', 'mia_essai'), ('00000000-0000-0000-0000-0000000000d2', 'tom_essai')
  on conflict (id) do update set username = excluded.username;

-- Mia écrit (genre « Autre », avec une capture) ; une capture qui n'est pas un JPEG en base64 est refusée.
set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-0000000000d1';
insert into public.support_requests (id, kind, reference, message, app_version, capture) values
  ('00000000-0000-0000-0000-00000000d1a1', 'autre', 'FLS-D1A1D1', 'Une remarque sur les couleurs.', '0.3.0', '/9j/4AAQSkZJRg==');
do $$
begin
  insert into public.support_requests (kind, message, capture) values ('autre', 'Une autre remarque.', '<script>');
  raise exception 'capture qui n''est pas une image acceptée';
exception when check_violation then null;
end $$;
do $$
begin
  insert into public.support_requests (kind, message) values ('bavardage', 'Un genre inconnu.');
  raise exception 'genre inconnu accepté';
exception when check_violation then null;
end $$;
reset role;

do $$
declare
  appel record;
begin
  select * into appel from net.calls order by id desc limit 1;
  if appel.body ->> 'subject' <> 'FL Shortcuts · Autre · FLS-D1A1D1' then raise exception 'sujet : %', appel.body ->> 'subject'; end if;
  if appel.body -> 'attachments' -> 0 ->> 'content' <> '/9j/4AAQSkZJRg==' then raise exception 'capture absente du mail'; end if;
  if position('select public.repondre(''FLS-D1A1D1''' in appel.body ->> 'text') = 0 then
    raise exception 'comment répondre absent du mail : %', appel.body ->> 'text';
  end if;
end $$;

-- Tom ne voit pas les messages de Mia, ni leurs réponses ; il ne peut pas y répondre.
set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-0000000000d2';
do $$
begin
  if exists (select 1 from public.support_requests where id = '00000000-0000-0000-0000-00000000d1a1') then
    raise exception 'Tom lit le message de Mia';
  end if;
  begin
    insert into public.support_replies (request_id, message) values ('00000000-0000-0000-0000-00000000d1a1', 'Coucou');
    raise exception 'Tom répond à la place de Mia';
  exception when insufficient_privilege then null;
  end;
end $$;
reset role;

-- Sans compte : rien de lisible.
set role anon;
set request.jwt.claim.sub to '';
do $$
begin
  if exists (select 1 from public.support_requests) or exists (select 1 from public.support_replies) then
    raise exception 'messages lisibles sans compte';
  end if;
end $$;
reset role;

-- L'équipe répond depuis SQL Editor (repondre) : réponse de l'équipe, sans mail pour elle-même.
set request.jwt.claim.sub to '';
do $$
declare
  avant bigint := (select count(*) from net.calls);
begin
  perform public.repondre('fls-d1a1d1', $t$Merci ! C'est noté.$t$);
  if (select team from public.support_replies where request_id = '00000000-0000-0000-0000-00000000d1a1') is not true then
    raise exception 'réponse de l''équipe pas marquée « équipe »';
  end if;
  if (select count(*) from net.calls) <> avant then raise exception 'mail envoyé pour la réponse de l''équipe'; end if;
  begin
    perform public.repondre('FLS-000000', 'Personne.');
    raise exception 'réponse à un message inconnu';
  exception when raise_exception then
    if sqlerrm not like 'Aucun message%' then raise; end if;
  end;
end $$;

-- Mia relit son message et la réponse, puis répond : sa réponse n'est jamais « de l'équipe », et un mail part.
set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-0000000000d1';
do $$
begin
  if (select count(*) from public.support_requests where id = '00000000-0000-0000-0000-00000000d1a1') <> 1 then
    raise exception 'Mia ne relit pas son message';
  end if;
  if (select message from public.support_replies where team) <> $t$Merci ! C'est noté.$t$ then
    raise exception 'Mia ne lit pas la réponse de l''équipe';
  end if;
  insert into public.support_replies (request_id, team, message)
    values ('00000000-0000-0000-0000-00000000d1a1', true, '  Super, merci.  ');
  if (select count(*) from public.support_replies where not team and message = 'Super, merci.') <> 1 then
    raise exception 'réponse de Mia marquée « équipe » ou pas nettoyée';
  end if;
end $$;
reset role;
do $$
declare
  appel record;
begin
  select * into appel from net.calls order by id desc limit 1;
  if appel.body ->> 'subject' <> 'Re: FL Shortcuts · FLS-D1A1D1' then raise exception 'sujet de la réponse : %', appel.body ->> 'subject'; end if;
  if position('Super, merci.' in appel.body ->> 'text') = 0 or position('mia_essai' in appel.body ->> 'text') = 0 then
    raise exception 'réponse de Mia mal envoyée : %', appel.body ->> 'text';
  end if;
end $$;

-- Anti-spam : 20 réponses par heure et par compte.
set role authenticated;
set request.jwt.claim.sub to '00000000-0000-0000-0000-0000000000d1';
do $$
begin
  for i in 1..19 loop
    insert into public.support_replies (request_id, message) values ('00000000-0000-0000-0000-00000000d1a1', 'Encore ' || i);
  end loop;
  insert into public.support_replies (request_id, message) values ('00000000-0000-0000-0000-00000000d1a1', 'Une de trop');
  raise exception '21e réponse de l''heure acceptée';
exception when raise_exception then
  if sqlerrm not like 'Trop de messages%' then raise; end if;
end $$;
reset role;
set request.jwt.claim.sub to '';

select 'mes messages : tout est conforme' as resultat;
