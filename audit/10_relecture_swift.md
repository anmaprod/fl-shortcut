# 10 — Relecture Swift (macOS) : compilation, protocole, sécurité, logique

Relecture de `Sources/FLShortcut/*.swift` (17 fichiers), `Tests/FLShortcutTests/*.swift` et `Package.swift`, sans compilateur (environnement Linux). La relecture tient lieu de compilation. Chaque fichier a été lu en entier. Les signatures Apple utilisées ont été comparées aux en-têtes connus : CGEvent / tap, CoreMIDI, CryptoKit, Security, `OSAllocatedUnfairLock`, NSWorkspace, SwiftUI macOS 13. Les points douteux ont été vérifiés en ligne.

Ce que j'ai vérifié mécaniquement :
- l'ordre des étiquettes dans les 120 appels `KeyCombo(...)` : aucun appel mal ordonné ;
- les littéraux de dictionnaire : aucune clé en double, ce qui aurait provoqué un plantage au lancement ;
- la table des actions : identique à PROTOCOL.md §6 et à `ACTIONS` du script (id, clé, version minimale de FL).

## 1. Problèmes trouvés

Gravités : **Compilation** (empêche ou risque d'empêcher la compilation), **Bloquant**, **Majeur**, **Mineur**.

| # | Fichier:ligne (après correction) | Gravité | Description | Correction |
|---|---|---|---|---|
| 1 | `Store.swift:7`, `MIDILink.swift:6`, `FLPresence.swift:6` | Compilation (selon le SDK) | `ObservableObject` et `@Published` viennent de Combine. Ces trois fichiers n'importaient que Foundation, AppKit ou CoreMIDI. Selon la version du SDK, Foundation expose ou non un alias. Avec *Member Import Visibility* (SE-0444), c'est une erreur certaine. | **Appliquée** : `import Combine` explicite. |
| 2 | `Store.swift:126-136` | Compilation | `let data: Data?` puis `guard let data else` dans **la même portée** : erreur « definition conflicts with previous value ». Ce masquage n'est permis que pour une portée englobante, par exemple un paramètre. | **Appliquée** : renommage en `stored`, puis `guard let data = stored`. |
| 3 | `Store.swift:70` | Compilation (précaution) | Une fermeture littérale suivie d'un bloc `{ didSet }` peut être lue comme une fermeture finale. L'analyseur gère normalement ce cas (`isStartOfGetSetAccessor`), mais la forme reste fragile. | **Appliquée** : fermeture entre parenthèses. |
| 4 | `FLShortcutApp.swift:305` | Compilation (précaution) | Une fermeture contenant une chaîne interpolée était imbriquée dans l'interpolation d'un `LocalizedStringKey` : risque d'« expression ambiguë » ou trop complexe. | **Appliquée** : propriété calculée `statusLine: String`. |
| 5 | `MIDILink.swift:412` | Compilation (précaution) | Un tuple sans étiquettes `(id, Date())` était affecté à un `(id:date:)?` publié. | **Appliquée** : tuple étiqueté. |
| 6 | `EventTap.swift:152-176` | **Majeur** (REL-06) | La touche était avalée dès que `routingView()` disait « Relié », même si l'envoi échouait ensuite. Deux causes : le lien expire entre les deux verrous, ou CoreMIDI tombe (`transportFailed`). Dans le second cas, la vue reste « Relié » jusqu'à 6 s, faute de battement. Résultat : la touche est perdue sans aucun effet. | **Appliquée** : si `sendAction` ne renvoie pas `.sent`, l'appui est rendu (`KeyRouter.release`) et la touche passe à FL. Ses répétitions et son keyUp passent aussi. |
| 7 | `EventTap.swift:165-171`, `198` | Majeur | Une « Touche de FL » était avalée même quand `post()` refusait d'injecter au dernier moment (FL n'est plus au premier plan, ou cible interdite). La frappe était donc perdue. | **Appliquée** : `post` renvoie `Bool`. En cas de refus, l'appui initial est rendu. Une répétition reste avalée, pour ne pas envoyer de répétition orpheline. |
| 8 | `MIDILink.swift:300-316` | Majeur (mémoire) | `packet.pointee.length` copie toute la `MIDIPacket` (256 octets de données) : lecture hors limites possible sur un paquet court en fin de liste. | **Appliquée** : lecture de `numPackets` et `length` à leur décalage, avec `loadUnaligned`. Test ajouté : `testPacketListWalkReadsEveryPacket`. |
| 9 | `EventTap.swift:152` | Mineur (REL-28 / SEC-07) | Le verrou du lien était consulté pour **chaque** frappe du système, même hors FL. | **Appliquée** : `routingView()` seulement si la frappe est destinée à FL ; sinon `.offline`, sans changement de comportement, car le routeur ne lit le lien qu'après `targetIsFL`. |
| 10 | `MIDILink.swift:403` | Mineur (REL-10) | Notre propre `connect()` déclenche `msgSetupChanged`. Si `verify()` échouait, on obtenait une boucle de recréation. | **Appliquée** : au plus une recréation par seconde depuis la notification ; la minuterie (toutes les 5 s) prend le relais. |
| 11 | `SecureFile.swift:124` | Mineur (SEC-05/06) | `open(O_RDONLY)` sur un tube nommé posé à la place du profil, de la clé ou du script bloque le fil principal. | **Appliquée** : ajout de `O_NONBLOCK`. Le contrôle « fichier ordinaire » refuse ensuite le tube. |
| 12 | `ModelTests.swift:1` | Mineur | `CGEventFlags` était utilisé sans import de CoreGraphics. Ça compile aujourd'hui grâce à la visibilité implicite des membres, mais pas avec SE-0444. | **Appliquée** : `import CoreGraphics`. |
| 13 | `MIDILink.swift:104` | Mineur | Le script renvoie un accusé 0 aussi quand une action échoue normalement (aucune piste sélectionnée). Deux échecs de suite déclenchent donc un PING et un nouveau nonce. C'est sans danger mais inutile. | Proposée : distinguer « rejet » et « échec » dans le protocole (CC 119 = 0 contre 127, par exemple). C'est une modification du contrat, donc non faite. |
| 14 | `MIDILink.swift:273` | Mineur | Course théorique : un `send` lancé avant une reconnexion peut marquer `ready = false` sur les **nouveaux** points de terminaison. Effet : une reconnexion de plus, 5 s plus tard. | Proposée : comparer `h.source` avant de marquer. Négligeable. |
| 15 | `EventTap.swift:77` | Mineur | `start()` bloque le fil principal 2 s au plus. Si `tapCreate` répond après ce délai, `staleTCC` s'affiche à tort pendant un cycle de 2 s. | Laissé : le superviseur corrige au cycle suivant. |
| 16 | `FLProtocol.swift:243` | Mineur (choix) | Sans lien, la fenêtre FL est inconnue : les raccourcis « Touche de FL » limités à une fenêtre (Mixer…) sont alors inactifs. Seuls les « Partout » marchent. | Laissé, choix prudent cohérent avec PROTOCOL.md. À documenter dans l'interface. |
| 17 | `MIDILink.swift:220-271` | Mineur (avertissements) | `MIDISourceCreate`, `MIDIDestinationCreateWithBlock`, `MIDIPacketListAdd` et `MIDIReceived` sont dépréciés depuis macOS 11. Ce sont des avertissements, pas des erreurs. Les autres signatures (`MIDIClientCreateWithBlock`, `MIDINotifyBlock`, `MIDIReadBlock`) sont exactes. | Proposée pour plus tard : `MIDISourceCreateWithProtocol(._1_0)` et `MIDIReceivedEventList`. |
| 18 | `EditorView.swift:357`, `FLShortcutApp.swift:264` | Mineur (avertissements Xcode 16+) | Avec les SDK où `View` est `@MainActor @preconcurrency`, passer `accept` comme fermeture non isolée, ou créer `NSHostingView` depuis du code non isolé, produit des **avertissements** en mode Swift 5. | Laissé. Le mode de langage reste Swift 5 avec `swift-tools-version:5.9`. |

