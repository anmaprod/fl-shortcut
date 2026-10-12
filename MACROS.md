# Macros FL Shortcut (sans MIDI)

## Pourquoi pas de MIDI, pas d'UDP
- Le lien MIDI (script Python dans FL) est resté en option, désactivé par défaut. Le **mode léger** n'installe rien dans FL : l'app envoie des touches d'origine de FL, seulement quand FL est au premier plan.
- Les macros prolongent ce mode : mêmes garde-fous, aucune dépendance au script FL.
- Un lien UDP local n'a pas été retenu : FL ne charge un script de contrôleur que s'il est rattaché à un port MIDI activé, le script ne peut lire un socket que depuis `OnIdle` (~20 ms), et il faudrait refaire toute l'authentification déjà présente dans le protocole HMAC.

## Ce que fait une macro
Une macro est une liste d'étapes (`Macro.swift`) exécutée par `MacroRunner` sur sa propre file, jamais dans le thread du tap clavier.

| Étape | Effet |
|---|---|
| `key` | une touche ou combinaison envoyée à FL (liste noire ⌘Q, ⌘W… revérifiée) |
| `delay` | pause (≤ 5 s), interrompue par Échap |
| `click` | clic gauche/droit à un point appris (repère : curseur, fenêtre FL, ou x du curseur + y de la fenêtre) ; le point doit tomber dans une fenêtre de FL |
| `menu` | choix dans un menu par ses titres (Accessibilité) ; sinon clics de secours appris |
| `waitDialog` / `waitDialogClose` | attend l'ouverture / la fermeture d'une boîte de dialogue de FL (nombre de fenêtres de FL au niveau 0 à 8) |
| `chooseFile` | dans une boîte « Ouvrir » native : ⌘⇧G, chemin, Entrée, Entrée |

Bornes (`MacroLibrary.validate`) : 40 étapes, 180 s au total, chemins sans caractères de contrôle. Une macro `custom` (étapes libres) ne s'écrit qu'à la main dans le profil JSON et est **refusée à l'import**.

## Enregistrement rapide automatique (modèle livré, rien à régler)
Modèle `autoRecord`, sur ⌃R dans le profil Recommandé. Il suffit de cliquer sur une piste du Mixer puis de taper le raccourci. **Aucune lecture de l'écran** : seule la permission du clavier (Accessibilité) est utilisée.

| Étape | Effet |
|---|---|
| `trackMenu` | clic droit sur la **dernière piste cliquée** dans FL (`TrackMemory.swift`), puis « File › Open mixer track state » : la **première fois**, une bulle demande à l'utilisateur de cliquer lui-même ; l'app retient la place des clics par rapport au clic droit (`MacroSpots.swift`) et les refait ensuite seule |
| `waitDialog` / `waitDialogClose` | attend la boîte « Ouvrir » puis le choix du preset (ou tape le chemin d'un preset fixe) |
| `armTrack` | action 39 `armon` du script FL : arme la piste sélectionnée **seulement si** elle ne l'est pas |
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

## Fichiers
`Macro.swift` (données, logique pure) · `MacroRunner.swift` (exécution, menus, apprentissage, diagnostic) · `MacroFields.swift` (interface) · `Model.swift`, `KeyRouter.swift`, `EventTap.swift`, `EditorView.swift`, `Catalog.swift`, `FLShortcutApp.swift` (branchements) · `Tests/FLShortcutTests/MacroTests.swift`.

Windows : non porté (`windows/FLShortcut.Core` ignore le type `macro` ; il faudrait `SendInput` + UI Automation).
