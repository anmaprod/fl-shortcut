# FL Shortcuts — à lire avant de travailler

- Réponds en français, en tutoyant le propriétaire (musicien, pas développeur). Textes de l'app, commentaires et
  commits en français. Priorité macOS ; Windows en pause (compilé seulement pour un tag `v*`).
- Branche la plus récente : **`claude/great-hopper-qihaiy`** (en avance de 138 commits sur `claude/relaxed-mayer-ndguzv`).
  Pas de nouvelle PR sans demande (anmaprod/fl-shortcut#1 existe). Un push lance la CI ; ne pas la relancer à la main
  sans demande. Derniers tests Mac verts : commit 1843b87 (502 tests, lancés par le propriétaire sur son Mac) ; CI
  entièrement verte sur 8861883 (plugins par « More plugins… », preset déposé sur Windows, tous les essais PASS ;
  lancée à la main avec `mac_runner=macos-15-intel` à sa demande : le 28/10 GitHub n'a donné aucun Mac arm64 en 15 min,
  deux fois). La lecture de GitHub (CI, artefacts, images) marche : vérifier chaque push dessus.
- Tout texte affiché doit avoir son anglais (la CI échoue sinon) : `python3 scripts/localisation.py generer trad.json`.
- Historique, décisions et échecs : `docs/contexte/HISTORIQUE.md` ; lien avec FL (script v16) : `PROTOCOL.md`.
- **Graphify, toujours** (demande du 29/10, pour moins de jetons) : chercher dans le graphe du code AVANT de lire des
  fichiers (`graphify query "…"`, `graphify explain "Nom"`, `graphify path "A" "B"`), puis lire seulement les lignes
  utiles. Session neuve : `uv tool install graphifyy && graphify update .` (30 s, sans IA ; dossier `graphify-out/`
  exclu du dépôt par `.git/info/exclude`) ; `graphify update .` après chaque changement de code. Le Graphify en ligne
  (outils MCP) lit une ancienne branche : se fier au graphe local.

## Règles du propriétaire
- Pas de lecture de l'écran, sauf pour retrouver un bouton à son nom ou son image, dans la seule fenêtre de FL, au
  moment du clic, avec l'autorisation « Enregistrement de l'écran ».
- Jamais de nom de son, de piste ou de texte tapé dans les journaux ni le diagnostic (nombres seulement).
- JAMAIS rien ajouté aux listes de plugins de FL (favoris, catégorie « FL Shortcuts » des menus Add : captures du
  28/10) ; celle que créaient d'anciennes versions part à la Corbeille au lancement (`FLPluginDatabase`). Tous les
  plugins restent choisissables : hors favoris, Add › Channel/Effect › More plugins..., nom lu au clic, double-clic
  (jamais la case devant le nom : elle en ferait un favori) ; Mac et Windows.
- Essais sur un projet de test seulement. Jamais de clé secrète Supabase ni de clé privée dans le dépôt. Pas
  d'identifiant de modèle dans les commits. Le bouton s'appelle « Organiser » (pas « Tout organiser »).

## Sécurité (audit du 25/10, à garder)
- Un autre programme du Mac peut écrire les réglages de l'app (`defaults`) et envoyer des notifications distribuées :
  rien de sensible ne doit en dépendre. L'adresse du serveur du compte vient de l'Info.plist (les réglages seulement
  pour une app compilée sans serveur, `CommunityConfig.resolve`) ; le mode capture (`debugSnapshots`) ne fait jamais
  agir l'app avec ses autorisations (plus de « vrai clic » de l'app : les scripts de la CI cliquent eux-mêmes) ;
  les modes d'essai de la CI ne visent que le faux FL (`SelfTestTarget`) et n'écrivent que leurs .txt/.json ; la liste
  des versions organisées n'accepte que des .flp et leurs « _N » du même dossier (`CopyApprovalRules.isSafe`).
- Déjà bon : touches et clics des macros au seul FL (devant), liste noire ⌘Q…, import borné, fichiers 0600 sans
  lien symbolique, Trousseau « cet appareil seulement », HTTPS seulement, script FL signé (HMAC), aucune frappe gardée.

