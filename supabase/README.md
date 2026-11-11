# Comptes, Communauté et sauvegarde en ligne de FL Shortcuts : mise en place du serveur (Supabase)

Un seul compte (page **Mon compte**) sert à deux choses : la **sauvegarde en ligne** des raccourcis et des macros
(retrouvés sur n'importe quel Mac, retirés de ce Mac à la déconnexion : `supabase/sauvegarde.sql`,
`Sources/FLShortcut/AccountBackup.swift`) et la **Communauté**.

La page **Communauté** de l'app (barre latérale, sous « Mes raccourcis ») permet à chacun de partager ses macros et
ses raccourcis avec des notes d'explication. Il faut un compte (mail, mot de passe, nom d'utilisateur) : sans
compte, rien n'est visible. Sans serveur réglé, la page affiche « La Communauté n'est pas encore ouverte » et l'app
ne se connecte jamais à internet.

**Projet en service** (16/10/2026) : `https://ulzxunuytsakxrvovxen.supabase.co`, clé publique dans
`Resources/Info.plist` (`FLSCommunityURL`, `FLSCommunityAnonKey`). Étapes 1 à 5 et 8 faites ; restent l'étape 6 (serveur de mail)
et l'étape 7 (modèles des mails avec le code).

## 1. Créer le projet (une fois, ~10 min)

1. Sur <https://supabase.com>, crée un compte puis **New project** (région Europe, par exemple Paris ou Francfort).
   Garde le mot de passe de la base dans ton gestionnaire de mots de passe.
