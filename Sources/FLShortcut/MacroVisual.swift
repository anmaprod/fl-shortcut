// « Retrouver ce bouton s'il bouge » : certains boutons de FL changent de place (le « + » du Channel rack descend à
// chaque piste ajoutée), et FL les dessine lui-même, sans nom pour l'Accessibilité. Pour un clic où l'utilisateur
// l'a demandé, et seulement pour lui : une petite image du bouton (niveaux de gris, 1 pixel par point) est prise en
// le montrant dans FL, puis cherchée dans sa fenêtre au moment du clic.
// - Lecture de l'écran : seulement la fenêtre de FL visée, seulement à ce moment-là (jamais au repos, jamais
//   d'enregistrement), avec l'autorisation « Enregistrement de l'écran » demandée quand l'utilisateur active l'option.
//   Rien n'est envoyé ; l'image reste dans la macro et est retirée à l'export.
// - Recherche : corrélation normalisée (insensible à la luminosité), d'abord sur une image réduite au tiers, puis au
//   point près autour des meilleures places ; à score presque égal, la plus proche de l'endroit montré.
import AppKit
import CoreGraphics
import ScreenCaptureKit

/// Bouton retrouvé à son image : où il était quand on l'a montré (fenêtre de FL : coin, décalage, taille, titre de
/// plugin), et son image.
struct VisualSpot: Equatable {
    let corner: Corner
    let dx: Double
    let dy: Double
    let size: CGSize
    var title: String? = nil
    /// Côté de l'image carrée, en points (1 pixel par point), centrée sur le clic.
    let side: Int
    /// Niveaux de gris, ligne par ligne (side × side).
    let pixels: [UInt8]

    static let sides = 12...64
    static let defaultSide = 26

    /// La même place, sans l'image (option désactivée).
    var place: ClickTarget { .flWindow(corner: corner, dx: dx, dy: dy, size: size, title: title) }

    var isValid: Bool {
        func ok(_ v: Double) -> Bool { v.isFinite && abs(v) <= 5000 }
        return ok(dx) && ok(dy) && size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
            && size.width <= 10_000 && size.height <= 10_000 && Self.sides.contains(side) && pixels.count == side * side
            && (title.map { !$0.isEmpty && $0.count <= ClickTarget.maxTitle } ?? true)
    }

    var image: GrayImage { GrayImage(width: side, height: side, pixels: pixels) }
}

/// Image en niveaux de gris (8 bits).
struct GrayImage: Equatable {
    let width: Int
    let height: Int
    var pixels: [UInt8]

    subscript(x: Int, y: Int) -> UInt8 { pixels[y * width + x] }

    /// Carré de `side` centré sur (cx, cy), entièrement dans l'image ; nil sinon.
    func crop(centerX cx: Int, centerY cy: Int, side: Int) -> GrayImage? {
        let x0 = cx - side / 2, y0 = cy - side / 2
        guard side > 0, x0 >= 0, y0 >= 0, x0 + side <= width, y0 + side <= height else { return nil }
        var out = [UInt8](repeating: 0, count: side * side)
        for y in 0..<side {
            let from = (y0 + y) * width + x0
            for x in 0..<side { out[y * side + x] = pixels[from + x] }
        }
        return GrayImage(width: side, height: side, pixels: out)
    }

    /// Réduite d'un facteur entier (moyenne de chaque bloc).
    func reduced(by f: Int) -> GrayImage {
        guard f > 1 else { return self }
        let w = width / f, h = height / f
        var out = [UInt8](repeating: 0, count: max(0, w * h))
        for y in 0..<h {
            for x in 0..<w {
                var sum = 0
                for yy in 0..<f {
                    let row = (y * f + yy) * width + x * f
                    for xx in 0..<f { sum += Int(pixels[row + xx]) }
                }
                out[y * w + x] = UInt8(sum / (f * f))
            }
        }
        return GrayImage(width: w, height: h, pixels: out)
    }

    /// Écart type des niveaux : une image presque unie (fond vide) ne se reconnaît pas.
    var contrast: Double {
        guard !pixels.isEmpty else { return 0 }
        let n = Double(pixels.count)
        var s = 0.0, ss = 0.0
        for p in pixels { let v = Double(p); s += v; ss += v * v }
        let mean = s / n
        return (max(0, ss / n - mean * mean)).squareRoot()
    }
}

enum VisualMatch {
    /// Score minimal (corrélation de -1 à 1) pour dire « c'est ce bouton ».
    static let threshold = 0.8
    /// Contraste minimal de l'image d'un bouton (écart type des niveaux).
    static let minContrast = 8.0

    struct Hit: Equatable {
        /// Centre du bouton dans l'image (pixels).
        let x: Int
        let y: Int
        let score: Double
    }

