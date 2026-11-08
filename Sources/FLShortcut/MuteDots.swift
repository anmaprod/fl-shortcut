// Mute et solo d'une piste sans le lien avec FL (08/11, « pour le mute solo d'une piste sans le lien, il n'y a pas
// besoin de montrer… ce sera la piste sélectionnée ») : le petit rond de couleur de la piste (rose chez le propriétaire,
// d'une autre couleur chez d'autres) est retrouvé tout seul dans l'image de la fenêtre de FL, au moment du clic :
// - Mixer : juste sous le nom de chaque piste (« Insert 2 ») → les ronds forment une RANGÉE à pas réguliers ;
// - Channel rack : à gauche des deux boutons et de la case du numéro de chaque son → une COLONNE, la piste cliquée à
//   droite des ronds, chaque rond au milieu de sa ligne ;
// - Playlist : en bas à droite de l'en-tête de chaque piste (« Track 1 ») → une COLONNE, la piste cliquée à gauche des
//   ronds, chaque rond en bas de son en-tête.
// La piste visée est la dernière cliquée dans FL (celle que FL vient de sélectionner). Rond éteint (piste coupée) :
// sa place est déduite de ses voisins, et vérifiée (un disque, pas autre chose). Pur et testé : aucune image gardée,
// rien au journal que des nombres.
import Foundation

/// Image en couleurs, 4 octets par pixel (rouge, vert, bleu, alpha), repère en haut à gauche.
struct RGBAImage {
    let width: Int
    let height: Int
    let pixels: [UInt8]

    func rgb(_ x: Int, _ y: Int) -> (r: Int, g: Int, b: Int) {
        let i = (y * width + x) * 4
        return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]))
    }

    func luminance(_ x: Int, _ y: Int) -> Double {
        let c = rgb(x, y)
        return 0.299 * Double(c.r) + 0.587 * Double(c.g) + 0.114 * Double(c.b)
    }

    /// Pixel d'une couleur franche et claire (un voyant allumé), pas un gris ni un noir.
    func lit(_ x: Int, _ y: Int) -> Bool {
        let c = rgb(x, y)
        let hi = max(c.r, c.g, c.b), lo = min(c.r, c.g, c.b)
        return hi - lo >= MuteDots.minSaturation && hi >= MuteDots.minBrightness
    }
}

enum MuteDots {
    static let minSaturation = 50
    static let minBrightness = 110
    /// Diamètre d'un rond (pixels de l'image : la fenêtre lue deux fois plus fine que l'écran).
    static let diameters = 5...32

    struct Blob: Equatable {
        var x: Double
        var y: Double
        var diameter: Double
    }

    /// Ronds alignés à pas réguliers : une rangée (Mixer) ou une colonne (Channel rack, Playlist).
    struct Series: Equatable {
        var horizontal: Bool
        /// Ronds dans l'ordre (gauche → droite ou haut → bas).
        var members: [Blob]
        var step: Double
        /// y de la rangée, ou x de la colonne.
        var line: Double
        var diameter: Double

        func along(_ b: Blob) -> Double { horizontal ? b.x : b.y }
    }

    enum Page: String { case mixer, channelRack, playlist }

    struct Target: Equatable {
        var x: Double
        var y: Double
        /// Rond éteint (piste coupée) : sa place vient de ses voisins.
        var inferred: Bool
        var page: Page
    }

    // MARK: Ronds

    /// Taches d'une couleur franche, petites, rondes et pleines.
    static func blobs(in image: RGBAImage) -> [Blob] {
        let w = image.width, h = image.height
        guard w > 0, h > 0, image.pixels.count >= w * h * 4 else { return [] }
        var seen = [Bool](repeating: false, count: w * h)
        var out: [Blob] = []
        var stack: [Int] = []
        for start in 0..<(w * h) where !seen[start] {
            seen[start] = true
            guard image.lit(start % w, start / w) else { continue }
            var minX = start % w, maxX = minX, minY = start / w, maxY = minY, count = 0
            var sumX = 0, sumY = 0
            var members: [Int] = []
            stack.append(start)
            while let p = stack.popLast() {
                let px = p % w, py = p / w
                count += 1
                if count <= 1200 { members.append(p) }
                sumX += px
                sumY += py
                minX = min(minX, px); maxX = max(maxX, px); minY = min(minY, py); maxY = max(maxY, py)
                if count > 4000 { continue }                       // grande surface : jamais un rond (on la vide)
                for (dx, dy) in [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (1, -1), (-1, 1), (1, 1)] {
                    let nx = px + dx, ny = py + dy
                    guard nx >= 0, ny >= 0, nx < w, ny < h else { continue }
                    let n = ny * w + nx
                    if seen[n] { continue }
                    seen[n] = true
                    if image.lit(nx, ny) { stack.append(n) }
                }
            }
            let bw = maxX - minX + 1, bh = maxY - minY + 1
            guard diameters.contains(bw), diameters.contains(bh) else { continue }
            let aspect = Double(bw) / Double(bh)
            let fill = Double(count) / Double(bw * bh)
            guard (0.7...1.45).contains(aspect), (0.6...0.9).contains(fill) else { continue }
            // Un disque laisse ses coins vides (pas des pas du Channel rack, rectangles aux coins arrondis) : presque rien
            // hors de l'ellipse inscrite dans son cadre.
            let cx = Double(minX + maxX) / 2, cy = Double(minY + maxY) / 2
            let a = max(1, Double(bw) / 2), b = max(1, Double(bh) / 2)
            let outside = members.filter { p in
                let u = (Double(p % w) - cx) / a, v = (Double(p / w) - cy) / b
                return u * u + v * v > 1.35
            }.count
            guard Double(outside) <= 0.06 * Double(members.count) else { continue }
            out.append(Blob(x: Double(sumX) / Double(count), y: Double(sumY) / Double(count),
                            diameter: Double(bw + bh) / 2))
        }
        return out
    }