## Déjà fait (ne pas refaire)
- Raccourcis, créateur de macros, compte et sauvegarde en ligne, Communauté, aide, désinstallation : voir HISTORIQUE.
- Langue du Mac : toute l'app en anglais (`Resources/en.lproj`), français par défaut.
- Trousseau : un seul élément pour la clé du script et la session du compte (une seule demande d'accès).
- Autorisations au début (`AccessibilityGuide`) : page Accessibilité seule (ni Finder, ni panneau depuis l'accueil),
  puis le son de FL (Audio du système) ; « Enregistrement de l'écran » jamais au début (créateur de macros seulement ;
  icônes de l'Organiser : « Autoriser » ouvre sa page des Réglages). Vidéo du 31/10 : l'accueil revient 0,8 s après la
  réponse à la question du son (plus pendant son fondu) ; TCC relu après la réponse (0,5 à 6 s) et à chaque retour de
  l'app, rien conclu pendant la question (« Son de FL » restait « À autoriser ») ; journal `AUDIO` (réponse, état TCC).
- Fenêtre principale sans bande sous la barre d'outils ; accueil remontré si l'autorisation clavier manque.
- **Organiser v5** (`Sources/FLShortcut/Organizer*.swift`, `SoundFeatures.swift`, `SoundFamilies.swift`, script FL v16) :
  - analyse sur le fichier du projet (PROTOCOL.md §9, `FLP*.swift`, `OrganizerProject*.swift`) : FL enregistre (⌘S),
    le .flp est lu ; sons de chaque pattern et de chaque piste d'après les notes et les clips (plus rien de deviné :
    ni relevé des patterns, ni chanson jouée, ni piste écoutée) ; chaque son classé par son nom ou écouté seul dans son
    pattern, à son tempo (JAMAIS accéléré : refusé par le propriétaire) ; rien n'est touché si le fichier n'est pas le
    projet ouvert ou a une forme inattendue ; le diagnostic donne les sons de chaque pattern et piste (numéros) ;
  - classement réglé (arpège → mélodie, drum loop → Drums, hi-hat par ses aigus ; 3 notes nettes ou plus → mélodie,
    jamais drums ni FX ; un canal au nom d'un synthé de mélodies, ZENOLOGY, Serum… → jamais drums ni FX) ;
  - « Organiser » : sons sans note supprimés (⌥ + Suppr de FL), Channel rack, Mixer (un bus par famille, son sur le
    Master relié à une piste libre, pistes inutiles remises à neuf), patterns et Playlist dans le même ordre, mêmes noms
    partout, le tout dans une copie « <nom>_2.flp » (voir Playlist) ;
  - IA de macOS sur une fenêtre de 1 s (son court complété) ; « Voix » seulement si l'IA entend une voix ; tempo du
    projet jamais changé ; règle de chaque son dans le diagnostic (`c4:melodie+ia`) ;
  - Playlist rangée dans une copie « <nom>_2.flp » (comme « Save new version » de FL ; puis _3…) à côté de l'original : chaque clip sur la piste de ses
    sons (les mêmes sons, la même piste ; un clip qui en chevaucherait un autre : une piste de plus dessous ; patterns
    vides en bas), pistes dans l'ordre des familles ; FL ouvre la copie (reconnue à un nom de pattern posé pour ça,
    remis aussitôt), le reste s'y fait par le script, FL l'enregistre. L'original ne bouge jamais : « Revenir comme
    avant » le rouvre (tout revient, suppressions comprises) et, demande du 28/10, met la copie (et les _N d'avant) à
    la Corbeille dès que FL l'a quittée (`CopyApproval.discard` / `DiscardAfterUndo` ; encore ouverte au bout d'une
    minute : gardée, la question revient). Validation (`OrganizerCopyApproval.swift`) : Organiser
    fermé, à la réouverture de FL Shortcuts, « Tu valides la version organisée ? » → original à la Corbeille, copie
    renommée au nom de l'original (FL enregistre puis rouvre) ; « Retourner en arrière » → copie à la Corbeille et FL
    rouvre le projet d'avant (lancé dessus s'il était fermé). Plus aucune lecture de l'écran pour la Playlist ; l'ancien
    code (réunion des clips lus dans la fenêtre, patterns descendus, « Move up ») ne sert plus que sans fichier (tests).
  - aperçu (maquette du 28/10, refait le 29/10) : titre « Organiser », « Rangement automatique » et « Options »
    (pages de FL, Renommer, bus, sons sans note, Copier le diagnostic) en haut ; familles sur 2 colonnes dès 600
    points (`familyColumns`, fenêtre ouverte à 720), en-tête (poignée, couleur, nom, Mixer [départ], icône) au-dessus
    d'une carte de verre de ses sons : ancien nom → [nouveau nom ▾] [piste] ; « Organiser » toujours bleu
    (`AlwaysBlueButtonStyle` : le panneau n'est jamais actif) ; case du Mixer tirée comme FL (`HiddenDrag` ; flèche cachée même FL devant, `BackgroundCursor`, 30/10).
    Familles prises en entier (30/10) : copie nette qui suit la souris, place en transparence, trait de couleur où
    elle tombe (`FamilyDrag`, `OrganizerView.dropTarget`) ; plus de glisser du système (image floue + « + »).
  - « All » automatique (script v16, API 33) ; copie toujours faite sur le fichier (Channel rack sur « All ») ;
    arrangement ouvert rangé (événement 100) ; marque sur un canal si aucun pattern n'est nommé ; page de FL remise
    devant (4 fois) au lieu de s'arrêter ; Mixer : piste qui envoie déjà ailleurs que le Master = famille sans bus ;
    sortes de voix Voix lead, Back, Ambiance ; enregistrements de FL écoutés une fois qu'ils sonnent (JAMAIS « Voix »
    d'office : guitare, piano, synthé aussi) ; voix et enregistrements : une ligne de Playlist par sorte ; sorte des
    mélodies à l'écoute (`MelodyNaming`) ; fenêtre redimensionnable qui suit son contenu (25/10 : hors aperçu, seule
    la largeur se tire ; aperçu tiré en hauteur, jamais sous 420 ; largeur 440 à 760 ; cartes sans zoom) ; patterns de plusieurs sons
    séparés son par son dans la copie (`splitByChannel`, comme « Split by channel » de FL) ; nom du fichier de son
    (événement 196) pour reconnaître un clip audio dont le canal ne dit rien (`sampleNames`, sinon son dossier) ;
    fichier de chaque clip audio lu directement, son passage le plus fort (`SampleFiles.swift`, règle `+fichier`),
    joué dans FL seulement s'il est introuvable ; étapes dans le journal (`ORGANIZE`).
  - boîte « Invalid project data folder » de FL à l'ouverture de la copie (capture du 25/10 : l'Organiser comptait
    les sons pendant qu'elle attendait, « pas les mêmes sons ») : la copie ne garde pas un dossier de données qui
    n'existe pas (événement 202, `withoutMissingDataFolder` ; l'original ne bouge pas) ; si FL la montre quand même,
    Entrée valide « Do nothing » (`answerDialog`, 4 fois au plus) ; les sons ne sont comptés qu'une fois tous là
    (attente jusqu'à 2 min 30). Diagnostic : `dossier-données=retiré`, `boîte=dossier-données`.
- **Animations « morph » : RETIRÉES** le 23/10 à la demande du propriétaire (« c'est vraiment nul », après les avoir
  essayées). Les 9 tâches (moteur de mouvement, vols, fenêtres qui sortent du clic, cartes, gouttes, Organiser en
  morph) ont été enlevées : le code est revenu à 7f68c9f. Ne pas les refaire sans qu'il le demande ; tout reste dans
  l'historique git (commits 541d81c → dcd01f0) si besoin d'y regarder.
  Le 24/10, il a aussi fait retirer l'animation d'avant du changement de page (barre de gauche) : la page s'affiche
  d'un coup (`pageSwitch`). Gardées : guide, accueil, menu de l'icône, Organiser, créateur, survols.
- **IA intégrée** (`ia/`, mode d'emploi `ia/README.md`, chiffres `ia/RESULTATS.md`) : YAMNet (Apache 2.0) + deux
  têtes apprises sur des sons libres d'usage commercial (VocalSet, LibriSpeech, NSynth, Freesound CC0/CC BY, Groove
  MIDI Dataset) et, à sa demande (24/10), les packs de batterie qu'il a donnés (`FLS_IA_KITS`, jamais dans le dépôt ;
  tous appris, `FLS_IA_KITS_VERIF=0` ; sorte d'après le type avant « -- » dans le NOM du son, PIÈGES : « LOW » =
  basse quelconque, pas une 808 ; jamais un dossier mélangé « fill + chop »). Sortes Drum loop et Fill (24/10). Famille + sorte parmi les choix de l'aperçu
  (`SoundKind`, sauf Back et Synth : au nom). Mac : `ClasseurSons.swift` (Core ML `Resources/ClasseurSons.mlpackage`,
  compilé par build.sh). Demande du propriétaire : l'organisation ne change pas avec l'IA, elle prend la place de
  l'IA de macOS dans les MÊMES règles (nom d'abord, mesures sûres d'abord : boucle, hi-hat à ses aigus, 3 notes
  nettes…) : `voix-iv` juste après `voix-ia`, drums/instruments mis avec ceux de macOS (`AILabels.merge`),
  `famille-iv` seulement quand les règles hésitent, sorte des drums/mélodies dans `DrumNaming`/`MelodyNaming` à la
  place des étiquettes de macOS, sorte des voix/basses/FX (`liveKindNamer`) ; diagnostic `+ivNN`. Windows : `ia/modele/classeur_sons.onnx` + exemple `ia/integration/ClasseurSons.cs`.
  Refaire : `ia/donnees.py` → `preparer.py` → `entrainer.py` → `exporter.py` → `essais_app.py` (le seuil des voix de
  `ClasseurSons.swift` doit suivre `classeur_sons.json`, vérifié par les tests).
