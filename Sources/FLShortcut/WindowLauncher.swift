// Fenêtres qui sortent du clic : une bulle part de ce qu'on a cliqué (ligne du menu de l'icône ; sans clic, l'icône
// de la barre des menus) et va jusqu'au cadre de la fenêtre qui s'ouvre, en emportant l'icône et le titre de la
// ligne ; la fenêtre apparaît quand la bulle se pose. Fermée par l'utilisateur, la fenêtre disparaît et une bulle
// rentre dans l'icône. La bulle vit dans une fenêtre de vol (sans bord, transparente, sans clic, à la taille du
// trajet), retirée et libérée à la fin ; jamais plus d'une à la fois.
// Pas de vol (ouverture normale de macOS) : fenêtre déjà ouverte, réduite, en plein écran ou sur un autre espace ;
// départ et arrivée sur deux écrans ; « Réduire les animations ». Jamais de bulle restée à l'écran, de fenêtre
// invisible ni d'ouverture perdue : double clic ignoré, fermeture pendant l'ouverture, fenêtre qui n'arrive pas
// (1 s), sûreté à 2 s (ralenti compris).
import AppKit
import SwiftUI

// MARK: - Règles (pures)

enum LaunchEvent {
    case open, landed, windowVisible, timeout, close, finished
}

/// Où en est une ouverture (ou une fermeture) : repos, vol, attente de la fenêtre, apparition, fermeture.
enum LaunchState: Equatable {
    case idle, flying, waiting, revealing, closing

    func next(_ event: LaunchEvent) -> LaunchState {
        switch (self, event) {
        case (.idle, .open): return .flying
        case (.flying, .landed): return .waiting
        case (.waiting, .windowVisible): return .revealing
        case (.waiting, .timeout): return .idle                   // fenêtre absente : bulle retirée
        case (.revealing, .finished), (.closing, .finished): return .idle
        case (.idle, .close), (.flying, .close), (.waiting, .close), (.revealing, .close): return .closing
        default: return self                                       // deuxième clic pendant un vol : ignoré
        }
    }
}

enum LaunchDecision {
    /// Vrai : la bulle vole. Départ connu, même écran que l'arrivée, fenêtre pas déjà là (ni réduite, ni en plein
    /// écran, ni sur un autre espace), mouvement non réduit.
    static func flies(sourceScreen: CGRect?, targetScreen: CGRect?, alreadyVisible: Bool, miniaturized: Bool,
                      fullScreen: Bool, onActiveSpace: Bool, reduced: Bool) -> Bool {
        guard let sourceScreen, let targetScreen, sourceScreen == targetScreen else { return false }
        return !alreadyVisible && !miniaturized && !fullScreen && onActiveSpace && !reduced
    }
}

enum WindowFrameMemory {
    static func save(_ frame: CGRect, key: String, defaults: UserDefaults = .standard) {
        defaults.set(NSStringFromRect(frame), forKey: key)
    }

    static func load(key: String, defaults: UserDefaults = .standard) -> CGRect? {
        guard let text = defaults.string(forKey: key) else { return nil }
        let rect = NSRectFromString(text)
        return rect.width > 0 && rect.height > 0 ? rect : nil
    }

    /// Cadre de cette taille au milieu de `screen`.
    static func centered(size: CGSize, in screen: CGRect) -> CGRect {
        CGRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2, width: size.width,
               height: size.height)
    }
}

/// Fenêtre principale : clé de son cadre mémorisé et taille à sa première ouverture.
enum EditorWindowFrame {
    static let key = "editorFrame"
    static let size = CGSize(width: 900, height: 620)
}

// MARK: - Fenêtre de vol