    /// Pure (testée) : place du bouton `patch` dans `image`, ou nil s'il n'y est pas. `hint` : centre attendu (endroit
    /// montré) ; à score presque égal (0,03), la place la plus proche gagne.
    static func find(_ patch: GrayImage, in image: GrayImage, hint: (x: Int, y: Int)) -> Hit? {
        guard patch.width >= 4, patch.height >= 4, image.width >= patch.width, image.height >= patch.height,
              patch.contrast >= minContrast else { return nil }
        // 1. Image réduite au tiers : toutes les places, les 8 meilleures retenues (pas deux au même endroit).
        let f = patch.width >= 18 ? 3 : 1
        let small = image.reduced(by: f), smallPatch = patch.reduced(by: f)
        var coarse = scores(smallPatch, in: small, xs: 0...(small.width - smallPatch.width),
                            ys: 0...(small.height - smallPatch.height))
        coarse.sort { $0.score > $1.score }
        var picks: [(x: Int, y: Int)] = []
        for c in coarse where c.score >= threshold - 0.25 {
            if picks.contains(where: { abs($0.x - c.x) * f < patch.width / 2 && abs($0.y - c.y) * f < patch.height / 2 }) { continue }
            picks.append((c.x, c.y))
            if picks.count == 8 { break }
        }
        // 2. Au point près autour de chacune, sur l'image entière.
        var best: [Hit] = []
        for p in picks {
            let x0 = p.x * f, y0 = p.y * f
            let xs = max(0, x0 - f - 1)...min(image.width - patch.width, x0 + f + 1)
            let ys = max(0, y0 - f - 1)...min(image.height - patch.height, y0 + f + 1)
            guard xs.lowerBound <= xs.upperBound, ys.lowerBound <= ys.upperBound,
                  let top = scores(patch, in: image, xs: xs, ys: ys).max(by: { $0.score < $1.score }) else { continue }
            best.append(Hit(x: top.x + patch.width / 2, y: top.y + patch.height / 2, score: top.score))
        }
        guard let top = best.map(\.score).max(), top >= threshold else { return nil }
        func distance(_ h: Hit) -> Int { (h.x - hint.x) * (h.x - hint.x) + (h.y - hint.y) * (h.y - hint.y) }
        return best.filter { $0.score >= top - 0.03 }.min { distance($0) < distance($1) }
    }

    /// Corrélation normalisée du motif à chaque place (coin haut gauche) de `xs` × `ys`.
    private static func scores(_ patch: GrayImage, in image: GrayImage, xs: ClosedRange<Int>,
                               ys: ClosedRange<Int>) -> [(x: Int, y: Int, score: Double)] {
        let pw = patch.width, ph = patch.height, n = Double(pw * ph)
        var pMean = 0.0
        for v in patch.pixels { pMean += Double(v) }
        pMean /= n
        var centered = [Double](repeating: 0, count: pw * ph)
        var pNorm = 0.0
        for i in 0..<(pw * ph) {
            let d = Double(patch.pixels[i]) - pMean
            centered[i] = d
            pNorm += d * d
        }
        guard pNorm > 0 else { return [] }
        var out: [(x: Int, y: Int, score: Double)] = []
        out.reserveCapacity(xs.count * ys.count)
        let iw = image.width
        image.pixels.withUnsafeBufferPointer { px in
            centered.withUnsafeBufferPointer { cp in
                for y in ys {
                    for x in xs {
                        var sum = 0.0, sumSq = 0.0, cross = 0.0
                        for py in 0..<ph {
                            let row = (y + py) * iw + x
                            let prow = py * pw
                            for pxi in 0..<pw {
                                let v = Double(px[row + pxi])
                                sum += v
                                sumSq += v * v
                                cross += v * cp[prow + pxi]
                            }
                        }
                        let variance = sumSq - sum * sum / n
                        guard variance > 1 else { continue }
                        out.append((x, y, cross / (variance * pNorm).squareRoot()))
                    }
                }
            }
        }
        return out
    }
}

/// Lecture d'une fenêtre de FL (ScreenCaptureKit, macOS 14 et plus), 1 pixel par point, en niveaux de gris.
enum ScreenLook {
    /// Option possible sur ce Mac.
    static var available: Bool {
        if #available(macOS 14.0, *) { return true }
        return false
    }

    /// Autorisation « Enregistrement de l'écran » déjà donnée (aucune fenêtre affichée).
    static var allowed: Bool { CGPreflightScreenCaptureAccess() }

    /// Demande l'autorisation (fenêtre de macOS la première fois) ; vrai si elle est donnée.
    @discardableResult
    static func requestAccess() -> Bool { CGRequestScreenCaptureAccess() }

    static func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Fenêtre `number` (liste des fenêtres de macOS) de taille `size` en points. À appeler hors du fil principal
    /// (attente bornée à 2 s).
    static func capture(windowNumber number: Int, size: CGSize) -> GrayImage? {
        guard number > 0, allowed else { return nil }
        if #available(macOS 14.0, *) {
            let box = CaptureBox()
            let done = DispatchSemaphore(value: 0)
            Task.detached {
                box.image = await captureWindow(number: number, size: size)
                done.signal()
            }
            guard done.wait(timeout: .now() + 2) == .success, let cg = box.image else { return nil }
            return gray(cg)
        }
        return nil
    }

    /// Même lecture, résultat sur le fil principal (« Montrer dans FL… »).
    static func capture(windowNumber number: Int, size: CGSize, completion: @escaping (GrayImage?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let image = capture(windowNumber: number, size: size)
            DispatchQueue.main.async { completion(image) }
        }
    }

    private final class CaptureBox: @unchecked Sendable {
        var image: CGImage?
    }

    @available(macOS 14.0, *)
    private static func captureWindow(number: Int, size: CGSize) async -> CGImage? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true),
              let window = content.windows.first(where: { Int($0.windowID) == number }) else { return nil }
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration()
        config.width = max(1, Int(size.width.rounded()))
        config.height = max(1, Int(size.height.rounded()))
        config.showsCursor = false
        return try? await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
    }

    private static func gray(_ image: CGImage) -> GrayImage? {
        let w = image.width, h = image.height
        guard w > 0, h > 0 else { return nil }
        var pixels = [UInt8](repeating: 0, count: w * h)
        let drawn: Bool = pixels.withUnsafeMutableBytes { raw in
            guard let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)
            else { return false }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return drawn ? GrayImage(width: w, height: h, pixels: pixels) : nil
    }
}
