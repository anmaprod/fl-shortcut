// « Enregistrer des clics » : l'utilisateur clique et tape une suite dans FL (menus, Options › Audio, boutons des
// fenêtres de réglages, flèches, Entrée, raccourcis…), chaque clic et chaque touche devient un bloc de la macro. Comme
// « Montrer dans FL… », mais pour toute une suite.
// - Pendant l'enregistrement SEULEMENT, et seulement quand FL est devant : moniteur global des clics (gauche et droit)
//   et des touches, relevé des fenêtres de FL toutes les 50 ms, petit panneau « ● Enregistrement – Terminer /
//   Annuler » qui ne prend jamais le premier plan à FL. 120 s et 80 clics ou touches au plus. Jamais l'écran. Clics et
//   touches restent en mémoire et ne sont jamais journalisés.
// - Touche dans un menu de FL ouvert : ↑ ↓ ← → Entrée Échap → « Dans le menu », lettre → « Lettres d'un menu » ;
//   ailleurs → « Touche » (raccourci compris) ; la même touche répétée → « × n ».
// - Chaque clic est retenu par rapport à ce qu'il a touché, comme « Montrer dans FL… » : un menu de FL (son coin),
//   une fenêtre de FL (son coin le plus proche et sa taille : fenêtre principale, réglages, boîte…). Un élément des
//   menus de FL dans la barre des menus de macOS (FL 2024.2 et plus) est retenu par ses titres (Accessibilité) et
//   rejoué sans clic : bloc « Menu de FL ».
// - Au rejeu, le clic attend la fenêtre ou le menu qu'ouvre le clic précédent (MacroEffectsMac.click).
import AppKit
import ApplicationServices
import SwiftUI

// MARK: - Menus de FL dans la barre des menus de macOS (Accessibilité, par titres)

enum MenuBarAX {
    /// Titre du menu dans la barre, puis jusqu'à 4 niveaux d'éléments.
    static let maxDepth = 5

    enum Hit: Equatable {
        /// Menu de la barre ouvert (« Options ») : l'élément choisi suit.
        case bar(String)
        /// Élément choisi, chemin complet depuis la barre : [« Options », « Audio settings »].
        case item([String])
    }

    enum Outcome: Equatable {
        case done
        case cancelled(String)
        case failed(String)
    }

