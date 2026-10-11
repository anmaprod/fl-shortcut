// Styles communs, volontairement sobres : polices et couleurs système, aucun dégradé, aucune animation infinie.
// Liquid Glass (macOS 26) : seulement sur quelques surfaces flottantes (notification, boutons principaux), jamais
// ligne par ligne (une couche de verre par ligne coûtait cher : 8fb66a8). Le verre redevient opaque dès que la
// fenêtre n'est plus active (FL au premier plan) : rien à recalculer pendant que tu travailles dans FL.
// Réglable dans le menu Profil (« Effet Liquid Glass »). Audit 05 : touches affichées avec leur nom en clair.
// Mouvement : courtes transitions, remplacées par un simple fondu quand « Réduire les animations » est activé.
import AppKit
import SwiftUI

// MARK: - Mouvement

enum Motion {
    /// Changement d'état ordinaire (notification).
    static let smooth = Animation.easeInOut(duration: 0.2)
    /// Remplacement quand l'utilisateur a demandé moins de mouvement.
    static let reduced = Animation.easeInOut(duration: 0.15)

    static var reduce: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Transition remplacée par un fondu quand le mouvement est réduit.
    static func transition(_ t: AnyTransition) -> AnyTransition { reduce ? .opacity : t }

    /// Apparition depuis le bas (notification).
    static var rise: AnyTransition { transition(.move(edge: .bottom).combined(with: .opacity)) }
}

private struct MotionModifier<V: Equatable>: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let animation: Animation
    let value: V

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? Motion.reduced : animation, value: value)
    }
}

extension View {
    /// `.animation(_:value:)` qui respecte « Réduire les animations ».
    func motion<V: Equatable>(_ animation: Animation = Motion.smooth, value: V) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
    }
}

// MARK: - Liquid Glass

enum Appearance {
    /// Préférence « Effet Liquid Glass » (vrai par défaut ; sans effet avant macOS 26).
    static let glassKey = "liquidGlass"

    static var glassAvailable: Bool {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { return true }
        #endif
        return false
    }
}

/// Surface flottante : verre natif sur macOS 26 quand la préférence est active et la fenêtre au premier plan,
/// sinon fond opaque de fenêtre. Même structure de vue dans tous les cas (aucun arbre reconstruit au passage
/// FL ↔ FL Shortcut) : seul le paramètre du verre change.
struct GlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    @AppStorage(Appearance.glassKey) private var glassEnabled = true
    @Environment(\.controlActiveState) private var activeState

    private var live: Bool { glassEnabled && activeState != .inactive }

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            content
                .background(shape.fill(Color(nsColor: .windowBackgroundColor)).opacity(live ? 0 : 1))
                .glassEffect(live ? Glass.regular : Glass.identity, in: shape)
        } else {
            opaque(content)
        }
        #else
        opaque(content)
        #endif
    }

    private func opaque(_ content: Content) -> some View {
        content
            .background(shape.fill(Color(nsColor: .windowBackgroundColor)))
            .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }
}

/// Bouton principal : verre teinté sur macOS 26 (préférence active), bouton accentué sinon.
private struct PrimaryButtonStyleModifier: ViewModifier {
    @AppStorage(Appearance.glassKey) private var glassEnabled = true

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), glassEnabled {
            content.buttonStyle(.glassProminent)
        } else {
            content.buttonStyle(.borderedProminent)
        }
        #else
        content.buttonStyle(.borderedProminent)
        #endif
    }
}

/// Regroupe des surfaces de verre voisines : le système les dessine en une passe et les fait se fondre
/// entre elles (GlassEffectContainer, macOS 26). Ailleurs : simple conteneur.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
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

/// Bouton secondaire : verre sur macOS 26 (préférence active), bordé sinon.
private struct SecondaryButtonStyleModifier: ViewModifier {
    @AppStorage(Appearance.glassKey) private var glassEnabled = true

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *), glassEnabled {
            content.buttonStyle(.glass)
        } else {
            content.buttonStyle(.bordered)
        }
        #else
        content.buttonStyle(.bordered)
        #endif
    }
}

extension View {
    /// Bouton secondaire (Annuler, Changer…, Apprendre…).
    func secondaryButton() -> some View {
        modifier(SecondaryButtonStyleModifier())
    }

    /// Surface flottante en verre (voir GlassSurface).
    func glassSurface<S: InsettableShape>(_ shape: S) -> some View {
        modifier(GlassSurface(shape: shape))
    }

    /// Bouton principal (Valider, Continuer…).
    func primaryButton() -> some View {
        modifier(PrimaryButtonStyleModifier())
    }
}

// MARK: - Touches

/// Une touche de clavier, plate : symbole, et en grand le nom en clair (« ⌃ ctrl »).
struct KeyCap: View {
    let symbol: String
    var name: String? = nil
    var large = false

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: large ? 6 : 4, style: .continuous) }

    var body: some View {
        VStack(spacing: 1) {
            Text(symbol).font(.system(size: large ? 15 : 12, weight: .medium))
            if large, let name {
                Text(name).font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: large ? 34 : 20, minHeight: large ? 36 : 20)
        .padding(.horizontal, large ? 6 : 4)
        .background(shape.fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
        .accessibilityHidden(true)
    }
}

/// Une touche à dessiner. `id` stable (modificateur ou touche finale).
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

/// Rangée de touches (champ d'enregistrement, accueil). Statique : aucune animation.
struct KeyCaps: View {
    let combo: KeyCombo?
    var large = false
    var placeholder = "—"

    var body: some View {
        HStack(spacing: large ? 4 : 3) {
            if let combo {
                ForEach(combo.caps) { cap in
                    KeyCap(symbol: cap.symbol, name: cap.name.isEmpty ? nil : cap.name, large: large)
                }
            } else {
                Text(placeholder).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(combo?.spoken ?? "Aucun raccourci")
    }
}

/// Touche compacte d'une liste, comme dans Réglages › Clavier : le raccourci en texte dans un petit cadre.
/// `accent` : raccourci modifié.
struct KeyLabel: View {
    let combo: KeyCombo?
    var accent = false
    var placeholder = "Aucune"

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 5, style: .continuous) }

    var body: some View {
        Group {
            if let combo {
                Text(combo.display)
                    .foregroundStyle(accent ? Color.accentColor : Color.primary)
            } else {
                Text(placeholder).foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
        .lineLimit(1)
        .padding(.horizontal, 7)
        .frame(minWidth: 56, minHeight: 20)
        .background(shape.fill(Color.primary.opacity(0.05)))
        .overlay(shape.strokeBorder(accent ? Color.accentColor.opacity(0.5) : Color(nsColor: .separatorColor),
                                    lineWidth: 0.5))
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(combo?.spoken ?? placeholder)
    }
}

/// Description courte de chaque action (affichée en bulle d'aide).
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
        case "armon": return "Arme la piste sélectionnée, sans jamais la désarmer"
        case "recon": return "Allume le REC, sans jamais l'éteindre"
        default: return label
        }
    }
}
