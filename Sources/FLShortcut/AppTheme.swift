// Thèmes de l'app (demande du 04/11 : « dans mon compte la possibilité de changer de thèmes ») : Noir, le style suisse
// d'origine ; Papier, blanc à l'encre noire ; Orange, le rouge de la marque en fond, la barre de gauche et les cartes
// en noir. D'après les maquettes validées (artefact 1EFC8zLVn5ATRWAnQMBZrB). Choisi dans Mon compte, gardé dans les
// réglages : rien de sensible n'en dépend (un autre programme qui l'écrirait ne changerait que les couleurs). Depuis le
// 07/11, seulement avec un compte connecté : sans compte, Noir (le choix est gardé pour la prochaine connexion).
//
// Les couleurs du style suisse (`Swiss`) se lisent au moment du dessin, d'après le thème et l'apparence de macOS
// (sombre pour Noir, claire pour Papier et Orange) : rien à reconstruire, la fenêtre se redessine quand l'apparence
// change. Une partie sombre sous Orange (barre de gauche, cartes, petites fenêtres) prend les couleurs « inversées ».
import AppKit
import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case noir, papier, orange

    var id: String { rawValue }

    /// Clé du réglage.
    static let key = "theme"
    /// Dernier état connu du compte (connecté ou non), pour le lancement : le Trousseau n'est lu qu'ensuite.
    static let accountKey = "themeAccount"

    /// Thème choisi dans Mon compte (enregistré) ; Noir si rien n'est choisi ou si la valeur est inconnue.
    private static let saved = Locked<AppTheme?>(nil)
    /// Thème montré sans rien enregistrer (essais, photos de la CI) : passe avant tout.
    private static let forced = Locked<AppTheme?>(nil)
    /// Compte connecté ou non (nil : pas encore su, dernier état connu des réglages).
    private static let account = Locked<Bool?>(nil)

    /// Thème affiché, lu à chaque dessin. Demande du 07/11 (« les thèmes… que si la personne crée un compte ou se
    /// connecte ») : sans compte connecté, toujours Noir ; le choix est gardé et revient à la connexion.
    static var current: AppTheme {
        if let theme = forced.value { return theme }
        return unlocked ? chosen : .noir
    }

    /// Thème choisi dans Mon compte, même sans compte connecté (il n'est alors pas affiché).
    static var chosen: AppTheme {
        if let theme = saved.value { return theme }
        let theme = AppTheme(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .noir
        saved.withLock { $0 = theme }
        return theme
    }

    /// Les thèmes sont ouverts : un compte est connecté.
    static var unlocked: Bool {
        if let signedIn = account.value { return signedIn }
        let signedIn = UserDefaults.standard.bool(forKey: accountKey)
        account.withLock { $0 = signedIn }
        return signedIn
    }

    /// Thème pris sans rien enregistrer (essais, photos de la CI), compte ou non ; nil : de nouveau le choix du compte.
    static func use(_ theme: AppTheme?) {
        forced.withLock { $0 = theme }
    }

    var title: String {
        switch self {
        case .noir: return String(localized: "Noir")
        case .papier: return String(localized: "Papier")
        case .orange: return String(localized: "Orange")
        }
    }

    /// Apparence de macOS sous le thème : sombre pour Noir ; claire pour Papier et Orange, dont le texte est noir.
    var appearanceName: NSAppearance.Name { self == .noir ? .darkAqua : .aqua }

    /// Petites fenêtres (questions, feuilles, menu de l'icône) : noires sous Orange, comme ses cartes.
    var floatingAppearanceName: NSAppearance.Name { self == .papier ? .aqua : .darkAqua }

    /// Sous Orange, une partie sombre (barre de gauche, carte) : noire, texte blanc.
    static var invertsSurfaces: Bool { current == .orange }

    /// Au lancement, avant la première fenêtre : rien ne s'affiche dans un autre thème.
    @MainActor static func applyAtLaunch() {
        NSApp.appearance = NSAppearance(named: current.appearanceName)
    }

    /// Choisit le thème (page Mon compte) : enregistré, puis toute l'app redessinée.
    /// `save` faux : montré sans être enregistré, compte ou non (photos de la CI, DebugSnapshot.theme).
    @MainActor static func choose(_ theme: AppTheme, save: Bool = true) {
        let before = current
        if save {
            UserDefaults.standard.set(theme.rawValue, forKey: key)
            saved.withLock { $0 = theme }
            forced.withLock { $0 = nil }
        } else {
            use(theme)
        }
        redraw(from: before)
    }

    /// Connexion ou déconnexion du compte (CommunityStore) : le thème choisi revient, ou Noir sans compte.
    @MainActor static func accountChanged(signedIn: Bool) {
        let before = current
        account.withLock { $0 = signedIn }
        if UserDefaults.standard.bool(forKey: accountKey) != signedIn {
            UserDefaults.standard.set(signedIn, forKey: accountKey)
        }
        redraw(from: before)
    }

    /// Toute l'app redessinée si le thème affiché a changé. Papier et Orange ont la même apparence claire de macOS :
    /// un aller-retour par la sombre fait relire les couleurs à chaque fenêtre.
    @MainActor private static func redraw(from before: AppTheme) {
        let theme = current
        guard theme != before else { return }
        if before.appearanceName == theme.appearanceName {
            NSApp?.appearance = NSAppearance(named: theme.appearanceName == .aqua ? .darkAqua : .aqua)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 80_000_000)
                NSApp?.appearance = NSAppearance(named: current.appearanceName)
                NotificationCenter.default.post(name: changed, object: nil)
            }
        } else {
            NSApp?.appearance = NSAppearance(named: theme.appearanceName)
            NotificationCenter.default.post(name: changed, object: nil)
        }
    }

    /// Le thème a changé : les fenêtres d'AppKit qui gardent une apparence la reprennent.
    static let changed = Notification.Name("FLShortcuts.themeChanged")
}

