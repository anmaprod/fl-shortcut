# Audit de fiabilité : FL Remap v0.1 (macOS)

*Revue QA / fiabilité. Code audité : commit `bf2b36a` (« v0.1 avant audit »). Complète `01_securite_mac.md` (les renvois `SEC-xx` pointent vers ce document).*

**Méthode.** Le Swift n'a pas pu être compilé (environnement Linux) : la partie Swift est une **revue de code ligne à ligne**, scénario par scénario. Le script Python a été **exécuté** contre des modules FL simulés (`midi`, `transport`, `ui`, `general`, `mixer`, `channels`, `patterns`) qui respectent les bornes de l'API. Le paquet `fl-studio-api-stubs` n'a pas pu être installé (accès PyPI refusé par la politique réseau). Résultat : **13 tests, 6 échecs sur le script actuel**, 0 échec sur la version corrigée proposée (annexes A et B).

Les points marqués **(à valider sur Mac)** dépendent d'un comportement de macOS ou de FL Studio que la lecture du code ne permet pas de trancher. Ils doivent être confirmés par un essai manuel avant correction.

---

## 1. Résumé

Pour une v0.1, le cœur est sain : les événements que l'app poste sont marqués, donc pas de boucle ni de remaps en chaîne ; l'auto-répétition n'envoie pas plusieurs fois le même CC ; les drapeaux Fn et pavé numérique sont ignorés, donc les flèches correspondent bien ; la suppression d'une ligne de l'éditeur se fait en différé, par identifiant ; la fenêtre `Window` est unique. En revanche, **six familles de défauts** rendront l'app peu fiable chez de vrais utilisateurs :

1. **Perte de profil (Bloquant).** Le décodage JSON est strict : un champ absent ou une action inconnue (passage v1 → v2, retour de v2 à v1, fichier tronqué) font **jeter tout le profil**. L'app charge alors les défauts, puis **écrase le fichier** à la première modification. L'écriture n'est pas atomique. → REL-01, REL-02.
2. **Touches coincées ou volées.** L'ensemble `swallowed` est indexé par keyCode seulement et n'est jamais purgé. Un keyUp manqué (tap coupé, veille, saisie sécurisée) fait **avaler le keyUp suivant de cette touche dans n'importe quelle appli**. Exemple : une note du clavier-piano de FL reste tenue. La répétition d'une touche après relâchement du modificateur part vers FL sans keyUp. → REL-04.
3. **Mauvaise cible.** `frontmostApplication` n'est **pas** l'appli qui reçoit le clavier. Spotlight, Raycast/Alfred, le sélecteur d'émojis et les panneaux non activants laissent FL au premier plan : taper « 0 » dans Spotlight coupe la piste dans FL. → REL-05.
4. **Échecs silencieux.** Les touches d'action FL sont avalées même si le script n'est pas installé ou si le port est désactivé. La saisie sécurisée (Terminal, gestionnaires de mots de passe) éteint le tap sans que l'icône change. Le retrait de la permission Accessibilité n'est pas détecté. Une réinitialisation CoreMIDI n'est pas vue. Une deuxième instance de l'app vole le port MIDI. → REL-06 à REL-10.
5. **Tap sur le thread principal.** Tout blocage du main thread (SwiftUI, E/S, panneau) **ralentit le clavier de tout le système** jusqu'au time-out du tap. → REL-03.
6. **Script Python fragile.** Une seule fonction d'API absente au chargement (ancienne version de FL, ou fonctions plus récentes ajoutées en v2) **désactive toutes les actions**. D'autres défauts sont démontrés par les tests : canal -1, pattern précédent bloqué, CC inconnus ignorés en silence, exception qui s'échappe du bloc `except`. → REL-14, REL-24 à REL-27.

**Hypothèses du cahier des charges infirmées par la revue :**
- `UCKeyTranslate` n'est **pas** appelé à chaque frappe. Il ne sert qu'à l'affichage (`KeyCombo.display`) et au calcul des défauts.
- `NSWorkspace.frontmostApplication` est une propriété en cache, peu coûteuse.
- `NSAlert.runModal` ne bloque pas le tap : la source du tap est ajoutée en `.commonModes`, qui inclut le mode du panneau modal.

Le vrai risque de latence est ailleurs : c'est le partage du main thread (REL-03).

| Gravité | Nombre | IDs |
|---|---|---|
| Bloquant | 1 | REL-01 |
| Majeur | 13 | REL-02 à REL-14 |
| Mineur | 14 | REL-15 à REL-28 |

---

## 2. Tableau des problèmes

### Vue d'ensemble

| ID | Gravité | Fichier:ligne | Problème |
|---|---|---|---|
| REL-01 | **Bloquant** | Model.swift:113-121, 156-163 | Décodage strict : tout le profil est perdu puis écrasé |
| REL-02 | Majeur | Model.swift:184-188 | Écriture non atomique ; échecs ignorés |
| REL-03 | Majeur | EventTap.swift:24-25 | Tap exécuté sur le main thread : clavier système ralenti |
| REL-04 | Majeur | EventTap.swift:11, 43-45, 57-60 | `swallowed` : keyUp manqué, répétition orpheline, jamais purgé |
| REL-05 | Majeur | EventTap.swift:57, 70-75 | Premier plan ≠ destinataire du clavier (Spotlight, panneaux) |
| REL-06 | Majeur | EventTap.swift:64-65 | Touche avalée même si personne n'écoute le MIDI |
| REL-07 | Majeur | MIDIOut.swift:14, FLRemapApp.swift:31-33 | Deux instances : deux taps, deux sources « FL Remap » |
| REL-08 | Majeur | FLRemapApp.swift:66-80, EventTap.swift:14-37 | Permission retirée ou périmée, tap jamais recréé |
| REL-09 | Majeur | (absent) | Saisie sécurisée : remaps éteints en silence |
| REL-10 | Majeur | MIDIOut.swift:10-15, 19 | Pas de suivi CoreMIDI : réinitialisation, échec au démarrage |
| REL-11 | Majeur (à valider sur Mac) | Model.swift:198-206 | Défauts en conflit avec des raccourcis macOS (⌃←/⌃→) |
| REL-12 | Majeur | Model.swift:196-197 | Touches nues par défaut (« 0 », Tab) volées dans les champs texte |
| REL-13 | Majeur (à valider sur Mac) | EventTap.swift:77-85 | Cible postée alors que les modificateurs du déclencheur sont enfoncés |
| REL-14 | Majeur | device_FLRemap.py:57-76 | Une fonction d'API absente désactive tout le script |
| REL-15 | Mineur | EventTap.swift:51-55 | ⌃⌥⌘F maintenu : bascule à chaque répétition |
| REL-16 | Mineur | KeyNames.swift:42 | Bit passé au lieu du masque : touches mortes illisibles |
| REL-17 | Mineur | KeyNames.swift:5-13 | Pavé numérique, F13-F20, Entrée du pavé : noms faux ou ambigus |
| REL-18 | Mineur | Model.swift:147, EventTap.swift:77-85 | Changement de disposition clavier pendant l'exécution |
| REL-19 | Mineur | EditorView.swift:118-134 | Enregistreur : effacement impossible, moniteurs multiples, ⌃⌥⌘F |
| REL-20 | Mineur | Model.swift:167-182 | Avertissement de doublon inexact ; déclencheur = ⌃⌥⌘F |
| REL-21 | Mineur | Model.swift:139-141, 149-154 | Sauvegarde synchrone à chaque modification |
| REL-22 | Mineur | FLScriptInstaller.swift:20-38 | Dossier non vérifié, remplacement non atomique, version du script |
| REL-23 | Mineur | FLRemapApp.swift:35-37, 67 | Accueil marqué « vu » avant affichage ; deux fenêtres en même temps |
| REL-24 | Mineur | device_FLRemap.py:33-48 | Index de canal ou de piste non vérifié (-1) |
| REL-25 | Mineur | device_FLRemap.py:51-54 | `patternCount()` utilisé comme borne : précédent ou suivant bloqué |
| REL-26 | Mineur | device_FLRemap.py:83-89 | CC à 0 et CC inconnus non marqués `handled`, ignorés en silence |
| REL-27 | Mineur | device_FLRemap.py:90-93 | Exception qui s'échappe du `except` |
| REL-28 | Mineur | EventTap.swift:57, 70-75 | Ordre des tests : appel inutile sur chaque frappe |

---

### REL-01 — Décodage strict du profil : perte totale puis écrasement silencieux · **Bloquant**

- **Où :** `Model.swift:113-121` (`Remap`, champs `var x = défaut` non optionnels), `Model.swift:5-10` (`KeyCombo`), `Model.swift:156-163` (chargement).
- **Reproduction :**
  1. Retirer `"enabled"` d'une entrée de `profile.json` (fichier d'une version plus ancienne, ou édité à la main) **ou** y mettre `"action": "save"` (une action de la v2 relue par la v1).
  2. Relancer.
  3. Modifier n'importe quelle ligne.
- **Cause :**
  - Le `Decodable` synthétisé **n'utilise pas les valeurs par défaut** : il appelle `decode` (et non `decodeIfPresent`) pour chaque propriété non optionnelle. Une clé manquante ou une valeur d'enum inconnue fait échouer **tout le tableau** (`try?` → `nil`).
  - Les observateurs `didSet` ne sont pas appelés dans l'`init` de la classe. Les défauts ne sont donc pas sauvegardés tout de suite : le fichier abîmé reste en place jusqu'à la première modification, qui l'écrase.
