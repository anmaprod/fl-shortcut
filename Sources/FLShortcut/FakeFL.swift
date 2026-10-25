// FL Studio SIMULÉ pour l'essai de bout en bout de la macro sur la CI : `FLShortcut --fake-fl <état.json> [--o-highlights]`.
// Reproduit ce que la macro touche dans FL 2026 (relevé sur les vidéos de l'utilisateur) :
//  - Mixer : pistes (nom en haut, bouton d'armement en bas), panneau de droite « Mixer - Insert N » avec le
//    sélecteur d'entrée « (none) » ; touche R = REC (inverse l'état) ;
//  - menu de piste au clic droit : fenêtre à part, décalée pour tenir à l'écran, mêmes éléments dans le même ordre,
//    lettres soulignées (F de File, S de Select…), sous-menus dans leurs propres fenêtres, flèches, Entrée, Échap,
//    survol ; File › Open mixer track state ouvre une vraie boîte « Open » (NSOpenPanel) ;
//  - liste des entrées : « (none) », « In 1 - In 2 », « In 1 », « In 2 » ; choisir une entrée arme la piste (comme FL).
// `--o-highlights` : « O » ne fait que surligner Open mixer track state (il faut Entrée), l'autre comportement possible.
// L'état (preset chargé, pistes armées, REC, entrée, actions déclenchées, positions utiles) est écrit en JSON à chaque
// changement : le pilote de l'essai le relit. Toute action inattendue (Delete, Solo…) y est notée.
import AppKit

enum FakeFL {
    private static var controller: FakeFLController?

    static func runIfRequested() {
        guard let i = CommandLine.arguments.firstIndex(of: "--fake-fl") else { return }
        let path = CommandLine.arguments.dropFirst(i + 1).first ?? (NSTemporaryDirectory() + "fakefl.json")
        guard path.hasSuffix(".json") else { exit(2) }            // son état seulement, jamais un autre fichier écrasé
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        let c = FakeFLController(statePath: path, oHighlights: CommandLine.arguments.contains("--o-highlights"))
        controller = c
        c.start()
        app.run()
        exit(0)
    }
}

final class FakeMenuItem {
    let title: String
    let mnemonic: Character?
    var enabled = true
    var isHeader = false
    var isSeparator = false
    /// La lettre ouvre/active l'élément ; faux : elle le surligne seulement (Entrée nécessaire).
    var mnemonicActivates = true
    var submenu: [FakeMenuItem]?
    var action: (() -> Void)?

    init(_ title: String, _ mnemonic: Character? = nil, enabled: Bool = true, submenu: [FakeMenuItem]? = nil,
         action: (() -> Void)? = nil) {
        self.title = title
        self.mnemonic = mnemonic
        self.enabled = enabled
        self.submenu = submenu
        self.action = action
    }

    static func header(_ t: String) -> FakeMenuItem { let i = FakeMenuItem(t, enabled: false); i.isHeader = true; return i }
    static var separator: FakeMenuItem { let i = FakeMenuItem("-", enabled: false); i.isSeparator = true; return i }

    var selectable: Bool { enabled && !isHeader && !isSeparator }
    var height: CGFloat { isSeparator ? 7 : 20 }
}

/// Un niveau de menu ouvert : sa fenêtre, ses éléments, l'élément surligné.
final class FakeMenuLevel {
    let items: [FakeMenuItem]
    let panel: NSPanel
    let view: FakeMenuView
    var highlighted: Int?

    init(items: [FakeMenuItem], panel: NSPanel, view: FakeMenuView) {
        self.items = items
        self.panel = panel
        self.view = view
    }

    func rowRect(_ index: Int) -> NSRect {            // coordonnées de la vue (retournée : y vers le bas)
        var y: CGFloat = 4
        for i in 0..<index { y += items[i].height }
        return NSRect(x: 0, y: y, width: view.bounds.width, height: items[index].height)
    }

    func index(at p: NSPoint) -> Int? {
        var y: CGFloat = 4
        for (i, item) in items.enumerated() {
            if p.y >= y && p.y < y + item.height { return i }
            y += item.height
        }
        return nil
    }

