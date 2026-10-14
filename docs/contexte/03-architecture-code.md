# Créateur de macros pour FL Shortcut : état actuel, architecture cible, plan

Aucun fichier modifié. Les références sont au format `Fichier.swift:ligne` (dépôt `/home/user/fl-shortcut`).

## 0. En bref

- **Aujourd'hui**, le seul produit réel est le modèle `autoRecord` « Enregistrement rapide ». Ses étapes sont produites par du code (`MacroLibrary.autoRecordSteps`, Macro.swift:199-220), puis exécutées par un moteur linéaire très durci (`MacroRunner`, 1 402 lignes).
  - Le type `custom` (étapes libres) existe, mais il ne s'écrit qu'à la main dans le JSON et il est refusé à l'import.
- **Ce que je propose :**
  1. Des blocs typés et imbriquables, rangés dans une bibliothèque séparée `macros.json`.
  2. Un registre unique des blocs. Il repose sur un `switch` exhaustif : un bloc oublié est une erreur de compilation.
  3. Un interpréteur récursif séparé des effets, testable sans FL.
  4. « Enregistrement rapide » devient un modèle développé en blocs. Deux garde-fous : un test « golden » et l'essai FakeFL actuel inchangé.
  5. Une extension rétro-compatible du protocole (paramètres signés, requêtes d'état aux réponses signées), sans passer en v3.
  6. Un enregistreur conforme à SEC-07.
- **Plan :** 6 incréments livrables. Le premier ne change rien de visible : c'est une refactorisation surveillée par l'essai de bout en bout.

---

## 1. État actuel

### 1.1 Du raccourci à la macro

1. Le tap clavier, sur son propre thread, appelle `EventTap.handle` (EventTap.swift:166-230), puis `KeyRouter.route`.
   - Un déclencheur de macro produit `RouterEffect.runMacro(Macro)` (KeyRouter.swift:157-159).
   - Les auto-répétitions et le relâchement sont avalés (KeyRouter.swift:116-128).
2. `MacroRunner.shared.start(macro, flPID:)` est appelé **dans le thread du tap** (EventTap.swift:213-224). Il :
   - vérifie que FL est au premier plan ;
   - **revalide la macro sur le thread du tap** (MacroRunner.swift:309) ;
   - prend le verrou `busy` : une seule macro à la fois, `.busy` avale le raccourci, `.refused` rend la touche à FL ;
   - lance `execute` sur la file `fr.flshortcut.macro` (MacroRunner.swift:306-331).
3. À la fin, la notification `.macroFinished` (MacroRunner.swift:319-328) met à jour `AppStatus.lastMacro`. En cas d'échec, `HintPanel.flash` affiche une bulle (FLShortcutApp.swift:148-156).
4. L'index du tap contient une **copie complète** de chaque `Macro` (`ShortcutIndex.RoutedAction.macro(Macro)`, KeyRouter.swift:12-16). `TapConfig` est relu à chaque frappe.

### 1.2 Modèle de données (Macro.swift)

- **`ClickSpot`** (9-26) : une ancre parmi `cursor | window | cursorXWindowY | lastClick`, plus dx/dy bornés à ±5000.
- **`MacroStep`** (28-84) : structure « fourre-tout ».
  - Un `kind` et des champs optionnels (`combo`, `ms`, `spot`, `button`, `titles`, `fallback`, `path`) partagés par 13 types.
  - Le décodage est tolérant champ par champ (60-70).
  - Aucun typage par type d'étape : `titles` sert à la fois à `menu` (titres d'accessibilité) et à `trackMenu` (première lettre de chaque variante).
