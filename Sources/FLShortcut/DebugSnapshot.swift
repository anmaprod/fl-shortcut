// Captures de l'interface pour le développement (désactivées par défaut) :
//   defaults write app.flshortcut.FLShortcut debugSnapshots -bool YES
// puis des notifications distribuées ouvrent l'éditeur, choisissent une section et photographient les fenêtres
// de l'app (ses propres fenêtres : aucune autorisation d'enregistrement de l'écran nécessaire).
import AppKit
import Combine
import SwiftUI

enum DebugSnapshot {
    static var enabled: Bool { UserDefaults.standard.bool(forKey: "debugSnapshots") }
    static let open = Notification.Name("app.flshortcut.debug.open")
    static let select = Notification.Name("app.flshortcut.debug.select")
    /// Texte de recherche de l'éditeur (mesure de la mémoire avec presque toutes les lignes affichées).
    static let search = Notification.Name("app.flshortcut.debug.search")
    static let snapshot = Notification.Name("app.flshortcut.debug.snapshot")
    /// Vrai clic de souris à « x,y » (points, depuis le coin haut-gauche de la fenêtre de l'éditeur).
    static let click = Notification.Name("app.flshortcut.debug.click")
    /// Vrai glisser-déposer de « x1,y1,x2,y2 » (points, depuis le coin haut-gauche de la fenêtre de l'éditeur).
    static let drag = Notification.Name("app.flshortcut.debug.drag")
    /// Taille « l,h » (points) de la fenêtre de l'éditeur, pour les captures sur un petit écran de test.
    static let resize = Notification.Name("app.flshortcut.debug.resize")
    /// Créateur de macros : « open » l'ouvre sur une macro d'exemple jamais enregistrée, « close » le ferme.
    static let macro = Notification.Name("app.flshortcut.debug.macro")
    /// Écrit « editorModels=<n> windows=<n> visible=<n> hidden=<classes> » dans report.txt : modèles du créateur
    /// encore vivants, fenêtres de l'app (même masquées), fenêtres visibles, classes des fenêtres masquées.
    static let report = Notification.Name("app.flshortcut.debug.report")
    /// Page Communauté avec des exemples, sans réseau : « connexion », « inscription », « liste », « vide »,
    /// « detail », « partager » ou « signaler ».
    static let community = Notification.Name("app.flshortcut.debug.community")
    /// Guide : « 0 » à « 4 » ouvre cette page, autre chose le ferme.
    static let guide = Notification.Name("app.flshortcut.debug.guide")

    static func publisher(_ name: Notification.Name) -> AnyPublisher<Notification, Never> {
        guard enabled else { return Empty().eraseToAnyPublisher() }
        return DistributedNotificationCenter.default().publisher(for: name).eraseToAnyPublisher()
    }

    private static var observer: NSObjectProtocol?

