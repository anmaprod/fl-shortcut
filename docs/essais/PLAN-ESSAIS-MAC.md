# Plan d'essais complet de FL Shortcut sur le Mac de Malo

Pour la session Claude Code qui tourne sur le Mac (computer use activé). But : vérifier TOUT FL Shortcut sur le
vrai FL Studio, et, pour chaque problème, écrire un compte rendu assez précis pour que la session cloud corrige le
code sans revenir au Mac.

## Règles

**Vitesse (demande de Malo, prioritaire)**
- Bash avant tout : `osascript`, commandes de l'app, journaux, `defaults`. Computer use seulement pour VOIR un
  résultat ou cliquer ce qu'aucune commande ne peut faire.
- Une capture au plus par vérification, sans zoom sauf pour trancher un doute.
- Plusieurs commandes par appel Bash ; pas de relecture d'un fichier qu'on vient d'écrire ; pas d'attente « par
  sécurité ».
- Compte rendu : faits, sortie brute, verdict. Pas de paraphrase. Un cas OK tient en une ligne.

**Touches** : sur ce MacBook, les touches F de computer use sont des touches média. Toujours
`osascript -e 'tell application "System Events" to key code N [using {control down, …}]'`, FL devant. Codes
utiles : F2 120, F5 96, F6 97, F7 98, F9 101, Entrée 36, Échap 53, Tab 48, Espace 49, ↑ 126, ↓ 125, 1 18, 2 19,
3 20, 4 21, 5 23, D 2, F 3, M 46, R 15, S 1, T 17, Z 6. Le clavier de FL doit être sur la bonne page : cliquer
d'abord le nom de la piste (F2 ne fait rien quand le Browser a le clavier).

**Sûreté**
- Projet de TEST uniquement (projet vide ou copie). Jamais un morceau de Malo. Si FL propose d'enregistrer des
  changements : Annuler, et demander à Malo.
- Les cas marqués **[accord de Malo]** changent quelque chose hors de FL Shortcut (réglages audio du Mac, script
  installé dans FL, désinstallation). Les faire à la fin, seulement après son accord dans la session, et remettre
  en état ensuite.
- Jamais de clic au hasard pour « réparer » : arrêt, capture, description.
- Malo ne touche pas la souris pendant les essais (il l'a fait une fois : la barre d'aide de FL a changé).

**Départ**
```
cd ~/Documents/fl-shortcut && git pull --ff-only && git log --oneline -1
```

## Compte rendu