    /// Élément des menus de la barre de FL sous `p`, au moment du clic (enregistrement). nil : autre chose (fenêtre,
    /// menu contextuel de FL, autre appli…). Délai court : FL peut être dans sa boucle de menu.
    static func hit(at p: CGPoint, pid: Int32) -> Hit? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)
        var found: AXUIElement?
        guard AXUIElementCopyElementAtPosition(system, Float(p.x), Float(p.y), &found) == .success, let el = found else { return nil }
        var owner: pid_t = 0
        guard AXUIElementGetPid(el, &owner) == .success, owner == pid, let kind = role(el) else { return nil }
        if kind == (kAXMenuBarItemRole as String) { return title(el).map { .bar($0) } }
        guard kind == (kAXMenuItemRole as String), let first = title(el) else { return nil }
        var path = [first]
        var current = el
        for _ in 0..<(maxDepth * 2 + 2) {
            guard let up = parent(current), let upRole = role(up) else { return nil }
            if upRole == (kAXMenuBarItemRole as String) {
                guard let t = title(up) else { return nil }
                path.insert(t, at: 0)
                return path.count <= maxDepth ? .item(path) : nil
            } else if upRole == (kAXMenuItemRole as String) {
                guard let t = title(up) else { return nil }
                path.insert(t, at: 0)
            } else if upRole != (kAXMenuRole as String) {
                return nil                              // menu contextuel : pas dans la barre (retenu par sa position)
            }
            current = up
        }
        return nil
    }

    /// Choisit l'élément `titles` (titre du menu de la barre, puis éléments) : AXPress sur l'élément, sans clic ni
    /// menu ouvert à l'écran. Un menu que FL ne remplit qu'à son ouverture est ouvert, relu une fois, puis refermé
    /// si l'élément n'y est pas.
    static func press(pid: Int32, titles: [String], stop: () -> String?) -> Outcome {
        guard titles.count >= 2 else { return .failed("chemin de menu incomplet") }
        let t0 = DispatchTime.now().uptimeNanoseconds
        func ms() -> Int { Int((DispatchTime.now().uptimeNanoseconds &- t0) / 1_000_000) }
        // Messages sans les titres : ils finissent dans le journal (un titre peut être un nom de projet récent).
        guard let item = find(pid: pid, titles: titles, openIfNeeded: true, stop: stop) else {
            if let why = stop() { return .cancelled(why) }
            MacroLog.shared.write("MENU", "menu bar item not found (\(titles.count) levels) · \(ms()) ms")
            return .failed("élément introuvable dans les menus de FL (renommé, ou FL dans une autre langue ? enregistre de nouveau tes clics)")
        }
        if let why = stop() { return .cancelled(why) }
        if bool(item, kAXEnabledAttribute as String) == false {
            closeMenus(pid: pid)
            return .failed("élément grisé dans le menu de FL")
        }
        let err = AXUIElementPerformAction(item, kAXPressAction as CFString)
        MacroLog.shared.write("MENU", "menu bar item pressed (\(titles.count) levels): AX \(err.rawValue) · \(ms()) ms")
        guard err == .success else {
            closeMenus(pid: pid)
            return .failed("FL n'a pas répondu à son menu (Accessibilité \(err.rawValue))")
        }
        return .done
    }

    /// Élément d'un menu de la barre de FL dont le titre contient l'un des `fragments` (sans casse ; premier niveau des
    /// menus seulement, bornés) : nil si introuvable (FL sans ses menus dans la barre de macOS). Délais courts.
    static func item(pid: Int32, titleContains fragments: [String]) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.1)
        guard let bar = element(app, kAXMenuBarAttribute as String) else { return nil }
        let wanted = fragments.map(normalized)
        for barItem in children(bar).prefix(14) {
            AXUIElementSetMessagingTimeout(barItem, 0.1)
            for menu in children(barItem) where role(menu) == (kAXMenuRole as String) {
                AXUIElementSetMessagingTimeout(menu, 0.1)
                for entry in children(menu).prefix(80) {
                    guard let t = title(entry).map(normalized), wanted.contains(where: { t.contains($0) }) else { continue }
                    return entry
                }
            }
        }
        return nil
    }

    /// Éléments d'un menu de la barre de FL (`path` : titre du menu, puis élément), avec ceux de ses sous-menus (un
    /// niveau : [sous-menu, élément]) : les plugins d'Add › Channel ou Effect pour « Cliquer sur… ». Lu sans rien
    /// ouvrir (FL n'est pas devant) : vide si FL n'a pas ses menus dans la barre de macOS, ou ne les remplit qu'ouverts.
    static func entries(pid: Int32, under path: [String], limit: Int = 400) -> [[String]] {
        guard let parent = find(pid: pid, titles: path, openIfNeeded: false, stop: { nil }),
              let menu = submenu(of: parent) else { return [] }
        var out: [[String]] = []
        func usable(_ el: AXUIElement) -> String? {
            guard let t = title(el), !t.contains("›"),
                  bool(el, kAXEnabledAttribute as String) != false else { return nil }
            return t
        }
        for entry in children(menu).prefix(limit) where out.count < limit {
            guard let t = usable(entry) else { continue }
            if let sub = submenu(of: entry) {
                for leaf in children(sub).prefix(limit) where out.count < limit && submenu(of: leaf) == nil {
                    if let l = usable(leaf) { out.append([t, l]) }
                }
            } else {
                out.append([t])
            }
        }
        return out
    }

    private static func submenu(of el: AXUIElement) -> AXUIElement? {
        children(el).first { role($0) == (kAXMenuRole as String) }
    }

    /// Cadre à l'écran (repère CoreGraphics) d'un menu de la barre ou d'un de ses éléments déjà affiché.
    static func frame(pid: Int32, titles: [String]) -> CGRect? {
        find(pid: pid, titles: titles, openIfNeeded: false, stop: { nil }).flatMap { AXProbe.frame($0) }
    }

    private static func find(pid: Int32, titles: [String], openIfNeeded: Bool, stop: () -> String?) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        guard !titles.isEmpty, let bar = element(app, kAXMenuBarAttribute as String) else { return nil }
        var current = bar
        var opened = false
        for (level, wanted) in titles.enumerated() {
            if stop() != nil { break }
            var next = child(of: current, titled: wanted, inMenu: level > 0)
            if next == nil, level > 0, openIfNeeded {
                AXUIElementPerformAction(current, kAXPressAction as CFString)
                opened = true
                Thread.sleep(forTimeInterval: 0.15)
                next = child(of: current, titled: wanted, inMenu: true)
            }
            guard let found = next else {
                if opened { closeMenus(pid: pid) }
                return nil
            }
            current = found
        }
        if stop() != nil {
            if opened { closeMenus(pid: pid) }
            return nil
        }
        return current
    }

    /// Ferme un menu de la barre resté ouvert (ouvert par nous pour lire son contenu).
    private static func closeMenus(pid: Int32) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.3)
        guard let bar = element(app, kAXMenuBarAttribute as String) else { return }
        for item in children(bar).prefix(20) {
            for menu in children(item) where role(menu) == (kAXMenuRole as String) {
                AXUIElementPerformAction(menu, kAXCancelAction as CFString)
            }
        }
    }

    /// Niveau 0 : les menus de la barre. Ensuite : les éléments du menu de `parent`.
    private static func child(of parent: AXUIElement, titled wanted: String, inMenu: Bool) -> AXUIElement? {
        let items: [AXUIElement]
        if inMenu {
            guard let menu = children(parent).first(where: { role($0) == (kAXMenuRole as String) }) else { return nil }
            items = children(menu)
        } else {
            items = children(parent)
        }
        let w = normalized(wanted)
        return items.prefix(150).first { title($0).map(normalized) == w }
    }

    private static func role(_ el: AXUIElement) -> String? { AXProbe.string(el, kAXRoleAttribute as String) }

    private static func title(_ el: AXUIElement) -> String? {
        guard let t = AXProbe.string(el, kAXTitleAttribute as String)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !t.isEmpty else { return nil }
        return String(t.prefix(80))
    }

    private static func element(_ el: AXUIElement, _ name: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success, let value,
              CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func parent(_ el: AXUIElement) -> AXUIElement? { element(el, kAXParentAttribute as String) }

    private static func children(_ el: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &value) == .success else { return [] }
        return value as? [AXUIElement] ?? []
    }

    private static func bool(_ el: AXUIElement, _ name: String) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, name as CFString, &value) == .success else { return nil }
        return value as? Bool
    }

    private static func normalized(_ s: String) -> String {
        var t = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        while t.hasSuffix("…") || t.hasSuffix(".") { t.removeLast() }
        return t
    }
}

