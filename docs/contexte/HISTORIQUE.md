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

- Retours du 22/10 (prods, projets de voix, « Mechanical ») :
  - « All » du Channel rack automatique : l'analyse sur le fichier compte tous les canaux même si un groupe est
    affiché (script v16 : genre 5 de l'opération 2, drapeau 1 des opérations 3 et 6, API 33 ; avant : le groupe affiché,
    comme avant). La copie s'ouvre sur « All » (événement 146) et elle est faite même si « Playlist » est décochée.
  - Deux arrangements : celui qui est ouvert (événement 100) est rangé, les autres ne bougent pas.
  - « Mechanical » (un seul pattern, jamais nommé) refusé « (patterns) » : la marque de la copie va alors sur le
    premier canal nommé, qui reprend son nom ensuite. Ouverture aussi reconnue au titre de la fenêtre de FL.
  - « bug ne fait rien » (resté longtemps sur « FL ouvre la copie… ») : l'attente dit où elle en est (secondes, « FL
    charge les sons… », « Rangement dans la copie… ») et le diagnostic donne `application=ouverture=… ; calme … s`.
  - Capture « La page de FL a changé » (Channel rack à moitié rangé) : la page qui n'est plus devant est remise devant
    (4 fois au plus) et le rangement continue ; diagnostic `page remise N`.
  - Règle du propriétaire pour le Mixer : une piste qui envoie déjà à une autre piste que le Master (groupe, sidechain,
    effet) reste avec sa famille sans que ses envois changent ; reliée au seul Master : famille et bus. Un bus déjà là
    reçoit des pistes qui n'envoient qu'à lui (le Master est maintenant gardé dans les envois lus).
  - Voix (« test voix » : des voix enregistrées rangées en Mélodies, FX et Drums) : sortes « Voix lead », « Back »,
    « Ambiance » (d'après les mots d'un nom de voix, ou au choix dans l'aperçu). Un enregistrement de FL
    (« <projet>_<date> <heure>_Insert 5 ») n'est PAS une voix d'office (guitare, piano, synthé aussi : retour du
    propriétaire) : seul le nom de sa piste du Mixer, après la date, compte ; sinon il est écouté, une fois qu'il sonne
    (une prise commence souvent par un silence, qui était classé ; 10 s d'attente au plus). Dans la Playlist, les
    clips des voix et des enregistrements d'une même sorte vont sur une seule piste, ceux qui se chevauchent dessous.
  - Mélodies : à l'écoute, leur sorte (Piano, Keys, Orgue, Guitare, Strings, Flûte, Brass, Bell d'après l'IA de
    macOS ; sinon Arp, Pluck, Pad ou Lead d'après la forme du son ; rien de sûr : « Mélodie »), changeable dans l'aperçu.
  - Fenêtre de l'Organiser redimensionnable ; sa hauteur suit le contenu mesuré à chaque changement (elle restait
    grande après l'aperçu, le texte en haut) ; l'aperçu garde la hauteur qu'on lui donne.
- « Quitter et rouvrir » ne rouvrait toujours pas (troisième retour). La relance ne se faisait que si la demande de
  fermeture venait de l'app Réglages Système (identifiant « com.apple.systempreferences ») ; or la page
  « Confidentialité et sécurité » est une extension à part (macOS 13 et plus), souvent sans identifiant d'app :
  l'app quittait sans revenir. Maintenant : reconnue aussi par le chemin de son programme (« Settings »,
  « Privacy », TCC, ou tout processus du système sans nom d'app), et un surveillant, posé dès que l'app ouvre les
  Réglages pour une autorisation, la rouvre une fois partie, même fermée de force ; jamais après ⌘Q, le menu, le Dock
  ou la fin de session. Le journal dit qui a demandé la fermeture (« QUIT asked by … »).
- Vidéo bug-4 (prod « dafftttt ») : un pattern de plusieurs sons restait un seul bloc (« il a pas split by
  channel »), les drums en clips audio étaient mal nommés (kick en « Keys », hi-hat en « Snare », clap en « Drums »,
  d'où l'impression de deux bus Drums). Maintenant : dans la copie, chaque pattern de plusieurs sons est séparé son par
  son (comme « Split by channel » de FL : nouveaux patterns, chaque clip doublé à la même place), l'analyse et la
  Playlist se font sur ce projet séparé (aperçu : « N sons sortis des patterns… ») ; le nom du fichier de son
  (« D30 Kick 85 », « ANMA - Hat House ») reconnaît un son quand le nom du canal ne dit rien ou a été donné par
  l'Organiser. L'écoute se fait toujours dans les patterns d'avant (le projet ouvert dans FL).
- Essais du propriétaire : les prods se rangent très bien, mais les voix restent mal reconnues et les projets de voix
  « chargent sans rien faire ». Cause probable : chaque prise était jouée dans FL et attendue jusqu'à ce qu'elle
  sonne (prises qui commencent par un long silence, 10 s d'attente chacune, puis un passage de bruit ou de souffle
  écouté). Maintenant, analyse sur le fichier : le fichier de chaque clip audio (événement 196) est lu directement par
  l'app (`SampleFiles.swift`, AVAudioFile), son passage le plus fort (3 s) est classé, en un instant et sans rien
  jouer dans FL ; le fichier est retrouvé à son chemin (dossiers de FL à la place de « %FLStudioUserData% »…), à côté
  du projet, sinon par Spotlight à son nom ; introuvable : joué dans FL comme avant (attente ramenée à 5 s). Le nom du
  dossier du son compte aussi quand celui du fichier ne dit rien (« …/Hat/BX 17.wav »). Règle `+fichier` dans le
  diagnostic, et chaque étape notée dans le journal (`grep ORGANIZE ~/Library/Logs/"FL Shortcuts"/macro.log`) pour
  voir où ça bloque s'il bloque encore. Même principe prévu pour Windows (Media Foundation). Prochain grand chantier
  convenu : une IA embarquée dans l'app (YAMNet, licence Apache 2.0, plus une petite tête entraînée sur des sons
  libres d'usage commercial), la même sur Mac et Windows, gratuite.
- Vérification complète demandée par le propriétaire (« refait un test… tu as mon accord »), CI lue jusqu'au bout :
  « Quitter et rouvrir » abandonnait trop tôt l'attente de l'ancienne copie sur un Mac chargé (test AppResume rouge,
  0,38 s) ; `build.sh` : « write: Permission denied » ×4 sur macOS 27 (`plutil -o /dev/null`, remplacé par
  `-o -`) ; trois alertes « erreur en Swift 6 » du compte (valeur par défaut `.shared` lue hors du fil principal) ;
  armement sans lien MIDI : le sous-menu « Select » n'était attendu que 0,45 s alors qu'il est apparu à 0,63 s sur
  la CI (plafond 1 s, rien de plus lent quand il s'ouvre vite). Captures « apercu » et « fini » de l'Organiser
  parfois restées sur l'écoute (runs d7c7f55 et 289f215, pas sur 0c18d51) : pas de plantage (même processus), écrans
  vérifiés par `testDemoScreensRender` ; le script de mesure note le processus après chaque écran et joint les
  rapports de plantage et le journal, au cas où ça revient. CI entièrement verte sur 0c18d51 (512 tests).

## 22–23 octobre : animations « morph », faites puis retirées
- Conception et plan validés (`docs/superpowers/specs/2026-10-22-animations-morph-design.md`, `docs/superpowers/plans/`),
  9 tâches codées et vérifiées sur la CI (commits 541d81c → dcd01f0) : moteur de mouvement, couche de vol, fenêtres
  qui sortent du clic, cartes au lieu des feuilles, gouttes du créateur, Organiser en morph, relecture indépendante.
- Le propriétaire les a essayées sur son Mac : « c'est vraiment nul, je veux que tu enlèves tout ce qui a été rajouté
  de 1 à 9 ». Tout est retiré : le code est revenu à 7f68c9f (seuls les noms des fichiers de la CI restent changés :
  FLShortcuts-mac, FLShortcuts-windows, FLShortcuts-mac-mesure). Ne pas les refaire sans qu'il le demande.
- 24/10 : « tu n'as pas enlevé les choses que je voulais » ; sur les animations d'avant le chantier, il a choisi de
  retirer seulement celle du changement de page (fondu et flou au clic dans la barre de gauche) : la page s'affiche
  maintenant d'un coup. Guide, accueil, menu de l'icône, Organiser et créateur gardent les leurs.

## 23 octobre : IA intégrée (classement des sons, Mac et Windows)
- Demande du propriétaire : « viens on bosse sur l'IA intégrée », priorité aux voix (« rangées ailleurs mais jsp
  pourquoi »), apprentissage sur des sons libres (ses packs seulement pour essayer), essai directement dans
  l'Organiser ; puis cahier des charges détaillé (hors-ligne, Mac et Windows, ONNX, quelques ms, quantification,
  faux positifs voix/FX) ; puis « la même classification qu'on avait fait sur le logiciel avec les options qu'on peut
  changer » ; puis « toute l'organisation dans Organiser ne doit pas changer même si on change d'IA […] le + c'est de
  l'entraîner pour qu'elle reconnaisse extrêmement facilement les sons en lui en donnant plein ».
- Cause des voix mal rangées : la première règle demandait à l'IA de macOS au moins 0,5 de « voix » ; une voix de
  production (réverb, pitch, chop) restait souvent dessous et, ayant des notes nettes, finissait en Mélodies.
- Fait (`ia/`, voir `ia/README.md`) : YAMNet (Google, Apache 2.0) + 192 mesures du spectre + 5 têtes moyennées
  (famille + sorte parmi les choix de l'aperçu, sauf Back et Synth), apprises sur 39 459 sons libres (VocalSet,
  LibriSpeech dev/test-clean, NSynth test/valid dans leur tessiture, Freesound one-shot CC0/CC BY, sons fabriqués)
  déclinés comme en production ; validation sur des chanteurs, locuteurs, instruments et sons jamais entendus.
  Résultats (`ia/RESULTATS.md`) : famille juste 93 %, voix reconnues 94 % (YAMNet seul 66 %), voix normales ou
  traitées 98–100 %, chops 79–90 %, stutters 66 %, autres sons pris pour des voix 1,7 %.
- Modèle ≈ 8 Mo (poids en 8 bits, calculs en 32 bits) en Core ML (`Resources/ClasseurSons.mlpackage`) et en ONNX
  (`ia/modele/classeur_sons.onnx`, exemple C# pour Windows) ; ≈ 21 ms pour un sample court sur un processeur. Essayé
  et refusé : calculs en 8 bits d'ONNX Runtime (même famille pour 78 % / 37 % des tranches seulement).
- Dans l'app : l'organisation ne change pas, l'IA intégrée prend la place de l'IA de macOS dans les mêmes règles
  (nom d'abord, mesures sûres d'abord) : `voix-iv` après `voix-ia`, ses drums/instruments mis avec ceux de macOS,
  `famille-iv` quand les règles hésitent, sortes des drums et mélodies à la place des étiquettes de macOS, sortes des
  voix, basses et FX ; diagnostic `+ivNN`. Crédits et licence de YAMNet copiés dans l'app.
- Erreurs en route : préparation plantée sur des accords de notes de longueurs différentes (30 min perdues ; chaque
  étape est maintenant gardée) ; poids des têtes illisibles par nom (`.weights.h5`) ; sorties Core ML renommées
  après conversion ; ONNX Runtime ne calibre pas un Softmax qui est une sortie.
- Le propriétaire veut « 99 % minimum pour tout ». Plus de sons : NSynth train (≈ 1000 instruments, 24 Go) et
  Medley-solos-DB (vraies chanteuses et instruments, 8 Go ; flux coupé en route, une partie seulement) lus au fil du
  téléchargement (rien sur le disque), voix hachées en plus, notes NSynth gardées dans leur tessiture : 67 043 sons.
  Résultats (6 837 sons jamais entendus) : voix 97,6 % (chops 93–96 %, stutters 86 %), drums 96,6 %, FX 94,2 %,
  basse 93,5 %, mélodies 84,4 % (notes graves prises pour des basses, synthés étranges pour des FX) ; 99 % pas
  encore atteint. Prochain levier : réapprendre aussi la fin de YAMNet, et les corrections des utilisateurs.
- Couche 14 de YAMNet réapprise sur nos sons (`ia/affiner.py`, préparation refaite : 72 643 sons, Medley complet,
  tessitures plus nettes ; ≈ 1 h 10 de préparation + 25 min) : sur les mêmes 7 379 sons jamais entendus, 92,6 %
  avec ou sans elle, et 92,7 % pour le modèle livré. Aucun gain : rien n'a changé dans l'app. Erreurs restantes :
  notes seules de NSynth ambiguës (claviers graves → basse 46, cuivres → FX 45, plucks → drums 28, guitares → voix
  26). Premier essai tué par la mémoire (écriture du jeu d'un coup) : écrit maintenant étape par étape.
- « Pas content ? » (demande du propriétaire : questions à cocher avec « Autre » en bas, pour que l'IA apprenne de
  ses erreurs ; choix : apprend sur le Mac + pour tout le monde avec accord ; bouton à la fin, pas de question à
  chaque fois) : `OrganizerFeedback.swift`, `CorrectionsIA.swift`, table `corrections_ia`
  (`supabase/corrections-ia.sql`, à coller par le propriétaire), `ia/corrections.py`. Le modèle rend maintenant
  aussi ses 1216 mesures par tranche (sortie « mesures »).

## 24 octobre : premier essai de l'Organiser sur le vrai Mac
- Le propriétaire avait encore la version du 23/10 avec le chantier des animations (la bulle qui sort de l'icône) :
  le code ne l'a plus depuis e6d0d52, il faut installer une version plus récente.
- Sur chaque projet ouvert, pourtant enregistré : « FL n'a pas enregistré ton projet », `fichier=non`. Causes
  possibles, aucune prouvée : titre de la fenêtre principale de FL sans le nom du projet, Spotlight en retard (1,5 s
  d'attente seulement sans fichier connu), dossiers trop gros parcourus en 3 s, projet déjà enregistré que FL ne
  réécrit pas (l'ancien code exigeait une écriture). Corrigé : titres et documents de toutes les fenêtres de FL,
  6 s d'attente avec Spotlight relu chaque seconde, Documents › Image-Line › FL Studio › Projects parcouru d'abord,
  projet non réécrit pris tel quel (sa lecture vérifie toujours que c'est le projet ouvert), sinon l'erreur
  `projectNotFound` et le bouton « Choisir le fichier… ». Diagnostic : ligne `recherche` (fenêtres, noms, candidats,
  récents, parcourus, pris=écrit|récent|dossier|déjà-enregistré|aucun).
- Autorisations au premier lancement (retour du propriétaire) : « Tout autoriser… » n'ouvre plus que la page
  Accessibilité de Réglages Système (plus de fenêtre du Finder sur Applications, plus de petit panneau depuis
  l'accueil), puis demande le son de FL (Audio du système, pour l'Organiser) au lieu de « Enregistrement de
  l'écran ». Celui-ci n'est plus demandé qu'au créateur de macros, quand un bloc en a besoin.
- 2e essai de l'Organiser (version 842a969) : le fichier est trouvé, la copie « _5 » écrite et ouverte par FL (la
  marque « FL Shortcuts 4922 » se voit dans la liste des patterns), résultat jugé à 99 % par le propriétaire. Mais
  l'app reste sur « FL charge les sons de la copie… » : elle attendait 3 réponses de FL en moins d'une seconde
  (jusqu'à 240 essais de plusieurs secondes, sans compteur). Maintenant : 2 réponses en moins de 3 s, 2 min 30 au
  plus, compteur de secondes, et l'application note `réponses=N lente=Nds` pour savoir si FL répondait.
- Interface (vidéo du propriétaire) : « Réinitialiser » et « Supprimer » gardent la même couleur au survol de la
  ligne (le gris « secondaire » de macOS s'éteignait sous l'ombre du survol : une vague quand la souris passait
  vite ; couleur simple maintenant, `RowActionStyle`) ; la recherche lâche la main aussi quand la fenêtre la perd
  (clic dans une autre app, le bureau, une autre fenêtre) et ne la reprend pas au retour ; pendant une recherche,
  la barre latérale n'a plus de page choisie : un clic sur une page (même celle d'avant) vide la recherche et
  l'ouvre (`sidebarSelection`).
- Drums : sortes « Drum loop » et « Fill » (demande du propriétaire). Noms : « Drum Loop », « Hat Loop »,
  « DrumLoop », « Top Loop » → Drum loop ; « Snare Fill », « Fill 1 » → Fill (« Piano Fill » reste un piano,
  « Melody Loop » une mélodie, « Loop 4 » ne dit rien). Boucle mesurée (grave d'un kick + aigus) : Drum loop, ou
  Fill si l'IA l'entend ainsi. IA réapprise (44 sortes) avec le Groove MIDI Dataset (batteurs enregistrés, boucles
  et fills, CC BY 4.0), les packs de batterie donnés par le propriétaire (Google Drive, 437 sons uniques, 7 packs ;
  jamais dans le dépôt ; « tu lui montres les sons du drive et tu lui expliques que là ça s'appelle comme ça ») et
  600 boucles + 600 fills trap fabriqués avec leurs sons seuls. Sorte de chaque son de pack d'après son type avant
  « -- » (« © FILL -- … », « TEXTURE -- … » = FX). Essai d'abord sans 2 packs : boucles
  trap clairsemées encore souvent prises pour des voix hachées (28 %), fills courts pris pour des boucles ; « deux
  tranches voix au lieu d'une » essayé, pas retenu. Modèle livré appris sur tous les packs : 92,9 % (voix 96,5,
  drums 97,3 ; Drum loop 86, Fill 91), seuil des voix 0,37. Note d'essai des tests (guitare) prise au-dessus du
  do 4 : le sol 3 d'avant, déjà à 59 % mélodie, passait à 57 % basse.
- « Il y a des pièges, il faut lire les noms dans les dossiers » (propriétaire) : chaque dossier et chaque type de
  son relus et écoutés (YAMNet). Piège : les « LOW -- NOM (C) » n'étaient pas des 808 mais des sons graves de toutes
  sortes (basses de synthé, nappes, grondements ; 30 sur 31 ont plus de 75 % de leur énergie sous 150 Hz) : appris
  comme Basse sans sorte, et un son « basse » d'après son nom qui n'est pas grave est écarté. Un dossier ne nomme
  plus un son que si son nom ne dit rien, et jamais un dossier mélangé (« fill + chop »). Le reste suit bien les
  noms (CLAP, HAT, KICK, SNARE, TOM, PERCUSSION, FILL, LOOP, FX, TEXTURE ; LAYER ignoré). Réappris : 92,4 %
  (voix 96,3, drums 97,2, basse 95,4 ; Drum loop 86, Fill 88), seuil 0,37 ; l'écart avec 92,9 % vient surtout des
  mélodies (86,0 contre 87,3), sans lien avec ce changement : variation d'un apprentissage à l'autre.
