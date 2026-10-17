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
6. **Mails (obligatoire avant d'ouvrir à tout le monde)** : sans serveur de mail à toi, Supabase n'envoie les mails
   de confirmation et de mot de passe oublié qu'aux membres de ton organisation Supabase, et 2 par heure au plus.
   **Authentication › Emails › SMTP Settings** : active « Custom SMTP » avec l'adresse de l'équipe (Gmail :
   `smtp.gmail.com`, port 465, identifiant = l'adresse, mot de passe = un « mot de passe d'application » Google,
   validation en deux étapes requise), puis **Authentication › Rate Limits** : mails par heure à ton goût.
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

## 2. Compiler l'app reliée au serveur

L'adresse et la clé publique du projet sont dans `Resources/Info.plist` : toute compilation est reliée au serveur.
Pour un autre projet (essais) sans toucher au fichier :

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

Essai sans recompiler (cette machine seulement) :

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

## Aide : les messages des utilisateurs

La page **Aide** de l'app (barre latérale) a un formulaire « Écrire à l'équipe » (problème, question ou idée, mail
facultatif pour répondre, état de l'app joint si l'utilisateur le laisse coché). Avec le serveur branché, chaque
message arrive dans **Table Editor › support_requests** (ou SQL :
`select created_at, reference, kind, email, message, error, diagnostic from support_requests order by created_at desc`). Personne ne
peut les relire depuis l'app ; 5 messages par heure et par mail au plus.

- Être prévenu à chaque message : **Database › Webhooks › Create a new hook**, table `support_requests`, événement
  *Insert*, vers l'adresse d'un webhook Discord ou Slack (ou une Edge Function qui envoie un mail).
- Sans serveur (ou s'il échoue), l'app propose « Envoyer par mail » vers l'adresse de l'équipe :
  `FLS_SUPPORT_EMAIL="toi@exemple.fr" ./build.sh` (CI : **Settings › Secrets and variables › Actions › Variables ›
  New repository variable** `FLS_SUPPORT_EMAIL`). Sans adresse non plus : « Copier » et « Ouvrir un ticket sur
  GitHub » (page publique, sans le mail de l'utilisateur).

## Ce que l'app envoie et garde

- Sauvegarde en ligne (connecté seulement) : les fichiers des raccourcis et des macros, quelques secondes après chaque
  changement ; rien d'autre (ni réglages du Mac, ni journal, ni touches tapées). **Table Editor › backups** : une
  ligne par compte. Sans compte, rien ne part.

- Écran : jamais lu, sauf pour un clic où l'utilisateur a activé « Retrouver ce bouton s'il bouge » (le « + » du
  Channel rack qui descend) : seulement la fenêtre de FL visée, au moment du clic, avec l'autorisation
  « Enregistrement de l'écran » ; l'image du bouton reste dans la macro (donc dans la sauvegarde en ligne, lisible
  par le seul propriétaire du compte) et est retirée à l'export et des partages.

- Envoyé : mail, mot de passe (seulement à la connexion ou à l'inscription), nom d'utilisateur, et ce que tu
  publies (titre, notes, fichier exporté **sans** positions apprises ni chemins de tes fichiers).
- Gardé sur le Mac : la session (jeton) au Trousseau, jamais le mot de passe ; supprimée par « Se déconnecter » et
  par la désinstallation.
- Importer un partage passe par les mêmes contrôles qu'un fichier reçu : touches interdites refusées, macro relue
  avant d'être ajoutée, sans raccourci ; profil remplaçable puis annulable.
