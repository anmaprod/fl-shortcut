// Styles communs : polices et couleurs système, aucune animation infinie, aucun minuteur.
// Liquid Glass (macOS 26, WWDC25 219/310/323/356) : le verre est réservé à la couche de navigation et de contrôle
// qui flotte au-dessus du contenu (barre latérale et barre d'outils du système, pastille de statut, notification,
// avertissements, boutons, bulle d'aide), jamais ligne par ligne (une couche de verre par ligne coûtait cher :
// 8fb66a8) ni verre sur verre. La couleur va dans le contenu (icônes de rubrique, lavis en haut de page) : c'est
// elle que le verre réfracte et qui le rend visible. Le verre redevient opaque dès que la fenêtre n'est plus active
// (FL au premier plan) : rien à recalculer pendant que tu travailles dans FL. Réduire la transparence et Contraste
// élevé : le verre s'adapte tout seul, la fenêtre et le lavis redeviennent unis. Réglable dans le menu Profil
// (« Effet Liquid Glass ») : coupé, tout est opaque. Audit 05 : touches affichées avec leur nom en clair.
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

    /// Fenêtre translucide (le bureau se devine derrière) : macOS 15+, préférence active, transparence non réduite.
    /// Une seule règle pour le fond de la fenêtre, les listes posées dessus et le lavis : jamais l'un sans l'autre.
    static func translucentWindow(glass: Bool, reduceTransparency: Bool) -> Bool {
        guard glass, !reduceTransparency else { return false }
        if #available(macOS 15.0, *) { return true }
        return false
    }

    /// Couleurs de l'icône (orange → rose → violet), reprises par l'accueil.
    static let brand: [Color] = [Color(red: 1.0, green: 0.64, blue: 0.36),
                                 Color(red: 0.95, green: 0.34, blue: 0.49),
                                 Color(red: 0.48, green: 0.36, blue: 0.96)]
}

/// Surface flottante : verre natif sur macOS 26 quand la préférence est active et la fenêtre au premier plan ;
/// matériau sur macOS 13-15 ; sinon fond opaque de fenêtre. Même structure de vue dans tous les cas (aucun arbre
/// reconstruit au passage FL ↔ FL Shortcut) : seuls les paramètres changent.
/// `tint` : teinte qui porte un sens (avertissement), jamais décorative (WWDC25 219).
/// `alwaysLive` : verre même quand l'app n'est pas active (bulle brève au-dessus de FL, macOS 26 seulement).
struct GlassSurface<S: InsettableShape>: ViewModifier {
    let shape: S
    var tint: Color? = nil
    var alwaysLive = false
    @AppStorage(Appearance.glassKey) private var glassEnabled = true
    @Environment(\.controlActiveState) private var activeState
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var active: Bool { activeState != .inactive }
    private var live: Bool { glassEnabled && (alwaysLive || active) }

    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            // Réduire la transparence / Contraste élevé : le verre devient plus givré ou cerné tout seul.
            content
                .background(shape.fill(Color(nsColor: .windowBackgroundColor)).opacity(live ? 0 : 1))
                .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5).opacity(live ? 0 : 1))
                .glassEffect(live ? glass : Glass.identity, in: shape)
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    #if compiler(>=6.2)
    @available(macOS 26.0, *)
    private var glass: Glass {
        guard let tint else { return Glass.regular }
        return Glass.regular.tint(tint.opacity(0.35))
    }
    #endif

    /// macOS 13-15 : matériau (flou) quand la fenêtre est active, fond opaque sinon (jamais de matériau dans une
    /// bulle au-dessus de FL : rien derrière à flouter dans sa fenêtre transparente), teinte légère par-dessus.
    private func fallback(_ content: Content) -> some View {
        let translucent = glassEnabled && active && !reduceTransparency
        let base = translucent ? AnyShapeStyle(Material.regular) : AnyShapeStyle(Color(nsColor: .windowBackgroundColor))
        return content
            .background(shape.fill((tint ?? Color.clear).opacity(0.14)))
            .background(base, in: shape)
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

/// Fond de liste transparent quand la fenêtre est translucide : les sections (cartes) se posent dessus.
private struct GlassListBackground: ViewModifier {
    @AppStorage(Appearance.glassKey) private var glassEnabled = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if Appearance.translucentWindow(glass: glassEnabled, reduceTransparency: reduceTransparency) {
            content.scrollContentBackground(.hidden)
        } else {
            content
        }
    }
}