- **L'IA apprend de ses erreurs** (demande du propriétaire) : bouton « Pas content ? » à la fin de l'Organiser
  (`OrganizerFeedback.swift` : cases à cocher + « Autre » en bas, puis la bonne famille/sorte des sons écoutés) ; les
  changements de l'aperçu comptent aussi, sans rien demander. Retenu sur le Mac (`CorrectionsIA.swift`, empreinte
  YAMNet, ressemblance ≥ 0,97 → règle `corrige` avant toutes les autres) ; partagé seulement avec la case « Aider
  l'IA de tout le monde » (des nombres : jamais le son, son nom ni le texte tapé) vers la table `corrections_ia`
  (`supabase/corrections-ia.sql`, À COLLER PAR LE PROPRIÉTAIRE dans Supabase, étape 9 du README) ; réappris par
  `ia/corrections.py` puis `entrainer.py`. Playlist, Mixer, aspect et « Autre » : message à l'équipe (support).
  Chiffres de l'IA seule (7 610 sons jamais entendus, 24/10) : ≈ 92,4 % (voix 96, drums 97, basse 95, FX 95,
  mélodies 86 ; Drum loop 86, Fill 88 ; sur des packs du propriétaire jamais entendus, boucles 72 %, fills 82 %) ;
  plafond : plus de sons et couche 14 de YAMNet réapprise (`ia/affiner.py`) n'y changent rien (essai non livré).