/// Couleurs du style suisse dans un thème, en sRGB (0xRRGGBB).
struct SwissPalette: Equatable, Sendable {
    let background: UInt32
    let text: UInt32
    /// Texte secondaire.
    let gray: UInt32
    /// Texte de lecture un peu effacé.
    let soft: UInt32
    /// Trait entre deux blocs.
    let line: UInt32
    /// Trait entre deux lignes.
    let faint: UInt32
    /// Cadre d'une touche.
    let keyLine: UInt32
    /// Ce qui compte (touche changée, avertissement) : le rouge de la marque ; blanc sur le fond orange.
    let red: UInt32

    static let brandRed: UInt32 = 0xFF3B1F

    static let noir = SwissPalette(background: 0x000000, text: 0xFFFFFF, gray: 0x8A8A8A, soft: 0xA8A8A8,
                                   line: 0x333333, faint: 0x222222, keyLine: 0x555555, red: brandRed)
    static let papier = SwissPalette(background: 0xFFFFFF, text: 0x000000, gray: 0x6E6E6E, soft: 0x555555,
                                     line: 0xCFCFCF, faint: 0xE6E6E6, keyLine: 0xAAAAAA, red: brandRed)
    static let orange = SwissPalette(background: brandRed, text: 0x000000, gray: 0x3A0B03, soft: 0x2A0702,
                                     line: 0xA62614, faint: 0xD5341B, keyLine: 0x5C1508, red: 0xFFFFFF)
    /// Parties noires sous Orange (barre de gauche, cartes, petites fenêtres).
    static let orangeInverse = SwissPalette(background: 0x000000, text: 0xFFFFFF, gray: 0xB4B4B4, soft: 0xC8C8C8,
                                            line: 0x2C2C2C, faint: 0x222222, keyLine: 0x555555, red: brandRed)

    /// Couleurs d'un thème ; `dark` : partie sombre (apparence sombre de macOS, ou partie inversée sous Orange).
    static func of(_ theme: AppTheme, dark: Bool) -> SwissPalette {
        switch theme {
        case .noir: return .noir
        case .papier: return dark ? .noir : .papier
        case .orange: return dark ? .orangeInverse : .orange
        }
    }

    enum Token: Sendable { case background, text, gray, soft, line, faint, keyLine, red }

    func value(_ token: Token) -> UInt32 {
        switch token {
        case .background: return background
        case .text: return text
        case .gray: return gray
        case .soft: return soft
        case .line: return line
        case .faint: return faint
        case .keyLine: return keyLine
        case .red: return red
        }
    }