    static func contentHeight(_ items: [FakeMenuItem]) -> CGFloat { items.reduce(8) { $0 + $1.height } }
}

final class FakeFLController {
    let statePath: String
    var oHighlights: Bool

    var window: NSWindow!
    var mixer: FakeMixerView!
    var levels: [FakeMenuLevel] = []
    var selected = 1
    var armed: Set<Int> = []
    var rec = false
    var input = "(none)"
    var preset: String?
    /// Piste qui a reçu le preset (dépôt sur sa tranche, ou boîte « Open » sur la piste sélectionnée) ; 0 : aucune.
    var presetTrack = 0
    var events: [String] = []
    var inputItems: [String: CGPoint] = [:]
    /// Centre de chaque élément des menus ouverts (« item:<titre> » dans l'état) : le pilote y clique comme l'utilisateur.
    var itemPoints: [String: CGPoint] = [:]
    var monitors: [Any] = []
    // Options › Audio settings : fenêtre à part, au niveau des boîtes de dialogue (8), carte son, case, Fermer.
    var settingsWindow: NSWindow?
    var settingsView: FakeSettingsView?
    var device = "Built-in"
    var autoClose = false
    let nativeMenuTarget = FakeNativeMenuTarget()

    init(statePath: String, oHighlights: Bool) {
        self.statePath = statePath
        self.oHighlights = oHighlights
    }