- **Organiser, demandes du 25/10** (vidéos du propriétaire) : case de la piste du Mixer à côté de chaque son (comme le
  Channel rack de FL : tirer haut/bas, clic pour écrire, ⌥ + clic automatique ; `MixerSlotBox`, `slots`), départ de
  chaque famille dans le Mixer (« Drums 27 → 32 », 808 et bus compris ; `FamilyStyle.mixerStart`, gardé), bouton
  « Rangement automatique », familles glissées comme des dossiers (`options.familyOrder`, gardé ; Channel rack, Mixer et
  Playlist suivent), « Écrire… » à la place de « À vérifier » dans la liste d'un son (nom tapé posé partout ;
  `OrganizerPlan.make(names:slots:)`, `pinned`). Vraies icônes de FL découpées de sa capture (`Resources/FLIcons.png`,
  `FLIconArt`). Bug « FL n'a pas supprimé exactement les sons sans note » : FL supprimait bien, relu trop tôt → relu
  jusqu'à la fin (6 s), suite avec ce qui est vraiment parti (`removed`) ; « raison 5 » : un son refusé reste « À
  vérifier », le diagnostic dit l'opération refusée (`lastRefusal`, « op6:5 »).
- **Windows** (en cours, demande du 25/10 : « les fonctionnalités pareil », puis pack de test pour ses amis) : cœur
  `windows/FLShortcut.Core/Organizer/*.cs` recopié du Mac (fichier .flp, copie rangée, classement, IA ONNX, plan, places,
  application, validation, corrections, contrôleur ; 180+ essais `dotnet test`). App WinUI : lien MIDI sur `LinkCore`
  (`MidiLink`), son de FL seul (`FlAudioCapture` : « process loopback », sinon tout le PC ; un pilote ASIO de carte son
  passe à côté de Windows), touches à FL devant seulement (`FlControl`), fichier du projet (`ProjectFileWindows` :
  Ctrl+S, titres des fenêtres de FL, dossiers surveillés), `OrganizerLive`, fenêtre en code (`OrganizerWindow`, mêmes
  textes que le Mac ; pas encore d'icônes de FL ni d'envoi à l'équipe), « Tu valides la version organisée ? »
  (`CopyApprovalPrompt`, Corbeille par le shell). **Même interface que le Mac** (29/10, « exactement la même interface
  sur win ») : `MacLook.cs` (couleurs, plaques, icônes dessinées aux noms des symboles du Mac, survol plein), fenêtre
  principale `MainShell*.cs` (barre de gauche, cartes `CatalogGroups`, Mes raccourcis, recherche, accueil), Macros
  `MacrosPage.cs` (dans la fenêtre ; créateur 3 colonnes, palette `CreatorPalette`), Organiser `OrganizerWindow.cs`
  (fond noir, 2 colonnes, Options, tuto aux images du Mac embarquées, réglage `OrganizerTutorialSeen`), menu de l'icône
  `TrayMenu.cs` (noir, sans « Mettre en pause »), question de validation sombre ; noms des touches en anglais si
  l'app l'est (`Vk.Name`). Photos CI : principale*, macros-*, organiser-* (dont tuto), menu-icone. La CI seule vérifie
  l'app (le propriétaire : « on s'en fout de Linux ») ; le cœur se teste avec `dotnet test`.
  CI : `--photos <dossier>` photographie les 6 écrans de l'Organiser (sons d'exemple), sous le débogueur cdb (pile et
  erreur d'origine si WinUI tombe). JAMAIS `SetDefaultDllDirectories` (la 1re fenêtre tombait : E_INVALIDARG du
  Windows App SDK auto-contenu) : `SetDllDirectory("")`. JAMAIS retirer la barre de titre d'une fenêtre WinUI déjà
  créée (`SetBorderAndTitleBar`, présentation « menu ») : le Windows App SDK libère deux fois un objet de ses boutons,
  mémoire abîmée puis chute (CI du 29/10) ; menu de l'icône = `AppWindow.Create` en présentation « menu » +
  `DesktopWindowXamlSource` (`TrayMenu.cs`) ; photos de la CI sous page heap (une telle écriture s'y arrête net).
  Macros (cœur `windows/FLShortcut.Core/Macros/`) : modèle et JSON
  communs au Mac, registre des blocs, validation, pages/« Cliquer sur… », modèles, catalogue des 270 raccourcis de FL
  (`Catalog.cs`, généré depuis Catalog.swift), programme compilé et interpréteur (`MacroProgram.cs`,
  `MacroInterpreter.cs` : miroir de MacroInterpreter.swift, mêmes essais avec de faux effets), bibliothèque
  (`%APPDATA%\FL Shortcuts\macros.json`, même format que le Mac, `MacroLibraryStore.cs` : copies de secours), raccourcis
  de type macro (`macroRef` + lien caché comme le Mac), effets (`MacroEffectsWindows.cs` derrière `IFlDriver`, essayés
  sur un faux FL ; pilote Win32 et lanceur `Services/MacroRunner.cs`, Échap compté par le hook) : touches, menus et
  boîtes de FL (reconnus par classe/style, jamais le titre), actions de FL (lien) ou leur touche, pages, Organiser.
  Faits aussi (28/10) : clics appris (« Montrer dans FL… », sans crochet souris) et glisser, Menu de FL (titre en haut
  de FL puis chaque élément cliqué comme à la main, retrouvé à son nom : menu standard lu par Windows avec l'état grisé,
  sinon texte lu dans la seule fenêtre de FL, `FlScreen`), menu de la piste (piste visée = dernier clic dans FL, crochet
  souris seulement si une macro la vise), preset déposé (glisser d'OLE comme depuis l'Explorateur) ou écrit dans la
  boîte « Open », « Cliquer sur… » (sauf menu Arrangement), Nom et couleur (sans l'icône) : les 5 modèles peuvent
  tourner. PAS ENCORE (`MacroEffectsWindows.Unsupported`, macro bloquée, raccourci laissé à FL) : bouton retrouvé à son
  image, entrée, larsen, carte son, menu Arrangement. Essai CI `--selftest-macros` : faux FL dans l'appli (vraie
  fenêtre Windows) et les vrais blocs joués dessus (`MacroSelfTest.cs`, rapport `macros-essai.txt`). Journal :
  `%LOCALAPPDATA%\FL Shortcuts\journal.txt` (`AppLogFile`, 512 Ko). Page Macros comme le Mac (29/10, `MacrosPage.cs`
  dans la fenêtre principale, « Macros » de la barre de gauche et de l'icône ; logique dans `MacroDrafts.cs`) : liste
  (Macro vide, Modèles…, ⋯ Dupliquer/Supprimer annulable), créateur en 3 colonnes (palette du Mac `CreatorPalette`,
  étapes glissées, interrupteur, réglages à droite, « Retirer ce bloc » ; blocs pas faits sur Windows « à régler sur le
  Mac »), photos `macros-liste.png`/`macros-createur.png` sur la CI ; fiche d'un raccourci : 3e type « Macro ».
  Reste : ces blocs, blocs imbriqués (si/répéter) dans le créateur, enregistrement, compte, Communauté, Aide.
- **Aspect validé le 28/10** (maquette, `HISTORIQUE`) : plus de Liquid Glass depuis le 29/10 (plaques dessinées), sans lavis ni lueur ; fond de
  fenêtre plein (« sans le Liquid Glass derrière »), verre devant : cartes, touches, cartes de l'Organiser
  (`GlassPlate`, dessiné : pas de `glassEffect` par ligne) ; titre de
  page seul ; raccourcis en cartes sur deux colonnes (`CardMasonry`) ; touche changée en bleu + ↺ ; rien d'inutile (pas de
  phrases d'explication, de compteurs, de pause dans les menus) ; bleu pour l'action ; aucune animation en plus ;
  logo : c'est lui qui le fera. Textes « clairs sans détail » : une phrase courte par bloc, aucune explication de
  la façon de faire ; bloc « Ouvrir un preset » (ex-« Déposer un preset sur la piste »). Début (maquettes du 28/10,
  sans animation du titre : refusée) : « FL Shortcuts » seul puis une carte Clavier / Son de FL avec leur état
  (À autoriser, En attente…, Autorisé) ; « Relier FL Studio » en 3 étapes d'une ligne + aperçu de MIDI Settings ;
  guide « Bienvenue » (une ligne par partie) puis pages en 3 étapes d'une ligne (plus d'astuce ni de résumé) ;
  panneau « Active FL Shortcuts » ; cartes `PlateRows`/`GlassPlateBackground`, plus aucune lueur (`BrandGlow` retiré).
- **Tuto** (29/10) : page `site/tuto.html` (7 étapes dessinées comme l'app ; images du README `docs/images/tuto-*.png`
  par `rendre-tuto.js`) ; Organiser : tuto en 4 images à la 1re ouverture, avant l'écoute (`OrganizerTutorial.swift`,
  « Revoir le tuto » dans Options ; images `Resources/*.lproj/OrganiserTuto*.png` de `docs/images/organiser-tuto.html`).
