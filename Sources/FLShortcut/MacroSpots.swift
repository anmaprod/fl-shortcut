// Clics que la macro ne peut pas deviner sans regarder l'écran (menu de piste de FL, sélecteur d'entrée) :
// la première fois, l'utilisateur les fait lui-même pendant la macro (une bulle le guide) ; l'app retient leur
// place, puis les refait seule. Aucune lecture de l'écran, seulement la position des clics dans FL.
// - Menu : positions relatives au clic droit sur la piste (le menu de FL s'ouvre toujours au même endroit
//   par rapport au clic).
// - Entrée : sélecteur relatif au coin haut-droit de la fenêtre de FL, entrée « 1 » relative au sélecteur.
//   Retenu avec la taille de la fenêtre : si elle change, la place du sélecteur aussi → on redemande.
import AppKit
import SwiftUI

enum MacroSpots {
    /// Points appris : le premier relatif à un repère, les suivants relatifs au point précédent.
    struct Learned: Codable, Equatable {
        var anchorSize: CGSize
        var offsets: [CGVector]

        func points(from anchor: CGPoint) -> [CGPoint] {
            var out: [CGPoint] = []
            var last = anchor
            for o in offsets {
                last = CGPoint(x: last.x + o.dx, y: last.y + o.dy)
                out.append(last)
            }
            return out
        }

        /// Même fenêtre qu'à l'apprentissage (à 2 points près).
        func matches(size: CGSize) -> Bool {
            abs(size.width - anchorSize.width) <= 2 && abs(size.height - anchorSize.height) <= 2
        }
    }

    static func offsets(_ points: [CGPoint], from anchor: CGPoint) -> [CGVector] {
        var out: [CGVector] = []
        var last = anchor
        for p in points {
            out.append(CGVector(dx: p.x - last.x, dy: p.y - last.y))
            last = p
        }
        return out
    }

    enum Kind: String, CaseIterable {
        case trackMenu = "macroSpots.trackMenu"
        case input = "macroSpots.input"
    }

    static func load(_ kind: Kind, defaults: UserDefaults = .standard) -> Learned? {
        guard let data = defaults.data(forKey: kind.rawValue) else { return nil }
        guard let l = try? JSONDecoder().decode(Learned.self, from: data),
              !l.offsets.isEmpty, l.offsets.count <= 4,
              l.offsets.allSatisfy({ abs($0.dx) <= 3000 && abs($0.dy) <= 3000 }) else { return nil }
        return l
    }

    static func save(_ learned: Learned, _ kind: Kind, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(learned) { defaults.set(data, forKey: kind.rawValue) }
    }

    static func forgetAll(defaults: UserDefaults = .standard) {
        for k in Kind.allCases { defaults.removeObject(forKey: k.rawValue) }
    }

    static var anyLearned: Bool { Kind.allCases.contains { load($0) != nil } }
}

/// Enregistre les clics gauches faits dans FL pendant l'apprentissage (position seulement). Thread principal pour
/// le moniteur ; les points se lisent depuis n'importe quel thread.
final class ClickRecorder {
    static let shared = ClickRecorder()

    private var monitor: Any?
    private let points = Locked<[CGPoint]>([])

    private init() {}

    var captured: [CGPoint] { points.value }

    func start() {
        points.withLock { $0 = [] }
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] _ in
            let cfg = EventTap.shared.currentConfig
            guard cfg.flPIDs.contains(cfg.frontmostPID) else { return }
            let p = FLWindows.cursor()
            self?.points.withLock { $0.append(p) }
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }
}

/// Petite bulle d'aide flottante (verre sur macOS 26), qui ne prend jamais le premier plan à FL.
final class HintPanel {
    static let shared = HintPanel()

    private var panel: NSPanel?

    private init() {}

    func show(_ text: String, near point: CGPoint) {
        hide()
        let host = NSHostingView(rootView: HintView(text: text))
        host.frame.size = host.fittingSize
        let p = NSPanel(contentRect: NSRect(origin: .zero, size: host.fittingSize),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.level = .statusBar
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        p.contentView = host
        // Coordonnées CoreGraphics (haut-gauche) → AppKit (bas-gauche), bulle juste au-dessus du point.
        let mainHeight = NSScreen.screens.first?.frame.height ?? 900
        var origin = NSPoint(x: point.x - host.fittingSize.width / 2, y: mainHeight - point.y + 24)
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSPoint(x: point.x, y: mainHeight - point.y)) }) {
            let f = screen.visibleFrame
            origin.x = min(max(origin.x, f.minX + 8), f.maxX - host.fittingSize.width - 8)
            origin.y = min(max(origin.y, f.minY + 8), f.maxY - host.fittingSize.height - 8)
        }
        p.setFrameOrigin(origin)
        p.orderFrontRegardless()
        panel = p
    }

    func hide() {
        hideWork?.cancel()
        panel?.orderOut(nil)
        panel = nil
    }

    private var hideWork: DispatchWorkItem?

    /// Message bref près du curseur (échec d'une macro), retiré tout seul.
    func flash(_ text: String, seconds: TimeInterval = 4) {
        show(text, near: FLWindows.cursor())
        let work = DispatchWorkItem { [weak self] in self?.hide() }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}

private struct HintView: View {
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.point.up.left.fill").foregroundStyle(.tint)
            Text(text).font(.system(size: 13, weight: .medium)).fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(maxWidth: 360)
        .glassSurface(Capsule())
    }
}
