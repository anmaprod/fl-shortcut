// Moteur de mouvement : toutes les animations de l'app passent par lui (aucune valeur de ressort ni de durée
// ailleurs, sauf les transitions de page de GlassStyle). Trois ressorts comme chez Apple, tous ralentis par le mode
// capture de la CI (`DebugSnapshot.slowMotion`) :
// - vif (0,35 ; 0,78) : boutons, pastilles, gouttes qui rentrent, survol ;
// - doux (0,5 ; 1) : pages, menu, cartes, vols ;
// - liquide (0,55 ; 0,62) : gouttes de verre seulement.
// Durées pures et testées (`settle`) : temps pour qu'un ressort soit posé, pour les minuteurs (macOS 13 n'a pas de
// rappel de fin d'animation) et les enchaînements. Gel (`MotionPolicy`) : la fenêtre principale ne bouge plus quand
// FL est devant (l'app n'est pas active) ; le menu, l'Organiser, le guide des autorisations, le badge de pause, la
// bulle d'aide, la barre d'enregistrement et les vols restent vivants (ils servent pendant que FL est devant).
import AppKit
import SwiftUI

// MARK: - Ressorts et durées

/// Les trois ressorts de l'app.
enum MotionSpring {
    case vif, doux, liquide

    /// Temps de réponse (s), avant le ralenti.
    var response: Double {
        switch self {
        case .vif: return 0.35
        case .doux: return 0.5
        case .liquide: return 0.55
        }
    }

    /// Amortissement : 1 = sans rebond.
    var damping: Double {
        switch self {
        case .vif: return 0.78
        case .doux: return 1
        case .liquide: return 0.62
        }
    }
}

extension Motion {
    /// Ralenti du mode capture (1 = vitesse normale, 10 = dix fois plus lent).
    private static var slow: Double { DebugSnapshot.slowMotion }

    /// Un des trois ressorts, ralenti s'il le faut.
    static func spring(_ kind: MotionSpring) -> Animation {
        .spring(response: kind.response * slow, dampingFraction: kind.damping)
    }

    /// Temps pour qu'un ressort soit posé (écart final sous 1/1000) : ω0 = 2π / réponse ; sous-amorti,
    /// ln(1000) / (ζ ω0) ; amortissement critique, 9,2 / ω0. Pur (sans ralenti).
    static func settle(response: Double, damping: Double) -> TimeInterval {
        guard response > 0 else { return 0 }
        let omega = 2 * Double.pi / response
        if damping < 1 { return log(1000) / (max(damping, 0.01) * omega) }
        return 9.2 / omega
    }

    /// Temps pour que ce ressort soit posé, ralenti compris (minuteurs, enchaînements, sûretés).
    static func settleTime(_ kind: MotionSpring) -> TimeInterval {
        settle(response: kind.response * slow, damping: kind.damping)
    }

    /// Position du ressort au temps `t` (0 au départ, 1 une fois posé), comme SwiftUI la dessine. Pur.
    static func springValue(at t: TimeInterval, response: Double, damping: Double) -> Double {
        guard t > 0, response > 0 else { return 0 }
        if t >= settle(response: response, damping: damping) { return 1 }
        let omega = 2 * Double.pi / response
        if damping < 1 {
            let zeta = max(damping, 0.01)
            let damped = omega * (1 - zeta * zeta).squareRoot()
            return 1 - exp(-zeta * omega * t) * (cos(damped * t) + zeta * omega / damped * sin(damped * t))
        }
        return 1 - exp(-omega * t) * (1 + omega * t)
    }

    /// Animation d'AppKit (cadre ou fondu d'une fenêtre) : courbe d'AppKit `easeInEaseOut`, jamais de ressort.
    static var appKitDuration: TimeInterval { 0.3 * slow }

    /// « Réduire les animations » : un fondu court, sans vol ni rebond (jamais au ralenti : voir `reduce`).
    static let reducedDuration: TimeInterval = 0.18
    static let reduced = Animation.easeInOut(duration: reducedDuration)

