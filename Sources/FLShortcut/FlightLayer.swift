// Couche de vol : un seul mécanisme pour ce qui vole d'un endroit à un autre dans une fenêtre (icône, titre, touche,
// fond de carte). Les cadres sont lus par AppKit (`frameProbe`, lignes de `List` comprises) au moment du vol, après
// la mise en page, et convertis vers la vue de la couche par `NSView.convert` (jamais retournés par la hauteur de la
// fenêtre : faux sous une barre d'outils). Une copie part de l'élément de départ (qui reste visible) et va jusqu'à
// l'élément d'arrivée (`flightTarget`, caché jusqu'à l'atterrissage), avec le ressort doux ; elle est dessinée à la
// taille d'arrivée et mise à l'échelle depuis celle de départ. Deux vols vers le même élément ne coexistent jamais :
// le second repart de la position courante du premier. Sûreté : un vol finit au plus tard 2 s (× ralenti) après son
// départ, quoi qu'il arrive ; aucun élément ne reste caché. Cadre manquant, mouvement réduit ou fenêtre gelée : pas
// de vol, la fin est appelée tout de suite. Jamais vers la barre d'outils (AppKit, au-dessus de la couche).
import AppKit
import SwiftUI

/// Ce qui vole.
enum FlightContent {
    case icon(symbol: String, tint: Color, size: CGFloat)
    case text(String, font: Font)
    case key(String)
    case card(cornerRadius: CGFloat)

    /// Dessiné à la taille d'arrivée puis mis à l'échelle (vrai), ou à la taille courante (faux : un fond de carte
    /// garde ses coins nets).
    var scales: Bool {
        if case .card = self { return false }
        return true
    }

    /// Même chose dessinée (même symbole, texte ou touche) : un nouveau vol vers la même place repart alors d'où
    /// l'autre en était ; sinon c'est un autre élément (navigation rapide dans la barre latérale), parti de chez lui.
    func isSame(as other: FlightContent) -> Bool {
        switch (self, other) {
        case let (.icon(a, _, _), .icon(b, _, _)): return a == b
        case let (.text(a, _), .text(b, _)): return a == b
        case let (.key(a), .key(b)): return a == b
        case (.card, .card): return true
        default: return false
        }
    }
}

/// Dessin d'un contenu qui vole (aussi utilisé par les fenêtres qui sortent du clic).
struct FlightContentView: View {
    let content: FlightContent
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        switch content {
        case .icon(let symbol, let tint, let size):
            SectionIcon(symbol: symbol, tint: tint, size: size)
        case .text(let text, let font):
            Text(text).font(font).lineLimit(1).fixedSize()
        case .key(let symbol):
            KeyCap(symbol: symbol)
        case .card(let radius):
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(scheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.045)))
                .shadow(color: Color.black.opacity(0.18), radius: 14, y: 6)
        }
    }
}

// MARK: - Géométrie (pure)

enum FlightGeometry {
    /// Rectangle à `progress` (0 = départ, 1 = arrivée) : origine et taille interpolées.
    static func rect(at progress: CGFloat, from: CGRect, to: CGRect) -> CGRect {
        CGRect(x: from.minX + (to.minX - from.minX) * progress,
               y: from.minY + (to.minY - from.minY) * progress,
               width: from.width + (to.width - from.width) * progress,
               height: from.height + (to.height - from.height) * progress)
    }

    /// `rect` (dans `view`) dans les coordonnées de la vue de la couche : `NSView.convert`, qui tient compte des vues
    /// retournées et de tout ce qui les sépare.
    static func local(_ rect: CGRect, of view: NSView, in layer: NSView) -> CGRect {
        view.convert(rect, to: layer)
    }

    /// Fin forcée d'un vol, après son départ : 2 s, ralenti compris.
    static func safetyDeadline(slowMotion: Double) -> TimeInterval {
        2 * slowMotion
    }
}

// MARK: - Centre des vols

final class FlightCenter: ObservableObject {
    struct Flight: Identifiable {
        let id = UUID()
        let content: FlightContent
        let from: CGRect
        let to: CGRect
        let target: String
        let start: Date
        let deadline: Date
        /// Réponse du ressort au départ (ralenti compris), pour retrouver la position courante.
        let response: Double
        let completion: (() -> Void)?

        /// Position au temps `date`, comme le ressort la dessine.
        func rect(at date: Date) -> CGRect {
            let progress = Motion.springValue(at: date.timeIntervalSince(start), response: response,
                                              damping: MotionSpring.doux.damping)
            return FlightGeometry.rect(at: CGFloat(progress), from: from, to: to)
        }
    }

    /// Éléments d'arrivée cachés jusqu'à l'atterrissage.
    @Published private(set) var hidden: Set<String> = []
    @Published private(set) var flights: [Flight] = []
    /// Mode de la fenêtre (posé par `flightLayer`) : pas de vol s'il est réduit ou gelé.
    var mode = MotionMode.full

    /// Centre sans couche (vue hors d'une fenêtre qui en a une) : rien n'y vole jamais.
    static let idle = FlightCenter()
    static let layerID = "flight.couche"

