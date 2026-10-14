# Macros FL Shortcut (sans MIDI)

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
| `chooseFile` | dans la boîte « Open » native (`PresetChooser.swift`) : ⌘⇧G renvoyé jusqu’à l’apparition de « Aller au dossier », chemin tapé caractère par caractère (un ⌘V synthétique est ignoré par macOS 26), Entrée quand la feuille est prête, Entrée jusqu’à la fermeture de la boîte. Essai réel sur la CI : `FLShortcut --selftest-preset` |

Bornes (`MacroLibrary.validate`) : 40 étapes, 180 s au total, chemins sans caractères de contrôle. Une macro `custom` (étapes libres) ne s'écrit qu'à la main dans le profil JSON et est **refusée à l'import**.

## Créer ses propres macros (créateur de macros)
Fenêtre *Raccourcis › Macros* : la bibliothèque des macros en blocs (nom, raccourci, badges « Lien FL », « À apprendre », « Désactivée », « À corriger »), avec **Nouvelle macro**, **Modèles…** et **Importer…**. Chaque macro s'ouvre dans le **créateur**, une fenêtre à part (fenêtre AppKit créée à la demande ; à la fermeture, le brouillon est enregistré, « Montrer dans FL… » et un essai en préparation s'arrêtent, puis la vue et son état sont libérés : rien ne reste en mémoire ni ne tourne) :

- **à gauche, la palette** par catégorie, avec une recherche (taper filtre, ↩ ajoute le premier bloc) ; un clic ajoute le bloc sous la ligne choisie, ou dans une boucle si sa ligne « Fin de la boucle » est choisie ;
- **au centre, la liste** des étapes, à plat avec un retrait selon l'imbrication : une phrase en français par ligne (« Appuyer sur ⌘S », « Attendre une boîte de dialogue · 4 s au plus »), une case pour sauter un bloc sans le supprimer, des badges (pause fixe, lien FL, à apprendre, à corriger, continue si échec). Glisser pour ranger, ⌘D duplique, ⌫ supprime, ⌘Z annule ;
- **à droite, l'inspecteur** du bloc choisi, construit à partir de ses réglages (registre) : touche capturée comme un raccourci, nombres bornés, preset .fst, action de FL du catalogue (avec sa touche de secours), endroit d'un clic montré dans FL (« Montrer dans FL… »), « Si le bloc échoue : Arrêter / Continuer », note ;
- **en haut**, le nom, l'état (« Prête · 5 blocs · 3 s au plus » ou ce qui bloque) et le **raccourci**, avec les avertissements de conflit habituels ;
- **▶ Tester** (⌘R) : FL passe devant et la macro tourne exactement comme depuis son raccourci ; chaque ligne montre son état (bleu en cours, coche verte, rouge avec la raison), un bandeau donne le résultat (« Échec au bloc 4 (Attendre une fenêtre) : … » et « Montrer le bloc »). Échap arrête. Les besoins de la macro (ports MIDI à la demande en mode léger, suivi de la dernière piste cliquée) ne sont demandés qu'au début de l'essai et rendus à la fin : ouvrir le créateur ne crée aucun port MIDI.