    /// Changement d'état ordinaire (notification).
    static var smooth: Animation { .easeInOut(duration: 0.2 * slow) }

    /// Départ rapide (option du menu qui repart, icône qui se referme) : court, en accélérant.
    static var exitDuration: TimeInterval { 0.16 * slow }
    static var exit: Animation { .easeIn(duration: exitDuration) }

    /// Couleurs qui coulent : lueur de fond d'une page ou du guide qui passe d'une couleur à l'autre.
    static var colorFlow: Animation { .easeInOut(duration: 0.6 * slow) }

    /// Délai d'un élément qui arrive juste après le précédent (`index` 0 : le premier), ralenti compris.
    static func stagger(_ index: Int, start: Double = 0.06, step: Double = 0.035) -> TimeInterval {
        (start + Double(max(0, index)) * step) * slow
    }

    /// Pages, menu, cartes, vols : ressort doux, sans rebond.
    static var morph: Animation { spring(.doux) }

    /// Survol et prise d'un élément : ressort vif.
    static var lift: Animation { spring(.vif) }
}

// MARK: - Gel

/// Là où l'animation se joue : seule la fenêtre principale (et le créateur qu'elle contient) peut geler.
enum MotionSurface {
    case window, menu, organiser, guide, badge, hint, recording, flight
}

enum MotionMode {
    /// Tout le mouvement.
    case full
    /// « Réduire les animations » : fondus courts seulement.
    case reduced
    /// Rien ne bouge (fenêtre principale pendant que FL est devant) : changements instantanés.
    case frozen

    /// Mode d'une vue : gelé si sa porte (`motionGate`) l'a gelée ; sinon « Réduire les animations » (hors
    /// ralenti) ; sinon tout le mouvement. Hors porte, l'environnement vaut `.full`.
    static func effective(_ environment: MotionMode, reduceMotion: Bool) -> MotionMode {
        if environment == .frozen { return .frozen }
        return reduceMotion && DebugSnapshot.slowMotion == 1 ? .reduced : environment
    }
}

enum MotionPolicy {
    /// Règle pure : la fenêtre principale gèle quand l'app n'est pas active et qu'elle n'est pas la fenêtre clé
    /// (FL devant) ; tout le reste reste vivant. Ralenti actif : jamais réduit (pour filmer le vrai mouvement).
    static func mode(reduceMotion: Bool, slowMotion: Double, surface: MotionSurface, isKey: Bool,
                     appActive: Bool) -> MotionMode {
        if surface == .window && !appActive && !isKey { return .frozen }
        if reduceMotion && slowMotion == 1 { return .reduced }
        return .full
    }
}

private struct MotionModeKey: EnvironmentKey {
    static let defaultValue = MotionMode.full
}

extension EnvironmentValues {
    /// Mode posé par la porte de la fenêtre (`motionGate`) ; `.full` hors porte.
    var motionMode: MotionMode {
        get { self[MotionModeKey.self] }
        set { self[MotionModeKey.self] = newValue }
    }
}

/// Porte du mouvement d'une fenêtre : pose `motionMode` pour tout son contenu ; gelée, elle retire toute animation
/// (transaction sans animation, et `disablesAnimations` coupe aussi les `.animation(_:value:)` internes). L'état
/// actif vient de `controlActiveState` (comme GlassSurface) : `.inactive` quand l'app n'est pas active, `.key` pour
/// la fenêtre clé ; SwiftUI le met à jour, aucun observateur à retirer.
private struct MotionGate: ViewModifier {
    let surface: MotionSurface
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let mode = MotionPolicy.mode(reduceMotion: reduceMotion, slowMotion: DebugSnapshot.slowMotion,
                                     surface: surface, isKey: activeState == .key,
                                     appActive: activeState != .inactive)
        content
            .environment(\.motionMode, mode)
            .transaction { transaction in
                guard mode == .frozen else { return }
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
    }
}

