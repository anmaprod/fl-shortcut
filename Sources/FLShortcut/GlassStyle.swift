// Styles communs : polices et couleurs système, aucune animation infinie, aucun minuteur.
// Plus aucun Liquid Glass (29/10, le propriétaire : « je veux que tout soit comme dans l'exemple… fond noir ») :
// l'app est toujours sombre, fond de fenêtre noir (#161618), boutons en capsules pleines (bleu pour l'action, clair
// sinon : `CapsuleButtonStyle`), cartes et touches en plaques claires dessinées (`GlassPlate`), comme la maquette du
// 28/10. Le nom « Glass » des types est resté, rien n'y est plus du verre de macOS. Audit 05 : touches affichées
// avec leur nom en clair.
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

    /// Survol d'une option (29/10, choix du propriétaire : « intérieur plein ») : tout l'intérieur prend la couleur de
    /// l'élément, son texte passe en blanc et son icône de couleur devient un carré blanc translucide
    /// (`hoverFilled`). Le contenu ne grossit pas (25/10 : un texte agrandi est redessiné flou). `outset` : fond un
    /// peu plus grand que l'élément ; `enabled` : faux pour un élément qu'on ne peut pas choisir, ou déjà choisi.
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

    func body(content: Content) -> some View {
        let hovered = hovering && enabled
        content
            .hoverFilled(hovered)
            // Aux bords de l'élément (ou `outset` au-delà), sans changer sa place. Style suisse (01/11) : blanc plein,
            // coins carrés, texte noir (comme la page choisie de la barre de gauche).
            .background {
                Rectangle().fill(Swiss.text)
                    .opacity(hovered ? 1 : 0)
                    .padding(-outset)
                    .allowsHitTesting(false)
            }
            .onHover { inside in
                withAnimation(reduceMotion ? Motion.reduced : Motion.lift) { hovering = inside }
            }
    }
}

private struct HoverFilledKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Vrai dans une option survolée (fond de sa couleur) : les icônes de couleur s'y effacent en blanc translucide.
    var hoverFilled: Bool {
        get { self[HoverFilledKey.self] }
        set { self[HoverFilledKey.self] = newValue }
    }
}

extension View {
    /// Contenu d'une option survolée (fond blanc, style suisse) : texte en noir (`nil` : la couleur de toujours, celle
    /// du conteneur). Même vue dans les deux cas : rien n'est recréé au survol.
    func hoverFilled(_ on: Bool) -> some View {
        foregroundColor(on ? Swiss.background : nil)
            .environment(\.hoverFilled, on)
    }

    /// Détail qui a sa propre couleur (rouge, bleu…) dans une option : noir quand l'option survolée est blanche (il y
    /// passerait mal), sa couleur sinon.
    func hoverTint(_ color: Color) -> some View {
        modifier(HoverTint(color: color))
    }
}

private struct HoverTint: ViewModifier {
    let color: Color
    @Environment(\.hoverFilled) private var filled

    func body(content: Content) -> some View {
        content.foregroundStyle(filled ? Swiss.background : color)
    }
}

// MARK: - Liquid Glass

/// Style suisse (maquette validée le 01/11, artefact `GHmTowhxy53F6VT3TEAjis`) : noir, blanc, traits fins, coins
/// carrés, gros titres gras, petites capitales espacées ; le rouge seulement pour ce qui compte.
enum Swiss {
    static let background = Color.black
    static let text = Color.white
    /// Texte secondaire (#8A8A8A).
    static let gray = Color(white: 0.541)
    /// Texte de lecture un peu effacé (#A8A8A8).
    static let soft = Color(white: 0.66)
    /// Traits : sous un titre (blanc), entre deux blocs (#333333), entre deux lignes (#222222), cadre d'une touche (#555555).
    static let line = Color(white: 0.2)
    static let faint = Color(white: 0.133)
    static let keyLine = Color(white: 0.333)
    /// Le rouge de ce qui compte : touche changée, avertissement, Désinstaller, progression (#FF3B1F).
    static let red = Color(red: 1.0, green: 0.231, blue: 0.122)
    static let fontName = "Helvetica Neue"

