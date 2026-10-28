// Styles communs : polices et couleurs système, aucune animation infinie, aucun minuteur.
// Liquid Glass (macOS 26, WWDC25 219/310/323/356) : le verre est réservé à la couche de navigation et de contrôle
// qui flotte au-dessus du contenu (barre latérale et barre d'outils du système, pastille de statut, notification,
// avertissements, boutons, bulle d'aide), jamais ligne par ligne (une couche de verre par ligne coûtait cher :
// 8fb66a8) ni verre sur verre. La couleur va dans le contenu (icônes de rubrique) ; plus de lavis de couleur sous le
// verre depuis le 28/10 (« garder que le Liquid Glass, pas de fond »). Le verre redevient opaque dès que la fenêtre n'est plus active
// (FL au premier plan) : rien à recalculer pendant que tu travailles dans FL. Réduire la transparence et Contraste
// élevé : le verre s'adapte tout seul, les cartes redeviennent grises. Fond de fenêtre plein depuis le 28/10 (« sans
// le Liquid Glass derrière ») : le verre est devant, sur les cartes, les touches et les cartes de l'Organiser
// (`GlassPlate`). Réglable dans le menu Profil (« Effet Liquid Glass ») : coupé, tout est opaque et les cartes
// grises. Audit 05 : touches affichées avec leur nom en clair.
// Mouvement : courtes transitions, remplacées par un simple fondu quand « Réduire les animations » est activé.
import AppKit
import SwiftUI

// MARK: - Mouvement

enum Motion {
    /// Changement d'état ordinaire (notification).
    static let smooth = Animation.easeInOut(duration: 0.2)
    /// Remplacement quand l'utilisateur a demandé moins de mouvement.
    static let reduced = Animation.easeInOut(duration: 0.15)

    /// « Réduire les animations » de macOS (ignoré au ralenti du mode capture, pour photographier le vrai mouvement).
    static var reduce: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && DebugSnapshot.slowMotion == 1 }

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
        content.animation(reduceMotion && DebugSnapshot.slowMotion == 1 ? Motion.reduced : animation, value: value)
    }
}

extension View {
    /// `.animation(_:value:)` qui respecte « Réduire les animations ».
    func motion<V: Equatable>(_ animation: Animation = Motion.smooth, value: V) -> some View {
        modifier(MotionModifier(animation: animation, value: value))
    }

    /// Survol du menu de la barre des menus : contour arrondi qui s'allume de la couleur de l'élément et s'écarte un peu
    /// de lui, avec un halo de sa couleur autour (ressort). Seul l'élément survolé est redessiné. Ses couleurs ne
    /// changent jamais (demande du propriétaire, 25/10) : ni fond ajouté, ni ombre sur son contenu (elle ternissait
    /// les gris et les boutons) ; le halo n'est que dehors. Le contenu ne grossit plus (25/10 : « ça fait bizarre à
    /// l'œil nu » : un texte agrandi est redessiné flou) : c'est le contour qui s'écarte, le texte reste net. `outset` : contour un peu plus grand que l'élément (ligne de
    /// la barre latérale) ; `enabled` : faux pour un élément qu'on ne peut pas choisir, ou déjà choisi (le fond de la
    /// sélection, plus grand, dépasserait du contour).
    func menuHover(tint: Color, cornerRadius: CGFloat = 10, outset: CGFloat = 0, enabled: Bool = true) -> some View {
        modifier(MenuHover(tint: tint, cornerRadius: cornerRadius, outset: outset, enabled: enabled))
    }
}

extension Motion {
    /// Changement de page « morph » (comme la Morphose de PowerPoint ou le Magic Move de Keynote) : ce qui se
    /// retrouve d'une page à l'autre glisse à sa nouvelle place, le reste se fond. Ressort lent et doux (0,8 s), sans
    /// rebond visible.
    static var morph: Animation { .spring(response: 0.8 * DebugSnapshot.slowMotion, dampingFraction: 0.9) }