- Créateur de macros (30/10, « le bouton enregistrer ne fonctionne plus ») : « Enregistrer » toujours actif (chaque
  changement s'enregistre seul 0,5 s après) ; il enregistre et revient aux macros (Mac et Windows).
- Pages Macros, Communauté, Mon compte, Aide « pas belles / plus ergonomiques » (30/10) : maquette (artefact privé
  `L3Vuc2e9Tj8mrJAmRPqiQy`) validée (« go change ça ») et faite sur Mac : Macros = 3 grandes cartes (Enregistrer une
  macro, Macro vide, Modèles) + macros en cartes (interrupteur, touches ; sans pastilles de blocs ni ⋯ : clic droit) ;
  Communauté = « Partager » bleu en haut, recherche + Tout/Macros/Raccourcis/Les miens, partages en cartes ; Mon
  compte = cartes profil, sauvegarde, choix des versions ; Aide = grande recherche, questions en carte (étapes
  numérotées, `HelpEntry.steps`), Écrire à l'équipe / Revoir le guide à droite (sans tuiles de thèmes : retirées à sa
  demande). Windows : seule la page Macros existe (pas encore à ce nouvel aspect).
- **Compte : connexion et profil** (maquette PDF/HTML « Mon compte — connexion et profil » du 30/10, faite par une
  autre session que celle des pages : les deux ont travaillé en même temps sur la branche, toujours `git fetch` avant
  d'envoyer) : cartes Se connecter / Créer un compte / Code en 6 cases (`AccountAuthViews.swift`, `CommunitySignIn`),
  pseudo vérifié en direct (onglets : fond qui glisse, carte qui change en un seul mouvement ; règles du mot de passe
  en `FlowRow`) ; photo de profil 256 × 256 JPEG préparée sur le Mac (`ProfilePhoto.swift`), « Modifier le
  profil » (`EditProfileSheet.swift` : zoom, glisser, Retirer, pseudo) ; photo ou initiale de couleur dans l'en-tête,
  Mon compte, cartes et page d'un auteur ; « Signaler la photo… », « Retirer la photo » (administrateur). Serveur :
  `supabase/profil.sql` (collé dans Supabase par le propriétaire le 30/10, étape 10 du README ; sans lui,
  initiales et « pas encore ouverts »), essais `supabase/tests/profil.sql`.
- Organiser, vidéo du 30/10 : chargement en carte à barres d'égaliseur essayé puis RETIRÉ à sa demande (« remet comme
  avant, j'aime pas ») : le chargement d'avant (badge, barre, « Ne touche pas à FL. », Arrêter) ; panneau retiré de
  l'écran pendant la pose d'une icône (`OrganizerWindow.stepAside` : une fenêtre de FL s'ouvrait dessous) ;
  familles posées où on les lâche, à gauche ou à droite, dessus ou dessous (`dropSlot`, `placing`, colonnes gardées
  `leftCount`, ordre = gauche puis droite) ; « Pas content ? » liste TOUS les sons (un son rangé par son nom est
  retenu par son nom codé SHA-256, `corrections-noms.json`, règle `corrige-nom`, jamais envoyé) ; fin en court
  (`doneSummary`, « Détails » pour tout le texte) : la fenêtre ne grandit plus.
- **Icônes de FL** (vidéo du 31/10 : « il faut qu'il clique sur changer l'icon et pas rename, color and icon » ; le
  bouton de gauche de la fenêtre F2 propose des NOMS, pas la grille) : clic droit sur le NOM de l'élément › « Change
  icon… » › case de la grille (`MacroIconPlacement.swift`). « Change icon… » lu dans le menu (Enregistrement de
  l'écran ; menu lu sans lui : Échap, rien cliqué) ; sans l'autorisation, place retenue par taille de menu
  (`macroSpots.v3.changeIcon`), sinon montrée une fois. Bloc « Nom et couleur » : clic droit au dernier clic dans FL
  (icône seule : sans le lien). Organiser : nom retrouvé dans la fenêtre de FL (`OrganizerIconTargets.swift` : colonne
  du Channel rack près du titre « Channel rack », noms VERTICAUX du Mixer lus dans l'image tournée ; seulement les noms
  lus et les places entre deux, jamais au-delà : un clic droit ailleurs peut changer le projet) ; sans « Enregistrement
  de l'écran », dit dans l'aperçu avant « Organiser » (« Autoriser » ; une version recompilée la perd : décocher puis
  recocher) ; une icône manquée n'arrête plus que les icônes (le Mixer n'était plus rangé), raison dans la fin,
  Échap arrête tout. « Reset » n'est PAS une icône (31/10 : il retire l'icône dans FL) : hors du sélecteur, « Aucune ».
  Essai CI : `scenarioIcon` (grille du faux FL).
- Organiser, « Installer le lien » (31/10, « ça se ferme ») : FL remis devant (⌘Q quittait FL Shortcuts, activé par
  l'installation), la fenêtre attend que FL soit quitté puis rouvert (« Ouvrir FL Studio » s'il est fermé), puis
  l'image MIDI Settings des 4 cases (`.midiSettings`, image du README) tant que FL ne répond pas ; « Copier le
  diagnostic » sur chaque écran de fin.
- **À l'identique des maquettes** (29/10, `HISTORIQUE`) : fenêtre principale = `Main.dc.html` (plaque de gauche
  avec les boutons de la fenêtre, `MainWindowChrome` ; en-tête titre + capsule du compte ; cartes par groupe,
  `CatalogGroups`) ; créateur = `Macros.dc.html` (← rond, nom, touches, « Enregistrer » bleu ; « Retirer ce bloc »).
  Gardés hors maquette (sa demande) : recherche par une touche, « Enregistrer clics et touches ». Retirés : menu ⋯,
  « + » des pages de raccourcis, Dupliquer, « Si le bloc échoue », Note, barre d'outils, Exporter du créateur.
