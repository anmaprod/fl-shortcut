# Répondre aux utilisateurs (page Aide de FL Shortcuts)

Les utilisateurs t'écrivent depuis la page **Aide** de l'app (barre latérale), ou en un clic depuis une erreur :
bouton **Signaler** dans le bandeau d'une macro qui échoue, **Signaler ce problème…** dans le menu de l'icône en
haut de l'écran. Le formulaire est alors prêt avec le message d'erreur exact, et l'app joint de quoi comprendre.

## 1. Mettre en place (une fois)

1. Crée l'adresse de l'équipe (par exemple une adresse Gmail dédiée).
2. Donne-la à l'app : dans `Resources/Info.plist`, clé `FLSSupportEmail` ; ou à la compilation
   `FLS_SUPPORT_EMAIL="aide@exemple.fr" ./build.sh` ; ou pour la CI, **Settings › Secrets and variables › Actions ›
   Variables › New repository variable** `FLS_SUPPORT_EMAIL`.
3. Dans ta boîte, un filtre sur le sujet **`[FL Shortcuts]`** range tout dans un libellé « FL Shortcuts ». Le sujet dit
   aussi le genre : `[FL Shortcuts] Problème · …`, `… Question · …`, `… Idée · …` (un filtre par genre si tu veux).

Sans serveur (tant que la Communauté n'est pas branchée), le bouton est **Envoyer par mail** : l'app de mail de
l'utilisateur s'ouvre avec le message tout prêt, il n'a qu'à l'envoyer. Avec le serveur, le message arrive aussi
dans Supabase (**Table Editor › support_requests**, voir `supabase/README.md`), sans app de mail.

## 2. Lire un message

Toujours le même plan :

```
Référence : FLS-3F9A2C          ← à reprendre dans ta réponse
Genre : Un problème
FL Shortcuts 0.1.0
Pour répondre : nina@exemple.fr

— Message —                     ← ce que la personne raconte
— Le problème signalé —         ← le message d'erreur exact affiché par l'app (si elle vient d'un bouton Signaler)
— État de l'app —               ← versions, autorisations, pause, nombre de raccourcis et de macros, écrans
— Derniers problèmes —          ← les 20 derniers problèmes de l'app, datés
— Journal de la dernière macro — ← chaque étape de la dernière macro lancée, jusqu'à l'échec
```

Rien de personnel n'est joint : ni touches tapées, ni noms de pistes, ni chemins de fichiers, ni titres de fenêtres.
L'utilisateur voit tout avant l'envoi et peut décocher « Joindre l'état de l'appli ».

## 3. Ce que tu lis → ce que tu réponds

| Dans le message | Cause | Réponse |
|---|---|---|
| `Clavier autorisé : non` | Accessibilité pas cochée | Réglages Système › Confidentialité et sécurité › Accessibilité : cocher FL Shortcuts. |
| `(autorisation périmée)` ou « Clavier : autorisation périmée » | macOS garde une ancienne autorisation (après une mise à jour) | Dans Accessibilité, retirer FL Shortcuts avec « − », puis le rajouter avec « + ». |
| `En pause : oui` | FL Shortcuts en pause | ⌃⌥⌘F, ou « Reprendre » dans le menu de l'icône en haut de l'écran. |
| `Saisie sécurisée : oui` | Une autre app attend un mot de passe | Fermer la fenêtre de mot de passe (ou l'app) qui la tient. |
| `FL Studio : fermé` | FL n'était pas ouvert | Ouvrir FL Studio, le mettre devant, recommencer. |
| `(n à apprendre)` | Macro avec un endroit jamais montré sur ce Mac | Ouvrir la macro, choisir le bloc marqué, « Montrer dans FL… ». |
| Journal : `STEP … click` puis `END` en échec, `WIN` sans la fenêtre attendue | La fenêtre ou le menu de FL n'était pas là | Ajouter un bloc « Attendre » avant le clic, ou remontrer l'endroit si FL a changé de taille ou d'écran. |
| Journal : `waitMenu` en échec | Le menu de FL ne s'est pas ouvert à temps | Clic droit au bon endroit (piste visée) ; allonger l'attente du bloc. |
| « Enregistrement impossible : … » | Disque plein ou dossier protégé | Libérer de la place ; vérifier ~/Library/Application Support/FL Shortcuts. |
| « Le fichier des macros était illisible… » | Fichier abîmé, copie gardée | La copie datée est dans Application Support › FL Shortcuts : me l'envoyer pour la réparer. |
| « Clavier : macOS a coupé l'interception… » | macOS a stoppé l'écoute du clavier (machine lente, veille) | Rien à faire si ça arrive rarement ; sinon redémarrer l'app. |

Une question qui revient souvent mérite sa place dans les **questions fréquentes** de la page Aide
(`Sources/FLShortcut/Support.swift`, `HelpContent.faq`) : la prochaine personne aura la réponse sans t'écrire.

## 4. Réponses toutes prêtes

**Accessibilité**
> Bonjour, merci pour ton message (FLS-XXXXXX). Le Mac ne laisse pas encore FL Shortcuts lire le clavier : ouvre
> Réglages Système › Confidentialité et sécurité › Accessibilité, retire FL Shortcuts avec « − » puis rajoute-le avec
> « + » (dans Applications). Le « ! » sur l'icône disparaît tout seul. Dis-moi si ça repart !

**Endroit à remontrer**
> Bonjour, merci (FLS-XXXXXX). Ta macro clique à un endroit appris quand FL avait une autre taille : ouvre-la, choisis
> le bloc indiqué dans le bandeau (« Montrer le bloc »), puis « Montrer dans FL… » et clique au bon endroit.

**Idée**
> Merci pour l'idée (FLS-XXXXXX) ! Je la note pour une prochaine version, je te préviens quand elle arrive.
