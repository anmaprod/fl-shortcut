// Style « Liquid Glass » : verre natif sur macOS 26 (SDK Xcode 26, Swift 6.2), repli en matériau translucide
// sur macOS 13–15 ou avec un compilateur plus ancien. Audit 05 : touches affichées avec leur nom en clair.
// Mouvement : ressorts courts façon macOS (réponse 0,25–0,45 s, peu de rebond), remplacés par un simple fondu
// quand « Réduire les animations » est activé (Réglages › Accessibilité › Affichage).
import AppKit
import SwiftUI

// MARK: - Mouvement

enum Motion {
    /// Changement d'état ordinaire (listes, bandeaux, feuilles).
    static let smooth = Animation.spring(response: 0.36, dampingFraction: 0.86)
    /// Retour immédiat (sélection, puces, survol appuyé).
    static let snappy = Animation.spring(response: 0.26, dampingFraction: 0.9)
    /// Apparition qui « se pose » (touches capturées, notification).
    static let bouncy = Animation.spring(response: 0.44, dampingFraction: 0.72)
    /// Survol.
    static let hover = Animation.easeOut(duration: 0.14)
    /// Remplacement quand l'utilisateur a demandé moins de mouvement.
    static let reduced = Animation.easeInOut(duration: 0.18)

    static var reduce: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// `withAnimation` qui respecte « Réduire les animations ».
    static func run(_ animation: Animation = smooth, _ body: () -> Void) {
        withAnimation(reduce ? reduced : animation, body)
    }

    /// Transition remplacée par un fondu quand le mouvement est réduit.
    static func transition(_ t: AnyTransition) -> AnyTransition { reduce ? .opacity : t }

    /// Apparition depuis le bas, légèrement réduite (notifications, bandeaux).
    static var rise: AnyTransition {
        transition(.move(edge: .bottom).combined(with: .opacity).combined(with: .scale(scale: 0.94, anchor: .bottom)))
    }

    /// Apparition « posée » (éléments qui arrivent dans une liste).
    static var pop: AnyTransition {
        transition(.asymmetric(insertion: .scale(scale: 0.96).combined(with: .opacity),
                               removal: .opacity.combined(with: .scale(scale: 0.98))))
    }
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? Motion.reduced : animation, value: value)
    }
}

/// Pulsation d'opacité infinie, confinée à la vue qui la porte : elle démarre à l'apparition et disparaît
/// avec la vue (un `repeatForever` piloté par un état du parent ne s'arrête pas de façon fiable : relecture 11).
/// Rien ne bouge si « Réduire les animations » est activé.
private struct PulseModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let duration: Double
    let low: Double
    @State private var dimmed = false

    func body(content: Content) -> some View {
        content
            .opacity(dimmed ? low : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: duration).repeatForever(autoreverses: true)) { dimmed = true }
            }
    }
}

extension View {
    /// `.animation(_:value:)` qui respecte « Réduire les animations ».
    func motion<V: Equatable>(_ animation: Animation = Motion.smooth, value: V) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
    }

    /// Pulsation douce (attente, enregistrement). À poser sur une vue insérée / retirée par un `if` :
    /// la retirer arrête l'animation.
    func pulsing(duration: Double = 1.0, low: Double = 0.45) -> some View {
        modifier(PulseModifier(duration: duration, low: low))
    }

    /// Petit rebond du symbole SF quand `value` change (macOS 14+).
    @ViewBuilder
    func bounceSymbol<V: Equatable>(on value: V) -> some View {
        #if compiler(>=5.9)
        if #available(macOS 14.0, *) {
            self.symbolEffect(.bounce, value: value)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

/// Ligne cliquable : léger enfoncement à l'appui, comme les listes de Réglages Système.
struct PressableRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !Motion.reduce ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .animation(Motion.snappy, value: configuration.isPressed)
    }
}

/// Regroupe des éléments en verre pour qu'ils se fondent entre eux comme sur macOS 26 (GlassEffectContainer).
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 10
    @ViewBuilder let content: () -> Content

    var body: some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content() }
        } else {
            content()
        }
        #else
        content()
        #endif
    }
}

// MARK: - Verre

extension View {
    /// Carte en verre (arrondie).
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 18) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(.regular, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            self.fallbackGlass(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        #else
        self.fallbackGlass(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        #endif
    }

    /// Pastille en verre (capsule). `interactive` : le verre réagit au pointeur (macOS 26).
    @ViewBuilder
    func glassCapsule(interactive: Bool = false) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.glassEffect(interactive ? Glass.regular.interactive() : Glass.regular, in: Capsule())
        } else {
            self.fallbackGlass(Capsule())
        }
        #else
        self.fallbackGlass(Capsule())
        #endif
    }

    /// Bouton principal (accent) : verre teinté sur macOS 26, bouton accentué ailleurs.
    @ViewBuilder
    func primaryGlassButton() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glassProminent)
        } else {
            self.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
        }
        #else
        self.buttonStyle(.borderedProminent).buttonBorderShape(.capsule)
        #endif
    }

    /// Bouton secondaire en verre.
    @ViewBuilder
    func secondaryGlassButton() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            self.buttonStyle(.glass)
        } else {
            self.buttonStyle(.bordered).buttonBorderShape(.capsule)
        }
        #else
        self.buttonStyle(.bordered).buttonBorderShape(.capsule)
        #endif
    }

    private func fallbackGlass<S: InsettableShape>(_ shape: S) -> some View {
        self
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(Color.white.opacity(0.35), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.08), radius: 2, y: 1)
    }
}

