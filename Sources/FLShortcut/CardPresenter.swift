// Cartes au lieu des feuilles : les fiches (raccourci, touche d'une action de FL, guide, modèles, Communauté) sont des
// cartes de verre qui sortent de la ligne cliquée (sinon du centre) et y retournent, sur un voile de verre dépoli.
// Vraie modale : tout ce qui est derrière est désactivé (ses raccourcis clavier aussi) et caché à VoiceOver, la
// fenêtre ne se ferme pas pendant une carte ; Échap = bouton Annuler de la carte, Entrée = son bouton principal, clic
// sur le voile = annuler. Hauteur au plus celle de la fenêtre moins 48 : le contenu défile au-delà.
// File : une seule carte à la fois ; une carte demandée pendant qu'une autre est ouverte la ferme d'abord ; demandée
// pendant une fermeture, elle attend la fin ; fermer est sans effet si rien n'est ouvert ; fenêtre fermée ou créateur
// ouvert : tout est oublié.
import AppKit
import SwiftUI

enum CardKind {
    case editRemap(Remap, isNew: Bool)
    case editCatalog(CatalogRow, notice: String?)
    case guide(page: Int)
    case templates
    case communityShare(Share)
    case communityCompose
    case communityReport(Share)
}

struct CardRequest: Identifiable {
    let id = UUID()
    let kind: CardKind
    /// Cadre de départ dans la couche de vol (ligne cliquée) ; nil : la carte sort du centre.
    let source: String?
    /// Contenu de la carte (la fiche), construit quand elle s'ouvre.
    var content: (() -> AnyView)? = nil
    /// Appelé une fois la carte fermée (fin de la fermeture, ou tout oublié).
    var onClose: (() -> Void)? = nil
}

struct CardQueue {
    private(set) var current: CardRequest?
    private(set) var closing = false
    private(set) var waiting: [CardRequest] = []

    /// Rien d'ouvert : la carte s'ouvre. Une carte ouverte : elle se ferme d'abord. Une fermeture en cours : attente.
    mutating func request(_ request: CardRequest) {
        if current == nil {
            current = request
            return
        }
        waiting.append(request)
        closing = true
    }

    /// Ferme la carte ouverte (sans effet si rien n'est ouvert ou si elle se ferme déjà).
    mutating func close() {
        guard current != nil else { return }
        closing = true
    }

    /// Fermeture finie : la carte suivante, s'il y en a une, s'ouvre. Sans effet si rien ne se fermait.
    mutating func closeFinished() {
        guard closing || current == nil else { return }
        closing = false
        current = waiting.isEmpty ? nil : waiting.removeFirst()
    }

    /// Fenêtre fermée pendant une carte : plus rien d'ouvert ni d'attendu.
    mutating func reset() {
        current = nil
        closing = false
        waiting = []
    }
}

// MARK: - Présentateur

final class CardPresenter: ObservableObject {
    @Published private(set) var queue = CardQueue()

    var isPresenting: Bool { queue.current != nil }

    func present(_ request: CardRequest) {
        let wasOpen = queue.current != nil, wasClosing = queue.closing
        queue.request(request)
        if !wasOpen { InterfaceSound.play(.cardOpen) } else if !wasClosing { InterfaceSound.play(.cardClose) }
    }

    /// Ferme la carte ouverte (sans effet si rien n'est ouvert ou si elle se ferme déjà).
    func dismiss() {
        guard queue.current != nil, !queue.closing else { return }
        queue.close()
        InterfaceSound.play(.cardClose)
    }

    /// Ferme cette carte-là seulement si c'est elle qui est ouverte.
    func dismiss(_ id: UUID) {
        guard queue.current?.id == id else { return }
        dismiss()
    }

    /// Fin de la fermeture (l'hôte, quand la carte est rentrée) : la carte suivante s'ouvre, s'il y en a une.
    func closeFinished() {
        guard queue.closing else { return }
        let closed = queue.current
        queue.closeFinished()
        closed?.onClose?()
        if queue.current != nil { InterfaceSound.play(.cardOpen) }
    }

    /// Fenêtre fermée ou créateur ouvert : tout est oublié tout de suite.
    func reset() {
        let open = [queue.current].compactMap { $0 } + queue.waiting
        queue.reset()
        for request in open { request.onClose?() }
    }
}

// MARK: - Environnement

private struct CardPresenterKey: EnvironmentKey {
    static let defaultValue: CardPresenter? = nil
}

private struct CardDismissKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

private struct CardMaxHeightKey: EnvironmentKey {
    static let defaultValue: CGFloat = .infinity
}