- **`Macro`** (89-137) : `template ∈ {autoRecord, quickRecord, custom}`, `name`, `presetPath`, `armAndInput`, `startRecording`, `recKey`, `spots` (positions de l'ancien modèle) et `steps` (seulement pour `custom`).
  - `template` est obligatoire. S'il est inconnu, `Remap.macro = nil` : la ligne est gardée, mais la macro est perdue à la sauvegarde suivante (Model.swift:188 et 247 ; test MacroTests.swift:184-194).
  - **Risque :** les étapes sont décodées en `[Lossy<MacroStep>]` (Macro.swift:134-135). Une étape de type inconnu est supprimée sans bruit, et la macro reste exécutable sans elle (par exemple sans une attente).
- **`Remap`** porte la macro en ligne : `kind = .macro`, `macro: Macro?` (Model.swift:125-141). Libellés : `Remap.title/subtitle` (EditorView.swift:1353, 1363).

### 1.3 Les 13 types d'étape et leur exécution (`MacroRunner.perform`, 455-539)

| Type | Paramètres | Exécution | Garde-fous |
|---|---|---|---|
| `key` | `combo` | `postKey` : flagsChanged, keyDown, keyUp, flagsChanged, envoyés au seul processus de FL (`postToPid`) (1158-1174) | liste noire revérifiée (463) ; journal « touche envoyée (masquée) » |
| `delay` | `ms` ≤ 5 s | `pause` par tranches de 50 ms (442-451) | `shouldStop` à chaque tranche |
| `click` | `spot`, `button` | `resolve(spot)` (1135-1149), puis `click(at:)` : le point doit être dans une fenêtre de FL et le test d'accessibilité ne doit pas trouver d'autre app au-dessus (1176-1197) ; `postClick` : curseur déplacé, survol, appui, 50 ms, relâchement par le flux du système (1199-1229) | curseur remis à sa place (585-591) ; `macroClicksToPid` pour l'essai |
| `menu` (quickRecord) | `titles`, `fallback` | `AXMenus.pressPath` par titres d'accessibilité (109-140), sinon clics de secours (471-485) | 0,9 s par élément, 300 nœuds au plus |
| `waitDialog` | `ms` | nouvelle fenêtre ressemblant à une boîte, absente au départ (FL ou service des panneaux) ; mémorisée dans `dialog` (1081-1098) | – |
| `waitDialogClose` | `ms` | `WindowWait.gone(dialog)` ou, à défaut, comptage des fenêtres (1100-1117) ; relevé toutes les 50 ms au-delà de 10 s | – |
| `chooseFile` | `path` | le fichier doit exister et `dialog` être connu ; `PresetChooser.choose` : ⌘⇧G renvoyé jusqu'à « Aller au dossier », ⌘A, chemin tapé par paquets de 12, Entrée, Entrée (PresetChooser.swift:30-124) | touches par le flux du système **seulement si FL est au premier plan** (128-147) |
| `trackMenu` | `titles` (variantes « File\|Fichier ») | voir le détail ci-dessous (599-705) | chaque lettre n'est envoyée que si un menu ouvert par la macro est encore là |
| `armTrack` | – | `armAndRecord` (767-797), voir ci-dessous | – |
| `recordOn` | `combo` (touche REC de secours) | même chemin ; **fusionné** avec un `armTrack` qui le précède (runSteps, 397-401) | REC de secours vérifiée contre la liste noire (788) |
| `selectInput` | – | chemin appris (UserDefaults `macroSpots.v2.input`) : sélecteur relatif au coin haut-droit de la fenêtre de taille apprise, puis `awaitPopup` et `runHops` (858-927, 1046-1077) ; sinon apprentissage guidé (`learnPath` + `ClickRecorder` + `HintPanel`, 983-1029) | jamais de clic si la taille de la fenêtre a changé |
| `feedbackCheck` | – | rapport de larsen lancé en parallèle dès le début (352-358), lu sans attendre (496-510) | – |

Détail de `trackMenu` (599-705) :
- clic droit sur la piste visée ;
- attente de la fenêtre du menu, puis pointeur écarté du menu (`hoverOutside`, 719-735) ;
- lettre F, puis flèche droite si le sous-menu n'apparaît pas ;
- lettre O. Entrée n'est envoyée que si les menus restent ouverts. Ce besoin est appris dans `macroMenuEnterAfterLetter`, une valeur à trois états globale (669-708) ;
- en cas d'échec, Échap seulement sur les menus ouverts par la macro.

Détail de `armAndRecord` (767-797) :
- d'abord le lien MIDI : `MIDILink.runBriefly([39,40])`, avec réveil bref, puis attente de l'accusé de la dernière action (MIDILink.swift:153-196, 484-491) ;
- sinon au clavier : `armViaKeyboard` (805-854) fait menu de piste, S, ←, ↓×5, Entrée (« Arm selected track(s) » ; `armDownCount = 5` lié au menu de FL 2026), puis la touche REC.

### 1.4 Garde-fous communs à toute la macro

- **Au départ :**
  - autorisation d'envoi d'événements vérifiée (360-362) ;
  - bulle cachée de façon synchrone (359) ;
  - piste visée = dernier clic de `TrackMemory` (TrackMemory.swift:22-47 : fenêtre de niveau 0, moins de 10 min, même fenêtre et même taille), sinon le curseur (366-377) ;
  - refus si la première étape est `trackMenu` et que la piste est hors de FL (378-380) ;
  - clavier au repos avant la première étape (384-386, `waitForKeyboardIdle` 552-574).
- **Pendant la macro :**
  - `shouldStop` vérifie que FL est au premier plan et lit Échap par **interrogation** de `CGEventSource.keyState(.combinedSessionState, 53)` (428-439) ;
  - `PresetChooser` envoie lui-même Échap par le flux du système (PresetChooser.swift:77). À vérifier : la lecture d'Échap peut-elle voir notre propre Échap ?
  - tous les événements portent `EventTap.mark` : ni le tap, ni `TrackMemory`, ni `ClickRecorder` ne les retraitent.
- **État partagé entre étapes :** `lastClickPoint`, `dialog`, `trackTarget`, `cursorBeforeBurst`, `popupAX` et le rapport de larsen sont des variables d'instance du singleton, remises à zéro à chaque passage (227-270, 343-351).
- **Journal :** les étapes, fenêtres, clics et tests d'accessibilité sont notés, jamais une frappe ni un chemin (MacroLog.swift:1-4, 57).

### 1.5 Stockage, validation, migrations

- **Stockage :**
  - profil `profile.json` (SecretStore.swift:163), écrit de façon atomique en 0600 (Store.swift:18-41), 0,3 s après chaque modification (288-307) ;
  - positions apprises **hors profil et globales** : UserDefaults `macroSpots.v2.*` (MacroSpots.swift:165-179) et `macroMenuEnterAfterLetter`. Rien n'est propre à une macro.
- **Validation :** `MacroLibrary.validate` (Macro.swift:257-307).
  - 40 étapes au plus ; pause ≤ 5 s ; attentes de 100 ms à 120 s ; budget statique ≤ 180 s avec des coûts forfaitaires (menu 2 s, `trackMenu` 4 s…).
  - touche valide et hors liste noire (Safety.swift:10-42) ; 1 à 3 titres de 80 ou 160 caractères au plus ; chemin de 1 024 caractères au plus, sans caractère de contrôle ; positions finies.
  - Elle est appelée à trois endroits :
    - par l'analyse, en bloquant la ligne (Model.swift:407-413), à chaque `Store.recompute` et pour toutes les macros ;
    - par `start`, sur le thread du tap ;
    - par « Tester » (MacroFields.swift:205).
- **Import :** les macros `custom` sont refusées (Model.swift:559-563).
- **Migrations :**
  - `quickRecord` sans position apprise devient `autoRecord`, une seule fois (Store.swift:105-112) ;
  - macro d'exemple ⌃R ajoutée une fois (Store.swift:115-123 ; Model.swift:473-478) ;
  - profil v1 → v2 avec copie de l'original (Store.swift:172-178) ;
  - anciennes positions v1 ignorées (MacroSpots.swift:4-7).
- **Effets de `recompute` :** `TrackMemory` n'est actif que si une macro `autoRecord` est active. Les ports MIDI à la demande n'existent que si une macro arme la piste ou lance le REC (Store.swift:203-209).

### 1.6 Interface d'aujourd'hui

- **Fiche `EditSheet`** : 500 pt de large, formulaire en colonnes. Un sélecteur de type, puis `MacroFields(macro:)` (EditorView.swift:965-976, 1011, 1016-1018).
- **`MacroFields`** :
  - titre « Enregistrement rapide » écrit en dur (47-52) ;
  - choix du preset : à chaque fois ou fichier .fst fixe (56-72, 245-258) ;
  - deux bascules : armer + entrée, REC (74-78) ;
  - lien avec FL : Installer / Vérifier (83-98, 233-243) ;
  - « Réapprendre » (99-110) ;
  - positions de l'ancien modèle via `MacroLearner` (111-128 ; MacroRunner.swift:1237-1363) ;
  - « Tester » avec FL au premier plan et compte à rebours de 3 s (203-230) ;
  - dernier résultat et export du journal.

### 1.7 Le lien MIDI dans les macros

- **Usage actuel :** uniquement les actions 39 `armon` et 40 `recon`, idempotentes (device_FLShortcut.py:798-813).
  - Le script dort au départ et se réveille par un PING bref (valeur 2).
  - Il se rendort 8 s après la dernière trame signée (435-450, 1422-1428 ; PROTOCOL.md:58-62).
- **Limites du protocole :**
  - ids d'action de 1 à 42, car le masque de capacités fait 6×7 bits (PROTOCOL.md:30 ; FLProtocol.swift:33 et 98 ; Actions.swift:135 et 147 ; script :52). 40 sont déjà pris.
  - aucune requête d'état ;
  - l'accusé CC 119 n'est pas signé ;
  - `IncomingDecoder` déclare « incompatible » tout HELLO dont le protocole n'est pas 2 (FLProtocol.swift:211).

### 1.8 Essais existants

- **MacroTests** : construction, ordre exact d'`autoRecord` (81-91), bornes (154-169), aller-retour du profil, refus à l'import, routeur.
- **MacroGeometryTests** : `MacroSpots.resolve`.
- **Python** : sommeil et trames.
- **CI macOS** :
  - `--selftest-preset` : vraie boîte « Open » ;
  - `--fake-fl` + `--selftest-macro` : 4 passages (apprentissage, rejeu, « O » qui surligne seulement, rejeu), état vérifié, aucune action inattendue (MacroSelfTest.swift:81-185 ; FakeFL.swift:199-239, 320-379).
  - Ces essais tournent en `continue-on-error: true` (build.yml:163-182).
  - La vérification du larsen est retirée de l'essai (MacroSelfTest.swift:110).

### 1.9 Ce que l'utilisateur ne peut pas faire aujourd'hui

1. Créer, voir, réordonner, désactiver ou supprimer des étapes dans l'interface. Il ne peut même pas renommer la macro.
2. Utiliser des conditions, des boucles, des variables, ou lire l'état de FL (sauf l'effet idempotent d'`armon`/`recon`).
3. Appeler l'une des 40 actions du script depuis une macro : seuls 39 et 40 sont câblés en dur.
4. Enregistrer ses gestes.
5. Exporter ou importer une macro seule. Réutiliser une macro sur plusieurs raccourcis : la macro est copiée dans chaque `Remap`.
6. Apprendre un clic propre à une macro : les positions et « Entrée après la lettre » sont globaux. Les lettres F/O et le chemin « S ← ↓×5 » sont figés.
7. Savoir *quel* bloc a échoué, autrement que par « étape N » à plat. Il n'existe ni pas-à-pas ni surlignage.
8. Dépasser 40 étapes, 5 s de pause ou 180 s estimées.
9. Utiliser les macros sur Windows : `ShortcutKind` n'a pas de macro (windows/FLShortcut.Core/Model.cs:48, 139-148) et les lignes macro y sont désactivées.

**Dettes repérées :**
- **Code mort :** `MacroSpots.Learned/Kind/load/save` (MacroSpots.swift:13-58), `hintPoint(awayFrom:)` (MacroRunner.swift:1039-1042), `TrackMemory.lastClick` (:53), clés `PathKind.openState/armSelected`.
- **Documentation périmée :**
  - MACROS.md:27 (mémoire de la rangée du Mixer, retirée : MacroRunner.swift:710-711) ;
  - MACROS.md:29 (« sans lien : rien », alors que l'armement passe désormais par le clavier, 776-784) ;
  - Macro.swift:38 (« clics appris ») ;
  - Actions.swift:2 (« 38 actions »).
- **Validation sur le thread du tap** (309).
- **Étapes inconnues supprimées sans bruit** (134-135).

---

## 2. Architecture proposée

### 2.1 Principes

- **FL seulement, par conception.** Aucun bloc ne peut lancer un shell, AppleScript, une URL, toucher au presse-papiers ou à des fichiers. Seule exception : choisir un preset existant dans la boîte de FL.
- **Les garde-fous restent dans la couche d'effets**, jamais dans les blocs. C'est le cas de `shouldStop`, du clic dans FL, de la liste noire et des événements marqués. Un bloc ne peut donc pas les contourner.
- **Trois couches séparées :**
  - données pures, testables ;
  - interpréteur pur, testable avec de faux effets ;
  - effets macOS, c'est-à-dire le code actuel déplacé tel quel.
- **Rien de nouveau ne tourne tant qu'aucune macro ne tourne :** pas de minuterie, pas d'observateur, pas de MIDI.

### 2.2 Modèle de données v2 (nouveau `MacroModel.swift`)

```swift
/// Une macro de la bibliothèque (identifiants JSON stables, jamais traduits : c'est un contrat, comme « armon »).
struct MacroDoc: Codable, Identifiable, Equatable {
    var id: UUID
    var format = 2
    var name: String                      // ≤ 60, affiché avec displaySafe()
    var blocks: [Block]
    var variables: [VariableDecl] = []    // ≤ 8 entiers (incrément 4)
    var origin: Origin?                   // .modele("autoRecord"), .importe, .enregistre
    var revision = 0                      // +1 à chaque enregistrement : clé du cache de validation
}

struct Block: Codable, Identifiable, Equatable {
    var id: UUID                          // stable : surlignage, rapport par bloc, positions apprises
    var enabled = true                    // case à cocher (comme Pulover)
    var onFailure: FailurePolicy = .stop  // .stop | .continue
    var note: String?                     // commentaire ≤ 120
    var body: BlockBody
}

indirect enum BlockBody: Equatable {
    // Clavier
    case key(KeyRef, times: Int)                            // « Touche »
    case menuLetters([Character], finalEnter: EnterPolicy)  // « Lettres d'un menu de FL » (seulement si un menu est ouvert)
    case menuKey(MenuKey, times: Int)                       // ↑ ↓ ← → Entrée Échap, seulement dans un menu ouvert
    // Souris
    case click(ClickTarget, button: MouseButton)
    // Fenêtres et attentes
    case delay(ms: Int)
    case waitWindow(WindowKind, timeoutMs: Int)             // .boite | .menu
    case waitWindowClose(WindowKind, timeoutMs: Int)
    // FL (haut niveau : le code validé d'aujourd'hui)
    case trackMenu(letters: [Character], target: TrackTarget, finalEnter: EnterPolicy)
    case chooseFile(path: String)
    case flAction(key: String, fallback: ActionFallback)    // clé stable du protocole ; repli : touche native / chemin clavier
    case flActionValue(key: String, value: IntSource)       // incrément 4 (paramètre signé)
    case selectInput(LearnedRef)
    case feedbackCheck
    // Contrôle
    case ifElse(Condition, then: [Block], else: [Block])
    case repeatCount(Int, [Block])
    case repeatWhile(Condition, maxIterations: Int, [Block])
    case waitUntil(Condition, timeoutMs: Int)
    case setVariable(String, IntSource)
    case stop(message: String?)
    case comment(String)
    // Format plus récent : conservé tel quel, macro BLOQUÉE (jamais exécutée sans lui)
    case unknown(type: String, raw: JSONValue)
}

indirect enum Condition: Codable, Equatable {
    case windowOpen(WindowKind)               // local, sans MIDI
    case flState(FLQuery, CompareOp, Int)     // lien MIDI (incrément 4)
    case variable(String, CompareOp, Int)
    case lastBlockFailed                      // utile avec onFailure = .continue
    case not(Condition), all([Condition]), any([Condition])
}

enum ClickTarget: Codable, Equatable {
    case flWindow(corner: Corner, dx: Double, dy: Double, size: CGSize?)  // taille retenue ⇒ refus si elle change
    case openMenu(MacroSpots.PopupHop)                                    // relatif au dernier menu ouvert (résiste au décalage)
    case track(dx: Double, dy: Double)                                    // depuis la piste visée (TrackMemory)
    case lastClick(dx: Double, dy: Double)
    case startCursor(dx: Double, dy: Double)
    case cursorXWindowY(dx: Double, dy: Double)                           // reprise d'un ancien ClickSpot
}

/// Touche portable : code Mac + caractère (re-résolu si la disposition change, et base d'un futur portage Windows).
struct KeyRef: Codable, Equatable { var combo: KeyCombo; var char: String? }
```

- **Codage JSON :** `{"type":"if","id":…,"condition":…,"then":[…],"else":[…]}`, avec un `Codable` écrit à la main et piloté par le registre.
  - Je déconseille l'encodage synthétisé des enums à valeurs associées (`_0`) : il est illisible et non tolérant.
  - Un type inconnu donne `.unknown(type:raw:)` via un petit `JSONValue`. Le contenu est conservé, mais la macro est bloquée, selon l'esprit de REL-01.
- **Profondeur :** déclarée par le registre, limitée à 4.

### 2.3 Stockage : bibliothèque séparée et compatibilité

- **Nouveau fichier `MacroLibraryStore.swift`.** Il écrit `Application Support/FL Shortcut/macros.json`, en 0600 et de façon atomique (`SecureFile`), avec des copies de secours.
  - Il couvre aussi la désinstallation : le dossier entier est supprimé (Uninstaller.swift:95-98).
- **Lien depuis le raccourci :** `Remap` gagne `macroRef: UUID?` pour les macros en blocs.
  - Les modèles `autoRecord` restent en ligne dans le profil, tels quels : aucun changement pour les profils existants.
- **Pourquoi un fichier séparé :**
  - Une ancienne version de l'app qui relit le profil verrait `"template":"blocks"`, mettrait `macro = nil` puis **réécrirait le profil sans la macro** (Model.swift:188, 247) : la macro serait perdue.
  - Avec la bibliothèque, l'ancienne app ne touche jamais `macros.json`.
  - Ceinture et bretelles : écrire aussi `"unknownAction":"macroRef:<uuid>"`, que les anciennes versions conservent (Model.swift:187, 245). La nouvelle version s'en sert pour retrouver le lien s'il a disparu.
  - Bonus : une page « Macros » propre, une macro pour plusieurs raccourcis, et un fichier `.flsmacro` qui correspond exactement à une entrée de la bibliothèque.
- **Positions apprises :** fichier `learned.json` dans le même dossier, indexé par id de bloc et propre à la machine.
  - `LearnedRef.legacy("macroSpots.v2.input")` et `EnterPolicy.learned(legacyKey: "macroMenuEnterAfterLetter")` pointent vers les clés actuelles : **rien à réapprendre**.
- **Migration** (une fois, drapeau UserDefaults, comme `autoRecordMigrationKey`, avec copie du profil) :
  - `custom` → entrée de la bibliothèque, étape par étape :
    - key → touche ; delay → pause ;
    - click → clic, ancre par ancre (`window` → `.flWindow(.hautGauche)`, `cursorXWindowY` gardé, `lastClick` → `.lastClick`) ;
    - menu → bloc `menuAX` caché, non proposé dans la palette ;
    - waitDialog/Close → attendre une fenêtre / sa fermeture ;
    - trackMenu → menu de piste ; armTrack/recordOn → `flAction(armon/recon)` ;
    - selectInput → choisir l'entrée ; feedbackCheck → vérifier le larsen.
  - `quickRecord` avec positions → macro en blocs « Enregistrement rapide (ancien) », par développement statique. On peut ensuite supprimer `quickRecordSteps` et `MacroLearner`.
  - Le décodeur `MacroStep` est conservé pour toujours, en lecture seule.
- **Index du tap :** il contient une référence `MacroProgram` (classe `final`, immuable, compilée et validée **sur le thread principal** dans `Store.recompute`, mise en cache par `(id, revision)`).
  - Le thread du tap ne fait plus qu'une recherche et une mise en file.
  - `RouterEffect.runMacro` porte cette référence.
  - L'égalité se fait par `id + revision`, pas par comparaison profonde.
- **Édition :** sur un brouillon (comme `EditSheet`), enregistré par « Enregistrer » ou après 0,5 s d'inactivité. Jamais `Store.remaps` à chaque frappe, pour éviter les `recompute` à répétition.

### 2.4 Format d'échange `.flsmacro`

```json
{ "format": "flsmacro", "version": 1, "exportedBy": "FL Shortcut 1.x (macOS)",
  "macro": { "name": "Armer et enregistrer si éteint",
    "blocks": [
      { "type": "if", "id": "…", "condition": { "type": "flState", "query": "isrec", "op": "eq", "value": 0 },
        "then": [ { "type": "flAction", "id": "…", "action": "recon", "fallback": { "key": { "combo": { "keyCode": 15 }, "char": "r" } } } ],
        "else": [] } ] } }
```

- **Export :** les positions apprises sont retirées (« à montrer sur cette machine »). Le chemin d'un preset est exporté, mais il faudra le rechoisir à l'import. Les actions sont désignées par leur **clé** (`recon`), plus lisible qu'un id.
- **Import :**
  - limites : 256 Ko, nombre de blocs et profondeur bornés ;
  - écran de relecture **en français clair**, bloc par bloc, avec les blocs sensibles marqués : touches avec ⌘, clics, fichiers, lien MIDI ;
  - la macro importée arrive **désactivée et sans raccourci**, et les ids sont régénérés ;
  - l'import de *profil* continue de refuser les macros libres (Model.swift:559-563), avec le message « importe-la en .flsmacro pour la relire » ;
  - en option : déclarer le type UTType `app.flshortcut.macro` (conforme à `public.json`) dans Resources/Info.plist, pour l'ouvrir par double-clic.

### 2.5 Règles de validation et de sécurité (nouveau `MacroValidation.swift`)

| Règle | Valeur proposée |
|---|---|
| Blocs au total, en comptant l'imbrication | ≤ 200 (aujourd'hui 40 étapes) |
| Profondeur d'imbrication | ≤ 4 ; conditions ≤ 3 niveaux et 6 termes |
| Pause | ≤ 5 s (inchangé) ; attentes ≤ 120 s ; « attendre que » ≤ 120 s, relevé toutes les 250 ms |
| Boucles | répéter ≤ 50 fois ; « tant que » ≤ 100 tours |
| Pire durée estimée (récursive : corps × nombre de tours, délais d'attente) | ≤ 300 s, sinon refus ; **garde-fou à l'exécution** : arrêt à 300 s ou après 2 000 blocs exécutés |
| Touches | `isValidKey` + `ForbiddenTargets` pour chaque touche, REC de secours comprise, à l'édition, à l'import, au chargement **et** juste avant l'envoi |
| Lettres de menu | a à z, sans modificateur, envoyées seulement si un menu ouvert par la macro est encore là (règle actuelle, 632-666) |
| Clics | positions finies, ≤ 5000 ; à l'exécution, toujours dans une fenêtre de FL, sans autre app au-dessus (1176-1197) |
| Fichiers | sans caractère de contrôle, ≤ 1024, sous le dossier personnel, extension `.fst` (liste blanche fixée par le bloc), fichier existant à l'exécution |
| Textes affichés (noms, notes) | `displaySafe` (Model.swift:321-329) |
| Blocs refusés par conception | shell, AppleScript, URL, presse-papiers, frappes ou clics hors de FL, lancement d'apps |
| Blocs inconnus | conservés, macro bloquée (fin de la suppression sans bruit, Macro.swift:134-135) |
| Import | relecture obligatoire ; macro désactivée et sans raccourci |

Le cache de validation est indexé par `(id, revision)` : `recompute` ne revalide plus que ce qui a changé.

### 2.6 Le registre des blocs (nouveau `MacroRegistry.swift`)

C'est l'endroit unique d'où l'interface, l'exécution, la validation, le journal et la documentation tirent leurs informations.

```swift
enum BlockType: String, CaseIterable, Codable { case key, menuLetters, menuKey, click, delay, waitWindow, waitWindowClose,
    trackMenu, chooseFile, flAction, flActionValue, selectInput, feedbackCheck,
    ifElse = "if", repeatCount = "repeat", repeatWhile = "while", waitUntil, setVariable, stop, comment }

enum BlockCategory: String, CaseIterable { case clavier = "Clavier", souris = "Souris",
    fenetres = "Fenêtres et attentes", fl = "FL Studio", controle = "Contrôle" }

struct BlockNeeds: OptionSet {      // agrégé par MacroProgram → Store.recompute
    static let flAuPremierPlan, clavierAuRepos, pisteVisee, lienMIDI, extensionsMIDI, larsenEnAvance, cliqueHID
}

struct ParamSpec { let id: String; let label: String; let kind: ParamKind; let aide: String? }
enum ParamKind { case touche, ms(ClosedRange<Int>), nombre(ClosedRange<Int>), lettres(max: Int), toucheMenu,
                 cible, fenetre, fichier(extensions: [String]), actionFL, condition, variable, texte(max: Int) }

struct BlockSpec {
    let type: BlockType
    let label: String                    // « Touche », « Lettres d'un menu de FL », « Si… sinon »
    let category: BlockCategory
    let symbol: String                   // SF Symbol de la palette
    let aide: String                     // phrase de la palette ET de MACROS.md
    let params: [ParamSpec]              // l'inspecteur est construit à partir de ce schéma
    let conteneur: Conteneur             // .aucun, .corps, .siSinon
    let needs: (BlockBody) -> BlockNeeds // flAction : lien seulement sans équivalent clavier (AppMode.nativeEquivalent)
    let parDefaut: () -> BlockBody
    let resume: (BlockBody, KeyboardLayout) -> String   // ligne de la liste : « ⌘S × 2 »
    let journal: (BlockBody) -> String                  // JAMAIS une touche, un chemin ou un nom de piste : « touche (masquée) »
    let estimationMs: (BlockBody) -> Int
    let valider: (BlockBody, ContexteValidation) -> String?
    let import_: PolitiqueImport          // .ok, .aRelire(raison), .retirerPositions
    let plateformes: Plateformes          // .mac (.windows prévu)
}

enum BlockRegistry {
    /// switch exhaustif (pas un dictionnaire) : un BlockType ajouté sans fiche = erreur de compilation.
    static func spec(_ t: BlockType) -> BlockSpec { switch t { case .key: return Specs.key /* … */ } }
    static let palette: [(BlockCategory, [BlockSpec])] = …
}
```

- **Côté exécution**, `MacroInterpreter` fait lui aussi un `switch` exhaustif sur `BlockBody`. Le compilateur garantit qu'aucun bloc n'est oublié.
- **Côté documentation**, la commande `FLShortcut --doc-blocs` produit le tableau Markdown des blocs. Un test vérifie que MACROS.md contient exactement ce tableau, ce qui met fin aux documents périmés constatés au §1.9.

### 2.7 Le moteur (exécution)

- **Découpage de `MacroRunner.swift`** (1 402 lignes), le code étant **déplacé tel quel** :
  - `MacroRunner.swift` (~350 lignes) : `start`, verrou, contexte, notification, essais ;
  - `MacroInterpreter.swift` : contrôle du déroulement ;
  - `MacroEffectsMac.swift` : touches, lettres, clics, curseur, attentes de fenêtres, `closePopups`, `hoverOutside` ;
  - `MacroFLBlocks.swift` : `trackMenu`, `armViaKeyboard`, `armAndRecord`, `selectInput`, `learnPath`, `awaitPopup/runHops` ;
  - `MacroLearner` et `MacroDiagnostics` dans leurs propres fichiers.
- **Effets injectables, interpréteur testable :**

```swift
protocol MacroEffects: AnyObject {
    func stopReason() -> String?                                 // FL plus devant, Échap, délai global dépassé
    func perform(_ body: BlockBody, state: inout RunState) -> StepResult      // blocs simples
    func flActions(_ group: [(key: String, fallback: ActionFallback)], state: inout RunState) -> [StepResult]
    func evaluate(_ c: Condition, state: inout RunState) -> Result<Bool, StepError>
    func pause(ms: Int) -> StepResult
    func cleanup(state: inout RunState)      // menus ouverts par nous, curseur, modificateurs relâchés
}
struct RunState {                            // remplace les variables d'instance (MacroRunner.swift:227-270)
    var track: CGPoint; var lastClick: CGPoint?; var dialog: WinInfo?; var trackTarget: CGPoint?
    var cursorBeforeBurst: CGPoint?; var startWindows: Set<Int>; var variables: [String: Int]; var lastFailed = false
}
final class MacroInterpreter {
    init(effects: MacroEffects, observer: RunObserver?, gate: StepGate?, limits: RuntimeLimits)
    func run(_ p: MacroProgram) -> MacroOutcome
    private func run(_ blocks: [Block], path: BlockPath, state: inout RunState) -> Flow   // .next | .stop | .fail | .cancel
}
```

- **Règles conservées à l'identique :**
  - les blocs `flAction` **consécutifs** sont regroupés en un seul réveil MIDI. C'est la généralisation de la fusion arm + REC (397-401). Sans lien, les replis s'exécutent un par un, dans l'ordre ;
  - larsen lancé en avance si un bloc le demande, recherché dans tout l'arbre ;
  - attente du clavier au repos et contrôle préalable de la piste visée, pilotés par `needs` (`.clavierAuRepos`, `.pisteVisee`) au lieu de `steps.first?.kind` (378-386).
- **Messages d'erreur :** `MacroOutcome.failed(path: "3.2", label: "Touche", reason)` donne « Macro arrêtée au bloc 3.2 (Touche) : … ». `onFailure = .continue` positionne `lastBlockFailed`.
- **Surlignage :** protocole `RunObserver` (bloc commencé ou fini, avec résultat et durée), appelé sur la file de la macro.
  - L'adaptateur `MacroRunMonitor: ObservableObject` publie seulement `currentBlockID` (deux lignes redessinées) et un rapport par bloc limité à 200 entrées.
  - Il n'est branché **que** pendant un essai lancé depuis l'éditeur : `nil` ailleurs, donc aucun coût.
- **Pas à pas :** `StepGate` (sémaphore attendu par tranches de 50 ms, `stopReason` vérifié entre deux).
  - Commandes dans un **`NSPanel` non activant**, qui accepte les clics sans enlever le premier plan à FL : Bloc suivant / Continuer / Arrêter, avec le bloc courant affiché.
  - Aujourd'hui, cliquer dans la fenêtre de l'app ferait échouer la macro, car `shouldStop` exige que FL soit au premier plan.
- **Échap fiable :** quand une macro tourne, `EventTap.handle` voit chaque appui sur Échap qui n'est pas de nous (sans `EventTap.mark`) et lève `MacroRunner.cancelRequested` (un `Locked<Bool>`). La touche continue vers FL.
  - On garde la lecture `keyState` en secours, mais on l'ignore pendant 150 ms après un Échap envoyé par la macro.
  - Effet : un bloc « Échap » ou `closePopups` ne s'annule plus lui-même.
- **Délais :** chaque attente garde son échéance. Le relevé des fenêtres s'espace : 12-15 ms pendant les 300 premières ms, puis 50 ms, puis 100 ms au-delà de 10 s. Garde-fou global de 300 s. Les appels à l'accessibilité gardent leur délai de messagerie.
- **Nettoyage à l'annulation :** `cleanup` dans un `defer` de l'interpréteur.

### 2.8 Extension du protocole MIDI (rétro-compatible, la version reste 2)

On annonce des extensions au lieu de passer au protocole 3. Raison : un `proto != 2` rend le lien « incompatible » (FLProtocol.swift:211), et FL ne relit le script mis à jour qu'à son redémarrage (FLScriptInstaller.swift:130-148).

| Élément | Sens | Numéros de CC (tous libres aujourd'hui) | Règle |
|---|---|---|---|
| Drapeaux d'extensions | FL → app, dans le HELLO (entre CC 126 et la fin CC 120 = 127) | CC 80 : bit 0 = paramètres, bit 1 = requêtes, bit 2 = actions étendues | les anciennes apps l'ignorent (`IncomingDecoder` : `default → nil`) ; sans CC 80, aucune extension |
| Capacités des actions 43-91 | FL → app, dans le HELLO | CC 81-87 (7 × 7 = 49 bits) | `CapabilityMask` gagne `extended: UInt64` |
| Paramètre | app → FL | CC 112, répété de 0 à 4 fois **juste avant** CC 104 | le script les garde en mémoire et les efface après la trame, sur un PING ou s'ils arrivent pendant une trame (rejet « mélangée ») ; nombre comparé à l'arité déclarée de l'action |
| Signature d'une trame | – | `HMAC(clé, nonce‖seq‖action‖paramètres…)` | **sans paramètre, c'est exactement la signature v2** : le vecteur de test actuel reste valable |
| Requête | app → FL | trame signée normale, octet « action » 96-127 = table `QUERIES` | séquence, anti-rejeu, 20/s en commun et 10 requêtes/s au plus ; une requête signée prolonge le réveil (`_keep_awake`) |
| Réponse signée | FL → app | CC 96 = id de la requête, CC 97/98 = valeur sur 14 bits (16383 = indisponible), CC 99-102 = MAC28 de `HMAC(clé, 0x52 ‖ nonce ‖ seq ‖ requête ‖ vhi ‖ vlo)` | octet `0x52` (« R ») pour séparer les deux sens ; ordre strict ; l'app vérifie qu'elle attendait ce couple (seq, requête), sinon elle ignore la réponse |

- **Requêtes proposées** (ids figés ; fonctions et API minimale **à vérifier dans les stubs de FL et dans audit/04**). Chaque requête teste la présence de la fonction (`_has`) et la version d'API, sinon elle répond 16383.

| id | clé | Source dans FL | Valeur |
|---|---|---|---|
| 96 | isrec | `transport.isRecording` | 0/1 |
| 97 | isplay | `transport.isPlaying` | 0/1 |
| 98 | track | piste sélectionnée (`_selected_track`) | numéro |
| 99 | armed | `mixer.isTrackArmed` | 0/1 |
| 100 | muted | `mixer.isTrackMuted` | 0/1 |
| 101 | solo | `mixer.isTrackSolo` | 0/1 |
| 102 | window | `focused_window_code` | code fenêtre |
| 103 | channel | `_selected_channel` | numéro |
| 104 | pattern | `patterns.patternNumber` | numéro |
| 105 | tempo | tempo | BPM × 10 |

- **Actions paramétrées (43 et plus, à vérifier) :** sélectionner la piste N (`mixer.setTrackNumber`), le canal N, aller au pattern N.
- **Nom de piste (plus tard) :** réponse texte bornée à 32 caractères ASCII, signée. Il serait **comparé en mémoire et jamais journalisé**.
- **À modifier côté script** (device_FLShortcut.py) :
  - `QUERIES` à côté d'`ACTIONS` (1154-1211) ;
  - `_PROTOCOL_CCS` (1459-1463) étendu aux CC 80-87, 96-102 et 112 ;
  - `hello_messages` (1251-1261) ;
  - `_process_frame` (1343-1377) : paramètres et chemin des requêtes ;
  - **aucun nouveau travail dans `OnIdle`/`OnRefresh`**. Le script reste endormi par défaut et ne répond qu'aux trames signées.
- **À modifier côté app :**
  - FLProtocol.swift : `FrameEncoder` avec paramètres et ids 1-127 selon les capacités, décodeur des réponses ;
  - Actions.swift : `CapabilityMask` étendu, table `FLQueries` ;
  - MIDILink.swift : `LinkCore.query(_:timeout:)` sur le modèle de `runBriefly`, avec réveil bref si nécessaire et attente de la réponse pendant 0,5 s ;
  - le message figé « FL n'a pas confirmé (armement / REC) » est à généraliser.
- **PROTOCOL.md :** §3 (extensions du HELLO), §4 (paramètres), nouveau §7 (requêtes) et §8 (vecteurs de test : MAC avec paramètres, MAC d'une réponse), à reproduire dans ProtocolTests.swift, `Tests/python` et `CoreTests.cs`.
- **Windows :** le script est commun, donc il fonctionne pour les deux. `windows/FLShortcut.Core/Protocol.cs` (`MaxActionId = 42` à la ligne 32) doit refléter le Mac : encodeur avec paramètres, décodeur et vérification des réponses, mêmes vecteurs. Le moteur de macros Windows reste un projet à part (SendInput et UI Automation). Les lettres de menu soulignées sont natives sous Windows : c'est le bloc le plus facile à porter.
- **Sans lien ou avec un script ancien :**
  - les blocs qui ont `.lienMIDI` affichent un badge dans l'éditeur ;
  - à l'exécution, l'échec est clair : « Ce bloc a besoin du lien avec FL », ou « Redémarre FL pour activer les conditions » si l'extension n'est pas annoncée ;
  - une condition peut choisir `siLienAbsent : faux | échec`.

### 2.9 L'enregistreur (nouveaux `MacroRecorder.swift` et `RecordingCompiler.swift`)

- **Capture :**
  - **Touches :** un crochet dans `EventTap.handle`. Une lecture atomique par frappe ; ne garde que `keyCode`, les modificateurs et l'horodatage, **jamais le caractère**. Un mode `config.macroRecording` laisse passer toutes les touches vers FL, comme `recording` (KeyRouter.swift:132).
  - **Souris :** clics gauche et droit par un moniteur global, comme `ClickRecorder` (MacroSpots.swift:71-102).
  - **Fenêtres de FL :** relevé toutes les 50 ms **seulement pendant l'enregistrement**, historique limité à 200 relevés.
- **Compilation** (fonction pure, testée sur des données figées comme `MacroSpots.resolve`) :
  - clic dans un menu ouvert depuis le début → `click(.openMenu(PopupHop))`, avec la même logique que `resolve` (194-221) ;
  - clic dans une fenêtre normale → `click(.flWindow(coin le plus proche, taille retenue))` ;
  - lettre ou flèche/Entrée/Échap pendant qu'un menu est ouvert → `menuLetters` ou `menuKey`, donc avec le garde-fou « seulement si un menu est ouvert » ;
  - autre touche → `key`. Une touche interdite est retirée, avec une note ;
  - boîte apparue ou disparue → `waitWindow` / `waitWindowClose`, délai = 2 × la durée observée, au moins 2 s ;
  - flèches identiques consécutives → `menuKey(times:)` ;
  - pauses ignorées, sauf option « garder les pauses » (arrondies à 100 ms, ≤ 5 s).
- **Vie privée (complément à SEC-07, à écrire dans l'audit et le README) :**
  - enregistrement explicite, avec témoin visible : pastille rouge dans la barre des menus et panneau non activant « ● Enregistrement – Arrêter » ;
  - limité à 120 s et 500 événements ;
  - refusé si la saisie sécurisée est active (`AppStatus.secureInput`) ;
  - en mémoire seulement jusqu'à la validation ; jamais journalisé ;
  - **les lettres tapées dans une boîte de FL ne sont pas gardées** : elles deviennent un bloc « Taper du texte » à remplir soi-même.

### 2.10 « Enregistrement rapide » devient un modèle en blocs

`MacroTemplates.enregistrementRapide(_ m: Macro) -> [Block]` remplace `autoRecordSteps` (Macro.swift:199-220). Ses ids sont **déterministes** (stables d'un lancement à l'autre) :

| # | Bloc | Paramètres, identiques à aujourd'hui | Condition d'ajout |
|---|---|---|---|
| 1 | `trackMenu` | lettres `f`, `o` (première lettre de « File\|Fichier » et « Open mixer track state\|… »), cible = dernière piste cliquée, `finalEnter = .learned(legacyKey: "macroMenuEnterAfterLetter")` ; flèche droite de secours, pointeur écarté, Échap seulement sur nos menus | toujours |
| 2 | `waitWindow(.boite)` | 4 000 ms | toujours |
| 3 | `chooseFile(path)` puis `waitWindowClose(8 000)` | – | preset fixe |
| 3' | `waitWindowClose(120 000)` | – | choix dans la liste de FL |
| 4 | `delay(100)` | – | armer ou REC |
| 5 | `flAction("armon", repli: .menuPisteArmer)` | menu de piste › S › ← › ↓×5 › Entrée | armer + entrée |
| 6 | `flAction("recon", repli: .touche(recKey))` | 5 et 6 regroupés en **un seul réveil MIDI** | REC |
| 7 | `selectInput(.legacy("macroSpots.v2.input"))` | appris une fois ; bulle la première fois | armer + entrée |
| 8 | `feedbackCheck` | lancé en avance, **en dernier** | armer ou REC |

- **Préconditions reprises :** le contrôle « clique d'abord sur ta piste » vient de `needs .pisteVisee` sur le premier bloc.
- **Le modèle reste paramétrique** dans le profil (`template: autoRecord` et ses trois options), et l'interface actuelle (`MacroFields`) reste la même. Une amélioration du modèle profite donc à tous.
- **« Personnaliser »** copie le développement dans la bibliothèque, comme « Convertir » dans Raccourcis d'Apple. La copie garde les `LearnedRef` vers les clés historiques.
- **Ce qui empêche une régression :**
  - un test golden sur les 8 combinaisons d'options (preset fixe ou non × armer × REC), qui reprend MacroTests.swift:81-121 ;
  - FakeFL : les 4 passages restent verts sans changer le scénario, avec les mêmes événements attendus (MacroSelfTest.swift:162-170) ;
  - les durées par étape publiées dans le résumé de la CI sont comparées à la référence (tolérance ±10 %) ;
  - la suite des étiquettes `STEP`, `KEY` et `MENU` du journal en écho est comparée entre l'ancien et le nouveau moteur.

### 2.11 Interface, entièrement en français

- **Barre latérale :** nouvelle rubrique « Macros » (EditorView.swift:136-170) qui liste la bibliothèque (nom, raccourci, badges « Lien FL » ou « À apprendre »). Boutons Nouvelle macro, Importer…, Modèles.
- **Créateur :** fenêtre dédiée (scène `Window`, comme l'éditeur, ouverte à la demande), car la fiche de 500 pt est trop étroite.
  - À gauche, la **palette** par catégorie, avec recherche.
  - Au centre, la **liste à plat avec retrait selon la profondeur** : réordonner par `.onMove`, imbriquer avec ⌘] / ⌘[ et « Déplacer dans… », case Activer, ⌫ pour supprimer, ⌘D pour dupliquer. Je déconseille `OutlineGroup`, qui ne sait pas réordonner sur macOS 13.
  - À droite, l'**inspecteur** construit depuis les `ParamSpec` : capture de touche, champs bornés, choix de fichier, bouton « Montrer dans FL… » pour apprendre une cible.
  - Barre d'outils : Tester ▶, Pas à pas, ● Enregistrer, Exporter, Raccourci.
- **Fiche d'un raccourci de type Macro :** choix entre « Enregistrement rapide (modèle) », une macro de la bibliothèque ou « Nouvelle… », plus « Ouvrir dans le créateur ».
- **Compatibilité et règles de dessin :** macOS 13, donc pas de `@Observable` (`ObservableObject` seulement). Règles existantes : jamais de verre par ligne, aucun survol animé (EditorView.swift:6-7).

### 2.12 Stratégie de test

- **Tests unitaires** (XCTest, `swift test` sur la CI macOS) :
  - `MacroModelTests` : aller-retour JSON de chaque `BlockType` (parcours de `allCases` avec les valeurs par défaut du registre), blocs inconnus conservés et macro bloquée, décodage tolérant, `displaySafe`.
  - `MacroMigrationTests` : `custom` → blocs, étape par étape ; `quickRecord` → blocs ; lien `unknownAction` retrouvé ; copie de secours.
  - `MacroTemplateTests` : test golden des 8 combinaisons d'options.
  - `MacroValidationTests` : profondeur, nombres, pire durée, touche interdite au fond d'un « si », boucles bornées, import désactivé.
  - `MacroRegistryTests` :
    - chaque type a un libellé et une aide en français et des valeurs par défaut valides ;
    - les besoins agrégés sont corrects ;
    - le tableau de MACROS.md est identique à la sortie de `--doc-blocs` (fichier lu via `#filePath`).
  - `MacroInterpreterTests` avec `FakeEffects` (trace des appels) : si/sinon, boucles, arrêt, `onFailure`, garde-fou de durée, annulation, pas à pas, regroupement des `flAction`.
  - `RecordingCompilerTests` : événements et relevés figés → blocs attendus.
  - `ProtocolTests` : vecteurs de signature avec paramètres et de réponse ; réponse falsifiée, mélangée ou non attendue ignorée ; `LinkCore.query` avec `FakeTransport` et `FakeClock` (TestSupport.swift:92-111).
- **Python et C# :** paramètres, chaque requête, signature des réponses, limites de débit, sommeil (seule une requête signée maintient le script éveillé), CC 112 parasites, drapeaux du HELLO, vieilles API qui répondent 16383. Mêmes vecteurs dans `CoreTests.cs`.
- **FakeFL de bout en bout sur la CI :** `--selftest-macro … --scenario <nom>`.
  1. `modele` : les 4 passages actuels, désormais par l'interpréteur (garde-fou de non-régression).
  2. `blocs` : macro construite à la main (clic droit sur la piste 5, lettres S, ←, ↓×5, Entrée, touche R) ; on vérifie « arm 5 » et « rec on ».
  3. `controle` : « Si une boîte est ouverte… sinon… » et « Répéter 3 fois : → ». Il faut un petit ajout à FakeFL : ←/→ changent la piste sélectionnée, hors menu (FakeFL.swift:199-239).
  4. `requetes` : un faux script, dans le pilote, répond aux requêtes signées avec la clé de test à partir de l'état JSON de FakeFL. Il teste tout le côté app sauf CoreMIDI ; le côté Python est couvert par unittest.
  5. `enregistreur` : le pilote joue l'utilisateur pendant l'enregistrement, compile, remet FakeFL à zéro, rejoue et compare l'état.
  - Rendre le scénario `modele` bloquant (retirer `continue-on-error`) dès qu'il est stable sur plusieurs exécutions.

---

## 3. Plan en 6 incréments (chacun compile, passe les tests et peut être livré)

Les tailles sont des ordres de grandeur, en lignes.

**Incrément 1 : moteur à blocs, rien de visible** (~1 600 lignes, surtout du déplacement)
- **Nouveaux fichiers :**
  - `MacroModel.swift` (~420), `MacroRegistry.swift` (~380), `MacroTemplates.swift` (~160), `MacroValidation.swift` (~260), `MacroInterpreter.swift` (~320) ;
  - `MacroEffectsMac.swift` (~700, déplacé) et `MacroFLBlocks.swift` (~450, déplacé).
- **Fichiers modifiés :**
  - `MacroRunner.swift` : de 1 402 à ~350 lignes ;
  - `Macro.swift` : décodage historique et conversion vers les blocs ;
  - `MacroSelfTest.swift` : passe par l'interpréteur ;
  - tests : nouveaux fichiers et `MacroTests` adapté.
- **Livré :** le modèle tourne par l'interpréteur ; la validation quitte le thread du tap ; `MacroProgram` est en cache.
- **Risques :**
  - partage d'état entre blocs (`dialog` entre attendre la boîte, choisir le fichier et attendre la fermeture ; `trackTarget` réutilisé par `armViaKeyboard`) → passer par un `RunState` explicite ;
  - place de l'attente du clavier et de `restoreCursor` ;
  - regroupement arm + REC.
  - Parade : déplacer le code tel quel, plus le test golden, l'essai FakeFL et la comparaison du journal.

**Incrément 2 : bibliothèque et créateur, édition et essai** (~2 000)
- **Nouveaux fichiers :** `MacroLibraryStore.swift` (~260), `MacroEditorView.swift` (~650), `MacroInspector.swift` (~380), `MacroPalette.swift` (~150), `MacroRunMonitor.swift` (~120).
- **Fichiers modifiés :**
  - `Model.swift` : `macroRef` et lien dans `unknownAction` ;
  - `Store.swift` : programmes, `needs` qui pilotent `TrackMemory` et les ports MIDI à la demande à la place de Store.swift:203-209 ;
  - `KeyRouter.swift`, `EventTap.swift` (références) ; `EditorView.swift` (rubrique) ; `MacroFields.swift` (choix, « Personnaliser ») ;
  - **export** `.flsmacro` ; MACROS.md.
- **Blocs :** touche, pause, clic (fenêtre, piste, dernier clic, curseur, menu ouvert), lettres et touches de menu, attentes, choix de preset, action FL (avec la touche native de `AppMode.nativeEquivalent` en mode léger, LightMode.swift:15-44, sinon le lien), blocs FL de haut niveau, répéter N fois, arrêter, commentaire.
- **Risques :**
  - perte au retour à une ancienne version → couvert par le lien caché et la copie ;
  - `recompute` à répétition → brouillon ;
  - fluidité de la liste → lignes `Equatable`, pas d'objet observé par ligne.
- **Mesure :** ajouter l'ouverture du créateur à `scripts/mesure-interface.sh`, comme pour la page Mixer (commit 765df0b).

**Incrément 3 : contrôle et mise au point** (~900)
- **Contenu :**
  - conditions locales (fenêtre ou menu ouvert, dernier bloc échoué, variable) ;
  - Si/Sinon, Tant que, Attendre que ;
  - `onFailure` ;
  - garde-fou d'exécution (300 s, 2 000 blocs) ;
  - panneau pas à pas non activant (~200) ;
  - Échap par le tap (~40) ;
  - rapport par bloc dans l'éditeur ;
  - scénarios FakeFL 2 et 3.
- **Risques :**
  - le panneau ne doit jamais faire perdre le premier plan à FL (`.nonactivatingPanel`, `canBecomeKey == false`) ;
  - boucles infinies → garde-fou et pire durée.

**Incrément 4 : protocole, actions paramétrées et requêtes** (~1 300)
- **Fichiers :** PROTOCOL.md (~120), FLProtocol.swift (~180), Actions.swift (~120), MIDILink.swift (`query`, ~150), device_FLShortcut.py (~250) et ses tests (~250), ProtocolTests (~150), Windows `Protocol.cs` (~150) et `CoreTests.cs` (~100).
- **Blocs :** conditions sur l'état de FL, `flActionValue`, variables (8 entiers au plus, jamais de texte), faux script FakeFL (~120).
- **Risques :**
  - différences entre versions d'API de FL (20.7, API 1 → API 45) : chaque fonction est testée par `_has` et la version ;
  - charge de FL : rien dans `OnIdle`, 4 requêtes/s au plus côté app ;
  - FL doit être redémarré pour relire le script → l'app le détecte (pas de CC 80) et le dit ;
  - parité Windows.

**Incrément 5 : enregistreur** (~1 000)
- **Fichiers :** `MacroRecorder.swift` (~320), `RecordingCompiler.swift` (~280), panneau d'enregistrement (~140), crochet dans `EventTap` (~25), `KeyRouter` (`macroRecording`, ~10), tests (~250), scénario FakeFL 5.
- **Risques :**
  - vie privée (complément à SEC-07, revue de l'audit) ;
  - modificateurs restés enfoncés ;
  - lettres en AZERTY : passer par `KeyRef.char` ;
  - attribution d'un clic au bon menu : historique horodaté, comme `learnPath`.

**Incrément 6 : partage, modèles, finitions** (~700, puis ~−400 de nettoyage)
- **Contenu :**
  - **import** `.flsmacro` avec relecture et UTType (Info.plist, ouverture par l'AppDelegate) ;
  - galerie de modèles ;
  - `--doc-blocs` et le test de MACROS.md ;
  - suppression du code mort (§1.9), de `quickRecordSteps`, de `MacroLearner` et de `AXMenus.pressPath` une fois la migration vérifiée ;
  - mise à jour du README et de l'audit.

---

## 4. Mémoire, processeur, langue : règles à tenir

- **Repos (aucune macro qui tourne) :** zéro minuterie, zéro relevé, zéro trafic MIDI.
  - Les ports MIDI à la demande n'existent que si un programme actif a `.lienMIDI`.
  - `TrackMemory` n'est actif que si un programme actif a `.pisteVisee`.
  - Bibliothèque et programmes compilés : moins de 1 Mo pour 100 macros de 200 blocs. Les programmes sont des références partagées, jamais copiés dans l'index.
- **Thread du tap :** une recherche et une mise en file, plus une lecture atomique pour l'enregistreur et une pour Échap. Aucune validation.
- **Pendant une macro :**
  - relevé des fenêtres espacé selon la durée de l'attente (§2.7) ;
  - parcours d'accessibilité borné (300 nœuds) ;
  - requêtes MIDI ≤ 4/s ;
  - journal asynchrone ;
  - observateur de l'interface seulement pendant un essai depuis l'éditeur ;
  - jamais de capture d'écran ni de lecture de pixels.
- **Créateur :**
  - ouvert à la demande, dans sa propre fenêtre ;
  - modèle en types valeur, projection à plat recalculée en O(n) seulement après une modification, lignes `Equatable` ;
  - inspecteur construit seulement pour le bloc sélectionné ;
  - aucun verre par ligne ;
  - à mesurer avec `scripts/mesure-interface.sh`. Objectifs : moins de 2 Mo de plus quand le créateur est fermé, moins de 15 Mo de plus quand il est ouvert, 0 % de processeur au repos.
- **Script FL :** endormi par défaut, inchangé ; requêtes et paramètres traités seulement dans `OnMidiMsg`, sur trame signée ; le HELLO gagne 8 CC.
- **Langue :**
  - tous les textes visibles (libellés et aides du registre, erreurs, panneaux, documentation générée) et tous les commentaires sont en français ;
  - les **identifiants JSON restent des identifiants stables en ASCII**, jamais traduits ni renommés. C'est un contrat, comme les clés d'action (`armon`) et les types existants (`autoRecord`, `trackMenu`) ;
  - un test vérifie que chaque fiche du registre a un libellé et une aide non vides.
- **Contraintes de compilation** (Swift 5, Xcode 26, macOS 13) : pas de `@Observable` ; `Locked` et `@unchecked Sendable` comme aujourd'hui ; `Codable` écrit à la main pour les enums à valeurs associées.

**Points à vérifier sur un vrai FL avant l'incrément 4 :**
- les fonctions de l'API proposées pour les requêtes et les actions paramétrées, et leur API minimale (audit/04) ;
- que FL ne transforme pas un CC 112 ou 80-87 sur le canal 16 du port « FL Shortcut » en contrôle lié quand le script est ancien.

**Point à vérifier dès l'incrément 3 :** si `CGEventSource.keyState(.combinedSessionState, 53)` voit les Échap que nous envoyons par le flux du système (PresetChooser.swift:77).
