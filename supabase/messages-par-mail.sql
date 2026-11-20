-- Les messages « Écrire à l'équipe » (page Aide de l'app, Mac et Windows) reçus PAR MAIL (09/11, demande du
-- propriétaire : « que je reçoive les messages… sûrement dans mes mails… quelque chose de simple »).
--
-- Chaque message qui arrive dans la table support_requests part aussitôt dans ta boîte mail, par Resend (service
-- d'envoi de mails, gratuit jusqu'à 3 000 mails par mois). « Répondre » dans ta boîte mail répond directement à la
-- personne quand elle a laissé son mail.
--
-- À FAIRE UNE FOIS (5 minutes) :
--   1. Sur https://resend.com, crée un compte AVEC L'ADRESSE OÙ TU VEUX RECEVOIR LES MESSAGES (sans domaine à toi,
--      Resend n'envoie qu'à l'adresse du compte : c'est exactement ce qu'il faut ici).
--   2. Resend › API Keys › Create API Key (« Sending access ») : copie la clé, elle commence par « re_ ».
--   3. Supabase › SQL Editor › New query : colle TOUT ce fichier, remplace les deux lignes marquées ⬇ ci-dessous
--      (ta clé et ton adresse), puis Run. « Success. No rows returned » : c'est en place.
--   4. Essaie : Aide › Écrire à l'équipe dans l'app ; le mail arrive en quelques secondes (regarde aussi les spams
--      la première fois).
-- Peut être recollé sans risque (pour changer de clé ou d'adresse ; recollé tel quel, sans rien remplacer, il garde ta
-- clé et ton adresse et met seulement le reste à jour). Pour arrêter : `drop trigger support_mail on
-- public.support_requests;`. La clé et l'adresse restent dans le coffre de Supabase (Vault), jamais dans l'app ni
-- dans le dépôt. Si l'envoi du mail échoue, le message reste quand même dans la table (Table Editor › support_requests).

create extension if not exists pg_net;

-- Ta clé Resend et ton adresse, gardées dans le coffre de Supabase (mises à jour si ce fichier est recollé).
do $$
declare
  cle constant text := 're_TA_CLE_RESEND';            -- ⬇ remplace par ta clé Resend (« re_… »)
  adresse constant text := 'ton.adresse@exemple.fr';  -- ⬇ remplace par l'adresse de ton compte Resend
  sid uuid;
begin
  -- Les deux lignes d'exemple laissées telles quelles ne remplacent jamais une vraie clé ou une vraie adresse.
  select id into sid from vault.secrets where name = 'fls_resend_key';
  if sid is null then
    perform vault.create_secret(cle, 'fls_resend_key', 'Clé Resend : messages « Écrire à l''équipe » de FL Shortcuts');
  elsif cle <> 're_TA_CLE_RESEND' then
    perform vault.update_secret(sid, cle);
  end if;
  select id into sid from vault.secrets where name = 'fls_support_to';
  if sid is null then
    perform vault.create_secret(adresse, 'fls_support_to', 'Adresse qui reçoit les messages de FL Shortcuts');
  elsif adresse <> 'ton.adresse@exemple.fr' then
    perform vault.update_secret(sid, adresse);
  end if;
end $$;

-- Le mail d'un message : sujet « FL Shortcuts · Problème · FLS-3F9A2C », le message, l'erreur signalée, le mail de
-- la personne, la version de l'app, le compte (son pseudo s'il est connecté), puis l'état de l'app joint (des
-- nombres, jamais de nom de son ni de touche tapée).
create or replace function public.mail_support() returns trigger
language plpgsql security definer set search_path = public, extensions as $corps$
declare
  k text;
  dest text;
  sujet text;
  corps text;
  envoi jsonb;
  pseudo text;
  capture text;
