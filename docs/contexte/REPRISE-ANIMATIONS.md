# Reprise du chantier « animations morph » (pour le Claude qui prend la suite)

Écrit le 2026-10-22 par la session précédente, juste avant sa limite. Lis d'abord `CLAUDE.md`, puis ce fichier, puis
la conception et le plan ci-dessous. Tout le reste (journal de travail local, fichiers de la session) n'existe pas
chez toi : ce fichier le remplace.

## Ce que veut le propriétaire

Des animations « morph » façon Apple, partout, « ultra bien travaillé SANS BUG ET SANS DÉFAUTS ». Il a tout validé
par écrit, ne lit pas le code et fait confiance : à toi de vérifier chaque étape sur la CI. Il a choisi l'exécution
« Je fais tout moi-même » : une seule session code les 9 tâches dans l'ordre, puis une relecture indépendante de
toute la branche à la fin (agent le plus capable, avec la « Review Focus » du plan), puis une passe de corrections.

- Conception (validée) : `docs/superpowers/specs/2026-10-22-animations-morph-design.md`
- Plan (9 tâches, titres « ### Tâche N », code des tests compris) : `docs/superpowers/plans/2026-10-22-animations-morph.md`
- Branche : **`claude/great-hopper-qihaiy`** (même si ta session te donne un autre nom de branche, c'est celle-ci
  qui porte tout le travail ; demande au propriétaire si tu as un doute). Pas de PR sans demande.

## Où on en est

| Tâche | État |
|---|---|
| 1 Moteur de mouvement | Commit 541d81c. CI : « Tests Swift », compilation universelle et textes anglais verts avec les tâches 1 à 5 (run 39870476151). Mesures, captures et essais pas encore lus : relire la CI du dernier commit. |
| 2 Couche de vol | Commit 86761da. CI à lire (compilation + `FlightLayerTests`). |
| 3 Menu de l'icône en bulle | Codée (`MenuBubble.swift`, `MenuPanel.swift`, commande CI `menu`, `MenuBubbleTests`), poussée avec les tâches 1 et 2 : une seule CI vérifie les trois. Reste l'étape 7 ci-dessous (vérifier les images et l'arbre des vues). |
| 4 Fenêtres qui sortent du clic | Codée (`WindowLauncher.swift`, lignes du menu, Organiser, accueil, désinstallation, guide des autorisations, cadre mémorisé de la fenêtre principale, commande CI `vol`, `WindowLauncherTests`), poussée avec 1 à 3. À vérifier : images `vol-organiser-*`, `vol-organiser-fermeture-*`, `vol-editeur-*` (bulle du cadre d'exemple au cadre de la fenêtre, puis vers l'icône), aucune fenêtre de vol dans les captures de repos, mémoire + 5 Mo au plus. |
| 5 Pages et listes | Codée (icône de la barre latérale qui vole jusqu'à l'en-tête `PageHeader`, page qui arrive sans glisser, listes et recherche qui glissent via `withListAnimation`, chiffres qui défilent dans `PageHeader`, `ListMotionTests`). À vérifier : `page-change-*` (l'icône vole, pas de titre en double). |
| 6 Cartes au lieu des feuilles | Codée (`CardPresenter.swift` : file, présentateur, hôte `cardHost` avec voile, carte de verre qui sort de la ligne cliquée — sondes `ligne.<id>` et `partage.<id>` — et y retourne, vraie modale, fenêtre non fermable pendant une carte, sons ; `cardDismiss` remplace `dismiss` ; guide, fiche d'un raccourci, touche d'une action de FL, modèles, fiche/partage/signalement de la Communauté). Pas fait : vols du nom et de la touche jusqu'en haut de la fiche, focus posé dans la carte, commande CI `carte` (les captures `communaute-detail/partager/signaler` montrent déjà des cartes). À vérifier sur la CI : ces captures, et la fenêtre de 480 de haut. |
| 7 Créateur de macros | En grande partie codée : barre du bas en gouttes (`LiquidDropsBar` : « Dupliquer » et « Supprimer » n'existent qu'avec un bloc choisi ; macOS 26 + verre : fusion native `GlassEffectContainer` ; sinon gouttes dessinées qui sortent de « Ajouter » — sans le dessin flou + seuil du plan, les boutons ayant des libellés de largeurs différentes), bloc qui s'éclaire à la pose (`landed`), icône qui vole de la palette à sa ligne (clic seulement) et de la ligne choisie à la souris jusqu'à l'inspecteur. Reste : entrée et sortie du créateur depuis la ligne de la macro (vol `.card`), commande CI `gouttes`. |
| 8 et 9 | Pas commencées. Suivre le plan tel quel. |

### À vérifier sur la CI pour les tâches 1 et 2 (avant d'aller plus loin)

- « Tests Swift » : `Executed N tests, with 0 failures` (N ≈ 512 + les nouveaux de `MotionEngineTests` et
  `FlightLayerTests`).
- Captures de l'artefact `FLShortcut-mac-mesure` : `page-change-*`, `createur-ouverture-*`, `createur-retour-*`,
  `accueil-partie-*` doivent montrer le mouvement en cours de route (ralenti × 10), comme avant mais plus court.
  **Risque connu** : la fenêtre principale gèle quand l'app n'est pas active (règle de la conception). Si ces images
  montrent un changement sec (aucun état intermédiaire), c'est que l'app n'était pas active pendant la capture : dans
  `EditorView.swift`, le récepteur de `DebugSnapshot.select` (et `DebugSnapshot.macro` dans `DebugSnapshot.swift`)
  doit alors faire `NSApp.activate(ignoringOtherApps: true)` avant de changer de page. Ne PAS changer la règle de gel.
- `*-general.png` inchangée (la couche de vol ne doit rien montrer au repos), glisser-déposer du créateur toujours OK
  (colonne « Bloc glissé de la palette » du tableau de mesure).
- Mémoire : menu ≈ 15 Mo, fenêtre ≈ 54 Mo (budget + 5 Mo au plus).

## Tâche 3 : à vérifier sur la CI

Tout est codé comme prévu par le plan, avec ces choix : un fond de macOS qui CONTIENT notre contenu n'est pas caché
(cela cacherait le menu) mais son verre est masqué (`maskImage` transparent) ; un fond posé à côté est caché ; une
fois la bulle en place, elle le reste jusqu'au prochain lancement (la préférence `legacyMenu` compte au lancement) ;
les lignes arrivent à 60 % de l'ouverture de la bulle ; la bulle rentre dans l'icône en ressort doux, puis le clic sur
l'icône ferme la fenêtre.

- `menu-ouverture-*` = une pastille sous l'icône qui grandit en bulle, aucun fond de macOS
  derrière ; lire l'arbre des vues dans `verre-menu-report.txt`. Si le verre est plat ou sans flou :
  `MenuBubbleStyle.glass = false`. Si le menu est vide ou cassé : corriger `prepare` d'après l'arbre (et au pire
  renvoyer faux = ancien menu, jamais un menu cassé).

## Décisions prises en route (à garder)

- `MotionGate` lit `controlActiveState` (comme `GlassSurface`) au lieu d'observateurs : même règle, rien à retirer.
- `Motion.reduced` = fondu 0,18 s (conception §2) ; badge de pause et fin de l'accueil : fondu court en mouvement réduit.
- Ajouts au moteur pour qu'aucune durée ne reste ailleurs : `Motion.reducedDuration`, `exit`/`exitDuration`,
  `colorFlow` (0,6 s), `stagger(_:start:step:)`, `MotionMode.effective(_:reduceMotion:)`,
  `InterfaceSoundEvent.soundName`, `glassHighlight(_ shape:)`.
- **Jamais de `switch`/`if` de vues selon le mode de mouvement** : le gel va et vient avec FL ; changer de branche
  recréerait la page (défilement, champs perdus). Choisir la valeur (animation, opacité), pas la vue.
- Cadre de l'Organiser animé par `NSAnimationContext` (non bloquant) au lieu de `setFrame(animate:)`.
- `WaitingPulse` (Organiser, animation sans fin) laissé : la tâche 8 le retire ; c'est la seule valeur en dur restante
  (vérification : `grep -rn "spring(response\|easeInOut(duration\|easeIn(duration\|easeOut(duration" Sources/FLShortcut`
  ne doit renvoyer que `MotionEngine.swift`, la section Motion de `GlassStyle.swift` et ce `WaitingPulse`).
- Fenêtres (tâche 4) : un seul vol à la fois ; une ouverture de la fenêtre principale en attente est toujours faite
  (même si le vol est arrêté) ; `open(window:)` est appelé juste AVANT de montrer la fenêtre (elle reste à
  `alphaValue = 0` jusqu'à 85 % du vol, puis fondu) ; départ = dernier clic d'une ligne du menu (moins d'1 s,
  `WindowLauncher.clicked`) sinon l'icône ; fermeture par l'app = `quietClose` (fin de l'accueil, captures CI de
  l'accueil, commande `vol editeur`) ; l'accueil photographié par la CI s'ouvre sans vol (`show(fly: false)`).
- Couche de vol : la sonde AppKit (`FlightProbeView`) ne répond jamais à la souris (`hitTest` → nil) : aucun clic ni
  dépôt volé ; `cancelAll()` à la fermeture de la fenêtre appelle la fin de chaque vol.
- La limite de la session approchant, les tâches 1 à 6 ont été poussées sans attendre leurs CI une à une : la CI
  du dernier commit les vérifie ensemble (lire « Tests Swift », puis les captures de chacune).

## Façon de travailler (apprise ici)

- Pas de Swift dans la session : **la CI est le seul compilateur**. Relire chaque diff avant de pousser (une erreur
  coûte ~25 min). Un push annule la CI en cours : ne pousser la tâche suivante qu'une fois la CI précédente finie, et
  coder la suivante pendant ce temps.
- Lire la CI avec les outils GitHub (MCP) : `actions_list` (`list_workflow_runs`, filtre branche ; puis
  `list_workflow_jobs`), `get_job_logs` (seulement une fois le job fini), artefact `FLShortcut-mac-mesure` par
  `download_workflow_run_artifact` puis `curl` de l'URL. Deux exécutions par push (push et PR) : lire celle du push.
- Chaque texte affiché nouveau : son anglais par `python3 scripts/localisation.py generer trad.json`.
- Un garde (« GateGuard ») demande des faits avant la première modification de chaque fichier : les donner
  (appelants, ce qui change, données, consigne du propriétaire) et refaire la même modification.
- Parler au propriétaire en français simple, en le tutoyant ; lui dire ce qui est vérifié et ce qui ne l'est pas.

## À la fin des 9 tâches

Relecture indépendante de toute la branche (depuis 7f68c9f) par un agent le plus capable, avec la conception, le plan
et sa « Review Focus » ; corriger ; puis donner au propriétaire la liste des décisions prises en route et des petits
défauts remis à plus tard ; mettre `CLAUDE.md` et `docs/contexte/HISTORIQUE.md` à jour ; supprimer ce fichier et le
pas de PR sans demande.