/// Fond de fenêtre translucide (voir `windowGlass`).
private struct WindowGlass: ViewModifier {
    let on: Bool
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        if #available(macOS 15.0, *), Appearance.translucentWindow(glass: on, reduceTransparency: reduceTransparency) {
            content.containerBackground(Material.thin, for: .window)
        } else {
            content
        }
    }
}

/// Lavis coloré en haut d'une page (couche de contenu : dégradé statique, sans flou ni animation). Il passe sous la
/// barre d'outils et sous la barre latérale en verre, qui en prennent la couleur (WWDC25 356 : fonds teintés sous
/// le verre). Seulement avec la fenêtre translucide ; Contraste élevé : rien.
private struct TintedBackdrop: ViewModifier {
    let tint: Color?
    @AppStorage(Appearance.glassKey) private var glassEnabled = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.colorScheme) private var scheme

    private var visible: Bool {
        tint != nil && contrast != .increased
            && Appearance.translucentWindow(glass: glassEnabled, reduceTransparency: reduceTransparency)
    }

    func body(content: Content) -> some View {
        content.background(alignment: .top) {
            if visible, let tint {
                LinearGradient(colors: [tint.opacity(scheme == .dark ? 0.30 : 0.24), tint.opacity(0.07), .clear],
                               startPoint: .top, endPoint: .bottom)
                    .frame(height: 340)
                    .ignoresSafeArea()           // sous la barre d'outils et la barre latérale flottante
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}

extension View {
    /// Fenêtre entière translucide (matériau derrière la fenêtre) : le bureau se devine, les sections posées
    /// dessus restent lisibles. Composé par le système ; figé par macOS quand la fenêtre n'est plus active.
    func windowGlass(_ on: Bool) -> some View {
        modifier(WindowGlass(on: on))
    }

    /// Liste posée sur le fond translucide de la fenêtre.
    func glassListBackground() -> some View {
        modifier(GlassListBackground())
    }

    /// Lavis de la couleur de la page sous le verre (nil : aucun).
    func tintedBackdrop(_ tint: Color?) -> some View {
        modifier(TintedBackdrop(tint: tint))
    }

    /// Bouton posé sur une surface de verre (notification, avertissement) : simple remplissage, jamais de verre sur
    /// du verre (WWDC25 219).
    @ViewBuilder func onGlassButton() -> some View {
        if #available(macOS 14.0, *) {
            buttonStyle(.bordered).buttonBorderShape(.capsule)
        } else {
            buttonStyle(.bordered)
        }
    }

    /// Identité de verre : deux surfaces du même GlassGroup se fondent l'une dans l'autre en apparaissant.
    @ViewBuilder func glassID(_ id: String, in ns: Namespace.ID) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { glassEffectID(id, in: ns) } else { self }
        #else
        self
        #endif
    }

    /// Barre flottante en haut ou en bas : safeAreaBar sur macOS 26 (effet de bord sous la barre), sinon
    /// safeAreaInset (le contenu laisse la place).
    @ViewBuilder func floatingBar<C: View>(_ edge: VerticalEdge, @ViewBuilder content: () -> C) -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            safeAreaBar(edge: edge, spacing: 0, content: content)
        } else {
            safeAreaInset(edge: edge, spacing: 0, content: content)
        }
        #else
        safeAreaInset(edge: edge, spacing: 0, content: content)
        #endif
    }

    /// Grands boutons d'accueil (extra-large depuis macOS 14).
    @ViewBuilder func heroControlSize() -> some View {
        if #available(macOS 14.0, *) { controlSize(.extraLarge) } else { controlSize(.large) }
    }

    /// Boutons qui prennent toute la largeur disponible (macOS 26), comme les fenêtres d'accueil d'Apple.
    @ViewBuilder func flexibleButtons() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) { buttonSizing(.flexible) } else { self }
        #else
        self
        #endif
    }

    /// Bouton secondaire (Annuler, Changer…, Apprendre…).
    func secondaryButton() -> some View {
        modifier(SecondaryButtonStyleModifier())
    }

    /// Surface flottante en verre (voir GlassSurface).
    func glassSurface<S: InsettableShape>(_ shape: S, tint: Color? = nil, alwaysLive: Bool = false) -> some View {
        modifier(GlassSurface(shape: shape, tint: tint, alwaysLive: alwaysLive))
    }

    /// Bouton principal (Valider, Continuer…).
    func primaryButton() -> some View {
        modifier(PrimaryButtonStyleModifier())
    }
}