    static func nsColor(_ rgb: UInt32, alpha: CGFloat = 1) -> NSColor {
        NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
                blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
    }

    /// Couleur d'AppKit qui suit le thème et l'apparence au moment du dessin.
    static func adaptive(_ token: Token, alpha: CGFloat = 1) -> NSColor {
        NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return nsColor(of(AppTheme.current, dark: dark).value(token), alpha: alpha)
        }
    }
}

extension SwissPalette {
    enum PrimaryPart: Sendable { case fill, ink, shadow, lift }

    /// Bouton principal et carte principale (maquettes du 05/11) : plein blanc sous Noir et Orange, noir sous Papier ;
    /// ombre nette rouge sous Papier, noire sous Orange, aucune sous Noir (et dans les parties sombres).
    static func primary(_ part: PrimaryPart) -> NSColor {
        NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let papier = AppTheme.current == .papier && !dark
            let orange = AppTheme.current == .orange && !dark
            switch part {
            case .fill: return nsColor(papier ? 0x000000 : 0xFFFFFF)
            case .ink: return nsColor(papier ? 0xFFFFFF : 0x000000)
            case .shadow: return papier ? nsColor(brandRed) : orange ? nsColor(0x000000) : .clear
            // Ombre du relief au survol (06/11, « l'effet Gumroad… dans tous les thèmes ») : noire sur le fond orange,
            // rouge partout ailleurs (sous Noir aussi, où le bouton au repos n'a pas d'ombre).
            case .lift: return orange ? nsColor(0x000000) : nsColor(brandRed)
            }
        }
    }
}

extension View {
    /// Partie sombre sous Orange (barre de gauche, petite fenêtre) : couleurs inversées ; rien dans les autres thèmes.
    func swissInverted() -> some View { modifier(SwissInvertedSurface()) }

    /// Bloc posé sur la page (carte de raccourcis, du compte, de l'aide) : sous Orange, une carte noire au texte blanc
    /// comme la maquette ; `padding` : marge ajoutée autour du contenu (0 s'il en a déjà une). Rien ailleurs.
    func swissCard(padding: CGFloat = 0) -> some View { modifier(SwissCardSurface(padding: padding)) }

    /// Carte des maquettes du 05/11 (Mon compte, Aide…) : marge de 22, pleine du fond, trait fin ; noire sous Orange.
    func swissPanel() -> some View {
        padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Rectangle().fill(Swiss.background))
            .overlay(Rectangle().strokeBorder(Swiss.line, lineWidth: 1))
            .swissCard()
    }

    /// `swissCard()` seulement si `on`.
    @ViewBuilder func swissCard(if on: Bool) -> some View {
        if on { swissCard() } else { self }
    }
}

private struct SwissInvertedSurface: ViewModifier {
    /// Lue pour que le choix du thème (aller-retour d'apparence) redessine la partie.
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        content.environment(\.colorScheme, AppTheme.invertsSurfaces ? .dark : scheme)
    }
}

private struct SwissCardSurface: ViewModifier {
    let padding: CGFloat
    @Environment(\.colorScheme) private var scheme

    @ViewBuilder func body(content: Content) -> some View {
        if AppTheme.invertsSurfaces && scheme == .light {
            content
                .padding(padding)
                .background(Rectangle().fill(Swiss.background))
                .environment(\.colorScheme, .dark)
        } else {
            content
        }
    }
}

/// Grille du thème Papier (maquette) : douze colonnes de traits très fins derrière la page ; rien dans les autres.
struct SwissPaperGrid: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if AppTheme.current == .papier && scheme == .light {
            GeometryReader { proxy in
                Path { path in
                    let inset: CGFloat = 26, gap: CGFloat = 20, columns = 12
                    let width = max(0, proxy.size.width - 2 * inset)
                    let column = (width - gap * CGFloat(columns - 1)) / CGFloat(columns)
                    guard column > 0 else { return }
                    for i in 0..<columns {
                        let x = inset + CGFloat(i) * (column + gap)
                        for edge in [x, x + column] {
                            path.move(to: CGPoint(x: edge + 0.5, y: 0))
                            path.addLine(to: CGPoint(x: edge + 0.5, y: proxy.size.height))
                        }
                    }
                }
                .stroke(Color(nsColor: SwissPalette.nsColor(0xEDEDED)), lineWidth: 1)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
