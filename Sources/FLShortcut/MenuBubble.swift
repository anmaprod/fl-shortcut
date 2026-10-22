// Menu de l'icône en bulle : on garde le menu de SwiftUI (`MenuBarExtra` en fenêtre : icône, ouverture, fermeture,
// `openWindow`, commandes de la CI) et on rend seulement sa fenêtre transparente pour y dessiner notre bulle. À
// chaque ouverture, une pastille de la taille de l'icône part de l'icône (son cadre à l'écran, même quand macOS
// décale le menu près d'un bord) et devient la bulle du menu (ressort doux) ; les lignes arrivent l'une après
// l'autre quand la bulle est presque posée. À la fermeture, la bulle rentre dans l'icône.
// Repli automatique, jamais de menu cassé : fond de macOS introuvable, fenêtre d'une forme inattendue, ou
// `defaults write app.flshortcut.FLShortcut legacyMenu -bool YES` (puis relancer l'app) → le menu d'avant, inchangé.
// Verre : macOS 26 avec « Effet Liquid Glass » ; sinon (ou « Réduire la transparence ») bulle opaque avec la lueur
// de marque, jamais un voile plat.
import AppKit
import SwiftUI

enum MenuBubbleStyle {
    /// Verre de macOS 26 pour la bulle ; faux : bulle opaque partout (si le verre se montrait plat ou sans flou).
    static var glass = true
}

enum MenuBubbleSupport {
    static let legacyKey = "legacyMenu"

    /// Prépare la fenêtre du menu pour notre bulle : fond de macOS (`NSVisualEffectView` hors de notre contenu)
    /// masqué, fenêtre transparente sans ombre. Vrai : bulle à nous ; faux : rien n'a changé (ancien menu). `host` :
    /// vue SwiftUI du menu, cherchée seule si nil. Rappelé à chaque ouverture (macOS peut remettre son fond).
    @discardableResult
    static func prepare(_ window: NSWindow, legacy: Bool, host: NSView? = nil) -> Bool {
        guard !legacy, let root = window.contentView?.superview ?? window.contentView,
              let host = host ?? hostingView(in: root) else { return false }
        let effects = visualEffects(in: root, outside: host)
        guard !effects.isEmpty else { return false }
        for effect in effects {
            if host.isDescendant(of: effect) {
                // Notre contenu est dedans : le cacher le cacherait aussi. Seul son verre est masqué (le masque ne
                // touche pas les vues qu'il contient).
                effect.maskImage = clearMask
            } else {
                effect.isHidden = true
            }
        }
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        return true
    }

    /// Image entièrement transparente : le verre de macOS ne se dessine plus nulle part.
    static let clearMask = NSImage(size: NSSize(width: 1, height: 1), flipped: false) { _ in true }

    /// Première vue SwiftUI de la fenêtre (le contenu du menu).
    static func hostingView(in view: NSView) -> NSView? {
        if String(describing: type(of: view)).contains("NSHostingView") { return view }
        for sub in view.subviews {
            if let found = hostingView(in: sub) { return found }
        }
        return nil
    }

    /// Fonds de macOS de la fenêtre, jamais à l'intérieur de notre contenu (le verre de nos propres vues y reste).
    static func visualEffects(in view: NSView, outside host: NSView) -> [NSVisualEffectView] {
        if view === host { return [] }
        var out: [NSVisualEffectView] = []
        if let effect = view as? NSVisualEffectView { out.append(effect) }
        for sub in view.subviews { out += visualEffects(in: sub, outside: host) }
        return out
    }
}

enum MenuBubbleGeometry {
    /// Marge transparente autour de la bulle, pour son ombre (rien en haut : elle touche la barre des menus).
    static let margin = EdgeInsets(top: 0, leading: 20, bottom: 28, trailing: 20)
    static let pillHeight: CGFloat = 24
    static let minPillWidth: CGFloat = 28
    static let radius: CGFloat = 18

    /// Pastille de départ sous l'icône, dans le contenu de la fenêtre (origine en haut à gauche) : `icon` et `window`
    /// à l'écran (origine en bas). Gardée dans la largeur de la fenêtre.
    static func pill(icon: CGRect, window: CGRect) -> CGRect {
        let width = max(icon.width, minPillWidth)
        let x = min(max(icon.midX - window.minX - width / 2, 0), max(window.width - width, 0))
        return CGRect(x: x, y: 0, width: width, height: pillHeight)
    }

    /// Cadre de la bulle posée : tout le contenu, moins la marge.
    static func content(in size: CGSize) -> CGRect {
        CGRect(x: margin.leading, y: margin.top,
               width: max(size.width - margin.leading - margin.trailing, 0),
               height: max(size.height - margin.top - margin.bottom, 0))
    }
}

/// La bulle à `progress` (0 = pastille sous l'icône, 1 = bulle posée), dans toute la fenêtre.
struct MenuBubbleShape: Shape {
    var progress: CGFloat
    let pill: CGRect

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let frame = FlightGeometry.rect(at: progress, from: pill, to: MenuBubbleGeometry.content(in: rect.size))
        let radius = min(MenuBubbleGeometry.radius, frame.height / 2, frame.width / 2)
        return Path(roundedRect: frame, cornerRadius: max(radius, 0), style: .continuous)
    }
}

extension View {
    /// Contenu du menu dans notre bulle (ou, en repli, déployé dans la bulle de macOS comme avant).
    func menuBubble(_ panel: MenuPanel) -> some View {
        modifier(MenuBubbleModifier(panel: panel))
    }
}

private struct MenuBubbleModifier: ViewModifier {
    @ObservedObject var panel: MenuPanel
    @Environment(\.accessibilityReduceMotion) private var reduceMotionSetting

    private var reduceMotion: Bool { reduceMotionSetting && DebugSnapshot.slowMotion == 1 }

    func body(content: Content) -> some View {
        if panel.bubble {
            // Mouvement réduit : la bulle déjà posée apparaît en fondu, sans vol.
            let shape = MenuBubbleShape(progress: reduceMotion || panel.revealed ? 1 : 0, pill: panel.pillFrame)
            content
                .padding(MenuBubbleGeometry.margin)
                .mask { shape }
                .background { MenuBubbleBackground(shape: shape) }
                .opacity(reduceMotion && !panel.revealed ? 0 : 1)
        } else {
            content.menuReveal(panel.revealed)
        }
    }
}

/// Fond de la bulle : verre de macOS 26 (préférence active, transparence non réduite), sinon fond de fenêtre
/// opaque avec un filet ; ombre dessinée par nous (la fenêtre n'en a plus).
private struct MenuBubbleBackground: View {
    let shape: MenuBubbleShape
    @AppStorage(Appearance.glassKey) private var glassEnabled = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        surface.shadow(color: Color.black.opacity(0.25), radius: 18, y: 8)
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