    /// Gros titre (46 pour une page, 30 à 34 pour une petite fenêtre) : gras, serré.
    static func title(_ size: CGFloat) -> Font { .custom(fontName, size: size).weight(.bold) }
    /// Texte en Helvetica (gras par défaut).
    static func font(_ size: CGFloat, _ weight: Font.Weight = .bold) -> Font { .custom(fontName, size: size).weight(weight) }
    /// Resserrement des gros titres (−1,8 à 46 points).
    static func titleTracking(_ size: CGFloat) -> CGFloat { -size * 0.039 }
}

extension View {
    /// Libellé en petites capitales espacées (« MES MACROS », « SAUVEGARDE »), gris par défaut.
    func swissLabel(_ color: Color = Swiss.gray, size: CGFloat = 11) -> some View {
        font(Swiss.font(size)).tracking(size * 0.11).textCase(.uppercase).foregroundStyle(color)
    }

    /// Gros titre de page, souligné d'un trait blanc sur toute la largeur.
    func swissTitle(_ size: CGFloat = 46) -> some View {
        font(Swiss.title(size)).tracking(Swiss.titleTracking(size)).foregroundStyle(Swiss.text)
            .lineLimit(1).minimumScaleFactor(0.6)
    }

    /// Trait sous un bloc : blanc sous un titre, #333 entre deux blocs, #222 entre deux lignes.
    func swissRule(_ color: Color = Swiss.text, edge: Alignment = .bottom) -> some View {
        overlay(alignment: edge) { Rectangle().fill(color).frame(height: 1).allowsHitTesting(false) }
    }
}

enum Appearance {
    /// Fond des fenêtres : noir plein (style suisse, 01/11).
    static let windowColor = Swiss.background
    /// Liens : blancs, soulignés là où ils sont posés (style suisse).
    static let link = Swiss.text

    /// Préférence « Effet Liquid Glass » (vrai par défaut) : ne règle plus que les plaques claires des cartes.
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

    /// Surface pleine (notification, avertissement, bulles au-dessus de FL) : le noir des menus, sa couleur par-dessus,
    /// un bord fin clair. Aucun verre (29/10).
    /// Style suisse (01/11) : noir, bord fin gris, et la couleur qui porte le sens (avertissement…) en trait épais à
    /// gauche, plus en fond plein.
    func body(content: Content) -> some View {
        content
            .background(shape.fill(MenuBackground.color))
            .overlay(alignment: .leading) {
                if let tint { Rectangle().fill(tint).frame(width: 3).allowsHitTesting(false) }
            }
            .overlay(shape.strokeBorder(Swiss.line, lineWidth: 1))
    }
}

/// Bouton principal : verre teinté sur macOS 26 (préférence active), bouton accentué sinon.
private struct PrimaryButtonStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.buttonStyle(CapsuleButtonStyle(prominent: true))
    }
}

/// Ancien groupe de surfaces de verre : simple conteneur depuis qu'il n'y a plus de verre (29/10).
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat = 8
    @ViewBuilder let content: () -> Content

    var body: some View { content() }
}

/// Bouton secondaire : verre sur macOS 26 (préférence active), bordé sinon.
private struct SecondaryButtonStyleModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.buttonStyle(CapsuleButtonStyle(prominent: false))
    }
}

/// Bouton du style suisse (01/11) : rectangle aux coins carrés, texte en capitales espacées ; blanc plein et texte
/// noir pour l'action (`prominent`), sinon noir bordé de blanc. Taille d'après `controlSize`. (Nom gardé : il est
/// utilisé partout.)
struct CapsuleButtonStyle: ButtonStyle {
    var prominent: Bool
    @Environment(\.controlSize) private var size
    @Environment(\.isEnabled) private var enabled