Le brouillon est enregistré par **Enregistrer** (⌘S) ou 0,5 s après la dernière modification (jamais à chaque frappe). *Personnaliser dans le créateur…* (fiche d'un raccourci « Enregistrement rapide ») développe le modèle en blocs avec ses réglages, et le raccourci lance ensuite cette version.

| Bloc de la palette | Effet |
|---|---|
| Touche | une touche ou combinaison envoyée à FL (liste noire revérifiée), N fois |
| Lettres d'un menu de FL | lettres soulignées d'un menu ouvert par la macro, Entrée à la fin si besoin |
| Touche de menu | ↑ ↓ ← → Entrée Échap, seulement dans un menu ouvert par la macro |
| Clic à un endroit appris | endroit montré une fois dans FL (relatif à la fenêtre, taille retenue, ou au menu ouvert) ; tant qu'il n'est pas montré, la macro est bloquée |
| Clic droit sur la piste | sur la dernière piste cliquée dans le Mixer (ouvre son menu) |
| Pause | ≤ 5 s (badge « pause fixe » : préférer une attente) |
| Attendre une fenêtre / la fermeture | boîte de dialogue ou menu de FL, 120 s au plus (le pointeur est écarté d'un menu qui s'ouvre) |
| Menu de la piste | clic droit sur la piste puis 2 ou 3 lettres (File › Open mixer track state…) |
| Choisir un preset | dans la boîte « Open » : le fichier .fst choisi (dossier personnel) |
| Action de FL | une action de FL Shortcut par le lien avec FL, sinon sa touche de FL ; *Armer la piste* (repli : menu de la piste) et *Allumer le REC* (repli : touche R) |
| Choisir l'entrée 1 | « (none) » → entrée 1, montrée une fois |
| Vérifier le larsen | micro et sortie de l'ordinateur, lancé dès le début, affiché à la fin |
| Répéter | N fois (50 au plus), blocs à l'intérieur |
| Arrêter la macro · Commentaire | fin avec message · note ignorée à l'exécution |

*Si… sinon*, *Tant que* et *Attendre que* sont affichés grisés (« bientôt ») : l'interpréteur sait les jouer, leurs conditions se régleront dans le créateur à l'incrément suivant.

**Stockage** : `~/Library/Application Support/FL Shortcut/macros.json` (0600, écriture atomique, copie `macros.precedente.json` une fois par lancement ; fichier illisible, plus récent ou en partie illisible : copie datée gardée). Le raccourci ne garde qu'une référence (`"macroRef"`), doublée d'un lien caché `"unknownAction": "macroRef:<uuid>"` que les anciennes versions conservent : en revenant à cette version, la macro est retrouvée. La désinstallation supprime tout le dossier.

**Partage** : *Exporter…* écrit un fichier `.flsmacro` (JSON lisible) :

```json
{ "format": "flsmacro", "version": 1, "exportedBy": "FL Shortcut 1.2 (macOS)",
  "macro": { "name": "Armer la piste et lancer le REC",
             "blocks": [ { "type": "click", "id": "…", "target": { "anchor": "toLearn" }, "button": "right" } ] } }
```

Les endroits appris sont retirés (à montrer sur chaque Mac), le chemin d'un preset est écrit relatif au dossier personnel (`~/…`). *Importer…* relit le fichier bloc par bloc en français, liste complète qui défile, avec le nombre de blocs à relire en tête (touches avec ⌘, clics, fichiers, lien FL et blocs cachés de l'ancien format signalés) : 256 Ko, 200 blocs et 4 niveaux au plus, ids régénérés, **chaque clic est à montrer de nouveau** (aucune position reprise d'un fichier, même écrit à la main), la macro arrive **sans raccourci**. Bibliothèque illisible ou impossible à enregistrer : le message reste affiché dans le menu, la page Macros (même vide) et le créateur ; si la copie de secours échoue, le fichier n'est plus jamais réécrit pendant ce lancement.

## Enregistrement rapide automatique (modèle livré, rien à régler)
Modèle `autoRecord`, sur ⌃R dans le profil Recommandé. Il suffit de cliquer sur une piste du Mixer puis de taper le raccourci. **Aucune lecture de l'écran** : seule la permission du clavier (Accessibilité) est utilisée.

| Étape | Effet |
|---|---|
| `trackMenu` | clic droit sur la **dernière piste cliquée** dans FL (`TrackMemory.swift`), puis « File › Open mixer track state » **au clavier** : les éléments des menus de FL ont une lettre soulignée (F de File, O de Open). La macro attend que le menu apparaisse (nouvelle fenêtre de FL), écarte le pointeur du menu, tape F (flèche droite si le sous-menu ne s'ouvre pas), puis O (Entrée si les menus restent ouverts ; retenu, Entrée part ensuite aussitôt). Après un passage réussi, la rangée des noms du Mixer et la hauteur du menu sont retenues : clic droit toujours sur cette rangée, refus si le dernier clic en est loin (Playlist : un clic droit y supprime un clip) ou si un autre menu s'ouvre. Rien à apprendre |
| `waitDialog` / `waitDialogClose` | attend la boîte « Ouvrir » puis le choix du preset (ou tape le chemin d'un preset fixe) |
| `armTrack` | action 39 `armon` du script FL : arme la piste sélectionnée **seulement si** elle ne l'est pas. Sans lien MIDI : rien (choisir l'entrée arme la piste dans FL) |
| `recordOn` | action 40 `recon` du script FL : allume le REC **seulement s'il** est éteint |
| `selectInput` | « (none) » puis l'entrée « 1 » : appris la première fois (place relative au coin haut-droit de la fenêtre de FL, retenue avec sa taille ; taille différente → redemandé, jamais de clic à côté) |
| `feedbackCheck` | **en dernier** : micro **et** haut-parleurs de l'ordinateur en service → fenêtre « risque de larsen » (tout est déjà en place, il ne reste qu'à changer d'entrée ou de sortie). Vérifié en parallèle dès le début de la macro : aucune attente |

**Lien MIDI à la demande** : en mode léger, les ports « FL Shortcut » existent (FL les voit) mais rien n'y circule. Le script FL démarre **endormi** : `OnIdle` et `OnRefresh` s'arrêtent à leur première ligne. La macro le réveille brièvement (PING = 2), envoie l'action signée, et le script se rendort tout seul 8 s après (PROTOCOL.md §4). À régler une fois dans FL : *Options › MIDI Settings*, Input « FL Shortcut » : Enable, Controller type « FL Shortcut » ; Output « FL Shortcut » : même port.

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

Sonde : `FLShortcut --diag-macro --watch 20` affiche pendant 20 s chaque fenêtre de FL qui apparaît, bouge ou disparaît (menus et sous-menus compris), l'état des boutons de la souris et ce que l'Accessibilité voit sous le curseur. Journal de chaque macro : `~/Library/Logs/FL Shortcut/macro.log` (bouton « Exporter le journal… » dans la fiche ; aucune frappe ni nom de fichier).

## Fichiers
`Macro.swift` (données, logique pure) · `MacroRunner.swift` (exécution, menus, apprentissage, diagnostic) · `MacroFields.swift` (interface) · `Model.swift`, `KeyRouter.swift`, `EventTap.swift`, `EditorView.swift`, `Catalog.swift`, `FLShortcutApp.swift` (branchements) · `Tests/FLShortcutTests/MacroTests.swift`.

Créateur : `MacroLibraryStore.swift` (bibliothèque), `MacroExchange.swift` (.flsmacro), `MacroEditing.swift` (liste à plat, opérations, palette : logique pure), `MacroEditorModel.swift` (brouillon, annulation, essai), `MacroRunMonitor.swift` (suivi d'un essai), `MacroCreatorWindow.swift` (fenêtre AppKit, libérée à la fermeture), `MacroEditorView.swift`, `MacroPalette.swift`, `MacroInspector.swift`, `MacroLibraryView.swift` (interface) · tests `MacroLibraryTests`, `MacroEditingTests`, `MacroRefTests`, `MacroCreatorWindowTests` · essai de bout en bout `--selftest-macro … --scenario blocs` (macro construite en blocs, lancée par le chemin de « Tester »).

Windows : non porté (`windows/FLShortcut.Core` ignore le type `macro` ; il faudrait `SendInput` + UI Automation).
