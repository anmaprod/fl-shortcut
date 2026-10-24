# FL Shortcuts — à lire avant de travailler

- Réponds en français, en tutoyant le propriétaire (musicien, pas développeur). Textes de l'app, commentaires et
  commits en français. Priorité macOS ; Windows en pause (compilé seulement pour un tag `v*`).
- Branche la plus récente : **`claude/great-hopper-qihaiy`** (en avance de 138 commits sur `claude/relaxed-mayer-ndguzv`).
  Pas de nouvelle PR sans demande (anmaprod/fl-shortcut#1 existe). Un push lance la CI ; ne pas la relancer à la main
  sans demande. Derniers tests Mac verts : commit 1843b87 (502 tests, lancés par le propriétaire sur son Mac) ; CI
  entièrement verte sur ec527b1 (« Pas content ? » et corrections de l'IA, tous les essais PASS). La lecture de GitHub (CI,
  artefacts, images) marche : vérifier chaque push dessus.
- Tout texte affiché doit avoir son anglais (la CI échoue sinon) : `python3 scripts/localisation.py generer trad.json`.
- Historique, décisions et échecs : `docs/contexte/HISTORIQUE.md` ; lien avec FL (script v16) : `PROTOCOL.md`.

## Règles du propriétaire
- Pas de lecture de l'écran, sauf pour retrouver un bouton à son nom ou son image, dans la seule fenêtre de FL, au
  moment du clic, avec l'autorisation « Enregistrement de l'écran ».
- Jamais de nom de son, de piste ou de texte tapé dans les journaux ni le diagnostic (nombres seulement).
- Essais sur un projet de test seulement. Jamais de clé secrète Supabase ni de clé privée dans le dépôt. Pas
  d'identifiant de modèle dans les commits. Le bouton s'appelle « Organiser » (pas « Tout organiser »).

## Déjà fait (ne pas refaire)
- Raccourcis, créateur de macros, compte et sauvegarde en ligne, Communauté, aide, désinstallation : voir HISTORIQUE.
- Langue du Mac : toute l'app en anglais (`Resources/en.lproj`), français par défaut.
- Trousseau : un seul élément pour la clé du script et la session du compte (une seule demande d'accès).
- Autorisations au début (`AccessibilityGuide`) : page Accessibilité seule (ni Finder, ni panneau depuis l'accueil),
  puis le son de FL (Audio du système) ; « Enregistrement de l'écran » jamais au début (créateur de macros seulement).
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
    avant » le rouvre (tout revient, suppressions comprises). Plus aucune lecture de l'écran pour la Playlist ; l'ancien
    code (réunion des clips lus dans la fenêtre, patterns descendus, « Move up ») ne sert plus que sans fichier (tests).
  - aperçu : couleur ou dégradé de chaque famille en haut, résumé et choix dessous, dans la même zone qui défile.
  - « All » automatique (script v16, API 33) ; copie toujours faite sur le fichier (Channel rack sur « All ») ;
    arrangement ouvert rangé (événement 100) ; marque sur un canal si aucun pattern n'est nommé ; page de FL remise
    devant (4 fois) au lieu de s'arrêter ; Mixer : piste qui envoie déjà ailleurs que le Master = famille sans bus ;
    sortes de voix Voix lead, Back, Ambiance ; enregistrements de FL écoutés une fois qu'ils sonnent (JAMAIS « Voix »
    d'office : guitare, piano, synthé aussi) ; voix et enregistrements : une ligne de Playlist par sorte ; sorte des
    mélodies à l'écoute (`MelodyNaming`) ; fenêtre redimensionnable qui suit son contenu ; patterns de plusieurs sons
    séparés son par son dans la copie (`splitByChannel`, comme « Split by channel » de FL) ; nom du fichier de son
    (événement 196) pour reconnaître un clip audio dont le canal ne dit rien (`sampleNames`, sinon son dossier) ;
    fichier de chaque clip audio lu directement, son passage le plus fort (`SampleFiles.swift`, règle `+fichier`),
    joué dans FL seulement s'il est introuvable ; étapes dans le journal (`ORGANIZE`).
- **Animations « morph » : RETIRÉES** le 23/10 à la demande du propriétaire (« c'est vraiment nul », après les avoir
  essayées). Les 9 tâches (moteur de mouvement, vols, fenêtres qui sortent du clic, cartes, gouttes, Organiser en
  morph) ont été enlevées : le code est revenu à 7f68c9f. Ne pas les refaire sans qu'il le demande ; tout reste dans
  l'historique git (commits 541d81c → dcd01f0) si besoin d'y regarder.
  Le 24/10, il a aussi fait retirer l'animation d'avant du changement de page (barre de gauche) : la page s'affiche
  d'un coup (`pageSwitch`). Gardées : guide, accueil, menu de l'icône, Organiser, créateur, survols.
- **IA intégrée** (`ia/`, mode d'emploi `ia/README.md`, chiffres `ia/RESULTATS.md`) : YAMNet (Apache 2.0) + deux
  têtes apprises sur des sons libres d'usage commercial (VocalSet, LibriSpeech, NSynth, Freesound CC0/CC BY, Groove
  MIDI Dataset) et, à sa demande (24/10), les packs de batterie qu'il a donnés (`FLS_IA_KITS`, jamais dans le dépôt ;
  des packs entiers gardés pour la vérification). Sortes Drum loop et Fill (demande du 24/10). Famille + sorte parmi les choix de l'aperçu
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
  Chiffres de l'IA seule (7 610 sons jamais entendus, 24/10) : ≈ 92,9 % (voix 96,5, drums 97, basse 95, FX 95,
  mélodies 87 ; Drum loop 86, Fill 91 ; sur des packs du propriétaire jamais entendus, boucles 72 %, fills 82 %) ;
  plafond : plus de sons et couche 14 de YAMNet réapprise (`ia/affiner.py`) n'y changent rien (essai non livré).
- Interface : survol coloré du menu de l'icône (`menuHover` : contour de sa couleur, grandit, ombre) voulu par le
  propriétaire partout : barre latérale (`sidebarHover`), lignes des pages, Macros, modèles, Communauté, Aide,
  palette, blocs, bouton d'enregistrement, « Menu de FL » du créateur ;
  « Mes raccourcis » = raccourcis changés + créés, jamais de macro (macro d'exemple ⌃R retirée) ; plus aucune note
  sous les blocs des macros ; « Menu de FL » en tête des blocs FL Studio de la palette ; recherche qui lâche la main
  au premier clic ailleurs ; « Cliquer sur… » › Playlist : tout le menu « Arrangement » (bouton retrouvé à son nom).

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
- IA intégrée : voix de ses projets enfin rangées en Voix ? Sortes proposées justes sur ses packs ?
- Organiser sur le fichier : 1er essai du propriétaire (24/10, ancienne version) : « FL n'a pas enregistré ton
  projet » sur chaque projet, pourtant enregistré. Corrigé sans preuve (titres de toutes les fenêtres de FL, Spotlight
  relu chaque seconde, dossier Projects de FL d'abord, projet déjà enregistré pris tel quel, bouton « Choisir le
  fichier… ») ; la ligne `recherche` du diagnostic dit ce qui a été vu. 2e essai (24/10, 842a969) : fichier trouvé,
  copie « _5 » écrite et ouverte par FL (marque « FL Shortcuts 4922 » visible), résultat « 99 % » pour lui ; puis
  bloqué sur « FL charge les sons de la copie… » (attente de 3 réponses < 1 s, sans compteur). Assoupli (2 réponses
  < 3 s, 2 min 30 au plus, compteur, `réponses=… lente=…ds` dans l'application) : à revérifier.
- La suppression par ⌥ + Suppr (si ça échoue, l'app le dit).
- Questions sans réponse : l'accueil manquant venait-il d'une installation sans désinstallation ?
