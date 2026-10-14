// « Enregistrer des clics » : l'utilisateur clique une suite dans FL (menus, Options › Audio, boutons des fenêtres de
// réglages…), chaque clic devient un bloc de la macro. Comme « Montrer dans FL… », mais pour toute une suite.
// - Pendant l'enregistrement SEULEMENT : moniteur global des clics (gauche et droit), relevé des fenêtres de FL toutes
//   les 50 ms, petit panneau « ● Enregistrement – Terminer / Annuler » qui ne prend jamais le premier plan à FL.
//   120 s et 40 clics au plus. Rien d'autre n'est lu : ni l'écran, ni le clavier. Les clics restent en mémoire et ne
//   sont jamais journalisés.
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
        guard let item = find(pid: pid, titles: titles, openIfNeeded: true, stop: stop) else {
            if let why = stop() { return .cancelled(why) }
            MacroLog.shared.write("MENU", "menu bar item not found (\(titles.count) levels) · \(ms()) ms")
            return .failed("élément « \(titles.map { $0.displaySafe(max: 30) }.joined(separator: " › ")) » introuvable dans les menus de FL")
        }
        if let why = stop() { return .cancelled(why) }
        if bool(item, kAXEnabledAttribute as String) == false {
            closeMenus(pid: pid)
            return .failed("« \(titles.last?.displaySafe(max: 40) ?? "") » est grisé dans le menu de FL")
        }
        let err = AXUIElementPerformAction(item, kAXPressAction as CFString)
        MacroLog.shared.write("MENU", "menu bar item pressed (\(titles.count) levels): AX \(err.rawValue) · \(ms()) ms")
        guard err == .success else {
            closeMenus(pid: pid)
            return .failed("FL n'a pas répondu à son menu (Accessibilité \(err.rawValue))")
        }
        return .done
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
    let time: TimeInterval            // NSEvent.timestamp (même horloge que les relevés de fenêtres)
    let right: Bool
    /// Menu de la barre de macOS sous le clic (lu au moment du clic), sinon nil.
    let menu: MenuBarAX.Hit?
}

enum ClickSequenceCompiler {
    struct Result: Equatable {
        var blocks: [BlockBody]
        /// Clics ignorés : hors de FL, ou menu de la barre ouvert puis refermé sans choix.
        var ignored: Int
    }

    /// Chaque clic, d'après les fenêtres de FL juste avant lui (`history`, de la plus ancienne à la plus récente) :
    /// menu ou fenêtre de FL → clic retenu par rapport à eux ; élément d'un menu de la barre → « Menu de FL » (le clic
    /// qui a ouvert ce menu n'est pas gardé). Un clic qui referme un menu de la barre sans choix est ignoré : macOS
    /// l'avale, FL ne le reçoit pas.
    static func compile(_ clicks: [RecordedClick], history: [WinSnapshot]) -> Result {
        var out: [BlockBody] = []
        var ignored = 0
        var barOpen = false
        for c in clicks {
            switch c.menu {
            case .bar?:
                if barOpen { ignored += 1 }             // autre menu de la barre, ou le même refermé
                barOpen = true
                continue
            case .item(let path)?:
                barOpen = false
                out.append(.menuBar(titles: path))
                continue
            case nil:
                if barOpen {
                    barOpen = false
                    ignored += 2                        // le menu ouvert, puis ce clic qui l'a refermé
                    continue
                }
            }
            let before = history.last(where: { $0.time <= c.time }) ?? history.first
            let windows = (before?.fl ?? []).map { (layer: $0.layer, bounds: $0.bounds) }
            guard let target = MacroOutline.learnedTarget(at: c.point, windows: windows) else {
                ignored += 1
                continue
            }
            out.append(.click(target, button: c.right ? .right : .left))
        }
        if barOpen { ignored += 1 }
        return Result(blocks: out, ignored: ignored)
    }
}

// MARK: - Enregistreur

final class ClickSequenceRecorder: ObservableObject {
    static let shared = ClickSequenceRecorder()
    static let maxClicks = 40
    static let maxDuration: TimeInterval = 120

    @Published private(set) var active = false
    @Published private(set) var count = 0

    private var monitor: Any?
    private var timer: Timer?
    private var history: [WinSnapshot] = []
    private var clicks: [RecordedClick] = []
    private var started = Date()
    private var pid: Int32 = 0
    private var completion: ((ClickSequenceCompiler.Result) -> Void)?
    private weak var returnWindow: NSWindow?
    private var panel: RecordingPanel?

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
        clicks = []
        history = [WinSnapshot.take(pid: pid)]
        started = Date()
        count = 0
        active = true
        fl.activate(options: [])
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
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

    /// « Terminer » : les clics deviennent des blocs, retour dans le créateur.
    func finish() {
        guard active else { return }
        let result = ClickSequenceCompiler.compile(clicks, history: history)
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
            guard cfg.flPIDs.contains(cfg.frontmostPID) else { return }
        }
        guard active, event.cgEvent?.getIntegerValueField(.eventSourceUserData) != EventTap.mark else { return }
        let p = event.cgEvent?.location ?? FLWindows.cursor()
        // Menus de la barre de macOS : lus tout de suite (le menu se ferme au relâchement). Seulement hors des fenêtres
        // de FL (barre des menus) ou dans un menu : jamais pour un clic dans une fenêtre de FL.
        let before = history.last(where: { $0.time <= event.timestamp }) ?? history.last
        let inMenuOrOutside = before?.hit(p).map { $0.layer > 8 } ?? true
        let menu = inMenuOrOutside ? MenuBarAX.hit(at: p, pid: pid) : nil
        clicks.append(RecordedClick(point: p, time: event.timestamp, right: event.type == .rightMouseDown, menu: menu))
        count = clicks.count
        if clicks.count >= Self.maxClicks { finish() }
    }

    private func tick() {
        history.append(WinSnapshot.take(pid: pid))
        if history.count > 200 { history.removeFirst(history.count - 200) }
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
        clicks = []
        if active { active = false }
    }

    private func returnToCreator() {
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

    func hide() {
        panel.orderOut(nil)
        panel.contentView = nil
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
                Text("Enregistrement des clics").font(.system(size: 13, weight: .semibold))
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
        switch recorder.count {
        case 0: return "Clique dans FL, dans l'ordre."
        case 1: return "1 clic enregistré"
        default: return "\(recorder.count) clics enregistrés"
        }
    }
}
