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
| 1 Moteur de mouvement | Fait. CI du commit 57de6a2 (run 39871515697) : « Tests Swift », compilation universelle, textes anglais, mesures, captures anglaises, essais (preset, macro, blocs, clics, touches), désinstallation : tout vert ou PASS. |
| 2 Couche de vol | Fait, vérifié sur la même CI (`page-change-*` : l'icône vole et se pose pile, aucun titre en double ; captures de repos sans fenêtre de vol). |
| 3 Menu de l'icône en bulle | Codée, mais la bulle ne s'active pas sur la CI (macOS 26) : la vue du menu s'appelle `MenuBarExtraHostingView` (pas `NSHostingView`) et il n'y a AUCUN `NSVisualEffectView` : le fond est dessiné ailleurs (calque ?). Le repli marche (ancien menu, lignes qui arrivent l'une après l'autre). Le relevé `verre-menu-report.txt` donne maintenant aussi les calques et le fond de la fenêtre : le lire avant de toucher à `prepare` (ne JAMAIS activer la bulle sans l'avoir vue sur les images). |
| 4 Fenêtres qui sortent du clic | Fait, vérifié (`vol-organiser-*`, `vol-editeur-*` : la bulle vole et se pose ; un peu plate et blanche, à revoir à la relecture). Mémoire : 98 Mo / pic 102 Mo dans `verre-avant-createur-footprint` — à comparer au tableau de mémoire du résumé de la CI (budget + 5 Mo). |
| 5 Pages et listes | Fait, vérifié (`page-change-*`). |
| 6 Cartes au lieu des feuilles | Codée (`CardPresenter.swift` : file, présentateur, hôte `cardHost` avec voile, carte de verre qui sort de la ligne cliquée — sondes `ligne.<id>` et `partage.<id>` — et y retourne, vraie modale, fenêtre non fermable pendant une carte, sons ; `cardDismiss` remplace `dismiss` ; guide, fiche d'un raccourci, touche d'une action de FL, modèles, fiche/partage/signalement de la Communauté). Vérifié sur la CI de 57de6a2 (`communaute-detail` : voile, carte, fenêtre non fermable) ; la double barre de défilement vue alors (fiche de 580 de haut dans une carte qui défile) est corrigée par `cardMaxHeight` (l'hôte donne sa hauteur, les fiches qui défilent elles-mêmes s'y tiennent) : à revérifier. Pas fait : vols du nom et de la touche jusqu'en haut de la fiche, focus posé dans la carte, commande CI `carte`. |
| 7 Créateur de macros | En grande partie codée : barre du bas en gouttes (`LiquidDropsBar` : « Dupliquer » et « Supprimer » n'existent qu'avec un bloc choisi ; macOS 26 + verre : fusion native `GlassEffectContainer` ; sinon gouttes dessinées qui sortent de « Ajouter » — sans le dessin flou + seuil du plan, les boutons ayant des libellés de largeurs différentes), bloc qui s'éclaire à la pose (`landed`), icône qui vole de la palette à sa ligne (clic seulement) et de la ligne choisie à la souris jusqu'à l'inspecteur. Reste : entrée et sortie du créateur depuis la ligne de la macro (vol `.card`), commande CI `gouttes`. |
| 8 Organiser | Codée : plus rien en boucle (compteur de secondes `SecondsCounter`/`SecondsLabel`, progression dessinée `OrganizerProgress`) ; la session annonce la famille définitive de chaque son (`classified`, règles du nom et du synthé appliquées son par son : `finalize`) ; pastilles des familles pendant l'écoute (`liveFamilies`, `FamilyPill`, `FlowRow`) ; la fenêtre grandit d'abord (`growForPreview`, une pastille tardive ne la fait plus rapetisser), puis l'écoute devient l'aperçu sur place (même étape « analysis » : l'icône de chaque pastille glisse dans sa carte, `matchedGeometryEffect`, cartes sans `morphIn`) ; « Organiser » devient la pastille du rangement, puis « ✓ N sons rangés » (`organizedCount`, `showingDone` 1,2 s, son « Glass ») ; « Revenir comme avant » devient « Retour en arrière… ». CI : `organizer "ecoute lent"`, `"apercu lent"`, `"fini lent"` → `organiser-ecoute-*`, `organiser-apercu-*`, `organiser-fini-*`. À vérifier sur ces images : pastilles → cartes sans saut, bouton → pastille, aucune roue. |
| 9 Relecture finale | Pas commencée. |

### Encore à vérifier sur la CI

- Mémoire : menu ≈ 15 Mo, fenêtre ≈ 54 Mo avant le chantier (budget + 5 Mo au plus) : lire le tableau de mémoire du
  résumé de la CI (le fichier `*-footprint` mesure autrement : 98 Mo, pic 102 Mo).
- La CI a « Réduire les animations » activé (« animations réduites : oui ») : les captures ralenties montrent quand
  même le mouvement (mode capture), mais un défaut qui n'existe qu'en mouvement réduit ne s'y voit pas.

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
- Plus aucune valeur d'animation en dur (vérification : `grep -rn "spring(response\|easeInOut(duration\|easeIn(duration\|easeOut(duration" Sources/FLShortcut`
  ne renvoie que `MotionEngine.swift` et la section Motion de `GlassStyle.swift`).
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