Écrire `docs/essais/COMPTE-RENDU-MAC.md` AU FUR ET À MESURE, et faire commit + push après chaque partie
(A, B, C…), message en français. Prévenir la session cloud après chaque push (une ligne : partie, nombre d'OK et de KO).

En tête : date, commit, macOS, FL (version), Xcode, écrans, langue du clavier.

Par cas : `ID — OK` (une ligne), `ID — NON FAIT (raison)`, ou pour un KO un rapport EXTRÊMEMENT approfondi :
1. pas exacts faits (commandes, clics, page de FL devant, élément sélectionné) ;
2. attendu, puis obtenu ;
3. messages exacts (bulle, alerte, fiche du raccourci, barre d'aide de FL), recopiés mot pour mot ;
4. extrait brut de `~/Library/Logs/FL Shortcut/macro.log` (le passage du RUN concerné, en entier) et sorties de
   commandes en entier ;
5. fenêtres de FL au moment du problème (`FLShortcut --diag-macro` ou les lignes WIN du journal : numéro, niveau,
   cadre) ;
6. reproductible ? combien de fois sur combien d'essais ;
7. hypothèse de cause avec fichier et ligne du code (lire le code), et idée de correctif.
Puis deux sections : **Lenteurs** (étapes chronométrées de plus de 1 s, avec la durée) et **Surprises**.

---

## A. Automatique (une commande, rien à regarder)

**A1** — `scripts/essais-mac.sh` (≈ 8 min : tests Python, tests Swift, compilation, choix du preset dans une vraie
boîte « Open », macro « Enregistrement rapide » sur le FL simulé, macro en blocs, « Enregistrer des clics »).
Ne pas toucher la souris pendant les essais du FL simulé. Résumé : `.essais/resume.txt`. Tout FAIL : joindre le
fichier de l'essai en entier (`.essais/*.txt`).

**A2** — `scripts/essais-mac.sh --vite --avec-mesure` (mesure mémoire / processeur de l'interface). Recopier le
tableau. Attendu : barre des menus ≈ 14 Mo, fenêtre ≈ 54 Mo, 0 % de processeur au repos.

## B. Raccourcis (app de la barre des menus lancée, profil « Recommandé », FL devant, projet de test)

Vérifier chaque effet par une seule capture, ou par la barre d'aide / le titre de la fenêtre de FL.

- **B1** — Lancement : `open ~/Applications/"FL Shortcut.app"`. Icône dans la barre des menus, aucune pastille
  d'alerte (Accessibilité accordée). Ouvrir le menu de la barre : statut, pause, liens.
- **B2** — Fenêtres : ⌃1 Playlist, ⌃2 Channel rack, ⌃3 Piano roll, ⌃4 Mixer, ⌃5 Browser
  (`key code 18 using control down`, etc.). Chacune doit passer devant dans FL.
- **B3** — ⌃D / ⌃F : pattern précédent / suivant (créer 2 patterns d'abord). ⌃M : métronome (bouton du transport).
- **B4** — Pause ⌃⌥⌘F : les raccourcis ne font plus rien ; de nouveau ⌃⌥⌘F : ils remarchent. Statut visible dans la
  barre des menus.
- **B5** — Touches seules (profil « Style Ableton » : Tab, 0) : marchent dans le Mixer ; NE se déclenchent PAS quand
  la fenêtre du nom de FL (F2) est ouverte, ni dans un champ de texte, ni avec un menu de FL ouvert.
- **B6** — Fenêtre principale : changer de profil (Recommandé → Style Ableton → Vide → Recommandé), annuler le
  changement ; créer un raccourci (capture d'une touche), le modifier, le supprimer ; conflit avec FL, touche déjà
  prise, touche interdite (⌘Q refusé), version de FL trop ancienne : chaque avertissement recopié.
- **B7** — Export puis import d'un profil (dossier Documents › FL Shortcut › Raccourcis) : le profil importé est
  identique.
- **B8** — FL fermé puis rouvert : les raccourcis remarchent sans relancer FL Shortcut. FL Shortcut quitté : plus
  aucune touche interceptée.

## C. Macros (projet de test, Mixer)

- **C1** — « Enregistrement rapide » (⌃R, fiche du raccourci › Type › Macro) avec un preset (.fst) choisi d'avance :
  clic sur une piste du Mixer, ⌃R. Attendu, dans l'ordre : preset chargé sur CETTE piste, piste armée seulement si
  elle ne l'était pas, REC seulement s'il était éteint, entrée 1 (apprise la première fois : 2 clics montrés par la
  bulle), avertissement de larsen si micro + haut-parleurs. Chronométrer chaque étape (journal). Puis REC arrêté
  (Espace) et l'enregistrement d'essai supprimé.
- **C2** — Même macro avec « preset choisi à chaque fois » : menu de la piste › File › Open mixer track state, la
  boîte « Open » attend le choix.
- **C3** — Armement sans le lien MIDI (clavier : S, ←, ↓ ×5, Entrée) : vérifier sur le vrai FL que c'est bien
  « Arm selected track(s) » qui est choisi (jamais vérifié sur le vrai FL).
- **C4** — Créateur de macros : nouvelle macro, un bloc de chaque sorte de la palette (Touche, Clic, Attendre,
  Menu de la piste, Lettres d'un menu, Action de FL, Déposer un preset, Si… sinon, Répéter, Variable, Arrêter,
  Commentaire, Nom et couleur, Carte son, Organiser…), glisser-déposer, ⌘Z / ⇧⌘Z, ▶ Tester bloc par bloc,
  enregistrer, attacher à un raccourci, lancer dans FL. Pour chaque bloc qui agit dans FL : effet constaté.
- **C5** — « Enregistrer des clics » : enregistrer une suite (menu de piste, Options › Audio settings, une touche),
  puis rejouer : mêmes effets.
- **C6** — Export / import de macros `.flsmacro` (Documents › FL Shortcut › Macros) : macros identiques, positions
  apprises à remontrer.
- **C7** — Fiche du raccourci : « Exporter le journal… » produit un fichier sans frappe ni nom de fichier ni nom de
  piste.
- **C8** — Échap pendant une macro : arrêt immédiat, rien d'autre ne se passe.

## D. Nom, couleur et icône (lien MIDI requis : partie E d'abord si le script n'est pas installé)

- **D1** — `FLShortcut --diag-icon 6-0` puis `--diag-icon 12-6` sur deux pistes du Mixer (cliquer leur nom
  d'abord) : PASS, icône visible dans la fenêtre du nom (F2 par osascript, puis Entrée).
- **D2** — Même chose dans le Channel rack (un canal sélectionné) : la fenêtre du nom de FL est-elle la même
  (taille, place du bouton) ? Si elle diffère, le dire avec ses mesures (ligne « ICON name window »).
- **D3** — Bloc « Nom et couleur » : nom + couleur + icône sur une piste ; couleur seule ; icône seule ; dégradé sur
  3 pistes sélectionnées (le réglage d'icône doit être grisé) ; refus clairs (aucune piste, deux pistes, page non
  prise en charge).

## E. Lien MIDI avec FL **[accord de Malo]** (installe le script dans FL)

- **E1** — Installation du script depuis FL Shortcut, réglage dans FL (Options › MIDI settings), statut du lien
  « actif ». Noter chaque écran.
- **E2** — Actions par le lien : Mute / Solo de la piste sélectionnée (⌃T / ⌃S), volume ±, piste suivante /
  précédente, Annuler / Rétablir (⇧⌘Z). Chaque effet constaté.
- **E3** — Sommeil : sans action pendant 1 min, le lien ne consomme rien (processeur de FL inchangé) ; l'action
  suivante marche du premier coup.
- **E4** — `FLShortcut --mesure` (app quittée) : recopier les temps.

## F. Organiser (projet de test avec 6 à 10 sons variés dans le Channel rack, lien MIDI actif)

- **F1** — Lancement par le menu de la barre et par le bloc. Autorisation « Audio système » demandée une fois.
- **F2** — Écoute : chaque son joue seul sans être entendu ; Échap au milieu : FL remis comme avant (sourdines, mode,
  position).
- **F3** — Aperçu : familles proposées (noter le classement de chaque son et s'il est juste), changer la famille
  d'un son, couleur / dégradé / icône par famille.
- **F4** — Appliquer : couleurs, regroupement par ⌥↑, icônes ; vérifier l'ordre final et chaque couleur ;
  « Revenir comme avant » : ordre et couleurs d'origine (les icônes restent, c'est prévu).
- **F5** — Refus : FL qui joue, groupe filtré dans le Channel rack, Playlist devant.
- **F6** — Mixer devant : couleurs (et icônes) par famille majoritaire.

## G. Système

- **G1** — `scripts/essais-mac.sh` a-t-il remis les préférences (positions apprises, macros) comme avant ?
- **G2** — Anomalie « write: Permission denied » ×4 pendant la fabrication du .pkg (`./build.sh`) : trouver la
  commande fautive (`bash -x ./build.sh 2>&1 | grep -B3 "Permission denied"`) et vérifier que le .pkg installe bien
  dans /Applications (sans l'installer : `pkgutil --expand` puis lire PackageInfo).
- **G3** — Deux écrans : la bulle d'aide et les clics appris marchent quand FL est sur l'écran principal ET sur le
  second écran (la session ne bouge pas les fenêtres sans l'accord de Malo).
- **G4** **[accord de Malo]** — « Carte son branchée » : seulement si une carte son USB est branchée ; noter les
  sorties / entrées avant, après, et les remettre.
- **G5** **[accord de Malo]** — Désinstallation complète puis réinstallation (`./build.sh`) : tout disparaît
  (préférences, script FL, Trousseau, journaux, app), puis tout revient.

## Ordre

A1 → B → C (C1 à C3 d'abord) → D1–D2 → E (si accord) → D3 → F → G1–G3 → A2 → G4, G5 (si accord).
Pousser le compte rendu après chaque partie.
