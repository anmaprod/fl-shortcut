# Prompt : recherche approfondie et propositions de code pour FL Shortcut (macOS)

> À coller tel quel dans une nouvelle conversation. Le destinataire n'a accès qu'au dépôt GitHub
> `anmaprod/fl-shortcut` et ne connaît rien du projet : tout ce dont il a besoin est ici ou dans le dépôt.

---

## 1. Ton rôle et ce que j'attends de toi

Tu travailles pour le propriétaire de **FL Shortcut**, un musicien francophone qui n'est pas développeur. Il est
sur un Mac M4 Pro sous macOS 27, avec FL Studio 2026. Tu as deux rôles :

1. **Chercheur.** Tu mènes une recherche technique très approfondie sur tout ce qui peut rendre l'app macOS plus
   fiable, plus rapide, plus légère et plus agréable. Tu lis les sources primaires : documentation Apple et
   Image-Line, code source d'outils connus, sessions WWDC, forums officiels.
2. **Ingénieur.** À partir de cette recherche, tu rédiges un document unique, en français, qui contient tes
   conclusions sourcées et le **code prêt à intégrer**.

Ton document sera relu par un autre agent (Claude Code). Lui dispose du dépôt, compile sur la CI macOS, fait
passer les tests et mesure la mémoire, et il ne retiendra que ce qui est prouvé. Écris donc pour un relecteur
exigeant :
- chaque affirmation technique a sa source ou est marquée comme hypothèse ;
- chaque morceau de code dit où il va et comment le vérifier.

**Périmètre : macOS uniquement.** Le dépôt contient aussi une app Windows (`windows/`). Ignore-la complètement pour
cette mission : Windows et Linux viendront plus tard.

Prends le temps qu'il faut. Planifie ta recherche, lance plusieurs recherches en parallèle, puis vérifie et
recoupe avant de conclure. La profondeur compte plus que la vitesse. La justesse compte plus que le volume.

---

## 2. Le projet en bref

**FL Shortcut** ajoute à FL Studio ce qui lui manque : un éditeur de raccourcis clavier et des macros. C'est une
app de **barre des menus** en SwiftUI, avec quelques fenêtres AppKit.

- **Raccourcis.** Quand FL Studio est au premier plan, une interception clavier (`CGEventTap`) reconnaît les
  raccourcis de l'utilisateur. Elle envoie alors à FL ses propres touches : Mixer, Playlist, REC…
- **Macros.** La macro phare, « Enregistrement rapide », se lance quand l'utilisateur clique sur une piste du
  Mixer puis tape le raccourci. Elle enchaîne :
  1. clic droit sur la piste › File › *Open mixer track state*, au clavier, par les lettres soulignées F puis O ;
  2. choix du preset `.fst` dans la boîte « Open » de macOS ;
  3. armement de la piste, seulement si elle ne l'est pas ;
  4. REC, seulement s'il est éteint ;
  5. entrée « 1 » (le micro) ;
  6. avertissement de larsen, à la fin.
- **Créateur de macros.** L'utilisateur construit ses propres macros en blocs, sur le modèle de Keyboard Maestro
  et de Pulover's Macro Creator. Il y trouve une palette, une liste d'étapes écrites en phrases, un inspecteur, un
  essai suivi bloc par bloc et l'export/import `.flsmacro`.
- **Lien MIDI facultatif.** Un script Python chargé par FL (`Resources/device_FLShortcut.py`, protocole décrit dans
  `PROTOCOL.md`) donne des actions exactes : armer, REC, mute, solo… Il est **endormi par défaut** et réveillé
  seulement pendant une macro.

**Où lire dans le dépôt.** Lis la branche de travail **`claude/relaxed-mayer-ndguzv`** (pas `main`). Note dans ton
rendu le SHA de sa tête au moment où tu commences.