    /// Page qui s'en va : un vrai fondu, assez long pour se croiser avec celle qui arrive (jamais de disparition sèche).
    static var fadeOut: Animation { .easeInOut(duration: 0.5 * DebugSnapshot.slowMotion) }

    /// Page qui arrive : floue, transparente, un peu plus bas et plus petite, puis nette à sa place (ressort) ; celle
    /// qui part se brouille et monte en s'effaçant. Les deux se croisent.
    static var pageMorph: AnyTransition {
        transition(.asymmetric(
            insertion: .modifier(active: SoftFocus(amount: 1, rise: 18), identity: SoftFocus(amount: 0, rise: 18)),
            removal: .modifier(active: SoftFocus(amount: 1, rise: -12), identity: SoftFocus(amount: 0, rise: -12))
                .animation(fadeOut)))
    }
}

extension Motion {
    /// Changement de contenu rapide (inspecteur du créateur, qui suit les flèches du clavier) : le même fondu flou,
    /// en un tiers de seconde.
    static var quickMorph: Animation { .spring(response: 0.35 * DebugSnapshot.slowMotion, dampingFraction: 0.92) }

    static var quickSwap: AnyTransition {
        transition(.asymmetric(
            insertion: .modifier(active: SoftFocus(amount: 1, rise: 8), identity: SoftFocus(amount: 0, rise: 8)),
            removal: .modifier(active: SoftFocus(amount: 1, rise: -6), identity: SoftFocus(amount: 0, rise: -6))
                .animation(.easeOut(duration: 0.2 * DebugSnapshot.slowMotion))))
    }
}

extension View {
    /// Contenu qui change (page de la barre latérale, connecté ou non, étape suivante…) : comme dans le guide,
    /// l'ancien se brouille et s'efface pendant que le nouveau passe du flou au net ; jamais de changement sec.
    /// `key` : ce qui fait changer le contenu (un nouveau contenu repart aussi de zéro : liste en haut, champs neufs).
    func softSwitch<K: Hashable>(_ key: K, quick: Bool = false) -> some View {
        ZStack {
            self.id(key).transition(quick ? Motion.quickSwap : Motion.pageMorph)
        }
        .motion(quick ? Motion.quickMorph : Motion.morph, value: key)
    }

    /// Page de la barre latérale : une nouvelle page à chaque `key` (liste neuve, en haut), affichée d'un coup. Plus
    /// d'animation au changement de page (demande du propriétaire, 24/10 : ni fondu ni flou).
    func pageSwitch<K: Hashable>(_ key: K) -> some View {
        id(key)
    }

    /// Bascule de toute la fenêtre (raccourcis ↔ créateur de macros) : la page qui arrive apparaît en fondu, à sa
    /// création. Opacité seule : ces pages sont faites de vues d'AppKit que le flou et l'échelle ne suivent pas.
    func windowReveal() -> some View {
        modifier(PageReveal())
    }
}

/// « Mise au point » : `amount` 1 = hors champ (transparent, flou, décalé, à peine plus petit), 0 = en place.
private struct SoftFocus: ViewModifier {
    let amount: CGFloat
    let rise: CGFloat

    func body(content: Content) -> some View {
        content
            .opacity(1 - amount)
            .blur(radius: 12 * amount)
            .scaleEffect(1 - 0.03 * amount, anchor: .top)
            .offset(y: rise * amount)
    }
}

/// Apparition de toute la fenêtre (raccourcis ↔ créateur), une seule fois, à sa création : fondu seul. Le
/// changement lui-même se fait SANS animation : avec une animation, SwiftUI garde la page qui part (ses listes et
/// barres d'AppKit, qui ne suivent pas le fondu) pleine jusqu'au bout, et la nouvelle apparaissait par-dessus.
private struct PageReveal: ViewModifier {
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotionSetting

    private var reduceMotion: Bool { reduceMotionSetting && DebugSnapshot.slowMotion == 1 }

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .onAppear {
                withAnimation(reduceMotion ? Motion.reduced : .easeOut(duration: 0.28 * DebugSnapshot.slowMotion)) {
                    shown = true
                }
            }
    }
}

