# Revue de l'incrément 2 « Créateur de macros » (4d48844..9d2c8c9)

Revue en lecture seule, faite sur le code uniquement : je n'ai ni compilé ni mesuré.
- Les 29 fichiers du diff ont été lus, dont tout le nouveau code (Library, EditorModel, EditorView, Inspector, Palette, RunMonitor, Exchange, LibraryView, Editing).
- J'ai aussi lu les diffs de Model, Store, KeyRouter, FLShortcutApp, EditorView, MacroEffectsMac, MacroRunner, MacroRegistry, MacroTemplates, MacroSelfTest, build.yml, mesure-interface.sh et MACROS.md.
- Les trois fichiers de tests nouveaux ont été lus, ainsi que MacroValidation, GlassStyle, Recorder, TrackMemory et MIDILink.setOnDemand pour le contexte.

Aucune API de macOS 14 ou plus n'est utilisée sans garde. Il n'y a aucun `!`, `try!`, `as!` ni `print` dans le nouveau code d'interface.

## Strengths

- **Bibliothèque** (`MacroLibraryStore.swift`) :
  - fichier séparé, écriture atomique en 0600 par `SecureFile`, lien symbolique refusé (testé), copie « précédente » une seule fois par lancement ;
  - cas dégradés distingués et testés : illisible, plus récent, partiel, inaccessible (jamais réécrit) ;
  - ids en double régénérés, décodage macro par macro (`Lossy`), blocs inconnus conservés et macro bloquée.
- **Compatibilité avec les anciennes versions** (`Model.swift:139-288`) :
  - `macroRef` doublé du lien caché `unknownAction = "macroRef:<uuid>"` ;
  - `MacroRefTests` couvre l'aller-retour, la réécriture par une ancienne version, la priorité d'un modèle en ligne sur un lien périmé, et le refus à l'import de profil.
- **Store** :
  - programmes compilés sur le thread principal et mis en cache par (id, révision), index qui ne porte que des références partagées ;
  - `activeNeeds` calculé à partir des programmes réellement indexés (`ShortcutIndex.macroPrograms`). Un raccourci bloqué ou désactivé ne laisse donc plus `TrackMemory` ni les ports MIDI actifs, ce qui est plus fidèle que l'ancien `filter { template == .autoRecord }` ;
  - `testTemplateNeedsAreUnchanged` fige le comportement du modèle livré.
- **Sécurité, couche d'effets** :
  - la liste noire des touches est revérifiée dans l'effet (`MacroEffectsMac.swift:317`, `MacroFLBlocks.swift:165`) ;
  - `ClickTarget.toLearn` échoue en fermé deux fois (validation, et effet qui renvoie `nil`) ;
  - le menu de la piste exige 2 ou 3 lettres dès la validation ;
  - `chooseFile` en mode strict : préfixe du dossier personnel, pas de `..`, extension `.fst` ;
  - `AXMenus.findItem` ignore la barre des menus. Le bloc caché `menuAX` ne peut donc ouvrir que des menus contextuels déjà ouverts.
- **Import et export** :
  - 256 Ko, 200 blocs, 4 niveaux, ids régénérés, nom nettoyé par `displaySafe`, macro sans raccourci à l'arrivée ;
  - à l'export, positions apprises retirées et chemins relatifs au dossier personnel, sans nom de compte.
- **Édition** :
  - logique pure et testée (`MacroOutline`) : refus de déplacer un bloc dans lui-même, limite de profondeur, numérotation des erreurs ;
  - lignes `Equatable`, aucun objet observé par ligne, id de ligne stable, inspecteur construit pour le seul bloc choisi ;
  - brouillon enregistré après 0,5 s, vidé à la fermeture, au changement de macro et à l'arrêt de l'app, avec l'ordre non garanti des observateurs géré explicitement ;
  - annulation regroupée par champ.