    func start() {
        window = NSWindow(contentRect: NSRect(x: 60, y: 60, width: 940, height: 620),
                          styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.title = "FL Studio (simulé pour l'essai)"
        mixer = FakeMixerView(frame: NSRect(x: 0, y: 0, width: 940, height: 620))
        mixer.controller = self
        window.contentView = mixer
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        installMainMenu()
        NSApp.activate(ignoringOtherApps: true)

        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] e in
            guard let self else { return e }
            return self.handleKey(e) ? nil : e
        } as Any)
        monitors.append(NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] e in
            guard let self, !self.levels.isEmpty else { return e }
            // Clic hors des menus : ils se ferment, le clic est avalé (comme FL).
            if let w = e.window, self.levels.contains(where: { $0.panel === w }) { return e }
            self.closeAll()
            return nil
        } as Any)
        let dnc = DistributedNotificationCenter.default()
        monitors.append(dnc.addObserver(forName: Notification.Name("app.flshortcut.fakefl.reset"), object: nil, queue: .main) { [weak self] _ in
            self?.reset()
        })
        monitors.append(dnc.addObserver(forName: Notification.Name("app.flshortcut.fakefl.mode"), object: nil, queue: .main) { [weak self] n in
            self?.oHighlights = (n.object as? String) == "highlight"
            self?.writeState()
        })
        writeState()
    }

    func reset() {
        closeAll()
        settingsWindow?.orderOut(nil)
        settingsWindow = nil
        settingsView = nil
        device = "Built-in"
        autoClose = false
        armed = []
        rec = false
        input = "(none)"
        preset = nil
        presetTrack = 0
        events = []
        mixer.needsDisplay = true
        writeState()
    }

    func note(_ event: String) {
        events.append(event)
        mixer.needsDisplay = true
        writeState()
    }

    // MARK: État partagé avec le pilote

    /// AppKit (origine en bas à gauche) → CoreGraphics (origine en haut à gauche, écran principal).
    static func cg(_ p: NSPoint) -> CGPoint {
        let h = NSScreen.screens.first?.frame.height ?? 900
        return CGPoint(x: p.x, y: h - p.y)
    }

    func screenPoint(inMixer p: NSPoint) -> CGPoint {
        let inWindow = mixer.convert(p, to: nil)
        return Self.cg(window.convertPoint(toScreen: inWindow))
    }

    func writeState() {
        func pt(_ p: CGPoint) -> [Double] { [Double(p.x), Double(p.y)] }
        var geometry: [String: [Double]] = [:]
        for t in 1...FakeMixerView.trackCount {
            let r = mixer.nameRect(t)
            geometry["track\(t)"] = pt(screenPoint(inMixer: NSPoint(x: r.midX, y: r.midY)))
            let a = mixer.armRect(t)
            geometry["arm\(t)"] = pt(screenPoint(inMixer: NSPoint(x: a.midX, y: a.midY)))
        }
        let s = mixer.selectorRect
        geometry["selector"] = pt(screenPoint(inMixer: NSPoint(x: s.midX, y: s.midY)))
        let e = mixer.emptyPoint
        geometry["empty"] = pt(screenPoint(inMixer: e))
        for (k, v) in inputItems { geometry["input:\(k)"] = pt(v) }
        let o = mixer.optionsRect
        geometry["options"] = pt(screenPoint(inMixer: NSPoint(x: o.midX, y: o.midY)))
        for (k, v) in itemPoints { geometry["item:\(k)"] = pt(v) }
        if let w = settingsWindow, let v = settingsView {
            func center(_ r: NSRect) -> CGPoint { Self.cg(w.convertPoint(toScreen: v.convert(NSPoint(x: r.midX, y: r.midY), to: nil))) }
            geometry["settings:device"] = pt(center(v.deviceRect))
            geometry["settings:toggle"] = pt(center(v.toggleRect))
            geometry["settings:close"] = pt(center(v.closeRect))
        }
        let dict: [String: Any] = [
            "pid": Int(getpid()), "selected": selected, "armed": armed.sorted(), "rec": rec, "input": input,
            "preset": preset ?? "", "presetTrack": presetTrack, "events": events, "menusOpen": levels.count,
            "oHighlights": oHighlights,
            "settingsOpen": settingsWindow != nil, "device": device, "autoClose": autoClose,
            "geometry": geometry,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: [.sortedKeys]) {
            try? data.write(to: URL(fileURLWithPath: statePath), options: .atomic)
        }
    }

    // MARK: Clavier

    /// Vrai si la touche est prise (menu ouvert, ou R).
    func handleKey(_ e: NSEvent) -> Bool {
        if let top = levels.last {
            switch e.keyCode {
            case 125: move(top, +1); return true
            case 126: move(top, -1); return true
            case 124:
                if let h = top.highlighted, top.items[h].submenu != nil { openSubmenu(from: top, index: h) }
                return true
            case 123:
                if levels.count > 1 { closeTop() }
                return true
            case 36, 76:
                if let h = top.highlighted { activate(top, h) }
                return true
            case 53:
                if levels.count > 1 { closeTop() } else { closeAll() }
                return true
            default:
                guard let c = e.charactersIgnoringModifiers?.lowercased().first else { return true }
                let hits = top.items.indices.filter { top.items[$0].selectable && top.items[$0].mnemonic == c }
                if hits.count == 1, let h = hits.first {
                    top.highlighted = h
                    top.view.needsDisplay = true
                    if top.items[h].mnemonicActivates { activate(top, h) }
                } else if let next = hits.first(where: { $0 > (top.highlighted ?? -1) }) ?? hits.first {
                    top.highlighted = next                  // lettre partagée : surligne seulement
                    top.view.needsDisplay = true
                }
                return true
            }
        }
        // ⌘S : « enregistrer le projet », un raccourci de FL avec une touche modificatrice.
        if NSApp.modalWindow == nil, e.keyCode == 1,
           e.modifierFlags.intersection([.command, .control, .option, .shift]) == .command {
            note("save project")
            return true
        }
        // R : dans la fenêtre du Mixer (ou sans fenêtre clé, juste après la fermeture des réglages), jamais pendant la
        // boîte « Open » (on y tape un chemin) ni dans les réglages.
        if NSApp.modalWindow == nil, e.window === window || e.window == nil,
           e.modifierFlags.intersection([.command, .control, .option]).isEmpty,
           e.keyCode == 15 || e.charactersIgnoringModifiers?.lowercased() == "r" {
            rec.toggle()
            note(rec ? "rec on" : "rec off")
            return true
        }
        return false
    }

    func move(_ level: FakeMenuLevel, _ step: Int) {
        let n = level.items.count
        var i = level.highlighted ?? (step > 0 ? -1 : n)
        for _ in 0..<n {
            i = (i + step + n) % n
            if level.items[i].selectable { break }
        }
        level.highlighted = i
        level.view.needsDisplay = true
    }

    func activate(_ level: FakeMenuLevel, _ index: Int) {
        let item = level.items[index]
        guard item.selectable else { return }
        if item.submenu != nil {
            openSubmenu(from: level, index: index)
            return
        }
        closeAll()
        if let action = item.action {
            DispatchQueue.main.async { action() }
        } else {
            note("WRONG: \(item.title)")
        }
    }

    // MARK: Menus

    func openMenu(_ items: [FakeMenuItem], topLeft: NSPoint, width: CGFloat = 300) -> FakeMenuLevel {
        let h = FakeMenuLevel.contentHeight(items)
        var frame = NSRect(x: topLeft.x, y: topLeft.y - h, width: width, height: h)
        // Comme FL : le menu est décalé pour tenir à l'écran (il peut alors recouvrir le pointeur).
        if let vf = (NSScreen.screens.first { $0.frame.contains(topLeft) } ?? NSScreen.main)?.visibleFrame {
            if frame.minY < vf.minY { frame.origin.y = vf.minY }
            if frame.maxY > vf.maxY { frame.origin.y = vf.maxY - h }
            if frame.maxX > vf.maxX { frame.origin.x = vf.maxX - width }
        }
        let view = FakeMenuView(frame: NSRect(origin: .zero, size: frame.size))
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.acceptsMouseMovedEvents = true
        panel.contentView = view
        let level = FakeMenuLevel(items: items, panel: panel, view: view)
        view.level = level
        view.controller = self
        levels.append(level)
        panel.orderFrontRegardless()
        for (i, item) in items.enumerated() where item.selectable {
            let r = level.rowRect(i)
            itemPoints[item.title] = Self.cg(panel.convertPoint(toScreen: NSPoint(x: r.midX, y: view.bounds.height - r.midY)))
        }
        writeState()
        return level
    }

    func openSubmenu(from level: FakeMenuLevel, index: Int) {
        guard let sub = level.items[index].submenu else { return }
        if let i = levels.firstIndex(where: { $0 === level }), i + 1 < levels.count {
            while levels.count > i + 1 { closeTop() }       // un autre sous-menu était ouvert
        }
        level.highlighted = index
        level.view.needsDisplay = true
        let row = level.rowRect(index)
        let top = level.panel.frame.maxY - row.minY + 4
        let child = openMenu(sub, topLeft: NSPoint(x: level.panel.frame.maxX - 2, y: top), width: 260)
        move(child, +1)                                      // ouvert au clavier : premier élément surligné
    }

    func closeTop() {
        guard let top = levels.popLast() else { return }
        top.panel.orderOut(nil)
        if levels.isEmpty {
            inputItems = [:]
            itemPoints = [:]
        }
        writeState()
    }

    func closeAll() {
        while !levels.isEmpty { closeTop() }
    }

    // MARK: Actions de FL

    func openTrackMenu(track: Int, at screen: NSPoint) {
        closeAll()
        selected = track
        mixer.needsDisplay = true
        let open = FakeMenuItem("Open mixer track state…", "o") { [weak self] in self?.openState() }
        open.mnemonicActivates = !oHighlights
        let file: [FakeMenuItem] = [
            open,
            FakeMenuItem("Save mixer track state as…", "s"),
            FakeMenuItem("Browse states", "b"),
        ]
        let select: [FakeMenuItem] = [FakeMenuItem("All", "a"), FakeMenuItem("None", "n"), FakeMenuItem("Toggle", "t")]
        let items: [FakeMenuItem] = [
            .header("Mixer track (Insert \(track))"),
            FakeMenuItem("Rename, color and icon…", "r"),
            FakeMenuItem("Change color…"),
            FakeMenuItem("Random color"),
            FakeMenuItem("Gradient color…", enabled: false),
            FakeMenuItem("Change icon…"),
            FakeMenuItem("Assign to new Audio track(s)", "a"),
            FakeMenuItem("Unassign from Audio track(s)", "u", enabled: false),
            .separator,
            FakeMenuItem("File", "f", submenu: file),
            FakeMenuItem("Open audio editor"),
            FakeMenuItem("Open audio editor and record"),
            .separator,
            FakeMenuItem("Reset selected track(s) to default"),
            .header("Routing"),
            FakeMenuItem("Channel routing", "c", submenu: [FakeMenuItem("Route to this track only")]),
            FakeMenuItem("Track routing", "t", enabled: false),
            FakeMenuItem("Select", "s", submenu: select),
            FakeMenuItem("Reset selected track(s) routing"),
            FakeMenuItem("Unroute tracks routed to the selected track(s)"),
            .separator,
            FakeMenuItem("Solo selected track(s)"),
            FakeMenuItem("Alt solo selected track(s)"),
            FakeMenuItem("Arm selected track(s)") { [weak self] in
                guard let self else { return }
                self.armed.insert(self.selected)
                self.note("arm \(self.selected)")
            },
            FakeMenuItem("Disarm selected track(s)"),
            .separator,
            FakeMenuItem("Compensate for master latency", enabled: false),
            .header("Group"),
            FakeMenuItem("Separator", "p"),
            FakeMenuItem("Create group…"),
            FakeMenuItem("Auto color group", enabled: false),
            .header("Layout"),
            FakeMenuItem("Dock to", submenu: [FakeMenuItem("Left"), FakeMenuItem("Middle"), FakeMenuItem("Right")]),
            FakeMenuItem("Move left"),
            FakeMenuItem("Move right"),
            .separator,
            FakeMenuItem("Delete", "d"),
            FakeMenuItem("Insert one"),
            FakeMenuItem("Insert multiple…"),
            FakeMenuItem("Insert from state", submenu: [FakeMenuItem("Browse…")]),
        ]
        _ = openMenu(items, topLeft: screen)
    }

    func openState() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Open mixer track state"
        if panel.runModal() == .OK, let url = panel.url {
            preset = url.resolvingSymlinksInPath().path
            presetTrack = selected
            note("open \(url.lastPathComponent)")
        } else {
            note("open cancelled")
        }
    }

    /// Fichier déposé sur une tranche (comme FL : l'état est chargé sur CETTE piste, sélectionnée ou non).
    func dropPreset(_ url: URL, on track: Int) {
        preset = url.resolvingSymlinksInPath().path
        presetTrack = track
        note("drop \(url.lastPathComponent) on \(track)")
    }

    func openInputList() {
        closeAll()
        let names = ["(none)", "In 1 - In 2", "In 1", "In 2"]
        let items = names.map { name in
            FakeMenuItem(name) { [weak self] in
                guard let self else { return }
                self.input = name
                if name != "(none)" { self.armed.insert(self.selected) }      // comme FL : l'entrée arme la piste
                self.note("input \(name)")
            }
        }
        let s = mixer.selectorRect
        let below = window.convertPoint(toScreen: mixer.convert(NSPoint(x: s.minX, y: s.maxY), to: nil))
        let level = openMenu(items, topLeft: below, width: s.width)
        inputItems = [:]
        for (i, name) in names.enumerated() {
            let r = level.rowRect(i)
            let inPanel = NSPoint(x: r.midX, y: level.view.bounds.height - r.midY)
            inputItems[name] = Self.cg(level.panel.convertPoint(toScreen: inPanel))
        }
        writeState()
    }

    // MARK: Options › Audio settings

    /// Menus de FL dans la barre des menus de macOS (FL 2024.2 et plus), lisibles par l'Accessibilité.
    func installMainMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        appItem.submenu = NSMenu(title: "FL Studio")
        main.addItem(appItem)
        let options = NSMenu(title: "Options")
        for (i, title) in ["MIDI settings", "Audio settings", "General settings"].enumerated() {
            let item = NSMenuItem(title: title, action: #selector(FakeNativeMenuTarget.run(_:)), keyEquivalent: "")
            item.target = nativeMenuTarget
            item.tag = i
            options.addItem(item)
        }
        let optionsItem = NSMenuItem(title: "Options", action: nil, keyEquivalent: "")
        optionsItem.submenu = options
        main.addItem(optionsItem)
        nativeMenuTarget.actions = [
            0: { [weak self] in self?.note("WRONG: MIDI settings") },
            1: { [weak self] in self?.openSettings() },
            2: { [weak self] in self?.note("WRONG: General settings") },
        ]
        NSApp.mainMenu = main
    }

    /// OPTIONS de la barre d'outils, dans la fenêtre de FL : menu maison, comme les autres.
    func openOptionsMenu() {
        closeAll()
        let items: [FakeMenuItem] = [
            FakeMenuItem("MIDI settings"),
            FakeMenuItem("Audio settings") { [weak self] in self?.openSettings() },
            FakeMenuItem("General settings"),
            .separator,
            FakeMenuItem("Project general settings"),
        ]
        let r = mixer.optionsRect
        let below = window.convertPoint(toScreen: mixer.convert(NSPoint(x: r.minX, y: r.maxY), to: nil))
        _ = openMenu(items, topLeft: below, width: 220)
    }

    func openSettings() {
        if let w = settingsWindow {
            w.makeKeyAndOrderFront(nil)
            return
        }
        let w = NSWindow(contentRect: NSRect(x: 300, y: 160, width: 520, height: 400),
                         styleMask: [.titled, .closable], backing: .buffered, defer: false)
        w.title = "Settings - Audio"
        w.level = .modalPanel
        w.isReleasedWhenClosed = false
        let v = FakeSettingsView(frame: NSRect(x: 0, y: 0, width: 520, height: 400))
        v.controller = self
        w.contentView = v
        settingsWindow = w
        settingsView = v
        w.makeKeyAndOrderFront(nil)
        note("settings open")
    }

    func closeSettings() {
        closeAll()
        settingsWindow?.orderOut(nil)
        settingsWindow = nil
        settingsView = nil
        window.makeKeyAndOrderFront(nil)          // comme FL : la fenêtre principale reprend le clavier
        note("settings close")
    }

    func openDeviceList() {
        closeAll()
        guard let w = settingsWindow, let v = settingsView else { return }
        let items = ["Built-in", "Interface USB", "Aggregate"].map { name in
            FakeMenuItem(name) { [weak self] in
                guard let self else { return }
                self.device = name
                self.settingsView?.needsDisplay = true
                self.note("device \(name)")
            }
        }
        let r = v.deviceRect
        let below = w.convertPoint(toScreen: v.convert(NSPoint(x: r.minX, y: r.maxY), to: nil))
        _ = openMenu(items, topLeft: below, width: r.width)
    }

    func toggleAutoClose() {
        autoClose.toggle()
        settingsView?.needsDisplay = true
        note(autoClose ? "auto close on" : "auto close off")
    }
}

