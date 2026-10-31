# Macros FL Shortcuts (sans MIDI)

## Pourquoi pas de MIDI, pas d'UDP
- Le lien MIDI (script Python dans FL) est resté en option, désactivé par défaut. Le **mode léger** n'installe rien dans FL : l'app envoie des touches d'origine de FL, seulement quand FL est au premier plan.
- Les macros prolongent ce mode : mêmes garde-fous, aucune dépendance au script FL.
- Un lien UDP local n'a pas été retenu : FL ne charge un script de contrôleur que s'il est rattaché à un port MIDI activé, le script ne peut lire un socket que depuis `OnIdle` (~20 ms), et il faudrait refaire toute l'authentification déjà présente dans le protocole HMAC.

## Ce que fait une macro
Une macro est une liste de blocs (`MacroModel.swift`, registre `MacroRegistry.swift`) jouée par l'interpréteur (`MacroInterpreter.swift`) sur sa propre file, jamais dans le thread du tap clavier ; le programme est développé et validé sur le thread principal (`MacroValidation.swift`), les effets macOS sont dans `MacroEffectsMac.swift` et `MacroFLBlocks.swift`. Le modèle « Enregistrement rapide » est développé en blocs (`MacroTemplates.swift`) ; les anciennes étapes ci-dessous (`Macro.swift`) restent lues et sont reprises bloc par bloc, avec leurs bornes d'origine.

| Étape | Effet |
|---|---|
| `key` | une touche ou combinaison envoyée à FL (liste noire ⌘Q, ⌘W… revérifiée) |
| `delay` | pause (≤ 5 s), interrompue par Échap |
| `click` | clic gauche/droit à un point appris (repère : curseur, fenêtre FL, ou x du curseur + y de la fenêtre) ; le point doit tomber dans une fenêtre de FL |
| `menu` | choix dans un menu par ses titres (Accessibilité) ; sinon clics de secours appris |
| `waitDialog` / `waitDialogClose` | attend l'ouverture / la fermeture d'une boîte de dialogue de FL (nombre de fenêtres de FL au niveau 0 à 8) |
| `dropFile` | **preset fixe** : le fichier .fst est glissé sur la dernière piste cliquée, comme depuis le Finder (`PresetDrop.swift`) — essai de l'utilisateur sur son FL : déposé sur la tranche, l'état charge sur CETTE piste (un double-clic dans le Finder le charge sur le Master). Une petite fenêtre transparente de l'app reçoit un appui synthétique sous le point de la piste, démarre une vraie session de glisser et disparaît ; quelques déplacements puis le relâchement déposent le fichier. FL dit s'il l'a pris (refus → échec expliqué). Ni menu ni boîte « Open ». Essai sur la CI : passages 1 et 2 de `--selftest-macro` |
| `chooseFile` | **preset choisi à chaque fois** (ou chemin d'origine) : dans la boîte « Open » native (`PresetChooser.swift`) : ⌘⇧G renvoyé jusqu’à l’apparition de « Aller au dossier », chemin tapé caractère par caractère (un ⌘V synthétique est ignoré par macOS 26), Entrée quand la feuille est prête, Entrée jusqu’à la fermeture de la boîte. Essai réel sur la CI : `FLShortcut --selftest-preset` |

Bornes (`MacroLibrary.validate`) : 40 étapes, 180 s au total, chemins sans caractères de contrôle. Une macro `custom` (étapes libres) ne s'écrit qu'à la main dans le profil JSON et est **refusée à l'import**.

## Créer ses propres macros (créateur de macros)
Fenêtre *Raccourcis › Macros* : la bibliothèque des macros en blocs (nom, raccourci, badges « Lien FL », « À apprendre », « Désactivée », « À corriger »), avec **Nouvelle macro**, **Modèles…** et **Importer…**. Chaque macro s'ouvre dans le **créateur**, DANS la même fenêtre, comme un dossier dans le Finder : la flèche ← en haut à gauche (⌘[) ramène aux raccourcis et aux macros, et la flèche → (⌘]) y fait revenir dans la dernière macro quittée, comme Avancer dans le Finder. Au retour : macro neuve → « Enregistrer » ou « Supprimer » (vide : supprimée sans question) ; macro modifiée → « Enregistrer » ou « Annuler les modifications » (elle revient telle qu'à l'ouverture) ; sinon retour direct. Tant que le créateur est affiché, la fenêtre reste devant FL (sauf pendant « Montrer dans FL… », « Enregistrer clics et touches », un essai ou une macro) ; au retour, son modèle est libéré : rien ne reste en mémoire ni ne tourne. **Partager** : « Exporter… » (page Macros : toutes les macros, un fichier .flsmacro chacune ; clic droit ou créateur : une seule) et « Importer… » (plusieurs fichiers d'un coup, chacun relu) s'ouvrent dans *Documents › FL Shortcuts › Macros* ; les raccourcis (menu ⋯ › Exporter… / Importer…) dans *Documents › FL Shortcuts › Raccourcis*:

