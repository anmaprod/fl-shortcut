# FL Shortcuts — à lire avant de travailler

- Réponds en français, en tutoyant le propriétaire (musicien, pas développeur). Textes de l'app, commentaires et
  commits en français. Priorité macOS ; Windows en pause (compilé seulement pour un tag `v*`).
- Branche la plus récente : **`claude/great-hopper-qihaiy`** (en avance de 138 commits sur `claude/relaxed-mayer-ndguzv`).
  Pas de nouvelle PR sans demande (anmaprod/fl-shortcut#1 existe). Un push lance la CI ; ne pas la relancer à la main
  sans demande. Derniers tests Mac verts : commit 1843b87 (502 tests, lancés par le propriétaire sur son Mac) ; CI
  entièrement verte sur 0c18d51 (512 tests, tous les essais PASS, mémoire 15 / 54 Mo). La lecture de GitHub (CI,
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
- **IA intégrée** (`ia/`, mode d'emploi `ia/README.md`, chiffres `ia/RESULTATS.md`) : YAMNet (Apache 2.0) + deux
  têtes apprises sur des sons libres d'usage commercial (VocalSet, LibriSpeech, NSynth, Freesound CC0/CC BY ;
  JAMAIS les packs du propriétaire, qui servent seulement à mesurer). Famille + sorte parmi les choix de l'aperçu
  (`SoundKind`, sauf Back et Synth : au nom). Mac : `ClasseurSons.swift` (Core ML `Resources/ClasseurSons.mlpackage`,
  compilé par build.sh). Demande du propriétaire : l'organisation ne change pas avec l'IA, elle prend la place de
  l'IA de macOS dans les MÊMES règles (nom d'abord, mesures sûres d'abord : boucle, hi-hat à ses aigus, 3 notes
  nettes…) : `voix-iv` juste après `voix-ia`, drums/instruments mis avec ceux de macOS (`AILabels.merge`),
  `famille-iv` seulement quand les règles hésitent, sorte des drums/mélodies dans `DrumNaming`/`MelodyNaming` à la
  place des étiquettes de macOS, sorte des voix/basses/FX (`liveKindNamer`) ; diagnostic `+ivNN`. Windows : `ia/modele/classeur_sons.onnx` + exemple `ia/integration/ClasseurSons.cs`.
  Refaire : `ia/donnees.py` → `preparer.py` → `entrainer.py` → `exporter.py` → `essais_app.py` (le seuil des voix de
  `ClasseurSons.swift` doit suivre `classeur_sons.json`, vérifié par les tests).
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

## Pas encore vérifié sur le vrai FL
- IA intégrée : voix de ses projets enfin rangées en Voix ? Sortes proposées justes sur ses packs ?
- Organiser sur le fichier : ⌘S enregistre-t-il le projet ? Son fichier est-il retrouvé (titre de la fenêtre de FL,
  Spotlight, dossiers habituels) ? FL ouvre-t-il la copie rangée sans rien demander, et le script lit-il la marque ?
- La suppression par ⌥ + Suppr (si ça échoue, l'app le dit).
- Questions sans réponse : l'accueil manquant venait-il d'une installation sans désinstallation ?