/// Une touche de clavier : symbole + nom en clair (« ⌃ ctrl »), comme dans la simulation validée.
struct KeyCap: View {
    let symbol: String
    var name: String? = nil
    var large = false

    var body: some View {
        VStack(spacing: 2) {
            Text(symbol)
                .font(.system(size: large ? 17 : 13, weight: .semibold, design: .rounded))
            if large, let name {
                Text(name)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: large ? 44 : 26, minHeight: large ? 46 : 26)
        .padding(.horizontal, large ? 8 : 6)
        .background(
            RoundedRectangle(cornerRadius: large ? 10 : 7, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.85))
                .shadow(color: .black.opacity(0.12), radius: 0, y: 1.5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: large ? 10 : 7, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }
}

/// Une touche à dessiner. `id` stable (modificateur ou touche finale) pour animer l'arrivée d'une touche
/// sans redessiner les autres.
struct CapInfo: Identifiable, Hashable {
    let id: String
    let symbol: String
    let name: String
}

extension KeyCombo {
    /// Touches à dessiner, dans l'ordre macOS (⌃ ⌥ ⇧ ⌘ puis la touche).
    var caps: [CapInfo] {
        var out: [CapInfo] = []
        if control { out.append(CapInfo(id: "ctrl", symbol: "⌃", name: "ctrl")) }
        if option { out.append(CapInfo(id: "option", symbol: "⌥", name: "option")) }
        if shift { out.append(CapInfo(id: "shift", symbol: "⇧", name: "maj")) }
        if command { out.append(CapInfo(id: "cmd", symbol: "⌘", name: "cmd")) }
        out.append(CapInfo(id: "key-\(keyCode)", symbol: KeyNames.name(for: keyCode), name: ""))
        return out
    }

    /// Texte lu par VoiceOver : « contrôle option R ».
    var spoken: String {
        var parts: [String] = []
        if control { parts.append("contrôle") }
        if option { parts.append("option") }
        if shift { parts.append("majuscule") }
        if command { parts.append("commande") }
        parts.append(KeyNames.name(for: keyCode))
        return parts.joined(separator: " ")
    }
}

/// Rangée de touches.
struct KeyCaps: View {
    let combo: KeyCombo?
    var large = false
    var placeholder = "—"

    var body: some View {
        HStack(spacing: large ? 6 : 4) {
            if let combo {
                ForEach(combo.caps) { cap in
                    KeyCap(symbol: cap.symbol, name: cap.name.isEmpty ? nil : cap.name, large: large)
                        .transition(Motion.transition(.scale(scale: 0.6).combined(with: .opacity)))
                }
            } else {
                Text(placeholder).foregroundStyle(.secondary)
            }
        }
        .motion(Motion.bouncy, value: combo)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(combo?.spoken ?? "Aucun raccourci")
    }
}

/// Description courte de chaque action (retours des tests utilisateurs : dire ce que fait l'action).
extension FLActionInfo {
    var detail: String {
        switch key {
        case "play": return "Lance ou met en pause la lecture"
        case "stop": return "Arrête la lecture"
        case "rec": return "Démarre ou arrête l'enregistrement"
        case "metro": return "Active ou coupe le métronome"
        case "count": return "Décompte avant l'enregistrement"
        case "loop": return "Enchaîne les prises sur la boucle"
        case "wait": return "Le REC démarre à la première note jouée"
        case "marker": return "Repère « bonne prise » à la position de lecture"
        case "arm": return "Prépare la piste du Mixer sélectionnée à enregistrer"
        case "tap": return "Tape le tempo en rythme"
        case "newpat": return "Crée un pattern vide et ouvre le Piano Roll"
        case "clone": return "Duplique le pattern en cours pour une variation"
        case "pnext": return "Passe au pattern suivant"
        case "pprev": return "Revient au pattern précédent"
        case "chnext": return "Instrument suivant, sans quitter le Piano Roll"
        case "chprev": return "Instrument précédent, sans quitter le Piano Roll"
        case "snap": return "Change le magnétisme : 1/4, 1/8, triolets…"
        case "quant": return "Aligne les notes de l'instrument sélectionné"
        case "presetnext": return "Preset suivant du plugin ouvert"
        case "presetprev": return "Preset précédent du plugin ouvert"
        case "mute": return "Coupe la piste du Mixer sélectionnée"
        case "solo": return "Écoute seulement la piste sélectionnée"
        case "unsolo": return "Réécoute tout le morceau"
        case "bypass": return "Compare la piste avec et sans effets"
        case "mono": return "Vérifie que le mix tient en mono"
        case "trnext": return "Sélectionne la piste suivante du Mixer"
        case "trprev": return "Sélectionne la piste précédente du Mixer"
        case "volup": return "Monte la piste sélectionnée"
        case "voldn": return "Baisse la piste sélectionnée"
        case "pl": return "Affiche la Playlist"
        case "cr": return "Affiche le Channel Rack"
        case "pr": return "Affiche le Piano Roll"
        case "mx": return "Affiche le Mixer"
        case "br": return "Affiche le Browser"
        case "plmx": return "Bascule entre la Playlist et le Mixer"
        case "undo": return "Annule la dernière action"
        case "redo": return "Rétablit l'action annulée"
        case "save": return "Sauvegarde le projet"
        default: return label
        }
    }
}