- **Suivi d'essai** : `MacroRunMonitor` est borné à 200 entrées, branché seulement pendant un essai, et le raccourci tourne avec `observer == nil`. L'essai CI « blocs » passe par le même chemin que « Tester » (`monitor.start` puis `MacroRunner.start`).
- **Rien de nouveau au repos, en dehors de la fenêtre ouverte** : pas de minuterie permanente ni d'observateur permanent. Les seuls minuteurs (`ClickTeacher` à 50 ms, `Recorder` à 5 s) vivent le temps d'une action.
- **Aucun cycle de rétention trouvé** dans le nouveau code :
  - les fermetures de longue durée sont `[weak self]`, y compris `terminateObserver`, `onChange` et `ClickTeacher.completion` ;
  - `window` et `undoManager` sont `weak`, les fermetures d'annulation ne capturent que des valeurs.

## Issues

### Critical (Must Fix)

Aucun. Les garde-fous de sécurité restent dans la couche d'effets, et je n'ai pas trouvé de contournement par une macro construite ou importée.

### Important (Should Fix)

**I1. Libération du créateur : l'hypothèse « fenêtre libérée à la fermeture » est très probablement fausse, et le coût d'ouverture n'est pas expliqué par le code.**
- Fichiers : `FLShortcutApp.swift:58-65` (commentaire « libérée à sa fermeture »), `MacroEditorView.swift:50` et `:77`, `MacroEditorModel.swift:121-125`, `MACROS.md` (même affirmation).
- **Cause probable de la non-libération (91 Mo fermé)**
  - C'est une scène `Window` SwiftUI : à la fermeture elle est masquée et SwiftUI garde le `NSWindow`, le `NSHostingView` et l'état `@StateObject`. C'est ce qui permet à `openWindow(id:)` de la réafficher.
  - Rien dans le code ne force la destruction. `close()` enregistre, vide l'annulation et remet les besoins à zéro, mais ne touche ni à `draft`, ni à `rows`, ni au moniteur, ni à la hiérarchie de vues.
  - Une fuite d'allocateur seule n'expliquerait pas les chiffres : la mémoire redescend déjà de 67 à 60 Mo en passant à la page Macros, donc le processus sait rendre des pages. Ce sont des références vivantes.
- **Aucun singleton ne tient le modèle ni le brouillon.** `MacroCreatorLink` ne garde qu'une requête. `ClickTeacher` n'a qu'une fenêtre `weak` et une fermeture `weak`, vidée à l'arrêt. `Recorder.handler` n'existe que pendant la capture.
- **Petites rétentions annexes**
  - `MacroProgram.docCache` (`MacroValidation.swift:284`) garde jusqu'à 64 anciennes révisions de programmes (borné, mais inutile : `MacroLibraryStore.programCache` fait déjà le même travail).
  - `previousContent` garde tout le fichier lu au lancement jusqu'à la première écriture (`MacroLibraryStore.swift:150`).
  - Le gestionnaire d'annulation n'a pas de `levelsOfUndo`, donc une copie complète du brouillon par étape, sans limite.
  - Tout cela est petit, ce n'est pas la cause des 23 Mo.
- **Correctif qui garantit la libération**
  - Posséder la fenêtre côté AppKit : un `MacroCreatorWindowController` (NSObject + `NSWindowDelegate`) crée à la demande un `NSWindow` + `NSHostingController(rootView: MacroCreatorView().environmentObject(Store.shared))`.
  - Dans `windowWillClose` : `model.close()`, `window.contentViewController = nil`, puis lâcher la référence. Remplacer `openWindow(id:)` par `controller.show(id)`.
  - Variante moins coûteuse : garder la scène mais conditionner le contenu par un `@State alive`, basculé par `NSWindow.willCloseNotification`, pour détruire au moins la liste, le formulaire et la barre d'outils.
  - Dans tous les cas, mettre un `deinit` (journal en DEBUG) sur `MacroEditorModel`, et vérifier avec `heap`/`leaks` ou le Memory Graph. Corriger aussi le commentaire et `MACROS.md`.