- **Conséquence :**
  - Tous les raccourcis de l'utilisateur disparaissent sans message, puis sont **définitivement écrasés**.
  - C'est quasi certain au passage à la v2, qui ajoute des champs (`where`, profils) et des actions (`save`, `arm`…), et lors de tout retour en arrière.
  - Effet secondaire : tant qu'aucune modification n'a eu lieu, les défauts sont recalculés à chaque lancement selon la disposition **du moment**.
- **Correction :** fichier versionné, décodage tolérant ligne par ligne, conservation des valeurs inconnues, copie de secours du fichier illisible, message non bloquant.

```swift
struct ProfileFile: Codable {
    static let currentVersion = 2
    var version: Int
    var remaps: [Remap]
}

/// Décode un élément sans faire échouer le tableau entier.
struct Lossy<T: Decodable>: Decodable {
    let value: T?
    init(from d: Decoder) throws { value = try? T(from: d) }
}

extension KeyCombo {
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        keyCode = try c.decode(UInt16.self, forKey: .keyCode)
        command = try c.decodeIfPresent(Bool.self, forKey: .command) ?? false
        option  = try c.decodeIfPresent(Bool.self, forKey: .option)  ?? false
        control = try c.decodeIfPresent(Bool.self, forKey: .control) ?? false
        shift   = try c.decodeIfPresent(Bool.self, forKey: .shift)   ?? false
    }
}

extension Remap {
    // Ajouter `var actionRaw: String?` : conserve une action inconnue (profil v2 relu par la v1).
    init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        id      = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        trigger = try? c.decodeIfPresent(KeyCombo.self, forKey: .trigger)
        target  = try? c.decodeIfPresent(KeyCombo.self, forKey: .target)
        kind    = (try? c.decodeIfPresent(Kind.self, forKey: .kind)) ?? .flAction
        let raw = try c.decodeIfPresent(String.self, forKey: .action)
        if let raw, let a = FLAction(rawValue: raw) {
            action = a
        } else {
            action = .playPause
            actionRaw = raw
            enabled = false   // jamais exécuter une action « devinée »
        }
    }
}

enum ProfileLoader {
    static func load(from url: URL) -> (remaps: [Remap], warning: String?) {
        guard let data = try? Data(contentsOf: url) else { return (Store.defaults(), nil) } // 1er lancement
        let dec = JSONDecoder()
        if let file = try? dec.decode(VersionedLossy.self, from: data) {
            return (file.remaps.compactMap(\.value), nil)                                   // v2+
        }
        if let legacy = try? dec.decode([Lossy<Remap>].self, from: data) {
            return (legacy.compactMap(\.value), nil)                                        // v1 : tableau nu
        }
        let backup = url.deletingLastPathComponent()
            .appendingPathComponent("profile.corrupt-\(Int(Date().timeIntervalSince1970)).json")
        try? FileManager.default.copyItem(at: url, to: backup)
        return (Store.defaults(), "Profil illisible : une copie a été gardée (\(backup.lastPathComponent)).")
    }
    private struct VersionedLossy: Decodable { let version: Int; let remaps: [Lossy<Remap>] }
}
```

Dans `Store.init`, appeler `ProfileLoader.load` puis **sauvegarder immédiatement** si le fichier n'existait pas, pour figer les défauts de la disposition du 1er lancement. Afficher `warning` dans le menu, pas dans une alerte modale (voir REL-23). Dédoublonner les `id` au chargement : des UUID en double dans un `ForEach` donnent un comportement indéfini.

---

### REL-02 — Écriture non atomique, échecs ignorés · **Majeur**

- **Où :** `Model.swift:187` : `try? data.write(to: Store.fileURL)` (options vides, donc **non atomique**).
- **Reproduction :** coupure de courant, plantage ou disque plein pendant l'écriture ; ou deux instances qui écrivent en même temps (REL-07).
- **Conséquence :** fichier tronqué, donc REL-01 au lancement suivant. L'erreur est avalée par `try?` : l'utilisateur croit son profil enregistré.
- **Correction :**

```swift
static func write(_ remaps: [Remap], to url: URL) throws {
    let enc = JSONEncoder()
    enc.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try enc.encode(ProfileFile(version: ProfileFile.currentVersion, remaps: remaps))
    try data.write(to: url, options: [.atomic])   // fichier temporaire puis rename(2)
}
```

En cas d'erreur, publier `@Published var saveError: String?` et l'afficher dans l'éditeur. Voir aussi REL-21 pour le regroupement des écritures.

---

### REL-03 — Le tap tourne sur le thread principal · **Majeur**

- **Où :** `EventTap.swift:24-25` : `CFRunLoopAddSource(CFRunLoopGetMain(), …)`.
- **Mécanisme :** un tap actif (`.defaultTap`) **bloque la file d'événements de toute la session** jusqu'au retour du callback. Si le main thread est occupé, chaque frappe, **dans toutes les applis**, attend. macOS finit par couper le tap (`tapDisabledByTimeout`), puis le code le relance, et le cycle recommence.
- **Reproduction :**
  - premier `NSOpenPanel` (installation du script), qui peut prendre 1 à 2 s ;
  - liste de l'éditeur longue, redessinée à chaque modification (`isDuplicate` en O(n²), `KeyNames` via TIS pour chaque ligne) ;
  - écriture JSON sur un disque lent ;
  - futur handshake MIDI traité sur le main thread ;
  - en v2, recherche dans la liste d'actions pendant la frappe.
- **Conséquence :** micro-gels du clavier dans tout le système, frappes perdues pendant que le tap est coupé, touches coincées (REL-04).
- **Correction :** thread dédié avec sa propre boucle d'exécution, et état partagé en lecture seule derrière un verrou (macOS 13+).

```swift
import os

struct TapConfig {                         // instantané immuable, remplacé en bloc
    var enabled: Bool
    var index: [KeyCombo: Remap]
    var toggle: KeyCombo
    var flPIDs: Set<pid_t>
    var scriptAlive: Bool                  // v2 : handshake (REL-06)
}

final class EventTap {
    static let shared = EventTap()
    let config = OSAllocatedUnfairLock(initialState: TapConfig(enabled: true, index: [:],
                                                               toggle: KeyCombo(keyCode: 3),
                                                               flPIDs: [], scriptAlive: false))
    private var thread: Thread?
    private var runLoop: CFRunLoop?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    func start() -> Bool {
        let ready = DispatchSemaphore(value: 0)
        var ok = false
        let t = Thread { [self] in
            ok = createTap(on: CFRunLoopGetCurrent())
            ready.signal()
            if ok { CFRunLoopRun() }
        }
        t.name = "FLRemap.EventTap"
        t.qualityOfService = .userInteractive
        t.start()
        ready.wait()
        thread = t
        return ok
    }

    func stop() {   // indispensable pour REL-08
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let runLoop { CFRunLoopStop(runLoop) }
        tap = nil; source = nil; runLoop = nil; thread = nil
    }
}
```

`Store` pousse un nouveau `TapConfig` à chaque `rebuildIndex()`. Les bascules (`enabled.toggle()`) repartent vers le main thread par `DispatchQueue.main.async`, comme aujourd'hui. `MIDIReceived` et `CGEvent.post` peuvent être appelés depuis n'importe quel thread.

---

### REL-04 — `swallowed` : keyUp manqué, répétition orpheline, jamais purgé · **Majeur**

- **Où :** `EventTap.swift:11`, `43-45`, `57-60`.
- **Scénarios :**

| # | Séquence | Ce qui se passe aujourd'hui |
|---|---|---|
| a | keyDown « 0 » remappé dans FL → tap coupé ou saisie sécurisée active (REL-09) ou veille ou changement d'utilisateur → keyUp jamais vu | `29` reste dans `swallowed`. Plus tard, dans FL avec les remaps coupés (⌃⌥⌘F) ou dans n'importe quelle appli, « 0 » : le keyDown passe, **le keyUp est avalé**. Dans FL, le clavier-piano garde **la note tenue** ; un jeu ou une appli qui suit l'état des touches voit la touche bloquée. |
| b | ⌃ + → (pattern suivant), relâcher ⌃ en gardant → | Les répétitions arrivent sans ⌃. La combinaison ne correspond plus, donc **FL reçoit des keyDown de répétition sans keyDown initial**. Le keyUp final est avalé (`124` ∈ `swallowed`) : FL voit → enfoncée sans jamais la voir relâchée. |
| c | « 0 » enfoncé dans Safari (passe), ⌘⇥ vers FL, relâchement | Le keyUp passe vers FL, qui reçoit un keyUp orphelin. Bénin. |
| d | « 0 » enfoncé dans FL (avalé), ⌘⇥ vers Safari, relâchement | Le keyUp est avalé. Cohérent : Safari n'a rien vu. ✅ |
| e | Croissance de l'ensemble | Bornée par le nombre de keyCodes (< 128). **Pas de fuite**, mais des entrées périmées (a). |

- **Correction :** la **propriété d'un appui** se décide au keyDown initial et dure jusqu'au keyUp. Les répétitions suivent cette décision, quels que soient les modificateurs. Un keyDown neuf remet la touche à zéro, et tout l'état est purgé à chaque coupure.

```swift
private var owned: [Int64: Remap?] = [:]   // keyCode → remap qui possède l'appui (nil = bascule)

fileprivate func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
    let pass = Unmanaged.passUnretained(event)
    switch type {
    case .tapDisabledByTimeout, .tapDisabledByUserInput:
        owned.removeAll()                                  // les keyUp ont pu être perdus
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        return pass
    case .keyDown, .keyUp: break
    default: return pass
    }
    if event.getIntegerValueField(.eventSourceUserData) == Self.mark { return pass }
    let code = event.getIntegerValueField(.keyboardEventKeycode)

    if type == .keyUp { return owned.removeValue(forKey: code) != nil ? nil : pass }

    let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
    if isRepeat {
        guard let owner = owned[code] else { return pass }        // appui qui ne nous appartient pas
        if let r = owner, r.kind == .keystroke, let t = r.target { Self.post(t) }
        return nil                                                 // jamais de bascule ni de CC répétés
    }
    owned.removeValue(forKey: code)    // keyDown neuf : un keyUp manqué n'empoisonne plus la touche
    // … décision habituelle ; si avalé : owned[code] = remap (ou .some(nil) pour la bascule)
}
```