/// Fenêtre d'une bulle en vol : sans bord, transparente, jamais touchée par la souris, au-dessus de tout, sur tous
/// les espaces ; exclue des rapports et captures de la CI.
final class FlightWindow: NSPanel {
    static func make(frame: CGRect) -> FlightWindow {
        let window = FlightWindow(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                                  backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = .popUpMenu
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        return window
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// MARK: - Lanceur

final class WindowLauncher {
    static let shared = WindowLauncher()

    private(set) var state = LaunchState.idle
    private var flight: FlightWindow?
    private var model: LaunchModel?
    private weak var target: NSWindow?
    /// Scène en vol (`openScene`) et son ouverture, faite à l'atterrissage ou, au plus tard, quand le vol s'arrête.
    private var sceneKey: String?
    private var pendingOpen: (() -> Void)?
    /// Change à chaque vol : un minuteur d'un vol fini ne touche plus à rien.
    private var serial = 0
    private var closeObserver: NSObjectProtocol?
    /// Dernier clic sur une ligne du menu (à l'écran) : départ des fenêtres que cette ligne ouvre.
    private var lastClick: (frame: CGRect, at: Date)?
    /// Fenêtres que l'app ferme elle-même (pas de bulle vers l'icône).
    private let quiet = NSHashTable<NSWindow>.weakObjects()
    /// Fenêtres dont le cadre est mémorisé, avec leurs observateurs (retirés quand la fenêtre a disparu).
    private var remembered: [RememberedWindow] = []
    /// Fenêtre principale attendue après un vol (`openScene`) : elle s'ouvre sans l'animation de macOS.
    private(set) var sceneExpected = false

    /// Ligne du menu cliquée (cadre à l'écran) : la fenêtre qu'elle ouvre part de là.
    func clicked(_ frame: CGRect?) {
        lastClick = frame.map { ($0, Date()) }
    }

    /// Fenêtre créée par l'app, pas encore montrée (son cadre est posé) : à appeler juste avant de la montrer. Si la
    /// bulle vole, la fenêtre reste invisible jusqu'à ce que la bulle soit presque posée.
    func open(source: CGRect?, icon: FlightContent?, title: String?, window: NSWindow) {
        if state != .idle, state != .closing, target === window { return }    // deuxième clic
        finishNow()
        guard let start = source ?? recentClick() ?? Self.iconFrame(),
              LaunchDecision.flies(sourceScreen: Self.screen(of: start), targetScreen: Self.screen(of: window.frame),
                                   alreadyVisible: window.isVisible, miniaturized: window.isMiniaturized,
                                   fullScreen: window.styleMask.contains(.fullScreen), onActiveSpace: true,
                                   reduced: Motion.reduce) else { return }
        window.animationBehavior = .none
        window.alphaValue = 0
        target = window
        watchClose(of: window)
        let id = launch(from: start, to: window.frame, icon: icon, title: title, closing: false)
        after(0.85 * Motion.settleTime(.doux), id) { [weak self] in
            guard let self else { return }
            self.state = self.state.next(.landed)
            self.reveal(id)
        }
    }

    /// Fenêtre d'une scène SwiftUI (fenêtre principale), qu'on ne peut pas cacher avant sa première image : la bulle
    /// vise son dernier cadre connu (sinon `size` au milieu de l'écran), `open` est appelé à l'atterrissage, et la
    /// bulle reste jusqu'à ce que la fenêtre soit là (1 s au plus), puis s'efface sur place.
    func openScene(source: CGRect?, icon: FlightContent?, title: String?, frameKey: String, size: CGSize,
                   window existing: NSWindow? = nil, open: @escaping () -> Void) {
        if sceneKey == frameKey, state == .flying || state == .waiting { return }    // deuxième clic
        finishNow()
        guard let start = source ?? recentClick() ?? Self.iconFrame(),
              let screen = Self.screenObject(of: start) else { open(); return }
        let frame = WindowFrameMemory.load(key: frameKey)
            ?? WindowFrameMemory.centered(size: size, in: screen.visibleFrame)
        guard LaunchDecision.flies(sourceScreen: screen.frame, targetScreen: Self.screen(of: frame),
                                   alreadyVisible: existing?.isVisible ?? false,
                                   miniaturized: existing?.isMiniaturized ?? false,
                                   fullScreen: existing?.styleMask.contains(.fullScreen) ?? false,
                                   onActiveSpace: existing.map { !$0.isVisible || $0.isOnActiveSpace } ?? true,
                                   reduced: Motion.reduce) else {
            open()
            return
        }
        sceneKey = frameKey
        pendingOpen = open
        let id = launch(from: start, to: frame, icon: icon, title: title, closing: false)
        after(Motion.settleTime(.doux), id) { [weak self] in
            guard let self else { return }
            self.state = self.state.next(.landed)
            self.sceneExpected = true
            self.openPending()
            self.waitForScene(id, deadline: Date().addingTimeInterval(DebugSnapshot.slowMotion))
        }
    }

    /// Fenêtre principale : son cadre est mémorisé à chaque déplacement ou changement de taille (cible de la bulle),
    /// et sa fermeture par l'utilisateur rentre dans l'icône. Appelé chaque fois que la fenêtre est connue.
    func remember(_ window: NSWindow, key: String) {
        if sceneExpected {
            window.animationBehavior = .none               // la bulle a fait l'animation
            sceneExpected = false
        }
        let center = NotificationCenter.default
        // Fenêtres disparues (SwiftUI en a créé une autre) : leurs observateurs sont retirés, rien ne s'accumule.
        remembered.removeAll { entry in
            guard entry.window == nil else { return false }
            for token in entry.tokens { center.removeObserver(token) }
            return true
        }
        guard !remembered.contains(where: { $0.window === window }) else { return }
        let entry = RememberedWindow(window)
        for name in [NSWindow.didMoveNotification, NSWindow.didEndLiveResizeNotification] {
            entry.tokens.append(center.addObserver(forName: name, object: window, queue: .main) { [weak window] _ in
                guard let window, window.isVisible, !window.styleMask.contains(.fullScreen) else { return }
                WindowFrameMemory.save(window.frame, key: key)
            })
        }
        entry.tokens.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) {
            [weak self, weak window] _ in
            guard let self, let window else { return }
            if !window.styleMask.contains(.fullScreen) { WindowFrameMemory.save(window.frame, key: key) }
            self.userClosed(window)
        })
        remembered.append(entry)
    }

    /// Fermée par l'utilisateur : une bulle part de son cadre et rentre dans l'icône (même écran seulement). À
    /// appeler avant que la fenêtre disparaisse.
    func userClosed(_ window: NSWindow) {
        if quiet.contains(window) {
            quiet.remove(window)
            return
        }
        if target === window { finishNow() }
        guard window.isVisible, !window.isMiniaturized, !window.styleMask.contains(.fullScreen), !Motion.reduce,
              let icon = Self.iconFrame(), Self.screen(of: icon) == Self.screen(of: window.frame) else { return }
        finishNow()
        let pill = CGRect(x: icon.midX - 14, y: icon.minY, width: 28, height: icon.height)
        let id = launch(from: window.frame, to: pill, icon: nil, title: nil, closing: true)
        after(Motion.settleTime(.doux), id) { [weak self] in self?.fadeAndEnd(id) }
    }

    /// Fermeture décidée par l'app (fin de l'accueil…) : pas de bulle vers l'icône.
    func quietClose(_ window: NSWindow) {
        quiet.add(window)
    }

    /// Tout s'arrête tout de suite : bulle retirée, fenêtre visée rendue visible, ouverture en attente faite.
    func finishNow() {
        serial += 1
        if let flight {
            flight.orderOut(nil)
            flight.contentView = nil
            flight.close()
        }
        flight = nil
        model = nil
        if let target, target.alphaValue < 1 { target.alphaValue = 1 }
        target = nil
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        openPending()
        sceneKey = nil
        state = .idle
    }

    // MARK: Vol

    /// Lance une bulle de `from` à `to` (à l'écran) ; renvoie le numéro du vol.
    private func launch(from: CGRect, to: CGRect, icon: FlightContent?, title: String?, closing: Bool) -> Int {
        let frame = from.union(to).insetBy(dx: -40, dy: -40)
        let local = { (r: CGRect) in
            CGRect(x: r.minX - frame.minX, y: frame.maxY - r.maxY, width: r.width, height: r.height)
        }
        let model = LaunchModel()
        let window = FlightWindow.make(frame: frame)
        window.contentView = NSHostingView(rootView: LaunchBubbleView(
            model: model, from: local(from), to: local(to), icon: icon, title: title, closing: closing))
        window.orderFrontRegardless()
        flight = window
        self.model = model
        state = state.next(closing ? .close : .open)
        let id = serial
        // Sûreté : quoi qu'il arrive, rien ne reste.
        after(FlightGeometry.safetyDeadline(slowMotion: DebugSnapshot.slowMotion), id) { [weak self] in
            self?.finishNow()
        }
        return id
    }

    private func openPending() {
        guard let open = pendingOpen else { return }
        pendingOpen = nil
        open()
    }

    /// La fenêtre apparaît pendant que la bulle s'efface.
    private func reveal(_ id: Int) {
        guard id == serial else { return }
        state = state.next(.windowVisible)
        if let target {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Motion.exitDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                target.animator().alphaValue = 1
            }
        }
        fadeAndEnd(id)
    }