- **Coût d'ouverture (+23 Mo pour une cible de +15)** : rien dans le code ne l'explique. Les copies superflues (catalogue reconstruit, voir I5) sont de l'ordre du Ko.
  - Il s'agit sans doute du coût d'une grande fenêtre. Les candidats que je vois, tous à confirmer par `vmmap -summary` ou `footprint --categories` avant et après ouverture :
    - `windowGlass` : matériau sur toute la fenêtre de 1100×700, soit 2200×1400×4 octets ≈ 12 Mo de surface si elle est translucide ;
    - `NavigationSplitView` (3 colonnes) + 2 `List` (NSTableView) + 1 `Form` groupé + `safeAreaBar`/`glassSurface` du bandeau ;
    - taille par défaut de 1100×700.
  - Pistes : comparer la ligne « sans-verre » de la mesure, désactiver le matériau de fenêtre pour cet outil dense, remplacer `NavigationSplitView` par un simple `HStack`/`HSplitView` (palette fixe de 230 pt), réduire la taille par défaut.

**I2. La fermeture repose sur `onDisappear` seul, et le créateur peut garder des services actifs.**
- `MacroEditorView.swift:77` appelle `model.close()` uniquement dans `onDisappear`.
  - Sur une scène `Window` masquée mais vivante, ce rappel n'est pas garanti sous macOS 13.
  - S'il ne part pas, `editorNeeds` reste non vide : `TrackMemory` garde un moniteur global de clics et, en mode léger, les ports MIDI à la demande existent. C'est contraire à « rien ne tourne au repos ».
  - Pas de `deinit` non plus sur `MacroEditorModel` pour remettre `setEditorNeeds([])`.
- **Correctif** : brancher `close()` aussi sur `NSWindow.willCloseNotification`. `WindowFinder` fournit déjà la fenêtre. Rendre `close()` idempotent et l'appeler aussi depuis `deinit`.
- **`ClickTeacher`** (`MacroInspector.swift:633-736`)
  - `close()` ne l'annule pas : si la fenêtre se ferme pendant « Montrer dans FL… », le minuteur de 50 ms et `ClickRecorder` tournent jusqu'à 30 s.
  - Le clic retenu modifierait alors le brouillon d'une fenêtre fermée, donc écrirait dans la bibliothèque. Appeler `ClickTeacher.shared.cancel(nil)` dans `close()`.
- **Ports MIDI** (`MIDILink.setOnDemand`, `MIDILink.swift:476`) : une fois créés, ils ne sont jamais détruits. Les annoncer dès l'ouverture du créateur (`needs` d'une macro qui contient `armon` ou `recon`) les laisse en place jusqu'à la fermeture de l'app. Il vaudrait mieux les demander au moment de « Tester ».

**I3. Les erreurs de la bibliothèque ne sont montrées nulle part : perte silencieuse possible.**
- `MacroLibraryStore.saveError` n'est lu par aucune vue. `MenuContent.alerts` (`FLShortcutApp.swift:463-464`) ne lit que `store.loadWarning` et `store.saveError`, qui sont ceux du profil.
- `MacroLibraryStore.loadWarning` n'apparaît que dans la branche « bibliothèque non vide » de `MacroLibraryPage` (`MacroLibraryView.swift:22-51`).
- Dans le cas le plus grave (fichier illisible ou trop gros, donc « repart vide », ou `writesDisabled`), la page est vide et le message est invisible.
  - Dans le cas `writesDisabled`, `scheduleSave` renvoie silencieusement (`:297`). L'utilisateur construit des macros qui disparaissent à la fermeture, sans le moindre avertissement.
  - Dans le cas « illisible », il ne sait pas qu'une copie datée a été gardée.
- **Correctif**
  - Afficher `loadWarning` aussi dans l'état vide.
  - Ajouter les deux messages de la bibliothèque aux alertes du menu.
  - Montrer un bandeau dans le créateur quand `writesDisabled` ou `saveError` est actif.
  - Si la copie de secours échoue (`try?` en `:178`, `:182`, `:187`), désactiver les écritures au lieu d'écraser le fichier.