private struct MorphIn: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotionSetting

    private var reduceMotion: Bool { reduceMotionSetting && DebugSnapshot.slowMotion == 1 }

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .blur(radius: shown || reduceMotion ? 0 : 8)
            .offset(y: shown || reduceMotion ? 0 : 16)
            .onAppear {
                withAnimation(reduceMotion ? Motion.reduced
                                           : Motion.morph.delay((0.15 + 0.1 * Double(index)) * DebugSnapshot.slowMotion)) {
                    shown = true
                }
            }
    }
}

extension View {
    /// Même place d'une vue à l'autre (`matchedGeometryEffect`) quand un espace de noms est donné ; sinon rien.
    @ViewBuilder func morphing(_ id: String, in ns: Namespace.ID?) -> some View {
        if let ns { matchedGeometryEffect(id: id, in: ns) } else { self }
    }

    /// Élément d'une page qui arrive : il passe du flou au net en montant à sa place, juste après le précédent
    /// (`index`), une seule fois, à l'apparition de la page. Pas dans une liste (les lignes y apparaissent aussi en
    /// défilant).
    func morphIn(_ index: Int) -> some View {
        modifier(MorphIn(index: index))
    }
}

extension Motion {
    /// Survol et prise d'un élément : ressort court et souple.
    static let lift = Animation.spring(response: 0.28, dampingFraction: 0.72)
}

struct MenuHover: ViewModifier {
    let tint: Color
    let cornerRadius: CGFloat
    var outset: CGFloat = 0
    var enabled = true
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Le contour s'écarte de 2 points au survol : l'élément semble se soulever, sans que son texte grossisse.
    static let lift: CGFloat = 2

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let hovered = hovering && enabled
        let spread = outset + (hovered && !reduceMotion ? Self.lift : 0)
        content
            // Aux bords de l'élément (ou `outset` au-delà), sans changer sa place : le halo derrière, le contour
            // par-dessus (rien de l'élément ne dépasse de sa couleur).
            .background {
                HoverGlow(shape: shape, tint: tint)
                    .opacity(hovered ? 1 : 0)
                    .padding(-spread)
            }
            .overlay {
                shape.strokeBorder(tint, lineWidth: 1.5)
                    .opacity(hovered ? 1 : 0)
                    .padding(-spread)
                    .allowsHitTesting(false)
            }
            .onHover { inside in
                withAnimation(reduceMotion ? Motion.reduced : Motion.lift) { hovering = inside }
            }
    }
}

/// Halo du survol, de la couleur de l'élément, seulement autour de lui : l'intérieur est découpé, ses couleurs ne
/// bougent pas (une ombre posée sur le contenu teintait ses textes et ses boutons).
struct HoverGlow<S: Shape>: View {
    let shape: S
    let tint: Color

    var body: some View {
        ZStack {
            shape.fill(tint.opacity(0.32)).blur(radius: 9).offset(y: 3)
            shape.fill(Color.black).blendMode(.destinationOut)
        }
        .compositingGroup()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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


    /// Couleurs de l'icône (orange → rose → violet), reprises par l'accueil.
    static let brand: [Color] = [Color(red: 1.0, green: 0.64, blue: 0.36),
                                 Color(red: 0.95, green: 0.34, blue: 0.49),
                                 Color(red: 0.48, green: 0.36, blue: 0.96)]
}

/// Surface flottante : verre natif sur macOS 26 quand la préférence est active et la fenêtre au premier plan ;
/// matériau sur macOS 13-15 ; sinon fond opaque de fenêtre. Même structure de vue dans tous les cas (aucun arbre
/// reconstruit au passage FL ↔ FL Shortcuts) : seuls les paramètres changent.
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
/// Fond de la liste toujours transparent : la lueur de couleur de la page (comme dans le guide) passe dessous ; les
/// cartes gardent leur propre fond, lisible.
private struct GlassListBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.scrollContentBackground(.hidden)
    }
}

