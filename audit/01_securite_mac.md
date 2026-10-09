# Audit de sécurité — FL Shortcut (macOS)

Audit offensif mandaté par le propriétaire du logiciel. Cible : dépôt `/home/claude/FLShortcut` (v0.1, commit `bf2b36a`) et maquette v2.
Angle : attaquant local non privilégié (une autre app de l'utilisateur, un plugin, un fichier importé), puis attaquant réseau/chaîne d'approvisionnement.

---

## 1. Résumé exécutif

FL Shortcut repose sur deux capacités très puissantes : **(a)** un `CGEventTap` global qui voit et peut modifier **toutes** les frappes clavier du système, et **(b)** un **port MIDI virtuel non authentifié** qui pilote des actions dans FL Studio via un script Python. Ces deux capacités sont correctement utilisées dans le cas nominal, mais l'enveloppe de sécurité autour d'elles est quasi inexistante.

Trois problèmes dominent le risque :

1. **Canal MIDI → FL sans aucune authentification (SEC-01, SEC-02).** N'importe quelle application locale peut envoyer des Control Change sur le canal 16 et faire exécuter des actions dans FL Studio (undo en boucle, mute, record, et `save` en v2). L'`uniqueID` MIDI est codé en dur, ce qui permet en plus d'**usurper** le contrôleur quand l'app n'est pas lancée. Le handshake bidirectionnel prévu en v2 est **forgeable** (faux « connecté »).
2. **Binaire non durci (SEC-08).** Signature ad-hoc, pas de Hardened Runtime, pas de notarisation, `codesign --deep`. Résultat : `DYLD_INSERT_LIBRARIES` / dylib hijacking fonctionnent, et comme l'app détient la permission **Accessibilité**, une injection transforme FL Shortcut en **keylogger + injecteur de frappes** clé en main.
3. **Injection de frappes hors FL (SEC-03) et profils non validés (SEC-05).** La vérification « FL au premier plan » est désynchronisée du `CGEvent.post` (asynchrone) et **usurpable par sous-chaîne de nom** (SEC-04) ; un profil importé malveillant peut cibler des combinaisons destructrices (⌘Q, ⌘⌫…).

À son crédit : l'app **ne journalise ni ne stocke aucune frappe** aujourd'hui (vérifié : `handle()` ne lit que keycode/flags, rien n'est persisté), et la ré-injection de ses propres événements est marquée (`eventSourceUserData`), ce qui évite les boucles de remap infinies. Le risque principal n'est donc pas ce que le code fait, mais ce qu'un attaquant peut lui faire faire.

### Classement des failles

| Gravité | IDs |
|---|---|
| **Critique** | SEC-01 (injection MIDI non authentifiée), SEC-08 (binaire non durci + Accessibilité) |
| **Haute** | SEC-02 (uniqueID MIDI usurpable), SEC-03 (race condition injection hors FL), SEC-05 (profil non validé / cibles dangereuses) |
| **Moyenne** | SEC-04 (front-most usurpable par nom), SEC-06 (TOCTOU/symlink installeur), SEC-07 (tap global = keylogger potentiel, pas de Secure Input), SEC-09 (CI non épinglée + droits larges) |
| **Basse** | SEC-10 (DoS : flood MIDI / ré-activation tap en boucle), SEC-11 (touches modificatrices coincées / set `swallowed` non borné) |

---

## 2. Tableau des failles

---

### SEC-01 — Canal MIDI → FL sans authentification ni limitation de débit
- **Gravité : Critique**
- **Fichiers :** `Resources/device_FLShortcut.py:83-93` (`OnMidiMsg`), `Sources/FLShortcut/MIDIOut.swift:18-27` (`send`)
- **Scénario d'attaque :** Le script FL accepte **n'importe quel** message CC arrivant sur le canal 16 et exécute l'action correspondante, sans vérifier l'origine du message :
  ```python
  def OnMidiMsg(event):
      if event.midiId != midi.MIDI_CONTROLCHANGE or event.midiChan != MIDI_CHANNEL:
          return
      action = ACTIONS.get(event.data1)   # aucune authentification
      ...
      action()
  ```
  Tout processus local de l'utilisateur peut créer une source CoreMIDI virtuelle (aucune permission TCC requise pour émettre du MIDI) et émettre des CC 20-37 canal 16. Si FL route cette source vers le script (ou si l'attaquant usurpe le port, cf. SEC-02), l'attaquant déclenche des actions : `undo`/`redo` en boucle (CC 23/24) pour corrompre le travail en cours, `record` (CC 22), `mute`/`solo`, bascule de fenêtres en rafale. En v2, l'action `save` (vue dans la maquette, `ACTIONS[... 'save']`) permet d'**écraser le projet** de la victime à volonté.
- **PoC (décrit) :** une app de 30 lignes : `MIDIClientCreate` → `MIDISourceCreate("FL Shortcut")` → boucle `MIDIReceived` avec `[0xBF, 23, 127]` (undo) 50×/s. FL « annule » en continu tant que la fenêtre est active. Aucune interaction utilisateur, aucune élévation de privilège.
- **Impact :** perte/corruption de données du projet FL, DoS applicatif, comportement erratique attribué à tort à FL ou à FL Shortcut.
- **Correction :**
  1. **Secret partagé + anti-rejeu.** À l'installation, l'app génère un secret aléatoire 128 bits, l'écrit dans un fichier `0600` lu par le script Python, et chaque commande transporte un compteur de séquence + un tag dérivé du secret (via SysEx, 7 bits, voir §3).
  2. **Liste blanche + actions destructrices désactivées par défaut.** Le script refuse tout CC hors d'une allowlist ; `save`, `record` et toute action destructrice exigent un opt-in explicite.
  3. **Limitation de débit** côté script : ignorer une même action répétée à < 150 ms d'intervalle.
  ```python
  SECRET = _load_secret()          # fichier 0600, voir §3
  last_seq = -1
  RATE = {}
  def _authorized(seq, tag, cc):
      global last_seq
      if seq <= last_seq:                      # anti-rejeu
          return False
      if tag != _tag(SECRET, seq, cc):         # intégrité/origine
          return False
      last_seq = seq
      return True
  ```

---

### SEC-02 — `uniqueID` MIDI codé en dur → usurpation du contrôleur
- **Gravité : Haute**
- **Fichier :** `Sources/FLShortcut/MIDIOut.swift:14`
  ```swift
  if ready { MIDIObjectSetIntegerProperty(source, kMIDIPropertyUniqueID, 0x464C5250) }
  ```
- **Scénario d'attaque :** L'`uniqueID` (`0x464C5250` = « FLRP ») et le nom (`"FL Shortcut"`) sont publics et fixes. FL Studio mémorise son contrôleur d'entrée par nom/uniqueID. Un attaquant qui lance sa propre source MIDI nommée `FL Shortcut` avec le même uniqueID **avant** FL Shortcut (ex. au login) **prend l'identité** du contrôleur : FL, configuré pour lire « FL Shortcut », lit en réalité les CC de l'attaquant. Si les deux coexistent, la collision d'uniqueID produit un comportement indéfini (CoreMIDI renumérote ou rejette), ce qui est aussi un vecteur de DoS/confusion.
- **Impact :** combiné à SEC-01, injection fiable de commandes sans même que l'app légitime tourne ; l'utilisateur ne peut pas distinguer le vrai contrôleur du faux.
- **Correction :** générer l'uniqueID **aléatoirement une fois par installation**, le persister dans le fichier de config `0600`, et le réutiliser. Ne jamais dériver l'identité d'une constante publique. L'authentification de SEC-01 reste la vraie défense (l'uniqueID n'est pas un secret).
  ```swift
  let uid = Config.midiUniqueID()   // généré une fois, stocké 0600
  MIDIObjectSetIntegerProperty(source, kMIDIPropertyUniqueID, uid)
  ```

---

### SEC-03 — Race condition « FL au premier plan » → frappe synthétique injectée hors FL
- **Gravité : Haute**
- **Fichier :** `Sources/FLShortcut/EventTap.swift:57-85`
- **Scénario d'attaque :** Dans le callback, on teste `flStudioIsFrontmost()` puis, pour un remap `.keystroke`, on **avale** la touche et on **poste** une frappe synthétique :
  ```swift
  guard store.enabled, Self.flStudioIsFrontmost(), let remap = store.index[combo] else { return pass }
  ...
  case .keystroke:
      if let target = remap.target { Self.post(target) }   // post() -> CGEvent.post (asynchrone)
  ```
  `CGEvent.post(tap: .cgSessionEventTap)` ré-injecte l'événement dans la file de session de façon **asynchrone**. Entre l'instant du test front-most et la livraison effective de l'événement synthétique, l'application active peut changer (⌘Tab, une fenêtre qui se met au premier plan, un clic). La frappe synthétique — potentiellement une combinaison dangereuse (⌘Q, ⌘W, ⌘⌫) — **atterrit alors dans Terminal, le Finder ou toute autre app**. La fenêtre temporelle est courte mais réelle et exploitable par un attaquant qui provoque le changement de focus.
  Variante : le `keyUp` physique est géré via le Set `swallowed` (`EventTap.swift:43-44`) ; si le focus change entre keyDown et keyUp, l'état se désynchronise (cf. SEC-11).
- **Impact :** exécution de raccourcis destructeurs dans une application tierce (fermeture d'app, suppression de fichier dans le Finder, commande dans un terminal).
- **Correction :**
  1. Re-vérifier le front-most **au moment du post** et abandonner si FL n'est plus actif.
  2. Mieux : cibler explicitement le PID de FL avec `CGEvent.postToPid(_:)` au lieu de `post(tap:)`, pour que l'événement ne puisse pas fuir vers une autre app.
  ```swift
  private static func post(_ combo: KeyCombo, toPid pid: pid_t) {
      guard flStudioPid() == pid else { return }   // re-check juste avant
      for down in [true, false] {
          guard let e = CGEvent(keyboardEventSource: CGEventSource(stateID: .hidSystemState),
                                virtualKey: combo.keyCode, keyDown: down) else { continue }
          e.flags = combo.cgFlags
          e.setIntegerValueField(.eventSourceUserData, value: mark)
          e.postToPid(pid)     // livré uniquement à FL
      }
  }
  ```

---

### SEC-04 — Détection « FL au premier plan » usurpable par sous-chaîne de nom
- **Gravité : Moyenne**
- **Fichier :** `Sources/FLShortcut/EventTap.swift:70-75`
  ```swift
  return bundle.contains("image-line") || name.contains("FL Studio")
  ```
- **Scénario d'attaque :** La condition est satisfaite par **n'importe quelle** app dont le `bundleIdentifier` contient `image-line` (ex. `com.image-line.evil`) ou dont le `localizedName` contient `FL Studio` (ex. une fenêtre « FL Studio Updater »). Un attaquant publie une app anodine portant ce nom ; dès qu'elle est au premier plan, FL Shortcut active l'interception/avalement de touches et l'injection dans **son** contexte. Couplé à un profil malveillant (SEC-05), cela étend la surface d'attaque hors de FL.
- **Impact :** avalement de frappes et injection activés au profit d'une app hostile ; contournement de la garantie « seulement dans FL ».
- **Correction :** vérifier le `bundleIdentifier` par **égalité stricte** contre une liste connue, et idéalement vérifier le Team ID / la signature de l'app front-most.
  ```swift
  private static let flBundleIDs: Set<String> = ["com.image-line.flstudio", "com.image-line.flstudio-arm"]
  static func flStudioIsFrontmost() -> Bool {
      guard let id = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
      return flBundleIDs.contains(id)
  }
  ```

---

### SEC-05 — Profil JSON non validé : cibles dangereuses, valeurs hors bornes, import non fiable
- **Gravité : Haute** (dans le contexte v2 « profils importables »)
- **Fichiers :** `Sources/FLShortcut/Model.swift:156-165` (décodage), `Model.swift:184-188` (sauvegarde), v2 : import/export de profils (maquette)
- **Scénario d'attaque :** Le profil est décodé sans **aucune** validation sémantique :
  ```swift
  if let data = try? Data(contentsOf: Store.fileURL),
     let saved = try? JSONDecoder().decode([Remap].self, from: data) {
      remaps = saved
  }
  ```
  - `profile.json` vit dans `~/Library/Application Support/FL Shortcut/` **sans permissions restreintes** (écrit via `data.write(to:)`, donc en 0644, modifiable par tout processus de l'utilisateur).
  - Un `Remap.kind == .keystroke` peut avoir un `target` arbitraire. La v2 prévoyant des **profils importables** partagés entre utilisateurs, un profil malveillant peut mapper une touche fréquente (ex. `Espace`, `Tab`) vers ⌘Q, ⌘⌫ (supprimer), ⌃⌘Q (verrouiller la session), etc. Combiné à SEC-03/SEC-04, l'injection peut sortir de FL.
  - Pas de borne sur `keyCode` (UInt16), pas de détection de boucle entre remaps au niveau sémantique.
  - **Point positif à conserver :** `JSONDecoder` sur des `struct Codable` n'instancie pas de classes arbitraires (pas de `NSKeyedUnarchiver`), donc **pas de faille de désérialisation de type**. Le CC est borné par l'enum `FLAction` (20-37), un attaquant ne peut pas injecter CC > 127 **via l'app** (mais il le peut via MIDI direct, cf. SEC-01).
- **Impact :** import d'un profil = exécution de raccourcis dangereux ; falsification locale du profil.
- **Correction :**
  1. Écrire `profile.json` en **0600** et vérifier le propriétaire/les permissions au chargement.
  2. **Valider** chaque remap à l'import : liste blanche de touches cibles autorisées (refuser ⌘Q, ⌘W, ⌘⌫, ⌃⌘Q, Power…), bornes de keyCode, rejet des doublons/boucles.
  3. À l'import d'un profil tiers, afficher un **récapitulatif** des actions et demander confirmation ; ne jamais activer un profil importé silencieusement.
  ```swift
  private static let forbiddenTargets: Set<KeyCombo> = [
      KeyCombo(keyCode: 12, command: true),               // ⌘Q
      KeyCombo(keyCode: 51, command: true),               // ⌘⌫
      KeyCombo(keyCode: 12, command: true, control: true) // ⌃⌘Q
  ]
  func validate(_ r: Remap) -> Bool {
      if let t = r.target, forbiddenTargets.contains(t) { return false }
      return true
  }
  let data = try Data(contentsOf: url)
  try data.write(to: Store.fileURL, options: [.atomic, .completeFileProtection])
  // + chmod 0600
  ```

---

### SEC-06 — Installeur du script FL : TOCTOU / symlink / dossier contrôlé par l'attaquant
- **Gravité : Moyenne**
- **Fichier :** `Sources/FLShortcut/FLScriptInstaller.swift:31-38`
  ```swift
  let folder = hardware.appendingPathComponent("FL Shortcut", isDirectory: true)
  try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
  let dest = folder.appendingPathComponent(fileName)
  if FileManager.default.fileExists(atPath: dest.path) {
      try FileManager.default.removeItem(at: dest)   // TOCTOU
  }
  try FileManager.default.copyItem(at: script, to: dest)
  ```
- **Scénario d'attaque :**
  - **Symlink / redirection :** si `FL Shortcut` (ou un composant du chemin sous `~/Documents/.../Hardware`) est un lien symbolique planté par un attaquant, l'écriture peut atterrir **hors** du dossier prévu, ou écraser un autre fichier via le lien.
  - **TOCTOU :** entre `fileExists`, `removeItem` et `copyItem`, un attaquant qui gagne la course peut substituer la cible (ex. remplacer `dest` par un lien) pour détourner l'écriture.
  - **Confiance du dossier FL :** le dossier `Hardware` est sous `~/Documents` (accessible en écriture à tout processus de l'utilisateur). N'importe quel processus peut y déposer un `device_*.py` que **FL exécutera avec les privilèges de FL** — c'est un vecteur de persistance/exécution de code indépendant de FL Shortcut, mais que l'installeur banalise. L'`NSOpenPanel` laisse aussi choisir un dossier quelconque sans vérifier qu'il s'agit bien de FL.
- **Impact :** écriture hors cible, écrasement d'un autre script FL, normalisation d'un vecteur d'exécution de code dans FL.
- **Correction :**
  1. Résoudre et **vérifier** que le chemin final ne contient aucun lien symbolique (`URL.resolvingSymlinksInPath`, comparer, refuser sinon) et reste sous le dossier FL attendu.
  2. Écriture **atomique** dans un fichier temporaire du même dossier puis `replaceItemAt` (évite le remove/copy en deux temps).
  3. Vérifier que le dossier choisi ressemble vraiment à `Settings/Hardware` de FL avant d'écrire.
  ```swift
  let tmp = folder.appendingPathComponent(".\(fileName).tmp")
  try? FileManager.default.removeItem(at: tmp)
  try FileManager.default.copyItem(at: script, to: tmp)
  _ = try FileManager.default.replaceItemAt(dest, withItemAt: tmp)   // atomique
  ```

---

### SEC-07 — Tap clavier global = keylogger potentiel ; pas de conscience de Secure Input ; privilège excessif
- **Gravité : Moyenne**
- **Fichier :** `Sources/FLShortcut/EventTap.swift:16-22`
- **Scénario d'attaque :** Le tap est créé sur `.cgSessionEventTap` en `.defaultTap` (actif, capable de **modifier/avaler**) pour `keyDown` **et** `keyUp` de **toute la session** — donc toutes les frappes de toutes les apps, y compris les mots de passe tapés hors FL.
  - **Vérifié :** aujourd'hui `handle()` ne lit que `keyboardEventKeycode`/`flags`/`autorepeat` et ne persiste rien → **pas de keylogging actif**. C'est une bonne propriété à préserver explicitement.
  - **Mais :** le processus a les privilèges nécessaires pour logger. Couplé à SEC-08 (injection de dylib) ou à un futur plugin/profil, il devient trivialement un keylogger complet avec Accessibilité déjà accordée. Aucune détection de **Secure Input** (champs mot de passe) : si une autre app active `EnableSecureEventInput`, le tap est muet — à documenter pour éviter des « bugs » perçus et pour la vie privée.
- **Impact :** surface d'exfiltration de frappes à l'échelle du système en cas de compromission du processus.
- **Correction :**
  1. **Réduire le privilège** : si seul l'avalement/injection pour FL est nécessaire, garder `.defaultTap` mais ne traiter les événements **que** lorsque FL est front-most (déjà le cas pour les remaps) et **ignorer entièrement** les frappes hors FL le plus tôt possible — ne jamais copier le contenu des frappes.
  2. **Ne jamais** journaliser le keycode en clair (pas de `print`/`os_log` de frappes, même en debug).
  3. Documenter le comportement Secure Input et ne pas tenter de le contourner.
  4. SEC-08 est la correction structurelle (empêcher l'injection dans ce processus privilégié).

---

### SEC-08 — Binaire non durci : signature ad-hoc, pas de Hardened Runtime/notarisation, `--deep`
- **Gravité : Critique**
- **Fichiers :** `build.sh:20`, `Resources/Info.plist` (aucun entitlement), `README.md:16`
  ```bash
  codesign --force --deep --sign "${SIGN_IDENTITY:--}" "$APP"
  ```
- **Scénario d'attaque :** Signature **ad-hoc** (`-`), **sans** `--options runtime` (pas de Hardened Runtime), app **non notarisée**, et `--deep` (déprécié, signe mal les composants imbriqués). Conséquences :
  - **Pas de Library Validation / Hardened Runtime** → `DYLD_INSERT_LIBRARIES` et le **dylib hijacking** fonctionnent. Un attaquant local lance FL Shortcut avec une dylib injectée qui s'exécute **dans un processus détenant la permission Accessibilité** → keylogger + injection de frappes immédiats (voir SEC-07), sans redemander d'autorisation.
  - **Permission Accessibilité sur binaire non signé de façon stable :** TCC identifie par cdhash/exigence de désignation. En ad-hoc il n'y a pas de Team ID stable ; un attaquant qui **remplace le binaire au même chemin** peut au minimum semer la confusion, et l'absence de Library Validation rend l'injection plus simple que le remplacement. Le principe « le binaire autorisé est de confiance » s'effondre.
  - **README** demande à l'utilisateur de contourner Gatekeeper (clic droit › Ouvrir), ce qui habitue la victime à exécuter du non-notarisé.
- **Impact :** élévation d'une app utilitaire en plateforme de surveillance/injection clavier à l'échelle système.
- **Correction :**
  1. Signer avec une **identité Developer ID**, activer le **Hardened Runtime** (`--options runtime`), **notariser** et stapler.
  2. Supprimer `--deep` ; signer chaque composant explicitement, de l'intérieur vers l'extérieur.
  3. Déclarer les entitlements minimaux et **ne pas** autoriser `com.apple.security.cs.disable-library-validation` ni `allow-dyld-environment-variables`.
  ```bash
  codesign --force --options runtime --timestamp \
    --sign "Developer ID Application: <Nom> (TEAMID)" \
    "$APP/Contents/MacOS/FLShortcut"
  codesign --force --options runtime --timestamp \
    --sign "Developer ID Application: <Nom> (TEAMID)" "$APP"
  xcrun notarytool submit dist/FLShortcut.dmg --wait ... && xcrun stapler staple ...
  ```

---

### SEC-09 — CI GitHub : actions tierces non épinglées + `contents: write` global, artefact sans intégrité
- **Gravité : Moyenne**
- **Fichier :** `.github/workflows/build.yml:9-11, 16-29`
- **Scénario d'attaque :**
  - `permissions: contents: write` est déclaré **au niveau workflow** → s'applique aussi au job de build qui n'en a pas besoin. Si une action tierce est compromise, le `GITHUB_TOKEN` write permet d'altérer le dépôt / publier des releases.
  - Actions référencées par **tag mobile** (`actions/checkout@v4`, `upload-artifact@v4`, `softprops/action-gh-release@v2`) et non par **SHA** : une action tierce compromise (surtout `softprops/action-gh-release`) s'exécute avec le token write et peut injecter un `.dmg` malveillant dans la Release.
  - Le `.dmg` publié est **non signé/non notarisé** (hérite de SEC-08) et sans **checksum** ni signature → aucune intégrité pour l'utilisateur final.
- **Impact :** compromission de la chaîne de distribution ; diffusion d'un binaire piégé sous l'identité du projet.
- **Correction :**
  1. `permissions: contents: read` par défaut ; `contents: write` **uniquement** sur le job de release, via `permissions:` au niveau job.
  2. **Épingler chaque action par SHA complet** (`uses: softprops/action-gh-release@<sha>`).
  3. Publier un **checksum SHA-256** et signer/notariser le `.dmg` (SEC-08). Pour les mises à jour futures via Sparkle : **signature EdDSA obligatoire** et `SUFeedURL` en HTTPS.
  ```yaml
  permissions:
    contents: read
  jobs:
    build:
      steps:
        - uses: actions/checkout@<sha40>
    release:
      if: startsWith(github.ref, 'refs/tags/v')
      permissions:
        contents: write
      steps:
        - uses: softprops/action-gh-release@<sha40>
  ```

---

### SEC-10 — DoS : flood MIDI et ré-activation du tap en boucle
- **Gravité : Basse**
- **Fichiers :** `Resources/device_FLShortcut.py:83-93`, `Sources/FLShortcut/EventTap.swift:34-37`
- **Scénario d'attaque :**
  - **Flood MIDI** (prolonge SEC-01) : un flux soutenu de CC fait exécuter des actions FL en rafale (undo/redo alternés corrompent l'historique, record on/off, `save` en v2) → DoS applicatif et potentielle corruption.
  - **Tap :** sur `tapDisabledByTimeout`, le tap est ré-activé immédiatement. Si le callback devient lent (ou est ralenti par un autre composant), on obtient un cycle désactivation→réactivation qui perd des événements. Le chemin actuel est léger, donc risque faible, mais il n'y a ni back-off ni télémétrie.
- **Impact :** instabilité, perte d'événements clavier, corruption de l'historique FL.
- **Correction :** limitation de débit côté script (SEC-01, point 3) ; sur réactivation du tap, ajouter un compteur et un back-off, et prévenir l'utilisateur si les réactivations se multiplient.

---

### SEC-11 — Touches modificatrices coincées / Set `swallowed` non borné
- **Gravité : Basse**
- **Fichier :** `Sources/FLShortcut/EventTap.swift:11, 43-44, 59`
- **Scénario d'attaque :** `swallowed` reçoit le keycode au `keyDown` et le retire au `keyUp`. Si le `keyUp` n'est jamais vu (changement d'app, Secure Input activé entre-temps, tap désactivé), le keycode **reste** dans le Set et le prochain `keyUp` de cette touche physique est avalé à tort. Pour les remaps avec modificateurs (ex. ⌃1), le modificateur physique reste pressé pendant l'injection → risque de combinaison involontaire ou de modificateur « coincé ».
- **Impact :** touches qui semblent bloquées, frappes avalées de façon inattendue (gêne, pas de compromission).
- **Correction :** purger `swallowed` sur `tapDisabled*` et sur changement d'app front-most ; borner/âger les entrées ; pour les remaps `.keystroke`, neutraliser les modificateurs physiques résiduels avant d'injecter la cible.

---

## 3. Exigences de sécurité pour la v2

La v2 (handshake bidirectionnel, raccourcis par fenêtre, profils importables, bouton « Tester ») **augmente** la surface. Exigences minimales :

### 3.1 Canal app ↔ script FL authentifié (répond à SEC-01, SEC-02, et au handshake forgeable)
Le handshake de la maquette (le script renvoie `hello`/`heartbeat`/`version` via `device.midiOutMsg`, l'app affiche « connecté ») est **trivialement forgeable** : toute source MIDI peut émettre les octets `hello`. Un faux « connecté » peut masquer une usurpation de contrôleur. Exigences :
- **Secret partagé par installation**, stocké dans `~/Library/Application Support/FL Shortcut/pairing.json` en **0600**, généré aléatoirement (≥ 128 bits). Le script Python le lit au `OnInit` (même fichier, mêmes droits).
- **Authentification des commandes** app → FL : chaque commande transporte un **compteur de séquence monotone** + un **tag** court dérivé `HMAC(secret, seq‖cc)` tronqué, transmis en **SysEx** (le CC 7 bits ne suffit pas ; SysEx permet d'emporter seq + tag). Le script **rejette** tout message sans tag valide ou avec `seq` déjà vu (**anti-rejeu**), ce qui neutralise le flood/replay (SEC-10).
- **Authentification du handshake** FL → app : le `hello`/`heartbeat` renvoyé par le script inclut lui aussi un tag dérivé du secret + un nonce fourni par l'app au début. Sans tag valide, l'app affiche « non vérifié », **pas** « connecté ». Le bouton « Tester » doit exercer ce chemin authentifié de bout en bout.
- **uniqueID MIDI aléatoire par installation** (SEC-02), persisté dans le même fichier de pairing.

### 3.2 Liste blanche d'actions et actions destructrices protégées (SEC-01, SEC-05)
- Le script maintient une **allowlist** explicite ; tout CC/ID hors allowlist est ignoré et journalisé via `ui.setHintMsg`.
- Les actions **destructrices ou à effet de bord fort** (`save`, `record`, `clone`, quantize, consolider…) sont **désactivées par défaut** et nécessitent un opt-in par raccourci côté app.
- **Limitation de débit** par action (anti-rebond ~150 ms) côté script, en plus de l'anti-rejeu.

### 3.3 Profils importables sûrs (SEC-05)
- Validation **systématique** à l'import : bornes de `keyCode`, **liste noire** de cibles dangereuses (⌘Q, ⌘W, ⌘⌫, ⌃⌘Q, Power…), détection de boucles, rejet des champs inconnus.
- Écran de **confirmation** listant toutes les actions et toutes les cibles `.keystroke` du profil avant activation. Jamais d'activation silencieuse.
- Fichiers de profil et de pairing en **0600**, écriture **atomique** (`.atomic` + `.completeFileProtection`), vérification du propriétaire au chargement.

### 3.4 Injection de frappes confinée à FL (SEC-03, SEC-04)
- Identifier FL par **bundle ID exact** (liste connue), pas par sous-chaîne de nom.
- Injecter via `CGEvent.postToPid(flPid)` plutôt que `post(tap:)`, avec **re-vérification du PID juste avant l'injection**, pour qu'aucune frappe synthétique ne puisse fuir vers une autre app.

### 3.5 Durcissement du binaire et de la distribution (SEC-08, SEC-09)
- **Developer ID + Hardened Runtime + notarisation**, sans entitlement affaiblissant (pas de `disable-library-validation`).
- CI : actions **épinglées par SHA**, `contents: read` par défaut et `write` au seul job de release, **checksum SHA-256** publié. Mises à jour auto **uniquement** via Sparkle avec **clé EdDSA** et flux HTTPS.

### 3.6 Vie privée et principe de moindre privilège (SEC-07)
- **Garantie écrite et testée** : aucune frappe n'est stockée, journalisée ni transmise ; les frappes hors FL sont ignorées au plus tôt sans copie de contenu.
- Documenter le comportement **Secure Input** ; ne pas le contourner.
- Idéalement, isoler la logique MIDI/profil du processus détenant le tap, pour qu'une compromission de la partie « UI/profil » ne donne pas accès au flux clavier.

---

*Fin du rapport — SEC-01 à SEC-11.*