**I4. « Personnaliser » peut remplacer un raccourci qui marche par une macro invalide.**
- `EditorView.swift:1054` `customizeTemplate()` transforme le modèle en blocs et met `macro = nil`, `macroRef = doc.id` sans vérifier que la copie est valide.
- Les macros de la bibliothèque sont validées en mode strict (`MacroRegistry.swift:468-474` : dossier personnel, extension `.fst`). Le modèle livré, lui, accepte un preset sur un autre disque (le commentaire de `ValidationContext` le dit).
- Un utilisateur dont le preset est sur un volume externe voit donc son raccourci bloqué (« preset .fst attendu dans ton dossier personnel ») juste après avoir confirmé la personnalisation.
- **Correctif**
  - Compiler le `MacroDoc` avant de remplacer le raccourci. Si `problem != nil`, ne pas basculer et expliquer, ou garder le modèle.
  - Ou assouplir la règle stricte pour les macros issues de la personnalisation.
  - Ajouter un test.

**I5. Fluidité : tout le créateur observe le modèle entier, et le menu « Ajouter » reconstruit le catalogue à chaque évaluation.**
- `MacroPaletteView` (`MacroPalette.swift:22`), `AddBlockMenu`, `MacroHeader`, `MacroInspectorView` et `MacroStepsPane` portent chacun `@ObservedObject var model`.
  - Un changement de sélection, une frappe dans l'inspecteur ou une notification redessine donc la palette, l'en-tête et le menu.
  - Les lignes `Equatable` limitent le coût de la liste, mais pas celui des autres vues.
- `AddBlockMenu` (`MacroEditorView.swift:289`) appelle `PaletteCatalog.items(layout: SystemKeyboardLayout())` dans la fermeture du `Menu`, dans un `ForEach` sur 5 catégories.
  - Cela donne 5 constructions de ~22 `PaletteItem` à chaque évaluation, chacune avec 2 recherches de disposition TIS (`AppMode.nativeEquivalent`).
  - Les éléments sont déjà calculés une fois dans `paletteItems`, et `store.layout` existe : utiliser ces deux-là.
- **Correctif**
  - Donner à la palette et au menu une fermeture `insert` et le tableau d'éléments au lieu de l'objet observé.
  - Séparer la sélection, l'essai et le brouillon en objets distincts si nécessaire.
- `MacroCreatorView` observe aussi tout `Store` via `@EnvironmentObject` sans en avoir besoin.

**I6. L'import ne tient pas toute la promesse « relue » ; le champ `import_` du registre est du code mort.**
- La relecture n'affiche que 30 lignes sur un maximum de 200 blocs (`MacroLibraryView.swift:330-335`).
  - Les avertissements sont calculés sur tout l'arbre, mais les marques « touche avec ⌘ » et « clic dans FL » ne sont visibles que pour les 30 premières lignes.
  - Afficher la liste complète défilable, ou au moins un décompte global des blocs sensibles.
