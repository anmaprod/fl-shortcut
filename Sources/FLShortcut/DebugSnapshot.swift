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
    /// Taille « l,h » (points) de la fenêtre de l'éditeur, pour les captures sur un petit écran de test.
    static let resize = Notification.Name("app.flshortcut.debug.resize")
    /// Créateur de macros : « open » l'ouvre sur une macro d'exemple jamais enregistrée, « close » le ferme.
    static let macro = Notification.Name("app.flshortcut.debug.macro")
    /// Écrit « editorModels=<n> windows=<n> visible=<n> hidden=<classes> » dans report.txt : modèles du créateur
    /// encore vivants, fenêtres de l'app (même masquées), fenêtres visibles, classes des fenêtres masquées.
    static let report = Notification.Name("app.flshortcut.debug.report")

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
    }

    private static var clickObserver: NSObjectProtocol?
    private static var resizeObserver: NSObjectProtocol?
    private static var reportObserver: NSObjectProtocol?

    private static var cacheDirectory: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("app.flshortcut.FLShortcut", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// ~/Library/Caches/app.flshortcut.FLShortcut/report.txt, écrasé à chaque demande.
    private static func writeReport() {
        let hidden = NSApp.windows.filter { !$0.isVisible }.map { String(describing: type(of: $0)) }
        let text = "editorModels=\(MacroEditorModel.liveCount) windows=\(NSApp.windows.count) "
            + "visible=\(NSApp.windows.count - hidden.count) hidden=\(hidden.joined(separator: ","))\n"
        try? text.write(to: cacheDirectory.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
    }

    private static func realClick(x: Double, y: Double) {
        guard let w = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 400 }),
              let screenHeight = NSScreen.screens.first?.frame.height,
              (0...w.frame.width).contains(x), (0...w.frame.height).contains(y) else { return }   // notre fenêtre seulement
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        let point = CGPoint(x: w.frame.minX + x, y: screenHeight - (w.frame.maxY - y))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            for type in [CGEventType.leftMouseDown, .leftMouseUp] {
                CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
                    .post(tap: .cghidEventTap)
            }
        }
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

/// Icône de la barre des menus ; en mode capture, sait aussi ouvrir l'éditeur.
struct MenuBarLabel: View {
    @Environment(\.openWindow) private var openWindow
    let symbol: String

    var body: some View {
        Image(systemName: symbol)
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