    private var views: [String: WeakView] = [:]
    private let now: () -> Date
    private let schedule: (TimeInterval, @escaping () -> Void) -> Void

    init(now: @escaping () -> Date = Date.init,
         schedule: @escaping (TimeInterval, @escaping () -> Void) -> Void = FlightCenter.mainQueue) {
        self.now = now
        self.schedule = schedule
    }

    static func mainQueue(_ delay: TimeInterval, _ work: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: Cadres

    func register(_ id: String, view: NSView) {
        views[id] = WeakView(view: view)
    }

    /// Oublie le cadre `id` ; avec `view`, seulement s'il est encore le sien (une cellule de `List` réutilisée a pu
    /// le reprendre entre-temps).
    func unregister(_ id: String, view: NSView? = nil) {
        guard let view else { views[id] = nil; return }
        if views[id]?.view === view || views[id]?.view == nil { views[id] = nil }
    }

    /// Cadre de `id` dans la couche, lu maintenant (après la mise en page de la fenêtre) ; nil si la vue n'est plus
    /// dans la même fenêtre que la couche.
    func frame(of id: String) -> CGRect? {
        guard let layer = views[Self.layerID]?.view, let window = layer.window,
              let view = views[id]?.view, view.window === window else { return nil }
        window.contentView?.layoutSubtreeIfNeeded()
        let rect = FlightGeometry.local(view.bounds, of: view, in: layer)
        return rect.width > 0 && rect.height > 0 ? rect : nil
    }

    /// Cadre de `id` dans sa fenêtre (coordonnées d'AppKit) ; nil si sa vue n'est plus dans une fenêtre.
    func windowFrame(of id: String) -> CGRect? {
        guard let view = views[id]?.view, view.window != nil else { return nil }
        return view.convert(view.bounds, to: nil)
    }

    // MARK: Vols

    func fly(_ content: FlightContent, from: String, to: String, completion: (() -> Void)? = nil) {
        guard let start = frame(of: from) else { completion?(); return }
        fly(content, fromRect: start, to: to, completion: completion)
    }

    func fly(_ content: FlightContent, fromRect: CGRect, to: String, completion: (() -> Void)? = nil) {
        guard mode == .full, let end = frame(of: to) else { completion?(); return }
        launch(content, from: fromRect, to: end, target: to, completion: completion)
    }

    /// Fenêtre fermée : tous les vols finissent (leur fin est appelée), plus rien n'est caché.
    func cancelAll() {
        for flight in flights { finish(flight.id) }
    }

    /// Vol de test, sans cadres ni ressort (FlightLayerTests).
    func testFly(target: String) {
        launch(.card(cornerRadius: 0), from: .zero, to: .zero, target: target, completion: nil)
    }

    /// Sûreté : finit les vols dont l'heure limite est passée.
    func expire(at date: Date) {
        for flight in flights where flight.deadline <= date { finish(flight.id) }
    }

    private func launch(_ content: FlightContent, from: CGRect, to: CGRect, target: String,
                        completion: (() -> Void)?) {
        let start = now()
        var origin = from
        if let previous = flights.first(where: { $0.target == target }) {
            if previous.content.isSame(as: content) { origin = previous.rect(at: start) }   // d'où l'autre en était
            finish(previous.id)
        }
        let slow = DebugSnapshot.slowMotion
        let flight = Flight(content: content, from: origin, to: to, target: target, start: start,
                            deadline: start.addingTimeInterval(FlightGeometry.safetyDeadline(slowMotion: slow)),
                            response: MotionSpring.doux.response * slow, completion: completion)
        flights.append(flight)
        hidden.insert(target)
        let id = flight.id
        schedule(Motion.settleTime(.doux)) { [weak self] in self?.finish(id) }
        schedule(FlightGeometry.safetyDeadline(slowMotion: slow) + 0.05) { [weak self] in
            guard let self else { return }
            self.expire(at: self.now())
        }
    }

    /// Fin d'un vol (atterrissage, sûreté, remplacement, fenêtre fermée) : une seule fois, sans animation (l'élément
    /// d'arrivée prend la place de la copie dans la même mise à jour).
    private func finish(_ id: UUID) {
        guard let index = flights.firstIndex(where: { $0.id == id }) else { return }
        let flight = flights[index]
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            flights.remove(at: index)
            if !flights.contains(where: { $0.target == flight.target }) { hidden.remove(flight.target) }
        }
        flight.completion?()
    }
}

private struct WeakView {
    weak var view: NSView?
}

// MARK: - Environnement

private struct FlightCenterKey: EnvironmentKey {
    static let defaultValue: FlightCenter? = nil
}

extension EnvironmentValues {
    /// Centre des vols de la fenêtre (posé par `flightLayer`) ; nil hors d'une fenêtre qui a une couche.
    var flightCenter: FlightCenter? {
        get { self[FlightCenterKey.self] }
        set { self[FlightCenterKey.self] = newValue }
    }
}