/// Cible des éléments du menu Options de la barre des menus.
final class FakeNativeMenuTarget: NSObject {
    var actions: [Int: () -> Void] = [:]

    @objc func run(_ sender: NSMenuItem) {
        let action = actions[sender.tag]
        DispatchQueue.main.async { action?() }        // après la fermeture du menu, comme une vraie appli
    }
}

/// Fenêtre des réglages audio simulée : carte son (liste déroulante maison), case « Auto close device », Fermer.
final class FakeSettingsView: NSView {
    weak var controller: FakeFLController?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var deviceRect: NSRect { NSRect(x: 20, y: 60, width: 260, height: 24) }
    var toggleRect: NSRect { NSRect(x: 20, y: 110, width: 22, height: 22) }
    var closeRect: NSRect { NSRect(x: bounds.width - 110, y: bounds.height - 46, width: 90, height: 26) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.17, alpha: 1).setFill()
        bounds.fill()
        guard let c = controller else { return }
        let text: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 12)]
        ("Audio settings" as NSString).draw(at: NSPoint(x: 20, y: 20),
                                            withAttributes: [.foregroundColor: NSColor.white, .font: NSFont.boldSystemFont(ofSize: 14)])
        NSColor(white: 0.25, alpha: 1).setFill()
        deviceRect.fill()
        ("Device : \(c.device)" as NSString).draw(at: NSPoint(x: deviceRect.minX + 8, y: deviceRect.minY + 4), withAttributes: text)
        (c.autoClose ? NSColor.systemOrange : NSColor(white: 0.4, alpha: 1)).setFill()
        toggleRect.fill()
        ("Auto close device" as NSString).draw(at: NSPoint(x: toggleRect.maxX + 8, y: toggleRect.minY + 3), withAttributes: text)
        NSColor(white: 0.3, alpha: 1).setFill()
        closeRect.fill()
        ("Close" as NSString).draw(at: NSPoint(x: closeRect.minX + 28, y: closeRect.minY + 5), withAttributes: text)
    }

    override func mouseDown(with event: NSEvent) {
        guard let c = controller else { return }
        let p = convert(event.locationInWindow, from: nil)
        if deviceRect.contains(p) {
            c.openDeviceList()
        } else if toggleRect.contains(p) {
            c.toggleAutoClose()
        } else if closeRect.contains(p) {
            c.closeSettings()
        }
    }
}

