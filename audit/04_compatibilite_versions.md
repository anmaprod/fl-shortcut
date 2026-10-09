# Audit 04 : compatibilité de FL Remap avec les versions de FL Studio

*Audit du 8 octobre 2026. Périmètre : script `Resources/device_FLRemap.py`, actions v2 (variable `ACTIONS` de la maquette), app Mac.*

Sources principales :
- stubs officiels de l'API (IL-Group/FL-Studio-API-Stubs, dépôt cloné et analysé localement, 503 fonctions avec leur version d'API minimale) ;
- leur historique Git (MaddyGuthridge/FL-Studio-API-Stubs, 784 commits), qui contient une table « version FL → API » retirée en 2024 ;
- manuel Image-Line : pages *MIDI scripting*, *What's New* 20/21/24/25/26, *Updating*, *Installation files*, *MIDI settings*, *Shortcuts* ;
- forum Image-Line.

Légende de fiabilité :
- ✅ **confirmé** par une source officielle ou par les stubs ;
- 🟡 **déduit**, par recoupement de dates ou de fonctions ;
- ❓ **non vérifié** : à tester sur une vraie installation.

---

## 0. Résumé exécutif

1. **Le scripting Python n'existe qu'à partir de FL 20.7** (22 juin 2020, API 1) ✅. Avant cette version, seul le mode (a) « Touche de FL » est possible. Une piste existe sans Python : émuler un **Mackie Control (MCU)**, voir §2.
2. **Le numéro d'API n'est pas la version de FL.** Le script doit lire `general.getVersion()` au démarrage, puis tester chaque fonction avec `hasattr`/`getattr`. Il ne doit jamais se fier uniquement à une table version FL → API.
3. **27 des 33 actions v2 marchent dès l'API 1** (FL 20.7), directement ou via `transport.globalTransport(FPT_…)`. Six actions demandent une API plus récente :

   | Action | Fonction | API min | FL (approx.) |
   |---|---|---|---|
   | Cloner le pattern | `patterns.clonePattern` | 25 | 21.0.3 |
   | Bypass des effets | `mixer.enableTrackSlots` | 19 | 20.9.1 |
   | Master en mono | `mixer.setTrackStereoSep` | 12 | ≈ 20.8.2–20.8.4 |
   | Preset suivant | `plugins.nextPreset` | 10 | 20.8.1 |
   | Quantize rapide | `channels.quickQuantize` | 9 | ≈ 20.8 |
   | Instrument suivant (propre) | `channels.selectOneChannel` | 8 | ≈ 20.7.3 |

   Pour l'instrument suivant, un repli `FPT_ChannelJog` existe dès l'API 1.
4. **Le handshake via `device.midiOutMsg` existe dès l'API 1** ✅. Il exige une **sortie MIDI appariée** : même numéro de port en *Input* et en *Output*. Aujourd'hui, l'app ne crée qu'une *source* CoreMIDI : il faut **ajouter une destination virtuelle**.
5. **Python embarqué :** 3.6 sous FL 20.7–20.8, puis 3.9 à partir de ≈ 20.8.4/20.9 🟡. La version actuelle n'est pas confirmée. **Il faut écrire en Python 3.6 strict**, sans I/O fichier et avec un minimum de modules de la bibliothèque standard.

---

## 1. Correspondance version FL ↔ version d'API Python

Aucune table officielle complète n'existe. Le manuel affiche une colonne « Version » par fonction, mais sans la relier aux versions de FL. La table ci-dessous croise quatre sources :

- **(S)** la table `target_version.py` des anciens stubs, seule correspondance chiffrée « officieuse » : `"20.8.4": 15`, `"20.9.2": 20`, `"21.0.0": 22`, `"21.0.3": 28` ;
- **(W)** les *What's New* : fonctions ajoutées par version ;
- **(A)** la version « Included since API N » des fonctions correspondantes ;
- **(D)** la date de publication des stubs.