    /// Attend la fenêtre principale (1 s au plus, ralenti compris) ; elle est là : la bulle s'efface sur place.
    private func waitForScene(_ id: Int, deadline: Date) {
        guard id == serial else { return }
        if let window = AppResume.shared.editorWindow, window.isVisible {
            state = state.next(.windowVisible)
            fadeAndEnd(id)
            return
        }
        guard Date() < deadline else {
            state = state.next(.timeout)
            sceneExpected = false
            finishNow()
            return
        }
        after(0.05, id) { [weak self] in self?.waitForScene(id, deadline: deadline) }
    }

    /// Fondu de la bulle, puis tout est retiré.
    private func fadeAndEnd(_ id: Int) {
        guard id == serial, let model else { return }
        withAnimation(Motion.exit) { model.fading = true }
        after(Motion.exitDuration + 0.05, id) { [weak self] in
            guard let self else { return }
            self.state = self.state.next(.finished)
            self.finishNow()
        }
    }

    private func after(_ delay: TimeInterval, _ id: Int, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, id == self.serial else { return }
            work()
        }
    }

    private func watchClose(of window: NSWindow) {
        closeObserver = NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                                               object: window, queue: .main) { [weak self] _ in
            self?.finishNow()                              // fermée pendant son ouverture : rien ne reste
        }
    }

    private func recentClick() -> CGRect? {
        guard let lastClick, Date().timeIntervalSince(lastClick.at) < 1 else { return nil }
        return lastClick.frame
    }

    /// Cadre de l'icône de la barre des menus à l'écran ; nil si elle n'est sur aucun écran (barre masquée).
    static func iconFrame() -> CGRect? {
        guard NSApp != nil,                                // tests : pas d'application, pas d'icône
              let frame = MenuPanel.shared.iconFrameNow(), screen(of: frame) != nil else { return nil }
        return frame
    }

    /// Écran (cadre) qui contient le milieu de `rect`.
    static func screen(of rect: CGRect) -> CGRect? {
        screenObject(of: rect)?.frame
    }

    private static func screenObject(of rect: CGRect) -> NSScreen? {
        let point = CGPoint(x: rect.midX, y: rect.midY)
        return NSScreen.screens.first { $0.frame.insetBy(dx: -1, dy: -1).contains(point) }
    }
}

