// Organiser : où faire le clic droit qui pose une icône (MacroIconPlacement.swift) — sur le nom de l'élément, retrouvé
// dans la fenêtre de FL au moment du clic, comme un bouton retrouvé à son nom (lecture de la seule fenêtre de FL,
// autorisation « Enregistrement de l'écran »). Channel rack : noms en colonne, de haut en bas. Mixer : noms écrits à la
// verticale (vidéo du propriétaire du 31/10), lus dans l'image tournée d'un quart de tour, de gauche à droite. Seuls
// les noms lus servent, et les places entre deux noms lus : jamais un clic droit deviné au-delà (un clic droit ailleurs
// dans FL peut changer le projet : pas du Channel rack, clips de la Playlist). Aucun nom n'est journalisé.
import AppKit

/// Élément qui reçoit une icône : sa page, sa place dans FL et les noms de cette page dans l'ordre de FL.
struct IconTarget: Equatable {
    let kind: ItemKind
    let place: Int
    let names: [String]

    /// Noms du Mixer tels que FL les montre, rangés par piste (0 = Master) : « Insert 3 » pour une piste sans nom.
    static func mixerNames(_ tracks: [MixerTrackInfo]) -> [String] {
        guard let last = tracks.map(\.index).max(), last >= 0 else { return [] }
        var out = (0...last).map { $0 == 0 ? "Master" : "Insert \($0)" }
        for track in tracks where track.index >= 0 {
            let name = track.name.trimmingCharacters(in: .whitespaces)
            if !name.isEmpty { out[track.index] = name }
        }
        return out
    }

    /// Noms du Channel rack rangés par place (0 = premier son).
    static func channelNames(_ channels: [ChannelInfo]) -> [String] {
        guard let last = channels.map(\.index).max(), last >= 0 else { return [] }
        var out = [String](repeating: "", count: last + 1)
        for channel in channels where channel.index >= 0 { out[channel.index] = channel.name }
        return out
    }
}

enum IconTargets {
    enum Found: Equatable {
        case point(CGPoint)
        /// Autorisation « Enregistrement de l'écran » absente.
        case notAllowed
        /// Nom de l'élément introuvable dans les fenêtres de FL.
        case notFound
    }

    /// Pur (testé) : point de chaque nom de `names` (0…) aligné dans les textes lus : de haut en bas (`across` faux,
    /// Channel rack) ou de gauche à droite (`across` vrai, Mixer). La ligne retenue : textes alignés (même début, même
    /// milieu ou même fin, à 8 points près) où le plus de noms attendus se suivent dans l'ordre ; à égalité entre deux
    /// lignes différentes, la plus proche de `near` (titre de la page), sinon aucune (doute). Un nom non lu entre deux
    /// noms lus prend sa place d'après eux ; jamais au-delà. nil si moins de 2 noms sont lus.
    static func line(names: [String], items: [TextLook.Item], across: Bool = false,
                     near: CGPoint? = nil) -> [Int: CGPoint]? {
        func flip(_ p: CGPoint) -> CGPoint { CGPoint(x: p.y, y: p.x) }
        if across {
            let turned = items.map {
                TextLook.Item(text: $0.text, box: CGRect(x: $0.box.minY, y: $0.box.minX,
                                                        width: $0.box.height, height: $0.box.width))
            }
            return line(names: names, items: turned, near: near.map(flip))?.mapValues(flip)
        }
        let wanted = names.map(TextLook.normalized)
        let matching = items.filter { item in
            let text = TextLook.normalized(item.text)
            return !text.isEmpty && wanted.contains(text)
        }
        typealias Candidate = (found: [Int: TextLook.Item], x: CGFloat)
        var candidates: [Candidate] = []
        let keys: [(TextLook.Item) -> CGFloat] = [{ $0.box.minX }, { $0.box.midX }, { $0.box.maxX }]
        for key in keys {
            var columns: [[TextLook.Item]] = []
            for item in matching.sorted(by: { key($0) < key($1) }) {
                if let i = columns.firstIndex(where: { abs(key($0[0]) - key(item)) <= 8 }) {
                    columns[i].append(item)
                } else {
                    columns.append([item])
                }
            }
            for column in columns {
                var found: [Int: TextLook.Item] = [:]
                var last = -1
                for item in column.sorted(by: { $0.box.midY < $1.box.midY }) {
                    let text = TextLook.normalized(item.text)
                    guard let slot = wanted.indices.first(where: { $0 > last && wanted[$0] == text }) else { continue }
                    found[slot] = item
                    last = slot
                }
                guard found.count >= 2 else { continue }
                let xs = found.values.map(\.box.midX).sorted()
                candidates.append((found, xs[xs.count / 2]))
            }
        }
        guard let most = candidates.map(\.found.count).max() else { return nil }
        let best = candidates.filter { $0.found.count == most }
        let chosen: Candidate
        if best.allSatisfy({ abs($0.x - best[0].x) <= 8 }) {
            chosen = best[0]
        } else if let near {
            chosen = best.min { abs($0.x - near.x) < abs($1.x - near.x) }!
        } else {
            return nil
        }
        var out: [Int: CGPoint] = [:]
        for (slot, item) in chosen.found { out[slot] = item.center }
        // Places entre deux noms lus : d'après eux, si les rangées sont assez espacées (8 points au moins).
        let slots = chosen.found.keys.sorted()
        for (a, b) in zip(slots, slots.dropFirst()) where b - a > 1 {
            let top = chosen.found[a]!.center, bottom = chosen.found[b]!.center
            let pitch = (bottom.y - top.y) / CGFloat(b - a)
            guard pitch >= 8 else { continue }
            for slot in (a + 1)..<b {
                out[slot] = CGPoint(x: chosen.x, y: top.y + CGFloat(slot - a) * pitch)
            }
        }
        return out
    }

