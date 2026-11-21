-- Essai de messages-par-mail.sql (lancé par supabase/tests/run.sh) : pas réglé, rien n'est envoyé ; réglé, chaque
-- message part par Resend vers l'adresse du propriétaire (réponse à la personne si elle a laissé son mail) ; un
-- envoi qui échoue ne perd jamais le message.
\set ON_ERROR_STOP on

do $$
declare
  appel record;
begin
  -- Clé d'exemple encore là : le message reste dans la table, aucun mail.
  set local role anon;
  insert into public.support_requests (kind, message, email, app_version)
    values ('probleme', 'Le lien MIDI ne répond pas.', 'ami@exemple.fr', '0.2.0');
  reset role;
  if (select count(*) from net.calls) <> 0 then raise exception 'mail envoyé avec la clé d''exemple'; end if;

  -- Réglé (comme en recollant le fichier avec une vraie clé) : le mail part.
  perform vault.update_secret((select id from vault.secrets where name = 'fls_resend_key'), 're_essai');
  perform vault.update_secret((select id from vault.secrets where name = 'fls_support_to'), 'flshortcuts@exemple.fr');
  set local role anon;
  insert into public.support_requests (kind, reference, message, email, diagnostic, app_version)
    values ('probleme', 'FLS-ABC123', 'Le lien MIDI ne répond pas.', 'ami@exemple.fr', 'lien muet · ports oui', '0.2.0');
  reset role;
  select * into appel from net.calls order by id desc limit 1;
  if appel.url <> 'https://api.resend.com/emails' then raise exception 'mauvaise adresse d''envoi : %', appel.url; end if;
  if appel.body -> 'to' <> '["flshortcuts@exemple.fr"]'::jsonb then raise exception 'mauvais destinataire : %', appel.body; end if;
  if appel.body ->> 'subject' <> 'FL Shortcuts · Problème · FLS-ABC123' then raise exception 'sujet : %', appel.body ->> 'subject'; end if;
  if appel.body ->> 'reply_to' <> 'ami@exemple.fr' then raise exception 'pas de réponse possible : %', appel.body; end if;
  if position('lien muet' in appel.body ->> 'text') = 0 then raise exception 'état de l''app absent'; end if;
  if appel.headers ->> 'Authorization' <> 'Bearer re_essai' then raise exception 'clé absente'; end if;

  -- Sans mail laissé : pas de « répondre à ».
  set local role anon;
  insert into public.support_requests (kind, message) values ('idee', 'Un thème bleu, peut-être ?');
  reset role;
  select * into appel from net.calls order by id desc limit 1;
  if appel.body ? 'reply_to' then raise exception 'répondre à sans mail'; end if;
  if appel.body ->> 'subject' <> 'FL Shortcuts · Idée' then raise exception 'sujet sans référence : %', appel.body ->> 'subject'; end if;
end $$;

-- L'envoi échoue (Resend injoignable) : le message est gardé quand même.
create or replace function net.http_post(url text, body jsonb default '{}', params jsonb default '{}',
                                         headers jsonb default '{}', timeout_milliseconds integer default 5000)
returns bigint language plpgsql as $$ begin raise exception 'réseau coupé'; end $$;
do $$
declare
  avant bigint := (select count(*) from public.support_requests);
begin
  set local role anon;
  insert into public.support_requests (kind, message) values ('question', 'Comment on installe loopMIDI ?');
  reset role;
  if (select count(*) from public.support_requests) <> avant + 1 then raise exception 'message perdu quand le mail échoue'; end if;
end $$;
select 'messages par mail : tout est conforme' as resultat;