/// Fond de la page aux couleurs de sa section, comme le guide : lueur de sa couleur (halo en haut à gauche, reflet en
/// haut à droite, une touche en bas, `TintGlow`) sur toute la page, sous la barre d'outils et la barre latérale.
/// D'une page à l'autre, les couleurs se fondent l'une dans l'autre (0,9 s), jamais de changement sec. Dégradés
/// statiques : rien ne tourne au repos. Contraste élevé : rien.
private struct TintedBackdrop: ViewModifier {
    let tint: Color?
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.background {
            ZStack {
                if contrast != .increased, let tint {
                    TintGlow(tint: tint)
                        .id(tint)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.9 * DebugSnapshot.slowMotion), value: tint)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

extension View {
    /// Pas de bande sous la barre d'outils (retour de l'utilisateur : un rectangle du titre jusqu'au « + » et au « ⋯ ») :
    /// ni fond de barre d'outils, ni effet de bord en haut de la page (macOS 26) ; le titre et les boutons flottent
    /// sur la page.
    @ViewBuilder func noToolbarBand() -> some View {
        #if compiler(>=6.2)
        if #available(macOS 26.0, *) {
            toolbarBackgroundVisibility(.hidden, for: .windowToolbar).scrollEdgeEffectHidden(true, for: .top)
        } else if #available(macOS 15.0, *) {
            toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        } else {
            self
        }
        #else
        if #available(macOS 15.0, *) { toolbarBackgroundVisibility(.hidden, for: .windowToolbar) } else { self }
        #endif
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
        if control { out.append(CapInfo(id: "ctrl", symbol: "⌃", name: String(localized: "ctrl"))) }
        if option { out.append(CapInfo(id: "option", symbol: "⌥", name: String(localized: "option"))) }
        if shift { out.append(CapInfo(id: "shift", symbol: "⇧", name: String(localized: "maj"))) }
        if command { out.append(CapInfo(id: "cmd", symbol: "⌘", name: String(localized: "cmd"))) }
        out.append(CapInfo(id: "key-\(keyCode)", symbol: KeyNames.name(for: keyCode), name: ""))
        return out
    }