    static func start() {
        guard enabled, observer == nil else { return }
        observer = DistributedNotificationCenter.default().addObserver(forName: snapshot, object: nil, queue: .main) { note in
            capture(tag: note.object as? String ?? "capture")
        }
        clickObserver = DistributedNotificationCenter.default().addObserver(forName: click, object: nil, queue: .main) { note in
            let parts = (note.object as? String ?? "").split(separator: ",").compactMap { Double($0) }
            guard parts.count == 2 else { return }
            realClick(x: parts[0], y: parts[1])
        }
        resizeObserver = DistributedNotificationCenter.default().addObserver(forName: resize, object: nil, queue: .main) { note in
            let parts = (note.object as? String ?? "").split(separator: ",").compactMap { Double($0) }
            guard parts.count == 2, (400...3000).contains(parts[0]), (300...2000).contains(parts[1]),
                  let w = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 400 }) else { return }
            w.setContentSize(NSSize(width: parts[0], height: parts[1]))
        }
        reportObserver = DistributedNotificationCenter.default().addObserver(forName: report, object: nil, queue: .main) { _ in
            writeReport()
        }
        dragObserver = DistributedNotificationCenter.default().addObserver(forName: drag, object: nil, queue: .main) { note in
            let parts = (note.object as? String ?? "").split(separator: ",").compactMap { Double($0) }
            guard parts.count == 4 else { return }
            realDrag(from: (x: parts[0], y: parts[1]), to: (x: parts[2], y: parts[3]))
        }
    }

    private static var dragObserver: NSObjectProtocol?

    private static var clickObserver: NSObjectProtocol?
    private static var resizeObserver: NSObjectProtocol?
    private static var reportObserver: NSObjectProtocol?

    private static var cacheDirectory: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("app.flshortcut.FLShortcut", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// ~/Library/Caches/app.flshortcut.FLShortcut/report.txt, écrasé à chaque demande. Première ligne lue par la
    /// mesure de la CI ; ensuite, l'état exact de chaque fenêtre visible (cadre, écran, barre de titre, barre
    /// d'outils, boutons fermer / réduire / agrandir), pour juger l'interface sans capture d'écran.
    private static func writeReport() {
        let hidden = NSApp.windows.filter { !$0.isVisible }.map { String(describing: type(of: $0)) }
        var text = "editorModels=\(MacroEditorModel.liveCount) windows=\(NSApp.windows.count) "
            + "visible=\(NSApp.windows.count - hidden.count) hidden=\(hidden.joined(separator: ","))\n"
        // Ordre des blocs du créateur ouvert (genres seulement, aucun texte) : un bloc déplacé à la souris le change.
        if let draft = MacroEditorModel.newest?.draft {
            text += "créateur : " + draft.blocks.map { BlockRegistry.journal(of: $0.body) }.joined(separator: " > ") + "\n"
        }
        for (i, s) in NSScreen.screens.enumerated() {
            text += "écran \(i): frame \(rect(s.frame)) visible \(rect(s.visibleFrame)) échelle \(s.backingScaleFactor)\n"
        }
        for w in NSApp.windows where w.isVisible {
            text += windowLines(w)
        }
        try? text.write(to: cacheDirectory.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
    }

    /// Toutes les zones de défilement visibles sous `view` (assez grandes pour être une liste).
    private static func scrollViews(in view: NSView) -> [NSScrollView] {
        var out: [NSScrollView] = []
        if let scroll = view as? NSScrollView, !scroll.isHiddenOrHasHiddenAncestor,
           scroll.bounds.width > 100, scroll.bounds.height > 100 {
            out.append(scroll)
        }
        for sub in view.subviews { out += scrollViews(in: sub) }
        return out
    }

    private static func tableViews(in view: NSView) -> [NSTableView] {
        var out: [NSTableView] = []
        if let table = view as? NSTableView, !table.isHiddenOrHasHiddenAncestor { out.append(table) }
        for sub in view.subviews { out += tableViews(in: sub) }
        return out
    }

    private static func splitViews(in view: NSView) -> [NSSplitView] {
        var out: [NSSplitView] = []
        if let split = view as? NSSplitView, !split.isHiddenOrHasHiddenAncestor { out.append(split) }
        for sub in view.subviews { out += splitViews(in: sub) }
        return out
    }

    private static func rect(_ r: NSRect) -> String {
        "(\(Int(r.minX)),\(Int(r.minY)) \(Int(r.width))×\(Int(r.height)))"
    }

    private static func size(_ s: NSSize) -> String {
        "\(Int(s.width))×\(Int(s.height))"
    }

    /// Coordonnées AppKit (origine en bas à gauche de l'écran principal).
    static func windowLines(_ w: NSWindow) -> String {
        var s = "fenêtre \(type(of: w)) « \(w.title) » #\(w.windowNumber) niveau \(w.level.rawValue)\n"
        s += "  cadre \(rect(w.frame)) · écran \(w.screen.map { rect($0.frame) } ?? "aucun")"
        if let screen = w.screen {
            let inside = screen.visibleFrame.contains(w.frame)
            s += " · entièrement dans la zone visible : \(inside ? "oui" : "NON")"
            if w.frame.maxY > screen.visibleFrame.maxY {
                s += " (dépasse en haut de \(Int(w.frame.maxY - screen.visibleFrame.maxY)) pt)"
            }
        }
        s += "\n"
        let mask = w.styleMask
        let flags: [(NSWindow.StyleMask, String)] = [(.titled, "titled"), (.closable, "closable"),
            (.miniaturizable, "miniaturizable"), (.resizable, "resizable"), (.fullSizeContentView, "fullSizeContentView"),
            (.fullScreen, "fullScreen"), (.borderless, "borderless")]
        s += "  styleMask : " + flags.filter { mask.contains($0.0) }.map(\.1).joined(separator: ", ") + "\n"
        s += "  titre visible : \(w.titleVisibility == .visible ? "oui" : "non") · barre de titre transparente : "
            + "\(w.titlebarAppearsTransparent ? "oui" : "non") · zoomée : \(w.isZoomed ? "oui" : "non") · clé : "
            + "\(w.isKeyWindow ? "oui" : "non") · espace actif : \(w.isOnActiveSpace ? "oui" : "non")\n"
        s += "  contentLayoutRect \(rect(w.contentLayoutRect)) · hauteur de la barre de titre "
            + "\(Int(w.frame.height - w.contentLayoutRect.height)) pt\n"
        if let toolbar = w.toolbar {
            let items = toolbar.items.map { $0.label.isEmpty ? $0.itemIdentifier.rawValue : $0.label }
            s += "  barre d'outils : visible \(toolbar.isVisible ? "oui" : "NON") · style \(w.toolbarStyle.rawValue) · "
                + "\(items.count) éléments : \(items.joined(separator: " | "))\n"
        } else {
            s += "  barre d'outils : AUCUNE\n"
        }
        // Zones de défilement (listes) : défilées (origine > 0) ou posées sous la barre de titre (marge du haut 0) ?
        if let root = w.contentView?.superview ?? w.contentView {
            for scroll in scrollViews(in: root) {
                let frame = scroll.convert(scroll.bounds, to: nil)
                let visible = scroll.documentVisibleRect
                let docHeight = scroll.documentView?.frame.height ?? 0
                s += "  défilement \(rect(frame)) · origine du contenu \(Int(visible.minY)) · hauteur du contenu "
                    + "\(Int(docHeight)) · marges auto \(scroll.automaticallyAdjustsContentInsets ? "oui" : "non") "
                    + "haut \(Int(scroll.contentInsets.top)) bas \(Int(scroll.contentInsets.bottom))\n"
            }
            // Listes : nombre de lignes (créateur : un bloc glissé depuis la palette en ajoute une).
            for table in tableViews(in: root) {
                s += "  liste \(rect(table.convert(table.visibleRect, to: nil))) · \(table.numberOfRows) lignes\n"
            }
            // Colonnes (NavigationSplitView) : laquelle réclame plus de hauteur que la fenêtre n'en a ?
            if let content = w.contentView {
                s += "  contenu \(rect(content.convert(content.bounds, to: nil))) · taille idéale \(size(content.fittingSize))\n"
            }
            for split in splitViews(in: root) {
                s += "  colonnes \(rect(split.convert(split.bounds, to: nil))) · taille idéale \(size(split.fittingSize))\n"
                for pane in split.arrangedSubviews {
                    s += "    colonne \(rect(pane.convert(pane.bounds, to: nil))) · taille idéale \(size(pane.fittingSize))"
                        + " · \(String(describing: type(of: pane)).prefix { $0 != "<" })\n"
                }
            }
        }
        for (button, name) in [(NSWindow.ButtonType.closeButton, "fermer"), (.miniaturizeButton, "réduire"),
                               (.zoomButton, "agrandir")] {
            guard let b = w.standardWindowButton(button) else { s += "  bouton \(name) : ABSENT\n"; continue }
            let inWindow = b.convert(b.bounds, to: nil)
            var visibleChain = !b.isHidden && b.alphaValue > 0.01
            var v: NSView? = b.superview
            while let view = v { if view.isHidden || view.alphaValue < 0.01 { visibleChain = false }; v = view.superview }
            s += "  bouton \(name) : \(visibleChain ? "visible" : "CACHÉ") · actif \(b.isEnabled ? "oui" : "non") · "
                + "dans la fenêtre \(rect(inWindow))\n"
        }
        return s
    }

    /// Point de l'écran (origine en haut à gauche, comme CGEvent) d'un point « x,y » de notre fenêtre, mise devant.
    private static func screenPoint(x: Double, y: Double) -> CGPoint? {
        guard let w = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 400 }),
              let screenHeight = NSScreen.screens.first?.frame.height,
              (0...w.frame.width).contains(x), (0...w.frame.height).contains(y) else { return nil }   // notre fenêtre seulement
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        return CGPoint(x: w.frame.minX + x, y: screenHeight - (w.frame.maxY - y))
    }

    private static func post(_ type: CGEventType, _ point: CGPoint) {
        CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    private static func realClick(x: Double, y: Double) {
        guard let point = screenPoint(x: x, y: y) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            post(.leftMouseDown, point)
            post(.leftMouseUp, point)
        }
    }

    /// Vrai glisser-déposer de la souris, comme une main : appui, 24 petits pas en 0,6 s, pause sur la cible, lâcher.
    private static func realDrag(from: (x: Double, y: Double), to: (x: Double, y: Double)) {
        guard let start = screenPoint(x: from.x, y: from.y), let end = screenPoint(x: to.x, y: to.y) else { return }
        let steps = 24
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { post(.leftMouseDown, start) }
        for i in 1...steps {
            let t = Double(i) / Double(steps)
            let p = CGPoint(x: start.x + (end.x - start.x) * t, y: start.y + (end.y - start.y) * t)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5 + 0.025 * Double(i)) { post(.leftMouseDragged, p) }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { post(.leftMouseUp, end) }
    }

    /// Une image PNG par fenêtre visible, dans ~/Library/Caches/app.flshortcut.FLShortcut/.
    static func capture(tag: String) {
        let dir = cacheDirectory
        var n = 0
        var sizes: [String] = []
        for w in NSApp.windows where w.isVisible && w.frame.width > 150 && w.frame.height > 80 {
            if let content = w.contentView {
                sizes.append("fenêtre \(Int(w.frame.width))×\(Int(w.frame.height)), contenu minimal "
                             + "\(Int(content.fittingSize.width))×\(Int(content.fittingSize.height)), "
                             + "taille min. \(Int(w.contentMinSize.width))×\(Int(w.contentMinSize.height))")
            }
            guard let view = w.contentView?.superview ?? w.contentView else { continue }
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { continue }
            n += 1
            try? png.write(to: dir.appendingPathComponent("\(tag)-\(n).png"))
        }
        try? sizes.joined(separator: "\n").write(to: dir.appendingPathComponent("\(tag)-tailles.txt"),
                                                atomically: true, encoding: .utf8)
    }
}

/// Icône de la barre des menus (le logo de l'app, avec la pastille d'état : MenuBarIcon) ; en mode capture, sait
/// aussi ouvrir l'éditeur.
struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow
    let symbol: String

    var body: some View {
        Image(nsImage: MenuBarIcon.image(MenuBarIcon.state(forSymbol: symbol)))
            .onReceive(DebugSnapshot.publisher(DebugSnapshot.open)) { _ in
                openWindow(id: "editor")
                NSApp.activate(ignoringOtherApps: true)
            }
            .onReceive(DebugSnapshot.publisher(DebugSnapshot.macro)) { note in
                if (note.object as? String) == "close" {
                    MacroCreatorLink.shared.requestClose()
                    return
                }
                MacroCreatorLink.shared.openSample()            // affiché dans la fenêtre principale
            }
    }
}