| Version FL | Sortie | API (`general.getVersion()`) | Fiabilité | Repères |
|---|---|---|---|---|
| ≤ 20.6 | 2018–2020 | — (pas de Python) | ✅ | 20.7 introduit le scripting (W, communiqué IL du 28-04-2020) |
| 20.7 | 22 juin 2020 | **1** | ✅ | callbacks et fonctions « API 1 » |
| 20.7.1 | 29 juin 2020 | 2–4 | 🟡 | « defined state for some functions » → paramètres `value` (API 2, ex. `mixer.muteTrack`), `ui.setFocused` (2) |
| 20.7.2 | 18 août 2020 | 5 | 🟡 | `channels.selectedChannel` (API 5) |
| 20.7.3 | 26 oct. 2020 | 7–8 | 🟡 | `selectOneChannel`, pitch range, infos plugin (API 8), `device.getName` (7) |
| 20.8 | 14 déc. 2020 | 8–9 | 🟡 | `plugins.setParamValue` (8), `quickQuantize` (9) |
| 20.8.1 | 1 fév. 2021 | 10 | 🟡 | `plugins.nextPreset/prevPreset` (10) |
| 20.8.2 / 20.8.3 | mars 2021 | 11–12 | 🟡 | `setTrackStereoSep` (12), `getPluginName(userName)` (12, mais annoncé en 20.8.4) |
| **20.8.4** | 31 août 2021 | **15** | ✅ (S) | natif Apple Silicon |
| 20.9 | 15 déc. 2021 | 16–17 | 🟡 | `OnProjectLoad`, `OnDirtyChannel` (16), `OnFirstConnect` (17) |
| 20.9.1 | 22 fév. 2022 | 18–19 | ✅ (A+D) | `getPadInfo`, `getMasterSync` (19) ; stubs « features from FL 20.9.1 » |
| **20.9.2** | 4 avr. 2022 | **20** | ✅ (S) | `showNotification`, `showGraphEditor(useGlobalIndex)` (20) |
| **21.0** | 6 déc. 2022 | **22** (21 en bêta) | ✅ (S) | `getPerformanceModeState` (21) |
| 21.0.1 / 21.0.2 | déc. 2022–janv. 2023 | 23–24 | 🟡 (D) | `isPatternDefault` (23), `ui.setSnapMode` (24) |
| **21.0.3** | 12 avr. 2023 | **28** | ✅ (S) | `clonePattern`, `getDeviceID` (25), `setActiveTrack` (27), step edit (28) |
| 21.1 | 8 août 2023 | ≈ 29 | 🟡 (D) | stubs v29 du 29-08-2023, `general.safeToEdit` (29) |
| 21.2 / 21.2.x | oct.–déc. 2023 | ≈ 30–33 | 🟡 | `soloChannel(value)` (note *30 du manuel), `useGlobalIndex` partout (33, stubs v33 de janv. 2024) |
| 2024 (= 21.3) | 26 juin 2024 | ≈ 35–37 | 🟡 (D) | EQ mixer (35), `setRouteToLevel` (36) ; stubs v36 « latest beta » (mai 2024), v37 (juil. 2024) |
| 2024.2 | 28 nov. 2024 | ≈ 37–38 | ❓ | — |
| 2025 (25.1) | mi-2025 | ≈ 38–39 | ❓ | — |
| 2025.2 → 25.2.4 | nov. 2025 → 5 fév. 2026 | ≈ 39 → **40** | 🟡 | `playlist.selectTool` = version 40 dans le manuel, ajoutée en 25.2.4 (« select Tools ») |
| 2026 (26.1.x) | 2 juil. 2026 → | 41–45 | 🟡 | `setPatternLength`, swing, `clearPattern`… |
| **26.1.7** | 28 sept. 2026 | **45** | ✅ | rapport réel « MIDI scripting version 45 » sur FL 26.1.7 build 5653 |

> Note de nommage : FL est passé de « 21.x » à des noms par année. FL 2024 = 21.3, puis 2024.2. Depuis FL 2025, la numérotation interne est 25.x, puis 26.x pour FL 2026. Pour l'affichage, utiliser `ui.getVersion(0..3)` (majeure, mineure, révision, build ; API 7 pour le paramètre `mode`), et `ui.getVersion()` sans argument pour le texte complet « Producer Edition v… ».

---

## 2. Versions sans scripting Python (FL ≤ 20.6, FL 12, FL 11…)

### Ce qui reste possible

| Mécanisme | Disponibilité | Utilité pour FL Remap |
|---|---|---|
| **Mode (a) : raccourcis clavier** | toutes versions | ✅ seul mode garanti. Sur Mac, seulement FL 20.0+ en natif. |
| **« Link to controller » / Multilink** (clic droit sur un bouton ou potard → *Link to controller*, option *Global*) | toutes versions | ⚠️ Fonctionne pour les **paramètres automatisables** : volume ou mute d'une piste précise, tempo, etc. Il faut lier à la main, un CC à la fois, et la cible est fixe (une piste précise, pas « la piste sélectionnée »). Pas de lien possible pour Play, Stop ou Record (forum IL, 2015). Utilisable en mode expert seulement. |
| **Mackie Control Universal (MCU)** : *Controller type* = « Mackie Control Universal » | intégré dans FL 8 → 25.x, **remplacé par un script Python en FL 2026** (W 26.1 bêta 1) | 🟡 Piste prometteuse : FL Remap peut **émuler un MCU** sur un 2ᵉ port virtuel « FL Remap MCU » (notes MIDI canal 1). Voir la table ci-dessous. |
| **MMC** (MIDI Machine Control, SysEx `F0 7F … 06 cmd F7`) | évoqué « supporté depuis FL 8 » sur le forum, sans confirmation dans le manuel actuel | ❓ À tester. Ne couvrirait que Play, Stop, Record et Locate. |
| CC « universels » fixes | **n'existent pas** : le manuel *MIDI settings* ne donne aucune table de CC fixes | ✗ |
| Anciens scripts `.txt`/`.fsc` | pas de format de script utilisateur documenté avant 20.7. Les pilotes étaient compilés en interne. | ✗ |

### Émulation MCU (protocole Mackie standard, à valider dans FL)