Aucun problème trouvé sur :
- les signatures CGEvent : `tapCreate(tap:place:options:eventsOfInterest:callback:userInfo:)`, `.cgAnnotatedSessionEventTap`, rappel C global sans capture, `postToPid`, `tapIsEnabled` ;
- CryptoKit (`HMAC<SHA256>.authenticationCode(for:using:)`, `SymmetricKey(data:)`) et Security (`SecRandomCopyBytes`, `SecItemCopyMatching` / `Update` / `Add` / `Delete`) ;
- `OSAllocatedUnfairLock(uncheckedState:)` et `withLockUnchecked` (macOS 13) ;
- SwiftUI : `MenuBarExtra(content:label:)`, `Window(_:id:)`, `openWindow`, `windowResizability`, `ForEach($…)` ;
- les initialiseurs memberwise des vues : une propriété `private` enveloppée **et** initialisée est exclue de l'initialiseur, qui reste donc accessible ;
- les accès `private` entre fichiers et les doublons de noms : aucun doublon de type de premier niveau ; les types imbriqués `Handles`, `Failure` et `Kind` sont dans des portées distinctes ;
- les `throws` : tous traités ;
- les symboles : aucun n'est référencé sans être défini.

### Cible de test sur un exécutable `@main`
SwiftPM accepte `@testable import` d'un `.executableTarget` depuis `swift-tools-version:5.5`. Le point d'entrée est renommé `<module>_main` (`-entry-point-function-name`), puis rétabli en `_main` à l'édition de liens (`-alias` sous Darwin) ; tout le code du module est visible des tests, sauf le point d'entrée. Le paquet est en 5.9 et `@main` n'est pas dans un `main.swift` : **la séparation en `FLShortcutCore` + `FLShortcut` n'est pas nécessaire**. Elle obligerait d'ailleurs à rendre `public` presque toute l'API interne. Sources : CHANGELOG de SwiftPM 5.5 et commit 685eb8d (« Allow tests to link against executable targets »).