// MARK: - Clics enregistrés → blocs (pur, testé)

struct RecordedClick: Equatable {
    let point: CGPoint                // coordonnées CG globales (origine en haut à gauche)
    let right: Bool
    /// Fenêtres de FL juste avant le clic, de l'avant vers l'arrière (relevé fait pendant l'enregistrement : un menu
    /// qui se ferme au clic y est encore).
    let windows: [WinInfo]
    /// Menu de la barre de macOS sous le clic (lu au moment du clic), sinon nil.
    let menu: MenuBarAX.Hit?
    /// Fenêtre de plugin sous le clic (Serum, Vital…) : son titre, lu au moment du clic (Accessibilité).
    var title: String? = nil
    /// Nom du bouton cliqué (« FILE », « Insert 1 »), lu dans la fenêtre de FL juste après le clic, et où tombait le
    /// clic par rapport au centre de ce nom.
    var named: NamedHit? = nil
    /// Bouton gauche relâché loin de l'appui : un glisser-déposer (où il est lâché, et les fenêtres de FL à ce moment).
    var release: RecordedRelease? = nil
}

/// Fin d'un glisser-déposer enregistré.
struct RecordedRelease: Equatable {
    let point: CGPoint
    let windows: [WinInfo]
}

/// Éléments des menus de FL (barre des menus de macOS) qui ont leur raccourci dans FL : enregistrés, ils deviennent
/// ce raccourci (instantané, sans ouvrir de menu). Titres de FL en anglais, comparés sans casse ni « … ».
enum MenuShortcuts {
    static func key(for path: [String], layout: KeyboardLayout) -> KeyCombo? {
        func cmd(_ letter: String, _ fallback: UInt16, shift: Bool = false) -> KeyCombo {
            KeyCombo(keyCode: KeyNames.commandKeyCode(for: letter, layout: layout) ?? fallback, command: true, shift: shift)
        }
        let p = path.map { t -> String in
            var s = t.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            while s.hasSuffix("…") || s.hasSuffix(".") { s.removeLast() }
            return s
        }
        switch p {
        case ["view", "playlist"]: return KeyCombo(keyCode: 96)                      // F5
        case ["view", "channel rack"]: return KeyCombo(keyCode: 97)                  // F6
        case ["view", "piano roll"]: return KeyCombo(keyCode: 98)                    // F7
        case ["view", "plugin picker"]: return KeyCombo(keyCode: 100)                // F8
        case ["view", "mixer"]: return KeyCombo(keyCode: 101)                        // F9
        case ["view", "browser"]: return KeyCombo(keyCode: 100, option: true)        // ⌥F8
        case ["options", "midi settings"]: return KeyCombo(keyCode: 109)             // F10
        case ["file", "open"]: return cmd("o", 31)
        case ["file", "save"]: return cmd("s", 1)
        case ["file", "save as"]: return cmd("s", 1, shift: true)
        case ["file", "save new version"]: return cmd("n", 45)
        case ["file", "export", "wave file"]: return cmd("r", 15)
        case ["file", "export", "mp3 file"]: return cmd("r", 15, shift: true)
        case ["file", "export", "midi file"]: return cmd("m", 46, shift: true)
        case ["edit", "undo"]: return cmd("z", 6)
        default: return nil
        }
    }
}

