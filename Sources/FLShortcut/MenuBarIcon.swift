// Logo de FL Shortcut dans la barre des menus : les deux touches de l'icône de l'app (une derrière, une devant avec
// une forme d'onde), dessinées en image modèle (template) : macOS la teinte comme les autres icônes de la barre, en
// clair ou en sombre. L'état ne remplace plus le logo : une pastille en haut à droite prend la place de la touche de
// derrière, « ! » quand les raccourcis sont inactifs (Accessibilité, saisie sécurisée), deux barres en pause.
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
        case .normal: image.accessibilityDescription = "FL Shortcut"
        case .warning: image.accessibilityDescription = "FL Shortcut : raccourcis inactifs"
        case .paused: image.accessibilityDescription = "FL Shortcut : en pause"
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
        let front = NSRect(x: 1, y: 5.5, width: 11.5, height: 11.5)       // en bas à gauche
        let back = NSRect(x: 6.5, y: 1, width: 10.5, height: 10.5)        // en haut à droite
        if state == .normal {
            let outline = NSBezierPath(roundedRect: back.insetBy(dx: 0.7, dy: 0.7), xRadius: 2.6, yRadius: 2.6)
            outline.lineWidth = 1.4
            outline.stroke()
            // Écart entre les deux touches.
            erase(NSBezierPath(roundedRect: front.insetBy(dx: -1.3, dy: -1.3), xRadius: 4.2, yRadius: 4.2), in: context)
        }
        NSBezierPath(roundedRect: front, xRadius: 3, yRadius: 3).fill()
        // Forme d'onde évidée dans la touche de devant.
        let heights: [CGFloat] = [3, 6.5, 4.5, 7.5, 3.5]
        let bar: CGFloat = 1.3, gap: CGFloat = 0.75
        var x = front.midX - (CGFloat(heights.count) * bar + CGFloat(heights.count - 1) * gap) / 2
        for h in heights {
            erase(NSBezierPath(roundedRect: NSRect(x: x, y: front.midY - h / 2, width: bar, height: h),
                               xRadius: bar / 2, yRadius: bar / 2), in: context)
            x += bar + gap
        }
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