## 2. Vérification croisée Python (encodage Swift contre le script FL réel)

J'ai écrit un script hors dépôt qui **porte ligne à ligne** la logique Swift : `FLProtocol.seqBytes` et `mac28`, `FrameSigner.message` et `mac`, `FrameEncoder.frame`, `CapabilityMask`, `MIDIByteParser`, `IncomingDecoder` et les règles de séquence de `LinkCore`. Ses trames sont envoyées à `Resources/device_FLShortcut.py`, chargé avec les modules FL simulés de `tests/python/fl_mocks.py`. L'encodage n'emprunte rien aux helpers de `fl_mocks`.

**Résultat : 1 579 vérifications, 0 échec.** Les 90 tests Python existants passent toujours.

| Vérifié | Résultat |
|---|---|
| Vecteur de PROTOCOL.md §4 : message `[17,42,99,5,0,2,44,12]`, MAC `[87,59,101,12]` | OK, identique au HMAC de CryptoKit (porté) et au SHA-256 Python pur du script |
| HELLO émis par le script, décodé par le décodeur Swift, pour les API 1, 2, 5, 8, 9, 10, 12, 13, 19, 20, 25, 28 et 45 | Nonce, version d'API, protocole 2 : OK |
| Masque CC 90–95 : bit j du CC 90+k = action 7k+j+1 ; comparé à `_caps()` du script pour les ids 1–42, toutes API | Identique (masque brut et `contains`) ; aller-retour `ccValues` OK |
| Les 38 actions envoyées en trames Swift (CC 104–111) | Acceptées : séquence consommée ; accusé = id, ou 0 si l'action est indisponible |
| Rejeu (même seq), MAC faux, mauvaise clé | Refusés (accusé 0) |
| PING : nouveau nonce, seq de l'appli remise à 0, numérotation depuis 1 | OK |
| HELLO renvoyé avec le même nonce : l'appli garde sa séquence | OK, trame suivante acceptée |
| Séquence 2²¹−2 puis 2²¹−1 ; séquence épuisée : nouveau HELLO, l'appli repart de 0 | OK |
| 25 trames d'affilée | 20 acceptées, 5 refusées (limite de 20/s), aucune trame mélangée |

Le vecteur de test est aussi présent dans les tests Swift (`ProtocolTests.testHMACTestVector`, `testFrameEncoding`), avec les mêmes valeurs.

## 3. État des exigences de sécurité

