// Logo de FL Shortcuts dans la barre des menus : le rond A (choisi le 04/11), tout en blanc depuis le 05/11 (session du
// site, marque/rond-A-barre-blanc.svg : « l'icône qui est en haut à droite dans mac, on gardera le logo qu'il a déjà
// mais tout en blanc » ; l'icône de l'app, elle, devient « fl. »). Le rond plein et le grand cercle décalé en haut à
// droite, séparés par un jour pour qu'on les distingue en petit. Image modèle de macOS (choix du 05/11 : « blanc, noir
// si la barre est claire ») : macOS la peint en blanc sur une barre sombre et en noir sur une barre claire, comme
// toutes les icônes de la barre. L'état ne remplace pas le logo : une pastille en haut à droite, « ! » quand les
// raccourcis sont inactifs (Accessibilité, saisie sécurisée), deux barres en pause.
// Dessiné une fois par état, dans des images à part (1x et 2x) : la barre n'en choisit qu'une.
import AppKit

enum MenuBarIcon {
    enum State: CaseIterable {
        case normal, warning, paused
    }

    /// État d'après le symbole choisi par AppStatus.menuBarSymbol (mêmes règles qu'avant).
    static func state(forSymbol symbol: String) -> State {
        switch symbol {
        case "pause.circle.fill": return .paused
        case "exclamationmark.triangle.fill": return .warning
        default: return .normal
        }
    }

    private static let side: CGFloat = 18
    private static let cache = Locked<[State: NSImage]>([:])

    static func image(_ state: State) -> NSImage {
        if let image = cache.value[state] { return image }
        let image = drawn(state)
        image.isTemplate = true
        switch state {
        case .normal: image.accessibilityDescription = "FL Shortcuts"
        case .warning: image.accessibilityDescription = String(localized: "FL Shortcuts : raccourcis inactifs")
        case .paused: image.accessibilityDescription = String(localized: "FL Shortcuts : en pause")
        }
        cache.withLock { $0[state] = image }
        return image
    }

    /// Le logo et sa pastille, en noir sur transparent (la barre les teinte), en 1x et 2x (lu aussi par
    /// MenuBarIconTests).
    static func drawn(_ state: State) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side))
        for scale in [1, 2] {
            if let rep = rep(state, scale: scale) { image.addRepresentation(rep) }
        }
        return image
    }

    /// Dessin dans une image à part (les effacements ne touchent jamais la barre des menus elle-même).
    private static func rep(_ state: State, scale: Int) -> NSBitmapImageRep? {
        let pixels = Int(side) * scale
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        rep.size = NSSize(width: side, height: side)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        // Le contexte compte en pixels : on dessine en points (x scale), origine en haut à gauche comme le logo.
        let flip = NSAffineTransform()
        flip.translateX(by: 0, yBy: CGFloat(pixels))
        flip.scaleX(by: CGFloat(scale), yBy: -CGFloat(scale))
        flip.concat()
        draw(state, in: context)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private static func draw(_ state: State, in context: NSGraphicsContext) {
        // Le dessin sur 1024 (rond-A-barre-blanc.svg) : cercle (590, 440) de rayon 365, trait de 70 ; un jour de
        // rayon 345 autour du rond ; rond plein (470, 580) de rayon 290.
        let k = side / 1024
        NSColor.black.setStroke()
        NSColor.black.setFill()
        let outline = circle(NSPoint(x: 590 * k, y: 440 * k), radius: 365 * k)
        outline.lineWidth = 70 * k
        outline.stroke()
        erase(circle(NSPoint(x: 470 * k, y: 580 * k), radius: 345 * k), in: context)
        circle(NSPoint(x: 470 * k, y: 580 * k), radius: 290 * k).fill()
        guard state != .normal else { return }
        // Pastille d'état en haut à droite, détachée du reste par un anneau vide.
        let center = NSPoint(x: 13.8, y: 4.2)
        if state == .warning {
            // Avertissement suisse (08/11 : « pas un emoji d'attention… un point orange ») : un carré plein, sans « ! ».
            erase(NSBezierPath(rect: NSRect(x: center.x - 4.6, y: center.y - 4.6, width: 9.2, height: 9.2)), in: context)
            NSColor.black.setFill()
            NSBezierPath(rect: NSRect(x: center.x - 3.4, y: center.y - 3.4, width: 6.8, height: 6.8)).fill()
            return
        }
        erase(circle(center, radius: 5.1), in: context)
        NSColor.black.setFill()
        circle(center, radius: 3.9).fill()
        switch state {
        case .warning:
            break
        case .paused:
            for dx: CGFloat in [-1.15, 1.15] {
                erase(NSBezierPath(roundedRect: NSRect(x: center.x + dx - 0.6, y: center.y - 1.7, width: 1.2, height: 3.4),
                                   xRadius: 0.5, yRadius: 0.5), in: context)
            }
        case .normal:
            break
        }
    }

    private static func circle(_ center: NSPoint, radius r: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: 2 * r, height: 2 * r))
    }

    /// Efface (rend transparent) l'intérieur du chemin.
    private static func erase(_ path: NSBezierPath, in context: NSGraphicsContext) {
        context.compositingOperation = .clear
        path.fill()
        context.compositingOperation = .sourceOver
    }
}