extension EnvironmentValues {
    /// Présentateur de cartes de la fenêtre (nil hors de la fenêtre principale).
    var cardPresenter: CardPresenter? {
        get { self[CardPresenterKey.self] }
        set { self[CardPresenterKey.self] = newValue }
    }

    /// Ferme la carte où se trouve la vue (remplace `dismiss` des anciennes feuilles).
    var cardDismiss: () -> Void {
        get { self[CardDismissKey.self] }
        set { self[CardDismissKey.self] = newValue }
    }

    /// Hauteur au plus de la carte où se trouve la vue : une fiche qui défile déjà elle-même s'y tient (une seule
    /// barre de défilement). Hors d'une carte : sans limite.
    var cardMaxHeight: CGFloat {
        get { self[CardMaxHeightKey.self] }
        set { self[CardMaxHeightKey.self] = newValue }
    }
}

extension View {
    /// Hôte des cartes à la racine de la fenêtre (dans la couche de vol, pour lire les cadres).
    func cardHost(_ presenter: CardPresenter) -> some View {
        modifier(CardHost(presenter: presenter))
    }
}

// MARK: - Hôte

private struct CardHost: ViewModifier {
    @ObservedObject var presenter: CardPresenter
    @Environment(\.flightCenter) private var flights
    @Environment(\.motionMode) private var motionMode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 0 : la carte est au cadre de départ (voile transparent) ; 1 : à sa place.
    @State private var progress: CGFloat = 0
    @State private var contentShown = false
    @State private var source: CGRect?
    @State private var target: CGRect?
    /// Carte posée : son verre est le fond de la fiche elle-même (il suit sa hauteur quand elle change : type changé,
    /// conflits affichés, fenêtre redimensionnée) ; avant et pendant la fermeture, c'est `CardPath` qui le dessine.
    @State private var landed = false

    static let placeID = "carte.place"

    func body(content: Content) -> some View {
        let presenting = presenter.isPresenting
        content
            .disabled(presenting)
            .accessibilityHidden(presenting)
            .overlay {
                if let request = presenter.queue.current {
                    cardLayer(request).id(request.id)
                }
            }
            .environment(\.cardPresenter, presenter)
            .onChange(of: presenter.queue.current?.id) { id in
                if id != nil { open() }
            }
            .onChange(of: presenter.queue.closing) { closing in
                if closing { close() }
            }
            .onChange(of: presenting) { on in
                // La fenêtre ne se ferme pas pendant une carte (bouton rouge et ⌘W inactifs).
                guard let window = AppResume.shared.editorWindow else { return }
                if on { window.styleMask.remove(.closable) } else { window.styleMask.insert(.closable) }
            }
    }

    private var mode: MotionMode { MotionMode.effective(motionMode, reduceMotion: reduceMotion) }