    private var metrics: (height: CGFloat, font: CGFloat, padding: CGFloat) {
        if #available(macOS 14.0, *), size == .extraLarge { return (42, 12.5, 22) }
        switch size {
        case .mini: return (20, 9.5, 8)
        case .small: return (24, 10.5, 10)
        case .large: return (38, 12, 18)
        default: return (32, 11, 14)
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        let m = metrics
        return configuration.label
            .font(Swiss.font(m.font))
            .tracking(m.font * 0.1)
            .textCase(.uppercase)
            .foregroundStyle(prominent ? Swiss.background : Swiss.text)
            .padding(.horizontal, m.padding)
            .frame(minHeight: m.height)
            .background(Rectangle().fill(prominent ? Swiss.text : Swiss.background))
            .overlay(Rectangle().strokeBorder(Swiss.text, lineWidth: 1))
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.35)
            .contentShape(Rectangle())
    }
}

/// Fond de la liste toujours transparent : le fond plein de la fenêtre passe dessous ; les cartes gardent leur propre
/// fond, lisible.
private struct GlassListBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.scrollContentBackground(.hidden)
    }
}

extension View {
    /// Liste posée sur le fond translucide de la fenêtre.
    func glassListBackground() -> some View {
        modifier(GlassListBackground())
    }

    /// Bouton posé sur une surface de verre (notification, avertissement) : simple remplissage, jamais de verre sur
    /// du verre (WWDC25 219).
    func onGlassButton() -> some View {
        buttonStyle(CapsuleButtonStyle(prominent: false))
    }

    /// Identité de verre : deux surfaces du même GlassGroup se fondent l'une dans l'autre en apparaissant.
    func glassID(_ id: String, in ns: Namespace.ID) -> some View { self }

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

    var body: some View {
        // Style suisse : un carré bordé de gris, sans relief ni verre (`glass` gardé pour les appels d'avant).
        face
            .background(Rectangle().fill(Swiss.background))
            .overlay(Rectangle().strokeBorder(Swiss.keyLine, lineWidth: 1))
            .accessibilityHidden(true)
    }