- **à gauche, la palette** par catégorie ; un clic ajoute le bloc sous la ligne choisie, ou dans une boucle si sa ligne « Fin de la boucle » est choisie ; on peut aussi le prendre et le glisser à sa place dans la liste. Au survol, un bloc se soulève un peu ; appuyé, il flotte ; pendant le glisser, il suit la souris en flottant (comme les lignes des raccourcis et des macros au survol). Colonnes souples : quand la fenêtre se resserre, la liste puis l'inspecteur rétrécissent, rien n'est coupé ;
- **au centre, la liste** des étapes, à plat avec un retrait selon l'imbrication : une phrase en français par ligne (« Appuyer sur ⌘S », « Attendre une boîte de dialogue · 4 s au plus »), une case pour sauter un bloc sans le supprimer, des badges (pause fixe, lien FL, à apprendre, à corriger, continue si échec). Glisser pour ranger, ⌘D duplique, ⌫ supprime, ⌘Z annule ;
- **à droite, l'inspecteur** du bloc choisi, construit à partir de ses réglages (registre) : touche capturée comme un raccourci, nombres bornés, preset .fst, action de FL du catalogue (avec sa touche de secours), endroit d'un clic montré dans FL (« Montrer dans FL… »), « Si le bloc échoue : Arrêter / Continuer », note ;
- **en haut**, le nom, l'état (« Prête · 5 blocs · 3 s au plus » ou ce qui bloque) et le **raccourci**, avec les avertissements de conflit habituels ;
- **Enregistrer clics et touches** (barre sous la liste) : FL passe devant, on clique et on tape une suite dans FL (menus, *Options › Audio settings*, boutons des fenêtres de réglages, flèches, Entrée, Échap, raccourcis…), puis **Terminer** dans le petit panneau « ● Enregistrement » (en haut à droite, déplaçable, ne prend jamais le premier plan à FL ; **Annuler** n'ajoute rien). Chaque clic et chaque touche devient un bloc, ajouté dans l'ordre sous la ligne choisie (⌘Z annule tout d'un coup) : clic dans une fenêtre de FL → relatif à son coin le plus proche, taille retenue ; clic dans un menu de FL → relatif à ce menu ; élément d'un menu de FL dans la barre des menus de macOS → bloc « Menu de FL » par ses titres. Touche dans un menu de FL ouvert : ↑ ↓ ← → Entrée Échap → « Dans le menu », lettre → « Lettres d'un menu » ; ailleurs → « Touche » (raccourci compris) ; la même touche répétée d'affilée → « × n ». Les clics et touches hors de FL, et le clic qui referme un menu de la barre sans choix, sont ignorés (le nombre est indiqué). Pendant l'enregistrement seulement, et seulement quand FL est devant : moniteur des clics et des touches, relevé des fenêtres de FL toutes les 50 ms, Accessibilité au moment d'un clic hors des fenêtres de FL ou dans un menu ; 120 s et 80 clics ou touches au plus ; rien n'est lu à l'écran, clics et touches restent en mémoire et ne sont jamais journalisés ;
- **Essayer une macro** : avec son raccourci, dans FL (le bouton ▶ Tester a été retiré de la barre, à la demande de l'utilisateur). Échap arrête. Ports MIDI à la demande (mode léger) : demandés seulement au premier usage, jamais à l'ouverture du créateur (une fois créés, ils restent jusqu'à la fermeture de l'app, sans aucun trafic).

Le brouillon est enregistré par **Enregistrer** (⌘S) ou 0,5 s après la dernière modification (jamais à chaque frappe). *Personnaliser dans le créateur…* (fiche d'un raccourci « Enregistrement rapide ») développe le modèle en blocs avec ses réglages, et le raccourci lance ensuite cette version.

| Bloc de la palette | Effet |
|---|---|
| Touche ou raccourci | une touche ou un raccourci envoyé à FL (⌘A, ⇧⌘S, F9…), N fois : taper le raccourci dans le champ, ou cocher ⌘ ⌥ ⌃ ⇧. Raccourcis dangereux refusés selon la disposition du clavier (en AZERTY ⌘Q est la touche Q, ⌘A est permis), revérifiés juste avant l'envoi |
| Touche de menu | ↑ ↓ ← → Entrée Échap, seulement dans un menu ouvert par la macro |
| Clic à un endroit appris | clic gauche ou droit (réglage « Bouton »), ailleurs aussi possible : sur la piste visée (clic droit : ouvre son menu, remplace l'ancien bloc « Clic droit sur la piste »), près du clic précédent, près du curseur. Endroit montré une fois dans FL (« Montrer dans FL… » ou « Enregistrer clics et touches ») : relatif à la fenêtre de FL où il tombe — fenêtre principale, fenêtre détachée, réglages comme *Options › Audio*, boîte de dialogue (niveaux 0 à 8), taille retenue — ou au menu de FL ouvert. Au rejeu, le clic attend que cette fenêtre (3 s au plus) ou ce menu (1,5 s) s'ouvre si le clic précédent vient de l'ouvrir, puis qu'elle ne bouge plus ; rien n'est attendu s'il est déjà là. Tant qu'il n'est pas montré, la macro est bloquée |
| Glisser-déposer | reste cliqué à un endroit de FL (un son du Browser, un clip, un plugin…), glisse jusqu'à un autre endroit de FL et lâche. Les deux bouts se montrent en faisant le geste une fois dans FL (« Montrer dans FL… » : l'appui puis le relâché), retenus comme des clics appris par rapport aux fenêtres de FL d'avant l'appui ; jamais dans un menu. Au rejeu : les deux endroits dans FL et rien ne les couvre, puis appui, une vingtaine de pas, relâché (toujours, même après Échap), par le flux du système. Retirés à l'export, à remontrer à l'import |
| Menu de FL | élément des menus de FL dans la barre des menus de macOS (FL 2024.2 et plus), par ses titres (*File › Export › …*). Dans le créateur, les menus de FL se parcourent comme dans FL : un menu de la barre, puis ce qu'il contient, sous-menu après sous-menu (4 niveaux au plus sous la barre), jusqu'à l'élément choisi ; FL doit être ouvert, chaque niveau est lu à la demande (Accessibilité, sans clic) et rien ne s'ouvre dans FL pendant qu'on parcourt ses menus ; un menu que FL ne remplit qu'à l'ouverture montre « Lire ce menu dans FL » (il s'ouvre alors un instant, puis se referme). Dans la palette (FL Studio), ajouté vide : à choisir. Créé aussi par « Enregistrer clics et touches ». Au rejeu : choisi par l'Accessibilité (AXPress), sans clic ni menu à l'écran ; un menu que FL ne remplit qu'à l'ouverture est ouvert puis relu toutes les 100 ms, 1 s au plus ; un chemin introuvable est aussi cherché sans le titre de son sous-menu (FL met ses macros à plat dans *Tools* de la barre de macOS). Journal : « menuBar », jamais les titres |
| Attendre | un seul bloc pour toutes les attentes, réglé dans l'inspecteur : qu'une boîte de FL s'ouvre, qu'elle se ferme, qu'un menu de FL s'ouvre ou se ferme (120 s au plus ; le pointeur est écarté d'un menu qui s'ouvre), ou un temps fixe (≤ 5 s, badge « pause fixe » : à éviter). Les clics appris attendent déjà leur fenêtre tout seuls |
| Menu de la piste | clic droit sur la piste puis l'élément choisi dans une liste : ouvrir un état de piste, enregistrer l'état, renommer, créer sa piste audio ; « Autre » pour taper 1 à 3 lettres soulignées |
| Ouvrir un preset | (ancien « Déposer un preset sur la piste ») glisse le fichier .fst choisi sur la dernière piste cliquée (dossier personnel) |
| Ouvrir un preset (boîte Open) | quand FL a ouvert sa boîte « Open » (preset d'un plugin, d'un canal…) : le fichier .fst choisi (dossier personnel) |
| Action de FL | une action de FL Shortcuts par le lien avec FL, sinon sa touche de FL ; *Mute* et *Solo de la piste* (sans le lien : un clic sur son bouton, montré une fois) |
| Nom et couleur | nom et/ou couleur de l'élément sélectionné dans la page de FL qui est devant : piste du Mixer, canal du Channel rack, piste de la Playlist. Un seul élément sélectionné, sinon la macro s'arrête (« Sélectionne une seule piste ou un seul canal »). Couleur : code « # », ou « Choisir… » qui ouvre la fenêtre de couleur de FL recopiée (roue à 16 secteurs et 5 anneaux, luminosité, cases 0 à 9 = les 10 dernières couleurs, #RRGGBB, teinte / saturation / luminance à l'échelle de FL et rouge / vert / bleu, Reset et Accept). Demande le lien avec FL (script v4 : redémarre FL après la mise à jour) |
| Carte son branchée | la carte son branchée (USB, Thunderbolt…) devient la sortie et l'entrée du Mac (comme dans Réglages Système › Son). FL la suit tout seul s'il est réglé une fois sur « Default audio device » (Output) et « Default input device » (Input) dans *Options › Audio settings* : vérifié sur le FL de l'utilisateur (la ligne Status passe de 1x2 à 2x2 sorties). Plusieurs cartes : celle choisie la dernière fois. Aucun clic dans FL ; macOS n'est interrogé qu'au moment du bloc |
| Répéter | N fois (50 au plus), blocs à l'intérieur |

Palette triée avec l'utilisateur : *Lettres d'un menu de FL* (fait par *Menu de la piste*), *Arrêter la macro* (inutile sans condition), *Commentaire* (doublon de la note de chaque bloc), *Tant que* et *Attendre que* ne sont plus proposés. Les anciennes macros qui les contiennent marchent toujours. *Si…* reste « bientôt » (à refaire simple : « sinon » caché, conditions en phrases).

*Si…* est affiché grisé (*Tant que* et *Attendre que* ne sont plus proposés) (« bientôt ») : l'interpréteur sait les jouer, leurs conditions se régleront dans le créateur à l'incrément suivant.

**Stockage** : `~/Library/Application Support/FL Shortcuts/macros.json` (0600, écriture atomique, copie `macros.precedente.json` une fois par lancement ; fichier illisible, plus récent ou en partie illisible : copie datée gardée). Le raccourci ne garde qu'une référence (`"macroRef"`), doublée d'un lien caché `"unknownAction": "macroRef:<uuid>"` que les anciennes versions conservent : en revenant à cette version, la macro est retrouvée. La désinstallation supprime tout le dossier.

**Partage** : *Exporter…* écrit un fichier `.flsmacro` (JSON lisible) :

```json
{ "format": "flsmacro", "version": 1, "exportedBy": "FL Shortcuts 1.2 (macOS)",
  "macro": { "name": "Armer la piste et lancer le REC",
             "blocks": [ { "type": "click", "id": "…", "target": { "anchor": "toLearn" }, "button": "right" } ] } }
```

Les endroits appris sont retirés (à montrer sur chaque Mac), le chemin d'un preset est écrit relatif au dossier personnel (`~/…`). *Importer…* relit le fichier bloc par bloc en français, liste complète qui défile, avec le nombre de blocs à relire en tête (touches avec ⌘, clics, fichiers, lien FL et blocs cachés de l'ancien format signalés) : 256 Ko, 200 blocs et 4 niveaux au plus, ids régénérés, **chaque clic est à montrer de nouveau** (aucune position reprise d'un fichier, même écrit à la main), la macro arrive **sans raccourci**. Bibliothèque illisible ou impossible à enregistrer : le message reste affiché dans le menu, la page Macros (même vide) et le créateur ; si la copie de secours échoue, le fichier n'est plus jamais réécrit pendant ce lancement.

## Enregistrement rapide automatique (modèle livré, rien à régler)
Modèle `autoRecord`, sur ⌃R dans le profil Recommandé. Il suffit de cliquer sur une piste du Mixer puis de taper le raccourci. **Aucune lecture de l'écran** : seule la permission du clavier (Accessibilité) est utilisée.

| Étape | Effet |
|---|---|
| `trackMenu` | clic droit sur la **dernière piste cliquée** dans FL (`TrackMemory.swift`), puis l'élément choisi dans la liste (par défaut « File › Open mixer track state ») **au clavier** : les éléments des menus de FL ont une lettre soulignée (F de File, O de Open). La macro attend que le menu apparaisse (nouvelle fenêtre de FL), écarte le pointeur du menu, tape F (flèche droite si le sous-menu ne s'ouvre pas), puis O (Entrée si les menus restent ouverts ; retenu, Entrée part ensuite aussitôt). Après un passage réussi, la rangée des noms du Mixer et la hauteur du menu sont retenues : clic droit toujours sur cette rangée, refus si le dernier clic en est loin (Playlist : un clic droit y supprime un clip) ou si un autre menu s'ouvre. Rien à apprendre |
| `waitDialog` / `waitDialogClose` | attend la boîte « Ouvrir » puis le choix du preset (ou tape le chemin d'un preset fixe) |
| `armTrack` | action 39 `armon` du script FL : arme la piste sélectionnée **seulement si** elle ne l'est pas. Sans lien MIDI : rien (choisir l'entrée arme la piste dans FL) |
| `recordOn` | action 40 `recon` du script FL : allume le REC **seulement s'il** est éteint |
| `selectInput` | « (none) » puis l'entrée « 1 » : appris la première fois (place relative au coin haut-droit de la fenêtre de FL, retenue avec sa taille ; taille différente → redemandé, jamais de clic à côté) |
| `soundCard` | CoreAudio : cartes branchées en USB, Thunderbolt, FireWire, PCI ou AVB avec une sortie (de préférence aussi une entrée), celle de la dernière fois d'abord (`soundCard.lastUID`) ; `kAudioHardwarePropertyDefaultOutputDevice` puis `DefaultInputDevice`. Aucun écouteur permanent : rien ne tourne au repos |
| `nameColor` | commande avec données du lien (PROTOCOL.md §7, opération 1) : le script repère la page devant (`ui.getFocused`) et l'unique élément sélectionné (`isTrackSelected`, `isChannelSelected`, Playlist dès l'API 12), puis `setTrackName`/`setChannelName` et `…Color` (`utils.RGBToColor`). Refus expliqué (CC 116) : page, rien ou plusieurs sélectionnés, données. Journal : `nameColor`, jamais le nom. Icône (`"icon":"c-r"`, colonne et rangée de la grille de FL) : posée après le nom et la couleur par la fenêtre de FL (`MacroIconPlacement.swift`) : F2, clic sur le bouton de l'icône de la fenêtre du nom (montré une fois, gardé par rapport à son coin haut-droit : `macroSpots.v2.iconButton`), clic au centre de la case de la grille, Entrée ; jamais avec un dégradé |
| `organize` | ouvre l'Organiser (`OrganizerWindow.swift`) et se termine aussitôt. Lien avec FL installé à la demande (écran d'installation s'il manque ; ports MIDI créés à l'ouverture en mode léger) ; la page devant est demandée à FL (opération 9, PROTOCOL.md §8). Écoute de chaque canal seul (opération 6 ; layers et automations sautés) par la capture du seul processus de FL (macOS 14.2+, FL muet pendant l'écoute), notes d'essai C3 puis C5 si le canal se tait ; Playlist : chaque piste seule (opération 11 ; les pistes sélectionnées, sinon jusqu'à la dernière renommée et 32 de plus, arrêt après 3 muettes de suite), chanson parcourue toutes les 4 mesures (opération 12) jusqu'à ce qu'elle sonne. Puis opération 7 (FL remis comme avant, aussi après Échap ou une erreur). Classement : mesures Accelerate + IA de macOS (SoundAnalysis, sur le Mac), familles dans l'ordre Voix, Mélodies, Basse, Drums, FX (les absentes sautées). Aperçu par famille, une couleur ou un dégradé chacune (préférence `organize.families`) ; Channel rack : couleurs (opération 4) puis regroupement par ⌥↑ envoyé à FL seul ; Mixer : couleurs des pistes reliées (famille majoritaire, Master jamais touché) ; Playlist : couleurs, et pistes au nom de FL renommées (opération 10 : Kick, Snare, Hi-hat, Clap… pour les drums, sinon Voix, Mélodie, Basse, FX ; numérotées). Ni ordre ni icône dans la Playlist (l'API de FL ne le permet pas). Vérifié par une nouvelle liste ; « Revenir comme avant ». Journal : `organize`, jamais un nom |
| `feedbackCheck` | **en dernier** : micro **et** haut-parleurs de l'ordinateur en service → fenêtre « risque de larsen » (tout est déjà en place, il ne reste qu'à changer d'entrée ou de sortie). Vérifié en parallèle dès le début de la macro : aucune attente |

**Lien MIDI à la demande** : en mode léger, les ports « FL Shortcuts » existent (FL les voit) mais rien n'y circule. Le script FL démarre **endormi** : `OnIdle` et `OnRefresh` s'arrêtent à leur première ligne. La macro le réveille brièvement (PING = 2), envoie l'action signée, et le script se rendort tout seul 8 s après (PROTOCOL.md §4). À régler une fois dans FL : *Options › MIDI Settings*, Input « FL Shortcuts » : Enable, Controller type « FL Shortcuts » ; Output « FL Shortcuts » : même port.

## Enregistrement rapide à positions apprises (ancien modèle)
Modèle `quickRecord` : voir README. Réglages d'un raccourci : preset (demander à chaque fois, ou fichier .fst fixe), armer + entrée 1, REC à la fin, positions apprises (menu de la piste, armement / entrée).

Format dans un profil :

```json
{"kind":"macro","trigger":{"keyCode":15,"control":true},
 "macro":{"template":"quickRecord","name":"Enregistrement rapide",
          "presetPath":"/Users/moi/Documents/Image-Line/Voix.fst",
          "armAndInput":true,"startRecording":true,"recKey":{"keyCode":15},
          "spots":{"arm":{"anchor":"cursorXWindowY","dx":12,"dy":640}}}}
```

## Garde-fous
- Démarre seulement si FL est au premier plan, s'arrête si FL le perd.
- Attend que ⌃⌥⌘⇧ du raccourci soient relâchés (un clic avec ⌃ serait un clic droit).
- Une seule macro à la fois ; un raccourci répété pendant l'exécution est avalé.
- Échap annule. Aucune frappe n'est lue ni journalisée.
- Échec : bip + notification `.macroFinished` (userInfo `ok`, `text`).

## À valider sur un vrai FL (modèle à positions apprises)
1. Le menu contextuel de la piste est-il natif (visible par l'Accessibilité) ? Sinon, les clics de secours appris prennent le relais.
2. « Open mixer track state » ouvre-t-il une boîte native macOS ? Sinon `waitDialog` et `chooseFile` ne fonctionnent pas.
3. Les événements envoyés au PID (souris) sont-ils pris par FL ? Sinon essayer `MacroRunner.warpCursor`.
4. Les boutons d'armement / d'entrée ont-ils une position stable par rapport à la colonne de la piste et au haut de la fenêtre ?

Diagnostic : app quittée, `FLShortcut --diag-macro`, ouvrir dans FL le menu ou la boîte à étudier pendant les 6 s. La sortie liste les fenêtres de FL et l'arbre d'accessibilité.

Sonde : `FLShortcut --diag-macro --watch 20` affiche pendant 20 s chaque fenêtre de FL qui apparaît, bouge ou disparaît (menus et sous-menus compris), l'état des boutons de la souris et ce que l'Accessibilité voit sous le curseur. Journal de chaque macro : `~/Library/Logs/FL Shortcuts/macro.log` (bouton « Exporter le journal… » dans la fiche ; aucune frappe ni nom de fichier).

Icône : `FLShortcut --diag-icon 7-4` (colonne-rangée de la grille de FL, ici Microphone ; `--relearn` pour montrer de nouveau le bouton de l'icône) pose l'icône sur l'élément sélectionné du vrai FL par le même chemin que le bloc « Nom et couleur » (FL mis au premier plan, F2, bouton de l'icône, case, Entrée) et affiche chaque fenêtre vue et chaque point cliqué ; « PASS » ou « FAIL » à la fin. Sélectionne d'abord une seule piste ou un seul canal, dans un projet de test. La grille de FL ne se ferme pas avec Échap : restée ouverte, elle est signalée, jamais fermée par un clic à l'aveugle.

## Fichiers
`Macro.swift` (données, logique pure) · `MacroRunner.swift` (exécution, menus, apprentissage, diagnostic) · `MacroFields.swift` (interface) · `Model.swift`, `KeyRouter.swift`, `EventTap.swift`, `EditorView.swift`, `Catalog.swift`, `FLShortcutApp.swift` (branchements) · `Tests/FLShortcutTests/MacroTests.swift`.

Créateur : `MacroLibraryStore.swift` (bibliothèque), `MacroExchange.swift` (.flsmacro), `MacroEditing.swift` (liste à plat, opérations, palette : logique pure), `MacroEditorModel.swift` (brouillon, annulation, essai), `MacroRunMonitor.swift` (suivi d'un essai), `MacroCreatorWindow.swift` (fenêtre AppKit, libérée à la fermeture), `MacroEditorView.swift`, `MacroPalette.swift`, `MacroInspector.swift`, `MacroLibraryView.swift` (interface) · tests `MacroLibraryTests`, `MacroEditingTests`, `MacroRefTests`, `MacroCreatorWindowTests` · essai de bout en bout `--selftest-macro … --scenario blocs` (macro construite en blocs, lancée par le même chemin que l'ancien bouton « Tester »).

Windows : non porté (`windows/FLShortcut.Core` ignore le type `macro` ; il faudrait `SendInput` + UI Automation).
