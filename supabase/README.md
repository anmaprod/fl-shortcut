# Communauté de FL Shortcut : mise en place du serveur (Supabase)

La page **Communauté** de l'app (barre latérale, sous « Personnalisés ») permet à chacun de partager ses macros et
ses raccourcis avec des notes d'explication. Il faut un compte (mail, mot de passe, nom d'utilisateur) : sans
compte, rien n'est visible. Tant que le serveur n'est pas réglé, la page affiche « Communauté bientôt disponible »
et l'app ne se connecte jamais à internet.

## 1. Créer le projet (une fois, ~10 min)

1. Sur <https://supabase.com>, crée un compte puis **New project** (région Europe, par exemple Paris ou Francfort).
   Garde le mot de passe de la base dans ton gestionnaire de mots de passe.
2. **SQL Editor › New query** : colle tout `supabase/schema.sql`, puis **Run**. Cela crée les tables, les règles
   d'accès (rien pour les visiteurs sans compte), le nom d'utilisateur unique et la limite de 20 partages par jour.
3. **Authentication › Sign In / Providers › Email** :
   - « Confirm email » : **activé** (chaque compte confirme son mail) ;
   - longueur minimale du mot de passe : **8**.
4. **Authentication › URL Configuration** : laisse l'adresse par défaut ; le lien du mail de confirmation et celui
   du mot de passe oublié s'ouvrent dans le navigateur (page de Supabase).
5. **Project Settings › API Keys** : note l'**URL du projet** (`https://xxxx.supabase.co`) et la clé publique :
   la **publishable key** (`sb_publishable_…`) ou, dans l'onglet des anciennes clés, la clé **anon public**
   (`eyJ…`) ; les deux marchent. Cette clé est publique par conception (elle est dans l'app) : ce sont les règles
   de `schema.sql` qui protègent les données. Ne mets JAMAIS la clé secrète (`sb_secret_…` ou `service_role`) dans
   l'app.

## 2. Compiler l'app reliée au serveur

```
FLS_SUPABASE_URL="https://xxxx.supabase.co" FLS_SUPABASE_ANON_KEY="eyJ…" ./build.sh
```

Pour la CI : **GitHub › Settings › Secrets and variables › Actions › New repository secret**, deux secrets
`FLS_SUPABASE_URL` et `FLS_SUPABASE_ANON_KEY` ; la CI les passe déjà à `./build.sh`.

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

- Envoyé : mail, mot de passe (seulement à la connexion ou à l'inscription), nom d'utilisateur, et ce que tu
  publies (titre, notes, fichier exporté **sans** positions apprises ni chemins de tes fichiers).
- Gardé sur le Mac : la session (jeton) au Trousseau, jamais le mot de passe ; supprimée par « Se déconnecter » et
  par la désinstallation.
- Importer un partage passe par les mêmes contrôles qu'un fichier reçu : touches interdites refusées, macro relue
  avant d'être ajoutée, sans raccourci ; profil remplaçable puis annulable.