| À lire d'abord | Pourquoi |
|---|---|
| `docs/contexte/HISTORIQUE.md` | Décisions, échecs et leçons : **à lire en entier avant tout** |
| `docs/contexte/03-architecture-code.md` | Architecture du créateur et plan en 6 incréments (1 et 2 faits, 3 à 6 à faire) |
| `docs/contexte/02-fl-studio-surface.md` | Ce qu'on sait déjà de l'API de script de FL, de ses raccourcis et de ses menus (à vérifier et compléter) |
| `docs/contexte/01-outils-macro.md` | Étude des outils de macros (Keyboard Maestro, PMC, AutoHotkey, Shortcuts…) |
| `docs/contexte/04-revue-increment2.md` | Dernière revue de code |
| `docs/superpowers/plans/2026-10-14-correctifs-createur-macros.md` | Dernier plan exécuté (contraintes, objectifs mémoire) |
| `MACROS.md`, `PROTOCOL.md`, `README.md` | Documentation du fonctionnement actuel |
| `audit/01…05, 10` | Audits précédents (sécurité, fiabilité, compatibilité, ergonomie, relecture Swift) |
| `.github/workflows/build.yml`, `scripts/mesure-interface.sh` | Comment la CI compile, teste, simule FL et mesure la mémoire et le processeur |

**Carte du code** (`Sources/FLShortcut/`) :
- **Interception et envoi de touches :** `EventTap.swift`, `KeyRouter.swift`, `KeyNames.swift` (dispositions de
  clavier), `Safety.swift`.
- **Moteur de macros :**
  - modèle et validation : `MacroModel.swift`, `MacroRegistry.swift` (registre de tous les blocs),
    `MacroValidation.swift` ;
  - exécution : `MacroInterpreter.swift` (effets injectables), `MacroRunner.swift`, `MacroEffectsMac.swift`
    (effets réels : clics, touches, fenêtres), `MacroFLBlocks.swift` (menu de piste, armement, REC) ;
  - outils : `PresetChooser.swift` (boîte « Open »), `MacroWindows.swift` (instantanés `CGWindowList`),
    `TrackMemory.swift` (dernière piste cliquée), `MacroSpots.swift` et `MacroLearner.swift` (positions apprises).
- **Lien MIDI :** `MIDILink.swift`, `FLProtocol.swift`, `FLScriptInstaller.swift`.
- **Créateur :** `MacroEditorView.swift`, `MacroEditorModel.swift`, `MacroInspector.swift`, `MacroPalette.swift`,
  `MacroEditing.swift`, `MacroRunMonitor.swift`, `MacroCreatorWindow.swift`, `MacroLibraryStore.swift`,
  `MacroLibraryView.swift`, `MacroExchange.swift`.
- **Interface générale :** `FLShortcutApp.swift`, `EditorView.swift`, `GlassStyle.swift` (Liquid Glass),
  `OnboardingView.swift`.
- **Simulation et essais sur la CI :** `FakeFL.swift` (un faux FL Studio) et `MacroSelfTest.swift` (macro jouée de
  bout en bout sur le faux FL). Les tests XCTest sont dans `Tests/FLShortcutTests/`.

---

## 3. Contraintes non négociables

Respecte-les dans chaque recommandation et chaque ligne de code. Pour chacune, la raison est donnée : quand une
idée la heurte, sers-toi de la raison pour juger.

1. **Pas de lecture ni d'enregistrement de l'écran** : ni ScreenCaptureKit, ni `CGWindowListCreateImage`, ni
   recherche d'image, ni OCR. L'utilisateur refuse de demander cette autorisation aux gens. Sont permis :
   - la liste des fenêtres (numéro, niveau, cadre ; jamais les pixels ni les titres) ;
   - l'Accessibilité, déjà accordée pour le clavier ;
   - les événements clavier et souris.
2. **MIDI seulement pendant une macro.** Le script FL dort le reste du temps pour que FL ne ralentisse jamais.
   Aucun trafic au repos.
3. **Rien ne tourne au repos.** Pas de minuterie, de sondage ni d'observateur permanent quand aucune macro ne
   tourne et que les fenêtres sont fermées. Mesures actuelles : processeur au repos 0,0 %, mémoire 14 Mo (barre
   des menus seule) et 54 Mo (fenêtre ouverte). Toute proposition doit dire son coût en mémoire et en processeur.
4. **Ultra rapide et fluide.** Une macro doit s'exécuter le plus vite possible, sans perdre en fiabilité.
5. **Ne jamais modifier une étape validée par l'utilisateur sur son vrai FL.** C'est la leçon la plus chère du
   projet (voir HISTORIQUE, point 4). En particulier, ne touche pas à l'ouverture du menu de piste dans
   `MacroFLBlocks.swift` / `MacroEffectsMac.swift` :
   - clic droit : survol 30 ms, appui 50 ms ;
   - lettres : 15 ms entre appui et relâchement ;
   - attente du sous-menu : 0,6 s ;
   - Entrée apprise : 0,12 s.

   Une idée qui toucherait ces durées ou cet ordre va dans une section **« Options à tester par l'utilisateur »**,
   jamais dans le code principal.