- `PolitiqueImport` (`MacroRegistry.swift:67`) est déclaré par chaque `BlockSpec` mais n'est lu nulle part.
  - Le retrait des positions se fait seulement à l'export (`MacroExchange.sharable`).
  - Un fichier fabriqué à la main peut donc arriver avec des clics déjà visés (`flWindow`, `openMenu`) et un bloc `menuAX` caché.
  - Ces clics restent confinés à FL par la couche d'effets, donc pas un contournement, mais ils ne sont pas « à montrer » comme annoncé dans l'architecture (§2.4).
  - Appliquer `sharable()` aussi à l'import, c'est-à-dire forcer `.toLearn` (il est garanti de bloquer la macro tant que l'utilisateur n'a pas montré l'endroit), ou supprimer `import_`.

**I7. Les tests ne couvrent pas la partie la plus risquée.**
- Aucun test pour :
  - `MacroEditorModel` : annulation et regroupement, `markDirty`/`saveNow`, sélection après suppression, `setTrigger`, `programForTest`, et surtout `close()` qui remet `editorNeeds` à zéro ;
  - `MacroRunMonitor` : borne de 200, garde `running` ;
  - `Remap.title`/`remapTitle` pour `macroRef` ;
  - une validation d'import avec `menuAX` ou des positions pré-apprises.
- `MacroEditorModel` est testable : `Store(pushToTap: false, library: mémoire)`.
- Ajouter un test d'adéquation inspecteur/registre : pour chaque bloc de la palette, chaque `ParamSpec` modifiable doit avoir un contrôle. Le `default:` de `BlockInspector.control` (« Réglage disponible dans une prochaine version ») masque aujourd'hui toute dérive.

### Minor (Nice to Have)

- **Blocs désactivés encore validés** (`MacroValidation.swift:59-71`). `check` ne saute pas les blocs désactivés alors que l'interpréteur les saute (`MacroInterpreter.swift:175`). Un clic « à apprendre » décoché bloque donc quand même la macro, ce qui n'est pas ce que « sauter sans supprimer » laisse attendre. C'est fail-closed donc sûr, mais à décider explicitement.
- **Nom vidé** (`MacroEditorModel.swift:188-191`). Un nom vide est enregistré après 0,5 s, la macro devient invalide et le raccourci est bloqué un instant. Garder l'ancien nom tant que le champ est vide ou enregistrer « Macro sans nom ».
- **Titres incohérents d'une macro de la bibliothèque** :
  - `Catalog.swift:511` (`remapTitle`) affiche « Macro : à configurer » pour un `macroRef` dans les messages de conflit de touche ;
  - renommer une macro dans le créateur ne rafraîchit pas les titres des listes de Raccourcis, car `Remap.title` lit `MacroLibraryStore.shared` sans abonnement.
- **Choix d'une macro dans la fiche d'un raccourci absent.** L'architecture (§2.11, §3) prévoit « Enregistrement rapide / une macro de la bibliothèque / Nouvelle… ». La fiche n'offre que « Personnaliser » et « Ouvrir dans le créateur » ; pour relier une macro existante à un raccourci, il faut passer par l'en-tête du créateur.
- **Copies de secours cumulatives** (`MacroLibraryStore.swift:178-187` et `FileMacroLibraryStorage.backup`). `plus-recente`, `partielle` et `illisible` créent un nouveau fichier daté (jusqu'à 8 Mo) à chaque lancement tant que le fichier n'est pas réécrit. Plafonner à quelques copies, ou ne pas copier un contenu identique.
- **Divers dans le même ordre**
  - `docCache` redondant avec `programCache`.
  - `MacroLibraryPage.row` relit `MacroSpots.loadPath(.input)` à chaque ligne (`MacroLibraryView.swift:108`).
  - Les badges de la bibliothèque sont des tuples avec comparaison par chaîne (`$0.0 == "Désactivée"`) au lieu de l'énumération `MacroBadge` existante.
  - Valeurs magiques d'actions (3, 33, 39, 40) dans `MacroPalette.swift` et `MacroInspector.setAction`.
  - Étiquettes de `Picker` en chaînes (`enterTag`, `targetKind`).
  - `stripPath` dépend du texte « Étape n : ».
  - Le choix « Apprise au premier passage » ne peut plus être rétabli une fois quitté.
- **`MacroRunMonitor.refuse` (`:96`)** utilise `.cancelled`, donc « Essai arrêté : Ouvre FL Studio… » alors que rien n'a démarré.
- **`handle(request)`** (`MacroEditorView.swift:82`) n'est pas idempotent : un `onAppear` répété recharge la macro et perd l'annulation et la sélection. Mémoriser le dernier `serial` traité.
- **Restauration de fenêtre.** Pour que le créateur ne se rouvre pas tout seul au lancement sur la première macro, désactiver la restauration : `window.isRestorable = false` dans `WindowFinder`.
- **`flPIDs.first`** (`MacroEditorModel.swift:340`) est arbitraire si plusieurs FL tournent.
- **Code de mesure en production.** `sampleForCapture`, `showSample` et le déclencheur de débogage restent compilés, sans effet sans le drapeau de débogage.
- **Modèles livrés non vérifiés.** Ils s'appuient sur des raccourcis FL que je n'ai pas pu confirmer : ⌘N « Save new version » et ⌘R « Export WAV ».
- **Documentation périmée.** `MACROS.md` garde « Bornes : 40 étapes, 180 s » (le nouveau moteur est à 200 blocs et 300 s) et la liste « Fichiers » (MacroRunner est désormais découpé).

## Declined to judge

- Mixer 94 Mo et recherche 224 Mo (192 déjà avant l'incrément) : probablement le `Form` groupé non paresseux, hors périmètre, non vérifié.
- Parité Windows, extension du protocole MIDI et conditions « Si / Tant que / Attendre que » grisées « bientôt », pas à pas, Échap par le tap, enregistreur : incréments 3 à 5, explicitement hors de celui-ci.
- `--doc-blocs` et test de MACROS.md contre le registre, nettoyage du code mort, suppression de `quickRecordSteps`/`MacroLearner`, UTType à double-clic : incrément 6.
- Comportement réel des modèles contre un vrai FL et du bloc `hoverOutside` ajouté à « Attendre un menu » : seulement raisonné. Je confirme seulement que le modèle « Enregistrement rapide » n'utilise pas ce bloc (il passe par `trackMenu`).
- Rendu visuel et Liquid Glass, qualité de la langue française de l'interface : survolés, pas jugés.
- Fiabilité de l'essai CI (`continue-on-error: true`, durée et capture d'écran) : je l'ai pris tel que décrit comme vert.
- Les 206 tests verts et le comportement exact de `Window` sous macOS 13, 14, 15 et 26 : donnés, non reproduits. Le diagnostic I1/I2 est une inférence à valider (voir recommandation 1).

## Recommendations

1. Prouver d'abord la cause de la non-libération : `deinit` journalisé sur `MacroEditorModel`, puis `vmmap -summary` ou `footprint` avant/après ouverture et après fermeture, en mode verre et sans verre. Cela départage « scène retenue » de « surface de fenêtre ».
2. Passer à un contrôleur de fenêtre AppKit (I1) : c'est le seul moyen déterministe d'atteindre « < +2 Mo fermé ». Brancher `close()` sur `willClose` (I2).
3. Rendre visibles les erreurs de la bibliothèque (I3) avant tout test utilisateur : c'est le seul chemin de perte de données silencieuse.
4. Garder la même architecture pour les chiffres de mémoire : ajouter à la mesure une ligne « créateur refermé deux fois de suite », pour vérifier qu'il n'y a pas d'accumulation.

## Assessment

**Ready to merge?** With fixes

**Reasoning:** La conception est solide (bibliothèque durcie, compatibilité ascendante testée, garde-fous restés dans la couche d'effets, lignes `Equatable`), et je n'ai trouvé ni faille de sécurité ni cycle de rétention. Les cibles de mémoire à la fermeture ne sont pas tenues et la fermeture repose sur un rappel non garanti. Les erreurs de la bibliothèque sont invisibles et « Personnaliser » peut casser un raccourci qui marche : I1 à I4 sont à corriger avant de livrer.

Fichiers principaux concernés (chemins absolus) :
- /home/user/fl-shortcut/Sources/FLShortcut/FLShortcutApp.swift
- /home/user/fl-shortcut/Sources/FLShortcut/MacroEditorView.swift
- /home/user/fl-shortcut/Sources/FLShortcut/MacroEditorModel.swift
- /home/user/fl-shortcut/Sources/FLShortcut/MacroInspector.swift
- /home/user/fl-shortcut/Sources/FLShortcut/MacroPalette.swift
- /home/user/fl-shortcut/Sources/FLShortcut/MacroLibraryStore.swift
- /home/user/fl-shortcut/Sources/FLShortcut/MacroLibraryView.swift
- /home/user/fl-shortcut/Sources/FLShortcut/MacroExchange.swift
- /home/user/fl-shortcut/Sources/FLShortcut/MacroRegistry.swift
- /home/user/fl-shortcut/Sources/FLShortcut/MacroValidation.swift
- /home/user/fl-shortcut/Sources/FLShortcut/EditorView.swift
- /home/user/fl-shortcut/Sources/FLShortcut/Catalog.swift
- /home/user/fl-shortcut/MACROS.md
