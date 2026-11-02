// Logo de FL Shortcuts dans la barre des menus : le petit clavier de l'icône de l'app (choisi par le propriétaire le
// 02/11 : « le petit clavier, c'est très bien pour l'icône »), une tuile pleine où le clavier est évidé (cadre, quatre
// touches, barre d'espace), en image modèle (template) : macOS la teinte comme les autres icônes de la barre, en clair
// ou en sombre. L'état ne remplace pas le logo : une pastille en haut à droite, « ! » quand les raccourcis sont
// inactifs (Accessibilité, saisie sécurisée), deux barres en pause.
// Dessiné une fois par état, dans des images à part (1x et 2x) : aucun dessin à chaque rafraîchissement de la barre.
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
        let image = NSImage(size: NSSize(width: side, height: side))
        for scale in [1, 2] {
            if let rep = rep(state, scale: scale) { image.addRepresentation(rep) }
        }
        image.isTemplate = true
        switch state {
        case .normal: image.accessibilityDescription = "FL Shortcuts"
        case .warning: image.accessibilityDescription = String(localized: "FL Shortcuts : raccourcis inactifs")
        case .paused: image.accessibilityDescription = String(localized: "FL Shortcuts : en pause")
        }
        cache.withLock { $0[state] = image }
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
        // Le contexte compte en pixels : on dessine en points (x scale), origine en haut à gauche comme l'icône.
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
        NSColor.black.set()
        // La tuile pleine, en paysage.
        let tile = NSRect(x: 0.5, y: 3, width: 17, height: 12.5)
        NSBezierPath(rect: tile).fill()
        // Le clavier évidé, d'après le dessin de 15 × 11 unités (cadre de 1,2, touches de 1,6, espace de 7).
        let k: CGFloat = 0.78
        let ox = tile.midX - 7.5 * k, oy = tile.midY - 5.5 * k
        func unit(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
            NSRect(x: ox + x * k, y: oy + y * k, width: w * k, height: h * k)
        }
        erase(NSBezierPath(rect: unit(0, 0, 15, 11)), in: context)
        NSBezierPath(rect: unit(1.2, 1.2, 12.6, 8.6)).fill()
        for x: CGFloat in [2.5, 5.2, 7.9, 10.6] { erase(NSBezierPath(rect: unit(x, 2.6, 1.6, 1.6)), in: context) }
        erase(NSBezierPath(rect: unit(4, 6.6, 7, 1.6)), in: context)
        guard state != .normal else { return }
        // Pastille d'état en haut à droite, détachée du reste par un anneau vide.
        let center = NSPoint(x: 13.8, y: 4.2)
        erase(circle(center, radius: 5.1), in: context)
        circle(center, radius: 3.9).fill()
        switch state {
        case .warning:
            erase(NSBezierPath(roundedRect: NSRect(x: center.x - 0.65, y: center.y - 2.5, width: 1.3, height: 3.1),
                               xRadius: 0.65, yRadius: 0.65), in: context)
            erase(circle(NSPoint(x: center.x, y: center.y + 1.9), radius: 0.75), in: context)
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
