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
    static let snapshot = Notification.Name("app.flshortcut.debug.snapshot")
    /// Vrai clic de souris à « x,y » (points, depuis le coin haut-gauche de la fenêtre de l'éditeur).
    static let click = Notification.Name("app.flshortcut.debug.click")

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
    }

    private static var clickObserver: NSObjectProtocol?

    private static func realClick(x: Double, y: Double) {
        guard let w = NSApp.windows.first(where: { $0.isVisible && $0.frame.width > 400 }),
              let screenHeight = NSScreen.screens.first?.frame.height else { return }
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
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("app.flshortcut.FLShortcut", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var n = 0
        for w in NSApp.windows where w.isVisible && w.frame.width > 150 && w.frame.height > 80 {
            guard let view = w.contentView?.superview ?? w.contentView else { continue }
            guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
            view.cacheDisplay(in: view.bounds, to: rep)
            guard let png = rep.representation(using: .png, properties: [:]) else { continue }
            n += 1
            try? png.write(to: dir.appendingPathComponent("\(tag)-\(n).png"))
        }
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
    }
}