struct NamedHit: Equatable {
    let label: String
    let dx: Double
    let dy: Double
}

/// Touche tapée dans FL pendant l'enregistrement (flèches, Entrée, Échap, raccourcis, lettres d'un menu).
struct RecordedKey: Equatable {
    let combo: KeyCombo
    /// Caractère produit selon la disposition du clavier (affichage et lettres de menu) ; jamais journalisé.
    let char: String?
    /// Un menu de FL était ouvert (fenêtre de menu de FL au-dessus) au moment de la touche.
    let menuOpen: Bool
}

/// Ce que l'enregistrement retient, dans l'ordre : clics et touches.
enum RecordedInput: Equatable {
    case click(RecordedClick)
    case key(RecordedKey)
}

enum ClickSequenceCompiler {
    struct Result: Equatable {
        var blocks: [BlockBody]
        /// Clics ignorés : hors de FL, ou menu de la barre ouvert puis refermé sans choix.
        var ignored: Int
    }

    /// Plafonds des blocs (validation) : au-delà, un nouveau bloc commence.
    static let maxTimes = 20
    static let maxMenuLetters = 8

    /// Clic dans une fenêtre de FL sur un bouton qui porte un nom : retenu par ce nom (sa place reste le repli).
    static func named(_ target: ClickTarget, _ hit: NamedHit?) -> ClickTarget {
        guard let hit, case .flWindow(let corner, let dx, let dy, let size?, let title) = target else { return target }
        let spot = NamedSpot(label: hit.label, dx: hit.dx, dy: hit.dy, corner: corner, px: dx, py: dy, size: size, title: title)
        return spot.isValid ? .named(spot) : target
    }

    static func compile(_ clicks: [RecordedClick], layout: KeyboardLayout = SystemKeyboardLayout()) -> Result {
        compile(inputs: clicks.map(RecordedInput.click), layout: layout)
    }