begin
  select decrypted_secret into k from vault.decrypted_secrets where name = 'fls_resend_key';
  select decrypted_secret into dest from vault.decrypted_secrets where name = 'fls_support_to';
  if k is null or dest is null or k = 're_TA_CLE_RESEND' then
    return new;                       -- pas encore réglé : le message reste seulement dans la table
  end if;
  if new.user_id is not null then
    begin
      select username into pseudo from public.profiles where id = new.user_id;
    exception when others then
      pseudo := null;                 -- pas de pseudo lisible : « connecté » seulement
    end;
  end if;
  sujet := 'FL Shortcuts · '
    || case new.kind when 'probleme' then 'Problème' when 'question' then 'Question' when 'idee' then 'Idée'
                     else 'Autre' end
    || case when new.reference <> '' then ' · ' || new.reference else '' end;
  corps := new.message
    || case when new.error <> '' then E'\n\nErreur signalée :\n' || new.error else '' end
    || E'\n\n— '
    || coalesce('Mail pour répondre : ' || new.email, 'Pas de mail laissé (on ne peut pas répondre).')
    || E'\nVersion de l''app : ' || coalesce(nullif(new.app_version, ''), '?')
    || E'\nCompte : ' || case when new.user_id is null then 'non connecté'
                              else 'connecté' || coalesce(' (' || pseudo || ')', '') end
    || case when new.diagnostic <> '' then E'\n\nÉtat de l''app :\n' || new.diagnostic else '' end
    -- 20/11 (Aide › Mes messages, supabase/mes-messages.sql) : répondre dans l'app, depuis SQL Editor.
    || case when new.user_id is not null and new.reference <> ''
            then E'\n\nRépondre dans l''app (Supabase › SQL Editor) :\nselect public.repondre('''
                 || new.reference || ''', $$ta réponse$$);'
            else '' end;
  envoi := jsonb_build_object(
    'from', 'FL Shortcuts <onboarding@resend.dev>',
    'to', jsonb_build_array(dest),
    'subject', sujet,
    'text', corps);
  if new.email is not null then
    envoi := envoi || jsonb_build_object('reply_to', new.email);
  end if;
  -- Capture jointe (facultative, 20/11) : lue sans nommer la colonne, absente avant mes-messages.sql.
  capture := to_jsonb(new) ->> 'capture';
  if capture is not null and capture <> '' then
    envoi := envoi || jsonb_build_object('attachments',
      jsonb_build_array(jsonb_build_object('filename', 'capture.jpg', 'content', capture)));
  end if;
  perform net.http_post(
    url := 'https://api.resend.com/emails',
    body := envoi,
    headers := jsonb_build_object('Authorization', 'Bearer ' || k, 'Content-Type', 'application/json'));
  return new;
exception when others then
  return new;                         -- jamais de message perdu à cause du mail
end;
$corps$;
revoke all on function public.mail_support() from public, anon, authenticated;

drop trigger if exists support_mail on public.support_requests;
create trigger support_mail after insert on public.support_requests
  for each row execute function public.mail_support();

-- 20/11 : la personne te répond dans l'app (Aide › Mes messages) : un mail aussi, « Re: » + la référence. Seulement
-- quand supabase/mes-messages.sql est en place (sinon la table des réponses n'existe pas : rien à faire).
create or replace function public.mail_support_reply() returns trigger
language plpgsql security definer set search_path = public, extensions as $corps$
declare
  k text;
  dest text;
  ref text;
  pseudo text;
begin
  if new.team then return new; end if;              -- ta propre réponse : pas de mail
  select decrypted_secret into k from vault.decrypted_secrets where name = 'fls_resend_key';
  select decrypted_secret into dest from vault.decrypted_secrets where name = 'fls_support_to';
  if k is null or dest is null or k = 're_TA_CLE_RESEND' then return new; end if;
  select r.reference, p.username into ref, pseudo
    from public.support_requests r left join public.profiles p on p.id = r.user_id where r.id = new.request_id;
  perform net.http_post(
    url := 'https://api.resend.com/emails',
    body := jsonb_build_object(
      'from', 'FL Shortcuts <onboarding@resend.dev>',
      'to', jsonb_build_array(dest),
      'subject', 'Re: FL Shortcuts' || case when coalesce(ref, '') <> '' then ' · ' || ref else '' end,
      'text', new.message
        || E'\n\n— ' || coalesce(pseudo, 'Compte sans pseudo')
        || case when coalesce(ref, '') <> ''
                then E'\nRépondre dans l''app (Supabase › SQL Editor) :\nselect public.repondre(''' || ref
                     || ''', $$ta réponse$$);'
                else '' end),
    headers := jsonb_build_object('Authorization', 'Bearer ' || k, 'Content-Type', 'application/json'));
  return new;
exception when others then
  return new;                         -- jamais de réponse perdue à cause du mail
end;
$corps$;
revoke all on function public.mail_support_reply() from public, anon, authenticated;

do $$
begin
  if to_regclass('public.support_replies') is not null then
    drop trigger if exists support_reply_mail on public.support_replies;
    create trigger support_reply_mail after insert on public.support_replies
      for each row execute function public.mail_support_reply();
  end if;
end $$;
