# Historique des sessions avec Claude Code (octobre 2026) — décisions, échecs, leçons

Propriétaire : musicien francophone, Mac M4 Pro sous macOS 27, FL Studio 2026 (Mac). Dépôt GitHub
`anmaprod/fl-shortcut`, branche de travail `claude/relaxed-mayer-ndguzv` (aucune PR ouverte : ne pas en créer sans
demande). Tout le texte visible et les commentaires du code sont en français.

## Point de départ
- Un logiciel « FL Shortcut » existait déjà (fait avec Claude) : raccourcis clavier personnalisables pour FL Studio,
  app Mac (SwiftUI, barre des menus), app Windows (WinUI 3), script MIDI Python chargé par FL (`device_FLShortcut.py`).
- L'utilisateur avait commencé des « macros ». Demandes : revoir son travail, rendre Windows aussi bon que Mac,
  simplifier téléchargement/installation (pkg, dmg, page de téléchargement), remettre le Liquid Glass sans coût
  en RAM/CPU, ajouter un désinstalleur complet (y compris l'app dans /Applications).

## La macro d'exemple « Enregistrement rapide » (⌃R par défaut)
Ordre voulu par l'utilisateur, NON négociable :
1. clic sur une piste du Mixer, puis le raccourci : clic droit sur la piste › File › Open mixer track state ;
2. attente du choix du preset (ou preset choisi d'avance, « preset automatique ») ;
3. armement de la piste (bouton en bas de la tranche) SEULEMENT s'il est éteint ;
4. gros bouton REC SEULEMENT s'il est éteint ;
5. « (none) » → entrée 1 (micro) ;
6. avertissement de larsen à la fin (micro et sortie de l'ordinateur sans casque) : tout est déjà en place, il
   n'a qu'à changer d'entrée ou de sortie.
Il veut ne configurer QUE le raccourci.

## Contraintes posées par l'utilisateur
- PAS d'enregistrement / lecture d'écran (« c'est compliqué de demander aux gens d'autoriser l'enregistrement
  d'écran »). On n'utilise que : la liste des fenêtres (CGWindowList : numéro, niveau, cadre — jamais les pixels ni
  les titres), l'Accessibilité (déjà accordée pour le clavier), les événements clavier/souris.
- MIDI accepté, mais « utilisé que pendant l'utilisation du raccourci, dès que c'est fait il faut bloquer, comme ça
  ça rame pas » → script FL endormi par défaut, réveillé brièvement par la macro (voir PROTOCOL.md).
- Ultra rapide et fluide, raccourcis comme macros. Vérifier fluidité/rapidité AVANT d'envoyer un pkg.
- Interface « full Liquid Glass façon Apple » (comme une appli Apple sur macOS 26/27), sans consommer de RAM.
- Désinstalleur qui enlève tout (préférences, script FL, clé du Trousseau, journaux, autorisations, app).
- « Engage des pros… tu ne peux pas être tout seul » : utilisation d'agents spécialisés (expert FL, ingénieur
  moteur de clics, designer Liquid Glass) et copie des techniques des outils établis (Keyboard Maestro, Hammerspoon,
  cliclick).
- « Test à ma place avec une simulation comme si c'était FL » → FL simulé + essai de bout en bout sur la CI.

## Chronologie des tentatives sur la macro (ce qui a échoué et pourquoi)
1. Clics appris par l'utilisateur, décalages relatifs au clic droit → ÉCHEC : FL décale son menu de piste (très
   haut) pour qu'il tienne à l'écran ; les clics tombaient à côté, le menu se refermait.
2. Moteur « ancré sur la fenêtre du menu » (ingénieur) : décalages relatifs au coin du menu, postconditions,
   apprentissage enregistrant la fenêtre de chaque clic → l'utilisateur : « ça ne fonctionne vraiment pas ».
3. Idée de l'utilisateur : ouvrir Open mixer track state « par du code ». L'API Python de FL n'a AUCUNE commande
   pour charger/ouvrir un état de piste ni pour choisir un élément de menu. MAIS sur sa vidéo, les éléments du menu
   ont des lettres soulignées (F de File, R de Rename, S de Select, D de Delete, A de Assign, C de Channel routing…)
   → navigation AU CLAVIER : clic droit sur la piste, puis F, puis O (+ Entrée si O ne fait que surligner).
   → « ça fonctionne bien mais c'est trop lent ».
4. Accélération (durées de clic/touche raccourcies, garde Playlist par rangée mémorisée, contrôle de la hauteur du
   menu) → « ça ne fonctionne plus » / « le raccourci ne fonctionne plus ». LEÇON : ne jamais modifier les durées ni
   la logique d'une étape validée par l'utilisateur ; tout a été remis à l'identique (durées 30 ms survol / 50 ms
   appui pour le clic droit, 15 ms entre appui et relâchement des lettres, attentes 0,6 s du sous-menu, aucun refus
   selon la rangée), seul gain gardé : Entrée après « O » envoyée au bout de 0,12 s au plus quand on a appris
   qu'elle est nécessaire (au lieu de 0,8 s).
5. Armement/REC : sans le lien MIDI rien ne s'allumait. « Arm selected track(s) » n'a pas de lettre soulignée ;
   chemin clavier : S (Select, ouvre son sous-menu) → ← (referme le sous-menu, « Select » reste surligné) → ↓ ×5
   (Reset selected track(s) routing, Unroute…, Solo, Alt solo, Arm) → Entrée. Idempotent (Disarm est un autre
   élément). NON VÉRIFIÉ dans le vrai FL (seulement dans le FL simulé). REC sans lien : touche R de FL, qui
   INVERSE l'état (limite assumée et expliquée ; le lien MIDI n'allume que si c'est éteint).
6. Preset automatique : « ça ouvre le Finder Mixer presets mais ça ne sélectionne rien ». Reproduit sur la CI avec
   une vraie boîte « Open », corrigé en 3 étapes mesurées :
   a. touches envoyées au seul processus de FL (postToPid) : la boîte « Open » de macOS 26 est servie par un autre
      processus du système → les touches n'arrivaient pas → frappe par le flux clavier du système (HID) quand FL
      est au premier plan ;
   b. « Aller au dossier » (⌘⇧G) s'anime et apparaissait après la fin de l'attente → détection parmi les fenêtres
      nouvelles depuis le premier ⌘⇧G, attente 1,5 s ;
   c. ⌘V synthétique ignoré par macOS 26 (protection du presse-papiers, vu sur les captures de la CI) → chemin tapé
      (Unicode joint aux événements, par paquets de 12 caractères).
7. Entrée 1 : seule étape encore apprise (2 clics montrés une fois, bulle d'aide) : sélecteur relatif au coin
   haut-droit de la fenêtre de FL (taille retenue), entrée relative à la liste ouverte (fenêtre à part).

## Autres échecs et leçons
- Signature ad hoc des pkg compilés sur la CI : pour macOS chaque version est une app différente → l'autorisation
  Accessibilité peut rester cochée sans plus fonctionner après une mise à jour (icône ⚠︎ dans la barre des menus) :
  la retirer (−) et la remettre. Piste d'amélioration : signer la CI avec une identité stable (secret GitHub).
- Lenteur de ~8 s due à Core Audio sur le chemin critique → vérification du larsen en parallèle, à la fin.
- Liquid Glass « invisible » → verre sur toute la fenêtre, puis refonte complète par un agent designer (WWDC25).
- Mémoire mesurée sur la CI : ~14 Mo barre des menus seule, ~54 Mo fenêtre ouverte, avec ou sans verre, 0 % CPU.
- Erreurs de compilation introduites sans pouvoir compiler localement (Linux) : chaque modification passe par la CI
  macOS (macos-26, Xcode 26) avant tout envoi de pkg.
- Un dossier de travail d'agent (`.claude/worktrees/`) a été commité par erreur puis retiré ; il est dans .gitignore.

## Mesures de la macro sur le FL simulé (CI, machine virtuelle : les pauses y durent plus que sur un vrai Mac)
Rejeu avec preset automatique ≈ 4,8 s au total, dont : menu de piste ≈ 0,6 s, apparition de la boîte « Open » par
macOS ≈ 0,8 s (incompressible), choix du preset ≈ 1,3–1,7 s (animations de macOS ≈ 1 s), armement clavier ≈ 1 s,
entrée 1 ≈ 0,5 s.

## Ce que l'utilisateur attend ensuite
- Retour sur le vrai FL : journal exporté (fiche du raccourci › « Exporter le journal… ») et vidéo.
- Vérifier sur le vrai FL : lettre soulignée de « Open mixer track state », comportement de ← dans le menu,
  nombre de ↓ jusqu'à « Arm selected track(s) ».
- Installation du lien MIDI recommandée pour armement/REC exacts.

## 13–14 octobre : créateur de macros (incréments 1 et 2) et correctifs
- Demande : « au lieu de faire plein de macros une par une, donner aux utilisateurs la chance de créer leurs propres
  macros » (exemples cités : Pulover's Macro Creator, VBA Excel/Word, Super Macro, AutoHotkey). Recherches :
  `01-outils-macro.md` (outils de macros), `02-fl-studio-surface.md` (ce qu'on peut piloter dans FL),
  `03-architecture-code.md` (architecture cible et 6 incréments ; seuls 1 et 2 sont faits).
- Incrément 1 : modèle en blocs (`MacroModel.swift`), registre exhaustif (`MacroRegistry.swift`), validation,
  interpréteur à effets injectables (`MacroInterpreter.swift`, `MacroEffectsMac.swift`), « Enregistrement rapide »
  devenu un modèle en blocs identique au chemin validé (`MacroTemplates.swift`, test « golden » des 8 combinaisons).
- Incrément 2 : bibliothèque `macros.json` séparée du profil (`MacroLibraryStore.swift`), fenêtre « Créateur de
  macros » (palette, liste à plat en phrases, inspecteur, ▶ Tester suivi bloc par bloc), export/import `.flsmacro`,
  essai « blocs » sur le FL simulé de la CI.
- Revue de l'incrément 2 (`04-revue-increment2.md`), puis plan de correction
  `docs/superpowers/plans/2026-10-14-correctifs-createur-macros.md`, exécuté et vérifié sur la CI :
  - mémoire prouvée avant correction : la recherche « e » coûtait 228 Mo à cause du `Form` groupé non paresseux
    (58 Mo en `List`) ; le créateur (scène `Window` SwiftUI) restait vivant après fermeture ;
  - pages en `List` paresseuse à l'aspect « cartes » (`PageContainer`, `CardRowBackground` dans `GlassStyle.swift`) ;
  - créateur dans une fenêtre AppKit possédée et libérée (`MacroCreatorWindow.swift`), 0 modèle vivant après
    fermeture, mémoire stable sur 3 cycles ;
  - erreurs de la bibliothèque visibles (menu, page Macros, créateur), plus aucune écriture sans copie de secours ;
  - « Personnaliser » validé avant de toucher au raccourci ; import : chaque clic à montrer de nouveau ;
  - dernière piste cliquée suivie tant que le créateur montre une macro qui la vise ; ports MIDI seulement pendant
    « Tester ».
- Mesures finales (CI, run 38612890994) : barre des menus 14 Mo ; fenêtre 54 Mo ; créateur ouvert 86 Mo, refermé
  79–80 Mo (stable, mais +25 Mo restent après la 1re ouverture : MALLOC_SMALL 39 → 59 Mo, non expliqué) ; recherche
  « e » 86 Mo ; processeur au repos 0,0 % (échantillon : fil principal en attente d'événements). 222 tests, 0 échec.
- Méthode demandée par l'utilisateur : rapide, économe, plugins seulement quand leur spécialité sert. Priorité
  macOS ; Windows et Linux plus tard.

## 16 octobre : relevé de la grille des icônes
- 16/10/2026 : grille de FL de 619 × 679 points (liste des fenêtres, niveau 101) ; Échap ne ferme pas la grille
  ouverte par « Change icon… » du menu de piste du Mixer (deux essais, souris sur la grille puis en dehors) ; une
  fois elle s'est fermée seule quelques secondes après son ouverture, une autre fois elle a disparu entre deux
  sessions sans action de notre part. Cases Two, Three et Five à Eight de Number non survolées (noms déduits).

## 16 octobre : nouveau nom « FL Shortcuts »
- Demande de l'utilisateur : « FL Shortcut » devient « FL Shortcuts » partout où le nom se voit (app, menus, textes,
  script et port MIDI dans FL, sujet des mails d'aide « [FL Shortcuts] », site, Windows, fichiers téléchargés
  FLShortcuts.dmg / .pkg / -Windows-Setup.exe). Les documents d'audit et cet historique gardent l'ancien nom.
- Gardés exprès : identifiant app.flshortcut.FLShortcut (réglages, autorisation Accessibilité, Trousseau),
  exécutable FLShortcut, device_FLShortcut.py, certificat local « FL Shortcut Dev » (sinon l'autorisation
  Accessibilité serait redemandée), texte d'entropie DPAPI Windows (sinon la clé enregistrée deviendrait illisible).
- Reprise de l'ancien nom (`AppPaths.oldName`) : Application Support et Documents › « FL Shortcut » renommés une
  fois (rename(2), jamais un lien) ; script FL déplacé dans « FL Shortcuts » à sa mise à jour, ancien dossier retiré
  s'il ne contient que notre script ; .pkg et build local retirent les anciennes apps (même identifiant vérifié) ;
  le désinstalleur retire les deux noms. Après la mise à jour du script, réactiver le port « FL Shortcuts » dans
  Options › MIDI Settings de FL (seulement si le lien MIDI était utilisé).

## 17 octobre : compte et sauvegarde en ligne
- Demande de l'utilisateur (gratuit exigé) : avec un compte, raccourcis et macros gardés en ligne ; déconnexion =
  retirés du Mac, gardés dans le compte ; reconnexion (ce Mac ou un autre) = tout revient.
- Serveur : `supabase/sauvegarde.sql` (table `backups`, une ligne par compte, RLS « soi seul » ; `save_backup` avec
  révision : refuse d'écraser une sauvegarde plus récente sauf choix forcé ; `delete_my_account`). Testé sur
  PostgreSQL (`supabase/tests/regles-sauvegarde.sql`), à coller dans Supabase après `schema.sql`.
- App : `AccountBackup` (envoi 4 s après un changement, reprise à la connexion, décision pure `BackupRules.decide` :
  envoyer / reprendre / à jour / demander), page **Mon compte** (barre latérale, avant Communauté), déconnexion
  confirmée (refusée si les derniers changements ne sont pas en ligne, sauf « quand même »), copie datée
  « avant-compte » avant de remplacer ce Mac, « Supprimer mon compte » (garde tout sur ce Mac).
- Gardé sur le Mac, jamais envoyé : réglages (pause, autorisations), endroits appris hors des macros, journal.
- Supabase par défaut n'envoie les mails de confirmation qu'aux membres de l'organisation (2 par heure) : serveur de
  mail à soi (Gmail de l'équipe) obligatoire avant l'ouverture à tous.

## 21–22 octobre : l'Organiser lit le fichier du projet
- Vidéo du propriétaire (00:32) : des mélodies classées « FX » alors qu'il n'y en a pas, des patterns mal placés dans
  la Playlist, des mélodies ni renommées ni colorées ; « je veux quelque chose de solide qui fasse qu'à 100 % il rende
  le travail sûr ». Cause : tout reposait sur des devinettes. Ce que FL disait jouer (relevé d'activité) ne voyait pas
  les canaux ZENOLOGY : leurs patterns sans son connu (ni nom ni couleur), leurs pistes classées à l'écoute (« FX »),
  et la réunion des clips par lecture de la fenêtre de FL n'a déplacé qu'un clip sur trois.
- Son projet de test lu : chaque pattern et chaque clip y sont exactement (26 clips, 88 octets chacun). Le pattern 1
  « ZENOLOGY » n'a aucune note (rien n'y joue), « ZENOLOGY #4 » une seule.
- Maintenant (PROTOCOL.md §9, `FLPFile`, `FLPProject`, `OrganizerProjectFile`, `OrganizerProjectLive`) : FL enregistre
  le projet, l'Organiser lit le fichier ; sons de chaque pattern et de chaque piste d'après les notes et les clips
  (plus de relevé des patterns, de chanson jouée ni de piste écoutée : l'analyse est bien plus courte) ; chaque son
  reste reconnu à son nom ou écouté seul dans son pattern. « Organiser » écrit une copie « <nom>_2.flp » (nommée comme « Save new version » de FL, demande du propriétaire) où
  chaque clip est sur la piste de ses sons (les mêmes sons, la même piste ; un clip qui en chevaucherait un autre :
  une piste de plus, juste dessous ; patterns vides en bas), FL l'ouvre, puis Channel rack, patterns, Mixer, noms et
  couleurs s'y font par le script ; FL l'enregistre. L'original ne bouge jamais : « Revenir comme avant » le rouvre
  (tout revient, sons supprimés compris). Plus aucune lecture de l'écran pour la Playlist.
- Rien n'est touché si le fichier n'est pas le projet ouvert, a une forme inattendue, ou a changé depuis l'analyse.
- Pas encore vérifié sur le vrai FL : ⌘S enregistre-t-il bien, le fichier est-il retrouvé (titre de la fenêtre,
  Spotlight), FL ouvre-t-il la copie sans rien demander ?
- Relecture : piste coupée (mute) portant des clips → arrêt (sinon la copie sonnerait autrement), pistes touchées
  réactivées ; textes d'autorisation des dossiers (Documents, Bureau, Téléchargements, disques) ; dossier refusé dit
  avec où l'autoriser ; Channel rack réduit à un groupe signalé ; 3 minutes pour que FL ouvre la copie ; une marque
  restée n'est jamais reprise comme nom.
- Réponses du propriétaire : ⌘S enregistre bien dans FL ; ouvrir un autre projet sans avoir enregistré fait demander
  à FL s'il faut enregistrer. Idée de sa part : un « point de retour » (⌘Z, ou une macro). Ici le point de retour est
  le projet enregistré avant de commencer : « Revenir comme avant » le rouvre, la copie étant enregistrée, FL ne
  demande rien. Pour les macros, un bloc « Point de retour » (historique d'annulation de FL, `general.getUndoHistoryPos`
  / `setUndoHistoryPos` du script) reste à proposer.
- Vidéo du 22/10 (10:34) : la Playlist rangée (un pattern par piste) plaît, mais le pattern 1 « ZENOLOGY » est parti en
  bas et le reste (couleurs, noms, Channel rack, Mixer) ne s'est pas fait. Causes : (1) l'événement 172 de FL 2025 a
  une taille à part ; lu comme les autres, la lecture se décalait et se recalait par hasard, en sautant les 13 notes
  du pattern 1 (pattern pris pour vide, son ZENOLOGY « sans note ») ; corrigé, et un contrôle arrête tout si des notes
  sont vues hors d'un début d'événement. (2) Juste après l'ouverture de la copie, FL chargeait encore ses plugins
  (« Opening: Fruity Wrapper ») et n'a pas confirmé le premier renommage : tout s'arrêtait. L'Organiser attend
  maintenant que FL réponde vite trois fois de suite, puis réessaie ses premières demandes.