    /// Texte lu par VoiceOver : « contrôle option R ».
    var spoken: String {
        var parts: [String] = []
        if control { parts.append(String(localized: "contrôle")) }
        if option { parts.append(String(localized: "option")) }
        if shift { parts.append(String(localized: "majuscule")) }
        if command { parts.append(String(localized: "commande")) }
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
        .accessibilityLabel(combo?.spoken ?? String(localized: "Aucun raccourci"))
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
    var placeholder = String(localized: "Aucune")
    @Environment(\.colorScheme) private var scheme
    @AppStorage(Appearance.glassKey) private var glassEnabled = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 6, style: .continuous) }

    private var plate: Bool {
        GlassPlate.on(glass: glassEnabled, reduceTransparency: reduceTransparency, increasedContrast: contrast == .increased)
    }

    /// Touche changée : teintée de bleu (maquette du 28/10) ; sinon un petit morceau de verre (gris sans l'effet).
    private var fill: Color {
        if accent { return Color.accentColor.opacity(0.18) }
        return plate ? GlassPlate.fill(scheme) : Color.primary.opacity(0.05)
    }

    private var border: AnyShapeStyle {
        if accent { return AnyShapeStyle(Color.accentColor.opacity(0.7)) }
        return plate ? AnyShapeStyle(GlassPlate.rim(scheme)) : AnyShapeStyle(Color(nsColor: .separatorColor))
    }

    var body: some View {
        Group {
            if let combo {
                // Une case par touche, comme sur la maquette du 28/10 : ⌘ puis A, pas « ⌘A » dans un seul cadre.
                HStack(spacing: 3) {
                    ForEach(Array(Self.parts(of: combo).enumerated()), id: \.offset) { _, part in
                        tile(Text(part).foregroundStyle(accent ? Color.accentColor : Color.primary))
                    }
                }
            } else {
                tile(Text(placeholder).foregroundStyle(.secondary))
            }
        }
        .font(.system(size: 12, weight: .medium))
        .lineLimit(1)
        .contentShape(Rectangle())
        // Jamais écrasé ni coupé quand la fenêtre est étroite : c'est le titre de la ligne qui se raccourcit.
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(combo?.spoken ?? placeholder)
    }

    /// Les modificateurs (⌃ ⌥ ⇧ ⌘) un par un, puis la touche.
    static func parts(of combo: KeyCombo) -> [String] {
        combo.modifierSymbols.map(String.init) + [KeyNames.name(for: combo.keyCode, layout: SystemKeyboardLayout())]
    }

    private func tile(_ label: some View) -> some View {
        label
            .padding(.horizontal, 6)
            .frame(minWidth: 22, minHeight: 22)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(border, lineWidth: accent || plate ? 1 : 0.5))
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
        case "play": return String(localized: "Lance ou met en pause la lecture")
        case "stop": return String(localized: "Arrête la lecture")
        case "rec": return String(localized: "Démarre ou arrête l'enregistrement")
        case "metro": return String(localized: "Active ou coupe le métronome")
        case "count": return String(localized: "Décompte avant l'enregistrement")
        case "loop": return String(localized: "Enchaîne les prises sur la boucle")
        case "wait": return String(localized: "Le REC démarre à la première note jouée")
        case "marker": return String(localized: "Repère « bonne prise » à la position de lecture")
        case "arm": return String(localized: "Prépare la piste du Mixer sélectionnée à enregistrer")
        case "tap": return String(localized: "Tape le tempo en rythme")
        case "newpat": return String(localized: "Crée un pattern vide et ouvre le Piano Roll")
        case "clone": return String(localized: "Duplique le pattern en cours pour une variation")
        case "pnext": return String(localized: "Passe au pattern suivant")
        case "pprev": return String(localized: "Revient au pattern précédent")
        case "chnext": return String(localized: "Instrument suivant, sans quitter le Piano Roll")
        case "chprev": return String(localized: "Instrument précédent, sans quitter le Piano Roll")
        case "snap": return String(localized: "Change le magnétisme : 1/4, 1/8, triolets…")
        case "quant": return String(localized: "Aligne les notes de l'instrument sélectionné")
        case "presetnext": return String(localized: "Preset suivant du plugin ouvert")
        case "presetprev": return String(localized: "Preset précédent du plugin ouvert")
        case "mute": return String(localized: "Coupe la piste du Mixer sélectionnée")
        case "solo": return String(localized: "Écoute seulement la piste sélectionnée")
        case "unsolo": return String(localized: "Réécoute tout le morceau")
        case "bypass": return String(localized: "Compare la piste avec et sans effets")
        case "mono": return String(localized: "Vérifie que le mix tient en mono")
        case "trnext": return String(localized: "Sélectionne la piste suivante du Mixer")
        case "trprev": return String(localized: "Sélectionne la piste précédente du Mixer")
        case "volup": return String(localized: "Monte la piste sélectionnée")
        case "voldn": return String(localized: "Baisse la piste sélectionnée")
        case "pl": return String(localized: "Affiche la Playlist")
        case "cr": return String(localized: "Affiche le Channel Rack")
        case "pr": return String(localized: "Affiche le Piano Roll")
        case "mx": return String(localized: "Affiche le Mixer")
        case "br": return String(localized: "Affiche le Browser")
        case "plmx": return String(localized: "Bascule entre la Playlist et le Mixer")
        case "undo": return String(localized: "Annule la dernière action")
        case "redo": return String(localized: "Rétablit l'action annulée")
        case "save": return String(localized: "Sauvegarde le projet")
        case "armon": return String(localized: "Arme la piste sélectionnée, sans jamais la désarmer")
        case "recon": return String(localized: "Allume le REC, sans jamais l'éteindre")
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
    /// `hover` : au survol, la ligne entière s'allume comme une ligne du menu de la barre des menus (contour de
    /// cette couleur, d'un filet à l'autre et toute la largeur de la carte).
    func cardRow(_ position: CardRowPosition, hover: Color? = nil) -> some View {
        modifier(CardRowModifier(position: position, hover: hover))
    }

    /// En-tête de page (28/10) : le titre posé sur la page, sans carte grise autour.
    func pageTitleRow() -> some View {
        padding(.horizontal, 12)
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .listRowInsets(EdgeInsets(top: 0, leading: CardRowBackground.inset, bottom: 0, trailing: CardRowBackground.inset))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }
}

