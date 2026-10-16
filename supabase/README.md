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
5. **Project Settings › API** : note l'**URL du projet** (`https://xxxx.supabase.co`) et la clé **anon public**.
   Cette clé est publique par conception (elle est dans l'app) : ce sont les règles de `schema.sql` qui protègent
   les données. Ne mets JAMAIS la clé `service_role` dans l'app.

## 2. Compiler l'app reliée au serveur

```
FLS_SUPABASE_URL="https://xxxx.supabase.co" FLS_SUPABASE_ANON_KEY="eyJ…" ./build.sh
```

Pour la CI, ajoute deux secrets GitHub du même nom et passe-les à `./build.sh`.

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

## Ce que l'app envoie et garde

- Envoyé : mail, mot de passe (seulement à la connexion ou à l'inscription), nom d'utilisateur, et ce que tu
  publies (titre, notes, fichier exporté **sans** positions apprises ni chemins de tes fichiers).
- Gardé sur le Mac : la session (jeton) au Trousseau, jamais le mot de passe ; supprimée par « Se déconnecter » et
  par la désinstallation.
- Importer un partage passe par les mêmes contrôles qu'un fichier reçu : touches interdites refusées, macro relue
  avant d'être ajoutée, sans raccourci ; profil remplaçable puis annulable.