extension View {
    /// Porte du mouvement à la racine d'une fenêtre (voir `MotionGate`).
    func motionGate(_ surface: MotionSurface) -> some View {
        modifier(MotionGate(surface: surface))
    }
}

// MARK: - Reflet qui suit la souris

/// Reflet de verre : une lueur blanche très légère centrée sur la souris, découpée à la forme de l'élément, seulement
/// pendant le survol. Rien hors survol, sur un élément inactif, gelé ou en mouvement réduit.
private struct GlassHighlight<S: Shape>: ViewModifier {
    let shape: S
    @State private var point: CGPoint?
    @Environment(\.motionMode) private var mode
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var isEnabled

    static var radius: CGFloat { 120 }

    func body(content: Content) -> some View {
        let live = isEnabled && MotionMode.effective(mode, reduceMotion: reduceMotion) == .full
        content
            .overlay {
                if live, let point {
                    GeometryReader { geo in
                        let size = geo.size
                        shape.fill(RadialGradient(
                            colors: [Color.white.opacity(0.16), Color.white.opacity(0)],
                            center: UnitPoint(x: size.width > 0 ? point.x / size.width : 0.5,
                                              y: size.height > 0 ? point.y / size.height : 0.5),
                            startRadius: 0, endRadius: Self.radius))
                    }
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                    .transaction { $0.animation = nil }      // collé à la souris, jamais en retard
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): point = location
                case .ended: point = nil
                }
            }
    }
}

extension View {
    /// Reflet qui suit la souris, découpé en rectangle arrondi (voir `GlassHighlight`).
    func glassHighlight(cornerRadius: CGFloat) -> some View {
        modifier(GlassHighlight(shape: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)))
    }

    /// Reflet qui suit la souris, découpé à cette forme (capsule d'un bouton).
    func glassHighlight<S: Shape>(_ shape: S) -> some View {
        modifier(GlassHighlight(shape: shape))
    }
}

// MARK: - Listes

/// Listes (`List`, dessinées par AppKit) : un ajout, une suppression, un déplacement ou un filtrage glisse (AppKit
/// anime lui-même ses lignes) au lieu de sauter ; au-delà de `limit` lignes changées d'un coup, changement direct.
enum ListMotion {
    static let limit = 60

    static func animates(changes: Int) -> Bool {
        changes > 0 && changes <= limit
    }

    /// Lignes changées entre deux listes : parties + arrivées + gardées mais déplacées (hors de la plus longue suite
    /// gardée dans le même ordre). Au-delà de `limit`, le compte s'arrête (inutile d'aller plus loin).
    static func changes<ID: Hashable>(from old: [ID], to new: [ID]) -> Int {
        let oldSet = Set(old), newSet = Set(new)
        let kept = old.filter { newSet.contains($0) }
        let removed = old.count - kept.count
        let added = new.filter { !oldSet.contains($0) }.count
        guard removed + added <= limit else { return removed + added }
        let keptNew = new.filter { oldSet.contains($0) }
        return removed + added + kept.count - longestCommonRun(kept, keptNew)
    }

    /// Plus longue sous-suite commune (programmation dynamique sur deux lignes).
    private static func longestCommonRun<ID: Hashable>(_ a: [ID], _ b: [ID]) -> Int {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        if a == b { return a.count }
        var previous = [Int](repeating: 0, count: b.count + 1)
        for x in a {
            var current = [Int](repeating: 0, count: b.count + 1)
            for (j, y) in b.enumerated() {
                current[j + 1] = x == y ? previous[j] + 1 : max(previous[j + 1], current[j])
            }
            previous = current
        }
        return previous[b.count]
    }
}

/// Change une liste : animé (ressort vif ; fondu court en mouvement réduit) si peu de lignes changent, sinon direct.
@discardableResult
func withListAnimation<R>(changes: Int, _ body: () throws -> R) rethrows -> R {
    guard ListMotion.animates(changes: changes) else {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        return try withTransaction(transaction, body)
    }
    return try withAnimation(Motion.reduce ? Motion.reduced : Motion.spring(.vif), body)
}