    /// Une touche : dans un menu de FL ouvert, ↑ ↓ ← → Entrée Échap → « Dans le menu » et une lettre seule →
    /// « Lettres d'un menu » ; ailleurs → « Touche » (raccourci compris). La même touche répétée d'affilée devient
    /// « × n ». Renvoie le bloc précédent remplacé (répétition) ou le bloc à ajouter.
    static func key(_ k: RecordedKey, after previous: BlockBody?) -> (replace: BlockBody?, add: BlockBody?) {
        let c = k.combo
        let plain = !c.command && !c.control && !c.option
        if k.menuOpen, plain, !c.shift, let mk = MenuKey.allCases.first(where: { $0.keyCode == c.keyCode }) {
            if case .menuKey(let p, let n)? = previous, p == mk, n < maxTimes { return (.menuKey(mk, times: n + 1), nil) }
            return (nil, .menuKey(mk, times: 1))
        }
        if k.menuOpen, plain, let ch = k.char?.lowercased(), ch.count == 1, let letter = ch.first,
           MacroEffectsMac.letterKeyCodes[letter] != nil {
            if case .menuLetters(let l, let e)? = previous, l.count < maxMenuLetters {
                return (.menuLetters(l + [letter], finalEnter: e), nil)
            }
            return (nil, .menuLetters([letter], finalEnter: .never))
        }
        if case .key(let p, let n)? = previous, p.combo == c, n < maxTimes { return (.key(p, times: n + 1), nil) }
        return (nil, .key(KeyRef(c, char: k.char), times: 1))
    }

    /// Chaque clic, d'après les fenêtres de FL juste avant lui : menu ou fenêtre de FL → clic retenu par rapport à
    /// eux ; élément d'un menu de la barre → « Menu de FL » (le clic qui a ouvert ce menu n'est pas gardé). Un menu de
    /// la barre refermé sans choix (titre recliqué, ou clic ailleurs : macOS avale ce clic, FL ne le reçoit pas) est
    /// ignoré, ainsi que les touches tapées pendant qu'il est ouvert (on ne sait pas ce qu'elles y choisissent).
    /// Un élément de menu qui a son raccourci dans FL devient ce raccourci ; un bouton gauche relâché loin de l'appui,
    /// dans FL, devient un glisser-déposer.
    static func compile(inputs: [RecordedInput], layout: KeyboardLayout = SystemKeyboardLayout()) -> Result {
        var out: [BlockBody] = []
        var ignored = 0
        var openBar: String?                            // menu de la barre ouvert, rien choisi encore
        for input in inputs {
            let c: RecordedClick
            switch input {
            case .key(let k):
                if openBar != nil {
                    ignored += 1
                    continue
                }
                let (replace, add) = key(k, after: out.last)
                if let replace { out[out.count - 1] = replace }
                if let add { out.append(add) }
                continue
            case .click(let click):
                c = click
            }
            switch c.menu {
            case .bar(let title)?:
                if openBar == title {
                    openBar = nil                       // même titre recliqué : macOS referme le menu
                    ignored += 2
                } else {
                    if openBar != nil { ignored += 1 }  // passage à un autre menu de la barre
                    openBar = title
                }
                continue
            case .item(let path)?:
                openBar = nil
                if let combo = MenuShortcuts.key(for: path, layout: layout) {
                    out.append(.key(KeyRef(combo), times: 1))
                } else {
                    out.append(.menuBar(titles: path))
                }
                continue
            case nil:
                if openBar != nil {
                    openBar = nil
                    ignored += 2                        // le menu ouvert, puis ce clic qui l'a refermé
                    continue
                }
            }
            let windows = c.windows.map { (layer: $0.layer, bounds: $0.bounds) }
            guard let target = MacroOutline.learnedTarget(at: c.point, windows: windows, title: c.title) else {
                ignored += 1
                continue
            }
            if let release = c.release, !c.right,
               let to = MacroOutline.learnedTarget(at: release.point,
                                                   windows: release.windows.map { (layer: $0.layer, bounds: $0.bounds) },
                                                   title: nil) {
                out.append(.drag(from: Self.named(target, c.named), to: to))
                continue
            }
            out.append(.click(Self.named(target, c.named), button: c.right ? .right : .left))
        }
        if openBar != nil { ignored += 1 }
        return Result(blocks: out, ignored: ignored)
    }
}

// MARK: - Enregistreur

final class ClickSequenceRecorder: ObservableObject {
    static let shared = ClickSequenceRecorder()
    /// Clics et touches en tout.
    static let maxInputs = 80
    static let maxDuration: TimeInterval = 120
    /// Au-delà (points), un appui relâché ailleurs est un glisser-déposer, pas un clic.
    static let dragDistance: CGFloat = 8