Chaque action est un Note On à vélocité 127 suivi d'un Note Off, sur le canal 1. Numéros de notes du protocole Mackie : Play 0x5E, Stop 0x5D, Record 0x5F, Click 0x59, Cycle 0x56, Marker 0x54, Save 0x50, Undo 0x51, Rec-arm 0x00–0x07, Solo 0x08–0x0F, Mute 0x10–0x17, Select 0x18–0x1F, Channel ◀▶ 0x30/0x31, Bank ◀▶ 0x2E/0x2F, F1–F8 0x36–0x3D.

**Ce qu'on ne sait pas encore ❓ :** comment FL traduit chacun de ces boutons. Les pages MCU du manuel n'ont pas pu être lues. Il faut le vérifier sur FL 12, 20.6 et 2025.

**Recommandation :** en faire un mode (c) optionnel, « Compatibilité anciennes versions (Mackie) », livré seulement après test. Il resterait secondaire derrière le mode (b) Python.

### Mac avant FL 20

- FL 11 (2013) puis FL 12 (2015–2018) existaient en **bêta « CrossOver wrap »** : l'appli Windows dans Wine, aujourd'hui arrêtée.
- Le processus visible est alors un wrapper Wine/CrossOver. `flStudioIsFrontmost()` ne le reconnaît pas forcément, et les raccourcis passent par la traduction clavier de Wine.
- **Recommandation : déclarer ces versions non prises en charge.** Afficher « FL Studio 20 ou plus récent requis sur Mac ».

---

## 3. Mac

| Point | Détail | Fiabilité |
|---|---|---|
| Natif Mac 64 bits | depuis **FL 20.0 (7 mai 2018)** | ✅ (W) |
| Apple Silicon | Rosetta en 20.8.2 ; **ARM natif en 20.8.4** | ✅ (W) |
| Nom de l'app | le manuel actuel indique `/Applications/FL Studio.app`. Les versions majeures ont aussi existé sous un nom versionné : « FL Studio 20.app », « FL Studio 21.app » (les stubs citent `FL Studio 21/Contents/Resources/FL/…`). IL recommande de **renommer l'ancienne app** pour garder deux versions. | ✅ / 🟡 |
| Bundle ID | aucune source publique trouvée. Probablement de la forme `com.image-line.*`. | ❓ |
| Dossier Hardware | `~/Documents/Image-Line/FL Studio/Settings/Hardware/<dossier>/device_<nom>.py` | ✅ (stubs, manuel) |
| User data folder | dans `~/Documents/Image-Line/` depuis FL 20, identique Mac et Windows. Avant FL 20, les données étaient dans le dossier d'installation (sans importance : pas de Python). | ✅ (*Updating*) |
| Dossier utilisateur déplacé | *Options › File settings › User data folder* : FL migre les fichiers vers le nouvel emplacement. Le dossier doit être **local** (pas iCloud ni OneDrive). L'emplacement n'est documenté nulle part (plist sur Mac, registre sur Windows). | ✅ / ❓ |
| Bibliothèque Python partagée | `/Library/Application Support/Image-Line/Shared/Python/Lib` | ✅ (stubs) |
| FL comme plugin VST/AU (depuis 20.5) | l'app au premier plan est l'hôte (Logic…) et non FL. Les remaps ne s'appliquent pas, ce qui est le bon comportement. | ✅ |

### Conséquences pour le code actuel

- **`EventTap.flStudioIsFrontmost()`** teste `name.contains("FL Studio")`, ce qui renvoie vrai aussi pour **« FL Studio Mobile »** : l'appli iOS tourne sur Mac Apple Silicon et existe aussi sur macOS. Il faut exclure `Mobile` et `Remote`, ou mieux, filtrer sur le bundle ID après l'avoir relevé sur une vraie installation.
- **Connaître la version de FL sans le script :** lire `NSRunningApplication.bundleURL` → `Bundle(url:)?.infoDictionary["CFBundleShortVersionString"]`. Cela permet de griser les actions dès le lancement, avant le handshake, et même en mode (a).
- **`FLScriptInstaller`** vérifie seulement l'existence de `Documents/Image-Line/FL Studio`. À améliorer :
  1. vérifier aussi `Settings/Hardware` ;
  2. si le dossier est absent, proposer le sélecteur (déjà fait) et mémoriser le choix ;
  3. rappeler qu'il faut **redémarrer FL**, car les scripts sont lus au lancement ;
  4. ne rien installer, et le dire, si la version FL détectée est < 20.7.

---

## 4. Windows (pour un futur portage)

| Point | Détail | Fiabilité |
|---|---|---|
| Exécutables | `FL64.exe` (64 bits). `FL.exe` = version 32 bits, depuis FL 12. | ✅ (KB IL n°526) |
| 32 bits | plus proposé à l'installation **à partir de 20.9** | 🟡 (forum IL, réponse support tronquée) |
| Dossier d'installation | `C:\Program Files\Image-Line\FL Studio N`. Anciennes versions : `Program Files (x86)`. Les versions majeures s'installent côte à côte (« 21 vs 2024 »), donc N = 20, 21, 2024, 2025… | ✅ (*Updating*) |
| User data | `%USERPROFILE%\Documents\Image-Line\FL Studio\…`. Attention aux Documents redirigés vers OneDrive. | ✅ |
| Port MIDI virtuel | Windows n'a pas de port virtuel natif historique. Il faut loopMIDI (tiers) ou les loopbacks de Windows MIDI Services (Windows 11 récent). | ❓ |
| Clavier | hook bas niveau + filtre sur le processus `FL64.exe` ou `FL.exe` | — |

