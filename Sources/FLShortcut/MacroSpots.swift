// Clics que la macro ne peut pas deviner sans regarder l'écran (menu de piste de FL, sélecteur d'entrée) :
// la première fois, l'utilisateur les fait lui-même pendant la macro (une bulle le guide) ; l'app retient leur
// place, puis les refait seule. Aucune lecture de l'écran, seulement la position des clics dans FL.
// - v2 (chemins) : chaque clic est retenu par rapport à la fenêtre du menu de FL où il est tombé (FL décale son
//   menu pour qu'il tienne à l'écran : seul son coin compte, jamais le point du clic droit). Entrée : sélecteur
//   relatif au coin haut-droit de la fenêtre de FL (taille retenue), entrée « 1 » relative à la liste ouverte.
// - v1 (Learned / Kind) : ancien format, ignoré (un seul réapprentissage) ; gardé pour le rejeu exact.
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
        for k in PathKind.allCases { defaults.removeObject(forKey: k.rawValue) }
        MacroRunner.forgetTrackMenuMemo(defaults: defaults)
    }

    static var anyLearned: Bool { PathKind.allCases.contains { loadPath($0) != nil } }
}

/// Enregistre les clics gauches faits dans FL pendant l'apprentissage : position ET instant de l'événement (pas le
/// curseur relu plus tard), nos propres clics ignorés.
final class ClickRecorder {
    static let shared = ClickRecorder()

    private var monitor: Any?
    private let samples = Locked<[ClickSample]>([])

    private init() {}

    var captured: [CGPoint] { samples.value.map(\.point) }
    var capturedSamples: [ClickSample] { samples.value }

    func start() {
        samples.withLock { $0 = [] }
        guard monitor == nil else { return }
        monitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            let cfg = EventTap.shared.currentConfig
            guard cfg.flPIDs.contains(cfg.frontmostPID) else { return }
            if event.cgEvent?.getIntegerValueField(.eventSourceUserData) == EventTap.mark { return }
            let p = event.cgEvent?.location ?? FLWindows.cursor()
            self?.samples.withLock { $0.append(ClickSample(point: p, time: event.timestamp)) }
        }
    }

    func stop() {
        if let m = monitor { NSEvent.removeMonitor(m) }
        monitor = nil
    }
}

struct ClickSample: Equatable {
    let point: CGPoint          // coordonnées CG globales (origine en haut à gauche)
    let time: TimeInterval      // NSEvent.timestamp (temps depuis le démarrage)
}

extension MacroSpots {
    /// Un clic dans un menu que FL a ouvert dans sa propre fenêtre, relatif au coin haut-gauche de CETTE fenêtre.
    /// Indépendant de l'endroit où FL a placé (décalé) le menu.
    struct PopupHop: Codable, Equatable {
        var offset: CGVector
        var size: CGSize

        /// Même menu qu'à l'apprentissage : même hauteur (lignes), largeur assez libre (les noms de piste l'élargissent).
        func fits(_ w: CGRect) -> Bool {
            abs(w.height - size.height) <= 3 && w.width >= size.width * 0.5 && w.width <= size.width * 2.5
                && offset.dy >= 1 && offset.dy <= w.height - 1
        }

        func point(in w: CGRect) -> CGPoint {
            CGPoint(x: w.minX + min(max(offset.dx, 8), w.width - 8), y: w.minY + offset.dy)
        }
    }

    /// Où le menu de piste a été ouvert à l'apprentissage (ligne de la tranche du mixer), relatif au haut de la fenêtre de FL.
    struct TrackRow: Codable, Equatable {
        var yFromWindowTop: CGFloat
        var windowSize: CGSize
    }

    /// Premier clic dans une fenêtre normale de FL (sélecteur d'entrée), relatif au coin haut-droit de cette fenêtre.
    struct WindowStart: Codable, Equatable {
        var fromTopRight: CGVector
        var windowSize: CGSize
    }

