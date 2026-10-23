# Animations « morph » — plan d'implémentation

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**But :** des animations façon Apple dans toute l'app (menu de l'icône, fenêtres, pages, cartes, créateur, Organiser),
sans bug, avec un seul moteur de mouvement.

**Architecture :** un moteur (`MotionEngine.swift`) porte les ressorts, les durées, le gel et les sons ; une couche de
vol (`FlightLayer.swift`) déplace icônes, titres et cartes entre deux vues d'une fenêtre ; une fenêtre de vol
(`WindowLauncher.swift`) fait sortir les fenêtres du clic ; un présentateur de cartes (`CardPresenter.swift`) remplace
les feuilles. Le menu de SwiftUI est gardé, sa fenêtre rendue transparente pour dessiner la bulle (`MenuBubble.swift`).

**Technique :** Swift 5.9, SwiftUI + AppKit, macOS 13 minimum, XCTest. Pas de Swift sur la machine de travail : la CI
macOS (`macos-26`) compile, teste et photographie.

**Conception :** `docs/superpowers/specs/2026-10-22-animations-morph-design.md` (à lire avec ce plan).

## Contraintes globales

- macOS 13 minimum ; API de macOS 14 derrière `#available(macOS 14.0, *)`, de macOS 26 derrière
  `#if compiler(>=6.2)` + `#available(macOS 26.0, *)` (comme `GlassStyle.swift:280`).
- Ressorts : vif `spring(response: 0.35, dampingFraction: 0.78)`, doux `(0.5, 1)`, liquide `(0.55, 0.62)` ; réponse
  × `DebugSnapshot.slowMotion`. Aucune autre valeur de ressort ou de durée dans le code.
- « Réduire les animations » : fondu 0,18 s, ni vol ni rebond. Ralenti actif (`slowMotion != 1`) : jamais réduit.
- Aucune copie de l'écran ; aucune fenêtre de vol visible au repos ; mémoire +5 Mo au plus (mesure CI).
- Garder intacts : `MenuBarExtra`, `MenuBarLabel`, l'ordre des scènes (`FLShortcutApp.swift:38-58`), les cas de
  `Phase`, `OrganizerWindow.controller` vidé à la fermeture, le modèle du créateur libéré, `MenuBarIcon`, la `List`
  des blocs et son `.onMove`, la scène `Window` de l'éditeur.
- Commentaires, textes et commits en français ; tout texte affiché a son anglais
  (`python3 scripts/localisation.py generer trad.json`) ; jamais de nom de son ni de texte tapé dans les journaux.
- Pas de Swift ici : tests et code d'une tâche sont poussés ensemble ; la vérification est la CI, lue avec les outils
  GitHub (`actions_list` → job « App Mac (compilation + tests) », étape « Tests Swift » : `Executed N tests, with 0
  failures` ; artefact `FLShortcuts-mac-mesure` : images relues une à une). Une tâche n'est finie qu'avec la CI verte.
- Commits : message en français, puis les deux lignes `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>` et
  `Claude-Session: https://claude.ai/code/session_015cWn3nRUmsQoCfPZgGBtCt`. Branche `claude/great-hopper-qihaiy`.

## Points de vigilance (relecture)

1. Clics répétés pendant une animation (icône, ligne du menu, bouton) : une seule fenêtre, aucune bulle restée →
   test `testDoubleOpenWhileFlying` (tâche 4).