/// Fenêtre mémorisée (sans la retenir) et ses observateurs.
private final class RememberedWindow {
    weak var window: NSWindow?
    var tokens: [NSObjectProtocol] = []

    init(_ window: NSWindow) { self.window = window }
}

// MARK: - La bulle

private final class LaunchModel: ObservableObject {
    @Published var fading = false
}

/// Bulle qui vole de `from` à `to` (coordonnées de la fenêtre de vol, origine en haut à gauche), avec l'icône et le
/// titre de la ligne qui vont jusqu'en haut à gauche de la fenêtre (après ses boutons). En fermeture : la bulle
/// rétrécit jusqu'à la pastille de l'icône.
private struct LaunchBubbleView: View {
    @ObservedObject var model: LaunchModel
    let from: CGRect
    let to: CGRect
    let icon: FlightContent?
    let title: String?
    let closing: Bool
    @State private var landed = false

    var body: some View {
        Color.clear
            .modifier(LaunchPath(from: from, to: to, icon: icon, title: title, closing: closing,
                                 progress: landed ? 1 : 0))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .opacity(model.fading ? 0 : 1)
            .onAppear { withAnimation(Motion.spring(.doux)) { landed = true } }
    }
}

private struct LaunchPath: ViewModifier, Animatable {
    let from: CGRect
    let to: CGRect
    let icon: FlightContent?
    let title: String?
    let closing: Bool
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let rect = FlightGeometry.rect(at: progress, from: from, to: to)
        let radius = min(closing ? 12 : 14 - 2 * progress, rect.height / 2, rect.width / 2)
        let shape = RoundedRectangle(cornerRadius: max(radius, 0), style: .continuous)
        // L'icône et le titre : du haut-gauche de la ligne au haut-gauche de la fenêtre, après ses boutons.
        let start = CGPoint(x: from.minX + 8, y: from.midY - 11)
        let end = CGPoint(x: to.minX + 78, y: to.minY + 14)
        let mark = CGPoint(x: start.x + (end.x - start.x) * progress, y: start.y + (end.y - start.y) * progress)
        return ZStack(alignment: .topLeading) {
            content
            LaunchSurface(shape: shape)
                .frame(width: max(rect.width, 0), height: max(rect.height, 0))
                .offset(x: rect.minX, y: rect.minY)
            if !closing {
                HStack(spacing: 8) {
                    if let icon { FlightContentView(content: icon) }
                    if let title { Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1).fixedSize() }
                }
                .offset(x: mark.x, y: mark.y)
            }
        }
    }
}

