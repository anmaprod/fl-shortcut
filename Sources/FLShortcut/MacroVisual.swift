// Boutons de FL retrouvés même s'ils bougent (le « + » du Channel rack descend à chaque piste ajoutée, une piste du
// Mixer change de place…). FL les dessine lui-même, sans nom pour l'Accessibilité : il faut lire sa fenêtre.
// - Par son nom (« FILE », « Insert 1 », « Master »…) : le texte sous le clic est lu à l'enregistrement (Vision, sur
//   le Mac), puis cherché dans la fenêtre au moment du clic ; c'est la règle pour tout bouton qui porte un nom.
// - Par son image (bouton sans texte, comme le « + ») : sur demande pour ce clic (« Retrouver ce bouton s'il bouge »),
//   une petite image du bouton (niveaux de gris, 1 pixel par point) est cherchée dans la fenêtre.
// - Lecture de l'écran : seulement la fenêtre de FL visée, seulement au moment d'un clic (jamais au repos, jamais
//   d'enregistrement vidéo), avec l'autorisation « Enregistrement de l'écran » ; sans elle, les clics gardent leur
//   place, comme avant. Ni le nom ni l'image ne sont journalisés.
//   L'image reste dans la macro (et dans la sauvegarde en ligne du compte, lisible par son seul propriétaire) ; elle
//   est retirée à l'export et des partages.
// - Recherche : corrélation normalisée (insensible à la luminosité), d'abord sur une image réduite au tiers, puis au
//   point près autour des meilleures places ; à score presque égal, la plus proche de l'endroit montré.
import AppKit
import CoreGraphics
import ScreenCaptureKit
import Vision

/// Bouton retrouvé à son nom : le texte lu sous le clic, où tombait le clic par rapport au centre de ce texte, et où
/// il était quand on l'a montré (fenêtre où le chercher ; repli sans lecture de l'écran).
struct NamedSpot: Equatable {
    let label: String
    let dx: Double
    let dy: Double
    let corner: Corner
    let px: Double
    let py: Double
    let size: CGSize
    var title: String? = nil

    /// La même place, sans le nom.
    var place: ClickTarget { .flWindow(corner: corner, dx: px, dy: py, size: size, title: title) }

    var isValid: Bool {
        func ok(_ v: Double) -> Bool { v.isFinite && abs(v) <= 5000 }
        return TextLook.isUsable(label) && ok(dx) && ok(dy) && abs(dx) <= 200 && abs(dy) <= 200 && ok(px) && ok(py)
            && size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
            && size.width <= 10_000 && size.height <= 10_000
            && (title.map { !$0.isEmpty && $0.count <= ClickTarget.maxTitle } ?? true)
    }
}

/// Textes d'une fenêtre de FL, lus sur le Mac (Vision), pour retrouver un bouton à son nom.
enum TextLook {
    struct Item: Equatable {
        let text: String
        /// Cadre dans la fenêtre, en points, origine en haut à gauche.
        let box: CGRect
        var center: CGPoint { CGPoint(x: box.midX, y: box.midY) }
    }

    /// Nom qu'on peut retenir : 2 à 40 caractères, au moins une lettre (pas « 1 », pas une phrase), et pas un
    /// affichage de valeur qui change avec le clic (« Device : X », « Mixer - Insert 3 », « ● REC »).
    static func isUsable(_ text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (2...40).contains(t.count) && t.contains(where: \.isLetter)
            && !t.contains(where: { ":•●○◉".contains($0) }) && !t.contains(" - ") && !t.contains(" – ")
    }

    /// Largeur maximale d'un nom de bouton (au-delà : une ligne de texte, pas un bouton).
    static let maxWidth: CGFloat = 160

    /// Forme de comparaison : sans casse ni accents, espaces simples, et les confusions de lecture courantes
    /// (0/O, 1/l/I/|) ramenées à une seule lettre.
    static func normalized(_ s: String) -> String {
        let folded = s.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return String(folded.map { c -> Character in
            switch c {
            case "0": return "o"
            case "1", "i", "|", "!": return "l"
            default: return c
            }
        })
    }

    /// Pure (testée) : nom retenu pour un clic en `p`, parmi les textes lus dans `region`. Le texte sous le clic (puis
    /// à 6 points près), étroit : le nom court entier (« Insert 1 »), ou le mot cliqué dans une ligne (« FILE » dans
    /// « FILE EDIT ADD… »). Jamais une ligne large, ni un texte qui touche le bord de la zone lue (il y est coupé).
    static func label(at p: CGPoint, in items: [Item], region: CGRect? = nil) -> Item? {
        let usable = items.filter { item in
            isUsable(item.text) && item.box.width <= maxWidth
                && !(region.map { item.box.minX <= $0.minX + 2 || item.box.maxX >= $0.maxX - 2
                        || item.box.minY <= $0.minY + 1 || item.box.maxY >= $0.maxY - 1 } ?? false)
        }
        for pad: CGFloat in [0, 6] {
            let near = usable.filter { $0.box.insetBy(dx: -pad, dy: -pad).contains(p) }
            if let best = near.max(by: { $0.box.width < $1.box.width }) { return best }
        }
        return nil
    }