    private func cardLayer(_ request: CardRequest) -> some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return ZStack {
            // Voile de verre dépoli, légèrement assombri ; un clic dessus = annuler.
            Rectangle().fill(.ultraThinMaterial)
                .overlay(Color.black.opacity(0.18))
                .opacity(progress)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { presenter.dismiss() }
                .accessibilityHidden(true)
            // Fond de la carte : du cadre de départ à sa place (mêmes coordonnées que la couche de vol).
            Color.clear
                .modifier(CardPath(from: source ?? Self.center(of: target), to: target ?? .zero, progress: progress))
                .opacity(target == nil || landed ? 0 : 1)
                .ignoresSafeArea()
                .allowsHitTesting(false)
            // La fiche, à sa place, qui défile au-delà de la hauteur de la fenêtre.
            GeometryReader { geo in
                let maxHeight = max(geo.size.height - 48, 160)
                ScrollView {
                    (request.content?() ?? AnyView(EmptyView()))
                        .environment(\.cardDismiss, { presenter.dismiss() })
                        .environment(\.cardMaxHeight, maxHeight)
                }
                .frame(maxHeight: maxHeight)
                .fixedSize(horizontal: true, vertical: true)
                .clipShape(shape)
                .frameProbe(Self.placeID)
                .opacity(contentShown ? 1 : 0)
                .blur(radius: contentShown || mode != .full ? 0 : 8)
                .background {
                    Color.clear
                        .glassSurface(shape)
                        .shadow(color: Color.black.opacity(0.25), radius: 24, y: 10)
                        .opacity(landed ? 1 : 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    /// Carte demandée : cadres lus après la mise en page, puis elle grandit depuis la ligne (ressort doux) ; la
    /// fiche apparaît quand la carte a fait 40 % du chemin ; une fois posée, son verre passe sous la fiche.
    private func open() {
        let id = presenter.queue.current?.id
        progress = 0
        contentShown = false
        landed = false
        target = nil
        source = presenter.queue.current?.source.flatMap { flights?.frame(of: $0) }
        DispatchQueue.main.async {
            target = flights?.frame(of: Self.placeID)
            let duration: TimeInterval
            switch mode {
            case .full where target != nil:
                withAnimation(Motion.spring(.doux)) { progress = 1 }
                withAnimation(Motion.spring(.vif).delay(0.4 * Motion.settleTime(.doux))) { contentShown = true }
                duration = Motion.settleTime(.doux)
            case .frozen:
                progress = 1
                contentShown = true
                duration = 0
            default:
                withAnimation(Motion.reduced) {
                    progress = 1
                    contentShown = true
                }
                duration = Motion.reducedDuration
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
                guard presenter.queue.current?.id == id, !presenter.queue.closing else { return }
                landed = true
                Self.focusFirstField(in: flights?.windowFrame(of: Self.placeID))
            }
        }
    }

    /// Fermeture : la fiche part d'abord, puis la carte rentre dans la ligne ; la suivante s'ouvre ensuite.
    private func close() {
        let id = presenter.queue.current?.id
        source = presenter.queue.current?.source.flatMap { flights?.frame(of: $0) }
        // La carte rentre depuis là où est la fiche maintenant (elle a pu changer de taille depuis l'ouverture).
        target = flights?.frame(of: Self.placeID) ?? target
        landed = false
        let duration: TimeInterval
        switch mode {
        case .full:
            withAnimation(Motion.spring(.vif)) { contentShown = false }
            withAnimation(Motion.spring(.doux)) { progress = 0 }
            duration = Motion.settleTime(.doux)
        case .reduced:
            withAnimation(Motion.reduced) {
                contentShown = false
                progress = 0
            }
            duration = Motion.reducedDuration
        case .frozen:
            contentShown = false
            progress = 0
            duration = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            guard presenter.queue.current?.id == id else { return }
            presenter.closeFinished()
        }
    }

    /// Focus dans la carte posée, comme dans une feuille de macOS : son champ de texte le plus haut (champs actifs
    /// et visibles dans le cadre de la carte, `card`, coordonnées de la fenêtre ; tout ce qui est derrière est
    /// désactivé). Cadre inconnu : rien. Déjà dans un de ses champs : rien ne change.
    private static func focusFirstField(in card: CGRect?) {
        guard let card, let window = AppResume.shared.editorWindow, let root = window.contentView else { return }
        var fields: [NSTextField] = []
        var stack: [NSView] = [root]
        while let view = stack.popLast() {
            if let field = view as? NSTextField, field.isEditable, field.isEnabled, !field.isHiddenOrHasHiddenAncestor {
                let frame = field.convert(field.bounds, to: nil)
                if card.contains(CGPoint(x: frame.midX, y: frame.midY)) { fields.append(field) }
            }
            stack.append(contentsOf: view.subviews)
        }
        if let editor = window.firstResponder as? NSText, let owner = editor.delegate as? NSTextField,
           fields.contains(owner) { return }
        let top = fields.max { a, b in
            let fa = a.convert(a.bounds, to: nil), fb = b.convert(b.bounds, to: nil)
            return fa.maxY != fb.maxY ? fa.maxY < fb.maxY : fa.minX > fb.minX
        }
        if let top { window.makeFirstResponder(top) }
    }

    /// Départ sans ligne : un rectangle de 60 % au milieu de la place de la carte.
    static func center(of target: CGRect?) -> CGRect {
        guard let t = target else { return .zero }
        return CGRect(x: t.midX - t.width * 0.3, y: t.midY - t.height * 0.3, width: t.width * 0.6,
                      height: t.height * 0.6)
    }
}

/// Fond de verre de la carte au rectangle de `progress` (du départ à la place).
private struct CardPath: ViewModifier, Animatable {
    let from: CGRect
    let to: CGRect
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func body(content: Content) -> some View {
        let rect = FlightGeometry.rect(at: progress, from: from, to: to)
        let shape = RoundedRectangle(cornerRadius: min(22, rect.height / 2, rect.width / 2), style: .continuous)
        return ZStack(alignment: .topLeading) {
            content
            Color.clear
                .glassSurface(shape)
                .shadow(color: Color.black.opacity(0.25), radius: 24, y: 10)
                .frame(width: max(rect.width, 0), height: max(rect.height, 0))
                .offset(x: rect.minX, y: rect.minY)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