/// La marge intérieure d'une ligne est dans la ligne elle-même (pas dans la liste) : le survol couvre toute la ligne,
/// jusqu'aux filets qui la séparent de ses voisines. Survol (25/10, capture du propriétaire : la carte grise
/// dépassait du contour coloré, la liste mettant sa propre marge autour du contenu) : c'est le fond de la ligne,
/// toute la largeur de la carte, qui s'allume et s'élargit ; le contenu ne bouge pas (texte net, couleurs inchangées).
private struct CardRowModifier: ViewModifier {
    let position: CardRowPosition
    let hover: Color?
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let gap = CardRowBackground.gap
        let lifted = hovering && hover != nil
        let row = content
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
        return Group {
            if hover != nil {
                row
                    .contentShape(Rectangle())
                    .onHover { inside in
                        withAnimation(reduceMotion ? Motion.reduced : Motion.lift) { hovering = inside }
                    }
            } else {
                row
            }
        }
        .listRowInsets(EdgeInsets(top: position.roundsTop ? gap : 0, leading: CardRowBackground.inset,
                                  bottom: position.roundsBottom ? gap : 0, trailing: CardRowBackground.inset))
        .listRowSeparator(.hidden)
        .listRowBackground(CardRowBackground(position: position, hover: lifted ? hover : nil,
                                             grow: lifted && !reduceMotion))
    }
}

/// Fond d'une ligne de carte : rectangle arrondi seulement aux bouts de la carte, filet sous les lignes intérieures.
/// Carte grise sur le fond de la page, comme le Form groupé (verre ou non). Survolée (`hover`) : la même couleur,
/// arrondie, un peu plus large que la carte (`grow`), cernée de la couleur de la page avec son halo autour ; rien de
/// gris ne dépasse du contour.
struct CardRowBackground: View {
    static let inset: CGFloat = 10                       // marge de la carte dans la liste
    static let gap: CGFloat = 4                          // espace au-dessus et au-dessous d'une carte
    /// Survol : la ligne s'élargit de 6 points de chaque côté (dans la marge de la carte, jamais rognée) ; ses coins
    /// arrondis de 6 couvrent ceux de la carte.
    static let liftOutset: CGFloat = 6
    let position: CardRowPosition
    var hover: Color? = nil
    var grow = false
    @Environment(\.colorScheme) private var scheme
    @AppStorage(Appearance.glassKey) private var glassEnabled = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var plate: Bool {
        GlassPlate.on(glass: glassEnabled, reduceTransparency: reduceTransparency, increasedContrast: contrast == .increased)
    }

    private var fill: Color {
        if plate { return GlassPlate.fill(scheme) }
        return scheme == .dark ? Color.white.opacity(0.07) : Color.black.opacity(0.045)
    }

    var body: some View {
        Group {
            if let hover {
                let shape = RoundedRectangle(cornerRadius: Self.liftOutset, style: .continuous)
                shape.fill(fill)
                    .background(HoverGlow(shape: shape, tint: hover))
                    .overlay(shape.strokeBorder(hover, lineWidth: 1.5))
                    .padding(.horizontal, grow ? -Self.liftOutset : 0)
            } else {
                CardRowShape(roundsTop: position.roundsTop, roundsBottom: position.roundsBottom)
                    .fill(fill)
                    .overlay {
                        // Bord de verre : le reflet sur la première ligne, puis un bord fin ; ouvert entre deux
                        // lignes, la carte reste d'un seul tenant.
                        if plate {
                            CardRimShape(roundsTop: position.roundsTop, roundsBottom: position.roundsBottom)
                                .stroke(position.roundsTop ? AnyShapeStyle(GlassPlate.rim(scheme))
                                                           : AnyShapeStyle(GlassPlate.edge(scheme)), lineWidth: 1)
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if !position.roundsBottom {
                            Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.5).padding(.leading, 12)
                        }
                    }
            }
        }
        .padding(.top, position.roundsTop ? Self.gap : 0)
        .padding(.bottom, position.roundsBottom ? Self.gap : 0)
        .padding(.horizontal, Self.inset)
        .accessibilityHidden(true)
    }
}