---

## 5. Éditions et version d'essai

- **MIDI scripting :** aucune page d'IL ne le réserve à une édition. La comparaison des éditions classe la « MIDI controller support » dans les 4 éditions (Fruity, Producer, Signature, All Plugins). Le scripting, cœur de cette fonction, est **a priori disponible partout** 🟡.
- **Fruity Edition :** pas d'enregistrement audio dans la Playlist ✅. Les actions *Armer la piste* (arm d'une piste Mixer pour l'audio) et les options d'enregistrement audio y sont **sans effet utile**. Détection : `ui.getVersion()` (texte) commence par « Fruity Edition ».
- **Version d'essai :** mêmes fonctions qu'All Plugins ✅. *Sauvegarder* marche, mais l'essai illimité **ne peut pas rouvrir** un projet sauvegardé ✅. Aucune limite connue sur le scripting ❓. L'essai limité dans le temps peut sauvegarder et recharger.

---

## 6. Table action → fonction → API minimale → repli

Conventions :
- `GT(x)` = `transport.globalTransport(midi.x, 1)`, API 1, avec la constante récupérée par `getattr(midi, "x", valeur)` ;
- `T` = `mixer.trackNumber()` (piste Mixer sélectionnée, API 1) ;
- `C` = `channels.selectedChannel()` (API 5), avec repli sur `channels.channelNumber()` (API 1).

Le raccourci clavier natif indiqué sert de repli en mode (a). Il vient du manuel *Shortcuts* actuel, où Ctrl correspond à ⌘ et Alt à ⌥ sur Mac.

### Composition