    /// Pur (testé) : cadre (points, origine en haut à gauche) lu dans l'image d'une fenêtre de `size` tournée d'un
    /// quart de tour (`clockwise` : dans le sens des aiguilles d'une montre), ramené dans la fenêtre.
    static func unturned(_ box: CGRect, clockwise: Bool, size: CGSize) -> CGRect {
        clockwise
            ? CGRect(x: box.minY, y: size.height - box.maxX, width: box.height, height: box.width)
            : CGRect(x: size.width - box.maxY, y: box.minX, width: box.height, height: box.width)
    }

    /// L'image tournée d'un quart de tour (texte vertical du Mixer remis à l'horizontale).
    static func turned(_ image: CGImage, clockwise: Bool) -> CGImage? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        guard let context = CGContext(data: nil, width: image.height, height: image.width, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Repère de CoreGraphics (origine en bas à gauche) : (x, y) → (y, w − x) dans le sens des aiguilles d'une
        // montre, (h − y, x) dans l'autre.
        context.concatenate(clockwise ? CGAffineTransform(a: 0, b: -1, c: 1, d: 0, tx: 0, ty: w)
                                      : CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: h, ty: 0))
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return context.makeImage()
    }

    /// Textes écrits à la verticale dans une fenêtre de `size` points, lus dans les deux sens, cadres dans la fenêtre.
    static func readVertical(_ image: CGImage, size: CGSize) -> [TextLook.Item] {
        let turnedSize = CGSize(width: size.height, height: size.width)
        var out: [TextLook.Item] = []
        for clockwise in [true, false] {
            guard let upright = turned(image, clockwise: clockwise) else { continue }
            out += TextLook.read(upright, size: turnedSize).map {
                TextLook.Item(text: $0.text, box: unturned($0.box, clockwise: clockwise, size: size))
            }
        }
        return out
    }

    /// Dernière lecture (une par page) : gardée une minute, tant que la fenêtre de FL n'a pas bougé et que les noms
    /// sont les mêmes.
    private struct Reading {
        let kind: ItemKind
        let names: [String]
        let window: WinInfo
        let points: [Int: CGPoint]
        let date: Date
    }

    private static let last = Locked<Reading?>(nil)

    /// Point (écran) où faire le clic droit sur l'élément `target`. Hors du fil principal ; la page doit être devant.
    static func locate(_ target: IconTarget, pid: Int32) -> Found {
        guard ScreenLook.allowed else { return .notAllowed }
        let windows = WinSnapshot.take(pid: pid).fl
        if let reading = last.value, reading.kind == target.kind, reading.names == target.names,
           reading.date.timeIntervalSinceNow > -60, windows.contains(reading.window),
           let p = reading.points[target.place] {
            return .point(CGPoint(x: reading.window.bounds.minX + p.x, y: reading.window.bounds.minY + p.y))
        }
        // La plus grande fenêtre d'abord (la page peut être détachée de la fenêtre principale).
        let candidates = windows.filter { $0.layer == 0 && $0.bounds.width >= 200 && $0.bounds.height >= 150 }
            .sorted { $0.bounds.width * $0.bounds.height > $1.bounds.width * $1.bounds.height }
        for window in candidates {
            guard let image = ScreenLook.captureImage(windowNumber: window.number, size: window.bounds.size, scale: 2)
            else { continue }
            let points: [Int: CGPoint]?
            switch target.kind {
            case .mixer:
                // Noms écrits à la verticale ; sinon (tranches larges) à l'horizontale, toujours de gauche à droite.
                points = line(names: target.names, items: readVertical(image, size: window.bounds.size), across: true)
                    ?? line(names: target.names, items: TextLook.read(image, size: window.bounds.size), across: true)
            default:
                let items = TextLook.read(image, size: window.bounds.size)
                let title = items.first { TextLook.normalized($0.text) == TextLook.normalized("Channel rack") }
                points = line(names: target.names, items: items, near: title?.center)
            }
            MacroLog.shared.write("ICON", "names of \(target.kind) in window #\(window.number): "
                                  + "\(points?.count ?? 0)/\(target.names.count) placed")
            guard let points, let p = points[target.place] else { continue }
            last.withLock {
                $0 = Reading(kind: target.kind, names: target.names, window: window, points: points, date: Date())
            }
            return .point(CGPoint(x: window.bounds.minX + p.x, y: window.bounds.minY + p.y))
        }
        return .notFound
    }

    /// Nouvelle lecture au prochain élément (FL a pu bouger, ou une pose a échoué).
    static func forget() { last.withLock { $0 = nil } }
}