extension View {
    /// Cadre de cette vue, connu du centre des vols sous `id` tant qu'elle est dans la fenêtre.
    func frameProbe(_ id: String) -> some View {
        background(FlightProbe(id: id, isLayer: false))
    }

    /// Élément d'arrivée d'un vol : caché (opacité 0) tant que la copie vole vers lui.
    func flightTarget(_ id: String) -> some View {
        modifier(FlightTarget(id: id))
    }

    /// Couche de vol à la racine d'une fenêtre : au-dessus de tout, sans clic ; donne le centre à tout le contenu.
    func flightLayer(_ center: FlightCenter) -> some View {
        modifier(FlightLayerModifier(center: center))
    }
}

// MARK: - Vues

private struct FlightTarget: ViewModifier {
    let id: String
    @Environment(\.flightCenter) private var center

    func body(content: Content) -> some View {
        content.modifier(FlightHiding(id: id, center: center ?? .idle))
    }
}

private struct FlightHiding: ViewModifier {
    let id: String
    @ObservedObject var center: FlightCenter

    func body(content: Content) -> some View {
        content.opacity(center.hidden.contains(id) ? 0 : 1)
    }
}

private struct FlightLayerModifier: ViewModifier {
    let center: FlightCenter
    @Environment(\.motionMode) private var motionMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let mode = MotionMode.effective(motionMode, reduceMotion: reduceMotion)
        content
            .environment(\.flightCenter, center)
            .overlay {
                FlightLayerView(center: center)
                    .allowsHitTesting(false)
                    .ignoresSafeArea()
                    .accessibilityHidden(true)
            }
            .onAppear { center.mode = mode }
            .onChange(of: mode) { center.mode = $0 }
    }
}

private struct FlightLayerView: View {
    @ObservedObject var center: FlightCenter

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
            ForEach(center.flights) { flight in
                FlightSprite(flight: flight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(FlightProbe(id: FlightCenter.layerID, isLayer: true).environment(\.flightCenter, center))
    }
}

/// Une copie qui vole : part du départ, va à l'arrivée avec le ressort doux (une seule fois, à son apparition).
private struct FlightSprite: View {
    let flight: FlightCenter.Flight
    @State private var landed = false

    var body: some View {
        FlightContentView(content: flight.content)
            .modifier(FlightPath(from: flight.from, to: flight.to, scales: flight.content.scales,
                                 progress: landed ? 1 : 0))
            .onAppear { withAnimation(Motion.spring(.doux)) { landed = true } }
    }
}

/// Place de la copie à `progress` : à la taille d'arrivée mise à l'échelle (ou à la taille courante, fond de carte).
private struct FlightPath: ViewModifier, Animatable {
    let from: CGRect
    let to: CGRect
    let scales: Bool
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let rect = FlightGeometry.rect(at: progress, from: from, to: to)
        let size = scales ? to.size : rect.size
        let scale = scales && to.width > 0 ? rect.width / to.width : 1
        content
            .frame(width: max(size.width, 0), height: max(size.height, 0))
            .scaleEffect(scale)
            .position(x: rect.midX, y: rect.midY)
    }
}

/// Vue d'AppKit posée derrière une vue mesurée (ou sous toute la couche) : s'inscrit auprès du centre quand elle
/// entre dans une fenêtre, se retire quand elle en sort. Jamais touchée par la souris (ni clic ni dépôt).
private struct FlightProbe: NSViewRepresentable {
    let id: String
    let isLayer: Bool
    @Environment(\.flightCenter) private var center

    func makeNSView(context: Context) -> FlightProbeView {
        let view = FlightProbeView()
        view.configure(id: id, isLayer: isLayer, center: center)
        return view
    }

    func updateNSView(_ view: FlightProbeView, context: Context) {
        view.configure(id: id, isLayer: isLayer, center: center)
    }

    static func dismantleNSView(_ view: FlightProbeView, coordinator: ()) {
        view.configure(id: view.id, isLayer: view.isLayer, center: nil)
    }
}

final class FlightProbeView: NSView {
    private(set) var id = ""
    private(set) var isLayer = false
    private weak var center: FlightCenter?
    /// Fermeture de la fenêtre (couche seulement) ; retiré dès que la vue quitte sa fenêtre (`attach`).
    private var closeObserver: NSObjectProtocol?

    /// Origine en haut à gauche, comme la couche SwiftUI qu'elle mesure.
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(id: String, isLayer: Bool, center: FlightCenter?) {
        guard id != self.id || isLayer != self.isLayer || center !== self.center else { return }
        self.center?.unregister(self.id, view: self)
        self.id = id
        self.isLayer = isLayer
        self.center = center
        attach()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attach()
    }

    private func attach() {
        if let closeObserver { NotificationCenter.default.removeObserver(closeObserver) }
        closeObserver = nil
        guard let center, !id.isEmpty else { return }
        guard let window else {
            center.unregister(id, view: self)
            return
        }
        center.register(id, view: self)
        if isLayer {
            closeObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak center] _ in
                center?.cancelAll()
            }
        }
    }
}