| Id | État | Où / remarque |
|---|---|---|
| SEC-01 | **Fait** | `FLProtocol.swift` : HMAC-SHA256 tronqué à 28 bits, nonce de session, séquence monotone, liste blanche d'ids. `LinkCore.sendAction` : trames émises sous verrou. Anti-rejeu et débit côté script. Non fait : l'opt-in des actions destructrices (`save`, `rec`) suggéré en §3.2 de l'audit 01. Il ne figure pas dans PROTOCOL.md et le canal est maintenant authentifié. |
| SEC-02 | **Fait** | `CoreMIDITransport.applyUniqueID` : identifiant aléatoire par installation, pour la source **et** la destination ; nouvelle tentative si `kMIDIIDNotUnique`. |
| SEC-03 | **Fait** | `EventTap.post` : PID et premier plan revérifiés avec la configuration la plus récente, puis `postToPid` uniquement. Le refus est désormais traité (point 7). |
| SEC-04 | **Fait** | `FLMatcher` : bundle ID exact, insensible à la casse. Team ID non vérifié (« idéalement » dans l'audit). |
| SEC-05 | **Fait** | Liste noire appliquée à l'édition (`ShortcutField`), à l'import (`ProfileImporter`), au chargement (analyse bloquante, donc ligne hors index), dans le routeur **et** juste avant l'injection (`post`). keyCodes bornés, touches modificatrices refusées, profil 0600, propriétaire vérifié, import confirmé avec récapitulatif. |
| SEC-06 | **Fait** | `SecureFile` : `lstat`, `O_NOFOLLOW`, fichier temporaire `O_EXCL` dans le même dossier, `fsync`, `rename(2)`. Installeur : dossier Hardware vérifié, aucun lien dans le chemin. Nouveau : `O_NONBLOCK` à la lecture. |
| SEC-07 | **Fait** | Aucun `print`, `NSLog`, `os_log` ni `Logger` dans `Sources/`. Seuls keyCode et modificateurs sont lus. L'état « appui en cours » ne contient que keyCode → propriétaire, au plus 128 entrées, purgé. Nouveau : hors FL, le lien n'est même plus consulté. Non fait : isoler le tap dans un processus séparé (« idéalement »). |
| SEC-10 | **Fait** | 5 réactivations du tap par minute au plus, puis `restart` et message à l'utilisateur. PING limité ; resynchronisation bornée (toutes les 2 s au plus). |
| SEC-11 | **Fait** | `KeyRouter` : propriété de l'appui décidée au keyDown, ensemble borné, purgé à la coupure du tap, à la veille, au réveil, au changement de session, de saisie sécurisée ou d'appli au premier plan, à l'arrêt et au démarrage. Modificateurs physiques neutralisés autour de l'injection (flagsChanged, source privée). |

## 4. État des exigences de fiabilité (côté Swift)

| Id | État | Où / remarque |
|---|---|---|
| REL-01 | **Fait** | `Remap.init(from:)` tolérant, `Lossy`, actions inconnues conservées et désactivées, migration v1 avec copie de secours, ids dédoublonnés, défauts figés au premier lancement. |
| REL-02 | **Fait** | Écriture atomique 0600, erreur publiée (`saveError`), écriture immédiate à la fermeture. |
| REL-03 | **Fait** | Tap sur un thread dédié avec sa boucle d'exécution ; `TapConfig` immuable, sous `OSAllocatedUnfairLock`. |
| REL-04 | **Fait** | Voir SEC-11 ; tests `RouterTests`. |
| REL-05 | **Fait** (à valider sur Mac) | `.cgAnnotatedSessionEventTap` et `eventTargetUnixProcessID`, repli sur le PID au premier plan, ensemble des PID de FL tenu par notifications. |
| REL-06 | **Fait** (complété ici) | Le routeur n'avale une « Action dans FL » que si le lien est relié, la clé présente et l'action disponible. **Ajout** : si la trame ne part pas, la touche passe (point 6). |
| REL-07 | **Fait** | `SingleInstance.enforce()` dans `App.init`, avant tout tap, port ou profil ; conflit d'uniqueID affiché. |
| REL-08 | **Fait** | Superviseur toutes les 2 s : arrêt, création ou recréation du tap ; TCC périmé signalé. |
| REL-09 | **Fait** | `IsSecureEventInputEnabled()` : purge, icône et bandeau. Le PID responsable n'est pas lu (« en option » dans l'audit). |
| REL-10 | **Fait** | `msgSetupChanged`, puis `verify`, puis recréation ; reconnexion paresseuse toutes les 5 s ; échecs de `MIDIPacketListAdd` et `MIDIReceived` pris en compte. **Ajout** : garde contre la boucle (point 10). |