6. **L'utilisateur ne configure que le raccourci.** Tout le reste doit être automatique, ou appris une seule fois.
7. **Plateforme :**
   - macOS 13 minimum ;
   - `swift-tools-version:5.9`, mode Swift 5 (la CI compile avec Xcode 26) ;
   - **pas de `@Observable`** (macOS 14+) : on utilise `ObservableObject` ;
   - toute API plus récente que macOS 13 sous `if #available`, avec un repli ;
   - **aucune dépendance tierce** sans raison très forte et argumentée.
8. **Interface et commentaires du code en français**, concis, dans le style du fichier modifié. L'interface suit
   le style **Liquid Glass d'Apple** (macOS 26/27), sans coût en mémoire.
9. **Sécurité :**
   - garde-fous dans la couche d'effets uniquement : FL au premier plan, liste noire de touches (⌘Q, ⌘W…), Échap
     qui arrête, clics seulement dans FL ;
   - un fichier `.flsmacro` importé est relu et arrive sans raccourci ;
   - les journaux ne contiennent jamais une touche tapée, un chemin ou un nom de piste.

---

## 4. Ce qu'on sait déjà (à ne pas redécouvrir, mais à vérifier)

Ces faits ont été établis par des essais sur la CI et sur le vrai Mac de l'utilisateur. Considère-les comme acquis.
Tu peux les compléter, et les contredire **seulement avec une source primaire**.

- **Envoi des touches.** `CGEvent.postToPid` fonctionne pour les menus, les lettres et les touches de FL. En
  revanche, la boîte « Open » de macOS 26 est servie par un autre processus du système : il faut envoyer au flux
  HID (`.cghidEventTap`) quand FL est au premier plan.
- **Presse-papiers.** Le ⌘V synthétique est ignoré sous macOS 26. Le chemin du preset est donc tapé
  (`keyboardSetUnicodeString`, par paquets de 12 caractères).
- **Détection des fenêtres.** Elle se fait par instantanés `CGWindowList`, avec deux lectures stables de suite.
  Les menus contextuels de FL sont au niveau 101, les boîtes de dialogue au niveau 8.
- **Menus contextuels de FL.** On les navigue par leurs lettres soulignées : F = File, S = Select, D = Delete,
  R, A, U, C, T…
- **Sans MIDI :**
  - armement : S → ← → ↓ ×5 → Entrée (« Arm selected track(s) »), vérifié seulement sur le faux FL ;
  - REC : touche R, qui *inverse* l'état.