- Interface, survol (choix du propriétaire le 29/10, exemple « B — intérieur plein » de la maquette) : une option
  survolée est PLEINE de sa couleur, texte en blanc, icône de couleur en blanc translucide (`menuHover` →
  `hoverFilled`, détails colorés par `hoverTint`) ; plus de contour ni de halo ; le contenu ne grossit jamais ; les
  cartes de l'Organiser (conteneurs) n'ont plus de survol. Partout : barre latérale (`sidebarRow` : page choisie en
  pastille de SA couleur (30/10, plus le bleu), sans sélection grise du système ni compteurs), lignes des cartes (`cardRow`), menu de l'icône,
  Macros, modèles, Communauté, Aide, palette, blocs, bouton d'enregistrement, « Menu de FL » du créateur, guide.
  Menu de l'icône (29/10, « plus de Liquid Glass… fond noir ») ; plus petit le 30/10 (280 de large, lignes de 34 ;
  Windows 250) : fond noir plein `MenuBackground`, toujours sombre,
  fond du système caché (`MenuPanel.clearSystemBackground`) ; « Désinstaller » en texte gris ; photo `menu-icone.png`.
  Désinstallation (29/10, « dans le nouveau style… pas toucher à sa fonctionnalité juste à l'image ») : fond noir,
  plaques claires, capsules (`UninstallView` seule ; `UninstallFlow`/`Uninstaller` inchangés).
  « Mes raccourcis » = raccourcis changés + créés, jamais de macro (macro d'exemple ⌃R retirée) ; plus aucune note
  sous les blocs des macros ; « Menu de FL » en tête des blocs FL Studio de la palette ; recherche qui lâche la main
  au premier clic ailleurs ; « Cliquer sur… » › Playlist : tout le menu « Arrangement » (bouton retrouvé à son nom).

- Modèles de macro (25/10, demande du propriétaire) : ses 4 macros « 3/4 », « Enregistrement Rapide », « Export
  Stems », « Ouvre un VST », puis « Supprimer les clips audio inutilisés » ; retirés : l'ancien « Enregistrement
  rapide », « Organiser », « Enregistrer puis exporter en WAV ». « Choisir… » du preset s'ouvre dans Image-Line › FL
  Studio › Presets › Mixer presets (`PresetPanel.startFolder`).
- Clics « intelligents » de l'enregistrement (`SmartClicks`, 25/10) : FILE/EDIT/ADD… dans la fenêtre de FL puis un
  élément de son menu (noms lus au clic, menus de FL compris) → « Menu de FL › … » (chemin complet retrouvé dans la
  barre de macOS) ou son raccourci ; Add › Channel/Effect › … → « Cliquer sur… » Ajouter un instrument / un effet ;
  bouton Arrangement + ligne de son menu → option de la Playlist ; « Clic à un endroit appris » en dernier recours.
- Menu de l'icône (25/10) : chaque ligne qui mène à la fenêtre (« Modifier les raccourcis… », « Macros… »,
  « Signaler ce problème… ») y va toujours, même fenêtre déjà ouverte ailleurs (`EditorView.go(to:)` : créateur
  refermé, recherche finie, fiche fermée ; `ShortcutsLink` ; `MainWindow.bringForward` : devant, même réduite).
- « Quitter et rouvrir » (macOS, après une autorisation) : la copie relancée attend l'ancienne au lieu de partir
  (`SingleInstance`, clé `quittingPID`) ; la demande venant de l'extension « Confidentialité et sécurité » (sans nom
  d'app) est reconnue (`relaunches`) ; un surveillant posé à l'ouverture des Réglages rouvre l'app même fermée de
  force (pas après ⌘Q : note `FLShortcuts.norelaunch`) ; l'app reprend là où on en était si relancée moins de 2 min après
  (`AppResume.swift` : accueil et son écran, panneau des autorisations, fenêtre principale, page, macro, Organiser).
- Aspect : les versions d'avant sont fabriquées par GitHub avec Xcode 26.6 (kit macOS 26). Le Mac du propriétaire
  a Xcode 27 : avec le kit 27, macOS 27 dessine l'app autrement (boutons en rectangle arrondi…). `build.sh` prend
  alors tout seul le kit 26 des outils en ligne de commande (`--build-system native`, une architecture à la fois : l'outil d'Xcode inscrivait
  « sdk 13.0 ») et vérifie le kit inscrit (`vtool`). Ne pas « corriger » l'aspect en code.

## Sortie (plan validé le 23/10 ; à faire SEULEMENT quand la version finale sera validée par le propriétaire)
- Gratuit, sans frais fixes : page Gumroad en « 0 € + » (prix libre, Gumroad gère la TVA ; 10 % + 0,50 $ seulement sur
  les tips). Dépôt public : CI et versions GitHub gratuites ; Supabase gratuit (500 Mo : plafonner `corrections_ia`).
- « Tampon » gratuit : signature stable par un certificat à nous gardé dans les secrets GitHub (jamais dans le dépôt),
  pour que macOS garde les autorisations d'une mise à jour à l'autre. Plus tard, avec les tips : compte Apple
  (99 €/an) → notarisation, plus de « Ouvrir quand même » (build.sh est prêt : SIGN_IDENTITY, NOTARY_*).
- Aussi : « Nouvelle version disponible » dans l'app, page de téléchargement à jour (`site/index.html` dit encore
  « n'utilise pas le réseau ») avec guide en images pour « Ouvrir quand même ».

## Pas encore vérifié sur le vrai FL
- Icônes (31/10) : clic droit › « Change icon… » sur le vrai FL (macro « Nom et couleur » après un clic sur le nom ;
  Organiser : noms du Channel rack et noms verticaux du Mixer retrouvés ?) ; journal `ICON` (`--diag-icon 7-4`).
- Plugins (28/10) : la catégorie « FL Shortcuts » des menus Add a-t-elle disparu après un redémarrage de FL ? « Ouvre
  un VST » avec un plugin hors favoris (Add › Channel › More plugins..., nom lu puis double-clic) ; journal `PLUGIN`.
- Menu de FL (macOS), retour du 28/10 : « Export Stems » (File › Export › All playlist tracks › Time selection…) dit
  « grisé » même après ⌘A → FL ne met à jour l'état grisé qu'à l'ouverture du menu : élément lu grisé = ses menus
  ouverts un à un puis relu (`MenuBarAX.reopened`, essai CI sur le faux FL `scenarioGreyedItem`). Menu rempli à son
  ouverture (Add › Channel) : menus ouverts niveau par niveau avant « introuvable ». « Ajouter un effet » gelait FL (pas à la main) et « Ouvre un VST »
  (favori) « bloquait » : par AXPress, FL fait l'action PENDANT la demande d'Accessibilité (plugin chargé là-dedans,
  attente de 6 s puis « FL n'a pas répondu »). Les macros choisissent maintenant l'élément comme à la main (menus
  ouverts, vrai clic, `MenuBarAX.press(click:)`), AXPress seulement en secours (élément hors écran), attente 1,5 s.
  À revérifier chez lui (journal `~/Library/Logs/FL Shortcuts/macro.log`, lignes MENU).
- IA intégrée : voix de ses projets enfin rangées en Voix ? Sortes proposées justes sur ses packs ?
- Organiser sur le fichier : 1er essai du propriétaire (24/10, ancienne version) : « FL n'a pas enregistré ton
  projet » sur chaque projet, pourtant enregistré. Corrigé sans preuve (titres de toutes les fenêtres de FL, Spotlight
  relu chaque seconde, dossier Projects de FL d'abord, projet déjà enregistré pris tel quel, bouton « Choisir le
  fichier… ») ; la ligne `recherche` du diagnostic dit ce qui a été vu. 2e essai (24/10, 842a969) : fichier trouvé,
  copie « _5 » écrite et ouverte par FL (marque « FL Shortcuts 4922 » visible), résultat « 99 % » pour lui ; puis
  bloqué sur « FL charge les sons de la copie… » (attente de 3 réponses < 1 s, sans compteur). Assoupli (2 réponses
  < 3 s, 2 min 30 au plus, compteur, `réponses=… lente=…ds` dans l'application) : à revérifier.
- La suppression par ⌥ + Suppr (si ça échoue, l'app le dit).
- Barre de recherche qui lâche la main au clic ailleurs : bonne à vrais clics sur la CI (15dcdc0, macOS 26, photos
  `recherche-*.png` de la mesure) ; « toujours là » chez lui avec 992aa5b : à revérifier sur son Mac.
- Clics intelligents sur le vrai FL : les noms des éléments de ses menus sont-ils lus avant que le menu se ferme ?
- Questions sans réponse : l'accueil manquant venait-il d'une installation sans désinstallation ? Quel glisser-déposer
  des macros ne marche plus chez lui (25/10 : palette → liste et rangement des blocs marchent sur la CI, bloc
  « Glisser-déposer » présent ; essai « vite » comme une vraie main ajouté à la mesure, `glisser-essai.txt`) ? Noms des stems après deux exports (« pas de double ») : à voir avant d'y toucher.