    /// Pure (testée) : le nom parmi les textes lus (même texte, à la forme de comparaison près), le plus proche de
    /// `hint` s'il y est plusieurs fois.
    static func find(_ label: String, in items: [Item], near hint: CGPoint) -> Item? {
        let wanted = normalized(label)
        func distance(_ i: Item) -> CGFloat {
            (i.center.x - hint.x) * (i.center.x - hint.x) + (i.center.y - hint.y) * (i.center.y - hint.y)
        }
        return items.filter { normalized($0.text) == wanted }.min { distance($0) < distance($1) }
    }

    /// Textes de `image` (une fenêtre de `size` points), lignes et mots ; `region` (points) : seulement là.
    static func read(_ image: CGImage, size: CGSize, region: CGRect? = nil) -> [Item] {
        guard size.width > 0, size.height > 0 else { return [] }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US", "fr-FR"]
        var roi = CGRect(x: 0, y: 0, width: 1, height: 1)
        if let r = region?.intersection(CGRect(origin: .zero, size: size)), !r.isNull, r.width > 4, r.height > 4 {
            roi = CGRect(x: r.minX / size.width, y: 1 - r.maxY / size.height,
                         width: r.width / size.width, height: r.height / size.height)
            request.regionOfInterest = roi
        }
        // Textes de FL petits (environ 10 points) : 6 points de haut au moins, en fraction de la hauteur lue.
        request.minimumTextHeight = Float(min(1, 6 / max(1, roi.height * size.height)))
        guard (try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])) != nil else { return [] }
        // Cadres de Vision : normalisés dans la région lue, origine en bas à gauche → points de la fenêtre.
        func inWindow(_ b: CGRect) -> CGRect {
            let x = (roi.minX + b.minX * roi.width) * size.width
            let bottom = roi.minY + b.minY * roi.height
            let h = b.height * roi.height
            return CGRect(x: x, y: (1 - bottom - h) * size.height, width: b.width * roi.width * size.width,
                          height: h * size.height)
        }
        var out: [Item] = []
        for observation in request.results ?? [] {
            guard let top = observation.topCandidates(1).first else { continue }
            let text = top.string.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { continue }
            out.append(Item(text: text, box: inWindow(observation.boundingBox)))
            let words = wordRanges(top.string)
            guard words.count > 1 else { continue }
            for range in words {
                if let word = try? top.boundingBox(for: range) {
                    out.append(Item(text: String(top.string[range]), box: inWindow(word.boundingBox)))
                }
            }
        }
        return out
    }

    private static func wordRanges(_ s: String) -> [Range<String.Index>] {
        var out: [Range<String.Index>] = []
        var start: String.Index?
        for i in s.indices {
            if s[i].isWhitespace {
                if let b = start { out.append(b..<i); start = nil }
            } else if start == nil {
                start = i
            }
        }
        if let b = start { out.append(b..<s.endIndex) }
        return out
    }

    /// Nom du bouton sous `p` (coordonnées de l'écran) dans `window`, et où tombe le clic par rapport à son centre.
    /// Lecture hors du fil principal, résultat sur le fil principal. nil : pas de texte utilisable sous le clic, ou
    /// lecture de l'écran impossible.
    private static let queue = DispatchQueue(label: "FLShortcut.text-look", qos: .userInitiated)

    static func lookup(at p: CGPoint, window: WinInfo,
                       completion: @escaping ((label: String, dx: Double, dy: Double)?) -> Void) {
        queue.async {
            var found: (label: String, dx: Double, dy: Double)?
            let f = window.bounds
            if let image = ScreenLook.captureImage(windowNumber: window.number, size: f.size, scale: 2) {
                let local = CGPoint(x: p.x - f.minX, y: p.y - f.minY)
                let region = CGRect(x: local.x - 180, y: local.y - 50, width: 360, height: 100)
                    .intersection(CGRect(origin: .zero, size: f.size))
                if let item = label(at: local, in: read(image, size: f.size, region: region), region: region) {
                    found = (label: item.text, dx: Double(local.x - item.center.x), dy: Double(local.y - item.center.y))
                }
            }
            DispatchQueue.main.async { completion(found) }
        }
    }
}

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

    /// Fenêtre `number` (liste des fenêtres de macOS) de taille `size` en points, en niveaux de gris, 1 pixel par
    /// point. À appeler hors du fil principal (attente bornée à 2 s).
    static func capture(windowNumber number: Int, size: CGSize) -> GrayImage? {
        captureImage(windowNumber: number, size: size, scale: 1).flatMap(gray)
    }

    /// Même fenêtre en couleur, `scale` pixels par point (2 : textes nets pour la lecture). Hors du fil principal.
    static func captureImage(windowNumber number: Int, size: CGSize, scale: CGFloat) -> CGImage? {
        guard number > 0, allowed, size.width >= 1, size.height >= 1 else { return nil }
        if #available(macOS 14.0, *) {
            let box = CaptureBox()
            let done = DispatchSemaphore(value: 0)
            let pixels = CGSize(width: size.width * scale, height: size.height * scale)
            Task.detached {
                box.image = await captureWindow(number: number, size: pixels)
                done.signal()
            }
            guard done.wait(timeout: .now() + 2) == .success else { return nil }
            return box.image
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