    @Published private(set) var active = false
    @Published private(set) var count = 0
    @Published private(set) var keyCount = 0

    private var monitor: Any?
    private var timer: Timer?
    private var history: [WinSnapshot] = []
    private var inputs: [RecordedInput] = []
    private var started = Date()
    private var pid: Int32 = 0
    private var completion: ((ClickSequenceCompiler.Result) -> Void)?
    private weak var returnWindow: NSWindow?
    private var panel: RecordingPanel?
    /// Noms des boutons en cours de lecture (un par clic dans une fenêtre de FL) ; attendus à « Terminer ».
    private var naming = DispatchGroup()
    private var finishing = false
    /// Numéro de l'enregistrement : une fin attendue d'un enregistrement précédent n'arrête jamais le suivant.
    private var generation = 0

    /// Autorisation de lire l'écran demandée une fois, au premier enregistrement (les noms des boutons).
    static let screenAskedKey = "screenNamesAsked"

    private init() {}

    /// FL passe devant, l'enregistrement commence. `completion` : appelé par « Terminer » (jamais par « Annuler »).
    /// Faux : FL n'est pas ouvert.
    @discardableResult
    func start(pid: Int32, returnTo window: NSWindow?, completion: @escaping (ClickSequenceCompiler.Result) -> Void) -> Bool {
        stop()
        guard let fl = NSRunningApplication(processIdentifier: pid) else { return false }
        if ClickTeacher.shared.activeBlock != nil { ClickTeacher.shared.cancel(nil) }
        self.pid = pid
        self.completion = completion
        returnWindow = window
        inputs = []
        naming = DispatchGroup()
        finishing = false
        generation += 1
        // Boutons retenus par leur nom : il faut lire la fenêtre de FL au moment du clic. Demandé une seule fois ;
        // sans l'autorisation, les clics gardent leur place, comme avant.
        if MacroRunner.testFLPID == nil, ScreenLook.available, !ScreenLook.allowed,
           !UserDefaults.standard.bool(forKey: Self.screenAskedKey) {
            UserDefaults.standard.set(true, forKey: Self.screenAskedKey)
            ScreenLook.requestAccess()
        }
        history = [WinSnapshot.take(pid: pid)]
        started = Date()
        count = 0
        keyCount = 0
        active = true
        CreatorPresence.stepAside()
        fl.activate(options: [])
        // Touches aussi : flèches, Entrée, Échap, raccourcis, lettres des menus (seulement quand FL est devant ; les
        // raccourcis de FL Shortcuts, pris par le tap clavier, n'arrivent pas jusqu'ici).
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .leftMouseUp, .keyDown]) { [weak self] event in
            self?.record(event)
        }
        let t = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        let p = RecordingPanel(recorder: self)
        p.show()
        panel = p
        return true
    }

    /// « Terminer » : les clics deviennent des blocs (une fois lus les noms des derniers boutons, 2,5 s au plus),
    /// retour dans le créateur.
    func finish() {
        guard active, !finishing else { return }
        finishing = true
        if let m = monitor { NSEvent.removeMonitor(m) }            // plus rien d'enregistré
        monitor = nil
        let group = naming, current = generation
        DispatchQueue.global(qos: .userInitiated).async {
            _ = group.wait(timeout: .now() + 2.5)
            DispatchQueue.main.async { [weak self] in self?.complete(current) }
        }
    }

    private func complete(_ recording: Int) {
        guard active, finishing, recording == generation else { return }
        let result = ClickSequenceCompiler.compile(inputs: inputs)
        let done = completion
        stop()
        returnToCreator()
        done?(result)
    }

    /// « Annuler », ou créateur fermé (`returning` faux) : rien n'est ajouté.
    func cancel(returning: Bool = true) {
        guard active else { return }
        if !returning { returnWindow = nil }
        stop()
        returnToCreator()
    }

    private func record(_ event: NSEvent) {
        if let test = MacroRunner.testFLPID {
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == test else { return }
        } else {
            let cfg = EventTap.shared.currentConfig
            // FL devant, ou la fenêtre d'un plugin que FL fait tourner à part (pont des plugins Intel).
            guard cfg.flPIDs.contains(cfg.frontmostPID) || FLHelpers.isFLOrHelper(cfg.frontmostPID, fl: pid) else { return }
        }
        guard active, event.cgEvent?.getIntegerValueField(.eventSourceUserData) != EventTap.mark else { return }
        if event.type == .keyDown {
            recordKey(event)
            return
        }
        let p = event.cgEvent?.location ?? FLWindows.cursor()
        var barPending = false
        if case .bar? = lastClick?.menu { barPending = true }
        if event.type == .leftMouseUp {
            if barPending {
                // Menu de la barre choisi en glissant : appui sur son titre, relâché sur l'élément.
                guard let down = lastClick, abs(p.x - down.point.x) + abs(p.y - down.point.y) > 4,
                      let hit = MenuBarAX.hit(at: p, pid: pid), case .item = hit else { return }
                append(RecordedClick(point: p, right: false, windows: [], menu: hit))
                return
            }
            // Glisser-déposer : le bouton gauche relâché loin de l'appui. Le clic d'appui devient un glisser-déposer
            // (où il est lâché, et les fenêtres de FL à ce moment).
            guard let i = inputs.lastIndex(where: { if case .click = $0 { return true } else { return false } }),
                  case .click(var down) = inputs[i], !down.right, down.menu == nil, down.release == nil,
                  hypot(p.x - down.point.x, p.y - down.point.y) > Self.dragDistance else { return }
            let now = history.last(where: { $0.time <= event.timestamp }) ?? history.last ?? WinSnapshot.take(pid: pid)
            down.release = RecordedRelease(point: p, windows: now.fl)
            inputs[i] = .click(down)
            return
        }
        // Fenêtres de FL juste avant le clic, retenues tout de suite (un menu se ferme au clic). Menus de la barre de
        // macOS : lus aussi tout de suite, seulement hors des fenêtres de FL (barre des menus), dans un menu, ou quand
        // un menu de la barre est ouvert : jamais pour un clic dans une fenêtre de FL.
        let before = history.last(where: { $0.time <= event.timestamp }) ?? history.last ?? WinSnapshot.take(pid: pid)
        let inMenuOrOutside = barPending || (before.hit(p).map { $0.layer > 8 } ?? true)
        var menu = inMenuOrOutside ? MenuBarAX.hit(at: p, pid: pid) : nil
        // Dans la bande de la barre des menus, hors des fenêtres de FL, mais l'Accessibilité n'a pas répondu à temps
        // (le menu s'ouvrait) : c'est quand même l'ouverture d'un menu de la barre, jamais un clic dans FL.
        if menu == nil, before.hit(p) == nil, p.y - MacroEffectsMac.displayBounds(containing: p).minY <= 40 {
            menu = .bar("")
        }
        // Fenêtre de plugin : son titre la retrouvera au rejeu où qu'elle soit (jamais la fenêtre principale ni un menu).
        let title = menu == nil ? FLWindowAX.pluginTitle(at: p, before: before, fl: pid) : nil
        // Bouton qui porte un nom, dans une fenêtre de FL (pas un menu) : son nom est lu tout de suite (jamais pendant
        // les essais automatiques). Attendu avant de compiler : entré dans le groupe avant l'ajout (le 80ᵉ clic
        // termine l'enregistrement).
        let window = before.hit(p)
        let readName = menu == nil && MacroRunner.testFLPID == nil && MacroEffectsMac.canRead
            && (window.map { $0.number > 0 && (MacroEffectsMac.clickWindowLayers.contains($0.layer) || title != nil) } ?? false)
        let group = naming
        if readName { group.enter() }
        let index = inputs.count
        append(RecordedClick(point: p, right: event.type == .rightMouseDown, windows: before.fl, menu: menu, title: title))
        if readName, let window {
            TextLook.lookup(at: p, window: window) { [weak self] found in
                defer { group.leave() }
                guard let self, let found, index < self.inputs.count,
                      case .click(var click) = self.inputs[index], click.point == p else { return }
                // Lu sur l'appui (le relâché d'un glisser-déposer a pu s'ajouter depuis : il est gardé).
                click.named = NamedHit(label: found.label, dx: found.dx, dy: found.dy)
                self.inputs[index] = .click(click)
            }
        }
    }

    private var lastClick: RecordedClick? {
        for input in inputs.reversed() { if case .click(let c) = input { return c } }
        return nil
    }

    /// Touche (pas une touche modificatrice seule) : retenue avec l'état « menu de FL ouvert » juste avant elle.
    private func recordKey(_ event: NSEvent) {
        let code = event.keyCode
        guard !KeyCombo.modifierKeyCodes.contains(code) else { return }
        let flags = event.cgEvent?.flags ?? []
        // Menu ouvert juste avant la touche (Entrée ou Échap le referment aussitôt), ou maintenant (menu ouvert par
        // un clic il y a moins de 50 ms, pas encore dans les relevés).
        let isMenu: (WinInfo) -> Bool = { $0.layer > 8 && $0.isMenuLike }
        let before = history.last(where: { $0.time <= event.timestamp }) ?? history.last
        let menuOpen = (before?.fl.contains(where: isMenu) ?? false) || WinSnapshot.take(pid: pid).fl.contains(where: isMenu)
        let key = RecordedKey(combo: KeyCombo(keyCode: code, flags: flags), char: event.charactersIgnoringModifiers,
                              menuOpen: menuOpen)
        inputs.append(.key(key))
        keyCount += 1
        count = inputs.count
        if inputs.count >= Self.maxInputs { finish() }
    }

    private func append(_ click: RecordedClick) {
        inputs.append(.click(click))
        count = inputs.count
        if inputs.count >= Self.maxInputs { finish() }
    }

    /// Relevés de la dernière seconde seulement : chaque clic garde les siens dès qu'il est fait.
    private func tick() {
        history.append(WinSnapshot.take(pid: pid))
        if history.count > 20 { history.removeFirst(history.count - 20) }
        if Date().timeIntervalSince(started) > Self.maxDuration { finish() }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
        panel?.hide()
        panel = nil
        completion = nil
        history = []
        inputs = []
        finishing = false
        if active { active = false }
    }

    private func returnToCreator() {
        CreatorPresence.comeBack()
        if let window = returnWindow {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
        returnWindow = nil
    }
}

