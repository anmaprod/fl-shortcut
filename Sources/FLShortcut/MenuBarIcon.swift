// Logo de FL Shortcuts dans la barre des menus : le logo « A » (choisi par le propriétaire le 04/11, à la place du petit
// clavier) : un rond rouge plein devant un grand cercle à trait épais (rond-A-barre-*, marque/ de la session du site),
// le cercle au centre (recadré le 04/11 : « pour que le rond blanc soit au centre »). Toujours en couleurs (demande
// du 04/11 : « dans les couleurs… pas en noir et blanc ») : jamais une image modèle (template), que macOS teindrait
// d'une seule couleur. Le rond reste rouge ; le cercle est blanc sur une barre sombre et noir sur une barre claire,
// choisi au moment où la barre dessine l'image (son apparence, qui suit le fond d'écran). L'état ne remplace pas le
// logo : une pastille en haut à droite, « ! » quand les raccourcis sont inactifs (Accessibilité, saisie sécurisée),
// deux barres en pause.
// Dessiné une fois par état et par apparence, dans des images à part (1x et 2x) : la barre n'en choisit qu'une.
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
    /// Le rouge de la marque (#FF3B1F).
    private static let red = NSColor(srgbRed: 1, green: 0x3B / 255, blue: 0x1F / 255, alpha: 1)

    static func image(_ state: State) -> NSImage {
        if let image = cache.value[state] { return image }
        let onLight = drawn(state, ring: .black), onDark = drawn(state, ring: .white)
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let dark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            (dark ? onDark : onLight).draw(in: rect)
            return true
        }
        image.isTemplate = false
        switch state {
        case .normal: image.accessibilityDescription = "FL Shortcuts"
        case .warning: image.accessibilityDescription = String(localized: "FL Shortcuts : raccourcis inactifs")
        case .paused: image.accessibilityDescription = String(localized: "FL Shortcuts : en pause")
        }
        cache.withLock { $0[state] = image }
        return image
    }

    /// Le logo et sa pastille, cercle de la couleur `ring`, en 1x et 2x.
    private static func drawn(_ state: State, ring: NSColor) -> NSImage {
        let image = NSImage(size: NSSize(width: side, height: side))
        for scale in [1, 2] {
            if let rep = rep(state, ring: ring, scale: scale) { image.addRepresentation(rep) }
        }
        return image
    }

    /// Dessin dans une image à part (les effacements ne touchent jamais la barre des menus elle-même).
    private static func rep(_ state: State, ring: NSColor, scale: Int) -> NSBitmapImageRep? {
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
        draw(state, ring: ring, in: context)
        context.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    private static func draw(_ state: State, ring color: NSColor, in context: NSGraphicsContext) {
        // Le dessin sur 1024 : cercle au centre (512, 512) de rayon 370, trait de 60 ; rond (392, 652) de 290.
        let k = side / 1024
        let outline = circle(NSPoint(x: 512 * k, y: 512 * k), radius: 370 * k)
        outline.lineWidth = 60 * k
        color.setStroke()
        outline.stroke()
        red.setFill()
        circle(NSPoint(x: 392 * k, y: 652 * k), radius: 290 * k).fill()
        guard state != .normal else { return }
        // Pastille d'état en haut à droite, détachée du reste par un anneau vide.
        let center = NSPoint(x: 13.8, y: 4.2)
        erase(circle(center, radius: 5.1), in: context)
        color.setFill()
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