/// Vue d'un niveau de menu (retournée : y vers le bas, comme les lignes).
final class FakeMenuView: NSView {
    weak var level: FakeMenuLevel?
    weak var controller: FakeFLController?
    private var hoverWork: DispatchWorkItem?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                       owner: self, userInfo: nil))
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.18, alpha: 1).setFill()
        bounds.fill()
        guard let level else { return }
        for (i, item) in level.items.enumerated() {
            let r = level.rowRect(i)
            if item.isSeparator {
                NSColor(white: 0.35, alpha: 1).setFill()
                NSRect(x: 6, y: r.midY, width: r.width - 12, height: 1).fill()
                continue
            }
            if item.isHeader {
                NSColor(white: 0.3, alpha: 1).setFill()
                r.fill()
            } else if level.highlighted == i {
                NSColor(calibratedRed: 0.3, green: 0.45, blue: 0.7, alpha: 1).setFill()
                r.fill()
            }
            let color: NSColor = item.enabled ? .white : NSColor(white: 0.5, alpha: 1)
            (item.title as NSString).draw(at: NSPoint(x: item.isHeader ? 6 : 22, y: r.minY + 3),
                                          withAttributes: [.foregroundColor: color, .font: NSFont.systemFont(ofSize: 12)])
            if item.submenu != nil {
                ("›" as NSString).draw(at: NSPoint(x: r.maxX - 16, y: r.minY + 2),
                                       withAttributes: [.foregroundColor: color, .font: NSFont.systemFont(ofSize: 12)])
            }
        }
    }

    override func mouseMoved(with event: NSEvent) {
        guard let level, let controller else { return }
        let p = convert(event.locationInWindow, from: nil)
        guard let i = level.index(at: p), level.items[i].selectable, level.highlighted != i else { return }
        level.highlighted = i
        needsDisplay = true
        hoverWork?.cancel()
        if level.items[i].submenu != nil {
            // Survol d'un sous-menu : il s'ouvre après un court instant (comme FL).
            let work = DispatchWorkItem { [weak level, weak controller] in
                guard let level, let controller, level.highlighted == i else { return }
                controller.openSubmenu(from: level, index: i)
            }
            hoverWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }

    override func mouseDown(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard let level, let controller else { return }
        let p = convert(event.locationInWindow, from: nil)
        if let i = level.index(at: p) { controller.activate(level, i) }
    }
}