// MARK: - Panneau « ● Enregistrement »

/// Petit panneau en verre en haut à droite de l'écran, déplaçable : ne prend jamais le premier plan à FL, ses boutons
/// répondent au premier clic (qui n'est pas enregistré : c'est notre fenêtre).
private final class RecordingPanel {
    private let panel: NSPanel

    init(recorder: ClickSequenceRecorder) {
        let host = FirstClickHostingView(rootView: RecordingBar(recorder: recorder))
        host.frame.size = host.fittingSize
        panel = KeyablePanel(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = host
    }

    func show() {
        if let f = (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: f.maxX - panel.frame.width - 16, y: f.maxY - panel.frame.height - 12))
        }
        panel.orderFrontRegardless()
    }

    /// Contenu libéré au tour suivant : « Terminer » et « Annuler » appellent ceci depuis leur propre action.
    func hide() {
        let p = panel
        p.orderOut(nil)
        DispatchQueue.main.async { p.contentView = nil }
    }
}

private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

private final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private struct RecordingBar: View {
    @ObservedObject var recorder: ClickSequenceRecorder

    var body: some View {
        HStack(spacing: 12) {
            Circle().fill(Color.red).frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text("Enregistrement des clics et des touches").font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .frame(minWidth: 170, alignment: .leading)
            Button("Annuler") { recorder.cancel() }
                .secondaryButton()
            Button("Terminer") { recorder.finish() }
                .primaryButton()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassSurface(RoundedRectangle(cornerRadius: 20, style: .continuous), alwaysLive: true)
        .padding(6)
    }

    private var detail: String {
        let keys = recorder.keyCount
        let clicks = recorder.count - keys
        guard recorder.count > 0 else { return "Clique et tape dans FL (flèches, raccourcis…), dans l'ordre." }
        var parts: [String] = []
        if clicks > 0 { parts.append(clicks == 1 ? "1 clic" : "\(clicks) clics") }
        if keys > 0 { parts.append(keys == 1 ? "1 touche" : "\(keys) touches") }
        return parts.joined(separator: " · ") + (recorder.count == 1 ? " enregistré" : " enregistrés")
    }
}