2. **SQL Editor › New query** : colle tout `supabase/schema.sql`, puis **Run**. Cela crée les tables, les règles
   d'accès (rien pour les visiteurs sans compte), le nom d'utilisateur unique et la limite de 20 partages par jour.
   Puis, dans une nouvelle requête, tout `supabase/inscription.sql`, puis **Run** : le compte (profil, nom
   d'utilisateur) n'est créé qu'une fois le code du mail entré, et une inscription jamais confirmée est effacée au
   bout de 24 h (avec **Integrations › Cron** activé ; sans lui, rien n'est effacé tout seul).
   Projet déjà installé avant ce fichier : colle seulement `supabase/inscription.sql` ; les noms gardés par des
   inscriptions jamais confirmées redeviennent libres.
3. **Authentication › Sign In / Providers › Email** :
   - « Confirm email » : **activé** (chaque compte confirme son mail) ;
   - longueur minimale du mot de passe : **8** ;
   - « Password requirements » : **Lowercase, uppercase letters, digits and symbols**. L'app annonce et vérifie les
     mêmes règles à l'inscription (`CommunityRules.passwordSets`) : à changer ensemble.
4. **Authentication › URL Configuration** : laisse l'adresse par défaut. Les mails n'ont pas de lien : ils donnent un
   **code** que l'on tape dans l'app (confirmation du compte, mot de passe oublié ; étape 7).
5. **Project Settings › API Keys** : note l'**URL du projet** (`https://xxxx.supabase.co`) et la clé publique :
   la **publishable key** (`sb_publishable_…`) ou, dans l'onglet des anciennes clés, la clé **anon public**
   (`eyJ…`) ; les deux marchent. Cette clé est publique par conception (elle est dans l'app) : ce sont les règles
   de `schema.sql` qui protègent les données. Ne mets JAMAIS la clé secrète (`sb_secret_…` ou `service_role`) dans
   l'app.
6. **Mails (obligatoire avant d'ouvrir à tout le monde)** : sans serveur de mail à toi, Supabase envoie 2 mails par
   heure au plus (codes d'inscription et de mot de passe oublié), donc 2 inscriptions par heure. Avec ton serveur de
   mail : 30 par heure au départ, et tu choisis. 10 minutes, une seule fois.
   **Aujourd'hui, sans nom de domaine : une adresse Gmail rien que pour l'app** (gratuit, environ 500 mails par jour ;
   jamais ton adresse perso : chaque inscrit la verrait) :
   1. Crée un compte Gmail pour l'app (par exemple `flshortcuts.app@gmail.com`).
   2. Dans ce compte : <https://myaccount.google.com/security> › **Validation en deux étapes** : active-la.
   3. <https://myaccount.google.com/apppasswords> : crée un mot de passe d'application nommé `Supabase` et copie
      les 16 lettres, sans les espaces.
   4. Supabase, **Authentication › Emails › SMTP Settings** : active **Enable Custom SMTP**, puis :
      Sender email = l'adresse Gmail de l'app ; Sender name = `FL Shortcuts` ; Host = `smtp.gmail.com` ;
      Port = `465` ; Username = l'adresse Gmail de l'app ; Password = les 16 lettres. **Save changes**.
   5. **Authentication › Rate Limits** : « Rate limit for sending emails » = `60` par heure (Gmail s'arrête vers 500
      par jour). **Save changes**.
   6. Fais tout de suite l'étape 7 (mails en français avec le code), puis essaie : crée un compte dans l'app avec une
      autre adresse ; le code arrive en quelques secondes (la première fois, regarde aussi les spams).
   **Plus tard, avec le nom de domaine du site** : le même compte Brevo que le site (domaine déjà validé dans Brevo,
   voir le README du site), l'adresse d'envoi sur ton domaine. Seules ces cases changent : Sender email =
   l'adresse sur ton domaine ; Host = `smtp-relay.brevo.com` ; Port = `587` ; Username et Password = l'identifiant
   et la clé de **Brevo › SMTP & API › SMTP** (pas la clé API). 300 mails par jour pour le site et l'app ensemble.
   Si Google bloque l'adresse Gmail avant, passe à Brevo de la même façon.
7. **Mails en français, au nom de FL Shortcuts, avec un code** (après l'étape 6 : sans serveur de mail à soi, les
   nouveaux projets gratuits ne peuvent pas modifier les modèles). **Authentication › Emails › Templates** :
   - « Confirm signup » : sujet `Ton code FL Shortcuts : {{ .Token }}`, message : tout `supabase/mails/confirmation.html` ;
   - « Reset password » : sujet `Ton code pour changer de mot de passe : {{ .Token }}`, message : tout
     `supabase/mails/mot-de-passe.html`.
   Dans **SMTP Settings**, « Sender name » : `FL Shortcuts`. L'app attend un code de 6 à 10 chiffres
   (**Sign In / Providers › Email › Email OTP Length**) ; il reste valable une heure (« Email OTP Expiration »).
8. **Sauvegarde en ligne** : **SQL Editor › New query**, colle tout `supabase/sauvegarde.sql`, puis **Run** (après
   `schema.sql`). Cela crée la table `backups` (une ligne par compte, lisible et modifiable par lui seul), l'envoi qui
   refuse d'écraser une sauvegarde plus récente faite sur un autre Mac, et « Supprimer mon compte ». Place : une
   sauvegarde pèse quelques dizaines de Ko (2 Mo de raccourcis et 6 Mo de macros au plus).
9. **Corrections de l'IA** (bouton « Pas content ? » de l'Organiser) : **SQL Editor › New query**, colle tout
   `supabase/corrections-ia.sql`, puis **Run** (après `schema.sql`). Cela crée la table `corrections_ia`, où l'app
   envoie, avec l'accord de la personne, les mesures des sons qu'elle a corrigés (des nombres, jamais le son, son nom
   ni ce qu'elle écrit) ; avec ou sans compte, rien n'est relisible depuis l'app ; 300 par heure et par compte au
   plus. Place : ≈ 26 Ko par correction. Pour s'en servir : `ia/corrections.py` (voir `ia/README.md`). Sans cette
   étape, le partage échoue sans bruit : les corrections restent apprises sur le Mac de chacun. Il peut être recollé
   sans risque (« relation "corrections_ia" already exists » venait de l'ancienne version, collée une deuxième fois :
   la table était déjà là) ; « Success. No rows returned » : tout est en place.
10. **Pseudo et photo de profil** (page Mon compte › Modifier le profil) : **SQL Editor › New query**, colle tout
   `supabase/profil.sql`, puis **Run** (après `schema.sql` et `inscription.sql`). Cela permet de changer de pseudo
   (les partages déjà publiés prennent le nouveau ; une fois par minute au plus), de mettre une photo (l'app la réduit
   à 256 × 256 avant l'envoi : 20 à 40 Ko par compte, 96 Ko au plus), de signaler la photo d'un membre, et à un
   administrateur de la retirer. Les photos ne sont lisibles qu'avec un compte. Peut être recollé sans risque. Sans
   cette étape, l'app garde l'initiale de couleur et dit que les photos et le changement de pseudo ne sont pas encore
   ouverts.
11. **Recevoir les messages « Écrire à l'équipe » par mail** (page Aide de l'app, Mac et Windows) : chaque message
   arrive dans ta boîte mail en quelques secondes, et « Répondre » répond directement à la personne si elle a laissé
   son mail. Une fois, 5 minutes :
   1. Sur <https://resend.com>, crée un compte gratuit **avec l'adresse où tu veux recevoir les messages**.
   2. **API Keys › Create API Key** : copie la clé (elle commence par `re_`).
   3. **SQL Editor › New query** : colle tout `supabase/messages-par-mail.sql`, remplace les deux lignes marquées ⬇
      tout en haut (ta clé `re_…` et ton adresse), puis **Run**.
   4. Essaie : dans l'app, Aide › Écrire à l'équipe (la première fois, regarde aussi les spams).
   La clé et l'adresse restent dans le coffre de Supabase (Vault), jamais dans l'app ni dans le dépôt. Si l'envoi du
   mail échoue, le message reste dans **Table Editor › support_requests** comme avant. Peut être recollé sans risque.

## 2. Compiler l'app reliée au serveur (rien à faire)

Déjà fait : l'adresse et la clé publique de ton projet sont dans l'app (Mac : `Resources/Info.plist` ; Windows :
`windows/FLShortcut.App/FLShortcut.App.csproj`). Toute compilation, sur ton Mac comme sur la CI, parle donc à ton
serveur. La suite ne sert qu'à relier l'app à un AUTRE projet Supabase, pour des essais :

```
FLS_SUPABASE_URL="https://xxxx.supabase.co" FLS_SUPABASE_ANON_KEY="sb_publishable_…" ./build.sh
```

Pour la CI : **GitHub › Settings › Secrets and variables › Actions › New repository secret**, deux secrets
`FLS_SUPABASE_URL` et `FLS_SUPABASE_ANON_KEY` ; la CI les passe déjà à `./build.sh` (ils remplacent ceux du
fichier).

## Vérifier les règles sans Supabase

`supabase/tests/run.sh` essaie `schema.sql` sur un PostgreSQL ordinaire (la CI le fait à chaque envoi) : comptes et
noms d'utilisateur, rien de lisible sans compte, publication en son nom seulement, partage non modifiable, suppression
par l'auteur ou un administrateur, signalements lus par les administrateurs seulement, 20 partages par jour.

Essai sans recompiler (cette machine seulement, et seulement avec une app compilée sans serveur : une app qui a
le sien n'écoute jamais ces réglages, qu'un autre programme pourrait écrire) :

```
defaults write app.flshortcut.FLShortcut communityURL "https://xxxx.supabase.co"
defaults write app.flshortcut.FLShortcut communityAnonKey "eyJ…"
```

## 3. Modération

- Chacun peut supprimer ses propres partages et signaler ceux des autres.
- Pour être administrateur (supprimer n'importe quel partage, lire les signalements) : crée ton compte dans l'app,
  puis dans **Table Editor › admins › Insert row**, colle ton identifiant (Authentication › Users › ton compte ›
  User UID).
- Signalements : **Table Editor › reports** (ou SQL : `select * from reports order by created_at desc`).
- Supprimer un partage : **Table Editor › shares**, ou depuis l'app (menu « … » de la ligne, en administrateur).
- Photos signalées : **Table Editor › avatar_reports** (`user_id` : le membre dont la photo est signalée). La
  retirer : depuis l'app (page de ce membre dans la Communauté › « Retirer la photo », en administrateur), ou
  **Table Editor › avatars**, supprime la ligne de ce membre.

## Aide : les messages des utilisateurs

La page **Aide** de l'app (barre latérale) a un formulaire « Écrire à l'équipe » (problème, question ou idée, mail
facultatif pour répondre, état de l'app joint si l'utilisateur le laisse coché). Avec le serveur branché, chaque
message arrive dans **Table Editor › support_requests** (ou SQL :
`select created_at, reference, kind, email, message, error, diagnostic from support_requests order by created_at desc`). Personne ne
peut les relire depuis l'app ; 5 messages par heure et par mail au plus.

- Être prévenu à chaque message, par mail : étape 11 ci-dessus (`supabase/messages-par-mail.sql`).
- Sans serveur (ou s'il échoue), l'app propose « Envoyer par mail » vers l'adresse de l'équipe :
  `FLS_SUPPORT_EMAIL="toi@exemple.fr" ./build.sh` (CI : **Settings › Secrets and variables › Actions › Variables ›
  New repository variable** `FLS_SUPPORT_EMAIL`). Sans adresse non plus : « Copier » et « Ouvrir un ticket sur
  GitHub » (page publique, sans le mail de l'utilisateur).

## Ce que l'app envoie et garde

- Sauvegarde en ligne (connecté seulement) : les fichiers des raccourcis et des macros, quelques secondes après chaque
  changement ; rien d'autre (ni réglages du Mac, ni journal, ni touches tapées). **Table Editor › backups** : une
  ligne par compte. Sans compte, rien ne part.

- Écran : lu seulement au moment d'un clic de macro (et juste après un clic enregistré), seulement dans la fenêtre
  de FL visée, avec l'autorisation « Enregistrement de l'écran » : le texte du bouton (« FILE », « Insert 1 ») le
  retrouve par son nom même s'il bouge ; un bouton sans nom, si l'utilisateur l'a demandé, à son image. Le nom ou
  l'image restent dans la macro (donc dans la sauvegarde en ligne, lisible par le seul propriétaire du compte) et
  sont retirés à l'export et des partages. Sans l'autorisation, les clics gardent leur place.

- Photo de profil (si tu en mets une) : réduite à 256 × 256 sur le Mac avant l'envoi ; visible par les comptes
  connectés seulement ; retirée par « Retirer », et effacée avec le compte.
- Envoyé : mail, mot de passe (seulement à la connexion ou à l'inscription), nom d'utilisateur, et ce que tu
  publies (titre, notes, fichier exporté **sans** positions apprises ni chemins de tes fichiers).
- Organiser, « Pas content ? » : avec la case « Aider l'IA de tout le monde » cochée (une fois pour toutes), les
  mesures des sons corrigés (8 tranches de 1216 nombres au plus) et les familles et sortes (avant, après) ; jamais le
  son, son nom ni un texte tapé. Les cases Playlist, Mixer, aspect et « Autre » partent à l'équipe comme un message
  « Écrire à l'équipe », avec le diagnostic de l'Organiser (des nombres). Sur le Mac : l'empreinte de chaque son
  corrigé (`Application Support/FL Shortcuts/corrections-ia.json`, 500 au plus), effacée par la désinstallation.
- Gardé sur le Mac : la session (jeton) au Trousseau, jamais le mot de passe ; supprimée par « Se déconnecter » et
  par la désinstallation.
- Importer un partage passe par les mêmes contrôles qu'un fichier reçu : touches interdites refusées, macro relue
  avant d'être ajoutée, sans raccourci ; profil remplaçable puis annulable.