    // MARK: Rangées et colonnes

    /// Ronds de même taille, alignés, à pas réguliers (un trou d'un ou plusieurs pas : des ronds éteints). Au moins deux.
    static func series(_ blobs: [Blob]) -> [Series] {
        var out: [Series] = []
        for horizontal in [true, false] {
            let across: (Blob) -> Double = { horizontal ? $0.y : $0.x }
            let along: (Blob) -> Double = { horizontal ? $0.x : $0.y }
            var groups: [[Blob]] = []
            for b in blobs.sorted(by: { across($0) < across($1) }) {
                let tolerance = max(2, 0.35 * b.diameter)
                if let i = groups.lastIndex(where: { g in
                    abs(across(g[0]) - across(b)) <= tolerance && abs(g[0].diameter - b.diameter) <= 0.4 * g[0].diameter
                }) {
                    groups[i].append(b)
                } else {
                    groups.append([b])
                }
            }
            for group in groups where group.count >= 2 {
                let sorted = group.sorted { along($0) < along($1) }
                let d = sorted.map(\.diameter).sorted()[sorted.count / 2]
                let gaps = zip(sorted, sorted.dropFirst()).map { along($1) - along($0) }
                // Pas plausible : plus de 1,5 rond et au plus 20 (une piste de la Playlist très haute).
                guard let smallest = gaps.filter({ $0 >= 1.5 * d && $0 <= 20 * d }).min() else { continue }
                let near = gaps.filter { abs($0 / smallest - 1) <= 0.2 }
                let step = near.sorted()[near.count / 2]
                // Coupé là où l'écart n'est pas un nombre entier de pas (autre chose sur la même ligne).
                var chain: [Blob] = [sorted[0]]
                func flush() {
                    guard chain.count >= 2 else { return }
                    let line = chain.map(across).sorted()[chain.count / 2]
                    out.append(Series(horizontal: horizontal, members: chain, step: step, line: line, diameter: d))
                }
                for (b, gap) in zip(sorted.dropFirst(), gaps) {
                    let k = gap / step
                    if k >= 0.8, abs(k - k.rounded()) <= 0.2, k.rounded() <= 12 {
                        chain.append(b)
                    } else {
                        flush()
                        chain = [b]
                    }
                }
                flush()
            }
        }
        return out
    }

    // MARK: La piste cliquée

    /// Le rond de la piste cliquée en `click` (pixels de l'image), ou nil : aucune rangée ni colonne de ronds autour.
    static func target(in image: RGBAImage, click: (x: Double, y: Double)) -> Target? {
        let all = usable(series(blobs(in: image)))
        var best: (score: Double, count: Int, target: Target)?
        for s in all {
            guard let candidate = candidate(s, click: click, image: image) else { continue }
            if best == nil || candidate.score < best!.score - 0.05
                || (abs(candidate.score - best!.score) <= 0.05 && s.members.count > best!.count) {
                best = (candidate.score, s.members.count, candidate.target)
            }
        }
        return best?.target
    }

    /// Les séries qui peuvent être des pistes : au moins trois ronds (deux seulement s'il n'y a rien d'autre), et jamais
    /// la colonne des voyants des effets à droite du Mixer (« Mixer - Insert 2 », Slot 1 à 10 : ses ronds sont aussi
    /// de la couleur des pistes, mais un clic dessus allumerait ou éteindrait un effet).
    static func usable(_ all: [Series]) -> [Series] {
        let three = all.filter { $0.members.count >= 3 }
        let pool = three.isEmpty ? all : three
        let mixers = pool.filter { $0.horizontal && $0.members.count >= 3 }
        return pool.filter { s in
            guard !s.horizontal else { return true }
            let top = s.along(s.members[0]), bottom = s.along(s.members[s.members.count - 1])
            return !mixers.contains { m in
                let right = m.along(m.members[m.members.count - 1]) + m.step
                return s.line > right && bottom >= m.line - 2 * m.step && top <= m.line + 14 * m.step
            }
        }
    }

    /// Distance (pixels de l'image, fenêtre lue deux fois plus fine que l'écran) entre le nom d'une piste et son rond.
    static let channelReach: Double = 700
    static let playlistReach: Double = 640