/// Le Mixer simulé : pistes, armement, panneau de droite et sélecteur d'entrée.
final class FakeMixerView: NSView {
    static let trackCount = 8
    weak var controller: FakeFLController?

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        registerForDraggedTypes([.fileURL])
    }

    func track(at p: NSPoint) -> Int? { (1...Self.trackCount).first { stripRect($0).contains(p) } }

    // Dépôt d'un fichier n'importe où sur une tranche (comme FL).
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { dropOperation(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { dropOperation(sender) }

    private func dropOperation(_ sender: NSDraggingInfo) -> NSDragOperation {
        track(at: convert(sender.draggingLocation, from: nil)) != nil ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let c = controller, let t = track(at: convert(sender.draggingLocation, from: nil)),
              let url = (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self],
                                                               options: [.urlReadingFileURLsOnly: true]) as? [URL])?.first
        else { return false }
        c.dropPreset(url, on: t)
        return true
    }

    func stripRect(_ t: Int) -> NSRect { NSRect(x: 20 + CGFloat(t - 1) * 78, y: 70, width: 70, height: 470) }
    func nameRect(_ t: Int) -> NSRect { let s = stripRect(t); return NSRect(x: s.minX, y: s.minY, width: s.width, height: 40) }
    func armRect(_ t: Int) -> NSRect { let s = stripRect(t); return NSRect(x: s.midX - 11, y: s.maxY - 34, width: 22, height: 22) }
    var selectorRect: NSRect { NSRect(x: bounds.width - 250, y: 46, width: 230, height: 24) }
    /// OPTIONS de la barre d'outils de FL (menu dans la fenêtre).
    var optionsRect: NSRect { NSRect(x: 140, y: 14, width: 84, height: 24) }
    var emptyPoint: NSPoint { NSPoint(x: bounds.width - 140, y: bounds.height - 30) }

    override func draw(_ dirtyRect: NSRect) {
        NSColor(white: 0.15, alpha: 1).setFill()
        bounds.fill()
        guard let c = controller else { return }
        let text: [NSAttributedString.Key: Any] = [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 12)]
        ((c.rec ? "● REC" : "○ rec") as NSString).draw(at: NSPoint(x: 20, y: 20),
            withAttributes: [.foregroundColor: c.rec ? NSColor.systemRed : NSColor.gray, .font: NSFont.boldSystemFont(ofSize: 14)])
        for t in 1...Self.trackCount {
            let s = stripRect(t)
            (t == c.selected ? NSColor(white: 0.32, alpha: 1) : NSColor(white: 0.22, alpha: 1)).setFill()
            s.fill()
            ("Insert \(t)" as NSString).draw(at: NSPoint(x: s.minX + 6, y: s.minY + 12), withAttributes: text)
            (c.armed.contains(t) ? NSColor.systemRed : NSColor(white: 0.45, alpha: 1)).setFill()
            NSBezierPath(ovalIn: armRect(t)).fill()
        }
        NSColor(white: 0.24, alpha: 1).setFill()
        optionsRect.fill()
        ("OPTIONS" as NSString).draw(at: NSPoint(x: optionsRect.minX + 14, y: optionsRect.minY + 5), withAttributes: text)
        ("Mixer - Insert \(c.selected)" as NSString).draw(at: NSPoint(x: bounds.width - 250, y: 22), withAttributes: text)
        NSColor(white: 0.25, alpha: 1).setFill()
        selectorRect.fill()
        (c.input as NSString).draw(at: NSPoint(x: selectorRect.minX + 8, y: selectorRect.minY + 4), withAttributes: text)
        ("Preset : \(c.preset.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "—")" as NSString)
            .draw(at: NSPoint(x: 20, y: bounds.height - 40), withAttributes: text)
    }

    override func mouseDown(with event: NSEvent) {
        guard let c = controller else { return }
        let p = convert(event.locationInWindow, from: nil)
        if selectorRect.contains(p) {
            c.openInputList()
            return
        }
        if optionsRect.contains(p) {
            c.openOptionsMenu()
            return
        }
        for t in 1...Self.trackCount {
            if armRect(t).contains(p) {
                if c.armed.contains(t) { c.armed.remove(t) } else { c.armed.insert(t) }
                c.note("arm button \(t)")
                return
            }
            if stripRect(t).contains(p) {
                c.selected = t
                needsDisplay = true
                c.writeState()
                return
            }
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let c = controller else { return }
        let p = convert(event.locationInWindow, from: nil)
        for t in 1...Self.trackCount where nameRect(t).contains(p) {
            c.openTrackMenu(track: t, at: NSEvent.mouseLocation)
            return
        }
    }
}