| Action | Fonction(s) (meilleure) | API min | Repli ancienne API | Repli clavier (mode a) | Remarques |
|---|---|---|---|---|---|
| Nouveau pattern | `patterns.findFirstNextEmptyPat(midi.FFNEP_DontPromptName)` puis `ui.showWindow(widPianoRoll)` | 1 | — | F4 / Ctrl+F4 (l'une ouvre le dialogue de nom) ❓ | `jumpToPattern(patternCount()+1)` crée aussi un pattern, mais la doc le déconseille |
| Cloner le pattern | `patterns.clonePattern()` | **25** (21.0.3) | **aucun** | pas de raccourci documenté | Ferme le Piano Roll (doc). Le comportement a changé en 26.1.1 (index de destination) et en 26.1.6. → **griser avant API 25** |
| Pattern suivant / précédent | `patterns.jumpToPattern(patternNumber()±1)` borné à `[1, patternCount()]` | 1 | `GT(FPT_PatternJog)` avec ±1 | + / − du pavé numérique | déjà dans le script |
| Instrument suivant | `channels.selectOneChannel((C+1) % channelCount())` | **8** | `GT(FPT_ChannelJog)` (API 1), ou `channels.selectChannel` (API 1) | ↓ dans le Channel Rack | En API ≥ 33, respecte les groupes de canaux (`useGlobalIndex`) |
| Grille suivante (snap) | `ui.snapMode(1)` (relatif) | 1 | `GT(FPT_SnapMode)` | — | `ui.setSnapMode` (absolu) = API 24. Comportement « fenêtre active ou global » à tester ❓ |
| Quantize rapide | `channels.quickQuantize(C)` | **9** | aucun | Piano Roll : Ctrl/Cmd+⌥+Q selon le manuel actuel ❓ | → griser avant API 9, ou basculer sur le raccourci |
| Preset suivant | `plugins.nextPreset(index, slot)`. Plugin ciblé via `ui.getFocused(widPluginGenerator)` → `index = C`, ou via `ui.getFocused(widPluginEffect)` → `mixer.getActiveEffectIndex()` (API 25), sinon décoder `ui.getFocusedFormID()` (API 13) : piste = id // 4194304, slot = (id % 4194304) // 65536 | **10** | `GT(FPT_Next)` quand un plugin a le focus ❓ | aucun | module `plugins` à importer **paresseusement** (première fonction : API 8). `useGlobalIndex` = API 26 |
| Tap tempo | `GT(FPT_TapTempo)` | 1 | — | aucun documenté | |

### Enregistrement

| Action | Fonction(s) | API min | Repli | Clavier | Remarques |
|---|---|---|---|---|---|
| REC | `transport.record()` | 1 | `GT(FPT_Record)` | R | |
| Armer la piste | `mixer.armTrack(T)` (bascule) | 1 | — | aucun | sans effet utile en Fruity ; état lisible via `mixer.isTrackArmed` |
| Décompte | `GT(FPT_CountDown)` ; état : `general.getPrecount()` | 1 | — | Ctrl/Cmd+P | |
| Enregistrement en boucle | `GT(FPT_LoopRecord)` | 1 | — | aucun | |
| Attendre une note | `GT(FPT_WaitForInput)` | 1 | — | Ctrl/Cmd+I | |
| Métronome | `GT(FPT_Metronome)` ; état : `general.getUseMetronome()` | 1 | — | Ctrl/Cmd+M | déjà dans le script |
| Poser un marqueur | `arrangement.addAutoTimeMarker(transport.getSongPos(midi.SONGLENGTH_ABSTICKS), "Bonne prise")` | 1 (+3 pour le `mode` de `getSongPos`) | `GT(FPT_AddMarker)` | Alt/Opt+T dans la Playlist | En mode Pattern, `getSongPos` donne la position dans le pattern : n'agir qu'en mode Song (`transport.getLoopMode()`) |
| Lecture / Pause | `transport.start()` (bascule) | 1 | `GT(FPT_Play)` | Espace | |

### Mix

| Action | Fonction(s) | API min | Repli | Clavier | Remarques |
|---|---|---|---|---|---|
| Mute de la piste | `mixer.muteTrack(T)` | 2 | `mixer.enableTrack(T)` (API 1, même effet selon les stubs) | aucun | |
| Solo de la piste | `mixer.soloTrack(T)` (bascule) | 1 | — | S dans le Mixer | Les paramètres `value` et `mode` viennent plus tard : n'appeler qu'avec l'index pour les vieilles versions |
| Retirer tous les solos | boucle `for i in range(mixer.trackCount())` : si `mixer.isTrackSolo(i)`, alors `mixer.soloTrack(i)` (bascule). Idem pour les canaux avec `channels.isChannelSolo` / `soloChannel`. | 1 | — | aucun | En 21.2+, `soloChannel` accepte `value` ; ne pas l'exiger |
| Bypass des effets | `mixer.enableTrackSlots(T, not mixer.isTrackSlotsEnabled(T))` | **19** (20.9.1) | aucun fiable | aucun | **Toujours passer `value` explicitement** : bug documenté, sans `value` les slots sont *coupés* au lieu d'être basculés ; corrigé en 25.1.99. → griser avant API 19 |
| Master en mono | `mixer.setTrackStereoSep(0, -1.0)` (−1 = 100 % centré, donc mono). Mémoriser l'ancienne valeur (`getTrackStereoSep`) pour la remettre au 2ᵉ appui. | **12** | aucun | aucun | Modifie le projet (état sauvegardé, undo). Afficher un rappel avec `ui.setHintMsg`. → griser avant API 12 |
| Piste suivante | `mixer.setTrackNumber(T+1, midi.curfxScrollToMakeVisible)` | 1 | `GT(FPT_TrackJog)` | aucun | Borner à `trackCount()-2` : la dernière piste est la « Current », bug corrigé en 26.1.4. `mixer.setActiveTrack` = API 27 |
| Volume ±0,5 dB | lire en dB avec `mixer.getTrackVolume(T, 1)`, puis viser dB±0,5 par **dichotomie** sur `setTrackVolume(T, v)`, 8 à 10 itérations | 1 | si `getTrackVolume(T, 1)` lève `TypeError` : pas fixe normalisé (≈) | aucun | La courbe du fader n'est pas documentée : ne pas coder de formule en dur |

### Navigation

| Action | Fonction(s) | API min | Repli | Clavier |
|---|---|---|---|---|
| Ouvrir Playlist / Channel Rack / Piano Roll / Mixer / Browser | `ui.showWindow(wid)` + `ui.setFocused(wid)` | 1 (+2 pour `setFocused`) | `showWindow` seul (API 1) | F5 / F6 / F7 / F9 / Alt+F8 |
| Playlist ↔ Mixer | `ui.getFocused(midi.widMixer)` puis l'une des deux | 1 | — | F5 / F9 |
| Annuler / Rétablir | `general.undoUp()` / `general.undoDown()` | 1 | `GT(FPT_Undo)` / `GT(FPT_UndoUp)` | Ctrl/Cmd+Z (bascule annuler/rétablir), Ctrl/Cmd+Alt/Opt+Z (pas à pas) |
| Sauvegarder | `GT(FPT_Save)` | 1 | — | Ctrl/Cmd+S |

> Pour Annuler/Rétablir, l'ordre de l'historique est inversé visuellement depuis FL 21 (doc des stubs). Les fonctions gardent le sens « undo/redo ».

**Rien n'est strictement impossible** dès API ≥ 25. Les vraies impossibilités sont :
- **Cloner** avant API 25 ;
- **Bypass** avant API 19 ;
- **Master mono** avant API 12 ;
- **Preset** avant API 10 ;
- **Quantize** avant API 9 (repli clavier possible) ;
- **mute/solo de clips dans la Playlist**, absent de l'API dans toutes les versions (déjà documenté dans le README).

### Bugs FL connus à contourner

- **`globalTransport` en FL 26.1.0 → 26.1.6** : plantages et gels, corrigés en 26.1.7 (W 22359, 22689, 22725). **Préférer les fonctions dédiées** quand elles existent, par exemple `general.getUseMetronome` + `GT` seulement si nécessaire. Ajouter un avertissement si la version FL lue est dans cette plage.
- **Envoi de SysEx par un script** : gel ou plantage en 26.1.x avant 26.1.4/26.1.7 (W 22414, 22604). **Faire le handshake en CC, pas en SysEx.**
- **`device.midiOutMsg` avec un message invalide** : plante FL jusqu'à 20.9.2 (anciens stubs). Toujours borner les octets à 0–127 et les statuts à 0x80–0xEF.
- **I/O fichier dans `OnMidiMsg`** : `SystemError` sur FL 26.1.7 (API 45). **Aucun accès disque dans le script.**

---

## 7. Pièges de compatibilité du code Python

### 7.1 Métadonnées et emplacement

- `# name=FL Remap` **doit** figurer en tête de fichier (obligatoire) ✅.
- `# url=` doit pointer vers `https://forum.image-line.com/…`, sinon FL redirige vers le forum de scripting. La ligne `# url=` vide actuelle est inutile : la supprimer ou la remplir.
- **Ajouter `# supportedDevices=FL Remap`** : FL lie automatiquement un périphérique de ce nom au script. L'auto-détection existe depuis 20.7.1 ✅. C'est la fin de l'étape manuelle « Controller type » pour la plupart des utilisateurs. Le nom vu par FL dépend de l'OS ❓ : à tester sur Mac (« FL Remap » ou « FL Remap FL Remap » selon CoreMIDI).
- `# receiveFrom=` et `# supportedHardwareIds=` sont inutiles ici. Ce dernier sert à l'identification matérielle, ajoutée en 20.9 ; l'API `device.getDeviceID` est arrivée en API 25.
- Emplacement : `Settings/Hardware/FL Remap/device_FLRemap.py` (le préfixe `device_` est obligatoire) ✅. C'est conforme à l'installateur actuel.

### 7.2 Imports

D'après les stubs, tous les modules existent en API 1, **sauf `plugins`**, dont la plus ancienne fonction date de l'API 8. Les constantes du module `midi` (fichier `.py` livré avec FL) ont aussi été enrichies au fil des versions.

```python
# Imports sûrs (API 1)
import midi, transport, ui, general, mixer, channels, patterns, device

def _opt(name):
    try:
        return __import__(name)
    except ImportError:
        return None

arrangement = _opt("arrangement")
plugins = _opt("plugins")      # absent avant ~20.7.3

def C(name, default):          # constantes midi.* absentes des vieilles versions
    return getattr(midi, name, default)

FPT_CountDown = C("FPT_CountDown", 115)
FPT_LoopRecord = C("FPT_LoopRecord", 113)
```

### 7.3 Détection de version et table de capacités

```python
API = general.getVersion()      # API 1+

def has(mod, fn):
    return mod is not None and hasattr(mod, fn)

CAPS = {}   # id d'action -> bool, calculé une seule fois dans OnInit
CAPS["clone"]  = has(patterns, "clonePattern")
CAPS["bypass"] = has(mixer, "enableTrackSlots") and has(mixer, "isTrackSlotsEnabled")
CAPS["mono"]   = has(mixer, "setTrackStereoSep")
CAPS["preset"] = has(plugins, "nextPreset")
CAPS["quant"]  = has(channels, "quickQuantize")
```

- Combiner `hasattr` et l'API minimale. `hasattr` suffit pour une fonction absente. **Il ne suffit pas pour un paramètre ajouté plus tard** (`value`, `mode`, `useGlobalIndex`) : dans ce cas, envelopper l'appel dans `try/except TypeError` et réessayer avec moins d'arguments.
- Chaque action doit rester entourée du `try/except Exception` déjà présent, qui écrit le message dans `ui.setHintMsg`.

### 7.4 Version de Python et syntaxe à éviter

- Versions observées : **Python 3.6** sous FL 20.7–20.8 (flmidi-101, févr. 2021), puis **3.9.x** (même doc, mise à jour en oct. 2021 ; les stubs exigent 3.9.1 « features from FL 20.9.1 », janv. 2022).
- La version actuelle (FL 2024–2026) **n'est pas confirmée** ❓. Pour la connaître, faire `import sys; print(sys.version)` dans *View › Script output*, et la renvoyer dans le handshake.
- **Cible : Python 3.6.** À proscrire :
  - opérateur morse `:=` (3.8) ;
  - `match/case` (3.10) ;
  - paramètres positionnels seuls `/` (3.8) ;
  - `dict | dict` et `str.removeprefix` (3.9) ;
  - annotations `list[int]` et `X | None` (3.9/3.10) ;
  - `from __future__ import annotations` (3.7) ;
  - `dataclasses` (3.7) ;
  - f-string `{x=}` (3.8).
- Les f-strings simples passent en 3.6, mais le formatage `%` reste plus sûr.
- **Bibliothèque standard tronquée** (beaucoup de modules absents, `_thread` instable) : n'importer ni `os`, ni `json`, ni `threading`, ni `typing`.
- **Pas d'I/O fichier** (cf. bug 26.1.7).
- Garder les callbacks **courts**, moins de 10 ms environ, et rien de lourd dans `OnIdle`.

### 7.5 `OnMidiMsg` vs `OnControlChange`

- Ordre d'appel : `OnMidiIn` → `OnMidiMsg` → callbacks spécialisés (`OnControlChange`, `OnNoteOn`…) **seulement si l'événement n'a pas été marqué `handled`** ✅. Tous existent dès l'API 1.
- Garder `OnMidiMsg` (comme aujourd'hui) et poser `event.handled = True` **pour tout message du canal 16, même inconnu**. Sinon FL le traite en générique : un « Link to controller » de l'utilisateur ou l'Omni preview pourrait le capter.
- Ignorer `data2 == 0` comme maintenant, l'app n'envoyant que 127.

### 7.6 `device.midiOutMsg` et le port de sortie apparié

- `device.midiOutMsg(msg)` : API 1. La forme `(status, channel, data1, data2)` est arrivée en API 2 → **utiliser la forme combinée** `status | (data1 << 8) | (data2 << 16)` ✅.
- Garde-fou : `if device.isAssigned():` (API 1). `device.getPortNumber()` (API 1) donne le port d'entrée, et la sortie doit avoir **le même numéro** ✅ (doc `getPortNumber`, tutoriel, manuel *MIDI settings*).
- **Côté app :**
  - créer une **destination CoreMIDI** (`MIDIDestinationCreate`) nommée « FL Remap » en plus de la source actuelle, avec un `kMIDIPropertyUniqueID` fixe ;
  - documenter dans l'assistant : *Output* « FL Remap » → même *Port* que l'*Input*.
  - Sans cela, pas de handshake : l'app doit alors se rabattre sur la version lue dans le bundle (§3).

---

## 8. Recommandations d'architecture

### 8.1 Script (`device_FLRemap.py` v2)

1. **Démarrage (`OnInit`)** :
   - lire `API = general.getVersion()`, puis `ui.getVersion(0)`, `ui.getVersion(1)` et `ui.getVersion(2)` dans un `try` (le paramètre `mode` date de l'API 7 ; sinon parser `ui.getVersion()`) ;
   - lire l'édition via le texte de `ui.getVersion()` ;
   - calculer `CAPS` une fois ;
   - envoyer le handshake si `device.isAssigned()`.
2. **Dispatch déclaratif.** Chaque action est un tuple `(cc, id, api_min, test_capacité, fonction, repli)` :
   - si la capacité est absente et qu'un repli existe (`GT(...)`), utiliser le repli ;
   - sinon, `ui.setHintMsg("FL Remap : « Cloner » demande FL 21.0.3 ou plus récent")`.
3. **Chargement paresseux** : modules optionnels (`plugins`, `arrangement`) via `_opt`, constantes via `getattr(midi, …, valeur_numérique)`.
4. **Paramètres tardifs** : `try: f(i, v)` puis, sur `TypeError`, `f(i)`.
5. **Handshake en CC**, pas en SysEx (bugs 26.1.x), sur le canal 16 du port de sortie, à l'init puis sur demande de l'app (CC « ping »). Proposition :
   - CC 100 = API (0–127) ;
   - CC 101 = FL majeure (20, 21, 24, 25, 26…) ;
   - CC 102 = mineure ;
   - CC 103 = Python mineur (6, 9, 12…) ;
   - CC 104 = édition (0 Fruity, 1 Producer, 2 Signature, 3 All Plugins/Trial) ;
   - CC 105 à 109 = masque de capacités (7 bits par CC, soit 35 actions) ;
   - CC 110 = version du protocole FL Remap ;
   - CC 111 = fin de trame.
6. **Fenêtre active** : la renvoyer dans `OnRefresh(flags)` quand `flags & midi.HW_Dirty_FocusedWindow` (constante récupérée par `getattr`, valeur 32) :
   - CC 112 = `wid` (0 Mixer, 1 Channel Rack, 2 Playlist, 3 Piano Roll, 4 Browser, 6 plugin d'effet, 7 générateur, 127 autre) ;
   - le calculer avec `ui.getFocused(wid)` (API 1) ;
   - n'envoyer qu'**en cas de changement**.

   L'app peut ainsi appliquer les remaps « Où : Piano Roll / Playlist / Mixer » de la maquette, y compris pour le mode (a).
7. **Constante de protocole** dans le script et dans `Model.swift`. Si le script installé est plus ancien que l'app (CC 110 inférieur), l'app propose « Mettre à jour le script ».

### 8.2 App

1. **Détection de FL sans script :**
   - lire la version dans l'`Info.plist` du bundle de l'app au premier plan ;
   - corriger `flStudioIsFrontmost` (exclure Mobile et Remote ; relever le bundle ID réel et le figer) ;
   - si FL < 20.7, mode (a) seulement ; bannière : « Les actions FL demandent FL Studio 20.7 ou plus récent (tu as 20.6). Les raccourcis-clavier restent disponibles. »
2. **Table de compatibilité embarquée** (`Model.swift`) : `FLAction` → `apiMin`, `flMinLabel` (« FL 21.0.3 »), `fallbackKeystroke` (optionnel), `editionsExcluded`.
   - **Avant handshake** : estimer à partir de la version du bundle et de la table §1.
   - **Après handshake** : **toujours privilégier le masque de capacités renvoyé par le script**. Il fait foi, puisque la table §1 est partiellement déduite.
3. **Dans l'éditeur** (maquette, sélecteur d'action) :
   - action non supportée → ligne **grisée**, avec la pastille « Disponible à partir de FL 21.0.3 » et un lien « Pourquoi ? » ;
   - action supportée seulement par repli → pastille discrète « mode compatible », par exemple « Quantize via raccourci clavier » ;
   - Fruity → *Armer la piste* grisée : « Non disponible dans FL Studio Fruity Edition (pas d'enregistrement audio) » ;
   - profils (« Recommandé ») : à l'import, signaler les lignes non disponibles au lieu de les supprimer.
4. **État de la liaison** (« Relié / FL fermé / Lien inactif » de la maquette) :
   - « Relié » = handshake reçu ;
   - « Script non installé » si FL ≥ 20.7 mais pas de réponse ;
   - « Sortie MIDI non configurée » si l'app voit que FL ouvre la source mais rien n'arrive en retour (pas de handshake) ;
   - afficher l'API et la version FL dans *À propos / Diagnostic*.
5. **Avertissements ciblés :**
   - FL 26.1.0 → 26.1.6 : « mise à jour recommandée vers 26.1.7, bugs de stabilité MIDI scripting » ;
   - Mac FL < 20 (wrapper) : non pris en charge.
6. **Option mode (c) « Mackie »** pour FL 12 → 20.6 : seulement après validation sur une vraie installation (§2).
7. **Portage Windows** (plus tard) : même script ; côté app, port virtuel via loopMIDI ou Windows MIDI Services, hook clavier, détection de `FL64.exe`/`FL.exe`, version lue dans la ressource de version de l'exécutable.

### 8.3 Tests à faire sur de vraies installations

- **FL 20.7.x** (API 1–4) : l'import de `plugins` doit échouer proprement ; les repli `GT` doivent marcher ; `midiOutMsg` en forme combinée.
- **FL 20.8.4 (API 15)** et **20.9.2 (API 20)**.
- **FL 21.0.3 (API 28)** et **FL 2024**.
- **Dernière 2026** : `sys.version`, nom du port vu par FL (`supportedDevices`), bundle ID et nom de l'app.
- **Tous** : vérifier la valeur exacte renvoyée par `general.getVersion()` pour compléter la table §1. C'est le meilleur moyen de lever les 🟡.

---

## 9. Sources

**Officielles Image-Line**
- Manuel, MIDI Scripting : https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/midi_scripting.htm
- What's New FL 20.x : https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/basics_new_20.htm
- What's New FL 21.x : https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/basics_new_21.htm
- What's New FL 2024 : https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/basics_new_24.htm
- What's New FL 2025 : https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/basics_new_25.htm
- What's New FL 2026 : https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/basics_new.htm
- Change log complet : https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/WhatsNew.htm
- Updating (dossiers par version, nom de l'app Mac) : https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/app_update.htm
- Fichiers d'installation (FL64.exe, chemins Mac) : https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/app_flstudioinstallationfiles.htm
- File settings (User data folder) : https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/envsettings_files.htm
- MIDI settings (ports appariés, Controller type) : https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/envsettings_midi.htm
- Raccourcis clavier : https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/basics_shortcuts.htm
- Éditions : https://www.image-line.com/fl-studio-learning/fl-studio-online-manual/html/app_feature.htm et https://www.image-line.com/fl-studio/compare-editions
- Version d'essai : https://support.image-line.com/action/knowledgebase/?ans=94
- FL.exe / FL64.exe : https://support.image-line.com/action/knowledgebase?ans=526
- Annonce FL 20.7 (28-04-2020) : https://www.image-line.com/fl-studio-news/fl-studio-207-released

**Stubs de l'API**
- Documentation : https://il-group.github.io/FL-Studio-API-Stubs/ (dépôt https://github.com/IL-Group/FL-Studio-API-Stubs, commit 9b4c7fa, mai 2026)
- Dépôt d'origine et historique (table `target_version.py`, commits « Update for API version 20 », « Bump API version to 22/24 », « features from FL 20.9.1 ») : https://github.com/MaddyGuthridge/FL-Studio-API-Stubs
- Versions PyPI des stubs (datation des API) : https://pypi.org/project/fl-studio-api-stubs/

**Forum Image-Line**
- Forum MIDI scripting : https://support.image-line.com/redirect/midi_scripting_forum
- 32 bits arrêté à partir de 20.9 : https://forum.image-line.com/viewtopic.php?p=1686283
- Pas de « Link to controller » sur le transport : https://forum.image-line.com/viewtopic.php?p=1062436
- MMC dans FL 8 : https://forum.image-line.com/viewtopic.php?p=80315
- Wrapper CrossOver Mac (FL 12) : https://forum.image-line.com/viewtopic.php?p=1072664

**Communauté (recoupement)**
- FL MIDI Scripting 101, Python 3.6 → 3.9 et modules absents : https://flmidi-101.readthedocs.io/en/latest/scripting/fl_midi_api.html (historique : https://github.com/hobyst/flmidi-101)
- Rapport « MIDI scripting version 45 » sur FL 26.1.7 et bug I/O fichier : https://github.com/Zierax/fl-studio-mcp/issues/1
- Universal Controller Script (exige FL ≥ 21.0.3) : https://github.com/MaddyGuthridge/Universal-Controller-Script
- Configuration Mackie Control dans FL (Native Instruments) : https://support.native-instruments.com/hc/en-us/articles/210305785