    private var face: some View {
        VStack(spacing: 1) {
            Text(symbol).font(Swiss.font(large ? 15 : 11.5)).foregroundStyle(Swiss.text)
            if large, let name {
                Text(name).font(Swiss.font(9, .regular)).foregroundStyle(Swiss.gray)
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

    private var shape: Rectangle { Rectangle() }

    /// Style suisse (01/11) : touche changée pleine de rouge ; sinon un carré noir bordé de gris.
    private var fill: Color { accent ? Swiss.red : Swiss.background }

    private var border: AnyShapeStyle { AnyShapeStyle(accent ? Swiss.red : Swiss.keyLine) }

    var body: some View {
        Group {
            if let combo {
                // Une case par touche, comme sur la maquette du 28/10 : ⌘ puis A, pas « ⌘A » dans un seul cadre.
                HStack(spacing: 3) {
                    ForEach(Array(Self.parts(of: combo).enumerated()), id: \.offset) { _, part in
                        tile(Text(part).foregroundStyle(Swiss.text))
                    }
                }
            } else {
                tile(Text(placeholder).foregroundStyle(.secondary))
            }
        }
        .font(Swiss.font(11.5))
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
            .padding(.horizontal, 5)
            .frame(minWidth: 20, minHeight: 20)
            .background(shape.fill(fill))
            .overlay(shape.strokeBorder(border, lineWidth: 1))
    }
}

// MARK: - Icônes

/// Icône de rubrique façon Réglages Système : symbole blanc sur un carré arrondi coloré, liseré clair en haut
/// comme un reflet. Couche de contenu (la couleur y a sa place, WWDC25 219) : aucun verre, aucun flou, statique.
struct SectionIcon: View {
    let symbol: String
    let tint: Color
    var size: CGFloat = 20
    /// Dans une option survolée (fond de sa couleur) : blanc translucide, sinon l'icône disparaîtrait dans le fond.
    @Environment(\.hoverFilled) private var hoverFilled

    var body: some View {
        // Style suisse (01/11) : un carré plat de sa couleur, coins droits, symbole noir.
        Rectangle().fill(tint)
            .overlay(Image(systemName: symbol)
                .symbolVariant(.fill)
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(Swiss.background))
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
                Image(systemName: "checkmark")
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(Swiss.background)
                    .frame(width: 18, height: 18)
                    .background(Rectangle().fill(Swiss.text))
            } else {
                Text("\(number)")
                    .font(Swiss.font(11).monospacedDigit())
                    .foregroundStyle(Swiss.background)
                    .frame(width: 18, height: 18)
                    .background(Rectangle().fill(Swiss.red))
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
    /// `hover` : au survol, la ligne entière prend cette couleur, comme une option du menu de l'icône (d'un filet à
    /// l'autre et toute la largeur de la carte), texte en blanc.
    func cardRow(_ position: CardRowPosition, hover: Color? = nil, selected: Bool = false, stamp: Color? = nil) -> some View {
        modifier(CardRowModifier(position: position, hover: hover, selected: selected, stamp: stamp))
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
/// jusqu'aux filets qui la séparent de ses voisines. Survol : c'est le fond de la ligne, toute la largeur de la carte,
/// qui prend la couleur et s'élargit ; le contenu ne bouge pas, son texte passe en blanc (29/10, « intérieur plein »).
private struct CardRowModifier: ViewModifier {
    let position: CardRowPosition
    let hover: Color?
    /// Ligne choisie (style suisse) : blanche jusqu'aux bords, texte noir, comme au survol.
    var selected = false
    /// Survolée ou choisie : elle se soulève et laisse voir dessous une encoche de cette couleur (comme les cartes de
    /// Gumroad, demande du 01/11 : blocs des macros).
    var stamp: Color? = nil
    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let gap = CardRowBackground.gap
        let lifted = selected || (hovering && hover != nil)
        let row = content
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .hoverFilled(lifted)
            .offset(x: lifted && stamp != nil ? -2 : 0, y: lifted && stamp != nil ? -2 : 0)
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
        .listRowBackground(CardRowBackground(position: position, hover: lifted ? (hover ?? Swiss.text) : nil, stamp: stamp,
                                             grow: lifted && !reduceMotion))
    }
}

/// Fond d'une ligne de carte : rectangle arrondi seulement aux bouts de la carte, filet sous les lignes intérieures.
/// Carte grise sur le fond de la page, comme le Form groupé (verre ou non). Survolée (`hover`) : pleine de la couleur
/// de la page, arrondie, un peu plus large que la carte (`grow`).
struct CardRowBackground: View {
    static let inset: CGFloat = 10                       // marge de la carte dans la liste
    static let gap: CGFloat = 4                          // espace au-dessus et au-dessous d'une carte
    /// Survol : la ligne s'élargit de 6 points de chaque côté (dans la marge de la carte, jamais rognée) ; ses coins
    /// arrondis de 6 couvrent ceux de la carte.
    static let liftOutset: CGFloat = 6
    let position: CardRowPosition
    var hover: Color? = nil
    /// Encoche de couleur sous la ligne soulevée (voir `cardRow(stamp:)`).
    var stamp: Color? = nil
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
            if hover != nil, let stamp {
                // Soulevée : la ligne blanche monte de 2 points vers la gauche et le haut, l'encoche de couleur reste
                // dessous, décalée de 4 points (comme Gumroad).
                ZStack {
                    Rectangle().fill(stamp).padding(.leading, 4).padding(.top, 4)
                    Rectangle().fill(Swiss.text).padding(.trailing, 4).padding(.bottom, 4)
                }
            } else if hover != nil {
                // Survolée : blanc plein, coins carrés (style suisse, 01/11).
                Rectangle().fill(Swiss.text)
            } else if Swiss.flat {
                // Style suisse : pas de carte, un trait fin sous chaque ligne (blanc au-dessus de la première).
                Rectangle().fill(Swiss.background)
                    .overlay(alignment: .top) {
                        if position.roundsTop { Rectangle().fill(Swiss.line).frame(height: 1) }
                    }
                    .overlay(alignment: .bottom) { Rectangle().fill(Swiss.faint).frame(height: 1) }
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

extension Swiss {
    /// Cartes à plat (vrai : le style suisse ; l'ancien dessin des plaques reste dans le code, éteint).
    static let flat = true
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

/// Carte d'un seul tenant en plaque de verre (accueil, guide, panneau des autorisations) ; sans l'effet, voile clair
/// et bord fin.
struct GlassPlateBackground: View {
    var cornerRadius: CGFloat = 14
    @Environment(\.colorScheme) private var scheme
    @AppStorage(Appearance.glassKey) private var glassEnabled = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = Rectangle()
        if Swiss.flat {
            // Style suisse : un cadre fin, sans voile.
            shape.fill(Swiss.background).overlay(shape.strokeBorder(Swiss.line, lineWidth: 1))
        } else if GlassPlate.on(glass: glassEnabled, reduceTransparency: reduceTransparency,
                         increasedContrast: contrast == .increased) {
            shape.fill(GlassPlate.fill(scheme))
                .overlay(shape.strokeBorder(GlassPlate.rim(scheme), lineWidth: 1))
        } else {
            shape.fill(Color.primary.opacity(0.045))
                .overlay(shape.strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
        }
    }
}

/// Lignes posées dans une seule plaque de verre, séparées par un trait fin.
struct PlateRows<Data: RandomAccessCollection, Row: View>: View where Data.Element: Identifiable {
    let data: Data
    @ViewBuilder let row: (Data.Element) -> Row

    var body: some View {
        VStack(spacing: 0) {
            ForEach(data) { item in
                if item.id != data.first?.id { Rectangle().fill(Swiss.faint).frame(height: 1).padding(.horizontal, 12) }
                row(item)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(GlassPlateBackground())
    }
}

/// Anneau fixe de la couleur d'accent : ce qui est attendu (aucune animation continue).
struct WaitingRing: View {
    var size: CGFloat = 14

    var body: some View {
        Circle()
            .stroke(Swiss.line, lineWidth: 2)
            .overlay(Circle().trim(from: 0, to: 0.25).stroke(Swiss.red, lineWidth: 2)
                .rotationEffect(.degrees(-45)))
            .frame(width: size, height: size)
            .accessibilityHidden(true)
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

/// Interrupteur du style suisse (01/11) : un rectangle bordé de blanc ; allumé, blanc plein et carré noir à droite ;
/// éteint, noir et carré blanc à gauche.
struct SwissSwitch: View {
    @Binding var isOn: Bool
    var label: String
    /// Sur une ligne blanche (survolée, choisie) : couleurs inversées, contour noir, le carré reste lisible (01/11 :
    /// « il ne reste plus qu'un point noir »).
    @Environment(\.hoverFilled) private var onWhite

    var body: some View {
        let ink = onWhite ? Swiss.background : Swiss.text
        let paper = onWhite ? Swiss.text : Swiss.background
        return Button { isOn.toggle() } label: {
            HStack(spacing: 0) {
                if isOn { Spacer(minLength: 0) }
                Rectangle().fill(isOn ? paper : ink).frame(width: 14, height: 14)
                if !isOn { Spacer(minLength: 0) }
            }
            .padding(2)
            .frame(width: 40, height: 20)
            .background(Rectangle().fill(isOn ? ink : paper))
            // Le carré glisse (0,18 s, ralenti à la fin), au lieu de sauter.
            .animation(.easeOut(duration: 0.18), value: isOn)
            .overlay(Rectangle().strokeBorder(ink, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityValue(isOn ? String(localized: "activé") : String(localized: "désactivé"))
        .accessibilityAddTraits(.isButton)
    }
}

/// Barre de progression du style suisse : un trait gris de 4 points, rempli de rouge jusqu'où on en est.
struct SwissProgress: View {
    var value: Double

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Rectangle().fill(Swiss.line)
                Rectangle().fill(Swiss.red).frame(width: g.size.width * max(0, min(1, value)))
            }
        }
        .frame(height: 4)
        .accessibilityElement()
        .accessibilityValue("\(Int((max(0, min(1, value)) * 100).rounded())) %")
    }
}

/// Poignée à six points (deux colonnes de trois) : ce qui se prend et se glisse (familles de l'Organiser).
struct SixDots: View {
    var color: Color = Swiss.gray

    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 3) {
                    Rectangle().fill(color).frame(width: 2.5, height: 2.5)
                    Rectangle().fill(color).frame(width: 2.5, height: 2.5)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