Purger aussi `owned` sur `NSWorkspace.willSleepNotification`, `didWakeNotification` et `sessionDidResignActiveNotification`, et à chaque `stop()` ou `start()`.

---

### REL-05 — « FL au premier plan » ≠ « FL reçoit la frappe » · **Majeur**

- **Où :** `EventTap.swift:57`, `70-75`.
- **Reproduction :**
  1. FL au premier plan.
  2. ⌘Espace (Spotlight), puis taper `10*3`. Variantes : Raycast, Alfred, sélecteur d'émojis (⌃⌘Espace), fenêtre de candidats d'une méthode de saisie, panneau Enregistrer sous de FL (servi par un processus à part).
- **Cause :** ces fenêtres sont des panneaux **non activants**. `frontmostApplication` reste FL Studio, mais le clavier va à un autre processus.
- **Conséquence :** « 0 » est avalé dans Spotlight et **la piste est coupée dans FL** ; Tab ne navigue plus dans le panneau d'enregistrement. Une variante de course (changement d'appli avant que la notification d'activation soit traitée) est décrite en SEC-03.
- **Correction (à valider sur Mac) :**
  - Utiliser le tap **annoté** (`.cgAnnotatedSessionEventTap`), où chaque événement porte le PID de l'appli destinataire.
  - Comparer ce PID à un ensemble de PID de FL tenu à jour par notifications.
  - Garder `frontmostApplication` en secours si le champ vaut 0.

```swift
CGEvent.tapCreate(tap: .cgAnnotatedSessionEventTap, place: .headInsertEventTap, …)

// dans handle :
let targetPID = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
let cfg = config.withLock { $0 }
let isFL = targetPID != 0 ? cfg.flPIDs.contains(targetPID) : Self.flStudioIsFrontmostFallback()

// tenu à jour sur le main thread :
NotificationCenter workspace : didLaunchApplication / didTerminateApplication / didActivateApplication
    → flPIDs = NSWorkspace.shared.runningApplications.filter(FLMatcher.isFL).map(\.processIdentifier)

enum FLMatcher {
    /// Liste blanche explicite (voir SEC-04) : à confirmer sur FL 20, 21, 2024 et 2025, Intel et Rosetta.
    static let bundleIDs: Set<String> = ["com.image-line.flstudio"]
    static func isFL(_ app: NSRunningApplication) -> Bool {
        guard let id = app.bundleIdentifier?.lowercased() else { return false }
        return bundleIDs.contains(id) || id.hasPrefix("com.image-line.flstudio")
    }
}
```

- **Autres cas de détection, vérifiés sans défaut :**
  - FL en plein écran : il reste au premier plan ✅.
  - FL sous Rosetta : même identifiant d'application ✅.
  - Plusieurs versions installées : elles partagent le même préfixe ✅.
  - Fenêtres de plugins internes : ce sont des fenêtres de FL, donc les remaps s'y appliquent, ce qui est documenté.
  - Plugins pontés (processus `ilbridge`) : l'actuel `contains("image-line")` les inclut, la liste blanche les exclurait. À décider et à documenter.
  - Le test sur le nom (« FL Studio 2025 ») devient inutile, et il est usurpable (SEC-04).

---

### REL-06 — Touches d'action FL avalées même si personne n'écoute · **Majeur**

- **Où :** `EventTap.swift:64-65`, `MIDIOut.swift:19`.
- **Reproduction :** utilisateur qui a passé l'étape d'installation du script, port « FL Remap » non activé dans FL, mauvais *Controller type*, `MIDIOut.ready == false` (REL-10), ou FL relancé sans le port.
- **Conséquence :** Tab et « 0 » (défauts) **ne font plus rien du tout dans FL**. La touche est avalée, le CC part dans le vide, rien n'est affiché. C'est le bug « l'app casse mes touches » le plus probable en support.
- **Correction :**
  - **v1 :** ne pas avaler une touche d'action FL si `!MIDIOut.shared.ready`, ni tant que l'utilisateur n'a pas réussi le bouton « Tester ».
  - **v2 :** utiliser l'état du handshake.

```swift
case .flAction:
    guard cfg.scriptAlive || !Settings.requireHandshake else { return pass }   // laisser FL recevoir la touche
    if !isRepeat { midi.send(cc: remap.action.cc) }
```

**Handshake v2 (exigences de fiabilité) :**
- Le script répond à un ping (par exemple SysEx ou CC 127) et pousse sa version dans `OnInit` puis toutes les N secondes depuis `OnIdle`.
- Côté app : état « vivant » si une réponse est arrivée il y a moins de 3 s, « inactif » après 3 pings sans réponse. Prévoir une **hystérésis**, car FL ne traite plus les scripts pendant un rendu, un scan de plugins ou une boîte de dialogue modale.
- Pendant « inconnu ou inactif » : **laisser passer les touches**.
- Comparer la version du script (REL-22) et proposer la réinstallation.
- L'authentification du canal est traitée en SEC-01.

---

### REL-07 — Deux instances de l'app · **Majeur**