// MARK: - Touches

/// Une touche de clavier : symbole, et en grand le nom en clair (« ⌃ ctrl »). Plate avec un léger relief (ombre
/// nette d'un point, sans flou) ; en verre sur l'accueil, posée sur un fond coloré (`glass`).
struct KeyCap: View {
    let symbol: String
    var name: String? = nil
    var large = false
    var glass = false

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: large ? 8 : 5, style: .continuous) }

    var body: some View {
        Group {
            if glass {
                face.glassSurface(shape)
            } else {
                face
                    .background(shape.fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: Color.black.opacity(0.14), radius: 0, x: 0, y: 1))
                    .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
            }
        }
        .accessibilityHidden(true)
    }

    private var face: some View {
        VStack(spacing: 1) {
            Text(symbol).font(.system(size: large ? 15 : 12, weight: .medium))
            if large, let name {
                Text(name).font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: large ? 34 : 20, minHeight: large ? 36 : 20)
        .padding(.horizontal, large ? 6 : 4)
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
/// `glass` : touches en verre regroupées (une seule passe, elles se fondent entre elles).
struct KeyCaps: View {
    let combo: KeyCombo?
    var large = false
    var glass = false
    var placeholder = "—"

    var body: some View {
        Group {
            if glass {
                GlassGroup(spacing: large ? 4 : 3) { row }
            } else {
                row
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(combo?.spoken ?? "Aucun raccourci")
    }

    private var row: some View {
        HStack(spacing: large ? 4 : 3) {
            if let combo {
                ForEach(combo.caps) { cap in
                    KeyCap(symbol: cap.symbol, name: cap.name.isEmpty ? nil : cap.name, large: large, glass: glass)
                }
            } else {
                Text(placeholder).foregroundStyle(.secondary)
            }
        }
    }
}

/// Touche compacte d'une liste, comme dans Réglages › Clavier : le raccourci en texte dans un petit cadre.
/// `accent` : raccourci modifié.
struct KeyLabel: View {
    let combo: KeyCombo?
    var accent = false
    var placeholder = "Aucune"

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 6, style: .continuous) }

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
        .padding(.horizontal, 8)
        .frame(minWidth: 56, minHeight: 22)
        .background(shape.fill(Color.primary.opacity(0.05)))
        .overlay(shape.strokeBorder(accent ? Color.accentColor.opacity(0.5) : Color(nsColor: .separatorColor),
                                    lineWidth: 0.5))
        .contentShape(shape)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(combo?.spoken ?? placeholder)
    }
}

// MARK: - Icônes

/// Icône de rubrique façon Réglages Système : symbole blanc sur un carré arrondi coloré, liseré clair en haut
/// comme un reflet. Couche de contenu (la couleur y a sa place, WWDC25 219) : aucun verre, aucun flou, statique.
struct SectionIcon: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 20

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: size * 0.27, style: .continuous) }

    var body: some View {
        shape.fill(tint.gradient)
            .overlay(shape.strokeBorder(LinearGradient(colors: [Color.white.opacity(0.5), Color.white.opacity(0.06)],
                                                       startPoint: .top, endPoint: .bottom),
                                        lineWidth: max(0.5, size / 40)))
            .overlay(Image(systemName: symbol)
                .symbolVariant(.fill)
                .font(.system(size: size * 0.52, weight: .semibold))
                .foregroundStyle(Color.white))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}