    /// Aucune fenêtre de menu vue à l'apprentissage (FL a dessiné le menu dans sa propre fenêtre) : rejeu exact seulement.
    struct InlineReplay: Codable, Equatable {
        var anchor: CGPoint            // point du clic droit (menus de piste) ou premier clic (entrée)
        var offsets: [CGVector]        // enchaînés, le premier depuis `anchor`
    }

    struct MenuPath: Codable, Equatable {
        var version = 2
        var row: TrackRow?
        var start: WindowStart?
        var hops: [PopupHop] = []
        var inline: InlineReplay?

        var isValid: Bool {
            func ok(_ v: CGFloat) -> Bool { v.isFinite && abs(v) <= 5000 }
            guard version == 2, hops.count <= 3, !hops.isEmpty || inline != nil else { return false }
            let hopsOK = hops.allSatisfy {
                ok($0.offset.dx) && ok($0.offset.dy) && (16...2000).contains($0.size.width) && (16...4000).contains($0.size.height)
                    && $0.offset.dy >= 0 && $0.offset.dy <= $0.size.height
            }
            let inlineOK = inline.map { (1...3).contains($0.offsets.count) && $0.offsets.allSatisfy { ok($0.dx) && ok($0.dy) } } ?? true
            let startOK = start.map { ok($0.fromTopRight.dx) && ok($0.fromTopRight.dy) && $0.windowSize.width > 50 } ?? true
            return hopsOK && inlineOK && startOK
        }
    }

    enum PathKind: String, CaseIterable {
        case openState = "macroSpots.v2.openState"       // menu de piste › File › Open mixer track state
        case armSelected = "macroSpots.v2.armSelected"   // menu de piste › Arm selected track(s)
        case input = "macroSpots.v2.input"               // (none) › 1
    }

    static func loadPath(_ kind: PathKind, defaults: UserDefaults = .standard) -> MenuPath? {
        guard let data = defaults.data(forKey: kind.rawValue),
              let path = try? JSONDecoder().decode(MenuPath.self, from: data), path.isValid else { return nil }
        return path
    }

    static func savePath(_ path: MenuPath, _ kind: PathKind, defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(path) { defaults.set(data, forKey: kind.rawValue) }
    }

    static func describe(_ path: MenuPath) -> String {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys]
        return (try? e.encode(path)).flatMap { String(data: $0, encoding: .utf8) } ?? "?"
    }

    static func sameSize(_ a: CGSize, _ b: CGSize, tolerance: CGFloat = 2) -> Bool {
        abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    /// Pure (testée) : attribue chaque clic de l'utilisateur à la fenêtre de FL qui était tout devant sous lui juste avant
    /// le clic. Une fenêtre absente de `base` (relevée avant le clic droit / le premier clic) est un menu → saut
    /// relatif à son coin haut-gauche. Si un clic n'est pas tombé dans un menu, tout le chemin est gardé tel quel (inline).
    static func resolve(_ samples: [ClickSample], history: [WinSnapshot], base: Set<Int>,
                        anchor: CGPoint, firstInWindow: Bool) -> MenuPath {
        func window(at s: ClickSample) -> WinInfo? {
            (history.last(where: { $0.time <= s.time }) ?? history.first)?.hit(s.point)
        }
        var path = MenuPath()
        var rest = samples[...]
        var origin = anchor
        if firstInWindow, let first = rest.first {
            guard let w = window(at: first) else { return path }                   // invalide (ni sauts, ni inline)
            path.start = WindowStart(fromTopRight: CGVector(dx: first.point.x - w.bounds.maxX, dy: first.point.y - w.bounds.minY),
                                     windowSize: w.bounds.size)
            origin = first.point
            rest = rest.dropFirst()
        }
        var hops: [PopupHop] = []
        for s in rest {
            guard let w = window(at: s), !base.contains(w.number) else { break }
            hops.append(PopupHop(offset: CGVector(dx: s.point.x - w.bounds.minX, dy: s.point.y - w.bounds.minY),
                                 size: w.bounds.size))
        }
        if !hops.isEmpty, hops.count == rest.count {
            path.hops = hops
        } else if !rest.isEmpty {
            path.inline = InlineReplay(anchor: origin, offsets: offsets(rest.map(\.point), from: origin))
        }
        return path
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