- **API Python de FL** (d'après `02-fl-studio-surface.md`, à vérifier) : aucune fonction pour charger un état de
  piste, choisir l'entrée audio d'une piste, ouvrir un menu ni faire un rendu.
- **Barre des menus de macOS.** Depuis FL 2024.2, les menus principaux de FL y sont, donc atteignables par
  l'Accessibilité.
- **Signature ad hoc sur la CI.** Chaque version est une app « différente » pour macOS : l'autorisation
  Accessibilité peut rester cochée mais ne plus marcher après une mise à jour.
- **Mémoire :**
  - un `Form` groupé SwiftUI construit toutes ses lignes ; le passage en `List` a fait tomber la recherche de
    228 Mo à 86 Mo ;
  - une scène `Window` SwiftUI ne se libère pas, d'où une fenêtre AppKit possédée pour le créateur ;
  - il reste **+25 Mo** inexpliqués après la première ouverture du créateur (`MALLOC_SMALL` de 39 à 59 Mo). Ce
    surplus est stable sur 3 ouvertures et aucun modèle ne reste vivant.

---

## 5. Les chantiers de recherche

Les chantiers sont classés par priorité. Pour chacun : **quoi** trouver précisément, **où** chercher, **comment**
chercher, et le **rendu** attendu.

**Méthode commune à tous les chantiers :**
- Sources primaires d'abord, de préférence de 2024 ou plus récentes (macOS 26/27, FL 2025/2026). Note l'URL, la
  date et la version concernée.
- Pour une API, cite la page de documentation et sa **disponibilité** (version de macOS, version d'API de FL).
- Lis le code source des outils open source qui ont déjà résolu le problème : Hammerspoon, Karabiner-Elements,
  cliclick, skhd, AltTab, Rectangle, Maccy, KeyboardShortcuts, Sparkle… Cite le fichier et la ligne.
- Distingue toujours **fait sourcé**, **déduction** et **à tester sur un vrai Mac / vrai FL**.
- Si tu ne trouves rien de fiable, dis-le, et propose l'expérience qui trancherait.

### P0 — Fiabilité et vitesse de la macro « Enregistrement rapide » sur le vrai FL

**P0.1 — API de script MIDI de FL Studio : inventaire exact pour nos besoins**
- **Quoi :**
  - inventaire des fonctions et constantes utiles des modules `mixer`, `transport`, `ui`, `general`, `channels`,
    `plugins` et `device` ;
  - inventaire des rappels (`OnInit`, `OnIdle`, `OnMidiMsg`, `OnSysEx`, `OnRefresh`, `OnDirtyMixerTrack`…) ;
  - pour chacun, la signature et la version d'API minimale.

  Et ces réponses précises :
  - a. Peut-on charger un état de piste `.fst`, même indirectement : événement REC, `general.processRECEvent`,
    fonction cachée, plugin ?
  - b. Peut-on lire ou choisir l'entrée audio d'une piste du Mixer ?
  - c. Peut-on lire ou changer la piste sélectionnée (`mixer.trackNumber`, `mixer.setTrackNumber`…) ?
  - d. Comment armer et lancer le REC de façon idempotente ?
  - e. Quel est le coût de `OnIdle`, et comment garder le script vraiment inerte au repos ?
- **Où :**
  - le manuel Image-Line, page *MIDI Scripting* ;
  - le dépôt officiel de stubs **IL-Group/FL-Studio-API-Stubs** sur GitHub et son site de documentation ;
  - les sous-forums « MIDI Scripting » du forum Image-Line ;
  - les notes de version de FL 2024, 2025 et 2026 ;
  - les scripts open source sur GitHub (cherche `mixer.armTrack`, `processRECEvent`, `REC_Mixer`) ;
  - les projets de Miguel Guthridge (auteur des stubs, Universal Controller Script).
- **Comment :** confronte tes trouvailles à `docs/contexte/02-fl-studio-surface.md`, `Resources/device_FLShortcut.py`
  et `PROTOCOL.md`.
- **Rendu :**
  - un tableau « fonction → utilité pour FL Shortcut → version mini → source » ;
  - une **proposition d'extension du protocole**, rétrocompatible (la version reste 2), avec le code Python du
    script et le code Swift côté app.

**P0.2 — Charger un preset `.fst` sans piloter la boîte « Open »**
- **Quoi :** savoir si FL sait charger un état de piste autrement que par la boîte « Open ». C'est l'étape la plus
  lente et la plus fragile (≈ 1,3 à 1,7 s). Pistes à examiner :
  - ouverture d'un `.fst` par le Finder (Apple Event `odoc`, `NSWorkspace.open(_:withApplicationAt:)`) :
    s'applique-t-il à la piste sélectionnée ?
  - glisser-déposer d'un `.fst` sur une piste du Mixer ;
  - double-clic dans le Browser de FL ;
  - presets de Mixer dans le Browser ;
  - ligne de commande de FL.
- **Où :**
  - le manuel FL : *Mixer track properties*, *Browser*, *Mixer presets*, *File formats* ;
  - le forum Image-Line et Reddit r/FL_Studio ;
  - des vidéos de démonstration (ne retiens que ce qui est montré clairement).
- **Rendu :**
  - ce qui est confirmé ou infirmé, avec la source ;
  - pour chaque voie plausible, un protocole d'essai de 2 minutes que l'utilisateur fera sur son vrai FL ;
  - le code de la voie la plus prometteuse, **en option désactivée par défaut** (contrainte 5).

**P0.3 — Piloter la boîte « Open » de macOS 26/27 (si P0.2 échoue)**
- **Quoi :**
  - la méthode la plus rapide et la plus fiable pour choisir un fichier dans un `NSOpenPanel` servi hors
    processus (ViewBridge, « remote view ») ;
  - savoir si l'Accessibilité y voit le champ « Aller au dossier » et la liste ;
  - comprendre pourquoi le ⌘V synthétique est ignoré sous macOS 26 (nouvelles protections du presse-papiers ?) ;
  - voir comment Keyboard Maestro, Raycast et Maccy s'y sont adaptés.
- **Où :**
  - documentation Apple : `NSOpenPanel`, `NSPasteboard`, confidentialité du presse-papiers dans macOS 26 ;
  - Apple Developer Forums ;
  - forum de Keyboard Maestro ;
  - code de Maccy (collage par CGEvent).
- **Rendu :** comparaison des méthodes (vitesse, fiabilité, autorisations), puis le code de la meilleure en diff
  de `PresetChooser.swift`.

**P0.4 — Menus de FL par l'Accessibilité**
- **Quoi :**
  - savoir si le menu contextuel d'une piste du Mixer (fenêtre surgissante de niveau 101) est exposé à
    l'Accessibilité (`AXMenu`, `AXMenuItem`, `AXPress`), ou seulement le menu de la barre des menus. Si oui, on
    pourrait viser « Open mixer track state » ou « Arm selected track(s) » par leur titre, sans lettres ni flèches ;
  - savoir avec quoi FL Mac dessine ses menus (Delphi/FireMonkey ? natif ?).
- **Où :**
  - documentation Apple `AXUIElement` ;
  - rapports d'utilisateurs d'Accessibility Inspector sur FL ;
  - forums des outils d'accessibilité (VoiceOver et FL Studio) ;
  - code de Hammerspoon `hs.axuielement`.
- **Rendu :** un verdict sourcé, et le code d'un petit outil de diagnostic qui liste l'arbre AX de FL, que
  l'utilisateur lancera une fois.

### P1 — Moteur d'événements macOS

**P1.1 — Envoi d'événements : vitesse et robustesse**
- **Quoi :**
  - les états de `CGEventSource` (`.privateState`, `.combinedSessionState`, `.hidSystemState`) ;
  - `CGEventSourceSetLocalEventsSuppressionInterval` ;
  - marquer nos propres événements (`eventSourceUserData`) pour que notre interception les ignore ;
  - les durées minimales fiables entre appui et relâchement ;
  - les drapeaux de modificateurs restés collés après un raccourci (⌃ encore enfoncé) ;
  - les différences entre `postToPid` et `post(tap:)`.
- **Où :**
  - Quartz Event Services (developer.apple.com) ;
  - code de Hammerspoon (`extensions/eventtap`), de cliclick (BlueM/cliclick) et de skhd ;
  - documentation de Karabiner-Elements ;
  - forum de Keyboard Maestro (« keystroke delay »).
- **Rendu :** des recommandations chiffrées, et un diff de `MacroEffectsMac.swift` limité aux étapes **non**
  validées par l'utilisateur.

**P1.2 — Attendre une fenêtre sans sonder**
- **Quoi :**
  - remplacer, là où c'est possible, le sondage de `CGWindowList` par des notifications d'Accessibilité sur
    l'application FL (`AXObserver` : `kAXWindowCreatedNotification`, `kAXFocusedWindowChangedNotification`,
    `kAXSheetCreatedNotification`…) ;
  - comparer la latence, et évaluer la fiabilité si FL n'expose pas ses fenêtres.
- **Où :** documentation `AXObserver` ; code source d'AltTab et de Rectangle ; Hammerspoon `hs.window.filter`.
- **Rendu :**
  - la mesure de latence attendue ;
  - le code d'un `WindowWaiter` à observateur, actif seulement pendant une macro (contrainte 3) ;
  - un repli sur le sondage actuel.

**P1.3 — Dispositions de clavier (l'utilisateur est en AZERTY)**
- **Quoi :**
  - comment trouver le code de touche d'une lettre de menu en AZERTY, QWERTZ ou Dvorak (`UCKeyTranslate`,
    `TISCopyCurrentKeyboardLayoutInputSource`, `kTISPropertyUnicodeKeyLayoutData`) ;
  - savoir si FL lit les mnémoniques par caractère ou par code de touche ;
  - les pièges : touches mortes, changement de disposition en cours de route.
- **Où :** documentation Carbon (TIS, UCKeyTranslate), Karabiner, KeyboardShortcuts (sindresorhus).
- **Rendu :** un audit de `KeyNames.swift`, avec des tests XCTest des dispositions.

**P1.4 — Autorisations (TCC) et interception**
- **Quoi :**
  - quelle autorisation, Accessibilité ou Surveillance de l'entrée, pour un `CGEventTap` qui modifie, et pour
    `CGEvent.post` ;
  - `CGPreflightListenEventAccess`, `CGRequestListenEventAccess`, `CGPreflightPostEventAccess` ;
  - ce qui change dans macOS 15, 26 et 27 ;
  - la gestion de `tapDisabledByTimeout` et `tapDisabledByUserInput` ;
  - `CGEvent.tapCreateForPid` : intercepter seulement FL serait-il plus léger ?
  - la « Secure Input » (`IsSecureEventInputEnabled`).
- **Où :**
  - documentation Apple ;
  - messages de Quinn « The Eskimo! » sur les Developer Forums (TCC, event taps) ;
  - code de Hammerspoon et de Karabiner.
- **Rendu :** un audit de `EventTap.swift`, et un diff si un défaut est prouvé.

### P1 — Mémoire et processeur de l'interface SwiftUI

**P1.5 — Les +25 Mo qui restent après le créateur, et les 54 Mo de la fenêtre**
- **Quoi :**
  - ce que SwiftUI et AppKit gardent après la fermeture d'un `NSHostingController` : AttributeGraph, caches de
    texte, de symboles SF et de couleurs, `NavigationSplitView` ;
  - les caches fragmentés de malloc (`malloc_zone_pressure_relief`) ;
  - comment le prouver **sur la CI, sans interface** : `leaks --atExit`, `heap`, `vmmap --summary`, `footprint`,
    `MallocStackLogging=lite` + `malloc_history`, `xcrun xctrace record --template Allocations`.
- **Où :**
  - WWDC24 « Analyze heap memory », WWDC21 « Detect and diagnose memory issues », WWDC23 « Demystify SwiftUI
    performance », WWDC25 « Optimize SwiftUI performance with Instruments » ;
  - pages de manuel de `footprint`, `heap` et `leaks` ;
  - billets techniques sur la rétention de `NSHostingView`.
- **Comment :** pas de correctif sans preuve.
  1. Propose d'abord les commandes à ajouter à `scripts/mesure-interface.sh` pour identifier les objets qui
     restent, et ce que chaque résultat prouverait.
  2. Seulement ensuite, les corrections candidates, classées par probabilité.
- **Rendu :**
  - un diff du script de mesure ;
  - les hypothèses classées ;
  - pour chaque hypothèse, sa correction et le gain attendu.

**P1.6 — Listes « en cartes » paresseuses**
- **Quoi :** existe-t-il sous macOS 26/27 une façon native d'obtenir, dans une `List` paresseuse, l'aspect
  « sections arrondies » des Réglages Système ? Pistes : styles de liste et de section, `listRowBackground`,
  `containerBackground`. Il faut un repli pour macOS 13 à 15. Aujourd'hui, `CardRowBackground` dans
  `GlassStyle.swift` dessine chaque ligne à la main.
- **Où :** documentation SwiftUI (List, ListStyle, Section), WWDC25 « Build a SwiftUI app with the new design ».
- **Rendu :** une recommandation, et un diff de `GlassStyle.swift` / `EditorView.swift` si c'est plus simple ou
  plus léger.

### P2 — Créateur de macros, incréments 3 à 6

Base-toi sur `docs/contexte/03-architecture-code.md` §3 et sur `01-outils-macro.md`.

**P2.1 — Incrément 3 : conditions, répétitions, pas à pas, arrêt immédiat**
- **Quoi :**
  - des blocs « Si » sur des conditions **sans écran** : fenêtre ou dialogue de FL présent, piste armée ou REC
    allumé par le lien MIDI, FL au premier plan ;
  - « Répéter » et « Tant que » ;
  - un mode pas à pas, comme le débogueur de Keyboard Maestro ou le mode manuel de PMC ;
  - l'arrêt immédiat par Échap via l'interception, avec relâchement de toutes les touches modificatrices.
- **Où :**
  - wiki Keyboard Maestro : *Macro Debugger*, *Pause Until*, *If Then Else* ;
  - documentation de PMC (*Playback*) ;
  - AutoHotkey v2 (`WinWait`, valeurs de retour) ;
  - Apple Shortcuts (blocs « Si »).
- **Rendu :**
  - la conception UX (comment ça se lit en français dans la liste) ;
  - les modifications de `MacroModel`, `MacroRegistry`, `MacroInterpreter` et de l'inspecteur ;
  - des tests XCTest sur l'interpréteur à effets factices.

**P2.2 — Incrément 4 : protocole MIDI enrichi et questions d'état**
- **Quoi :** les paramètres et interrogations d'état décidés en P0.1 (piste armée ? REC ? piste sélectionnée ?),
  sous forme de blocs.
- **Rendu :** le code Swift et Python, avec les tests (y compris `Tests/python/test_device_flshortcut.py`).

**P2.3 — Incrément 5 : enregistreur**
- **Quoi :**
  - capturer les actions de l'utilisateur dans FL (interception en écoute seule) et les transformer en blocs
    **nommés** : une touche connue de FL devient « Ouvrir le Mixer », un menu devient un chemin de menu, une pause
    devient « Attendre que… » ;
  - un écran de relecture « Voici ce que j'ai compris » ;
  - la confidentialité : jamais de texte tapé en clair.
- **Où :** comment Keyboard Maestro, PMC, Jitbit et Automator « Watch Me Do » enregistrent, et leurs défauts
  connus.
- **Rendu :** la conception, plus `MacroRecorder.swift` et `RecordingCompiler.swift` (noms prévus dans
  l'architecture), avec des tests.

**P2.4 — Incrément 6 : galerie de modèles utiles aux beatmakers**
- **Quoi :** les 15 macros FL que les utilisateurs Mac réclament le plus.
- **Où :**
  - Reddit r/FL_Studio et le forum Image-Line ;
  - les profils Stream Deck et Metagrid pour FL ;
  - les macros Keyboard Maestro pour FL ;
  - les vidéos « FL Studio workflow tips ».
- **Comment :** pour chaque macro, les étapes exactes (touches et menus de FL **sur Mac**, vérifiés dans le
  manuel).
- **Rendu :** un classement argumenté, et le code des modèles dans `MacroTemplates.swift`, avec des tests.

### P2 — Interface Liquid Glass et accessibilité

**P2.5 — Conformité Liquid Glass (macOS 26/27)**
- **Quoi :**
  - comparer `GlassStyle.swift` et les vues aux règles d'Apple : verre sur la couche de navigation et jamais sur
    le contenu, pas de verre sur du verre, `GlassEffectContainer`, `glassEffect`, `buttonStyle(.glass)`, barres
    d'outils, barres latérales, `backgroundExtensionEffect`, `scrollEdgeEffect` ;
  - ce qui a changé dans macOS 27 ;
  - le coût en mémoire et en processeur.
- **Où :**
  - Human Interface Guidelines (*Materials*, *Liquid Glass*) ;
  - WWDC25 219 « Meet Liquid Glass », 356 « Get to know the new design system », 323 « Build a SwiftUI app with
    the new design », 310 « Build an AppKit app with the new design » ;
  - les sessions WWDC26 correspondantes.
- **Rendu :** une liste d'écarts classés, et des diffs avec repli pour macOS 13 à 15.

**P2.6 — Accessibilité de l'app**
- **Quoi :**
  - VoiceOver en français sur la liste des étapes, la palette et l'inspecteur ;
  - la navigation au clavier dans le créateur ;
  - « Réduire la transparence », « Réduire les animations » et le contraste.
- **Où :** HIG *Accessibility*, documentation SwiftUI sur l'accessibilité.
- **Rendu :** un audit, et des diffs.

### P3 — Qualité, tests, livraison

**P3.1 — Tests**
- **Quoi :**
  - étendre le faux FL (`FakeFL.swift`) : plus de menus, retards aléatoires, boîtes qui tardent ;
  - des tests d'instantanés SwiftUI sous macOS, sans dépendance (`ImageRenderer`, macOS 13+) ;
  - ce qui est possible en tests d'interface pour un exécutable SwiftPM sur la CI GitHub, où les machines
    hébergées n'ont pas l'autorisation Accessibilité ;
  - XCTest, ou Swift Testing si c'est compatible avec la CI.
- **Rendu :** des propositions, et le code des tests.

**P3.2 — Signature, notarisation, mises à jour**
- **Quoi :**
  - signer la CI avec une identité **stable**, pour que l'autorisation Accessibilité survive aux mises à jour.
    C'est le plus gros irritant actuel ;
  - Developer ID et `notarytool`, Hardened Runtime, et les droits nécessaires à une interception clavier ;
  - pkg ou dmg ;
  - les mises à jour automatiques (Sparkle 2 : EdDSA, appcast) et leur coût au repos.
- **Où :** documentation Apple (*Notarizing macOS software*), Developer Forums, documentation de Sparkle.
- **Rendu :**
  - la marche à suivre pour le propriétaire : les secrets GitHub à créer (sans jamais écrire de secret) ;
  - les modifications de `.github/workflows/build.yml` et de `build.sh`.

**P3.3 — Mode Swift 6**
- **Quoi :** le coût et le bénéfice d'un passage au mode de langage Swift 6 (concurrence stricte) avec Xcode 26,
  en gardant macOS 13, et la liste des avertissements probables (`@MainActor`, `Sendable`).
- **Rendu :** une recommandation (oui, non ou plus tard), avec une estimation de l'effort.

---

## 6. Forme exacte de ton rendu

Un seul document Markdown, en français, avec ces parties dans cet ordre :

**A. Résumé pour le propriétaire.** Dix lignes au plus, sans jargon : ce qui va changer pour lui, par ordre
d'importance.

**B. Plan priorisé.** Un tableau avec ces colonnes :
`# | changement | chantier | gain attendu (vitesse / fiabilité / mémoire / confort) | risque | effort | dépend de`.

**C. Résultats de recherche.** Une section par chantier, avec :
- les questions et les réponses ;
- pour chaque affirmation, son niveau : `[vérifié : source]`, `[déduit]` ou `[à tester sur le vrai FL/Mac]` ;
- les sources (URL, date, version).

**D. Code.** Un bloc par changement, qui contient :
1. Le **titre** et le chantier.
2. Le **fichier** (chemin exact) et le **SHA** de base de la branche `claude/relaxed-mayer-ndguzv`.
3. Un **diff unifié applicable** par `git apply` (contexte de 3 lignes), ou le fichier complet s'il est nouveau.
   Pas de « … » ni de « reste inchangé » : du code complet.
4. Les **tests** XCTest (fichier dans `Tests/FLShortcutTests/`) qui prouvent le changement.
5. La **vérification** : quel test, quelle colonne de `scripts/mesure-interface.sh`, quel essai sur le faux FL
   (`--selftest-macro`, `--selftest-preset`) ou quel geste sur le vrai FL.
6. Les **coûts** : mémoire, processeur, latence ajoutée ou gagnée.
7. Une **liste de contrôle** des contraintes de la section 3 : pour chacune, « respectée », ou pourquoi elle ne
   s'applique pas.

**E. Options à tester par l'utilisateur.** Tout ce qui toucherait une étape validée (contrainte 5) ou que seul le
vrai FL peut trancher. Chaque option a un protocole d'essai court, qui teste une seule chose à la fois.

**F. Questions ouvertes et hypothèses non vérifiées.**

---

## 7. Règles de qualité pour le code

- **Ne compile pas en imagination.** N'utilise que des API dont tu as lu la documentation, et cite leur
  disponibilité. Si tu n'es pas sûr d'une signature, dis-le dans le bloc.
- **Écris dans le style du fichier modifié** : noms, densité de commentaires, commentaires en français. Lis le
  fichier avant de le modifier.
- **Changements minimaux.** Pas de refactorisation qui ne sert pas le chantier, pas de renommage gratuit.
- **Plateforme :** pas de nouvelle dépendance (contrainte 7), pas de `@Observable`, macOS 13 minimum.
- **Tout s'arrête à la fin de la macro.** Ce qui tourne pendant une macro (observateurs, ports MIDI, minuteries)
  s'arrête quand elle se termine.
- **Aucun secret.** Pas de secret, de clé ni d'identifiant dans le code ou le document.
- **Compilation.** Indique en tête de la partie D que **rien n'a été compilé** de ton côté. Ce n'est pas un
  défaut : la vérification se fait sur la CI macOS du projet.

---

## 8. Avant d'envoyer, vérifie

- [ ] J'ai lu `docs/contexte/HISTORIQUE.md`, et je ne propose rien que l'historique a déjà essayé et écarté (ou
      je dis pourquoi ce serait différent cette fois).
- [ ] Aucune proposition n'utilise la capture d'écran ni ne modifie une étape validée (sauf en partie E).
- [ ] Chaque API citée a sa source et sa disponibilité.
- [ ] Chaque diff indique son fichier et son SHA de base, et il est complet.
- [ ] Chaque changement a sa vérification et ses coûts.
- [ ] Le résumé A est compréhensible par un musicien non développeur.
- [ ] Windows est hors sujet et n'apparaît pas.