2. FL passe devant au milieu d'un vol ou d'une carte (l'app perd la main) : rien ne reste caché ni à moitié →
   test `testSafetyEndsFlightWithoutCompletion` (tâche 2).
3. Fenêtre fermée pendant un vol ou une carte : vols annulés, carte jetée sans rien garder → tests
   `testCancelAllForgetsHiddenTargets` (tâche 2) et `testResetDropsQueue` (tâche 6).
4. Combinaisons « Réduire les animations », verre coupé, « Réduire la transparence » : le bon repli partout →
   tests `testPolicyReduced` (tâche 1), `testLegacyMenuKeepsSystemBubble` (tâche 3), `testDropsPathChoice` (tâche 7).
5. Deux écrans (menu sur l'un, fenêtre sur l'autre) : pas de vol, ouverture normale → test
   `testNoFlightAcrossScreens` (tâche 4).

---

### Tâche 1 : Moteur de mouvement

**Fichiers :**
- Créer : `Sources/FLShortcut/MotionEngine.swift`, `Sources/FLShortcut/InterfaceSound.swift`
- Modifier : `Sources/FLShortcut/GlassStyle.swift:16-195,395-414` (Motion, MotionModifier, PageReveal, MorphIn,
  TintedBackdrop), `MenuPanel.swift:61-106,198-218`, `StyledMenu.swift:119-130,166-170`,
  `FLShortcutApp.swift:538-569,796-800`, `MacroEditorView.swift:197`, `OrganizerWindow.swift:974`,
  `OnboardingView.swift:75-86`, `UninstallView.swift:386`, `EditorView.swift:205-240` (racine), `:905-912` (menu ⋯)
- Textes : `Resources/en.lproj` via `scripts/localisation.py` (« Sons de l'interface » → « Interface sounds »)
- Tests : `Tests/FLShortcutTests/MotionEngineTests.swift`

**Interfaces :**
- Produit :
  - `enum MotionSpring { case vif, doux, liquide }` ; `var response: Double`, `var damping: Double`
  - `extension Motion` : `static func spring(_ kind: MotionSpring) -> Animation` (réponse × ralenti) ;
    `static func settle(response: Double, damping: Double) -> TimeInterval` (pur) ;
    `static func settleTime(_ kind: MotionSpring) -> TimeInterval` (× ralenti) ;
    `static func springValue(at t: TimeInterval, response: Double, damping: Double) -> Double` (pur, 0 → 1) ;
    `static var appKitDuration: TimeInterval` (0,3 × ralenti, courbe `easeInEaseOut`) ; `static var smooth` calculé
    (0,2 × ralenti) ; `morph` = `spring(.doux)` ; `lift` = `spring(.vif)`
  - `enum MotionSurface { case window, menu, organiser, guide, badge, hint, recording, flight }`
  - `enum MotionMode { case full, reduced, frozen }`
  - `enum MotionPolicy { static func mode(reduceMotion: Bool, slowMotion: Double, surface: MotionSurface, isKey: Bool,
    appActive: Bool) -> MotionMode }`
  - `extension EnvironmentValues { var motionMode: MotionMode }` ; `func motionGate(_ surface: MotionSurface) -> some
    View`
  - `func glassHighlight(cornerRadius: CGFloat) -> some View`
  - `enum InterfaceSoundEvent { case cardOpen, cardClose, creatorOpen, creatorClose, dropDetach, organiserDone }`
  - `enum InterfaceSound { static let key = "interfaceSounds" ; static func allowed(event: InterfaceSoundEvent,
    enabled: Bool, systemSounds: Bool, appActive: Bool, organiserBusy: Bool) -> Bool ; static func play(_ event:
    InterfaceSoundEvent, organiserBusy: Bool = false) }`

- [ ] **Étape 1 : écrire les tests** (`MotionEngineTests.swift`)

```swift
func testSettleTimes() {
    XCTAssertEqual(Motion.settle(response: 0.35, damping: 0.78), 0.493, accuracy: 0.01)
    XCTAssertEqual(Motion.settle(response: 0.5, damping: 1), 0.732, accuracy: 0.01)
    XCTAssertEqual(Motion.settle(response: 0.55, damping: 0.62), 0.975, accuracy: 0.01)
}
func testSpringValueEnds() {
    XCTAssertEqual(Motion.springValue(at: 0, response: 0.5, damping: 1), 0, accuracy: 0.001)
    XCTAssertEqual(Motion.springValue(at: 0.732, response: 0.5, damping: 1), 1, accuracy: 0.01)
    XCTAssertGreaterThan(Motion.springValue(at: 0.2, response: 0.55, damping: 0.62), 0.5)
}
func testPolicyFreezesOnlyTheMainWindow() {
    XCTAssertEqual(MotionPolicy.mode(reduceMotion: false, slowMotion: 1, surface: .window, isKey: false, appActive: false), .frozen)
    XCTAssertEqual(MotionPolicy.mode(reduceMotion: false, slowMotion: 1, surface: .window, isKey: true, appActive: false), .full)
    for surface in [MotionSurface.menu, .organiser, .guide, .badge, .hint, .recording, .flight] {
        XCTAssertEqual(MotionPolicy.mode(reduceMotion: false, slowMotion: 1, surface: surface, isKey: false, appActive: false), .full)
    }
}
func testPolicyReduced() {
    XCTAssertEqual(MotionPolicy.mode(reduceMotion: true, slowMotion: 1, surface: .menu, isKey: true, appActive: true), .reduced)
    XCTAssertEqual(MotionPolicy.mode(reduceMotion: true, slowMotion: 10, surface: .menu, isKey: true, appActive: true), .full)
    XCTAssertEqual(MotionPolicy.mode(reduceMotion: true, slowMotion: 1, surface: .window, isKey: false, appActive: false), .frozen)
}
func testSoundRules() {
    XCTAssertTrue(InterfaceSound.allowed(event: .cardOpen, enabled: true, systemSounds: true, appActive: true, organiserBusy: false))
    XCTAssertFalse(InterfaceSound.allowed(event: .cardOpen, enabled: true, systemSounds: true, appActive: false, organiserBusy: false))
    XCTAssertTrue(InterfaceSound.allowed(event: .organiserDone, enabled: true, systemSounds: true, appActive: false, organiserBusy: false))
    XCTAssertFalse(InterfaceSound.allowed(event: .dropDetach, enabled: true, systemSounds: true, appActive: true, organiserBusy: true))
    XCTAssertFalse(InterfaceSound.allowed(event: .cardOpen, enabled: false, systemSounds: true, appActive: true, organiserBusy: false))
    XCTAssertFalse(InterfaceSound.allowed(event: .organiserDone, enabled: true, systemSounds: false, appActive: true, organiserBusy: false))
}
```

- [ ] **Étape 2 : écrire `MotionEngine.swift`**
  - `settle` : ω0 = 2π / réponse ; amortissement < 1 → ln(1000) / (amortissement × ω0) ; sinon 9,2 / ω0.
  - `springValue` : sous-amorti 1 − e^(−ζω0t)(cos ωd t + ζω0/ωd sin ωd t), ωd = ω0√(1−ζ²) ; critique
    1 − e^(−ω0t)(1 + ω0t) ; t ≥ settle → 1.
  - `MotionPolicy.mode` : `.frozen` si `surface == .window && !appActive && !isKey` ; sinon `.reduced` si
    `reduceMotion && slowMotion == 1` ; sinon `.full`.
  - `MotionGate` : lit l'état actif (`NSApplication.didBecomeActive/didResignActive`) et la fenêtre clé
    (`WindowReader`, `didBecomeKey/didResignKey`), pose `\.motionMode`, et en `.frozen` :
    `.transaction { $0.animation = nil; $0.disablesAnimations = true }`.
  - `glassHighlight` : `onContinuousHover` ; dégradé radial blanc (opacité 0,16, rayon 120) centré sur la souris,
    `.blendMode(.plusLighter)`, découpé en `RoundedRectangle(cornerRadius:style: .continuous)` ; rien hors survol ni
    en `.frozen`/`.reduced`.
- [ ] **Étape 3 : écrire `InterfaceSound.swift`** — sons `Pop` (cardOpen, creatorOpen), `Bottle` (cardClose,
  creatorClose), `Tink` (dropDetach), `Glass` (organiserDone) ; `NSSound(named:)` copié à chaque lecture, volume
  0,15 ; réglage macOS lu par `CFPreferencesCopyAppValue("com.apple.sound.uiaudio.enabled", "com.apple.systemsound")`
  (absent = activé) ; `allowed` : faux si `!enabled || !systemSounds || organiserBusy` ; `organiserDone` sans condition
  d'app active ; les autres exigent `appActive`.
- [ ] **Étape 4 : brancher le moteur** — dans `GlassStyle.swift` : `morph`, `lift`, `smooth` comme ci-dessus ;
  `MotionModifier` et `PageReveal`/`MorphIn` lisent `\.motionMode` (réduit → `Motion.reduced` ; gelé → pas
  d'animation) ; `TintedBackdrop` en `easeInOut(0,6 × ralenti)`. Remplacer les ressorts et durées en dur aux lignes
  listées (MenuReveal, StyledMenu, PanelItem, `MacroStepsPane.spring` → `Motion.spring(.vif)`, `setFrame` de
  l'Organiser → `NSAnimationContext` de durée `Motion.appKitDuration`, fondus du badge et de l'accueil →
  `Motion.appKitDuration`, coche de la désinstallation → `spring(.vif)`). `.motionGate(.window)` à la racine de
  `EditorView.body` ; `.motionGate(.organiser)` dans `OrganizerView` ; `.motionGate(.guide)` dans le guide des
  autorisations. Reflet : `.glassHighlight(cornerRadius: 10)` dans `cardRow(hover:)` (`GlassStyle.swift:784-786`, avec
  `menuHover`), sur les cartes de famille de l'Organiser (`OrganizerHoverCard`, `OrganizerWindow.swift:1494-1508`) et
  dans les styles de boutons de verre (`GlassStyle.swift:316-366`, rayon de la capsule).
- [ ] **Étape 5 : réglage « Sons de l'interface »** — `@AppStorage(InterfaceSound.key) var interfaceSounds = true`,
  entrée `.toggle(String(localized: "Sons de l'interface"), symbol: "speaker.wave.2", tint: .pink, isOn:
  $interfaceSounds)` juste après « Effet Liquid Glass » (`EditorView.swift:909`), visible sur tous les macOS.
  Anglais : « Interface sounds ».
- [ ] **Étape 6 : vérifier** — `grep -rn "spring(response\|easeInOut(duration\|easeIn(duration\|easeOut(duration"
  Sources/FLShortcut` ne renvoie plus que `MotionEngine.swift` et `GlassStyle.swift` (Motion) ; pousser ; CI : 0
  échec, « Textes en anglais » vert ; images `page-change-*`, `createur-*`, `guide-morph-*` relues (même mouvement,
  plus court).
- [ ] **Étape 7 : commit** « Moteur de mouvement : trois ressorts, gel, ralenti partout, sons de l'interface »

---

### Tâche 2 : Couche de vol

**Fichiers :**
- Créer : `Sources/FLShortcut/FlightLayer.swift`
- Modifier : `Sources/FLShortcut/EditorView.swift:205-240` (couche à la racine de la fenêtre)
- Tests : `Tests/FLShortcutTests/FlightLayerTests.swift`

**Interfaces :**
- Consomme : `Motion.spring(.doux)`, `Motion.settleTime(.doux)`, `Motion.springValue`, `\.motionMode` (tâche 1)
- Produit :
  - `enum FlightContent { case icon(symbol: String, tint: Color, size: CGFloat), text(String, font: Font),
    key(String), card(cornerRadius: CGFloat) }`
  - `final class FlightCenter: ObservableObject` : `init(now: @escaping () -> Date = Date.init, schedule: @escaping
    (TimeInterval, @escaping () -> Void) -> Void = FlightCenter.mainQueue)` ; `func register(_ id: String, view:
    NSView)`, `func unregister(_ id: String)`, `func frame(of id: String) -> CGRect?` (dans la couche),
    `func fly(_ content: FlightContent, from: String, to: String, completion: (() -> Void)? = nil)`,
    `func fly(_ content: FlightContent, fromRect: CGRect, to: String, completion: (() -> Void)? = nil)`,
    `func cancelAll()`, `@Published private(set) var hidden: Set<String>`
  - `extension View` : `func frameProbe(_ id: String) -> some View`, `func flightTarget(_ id: String) -> some View`
    (opacité 0 tant que `hidden` contient `id`), `func flightLayer(_ center: FlightCenter) -> some View`
  - `enum FlightGeometry { static func rect(at progress: CGFloat, from: CGRect, to: CGRect) -> CGRect ;
    static func local(_ rect: CGRect, of view: NSView, in layer: NSView) -> CGRect ;
    static func safetyDeadline(slowMotion: Double) -> TimeInterval }`

- [ ] **Étape 1 : écrire les tests**

```swift
func testRectInterpolation() {
    let a = CGRect(x: 0, y: 0, width: 20, height: 20), b = CGRect(x: 100, y: 50, width: 60, height: 40)
    XCTAssertEqual(FlightGeometry.rect(at: 0, from: a, to: b), a)
    XCTAssertEqual(FlightGeometry.rect(at: 1, from: a, to: b), b)
    XCTAssertEqual(FlightGeometry.rect(at: 0.5, from: a, to: b), CGRect(x: 50, y: 25, width: 40, height: 30))
}
func testLocalConversionUsesTheLayerView() {   // couche retournée (origine en haut), vue dans un parent normal
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    let layer = FlippedView(frame: root.bounds); root.addSubview(layer)
    let probe = NSView(frame: NSRect(x: 10, y: 250, width: 30, height: 20)); root.addSubview(probe)
    XCTAssertEqual(FlightGeometry.local(probe.bounds, of: probe, in: layer), CGRect(x: 10, y: 30, width: 30, height: 20))
}
func testSafetyDeadlineFollowsSlowMotion() {
    XCTAssertEqual(FlightGeometry.safetyDeadline(slowMotion: 1), 2)
    XCTAssertEqual(FlightGeometry.safetyDeadline(slowMotion: 10), 20)
}
func testSafetyEndsFlightWithoutCompletion() {   // Point de vigilance 2
    let center = FlightCenter(now: { Date(timeIntervalSince1970: 0) }, schedule: { _, _ in })   // rien ne s'exécute
    center.testFly(target: "t")
    XCTAssertEqual(center.hidden, ["t"])
    center.expire(at: Date(timeIntervalSince1970: 2.1))
    XCTAssertTrue(center.hidden.isEmpty)
}
func testCancelAllForgetsHiddenTargets() {   // Point de vigilance 3
    let center = FlightCenter(now: Date.init, schedule: { _, _ in })
    center.testFly(target: "a"); center.testFly(target: "b")
    center.cancelAll()
    XCTAssertTrue(center.hidden.isEmpty)
}
```
  (`FlippedView` : petite classe de test `override var isFlipped: Bool { true }` ; `testFly(target:)` et
  `expire(at:)` sont `internal`, pour les tests.)

- [ ] **Étape 2 : écrire `FlightLayer.swift`**
  - `frameProbe` : `NSViewRepresentable` qui s'inscrit auprès du `FlightCenter` de l'environnement
    (`register` à `viewDidMoveToWindow`, `unregister` quand il quitte la fenêtre).
  - `frame(of:)` lu au moment du vol (après `layoutSubtreeIfNeeded` de la fenêtre), converti par
    `FlightGeometry.local` vers la vue de la couche (inscrite elle aussi par un `frameProbe` interne).
  - Un vol : départ visible, `hidden.insert(to)`, copie dessinée par un `AnimatableModifier` de `progress` 0 → 1
    (`Motion.spring(.doux)`) placé avec `FlightGeometry.rect` ; la copie est dessinée à la taille d'arrivée et mise
    à l'échelle `rect.width / to.width`. Fin à `Motion.settleTime(.doux)` (minuteur, macOS 13) ; sûreté
    `safetyDeadline` qui retire le vol et `to` de `hidden` quoi qu'il arrive.
  - Même cible déjà en vol : le nouveau vol part de `rect(at: springValue(écoulé))` de l'ancien, qui est retiré.
  - Cadre manquant, mode `.reduced` ou `.frozen` : pas de vol, `completion` tout de suite.
  - `flightLayer` : `.overlay` sans clic (`allowsHitTesting(false)`), `.ignoresSafeArea()`, injecte le centre dans
    l'environnement ; `cancelAll()` à `NSWindow.willCloseNotification` de sa fenêtre.
- [ ] **Étape 3 : poser la couche** — `@StateObject private var flights = FlightCenter()` dans `EditorView`,
  `.flightLayer(flights)` sur le `ZStack` racine de `body` (créateur compris).
- [ ] **Étape 4 : vérifier** — pousser ; CI : 0 échec ; captures de la page Général inchangées (`*-general.png`).
- [ ] **Étape 5 : commit** « Couche de vol : un seul mécanisme pour ce qui vole dans une fenêtre »

---

### Tâche 3 : Menu de l'icône en bulle

**Fichiers :**
- Créer : `Sources/FLShortcut/MenuBubble.swift`
- Modifier : `Sources/FLShortcut/MenuPanel.swift` (ouverture, fermeture, cadre de l'icône),
  `FLShortcutApp.swift:701-718` (`MenuContent` : `.menuBubble`), `DebugSnapshot.swift:12-50,275-300` (commande
  `menu`), `scripts/mesure-interface.sh:227-247` (captures)
- Tests : `Tests/FLShortcutTests/MenuBubbleTests.swift`

**Interfaces :**
- Consomme : `Motion.spring(.doux)`, `Motion.settleTime(.doux)`, `Motion.spring(.vif)` (tâche 1)
- Produit :
  - `enum MenuBubbleSupport { static let legacyKey = "legacyMenu" ; static func prepare(_ window: NSWindow,
    legacy: Bool, host: NSView? = nil) -> Bool }` (vrai : bulle à nous ; faux : rien n'a changé ; `host` : vue
    SwiftUI du menu, trouvée seule si nil)
  - `enum MenuBubbleGeometry { static let margin = EdgeInsets(top: 0, leading: 20, bottom: 28, trailing: 20) ;
    static func pill(icon: CGRect, window: CGRect) -> CGRect }` (pastille dans le contenu, origine en haut à gauche)
  - `MenuPanel` : `@Published private(set) var bubble: Bool`, `var statusIconFrame: CGRect?` (cadre de l'icône à
    l'écran, utilisé aussi par la tâche 4), `@Published private(set) var pillFrame: CGRect`
  - `extension View { func menuBubble(_ panel: MenuPanel) -> some View }`
  - `DebugSnapshot.menu` (« ouvrir », « fermer », + « lent »)

- [ ] **Étape 1 : écrire les tests**

```swift
func testPillStartsUnderTheIcon() {
    let window = CGRect(x: 1000, y: 700, width: 340, height: 420)   // écran, origine en bas
    let icon = CGRect(x: 1150, y: 1120, width: 28, height: 24)
    XCTAssertEqual(MenuBubbleGeometry.pill(icon: icon, window: window), CGRect(x: 150, y: 0, width: 28, height: 24))
}
func testPillFollowsTheIconNearTheEdge() {   // macOS décale le menu près du bord : la pastille reste sous l'icône
    let window = CGRect(x: 1580, y: 700, width: 340, height: 420)
    let icon = CGRect(x: 1880, y: 1120, width: 28, height: 24)
    XCTAssertEqual(MenuBubbleGeometry.pill(icon: icon, window: window).midX, 314)
}
func testPreparedWindowHidesOnlyTheSystemBackground() {
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.borderless], backing: .buffered, defer: true)
    let background = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
    let host = NSView(frame: background.bounds); let inner = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
    host.addSubview(inner); background.addSubview(host); window.contentView = background
    XCTAssertTrue(MenuBubbleSupport.prepare(window, legacy: false, host: host))
    XCTAssertTrue(background.isHidden || background.alphaValue == 0)
    XCTAssertFalse(inner.isHidden)
    XCTAssertFalse(window.isOpaque); XCTAssertEqual(window.backgroundColor, .clear); XCTAssertFalse(window.hasShadow)
}
func testLegacyMenuKeepsSystemBubble() {   // Point de vigilance 4
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.borderless], backing: .buffered, defer: true)
    window.contentView = NSVisualEffectView()
    XCTAssertFalse(MenuBubbleSupport.prepare(window, legacy: true))
    XCTAssertTrue(window.hasShadow)
    let bare = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.borderless], backing: .buffered, defer: true)
    XCTAssertFalse(MenuBubbleSupport.prepare(bare, legacy: false), "pas de fond système trouvé : rien ne change")
}
```

- [ ] **Étape 2 : écrire `MenuBubble.swift`**
  - `prepare` : rien si `legacy` ; vue hôte = `host` ou la première `NSHostingView` de la fenêtre ; cherche les
    `NSVisualEffectView` qui sont la vue de contenu, ses ancêtres ou les frères de la vue hôte, jamais à l'intérieur
    de la vue hôte ; aucune trouvée → faux sans rien changer ; sinon les masque, `backgroundColor = .clear`,
    `isOpaque = false`, `hasShadow = false`, vrai. Rappelé à chaque ouverture.
  - `pill` : largeur `max(icon.width, 28)`, hauteur 24, centrée sur `icon.midX - window.minX`, `y = 0`, gardée dans
    `0...window.width`.
  - `menuBubble` : si `panel.bubble` faux → `menuReveal(panel.revealed)` d'aujourd'hui ; sinon marges
    `MenuBubbleGeometry.margin` autour du contenu, fond = `RoundedRectangle(cornerRadius: 18, style: .continuous)`
    dont le cadre va de `pillFrame` (fermé) au cadre du contenu (ouvert) en `spring(.doux)`, ombre dessinée (noir
    0,25, rayon 18, y 8). Verre (`MenuBubbleStyle.glass`, vrai au départ) : macOS 26 + « Effet Liquid Glass » +
    transparence non réduite → `glassEffect` ; sinon fond opaque `windowBackgroundColor` + `BrandGlow().opacity(0.55)`.
    Lignes : `menuRevealRow` d'aujourd'hui, départ quand la bulle a fait 60 % (`0,6 × settleTime(.doux)`).
- [ ] **Étape 3 : `MenuPanel`** — `opened()` : `bubble = MenuBubbleSupport.prepare(panel, legacy:
  UserDefaults.standard.bool(forKey: legacyKey))`, `statusIconFrame = statusButton?.window?.frame`, `pillFrame`
  calculé, puis `reveal()`. `close()` en bulle : pas de fondu de toute la fenêtre ; `revealed = false` (bulle qui
  rentre, `spring(.doux)`), `performClick` après `settleTime(.doux)`. En ancien menu : inchangé.
- [ ] **Étape 4 : commande CI `menu`** — dans `MenuBarLabel` : « ouvrir » → `statusButton.performClick` ;
  « fermer » → `MenuPanel.shared.close()` ; « lent » → ralenti 10. Script : `menu "ouvrir lent"` puis 8 captures
  `menu-ouverture-$i.png` toutes les 0,5 s, `menu "fermer lent"` puis 6 captures `menu-fermeture-$i.png`.
- [ ] **Étape 5 : vérifier** — pousser ; CI : 0 échec ; images `menu-ouverture-*` : une pastille sous l'icône qui
  grandit, aucun fond de macOS derrière, verre qui laisse voir le fond flouté (macOS 26). Si le verre est plat ou
  transparent sans flou : `MenuBubbleStyle.glass = false` (fond opaque), repousser, revérifier.
- [ ] **Étape 6 : commit** « Menu de l'icône : la bulle naît de l'icône (repli automatique sur l'ancien menu) »

---

### Tâche 4 : Fenêtres qui sortent du clic

**Fichiers :**
- Créer : `Sources/FLShortcut/WindowLauncher.swift`
- Modifier : `FLShortcutApp.swift:657-697,772-825` (lignes du menu : cadre de la ligne, ouvertures),
  `OrganizerWindow.swift:908-947,989-1001` (ouverture invisible, fermeture), `OnboardingView.swift:21-86`,
  `UninstallView.swift:154-179`, `AccessibilityGuide.swift:80-110`, `EditorView.swift:221` (cadre mémorisé),
  `DebugSnapshot.swift:105-270` (fenêtres de vol exclues ; commande `vol`), `scripts/mesure-interface.sh`
- Tests : `Tests/FLShortcutTests/WindowLauncherTests.swift`

**Interfaces :**
- Consomme : `FlightContent`, `FlightGeometry.rect` (tâche 2) ; `MenuPanel.shared.statusIconFrame` (tâche 3) ;
  `Motion.spring(.doux)`, `Motion.settleTime(.doux)` (tâche 1)
- Produit :
  - `enum LaunchEvent { case open, landed, windowVisible, timeout, close, finished }`
  - `enum LaunchState: Equatable { case idle, flying, waiting, revealing, closing ; func next(_ e: LaunchEvent) ->
    LaunchState }`
  - `enum LaunchDecision { static func flies(sourceScreen: CGRect?, targetScreen: CGRect?, alreadyVisible: Bool,
    miniaturized: Bool, fullScreen: Bool, onActiveSpace: Bool, reduced: Bool) -> Bool }`
  - `enum WindowFrameMemory { static func save(_ frame: CGRect, key: String, defaults: UserDefaults) ;
    static func load(key: String, defaults: UserDefaults) -> CGRect? ; static func centered(size: CGSize, in screen:
    CGRect) -> CGRect }`
  - `final class WindowLauncher` : `static let shared` ; `func open(source: CGRect?, icon: FlightContent?, title:
    String?, window: NSWindow)` (fenêtre créée par l'app, encore invisible) ; `func openScene(source: CGRect?, icon:
    FlightContent?, title: String?, frameKey: String, size: CGSize, open: @escaping () -> Void)` ;
    `func userClosed(_ window: NSWindow)` ; `func quietClose(_ window: NSWindow)`
  - `final class FlightWindow: NSPanel` (sans bord, transparente, `ignoresMouseEvents`, niveau `.popUpMenu`,
    `[.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]`)

- [ ] **Étape 1 : écrire les tests**

```swift
func testDoubleOpenWhileFlying() {   // Point de vigilance 1
    XCTAssertEqual(LaunchState.idle.next(.open), .flying)
    XCTAssertEqual(LaunchState.flying.next(.open), .flying, "deuxième clic ignoré")
    XCTAssertEqual(LaunchState.waiting.next(.open), .waiting)
}
func testLaunchPath() {
    XCTAssertEqual(LaunchState.flying.next(.landed), .waiting)
    XCTAssertEqual(LaunchState.waiting.next(.windowVisible), .revealing)
    XCTAssertEqual(LaunchState.waiting.next(.timeout), .idle, "fenêtre absente : bulle retirée, rien d'invisible")
    XCTAssertEqual(LaunchState.revealing.next(.finished), .idle)
    XCTAssertEqual(LaunchState.flying.next(.close), .closing)
    XCTAssertEqual(LaunchState.closing.next(.finished), .idle)
}
func testNoFlightAcrossScreens() {   // Point de vigilance 5
    let a = CGRect(x: 0, y: 0, width: 1440, height: 900), b = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
    XCTAssertFalse(LaunchDecision.flies(sourceScreen: a, targetScreen: b, alreadyVisible: false, miniaturized: false, fullScreen: false, onActiveSpace: true, reduced: false))
    XCTAssertTrue(LaunchDecision.flies(sourceScreen: a, targetScreen: a, alreadyVisible: false, miniaturized: false, fullScreen: false, onActiveSpace: true, reduced: false))
}
func testNoFlightForVisibleHiddenOrReduced() {
    let a = CGRect(x: 0, y: 0, width: 1440, height: 900)
    for (visible, mini, full, space, reduced) in [(true, false, false, true, false), (false, true, false, true, false),
                                                  (false, false, true, true, false), (false, false, false, false, false),
                                                  (false, false, false, true, true)] {
        XCTAssertFalse(LaunchDecision.flies(sourceScreen: a, targetScreen: a, alreadyVisible: visible, miniaturized: mini, fullScreen: full, onActiveSpace: space, reduced: reduced))
    }
    XCTAssertFalse(LaunchDecision.flies(sourceScreen: nil, targetScreen: a, alreadyVisible: false, miniaturized: false, fullScreen: false, onActiveSpace: true, reduced: false))
}
func testFrameMemory() {
    let d = UserDefaults(suiteName: "test.\(UUID())")!
    XCTAssertNil(WindowFrameMemory.load(key: "editorFrame", defaults: d))
    WindowFrameMemory.save(CGRect(x: 10, y: 20, width: 900, height: 600), key: "editorFrame", defaults: d)
    XCTAssertEqual(WindowFrameMemory.load(key: "editorFrame", defaults: d), CGRect(x: 10, y: 20, width: 900, height: 600))
    XCTAssertEqual(WindowFrameMemory.centered(size: CGSize(width: 900, height: 600), in: CGRect(x: 0, y: 0, width: 1500, height: 1000)),
                   CGRect(x: 300, y: 200, width: 900, height: 600))
}
```

- [ ] **Étape 2 : écrire `WindowLauncher.swift`**
  - Une `FlightWindow` par vol, au cadre de l'union départ ∪ arrivée (+ 40 de marge), retirée et libérée
    (`contentView = nil`, `close()`) à la fin ; contenu SwiftUI : bulle `RoundedRectangle` (rayon 14 → 12 ; verre ou
    fond opaque comme la bulle du menu), icône et titre de la ligne qui vont du haut-gauche de la ligne au haut-gauche
    de la fenêtre (+ 78, + 14 : après les boutons de la barre de titre).
  - `open(window:)` : `alphaValue = 0`, `animationBehavior = .none`, fenêtre montrée tout de suite (invisible), vol
    vers son cadre ; à 85 % (`0,85 × settleTime(.doux)`) fondu de la fenêtre 0,12 s et de la bulle.
  - `openScene` : vise `WindowFrameMemory.load(frameKey)` sinon `centered(size:)` ; `open()` à l'atterrissage ;
    bulle tenue jusqu'à `didBecomeKey`/occlusion visible de la fenêtre (1 s au plus, puis `.timeout`), fondu 0,15 s ;
    fenêtre ouverte ailleurs que prévu (écart > 40) : fondu sans viser.
  - `LaunchDecision.flies` faux → ouverture normale (`animationBehavior = .documentWindow`), aucune bulle.
  - `userClosed` : bulle du cadre de la fenêtre vers `statusIconFrame` (même écran, sinon rien) ; `quietClose`
    marque une fermeture décidée par l'app (pas de bulle).
  - Source absente (ouverture par l'app) : `statusIconFrame` comme départ.
- [ ] **Étape 3 : brancher** — `PanelItem` : `frameProbe` lu à l'écran au clic (`window.convertToScreen`), passé aux
  actions ; « Modifier les raccourcis… », « Macros… », « Signaler ce problème… » → `openScene(frameKey:
  "editorFrame", size: CGSize(width: 900, height: 620), open: { openWindow(id: "editor"); NSApp.activate(...) })` ;
  « Organiser… » → `OrganizerWindow.open(source:)` (panneau créé invisible puis `WindowLauncher.open`) ; « Tout
  autoriser… » et « Désinstaller… » pareil. `EditorView` : cadre mémorisé à `didMove`/`didEndLiveResize` (clé
  `editorFrame`), `animationBehavior = .none`. Fin de l'accueil (`OnboardingView.swift:68-86`) → `quietClose`.
  Fermetures par l'utilisateur (bouton rouge, ⌘W, « Fermer », « Arrêter » de l'Organiser) → `userClosed`.
  `OrganizerWindow.close()` vide `controller` avant toute bulle (test existant `testControllerReleasedOnClose`).
- [ ] **Étape 4 : CI** — `DebugSnapshot` ignore les `FlightWindow` (rapport, `screenPoint`, `capture`) ; commande
  `vol` (« editeur lent », « organiser lent ») qui ouvre depuis un cadre d'exemple (centre de l'écran, 280 × 34) ;
  script : 8 captures `vol-editeur-$i.png`, 8 `vol-organiser-$i.png`.
- [ ] **Étape 5 : vérifier** — pousser ; CI : 0 échec, mémoire (`mesure`) +5 Mo au plus ; images : bulle qui part du
  cadre d'exemple et finit au cadre de la fenêtre, aucune fenêtre de vol dans les captures de repos.
- [ ] **Étape 6 : commit** « Fenêtres : elles sortent du clic et rentrent dans l'icône »

---

### Tâche 5 : Fenêtre principale — pages et listes

**Fichiers :**
- Modifier : `GlassStyle.swift:102-155` (PageReveal sans déplacement), `EditorView.swift:441-513` (icônes de la
  barre latérale), `:534` (changement de page), `:1334-1360` (`PageHeader`), `:729,935-982,1472-1534,1951` et
  `MacroLibraryView.swift:226,233` (mutations animées), recherche (`searchResults`)
- Tests : `Tests/FLShortcutTests/ListMotionTests.swift`

**Interfaces :**
- Consomme : `FlightCenter.fly`, `frameProbe`, `flightTarget` (tâche 2) ; `Motion.spring(.vif)` (tâche 1)
- Produit : `enum ListMotion { static let limit = 60 ; static func animates(changes: Int) -> Bool ;
  static func changes<ID: Hashable>(from: [ID], to: [ID]) -> Int }` ; `func withListAnimation<R>(changes: Int, _ body:
  () throws -> R) rethrows -> R`

- [ ] **Étape 1 : écrire les tests**

```swift
func testListLimit() {
    XCTAssertTrue(ListMotion.animates(changes: 1))
    XCTAssertTrue(ListMotion.animates(changes: 60))
    XCTAssertFalse(ListMotion.animates(changes: 61))
    XCTAssertFalse(ListMotion.animates(changes: 0))
}
func testChangesCount() {
    XCTAssertEqual(ListMotion.changes(from: [1, 2, 3], to: [1, 3, 4]), 2)   // 2 parti, 4 arrivé
    XCTAssertEqual(ListMotion.changes(from: [1, 2, 3], to: [3, 2, 1]), 2)   // déplacés : hors de la plus longue suite gardée
}
```
  (`changes` : retirés + ajoutés + gardés hors de la plus longue sous-suite commune.)

- [ ] **Étape 2 : page qui change** — `SoftFocus(amount:rise:still:)` : `still` vrai → ni décalage ni échelle (flou et
  opacité seulement) ; `pageSwitch` l'utilise. `SectionIcon` des lignes de la barre latérale :
  `.frameProbe("side.\(id)")` ; icône de `PageHeader` : `.frameProbe("header")` + `.flightTarget("header")`. À un
  changement de `selection` venu d'un clic ou du clavier (pas de `resumeIfAsked` ni des commandes CI sans « lent »),
  `flights.fly(.icon(symbol:tint:size: 44), from: "side.\(new.id)", to: "header")`.
- [ ] **Étape 3 : listes** — chaque mutation listée passe par `withListAnimation(changes:)` (vif si `animates`, sinon
  sans animation) ; la liste filtrée de la recherche anime `trimmedQuery` de la même façon (lignes avant/après).
- [ ] **Étape 3 bis : chiffres qui défilent** — `.contentTransition(.numericText())` + `.animation(Motion.spring(.vif),
  value:)` sur le sous-titre de `PageHeader` (compte de la page) et sur les nombres de l'en-tête de la Communauté
  (`CommunityView.swift:763`).
- [ ] **Étape 4 : vérifier** — pousser ; CI : 0 échec ; images `page-change-*` : l'icône vole de la barre latérale à
  l'en-tête, pas de titre en double, page sans glissement.
- [ ] **Étape 5 : commit** « Fenêtre principale : l'icône vole jusqu'à la page, les listes glissent »

---

### Tâche 6 : Cartes au lieu des feuilles

**Fichiers :**
- Créer : `Sources/FLShortcut/CardPresenter.swift`
- Modifier : `EditorView.swift:171-176,231-233,416-420,565-580,725,797-820,924`, `EditSheet` (`:1378-1560`),
  `CatalogEditSheet` (`:1921-2040`), `Guide.swift:392-…` (`GuideSheet`), `MacroLibraryView.swift:67-70,343-390`,
  `CommunityView.swift:79-103,544-735,949-1160`, `DebugSnapshot.swift` (commande `carte`), script
- Tests : `Tests/FLShortcutTests/CardPresenterTests.swift`

**Interfaces :**
- Consomme : `FlightCenter.frame(of:)`, `FlightGeometry.rect` (tâche 2) ; `InterfaceSound.play(.cardOpen/.cardClose)`,
  `Motion.spring(.doux)`, `Motion.settleTime(.doux)` (tâche 1)
- Produit :
  - `enum CardKind { case editRemap(Remap, isNew: Bool), editCatalog(CatalogRow, notice: String?), guide(page: Int),
    templates, communityShare(Share), communityCompose, communityReport(Share) }` (`Share` : type des partages,
    `CommunityView.swift:58`)
  - `struct CardRequest: Identifiable { let id = UUID() ; let kind: CardKind ; let source: String? }`
  - `struct CardQueue { private(set) var current: CardRequest? ; private(set) var closing: Bool ;
    private(set) var waiting: [CardRequest] ; mutating func request(_ r: CardRequest) ; mutating func close() ;
    mutating func closeFinished() ; mutating func reset() }`
  - `final class CardPresenter: ObservableObject` (`present(_:)`, `dismiss()`, `var isPresenting: Bool`,
    `@Published private(set) var queue: CardQueue`)
  - `extension EnvironmentValues { var cardDismiss: () -> Void }` ; `func cardHost<C: View>(_ presenter:
    CardPresenter, @ViewBuilder content: @escaping (CardKind) -> C) -> some View`

- [ ] **Étape 1 : écrire les tests**

```swift
func testRequestWhileClosingWaits() {
    var q = CardQueue()
    let a = CardRequest(kind: .templates, source: nil), b = CardRequest(kind: .guide(page: 0), source: nil)
    q.request(a); XCTAssertEqual(q.current?.id, a.id)
    q.close(); XCTAssertTrue(q.closing)
    q.request(b); XCTAssertEqual(q.current?.id, a.id, "b attend la fin de la fermeture")
    q.closeFinished(); XCTAssertEqual(q.current?.id, b.id); XCTAssertFalse(q.closing)
}
func testRequestWhileOpenClosesFirst() {
    var q = CardQueue()
    let a = CardRequest(kind: .templates, source: nil), b = CardRequest(kind: .communityCompose, source: nil)
    q.request(a); q.request(b)
    XCTAssertTrue(q.closing); XCTAssertEqual(q.waiting.map(\.id), [b.id])
}
func testCloseIsIdempotent() {
    var q = CardQueue(); q.close(); q.closeFinished()
    XCTAssertNil(q.current); XCTAssertFalse(q.closing)
    q.request(CardRequest(kind: .templates, source: nil)); q.close(); q.close()
    XCTAssertTrue(q.closing); q.closeFinished(); XCTAssertNil(q.current)
}
func testResetDropsQueue() {   // Point de vigilance 3 (fenêtre fermée pendant une carte)
    var q = CardQueue()
    q.request(CardRequest(kind: .templates, source: nil)); q.request(CardRequest(kind: .communityCompose, source: nil))
    q.reset()
    XCTAssertNil(q.current); XCTAssertTrue(q.waiting.isEmpty); XCTAssertFalse(q.closing)
}
```

- [ ] **Étape 2 : écrire `CardPresenter.swift`** — `cardHost` à la racine de `EditorView.shortcuts` : voile
  (`.ultraThinMaterial` + noir 0,18, clic = annuler) ; carte de verre (`RoundedRectangle(cornerRadius: 22)`, ombre)
  qui grandit du cadre de `source` (sinon d'un rectangle de 60 % au centre) jusqu'à sa place, en `spring(.doux)` ;
  hauteur au plus celle du contenu de la fenêtre moins 48, `ScrollView` au-delà ; contenu en fondu flou après 40 % du
  vol ; fermeture : contenu d'abord (vif), carte qui rentre dans `source`, puis `closeFinished()` à
  `settleTime(.doux)`. Pendant une carte : tout le contenu derrière `.disabled(true)` + `.accessibilityHidden(true)` ;
  boutons de `withToolbar` `.disabled(presenter.isPresenting)` ; `.closable` retiré de la fenêtre (rendu à la fin) ;
  `defaultFocus` sur le premier champ de la carte ; sons `cardOpen`/`cardClose`. `reset()` à la fermeture de la
  fenêtre.
- [ ] **Étape 3 : remplacer les feuilles** — chaque `.sheet` listé → `cards.present(CardRequest(kind:source:))`
  (source : `frameProbe` de la ligne cliquée, ex. `"remap.\(id)"`, `"share.\(id)"`) ; chaque `@Environment(\.dismiss)`
  de ces vues → `@Environment(\.cardDismiss)` ; chaque vue a un bouton `.keyboardShortcut(.cancelAction)` (en ajouter
  un caché sinon) et son bouton principal `.defaultAction` ; les `asyncAfter` de reprise (`EditorView.swift:570-575`,
  `CommunityView.swift:100-103`) deviennent un `present` immédiat (la file attend).
- [ ] **Étape 4 : nom et touche qui volent** (fiche d'un raccourci) — la ligne porte `frameProbe("remap.\(id).title")`
  et `"remap.\(id).key"` ; l'en-tête de `EditSheet` porte les cibles `"card.title"`, `"card.key"` ; vols `.text` et
  `.key` au début de l'ouverture.
- [ ] **Étape 5 : CI** — commande `carte` (« raccourci lent », « modeles lent », « fermer ») ; 8 captures
  `carte-ouverture-$i.png`, 6 `carte-fermeture-$i.png` ; les captures existantes de la Communauté (`detail`,
  `partager`, `signaler`) montrent maintenant des cartes.
- [ ] **Étape 6 : vérifier** — pousser ; CI : 0 échec, textes anglais verts ; images : carte qui sort de la ligne,
  page voilée, barre d'outils grisée, aucune carte coupée sur une fenêtre de 480 de haut (`resize "820,480"`).
- [ ] **Étape 7 : commit** « Cartes : les fiches sortent de la ligne cliquée et y retournent »

---

### Tâche 7 : Créateur de macros

**Fichiers :**
- Créer : `Sources/FLShortcut/LiquidDrops.swift`
- Modifier : `MacroEditorView.swift:82-110,199-219,283-312,416-480`, `MacroPalette.swift:61-79`,
  `MacroInspector.swift:20-40`, `MacroEditorModel.swift:441` (dernier bloc posé), `EditorView.swift:315-372`
  (entrée et sortie du créateur), `MacroLibraryView.swift` (lignes : `frameProbe("macro.\(id)")`),
  `DebugSnapshot.swift` (commande `gouttes`), script
- Tests : `Tests/FLShortcutTests/LiquidDropsTests.swift`

**Interfaces :**
- Consomme : `FlightCenter.fly`, `frameProbe`, `flightTarget`, `.card` (tâche 2) ; `Motion.spring(.liquide/.vif/.doux)`,
  `InterfaceSound.play(.dropDetach/.creatorOpen/.creatorClose)` (tâche 1)
- Produit :
  - `enum DropLayout { static func positions(count: Int, progress: CGFloat, width: CGFloat, size: CGFloat,
    spacing: CGFloat) -> [CGFloat] }` (centres, depuis le bord gauche de la barre)
  - `enum LiquidDrops { static func useNativeGlass(available: Bool, glassEnabled: Bool, reduceTransparency: Bool) ->
    Bool }` ; `struct LiquidDropsBar<Content: View>: View` (`progress`, boutons posés dessus)
  - `MacroEditorModel` : `@Published private(set) var landed: UUID?` (bloc qui vient d'être posé, remis à nil après
    `settleTime(.vif)`)

- [ ] **Étape 1 : écrire les tests**

```swift
func testDropsStartInsideTheAddButton() {
    XCTAssertEqual(DropLayout.positions(count: 3, progress: 0, width: 400, size: 30, spacing: 10), [15, 15, 15])
}
func testDropsEndSpaced() {
    XCTAssertEqual(DropLayout.positions(count: 3, progress: 1, width: 400, size: 30, spacing: 10), [15, 55, 95])
}
func testDropsStayInsideNarrowBar() {
    let p = DropLayout.positions(count: 3, progress: 1, width: 80, size: 30, spacing: 10)
    XCTAssertLessThanOrEqual(p.last! + 15, 80)
}
func testDropsPathChoice() {   // Point de vigilance 4
    XCTAssertTrue(LiquidDrops.useNativeGlass(available: true, glassEnabled: true, reduceTransparency: false))
    XCTAssertFalse(LiquidDrops.useNativeGlass(available: true, glassEnabled: false, reduceTransparency: false))
    XCTAssertFalse(LiquidDrops.useNativeGlass(available: false, glassEnabled: true, reduceTransparency: false))
    XCTAssertFalse(LiquidDrops.useNativeGlass(available: true, glassEnabled: true, reduceTransparency: true))
}
```

- [ ] **Étape 2 : écrire `LiquidDrops.swift`** — `positions` : xᵢ = x₀ + (xᵢ final − x₀) × progress, x₀ = size/2,
  xᵢ final = size/2 + i × (size + spacing) ; si la dernière dépasse `width − size/2`, `spacing` réduit (au plus
  jusqu'à 0). Chemin natif : `GlassEffectContainer(spacing: 20)` + `glassEffect()` + `glassEffectID("add"/"dup"/"del",
  in:)`. Chemin dessiné : `Canvas` avec `addFilter(.alphaThreshold(min: 0.5, color: Color.primary.opacity(0.12)))` puis
  `addFilter(.blur(radius: 6))`, un cercle par bouton aux `positions`, `progress` animé par un `AnimatableModifier`.
- [ ] **Étape 3 : barre du bas** — `actionBar` garde son `ViewThatFits` ; « Dupliquer » et « Supprimer » n'existent que
  si `model.selectedBlock != nil` ; `progress` 0 → 1 en `spring(.liquide)` (son `dropDetach`), 1 → 0 en `spring(.vif)`.
- [ ] **Étape 4 : bloc posé** — après `move(fromOffsets:toOffset:)`, `landed = id` ; `MacroStepRowView` (`Equatable`,
  `landed` dans son égalité) éclaire son fond de sa couleur (opacité 0,25 → 0, vif).
- [ ] **Étape 5 : vols du créateur** — clic dans la palette (pas le glisser) : `.icon` de `"palette.\(id)"` vers
  `"block.\(new).icon"` ; choix d'un bloc à la souris (`NSApp.currentEvent?.type == .leftMouseDown`) : `.icon` de
  `"block.\(id).icon"` vers `"inspector.icon"` ; ouverture du créateur depuis la page Macros : `.card(cornerRadius: 12)`
  du cadre `"macro.\(id)"` vers le contenu de la fenêtre, puis fondu du créateur (son `creatorOpen`) ; retour :
  l'inverse si la ligne est visible (son `creatorClose`).
- [ ] **Étape 6 : CI** — commande `gouttes` (« choisir lent », « lacher lent ») sur la macro d'exemple ; 8 captures
  `gouttes-$i.png`, avec verre puis sans verre (passe « sans verre » existante) ; captures `createur-ouverture-*` et
  `createur-glisse` relues. Essai CI du glisser (`mesure-interface.sh:260-266`) toujours « ordre changé ».
- [ ] **Étape 7 : vérifier** — pousser ; CI : 0 échec ; images : gouttes qui sortent du bouton Ajouter (macOS 26) et
  gouttes dessinées (sans verre) ; ordre des blocs toujours changé par le glisser.
- [ ] **Étape 8 : commit** « Créateur : gouttes de verre, blocs qui volent et s'éclairent à la pose »

---

### Tâche 8 : Organiser

**Fichiers :**
- Modifier : `OrganizerSession.swift:180-240,464-520` (famille définitive de chaque son), `OrganizerWindow.swift:68-140`
  (environnement), `:578-601,773-823` (contrôleur), `:1026-1206` (vues), `:1320-1340,1494-1561` (attente, badge,
  `WaitingPulse`) — cas de `Phase` (`:344-357`) inchangés
- Textes : « %lld s », « ✓ %lld sons rangés », « Retour en arrière… » (anglais)
- Tests : `Tests/FLShortcutTests/OrganizerSessionTests.swift`, `OrganizerWindowTests.swift`

**Interfaces :**
- Consomme : `Motion.spring(.vif/.doux)`, `Motion.appKitDuration`, `InterfaceSound.play(.organiserDone)` (tâche 1)
- Produit :
  - `OrganizerSession` : paramètre d'init `classified: @escaping (SoundFamily) -> Void = { _ in }` (après `progress`)
  - `OrganizerController` : `@Published private(set) var liveFamilies: [SoundFamily: Int]` ;
    `var organizedCount: Int` (somme des membres des familles de l'aperçu) ; `@Published private(set) var showingDone:
    Bool`
  - `enum SecondsCounter { static func text(_ elapsed: TimeInterval) -> String }`
  - `OrganizerWindow.growForPreview(completion: @escaping () -> Void)`

- [ ] **Étape 1 : écrire les tests**

```swift
// OrganizerSessionTests (même projet que testSampleFileNameTellsWhatTheSoundIs, plus un canal « Serum » entendu
// comme Drums : la règle du synthé de mélodies doit déjà être appliquée quand sa famille est signalée)
func testLiveFamiliesMatchTheResult() throws {
    var live: [SoundFamily: Int] = [:]
    let session = OrganizerSession(link: link, audio: audio, classify: classify, nameDrum: { _, _ in .kick },
                                   timing: timing, sleep: { _ in }, files: files,
                                   classified: { live[$0, default: 0] += 1 })
    let result = try session.run().get()
    XCTAssertEqual(live, Dictionary(grouping: result.items, by: \.family).mapValues(\.count))
}

// OrganizerWindowTests
func testSecondsCounter() {
    XCTAssertEqual(SecondsCounter.text(0), "0 s")
    XCTAssertEqual(SecondsCounter.text(4.7), "4 s")
}
func testOrganizedCountIsThePreviewCount() {
    // contrôleur de démo « apercu » : organizedCount == somme des membres de presentFamilies
}
func testLiveFamiliesResetAtStart() {
    // après start() : liveFamilies vide
}
```

- [ ] **Étape 2 : famille définitive** — dans `classifyChannels`, les sons reconnus au nom sont signalés tout de suite ;
  l'ajustement d'après écoute (`keeps`, `isMelodicSynth`) devient `finalize(_ item: OrganizerItem, channel:
  ChannelInfo) -> OrganizerItem`, appelé son par son juste après son écoute (passé à `listen` par une fermeture),
  puis `classified(item.family)`. Résultat final inchangé (tests existants verts).
- [ ] **Étape 3 : écoute** — pastilles des familles (`liveFamilies`, ordre de `SoundFamily.order`) qui apparaissent
  en `scale + opacity` (vif) avec `.contentTransition(.numericText())` ; progression : capsule dessinée
  (`RoundedRectangle` de largeur `done/total`, doux) au lieu de `ProgressView` ; `OrganizerBadge` sans
  `symbolEffect` ; `WaitingPulse` retiré ; `working()` et l'attente : `SecondsCounter` (`TimelineView(.periodic(from:
  start, by: 1))`) au lieu de `ProgressView()`.
- [ ] **Étape 4 : aperçu** — `finishListening` : `OrganizerWindow.growForPreview { phase = .preview }` (la fenêtre prend
  la hauteur de l'aperçu en `Motion.appKitDuration`, puis la phase change) ; pastilles et icônes des cartes de
  famille liées par `matchedGeometryEffect(id: "fam.\(family)", in: ns)` ; ces éléments sans `morphIn` ni `pageMorph`.
- [ ] **Étape 5 : organiser et revenir** — bouton « Organiser » `matchedGeometryEffect(id: "action")` → pastille de
  `working(applyingText)` (même id), la fenêtre se resserre ensuite (`adapt`) ; `.applied(nil)` : pastille « ✓ N sons
  rangés » (`organizedCount`) pendant 1,2 s (`showingDone`), son `organiserDone`, puis l'écran de fin ;
  `.applied(error)` : écran d'erreur direct, sans son. « Revenir comme avant » → pastille « Retour en arrière… »,
  puis l'écran de fin actuel ; `.undone(nil)` : son `organiserDone`.
- [ ] **Étape 6 : CI** — écrans de démo existants (`organizer "ecoute"`, `"apercu"`, `"fini"`) + « lent » ; 8 captures
  `organiser-apercu-$i.png` et `organiser-fini-$i.png`.
- [ ] **Étape 7 : vérifier** — pousser ; CI : 0 échec ; images : pastilles → cartes sans saut, pastille de progression,
  aucune roue qui tourne.
- [ ] **Étape 8 : commit** « Organiser : pastilles des familles, progression et fin en morph, plus rien en boucle »

---

### Tâche 9 : Relecture finale, documentation, liste de contrôle

**Fichiers :**
- Créer : `docs/contexte/CONTROLE-ANIMATIONS.md`
- Modifier : `docs/contexte/HISTORIQUE.md`, `CLAUDE.md` (« Déjà fait »)

- [ ] **Étape 1 : relecture de toute la branche** par un relecteur indépendant (diff depuis `30f11fa`), avec la
  conception et ce plan ; corriger chaque constat bloquant, repousser, CI verte.
- [ ] **Étape 2 : mesure** — artefact `FLShortcuts-mac-mesure` : mémoire menu seul et fenêtre ouverte, avec et sans
  verre, comparée à ~14 Mo / ~54 Mo (+5 Mo au plus) ; processeur au repos 0 %.
- [ ] **Étape 3 : `CONTROLE-ANIMATIONS.md`** — une ligne par animation : quoi faire sur le Mac (ouvrir le menu, choisir
  « Macros… », changer de page, ouvrir une fiche, Échap, glisser un bloc, choisir un bloc, lancer l'Organiser sur un
  projet de test…), ce qu'on doit voir, ce qui serait un défaut ; plus les trois réglages à essayer (« Réduire les
  animations », « Effet Liquid Glass » coupé, `legacyMenu`).
- [ ] **Étape 4 : HISTORIQUE et CLAUDE.md** — ce qui a été fait, les limites des `List`, le repli `legacyMenu`, les
  sons, la commande `defaults` ; CLAUDE.md : une entrée « Animations » dans « Déjà fait ».
- [ ] **Étape 5 : commit** « Animations : relecture finale, documentation et liste de contrôle »