- **Où :** `MIDIOut.swift:14` (code de retour ignoré), `FLRemapApp.swift:31-33` (aucun verrou d'instance unique).
- **Reproduction :** lancer `dist/FL Remap.app` puis `/Applications/FL Remap.app`, ou la copie montée depuis le `.dmg`. `LSUIElement` n'empêche pas deux instances lancées depuis deux chemins différents.
- **Conséquences :**
  - Deux taps : le second, inséré en tête (`headInsertEventTap`), voit tout en premier. ⌃⌥⌘F ne coupe que **cette** instance ; l'autre prend alors le relais. Vu de l'utilisateur, **la bascule ne marche pas**.
  - Deux sources « FL Remap » : `MIDIObjectSetIntegerProperty` échoue pour la seconde (`kMIDIIDNotUnique`), qui reçoit un ID aléatoire. FL reste branché sur l'ancienne, donc **les actions FL ne marchent plus** si c'est la seconde instance qui avale les touches.
  - Écritures concurrentes de `profile.json` (REL-02).
- **Correction :**

```swift
// AppDelegate.applicationWillFinishLaunching
let me = NSRunningApplication.current
let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
    .filter { $0.processIdentifier != me.processIdentifier }
if let first = others.first {
    first.activate()
    exit(0)
}

// MIDIOut
let err = MIDIObjectSetIntegerProperty(source, kMIDIPropertyUniqueID, uniqueID)
if err == kMIDIIDNotUnique { state = .conflict }   // affiché dans le menu : « une autre copie de FL Remap tourne »
```

L'uniqueID doit être aléatoire par installation (SEC-02). Le verrou d'instance repose alors sur l'identifiant d'application, pas sur l'ID MIDI.

---

### REL-08 — Permission Accessibilité retirée ou périmée ; tap jamais recréé · **Majeur**

- **Où :** `FLRemapApp.swift:66-80`, `EventTap.swift:14-28` (pas de `stop()`, source non conservée), `EventTap.swift:34-37`.
- **Scénarios :**
  1. **Retrait en cours de route :** l'utilisateur décoche FL Remap dans Réglages. Le tap ne reçoit plus rien (ou reçoit des `tapDisabledByUserInput`, et le code le réactive en boucle, cf. SEC-10). `accessibilityOK` et `tapRunning` restent à `true`, et l'interface affirme que tout va bien.
  2. **Re-autorisation :** la minuterie de surveillance a été arrêtée au premier succès et n'est jamais relancée. Le tap mort n'est pas recréé, il faut **quitter et relancer** l'app sans qu'elle le dise.
  3. **Mise à jour d'une app signée ad hoc** (`build.sh:20`) : la permission TCC est liée à l'empreinte du binaire. Après mise à jour, Réglages montre FL Remap **coché** mais `AXIsProcessTrusted()` renvoie `false` : l'app attend indéfiniment, l'utilisateur ne comprend pas. Cause racine : SEC-08.
  4. `tapCreate` renvoie `nil` alors que `AXIsProcessTrusted()` vaut `true` (état TCC incohérent) : `tapRunning = false`, aucune nouvelle tentative, aucun message.
- **Correction :** une surveillance permanente qui agit sur le tap dans les deux sens, et un message adapté.

```swift
final class TapSupervisor {
    private var timer: Timer?
    func run() {
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            let trusted = AXIsProcessTrusted()
            let status = AppStatus.shared
            status.accessibilityOK = trusted
            status.secureInput = IsSecureEventInputEnabled()        // REL-09
            switch (trusted, EventTap.shared.isRunning) {
            case (false, true):
                EventTap.shared.stop()
            case (true, false):
                status.tapRunning = EventTap.shared.start()
                status.staleTCC = !status.tapRunning               // « Retire FL Remap de la liste puis ajoute-le à nouveau »
            case (true, true) where !EventTap.shared.isEnabled:      // CGEvent.tapIsEnabled(tap:)
                EventTap.shared.restart()
            default:
                break
            }
            status.tapRunning = EventTap.shared.isRunning && EventTap.shared.isEnabled
        }
    }
}
```

- Plafonner les réactivations après `tapDisabledByTimeout` (par exemple 5 par minute), puis passer en `restart()` et prévenir l'utilisateur (SEC-10).
- Ajouter dans le menu une ligne d'état : Actif / Coupé / Permission manquante / Saisie sécurisée.

---

### REL-09 — Saisie sécurisée : remaps éteints en silence · **Majeur**

- **Où :** absent du code.
- **Reproduction :** Terminal ou iTerm avec « Saisie sécurisée au clavier » activée (elle reste active **pour toute la session**, même en arrière-plan), un gestionnaire de mots de passe resté ouvert sur un champ, une appli qui oublie de désactiver la saisie sécurisée.
- **Conséquence :** le tap ne reçoit plus aucune frappe. FL Remap « ne marche plus » dans FL, et l'icône montre pourtant l'état actif. Si l'activation survient entre un keyDown et son keyUp, on retombe sur REL-04 (a).
- **Correction :** interroger `IsSecureEventInputEnabled()` (Carbon) dans la surveillance de REL-08. Si la saisie sécurisée est active, afficher l'icône barrée et « Saisie sécurisée activée par une autre appli (ex. Terminal) ». Le PID responsable peut être lu dans `ioreg -l -w 0 | grep kCGSSessionSecureInputPID`, en option.

---

### REL-10 — CoreMIDI : aucun suivi, pas de recréation · **Majeur**

- **Où :** `MIDIOut.swift:10-15` (client sans callback de notification), `MIDIOut.swift:19` (`ready` figé).
- **Scénarios :**
  1. **Lancement à l'ouverture de session** : le serveur MIDI n'est pas encore prêt, `MIDIClientCreate` échoue, `ready = false` **pour toute la session**. Aucune action FL ne marche, et les touches restent avalées (REL-06).
  2. **Réinitialisation de CoreMIDI** (Configuration audio et MIDI, plantage de `MIDIServer`, débranchement d'interfaces) : la source disparaît, `ready` reste `true`, les CC partent dans le vide.
  3. **FL Remap relancé pendant que FL tourne** : la source est détruite puis recréée. Selon la version, FL ne revoit pas le port avant « Rescan » ou un redémarrage **(à valider sur Mac, FL 20.8, 21, 2024 et 2025)**.
  4. `MIDIPacketListAdd` renvoie `nil` en cas d'échec : la valeur est ignorée et un paquet vide est envoyé.
- **Correction :**

```swift
private init() { connect() }

private func connect() {
    var c = MIDIClientRef()
    let err = MIDIClientCreateWithBlock("FL Remap" as CFString, &c) { [weak self] n in
        if n.pointee.messageID == .msgSetupChanged { DispatchQueue.main.async { self?.verify() } }
    }
    guard err == noErr else { scheduleRetry(); return }
    client = c
    createSource()
}

private func verify() {   // la source existe-t-elle toujours ?
    var type: MIDIObjectType = .other
    var obj = MIDIObjectRef()
    if MIDIObjectFindByUniqueID(uniqueID, &obj, &type) != noErr { createSource() }
}

func send(cc: UInt8, channel: UInt8 = 15) {
    if !ready { connect() }   // nouvelle tentative paresseuse
    guard ready else { return }
    …
    guard MIDIPacketListAdd(ptr, size, packet, 0, bytes.count, bytes) != nil else { return }
    let status = MIDIReceived(source, ptr)
    if status != noErr { ready = false }
}
```

En v2, le handshake (REL-06) est le seul indicateur fiable de bout en bout, car il couvre aussi le scénario 3.

---

### REL-11 — Le profil par défaut entre en conflit avec des raccourcis macOS · **Majeur (à valider sur Mac)**

- **Où :** `Model.swift:205-206` (⌃→ et ⌃← : « Aller d'un espace à droite / à gauche » de Mission Control, **actifs par défaut**), `Model.swift:198-202` (⌃1 à ⌃5 : « Passer au bureau n », inactifs par défaut mais souvent activés).
- **Reproduction :** installation neuve, FL au premier plan, ⌃→.
- **Conséquence probable :** les raccourcis système sont traités par le WindowServer et le Dock. Selon le moment où ce traitement a lieu par rapport au tap de session, soit **l'espace change** et le pattern ne bouge pas, soit le remap marche et **casse la navigation entre espaces** dans FL. Dans les deux cas, le profil livré par défaut est contradictoire.
- **Correction :**
  - Retirer ⌃←/⌃→ des défauts (par exemple ⌃⌥←/⌃⌥→, ou les touches de la maquette v2 `⌃⌥…`).
  - En v2, lire les raccourcis système actifs (`CopySymbolicHotKeys()`, Carbon) pour alimenter l'alerte de conflit, au lieu de la liste figée `⌃1-9` de la maquette.

---

### REL-12 — Touches nues par défaut volées dans les champs texte de FL · **Majeur**

- **Où :** `Model.swift:196-197` (Tab et « 0 » sans modificateur).
- **Reproduction :** dans FL, renommer une piste « Kick 01 », chercher « 808 » dans le Browser, taper un nom de preset dans un plugin, ou jouer du clavier-piano (la touche « 0 » est une note).
- **Conséquence :** les « 0 » disparaissent du texte **et** la piste ou le canal sélectionné est coupé. Tab n'avance plus de champ en champ. Le README propose ⌃⌥⌘F en contournement, mais c'est le comportement **par défaut**.
- **Correction :**
  - Pas de touche nue dans les profils livrés (la maquette v2 « Recommandé » va dans ce sens ; « Style Ableton » non).
  - Garder l'avertissement « Touche seule » de la maquette, avec une confirmation explicite.
  - Piste à valider pour la v2 : le script peut pousser l'identifiant de la fenêtre FL au premier plan (`ui.getFocusedFormID()`) via le handshake. Si ce n'est ni une des fenêtres principales ni un plugin, l'app laisse passer les touches nues.

---

### REL-13 — Cible d'un remap clavier postée pendant que les modificateurs du déclencheur sont enfoncés · **Majeur (à valider sur Mac)**

- **Où :** `EventTap.swift:77-85`.
- **Scénario :** déclencheur ⌃⌥R → cible ⌘S. Le tap n'intercepte pas `flagsChanged`, donc FL a déjà reçu ⌃ enfoncé et ⌥ enfoncé. Le keyDown S posté porte `flags = ⌘` mais aucun `flagsChanged(⌘)` ne le précède. Une appli qui lit l'**état** des modificateurs (`NSEvent.modifierFlags` de classe, `CGEventSourceFlagsState(.hidSystemState)`, ou une boucle de clavier multiplateforme comme celle de FL) voit ⌃⌥ et non ⌘, donc **mauvais raccourci, ou aucun**. La source `.hidSystemState` mélange en plus l'état des événements postés à celui du clavier physique.
- **Correction :**
  - Poster des `flagsChanged` encadrants : relâcher les modificateurs du déclencheur, appuyer ceux de la cible, envoyer la touche, puis rétablir l'état physique.
  - Utiliser une source privée.

```swift
private static let src = CGEventSource(stateID: .privateState)

private static func post(_ target: KeyCombo, physical: CGEventFlags) {
    func flags(_ f: CGEventFlags) {
        let e = CGEvent(source: src)
        e?.type = .flagsChanged
        e?.flags = f
        e?.setIntegerValueField(.eventSourceUserData, value: mark)
        e?.post(tap: .cgSessionEventTap)
    }
    flags(target.cgFlags)                                 // état = modificateurs de la cible uniquement
    for down in [true, false] { /* keyDown / keyUp avec flags = target.cgFlags, marqués */ }
    flags(physical.intersection([.maskCommand, .maskAlternate, .maskControl, .maskShift]))   // retour à l'état réel
}
```

Pour un déclencheur tenu (auto-répétition), décider si la cible est « tapée » à chaque répétition (comportement actuel) ou tenue jusqu'au keyUp. La v2 doit le préciser dans l'interface.

---

### REL-14 — Script Python : une fonction absente désactive tout · **Majeur** *(test `test_REL_PY1`, échoue)*

- **Où :** `device_FLRemap.py:57-76`. `ACTIONS` évalue `transport.start`, `general.undoUp`, `ui.nextWindow`… **au chargement du module**.
- **Reproduction :** API FL plus ancienne, fonction renommée ou retirée, ou, plus probable, une action v2 qui utilise une fonction récente (`patterns.clonePattern`, `mixer.armTrack`, `transport.globalTransport(FPT_CountDown)`, sauvegarde…) chargée sur une version de FL qui ne l'a pas.
- **Conséquence :** `AttributeError` à l'import, et FL ne charge pas le script. **Toutes** les actions sont mortes, pas seulement la fonction manquante. Le seul message est dans *View › Script output*.
- **Correction :** résoudre chaque fonction au moment de l'appel (appel paresseux), lire les constantes avec une valeur de repli, afficher un message par action indisponible. Version complète, testée, en **annexe B** :

```python
def _api(module_name, func_name):
    def call(*args):
        func = getattr(__import__(module_name), func_name, None)
        if func is None:
            _hint("FL Remap : %s.%s indisponible dans cette version de FL Studio" % (module_name, func_name))
            return None
        return func(*args)
    return call

ACTIONS = {20: _api("transport", "start"), …, 37: _api("ui", "nextWindow")}
```

Documenter la version minimale de FL : le scripting Python MIDI est arrivé avec FL 20.7. Pour les actions v2, filtrer par `general.getVersion()` (version de l'API) et le remonter dans le handshake, pour que l'app grise les actions non prises en charge.

---

### REL-15 — ⌃⌥⌘F maintenu bascule à chaque auto-répétition · Mineur

- **Où :** `EventTap.swift:51-55` : le test de bascule est fait avant toute vérification de répétition.
- **Conséquence :** si l'appui dure plus que le délai de répétition (environ 0,5 s par défaut, moins si l'utilisateur l'a raccourci), l'état final est aléatoire.
- **Correction :** `if combo == cfg.toggle { owned[code] = .some(nil); if !isRepeat { toggle() }; return nil }`. C'est couvert par le modèle de propriété de REL-04.

### REL-16 — Bit passé au lieu du masque dans `UCKeyTranslate` · Mineur

- **Où :** `KeyNames.swift:42` : `OptionBits(kUCKeyTranslateNoDeadKeysBit)` vaut **0** (c'est le numéro du bit), donc les touches mortes **sont** traitées.
- **Reproduction :** AZERTY, assigner la touche `^` (keyCode 33), ou `´` en QWERTZ (24).
- **Conséquence :** longueur 0, donc `nil`, donc l'affichage « Touche 33 ». `keyCode(for:)` ne trouve jamais une touche morte.
- **Correction :** `OptionBits(kUCKeyTranslateNoDeadKeysMask)` (vaut `1 << kUCKeyTranslateNoDeadKeysBit`).

### REL-17 — Noms et correspondances : pavé numérique, F13-F20, touches JIS · Mineur

- **Où :** `KeyNames.swift:5-13`.
- **Constats :**
  - Le « 0 » du pavé numérique (82) s'affiche « 0 », comme le « 0 » de la rangée (29). Deux lignes identiques à l'écran, mais seule l'une marche.
  - Le profil par défaut ne réagit **pas** au « 0 » du pavé numérique.
  - L'Entrée du pavé (76) produit le caractère de contrôle `\u{3}`, que `trimmingCharacters(.whitespaces)` ne retire pas : libellé invisible ou corrompu.
  - F13-F20 (105, 107, 113, 106, 64, 79, 80, 90) et Aide (114) donnent des caractères de la zone privée Unicode.
  - Les touches JIS (英数 102, かな 104, ¥ 93, _ 94) n'ont pas de nom.
  - Écart ISO/ANSI : la touche § ou `<` (10 ou 50) change de position selon `LMGetKbdType()` quand un clavier interne ANSI cohabite avec un clavier externe ISO.
- **Correction :**
  - Compléter `special` : pavé `82…92 → "0 (pavé)"…`, `76 → "⌤"`, `71 → "⌧"`, F13-F20, touches JIS.
  - Filtrer les caractères de contrôle et de zone privée (`CharacterSet.controlCharacters`, plage U+F700…U+F8FF).
  - Proposer « 0 et 0 du pavé » comme option d'un déclencheur, ou l'expliquer dans l'éditeur.

### REL-18 — Changement de disposition clavier pendant l'exécution · Mineur

- **Où :** `Model.swift:147` (`toggleCombo` calculé une seule fois), `EventTap.swift:77-85` (la cible est postée par keyCode).
- **Constats :**
  - Les libellés ne sont rafraîchis qu'au hasard d'un redessin : aucun observateur de `kTISNotifySelectedKeyboardInputSourceChanged`.
  - ⌃⌥⌘F reste à la position du « F » de la disposition du lancement (Dvorak ↔ QWERTY).
  - Pour une cible « ⌥M » enregistrée en AZERTY puis postée en QWERTY, le même keyCode produit « ; » : si FL interprète ses raccourcis **par caractère**, la cible change de sens **(à valider sur Mac)**.
  - « Dvorak – QWERTY ⌘ » : macOS bascule en QWERTY quand ⌘ est enfoncé, mais `defaults()` résout `z` avec la table Dvorak, donc ⌘⇧Z tombe sur la mauvaise touche.
- **Correction :**
  - Observer `DistributedNotificationCenter` `kTISNotifySelectedKeyboardInputSourceChanged`, puis vider le cache de `KeyNames`, recalculer `toggleCombo` et forcer `objectWillChange`.
  - Pour les cibles (raccourcis **de FL**), stocker aussi le caractère (`targetChar`) et résoudre le keyCode au moment de poster.

### REL-19 — Enregistreur de raccourcis (éditeur) · Mineur

- **Où :** `EditorView.swift:118-134`.
- **Constats :**
  1. **Impossible d'effacer** un déclencheur ou une cible : Échap seul annule, ce qui est voulu, mais rien ne remet à `nil`. Ajouter ⌫ seul pour « effacer », ou un bouton ✕.
  2. Clic sur un 2ᵉ champ pendant qu'un 1ᵉʳ enregistre : deux moniteurs locaux. Le premier renvoie `nil`, la frappe va donc **au mauvais champ**, et le 2ᵉ reste en attente. Il faut un coordinateur unique (`@Published var recordingID: UUID?` dans un `EnvironmentObject`), qui arrête l'enregistrement précédent.
  3. Enregistrer ⌃⌥⌘F : le tap l'avale et **coupe les remaps**, le champ reste en attente. Pendant un enregistrement, l'éditeur doit suspendre la bascule (`config.recording = true`) ou refuser cette combinaison avec un message.
  4. Raccourcis système (⌘⇥, ⌘Espace, ⌃→ si actif) : jamais reçus, donc attente infinie. Ajouter un délai (5 s) et un indice « macOS utilise peut-être ce raccourci ».
  5. L'enregistrement continue si la fenêtre perd le focus. L'arrêter sur `NSWindow.didResignKeyNotification`.
  6. Vérifié sans défaut : la suppression pendant `ForEach($store.remaps)` est différée et faite par identifiant, et `onDisappear` arrête le moniteur. Pas de crash d'index. La fenêtre `Window(id:"editor")` est unique : un second `openWindow` la ramène au premier plan.
  7. macOS 14+ : `NSApp.activate(ignoringOtherApps:)` est déprécié et souvent ignoré, donc la fenêtre peut s'ouvrir derrière FL. Utiliser `NSApp.activate()` et `window.makeKeyAndOrderFront`.

### REL-20 — Avertissement de doublon inexact ; déclencheur égal à ⌃⌥⌘F · Mineur

- **Où :** `Model.swift:167-170` comparé à `174-182`.
- **Constats :**
  - `isDuplicate` compte aussi les lignes ignorées par l'index (cible de remap clavier vide). Le message « seul le premier compte » est alors faux : c'est le second qui compte.
  - Un déclencheur égal à `toggleCombo` n'est jamais exécuté et ne déclenche aucun avertissement.
  - L'ordre de priorité dépend de l'ordre d'affichage, ce qui deviendra fragile avec les catégories et les fenêtres de la v2.
- **Correction :** une seule fonction `Store.validate() -> [UUID: [Issue]]` qui reprend **exactement** la logique de `rebuildIndex`, et l'utiliser à la fois pour l'index et pour l'interface. En v2, la clé d'unicité devient `(trigger, where)`, avec une priorité explicite : fenêtre précise, puis « Partout ».

### REL-21 — Sauvegarde synchrone à chaque modification · Mineur

- **Où :** `Model.swift:139-141` (`didSet` → `rebuildIndex()` + `save()`), `149-154` (`fileURL` crée le dossier à **chaque** accès).
- **Conséquence :** chaque interrupteur ou sélecteur provoque un encodage et une écriture disque sur le main thread, qui est aussi le thread du tap aujourd'hui (REL-03). « Restaurer les défauts » écrase sans confirmation.
- **Correction :**
  - Regrouper les écritures (300 ms) sur une file utilitaire, et forcer l'écriture dans `applicationWillTerminate`.
  - Calculer `fileURL` une seule fois (`static let`).
  - Demander confirmation avant restauration, avec une annulation possible (garder l'ancien tableau en mémoire).

```swift
private var pendingSave: DispatchWorkItem?
private func scheduleSave() {
    pendingSave?.cancel()
    let snapshot = remaps
    let work = DispatchWorkItem { [url = Self.fileURL] in try? ProfileLoader.write(snapshot, to: url) }
    pendingSave = work
    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.3, execute: work)
}
```

### REL-22 — Installeur du script : dossier non vérifié, remplacement non atomique, version · Mineur

- **Où :** `FLScriptInstaller.swift:20-38`.
- **Constats :**
  - Le choix fait dans `NSOpenPanel` n'est pas vérifié : choisir « Settings » au lieu de « Hardware » affiche « Script installé ✅ » alors que FL ne le verra jamais.
  - `removeItem` puis `copyItem` : entre les deux, plus de script (voir aussi SEC-06).
  - L'accès à `~/Documents` déclenche une demande d'autorisation macOS. En cas de refus, `fileExists` renvoie `false` et le panneau s'ouvre sans explication.
  - Une mise à jour de l'app **ne met pas à jour le script** : les actions nouvelles sont ignorées en silence (REL-26).
- **Correction :**
  - Exiger que `url.lastPathComponent == "Hardware"`, ou proposer `url/Hardware`.
  - Utiliser `FileManager.replaceItemAt(dest, withItemAt: tmp)`.
  - Ajouter `SCRIPT_VERSION = n` dans le script. Au lancement, si le fichier installé a une version inférieure, proposer la mise à jour. Le handshake v2 compare aussi la version **chargée** dans FL.

### REL-23 — Accueil marqué « vu » avant affichage ; deux fenêtres en même temps · Mineur

- **Où :** `FLRemapApp.swift:35-37` et `67`.
- **Constats :**
  - `didOnboard = true` est écrit **avant** `runModal()` : un plantage ou un « Quitter » à ce moment fait perdre l'accueil pour toujours.
  - La demande Accessibilité de macOS (`AXIsProcessTrustedWithOptions(prompt: true)`) et l'alerte d'accueil s'ouvrent **en même temps** et se superposent.
- **Correction :** écrire le drapeau après le choix de l'utilisateur. Afficher l'accueil d'abord, puis demander la permission depuis son bouton, comme dans la maquette v2 (« Autoriser le clavier »).

### REL-24 — Script : index de canal ou de piste non vérifié · Mineur *(test `test_REL_PY2`, échoue)*

- **Où :** `device_FLRemap.py:33-48`.
- **Constat :** aucune vérification de bornes. Si `selectedChannel()` renvoie -1 (aucun canal sélectionné, groupe de filtres vide), le script appelle `muteChannel(-1)`. L'exception est rattrapée, mais le message affiché est cryptique (« Channel index out of range »).
- **Correction :** vérifier `0 <= ch < channels.channelCount()` et `trackNumber() >= 0`, sinon afficher « aucun canal sélectionné ». Voir l'annexe B.

### REL-25 — Script : `patternCount()` utilisé comme borne · Mineur *(test `test_REL_PY3`, échoue)*

- **Où :** `device_FLRemap.py:51-54`.
- **Constat :** la borne de saut est `patternCount()`. S'il y a des trous (patterns supprimés ou vides), le pattern courant peut dépasser ce nombre : **« pattern précédent » ne fait plus rien** (pattern 7 affiché avec 4 patterns comptés).
- **Correction :** borner par `patterns.patternMax()` (avec repli à 999), et contraindre la cible entre 1 et le maximum.

### REL-26 — Script : CC à 0 et CC inconnus · Mineur *(tests `test_REL_PY4`, `test_REL_PY5`, échouent)*

- **Où :** `device_FLRemap.py:83-89`.
- **Constats :**
  - Un CC connu à valeur 0, ou un CC inconnu sur le canal 16, n'est pas marqué `handled`. FL le traite alors comme un contrôleur générique : lien de contrôleur, « dernier paramètre touché », voire automation enregistrée pendant un REC.
  - Un CC inconnu (app plus récente que le script) est ignoré **sans message**.
- **Correction :** sur le canal 16, tout CC appartient à FL Remap : `event.handled = True` d'abord, puis `return` si la valeur vaut 0, puis afficher « action inconnue, réinstalle le script » si le CC n'est pas dans la table.
- **Attention :** si l'utilisateur affecte par erreur le *Controller type* « FL Remap » à son vrai clavier MIDI, le canal 16 de ce clavier sera avalé. L'indiquer dans l'aide.

### REL-27 — Script : exception qui s'échappe du bloc `except` · Mineur *(test `test_REL_PY6`, échoue)*

- **Où :** `device_FLRemap.py:90-93`.
- **Constat :** `ui.setHintMsg` est appelé **dans** le `except`. S'il lève une exception (fonction absente, appel hors contexte), elle sort de `OnMidiMsg`. De plus, le test d'en-tête (`event.midiId`, `midi.MIDI_CONTROLCHANGE`) est en dehors du `try`.
- **Correction :** un `try` qui englobe toute la fonction, et un `_hint()` qui ne lève jamais d'exception (il écrit aussi avec `print` vers *Script output*). Voir l'annexe B.

### REL-28 — Ordre des tests : appel inutile sur chaque frappe · Mineur

- **Où :** `EventTap.swift:57`.
- **Constat :** `flStudioIsFrontmost()` (deux `String` allouées par `lowercased()`) est appelé **avant** la recherche dans le dictionnaire, donc à chaque frappe dans toutes les applis. Le coût est faible, de l'ordre de la microseconde, mais inutile et fait sur le main thread.
- **Correction :** `guard cfg.enabled, let remap = cfg.index[combo], isFL(targetPID) else { return pass }`. Avec REL-05, l'ensemble des PID de FL est en cache et la vérification est en temps constant.

---

## 3. Exigences de fiabilité pour la v2 (maquette `Main.dc.html`)

| Fonction v2 | Risque | Exigence |
|---|---|---|
| Raccourcis par fenêtre (« Où ? » : Piano Roll, Playlist, Mixer) | L'app ne sait pas quelle fenêtre FL a le focus. Si elle avale une touche qui ne concerne pas la fenêtre active, la touche est **perdue** : le script ne peut pas la réinjecter. | Le script pousse `ui.getFocused…` à chaque `OnRefresh(HW_Dirty_FocusedWindow)` vers l'app (sortie MIDI). L'app n'avale que si l'état est **frais** (moins de 2 s) **et** correspond. État inconnu : laisser passer. Pour les actions FL uniquement, une alternative plus sûre est d'envoyer un CC unique par déclencheur et de laisser **le script** choisir selon la fenêtre. |
| Handshake bidirectionnel | Pas de réponse pendant un rendu, un scan de plugins ou un dialogue modal FL. Port de sortie FL à configurer (numéro de *Port* identique), ce qui ajoute une étape et une cause d'échec. Retour forgeable (SEC-01). | Hystérésis (REL-06). Message « Lien inactif » avec action « Réparer » ciblée (port d'entrée, port de sortie, *Controller type*, version du script). Ne jamais bloquer les touches sur un handshake en échec. |
| Profils (Recommandé, Style Ableton, Vide) | Changement de profil pendant un appui ; profils importés (SEC-05) ; migration. | Le modèle de propriété de REL-04 isole l'appui en cours. Format versionné (REL-01). Valider chaque profil importé. |
| Alertes de conflit | La table `FL_USED` est figée alors qu'elle dépend de la version de FL et de la disposition clavier ; la liste figée `⌃1-9` ne reflète pas la configuration macOS réelle. | Raccourcis système lus via `CopySymbolicHotKeys()` (REL-11). Table FL versionnée et exprimée **par caractère**, résolue selon la disposition active (REL-18). Doublons calculés par la même fonction que l'index (REL-20), avec la clé `(trigger, where)`. |
| Nouvelles actions (sauvegarder, armer, décompte, quantize…) | Fonctions d'API récentes (REL-14) ; « Sauvegarder » est destructeur (SEC-01). | Appels paresseux avec message par action ; version de l'API envoyée dans le handshake ; actions non prises en charge grisées dans l'app. |

---

## 4. Tests à ajouter

### 4.1 Refactorisation préalable (Swift) : rendre la logique testable

Extraire la décision du tap dans une structure **sans AppKit ni CoreGraphics**. Elle pourra alors tourner avec `swift test` sur macOS **et** sur la CI Linux.

```swift
struct Mods: OptionSet, Hashable { let rawValue: UInt8
    static let cmd = Mods(rawValue: 1), opt = Mods(rawValue: 2), ctrl = Mods(rawValue: 4), shift = Mods(rawValue: 8) }

struct KeyEvent {
    enum Kind { case down, up, tapDisabled }
    var kind: Kind
    var keyCode: UInt16
    var mods: Mods
    var isRepeat = false
    var isOwn = false
    var targetPID: Int32 = 0
}

enum Effect: Equatable { case sendCC(UInt8), post(KeyCombo), toggleEnabled, reenableTap }

protocol FLPresence { func isFL(pid: Int32) -> Bool }

struct KeyRouter {
    var config: TapConfig
    private(set) var owned: [UInt16: Remap?] = [:]
    /// Retourne (avaler ?, effets à exécuter)
    mutating func route(_ e: KeyEvent, fl: FLPresence) -> (swallow: Bool, effects: [Effect])
}

protocol ProfileStorage { func read() throws -> Data?; func write(_ d: Data) throws; func backup(_ d: Data) throws }
protocol KeyboardLayout { func character(for keyCode: UInt16) -> String? }   // fausses dispositions AZERTY / QWERTZ / Dvorak / russe
protocol MIDISink { var isReady: Bool { get }; func send(cc: UInt8) -> Bool }
protocol TrustChecker { func isTrusted() -> Bool; func secureInput() -> Bool }
protocol TapControl { var isRunning: Bool { get }; var isEnabled: Bool { get }; func start() -> Bool; func stop() }
```

### 4.2 Tests unitaires Swift (XCTest)

| # | Test | Attendu | Couvre |
|---|---|---|---|
| T1 | down(⌃→) puis up(→) dans FL | down et up avalés, un seul `sendCC(35)` | nominal |
| T2 | down(0) dans FL, puis up(0) avec un PID cible Safari | up avalé, `owned` vide | REL-04 (d) |
| T3 | down(0) avalé, `tapDisabled`, down(0) avec remaps coupés, up(0) | 2ᵉ down passe, **up passe** | REL-04 (a) |
| T4 | down(⌃→), répétitions sans ⌃, up | répétitions **avalées**, 0 CC en plus, up avalé | REL-04 (b) |
| T5 | ⌃⌥⌘F puis 5 répétitions | **un seul** `toggleEnabled` | REL-15 |
| T6 | ⌃→ avec Fn, pavé numérique et Verr. Maj | correspond | non-régression flags |
| T7 | keypad 0 (82) avec un profil sur 29 | passe (comportement documenté) | REL-17 |
| T8 | événement marqué (`isOwn`) | passe, aucun effet | anti-boucle |
| T9 | down(0) avec un PID cible Spotlight, FL au premier plan | passe | REL-05 |
| T10 | action FL avec `scriptAlive == false` | passe | REL-06 |
| T11 | remap clavier A→B, puis B→C | B posté, pas de chaîne | anti-boucle |
| T12 | Profil v1 sans `enabled` ni `id` | chargé, `enabled == true`, nouvel `id` | REL-01 |
| T13 | Profil avec `"action":"save"` (inconnue) | ligne conservée, **désactivée**, `actionRaw == "save"` | REL-01 |
| T14 | JSON tronqué | `backup()` appelé, défauts chargés, **pas d'écriture** avant une modification | REL-01 |
| T15 | Stockage qui lève une erreur à l'écriture | `saveError` renseigné, ancien contenu intact | REL-02 |
| T16 | 50 modifications en 100 ms | **1** écriture | REL-21 |
| T17 | Doublon avec une ligne de remap clavier sans cible | pas d'avertissement sur la ligne valide | REL-20 |
| T18 | Déclencheur = ⌃⌥⌘F | problème « réservé » | REL-20 |
| T19 | Fausse disposition AZERTY : `keyCode(for:"z")`, `name(33)` | `13`, `"^"` | REL-16, REL-18 |
| T20 | Fausse disposition russe : `defaults()` | positions de repli QWERTY (6, 46, 37) | REL-18 |
| T21 | `KeyNames.name(76)`, `name(105)` | `"⌤"`, `"F13"` (pas de caractère de contrôle) | REL-17 |
| T22 | `MIDIOut` : octets envoyés | `[0xBF, cc, 127]` | nominal |
| T23 | `MIDISink` non prêt puis prêt | nouvelle tentative paresseuse réussie | REL-10 |
| T24 | Superviseur : confiance true → false | `stop()` appelé, `accessibilityOK == false` | REL-08 |
| T25 | Superviseur : false → true, `start()` échoue | `staleTCC == true` | REL-08 |
| T26 | Superviseur : saisie sécurisée active | `secureInput == true`, icône « barrée » | REL-09 |
| T27 | Instance unique (`RunningApps` injecté) | deuxième instance : sortie | REL-07 |

### 4.3 Tests manuels sur Mac (liste de contrôle avant publication)

1. Spotlight, Raycast, panneau d'émojis et panneau Enregistrer sous de FL, avec FL au premier plan : « 0 » et Tab doivent passer (REL-05).
2. Terminal avec Saisie sécurisée au clavier activée : l'état affiché passe à « Saisie sécurisée » (REL-09).
3. Décocher puis recocher l'Accessibilité : l'état suit, et le tap est recréé sans relancer l'app (REL-08).
4. Mettre à jour l'app (binaire signé ad hoc différent) : message « permission à renouveler » (REL-08).
5. ⌃→ avec Mission Control par défaut (REL-11).
6. Remap ⌃⌥R → ⌘S dans FL : la sauvegarde se déclenche-t-elle ? (REL-13).
7. Relancer FL Remap pendant que FL tourne, puis relancer FL : le port revient-il ? Tester aussi Configuration audio et MIDI › Réinitialiser (REL-10).
8. Veille pendant une touche tenue ; changement rapide d'utilisateur (REL-04).
9. Lancer deux copies de l'app (REL-07).
10. Charger le script dans FL 20.8, 21, 2024, 2025, et FL sous Rosetta.

### 4.4 Tests Python (avec modules simulés)

Fichier complet en **annexe A**. Il tourne avec `python3 -m unittest`, sans FL. Le chemin du script testé est réglable par `FLREMAP_SCRIPT`, ce qui permet de tester aussi la version corrigée.

| Test | Script actuel | Script corrigé (annexe B) |
|---|---|---|
| `TestNominal` (6 tests : lecture, CC 20-37, autre canal, Note On, exception attrapée, `OnInit`) | ✅ | ✅ |
| `TestSwiftPythonSync.test_cc_tables_match` (CC de `Model.swift` = clés `ACTIONS`) | ✅ | ✅ |
| `test_REL_PY1_missing_api_function_breaks_whole_script` | ❌ AttributeError à l'import | ✅ |
| `test_REL_PY2_no_selected_channel` | ❌ `muteChannel(-1)` | ✅ |
| `test_REL_PY3_prev_pattern_blocked_when_current_beyond_count` | ❌ pattern inchangé | ✅ |
| `test_REL_PY4_cc_value_zero_not_marked_handled` | ❌ | ✅ |
| `test_REL_PY5_unknown_cc_on_our_channel_leaks` | ❌ | ✅ |
| `test_REL_PY6_hint_failure_inside_except_propagates` | ❌ RuntimeError sortie | ✅ |

**Tests Python à ajouter ensuite :**
- Handshake v2 : réponse au ping, version envoyée dans `OnInit`.
- Limitation de débit (SEC-01/10) : 100 CC en 100 ms donnent N actions au plus.
- Raccourcis par fenêtre : un même CC dispatché selon `ui.getFocused`.
- `general.getVersion()` trop bas : action refusée avec un message.

Ajouter un job `python -m unittest` dans `.github/workflows/build.yml` (sur `ubuntu-latest`, quelques secondes).

---

## Annexe A — `test_device_flremap.py` (tests Python avec modules FL simulés)

Exécution : `FLREMAP_ROOT=/chemin/du/depot python3 -m unittest -v test_device_flremap.py`. Sur le script actuel : **13 tests, 6 échecs** (REL-PY1 à PY6 = REL-14, 24, 25, 26 ×2, 27).

```python
"""Tests du script FL Studio device_FLRemap.py avec des modules FL simulés.

Lancement :  python3 -m unittest -v test_device_flremap.py
Variable FLREMAP_ROOT = racine du dépôt (défaut /home/claude/FLRemap).
"""
import importlib.util
import os
import re
import sys
import types
import unittest

ROOT = os.environ.get("FLREMAP_ROOT", "/home/claude/FLRemap")
SCRIPT = os.environ.get("FLREMAP_SCRIPT", os.path.join(ROOT, "Resources", "device_FLRemap.py"))
MODEL = os.path.join(ROOT, "Sources", "FLRemap", "Model.swift")

FL_MODULES = ("midi", "transport", "ui", "general", "mixer", "channels", "patterns")


class Recorder:
    """Garde la trace des appels faits à l'API FL simulée."""
    def __init__(self):
        self.calls = []

    def fn(self, name, ret=None, side_effect=None):
        def _f(*args):
            self.calls.append((name, args))
            if side_effect:
                return side_effect(*args)
            return ret
        return _f


def build_fl(rec, focused=None, n_channels=8, n_tracks=126, pattern=1, pattern_count=4,
             selected_channel=0, missing=()):
    """Construit des modules FL cohérents avec l'API documentée (bornes vérifiées)."""
    focused = set(focused or ())
    state = {"pattern": pattern, "count": pattern_count}

    midi = types.ModuleType("midi")
    midi.MIDI_CONTROLCHANGE = 0xB0
    midi.MIDI_NOTEON = 0x90
    midi.widMixer, midi.widChannelRack, midi.widPlaylist, midi.widPianoRoll, midi.widBrowser = 0, 1, 2, 3, 4
    midi.FPT_Metronome = 110

    def check_channel(i):
        if not 0 <= i < n_channels:
            raise TypeError("Channel index out of range")

    def check_track(i):
        if not 0 <= i < n_tracks:
            raise TypeError("Track index out of range")

    def jump(i):
        if not 1 <= i <= 999:
            raise TypeError("Pattern index out of range")
        state["pattern"] = i

    transport = types.ModuleType("transport")
    transport.start = rec.fn("transport.start")
    transport.stop = rec.fn("transport.stop")
    transport.record = rec.fn("transport.record")
    transport.setLoopMode = rec.fn("transport.setLoopMode")
    transport.globalTransport = rec.fn("transport.globalTransport", 1)

    ui = types.ModuleType("ui")
    ui.showWindow = rec.fn("ui.showWindow")
    ui.setFocused = rec.fn("ui.setFocused")
    ui.getFocused = rec.fn("ui.getFocused", side_effect=lambda w: 1 if w in focused else 0)
    ui.setHintMsg = rec.fn("ui.setHintMsg")
    ui.nextWindow = rec.fn("ui.nextWindow")

    general = types.ModuleType("general")
    general.undoUp = rec.fn("general.undoUp")
    general.undoDown = rec.fn("general.undoDown")

    mixer = types.ModuleType("mixer")
    mixer.trackNumber = rec.fn("mixer.trackNumber", 3)
    mixer.muteTrack = rec.fn("mixer.muteTrack", side_effect=lambda i, *a: check_track(i))
    mixer.soloTrack = rec.fn("mixer.soloTrack", side_effect=lambda i, *a: check_track(i))

    channels = types.ModuleType("channels")
    channels.selectedChannel = rec.fn("channels.selectedChannel", selected_channel)
    channels.channelCount = rec.fn("channels.channelCount", n_channels)
    channels.muteChannel = rec.fn("channels.muteChannel", side_effect=lambda i, *a: check_channel(i))
    channels.soloChannel = rec.fn("channels.soloChannel", side_effect=lambda i, *a: check_channel(i))

    patterns = types.ModuleType("patterns")
    patterns.patternNumber = rec.fn("patterns.patternNumber", side_effect=lambda: state["pattern"])
    patterns.patternMax = rec.fn("patterns.patternMax", 999)
    patterns.patternCount = rec.fn("patterns.patternCount", side_effect=lambda: state["count"])
    patterns.jumpToPattern = rec.fn("patterns.jumpToPattern", side_effect=jump)

    mods = dict(midi=midi, transport=transport, ui=ui, general=general,
                mixer=mixer, channels=channels, patterns=patterns)
    for dotted in missing:                       # simule une ancienne version de l'API
        mod, attr = dotted.split(".")
        delattr(mods[mod], attr)
    return mods, state


def load_script(mods):
    for name in FL_MODULES:
        sys.modules[name] = mods[name]
    spec = importlib.util.spec_from_file_location("device_FLRemap_under_test", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Event:
    def __init__(self, data1, data2=127, chan=15, midi_id=0xB0):
        self.midiId, self.midiChan, self.data1, self.data2 = midi_id, chan, data1, data2
        self.status = midi_id | chan
        self.handled = False


class Base(unittest.TestCase):
    def setUp(self, **kw):
        self.rec = Recorder()
        self.mods, self.state = build_fl(self.rec, **kw)
        self.dev = load_script(self.mods)

    def send(self, cc, **kw):
        ev = Event(cc, **kw)
        self.dev.OnMidiMsg(ev)
        return ev

    def names(self):
        return [c[0] for c in self.rec.calls]


# --------------------------------------------------------------------------- OK attendus
class TestNominal(Base):
    def test_play(self):
        ev = self.send(20)
        self.assertTrue(ev.handled)
        self.assertIn("transport.start", self.names())

    def test_all_known_cc_are_handled_without_error(self):
        for cc in range(20, 38):
            ev = self.send(cc)
            self.assertTrue(ev.handled, cc)
        hints = [c for c in self.rec.calls if c[0] == "ui.setHintMsg"
                 and ("erreur" in c[1][0] or "indisponible" in c[1][0])]
        self.assertEqual(hints, [])

    def test_other_channel_ignored(self):
        ev = self.send(20, chan=0)
        self.assertFalse(ev.handled)
        self.assertNotIn("transport.start", self.names())

    def test_note_on_ignored(self):
        ev = self.send(20, midi_id=0x90)
        self.assertFalse(ev.handled)

    def test_exception_is_caught(self):
        self.mods["transport"].start = lambda: 1 / 0
        self.dev = load_script(self.mods)
        ev = self.send(20)
        self.assertTrue(ev.handled)
        self.assertTrue(any("erreur" in c[1][0] for c in self.rec.calls if c[0] == "ui.setHintMsg"))

    def test_oninit_exists(self):
        self.dev.OnInit()
        self.assertIn("ui.setHintMsg", self.names())


class TestSwiftPythonSync(unittest.TestCase):
    def test_cc_tables_match(self):
        src = open(MODEL, encoding="utf-8").read()
        swift = {int(n) for n in re.findall(r"case \.\w+: return (\d+)", src)}
        rec = Recorder()
        mods, _ = build_fl(rec)
        py = set(load_script(mods).ACTIONS)
        self.assertEqual(swift, py)


# --------------------------------------------------------------------------- BUGS révélés
class TestBugs(Base):
    def test_REL_PY1_missing_api_function_breaks_whole_script(self):
        """Une seule fonction absente (ancienne version de FL) empêche le chargement
        du script entier : AUCUNE action ne marche, pas seulement celle-là."""
        rec = Recorder()
        mods, _ = build_fl(rec, missing=("ui.nextWindow",))
        try:
            dev = load_script(mods)
        except AttributeError:
            self.fail("BUG REL-PY1 : AttributeError à l'import, le script ne se charge pas")
        ev = Event(20)
        dev.OnMidiMsg(ev)
        self.assertTrue(ev.handled)

    def test_REL_PY2_no_selected_channel(self):
        """Aucune garde de bornes : si selectedChannel() renvoie -1 (aucun canal,
        canBeNone=True, groupe de filtre vide), le script appelle muteChannel(-1)
        au lieu d'afficher un message clair (TypeError attrapée = message cryptique)."""
        self.setUp(focused={1}, selected_channel=-1)
        self.send(31)
        bad = [c for c in self.rec.calls if c[0] == "channels.muteChannel" and c[1][0] < 0]
        self.assertEqual(bad, [], "BUG REL-PY2 : muteChannel(-1) appelé")

    def test_REL_PY3_prev_pattern_blocked_when_current_beyond_count(self):
        """Pattern courant 7 alors que patternCount() == 4 (patterns vides intermédiaires,
        ou pattern choisi au sélecteur) : « pattern précédent » ne fait rien."""
        self.setUp(pattern=7, pattern_count=4)
        self.send(36)
        self.assertEqual(self.state["pattern"], 6, "BUG REL-PY3 : prevPattern bloqué")

    def test_REL_PY4_cc_value_zero_not_marked_handled(self):
        """Un CC connu à valeur 0 (relâchement, futur « note off ») n'est pas marqué
        handled : FL le traite comme un CC générique (liens de contrôleurs, etc.)."""
        ev = self.send(20, data2=0)
        self.assertTrue(ev.handled, "BUG REL-PY4 : CC connu à 0 laissé à FL")

    def test_REL_PY5_unknown_cc_on_our_channel_leaks(self):
        """CC inconnu (app plus récente que le script) : ni handled, ni message."""
        ev = self.send(90)
        hint = [c for c in self.rec.calls if c[0] == "ui.setHintMsg"]
        self.assertTrue(ev.handled and hint, "BUG REL-PY5 : action inconnue ignorée en silence")

    def test_REL_PY6_hint_failure_inside_except_propagates(self):
        """Si ui.setHintMsg lève (ou n'existe pas), l'exception sort de OnMidiMsg."""
        def boom(*a):
            raise RuntimeError("hint indisponible")
        self.mods["transport"].start = lambda: 1 / 0
        self.mods["ui"].setHintMsg = boom
        dev = load_script(self.mods)
        try:
            dev.OnMidiMsg(Event(20))
        except Exception as exc:
            self.fail("BUG REL-PY6 : exception non rattrapée : %r" % exc)


if __name__ == "__main__":
    unittest.main(verbosity=2)
```

## Annexe B — `device_FLRemap.py` corrigé (passe les 13 tests)

Corrige REL-14 et REL-24 à REL-27. Appels d'API résolus au moment de l'appel, constantes avec valeur de repli, bornes vérifiées, `handled` sur tout le canal 16, `_hint` qui ne lève jamais. Ajoute `SCRIPT_VERSION` (REL-22). Vérifié avec `FLREMAP_SCRIPT=fixed/device_FLRemap.py python3 -m unittest test_device_flremap.py` → `OK`.

```python
# name=FL Remap
# url=
"""Version corrigée proposée (audit REL-PY1..PY6)."""

import midi
import ui

SCRIPT_VERSION = 2
MIDI_CHANNEL = 15  # canal 16, 0-indexé


def _hint(text):
    try:
        ui.setHintMsg(text)
    except Exception:
        pass
    print(text)  # visible dans View > Script output


def _api(module_name, func_name):
    """Résout la fonction FL au moment de l'appel : une fonction absente
    (ancienne version de FL) ne casse que l'action concernée."""
    def call(*args):
        module = __import__(module_name)
        func = getattr(module, func_name, None)
        if func is None:
            _hint("FL Remap : %s.%s indisponible dans cette version de FL Studio"
                  % (module_name, func_name))
            return None
        return func(*args)
    return call


def _const(name, default):
    return getattr(midi, name, default)


def _show(window_id):
    _api("ui", "showWindow")(window_id)
    _api("ui", "setFocused")(window_id)


def _focused(window_id):
    return bool(_api("ui", "getFocused")(window_id))


def toggle_playlist_mixer():
    if _focused(_const("widMixer", 0)):
        _show(_const("widPlaylist", 2))
    else:
        _show(_const("widMixer", 0))


def _selected_channel():
    ch = _api("channels", "selectedChannel")()
    count = _api("channels", "channelCount")()
    if ch is None or ch < 0 or (count is not None and ch >= count):
        return None
    return ch


def _on_selection(mixer_fn, channel_fn, label):
    if _focused(_const("widMixer", 0)):
        track = _api("mixer", "trackNumber")()
        if track is not None and track >= 0:
            _api("mixer", mixer_fn)(track)
    elif _focused(_const("widChannelRack", 1)):
        ch = _selected_channel()
        if ch is None:
            _hint("FL Remap : aucun canal sélectionné")
        else:
            _api("channels", channel_fn)(ch)
    else:
        _hint("FL Remap : %s dispo dans le Mixer ou le Channel Rack" % label)


def jump_pattern(delta):
    current = _api("patterns", "patternNumber")()
    pmax = _api("patterns", "patternMax")() or 999
    if current is None:
        return
    target = min(max(1, current + delta), pmax)
    if target != current:
        _api("patterns", "jumpToPattern")(target)


ACTIONS = {
    20: _api("transport", "start"),
    21: _api("transport", "stop"),
    22: _api("transport", "record"),
    23: _api("general", "undoUp"),
    24: _api("general", "undoDown"),
    25: lambda: _show(_const("widPlaylist", 2)),
    26: lambda: _show(_const("widMixer", 0)),
    27: lambda: _show(_const("widChannelRack", 1)),
    28: lambda: _show(_const("widPianoRoll", 3)),
    29: lambda: _show(_const("widBrowser", 4)),
    30: toggle_playlist_mixer,
    31: lambda: _on_selection("muteTrack", "muteChannel", "mute"),
    32: lambda: _on_selection("soloTrack", "soloChannel", "solo"),
    33: lambda: _api("transport", "globalTransport")(_const("FPT_Metronome", 110), 1),
    34: _api("transport", "setLoopMode"),
    35: lambda: jump_pattern(1),
    36: lambda: jump_pattern(-1),
    37: _api("ui", "nextWindow"),
}


def OnInit():
    _hint("FL Remap prêt (script v%d)" % SCRIPT_VERSION)


def OnMidiMsg(event):
    try:
        if event.midiId != _const("MIDI_CONTROLCHANGE", 0xB0) or event.midiChan != MIDI_CHANNEL:
            return
        event.handled = True               # tout le canal 16 nous appartient
        if event.data2 == 0:
            return                         # relâchement : rien à faire
        action = ACTIONS.get(event.data1)
        if action is None:
            _hint("FL Remap : action %d inconnue, réinstalle le script depuis l'app" % event.data1)
            return
        action()
    except Exception as exc:
        _hint("FL Remap erreur : %r" % (exc,))
```