## 5. Logique vérifiée (priorité 4)

- **Touches coincées** : la cible « Touche de FL » est postée en keyDown et keyUp à chaque appui ou répétition. Les modificateurs sont restaurés à l'état physique. Le keyUp du déclencheur suit la décision du keyDown. Pas de keyUp avalé après un keyDown manqué (keyDown neuf → remise à zéro).
- **Purge** : voir SEC-11. Les sources de purge sont toutes branchées (`FLMonitor.refresh`, `AppStatus.start`, `supervise`, `EventTap.start`/`stop`/`tapDisabled`).
- **Filtrage par fenêtre** : la fenêtre précise est cherchée d'abord, puis « Partout ». La fenêtre ne compte que si le lien est relié. Une fenêtre inconnue, un plugin ou le Browser donnent « Partout » seulement (test `testWindowFilteringUsesLinkWindow`).
- **Ne pas avaler sans lien** : `LinkRoutingView.canRun` dans le routeur, plus la vérification du résultat d'envoi (nouveau). Tests `testInactiveLinkLetsActionKeyThrough` et `testReleasedPressLetsRepeatsAndKeyUpThrough`.
- **Liste noire avant chaque injection** : `KeyRouter` (keyDown et répétitions), puis `EventTap.post` avec la configuration du moment.
- **Bascule ⌃⌥⌘F** : une seule fois malgré l'auto-répétition. Elle reste active quand les raccourcis sont en pause, et tout passe pendant l'enregistrement d'un raccourci.

## 6. Ce qui ne peut être confirmé qu'en compilant et en lançant sur un Mac

1. **Compilation réelle**, avec Xcode 15 (Swift 5.9) et un Xcode récent :
   - visibilité de Combine selon le SDK (point 1) ;
   - `guard let` (point 2) ;
   - optionalité du retour de `MIDIPacketListAdd` : neutralisée par l'annotation `UnsafeMutablePointer<MIDIPacket>?` ;
   - nombre et nature des avertissements de dépréciation et de concurrence (points 17 et 18).
2. **`swift test`** sur la cible exécutable avec `@main` + SwiftUI : édition de liens du paquet de test (`-alias _FLShortcut_main`).
3. `MemoryLayout<MIDIPacketList/MIDIPacket>.offset(of:)` non nul sur les champs importés de C. Le test `testPacketListWalkReadsEveryPacket` le prouve, sinon aucune donnée MIDI ne serait lue.
4. **Construction universelle** arm64 + x86_64 (`build.sh`).
5. Tap annoté : `eventTargetUnixProcessID` renseigné pour Spotlight, la palette d'emojis, les panneaux Enregistrer sous (REL-05).
6. FL accepte les frappes `postToPid`, et l'encadrement `flagsChanged` lui donne les bons modificateurs (REL-13, SEC-03).
7. **Bundle ID** de FL Studio 20.7 → 2025 (Intel et Apple Silicon) : `com.image-line.flstudio` est le seul accepté.
8. TCC :
   - `tapCreate` refusé alors que la permission est cochée (TCC périmé) ;
   - invite d'accès à « Documents » à l'installation et à la vérification d'intégrité du script (toutes les 2 s) ;
   - invite du Trousseau après mise à jour d'une appli signée ad hoc : la liste d'accès est liée à la signature (lié à SEC-08).
9. CoreMIDI :
   - visibilité des ports virtuels dans FL et appariement entrée / sortie sur le même numéro ;
   - comportement après une réinitialisation de « Configuration audio et MIDI » ;
   - persistance de l'uniqueID ;
   - FL qui revoit le port après la relance de l'appli.
10. `IsSecureEventInputEnabled()` avec la saisie sécurisée de Terminal ; réactivation après `tapDisabledByTimeout`.
11. Comportement réel de `MenuBarExtra` + `Window` avec `LSUIElement` ; `openWindow` depuis le menu ; panneau de pause non activant sur tous les bureaux.