    /// Le rond de cette rangée ou colonne pour ce clic, et son éloignement (en pas) : nil si le clic n'est pas de ce côté.
    static func candidate(_ s: Series, click: (x: Double, y: Double), image: RGBAImage)
        -> (score: Double, target: Target)? {
        let first = s.along(s.members[0]), last = s.along(s.members[s.members.count - 1])
        let page: Page
        let along: Double
        let score: Double
        if s.horizontal {
            // Mixer : le clic tombe dans la bande d'une piste, du nom (vertical, haut de cinq pas au-dessus du rond)
            // jusqu'au fader et plus bas.
            guard click.x >= first - s.step, click.x <= last + s.step,
                  click.y >= s.line - 6 * s.step, click.y <= s.line + 14 * s.step else { return nil }
            page = .mixer
            along = click.x
            score = abs(click.y - s.line) / s.step
        } else if click.x >= s.line {
            // Channel rack : le nom du son est à droite des ronds, le rond au milieu de sa ligne.
            guard click.x <= s.line + channelReach, click.y >= first - s.step, click.y <= last + s.step else { return nil }
            page = .channelRack
            along = click.y
            score = (click.x - s.line) / s.step
        } else {
            // Playlist : le rond est en bas à droite de l'en-tête de sa piste : celui du clic est le premier rond qui
            // n'est pas au-dessus du clic (à un tiers de pas près).
            guard click.x >= s.line - playlistReach, click.y >= first - 0.75 * s.step, click.y <= last + 0.25 * s.step
            else { return nil }
            page = .playlist
            along = click.y + 0.25 * s.step                         // l'en-tête : de 0,75 pas au-dessus à 0,25 dessous
            score = (s.line - click.x) / s.step
        }
        guard let spot = spot(s, at: along, image: image) else { return nil }
        let point = s.horizontal ? (x: spot.along, y: s.line) : (x: s.line, y: spot.along)
        return (score, Target(x: point.x, y: point.y, inferred: spot.inferred, page: page))
    }

    /// Le rond le plus proche de `value` le long de la série : un rond allumé à moins d'un demi-pas, sinon la place
    /// d'un rond éteint entre deux voisins (ou un pas au-delà du dernier), vérifiée dans l'image.
    static func spot(_ s: Series, at value: Double, image: RGBAImage) -> (along: Double, inferred: Bool)? {
        let positions = s.members.map(s.along)
        if let nearest = positions.min(by: { abs($0 - value) < abs($1 - value) }), abs(nearest - value) <= 0.5 * s.step {
            return (nearest, false)
        }
        // Entre deux ronds allumés : leur écart partagé en pas égaux.
        let guess: Double
        if let right = positions.firstIndex(where: { $0 > value }), right > 0 {
            let a = positions[right - 1], b = positions[right]
            let n = max(1, ((b - a) / s.step).rounded())
            let pitch = (b - a) / n
            guess = a + ((value - a) / pitch).rounded() * pitch
        } else if let lastPos = positions.last, value > lastPos {
            guess = lastPos + max(1, ((value - lastPos) / s.step).rounded()) * s.step
        } else if let firstPos = positions.first {
            guess = firstPos - max(1, ((firstPos - value) / s.step).rounded()) * s.step
        } else {
            return nil
        }
        guard abs(guess - value) <= 0.5 * s.step + 1 else { return nil }
        let point = s.horizontal ? (x: guess, y: s.line) : (x: s.line, y: guess)
        return looksLikeDisk(image, x: point.x, y: point.y, diameter: s.diameter) ? (guess, true) : nil
    }

    /// Un rond éteint à cette place : un disque uni, net sur ce qui l'entoure, sans couleur franche (rien de posé
    /// dessus, pas une autre fenêtre).
    static func looksLikeDisk(_ image: RGBAImage, x: Double, y: Double, diameter d: Double) -> Bool {
        let r = d / 2
        let cx = Int(x.rounded()), cy = Int(y.rounded()), reach = Int((r * 1.9).rounded(.up))
        guard cx - reach >= 0, cy - reach >= 0, cx + reach < image.width, cy + reach < image.height else { return false }
        var inner: [Double] = [], ring: [Double] = []
        for dy in -reach...reach {
            for dx in -reach...reach {
                let dist = (Double(dx * dx + dy * dy)).squareRoot()
                if image.lit(cx + dx, cy + dy) { return false }
                let l = image.luminance(cx + dx, cy + dy)
                if dist <= 0.55 * r { inner.append(l) } else if dist >= 1.35 * r, dist <= 1.85 * r { ring.append(l) }
            }
        }
        guard !inner.isEmpty, !ring.isEmpty else { return false }
        let mi = inner.reduce(0, +) / Double(inner.count), mr = ring.reduce(0, +) / Double(ring.count)
        let spread = (inner.map { ($0 - mi) * ($0 - mi) }.reduce(0, +) / Double(inner.count)).squareRoot()
        return abs(mi - mr) >= 8 && spread <= 18
    }
}