/// Fond de la bulle : verre de macOS 26 comme la bulle du menu, sinon fond de fenêtre opaque avec un filet ; ombre.
private struct LaunchSurface: View {
    let shape: RoundedRectangle
    @AppStorage(Appearance.glassKey) private var glassEnabled = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        surface.shadow(color: Color.black.opacity(0.22), radius: 16, y: 6)
    }

    @ViewBuilder private var surface: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), MenuBubbleStyle.glass, glassEnabled, !reduceTransparency {
            Color.clear.glassEffect(Glass.regular, in: shape)
        } else {
            opaque
        }
        #else
        opaque
        #endif
    }

    private var opaque: some View {
        shape.fill(Color(nsColor: .windowBackgroundColor))
            .overlay(shape.stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }
}

// MARK: - Cadre à l'écran d'une vue (lignes du menu)

/// Boîte qui garde la vue d'AppKit d'une ligne, pour lire son cadre à l'écran au moment du clic.
final class ScreenFrameBox {
    fileprivate weak var view: NSView?

    var screenFrame: CGRect? {
        guard let view, let window = view.window else { return nil }
        return window.convertToScreen(view.convert(view.bounds, to: nil))
    }
}

/// Posée derrière une ligne : donne sa vue à la boîte ; jamais touchée par la souris.
struct ScreenFrameProbe: NSViewRepresentable {
    let box: ScreenFrameBox

    func makeNSView(context: Context) -> NSView {
        let view = PassThroughView()
        box.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        box.view = view
    }

    private final class PassThroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