/// Plaque de verre dessinée (maquette validée le 28/10 : « le verre seulement devant », fond de fenêtre plein) : un
/// voile clair, un bord fin et un reflet en haut, comme le Liquid Glass posé sur un fond sombre. Dessinée plutôt que
/// `glassEffect` : une couche de verre par ligne de liste coûtait cher (8fb66a8) et chaque ligne aurait eu son propre
/// bord (des morceaux séparés) ; sur un fond plein, le vrai verre n'aurait rien d'autre à montrer. Effet Liquid Glass
/// coupé, Réduire la transparence ou Contraste élevé : la carte grise de toujours.
enum GlassPlate {
    static func on(glass: Bool, reduceTransparency: Bool, increasedContrast: Bool) -> Bool {
        glass && !reduceTransparency && !increasedContrast
    }

    /// Voile de la plaque.
    static func fill(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.085) : Color.white.opacity(0.62)
    }

    /// Bord fin.
    static func edge(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color.white.opacity(0.12) : Color.black.opacity(0.09)
    }

    /// Bord qui part du reflet, en haut, et s'éteint vers le bas.
    static func rim(_ scheme: ColorScheme) -> LinearGradient {
        LinearGradient(colors: [scheme == .dark ? Color.white.opacity(0.34) : Color.white, edge(scheme)],
                       startPoint: .top, endPoint: .bottom)
    }
}

/// Bord d'une ligne de carte : ses côtés, plus le haut et/ou le bas arrondis aux bouts de la carte (rien entre deux
/// lignes). Tracé à un demi-point du bord, dans la ligne, avec les mêmes arrondis que `CardRowShape`.
private struct CardRimShape: Shape {
    let roundsTop: Bool
    let roundsBottom: Bool
    var radius: CGFloat = 10

    func path(in full: CGRect) -> Path {
        let rect = full.insetBy(dx: 0.5, dy: 0)
        let top = roundsTop ? rect.minY + 0.5 : rect.minY
        let bottom = roundsBottom ? rect.maxY - 0.5 : rect.maxY
        let r = max(0, min(radius, full.height / 2) - 0.5)
        let t = roundsTop ? r : 0
        let b = roundsBottom ? r : 0
        var p = Path()
        // Côté gauche de bas en haut, le haut s'il est arrondi, puis le côté droit vers le bas et le bas arrondi.
        p.move(to: CGPoint(x: rect.minX, y: bottom - b))
        p.addLine(to: CGPoint(x: rect.minX, y: top + t))
        if roundsTop {
            p.addArc(tangent1End: CGPoint(x: rect.minX, y: top), tangent2End: CGPoint(x: rect.minX + t, y: top), radius: t)
            p.addLine(to: CGPoint(x: rect.maxX - t, y: top))
            p.addArc(tangent1End: CGPoint(x: rect.maxX, y: top), tangent2End: CGPoint(x: rect.maxX, y: top + t), radius: t)
        } else {
            p.move(to: CGPoint(x: rect.maxX, y: top))
        }
        p.addLine(to: CGPoint(x: rect.maxX, y: bottom - b))
        if roundsBottom {
            p.addArc(tangent1End: CGPoint(x: rect.maxX, y: bottom), tangent2End: CGPoint(x: rect.maxX - b, y: bottom),
                     radius: b)
            p.addLine(to: CGPoint(x: rect.minX + b, y: bottom))
            p.addArc(tangent1End: CGPoint(x: rect.minX, y: bottom), tangent2End: CGPoint(x: rect.minX, y: bottom - b),
                     radius: b)
        }
        return p
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