/// Numéro d'étape dans une pastille (accueil, guide d'autorisation) ; coche verte une fois faite.
struct StepBadge: View {
    let number: Int
    var done = false

    var body: some View {
        Group {
            if done {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 17))
                    .foregroundStyle(Color.green)
            } else {
                Text("\(number)")
                    .font(.system(size: 11, weight: .bold).monospacedDigit())
                    .foregroundStyle(Color.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.accentColor))
            }
        }
        .frame(width: 20)
        .accessibilityHidden(true)
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

// MARK: - Pages en cartes (List paresseuse)

/// Place d'une ligne dans sa carte (section arrondie) : arrondie en haut si première, en bas si dernière.
enum CardRowPosition: Equatable {
    case single, first, middle, last

    static func position(index: Int, count: Int) -> CardRowPosition {
        if count <= 1 { return .single }
        if index == 0 { return .first }
        return index == count - 1 ? .last : .middle
    }

    var roundsTop: Bool { self == .single || self == .first }
    var roundsBottom: Bool { self == .single || self == .last }
}

extension View {
    /// Ligne d'une page en cartes : fond arrondi selon sa place dans la section, sans séparateur de la liste.
    func cardRow(_ position: CardRowPosition) -> some View {
        let gap = CardRowBackground.gap
        let side = CardRowBackground.inset + 12
        return listRowInsets(EdgeInsets(top: 8 + (position.roundsTop ? gap : 0), leading: side,
                                        bottom: 8 + (position.roundsBottom ? gap : 0), trailing: side))
            .listRowSeparator(.hidden)
            .listRowBackground(CardRowBackground(position: position))
    }
}

/// Fond d'une ligne de carte : rectangle arrondi seulement aux bouts de la carte, filet sous les lignes intérieures.
/// Carte grise sur le fond de la page, comme le Form groupé (verre ou non).
struct CardRowBackground: View {
    static let inset: CGFloat = 10                       // marge de la carte dans la liste
    static let gap: CGFloat = 4                          // espace au-dessus et au-dessous d'une carte
    let position: CardRowPosition
    @Environment(\.colorScheme) private var scheme

    private var fill: Color { scheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.045) }

    var body: some View {
        CardRowShape(roundsTop: position.roundsTop, roundsBottom: position.roundsBottom)
            .fill(fill)
            .overlay(alignment: .bottom) {
                if !position.roundsBottom {
                    Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5).padding(.leading, 12)
                }
            }
            .padding(.top, position.roundsTop ? Self.gap : 0)
            .padding(.bottom, position.roundsBottom ? Self.gap : 0)
            .padding(.horizontal, Self.inset)
            .accessibilityHidden(true)
    }
}

/// Rectangle aux coins arrondis en haut et/ou en bas (UnevenRoundedRectangle n'existe qu'à partir de macOS 14).
private struct CardRowShape: Shape {
    let roundsTop: Bool
    let roundsBottom: Bool
    var radius: CGFloat = 10

    func path(in rect: CGRect) -> Path {
        let t = roundsTop ? min(radius, rect.height / 2) : 0
        let b = roundsBottom ? min(radius, rect.height / 2) : 0
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY + t))
        if t > 0 {
            p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                     tangent2End: CGPoint(x: rect.minX + t, y: rect.minY), radius: t)
        }
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY))
        if t > 0 {
            p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                     tangent2End: CGPoint(x: rect.maxX, y: rect.minY + t), radius: t)
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - b))
        if b > 0 {
            p.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                     tangent2End: CGPoint(x: rect.maxX - b, y: rect.maxY), radius: b)
        }
        p.addLine(to: CGPoint(x: rect.minX + b, y: rect.maxY))
        if b > 0 {
            p.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                     tangent2End: CGPoint(x: rect.minX, y: rect.maxY - b), radius: b)
        }
        p.closeSubpath()
        return p
    }
}
