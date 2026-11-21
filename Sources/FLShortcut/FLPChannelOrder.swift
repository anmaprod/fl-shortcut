import Foundation

/// 13/11 (capture du propriétaire : « tout est génial sauf dans channel rack ça n'a pas tout rangé » ; diagnostics
/// d'avant : `remise rack touche sans effet 5`, `remise rack fenêtre playlist 5`) : le Channel rack est rangé dans la
/// copie, comme la Playlist et les icônes, au lieu de remonter chaque son par ⌥↑ dans FL (FL donnait la main à la
/// Playlist en route). FL écrit ses canaux dans l'ordre du Channel rack, chacun numéroté par sa place (64 = 0, 1, 2…),
/// et les notes (224) et les clips audio de la Playlist (233) les désignent par ce numéro : vérifié sur deux projets du
/// propriétaire (12/11), où deux canaux ajoutés avaient décalé les suivants avec leurs notes. Ranger = mettre chaque
/// canal à sa nouvelle place, le renuméroter, et suivre ses notes et ses clips. Tout ce qui pourrait désigner un canal
/// autrement (layer, clip d'automation, liens de contrôleurs, automations de pattern) : rien n'est touché, le Channel
/// rack est rangé dans FL comme avant.
extension FLPProject {
    /// Ce qui suit un canal dans le fichier sans être à lui : le canal suivant, les patterns (FL écrit leurs noms et
    /// couleurs après le premier canal), l'arrangement, le Mixer.
    private static func endsChannel(_ events: [FLPEvent], _ i: Int) -> Bool {
        let id = events[i].id
        if id == Event.channel, i + 1 < events.count, events[i + 1].id == Event.channelType { return true }
        return id == Event.pattern || id == Event.arrangement || id == insertStart
    }

    /// Événements qui peuvent désigner un canal ailleurs que dans les notes et les clips : automations de pattern (223),
    /// liens de contrôleurs (227), données d'automation (234).
    static let channelReferences: Set<UInt8> = [223, 227, 234]
    /// Types de canaux qui en désignent d'autres : layer (ses canaux), clip d'automation (sa cible).
    static let referencingTypes: Set<Int> = [ChannelInfo.layerType, ChannelInfo.automationType]

    /// Pur (testé) : le fichier avec les canaux dans l'ordre `order` (place → numéro d'avant, chaque canal une fois),
    /// renumérotés, leurs notes et leurs clips suivis ; ce qui n'est pas à un canal (noms des patterns…) reste à sa
    /// place. nil si le fichier n'a pas la forme connue ou si un canal pourrait être désigné autrement.
    static func reorderingChannels(_ file: FLPFile, order: [Int]) -> FLPFile? {
        let events = file.events
        var starts: [Int] = []
        for i in events.indices where events[i].id == Event.channel && i + 1 < events.count
            && events[i + 1].id == Event.channelType {
            starts.append(i)
        }
        let n = starts.count
        guard n >= 2, order.count == n, Set(order) == Set(0..<n) else { return nil }
        // La forme de FL : numérotés 0, 1, 2… dans l'ordre ; aucun type qui désigne un autre canal.
        for (k, start) in starts.enumerated() {
            guard events[start].bytes.count == 2, Int(events[start].value) == k,
                  !referencingTypes.contains(Int(events[start + 1].value)) else { return nil }
        }
        guard !events.contains(where: { channelReferences.contains($0.id) }) else { return nil }
        // Chaque canal : de son 64 jusqu'à ce qui n'est plus à lui ; tous finissent par le même événement (FL : 51),
        // sinon quelque chose d'autre y est collé.
        var ranges: [Range<Int>] = []
        for (k, start) in starts.enumerated() {
            var end = start + 2
            let limit = k + 1 < n ? starts[k + 1] : events.count
            while end < limit && !endsChannel(events, end) { end += 1 }
            ranges.append(start..<end)
        }
        let lastIDs = Set(ranges.map { events[$0.upperBound - 1].id })
        guard lastIDs.count == 1, !ranges.contains(where: { range in
            events[range].contains { $0.id == Event.children }
        }) else { return nil }
        var newPlace = [Int](repeating: 0, count: n)
        for (place, old) in order.enumerated() { newPlace[old] = place }

        // Notes : 24 octets chacune, le canal sur 2 octets à la place 6.
        var out = file
        for i in events.indices where events[i].id == Event.notes {
            var bytes = events[i].bytes
            guard bytes.count % noteSize == 0 else { return nil }
            for at in stride(from: 0, to: bytes.count, by: noteSize) {
                let channel = Int(FLPBytes.uint(bytes, at: at + 6, size: 2))
                guard channel < n else { return nil }
                FLPBytes.put(UInt32(newPlace[channel]), into: &bytes, at: at + 6, size: 2)
            }
            out.events[i].bytes = bytes
        }
        // Clips de la Playlist (chaque arrangement) : en dessous de la marque des patterns, un canal.
        for i in events.indices where events[i].id == Event.playlist {
            var bytes = events[i].bytes
            guard !bytes.isEmpty else { continue }
            guard let size = itemSize(bytes) else { return nil }
            for at in stride(from: 0, to: bytes.count, by: size) {
                let index = Int(FLPBytes.uint(bytes, at: at + 6, size: 2))
                guard index <= patternBase else { continue }
                guard index < n else { return nil }
                FLPBytes.put(UInt32(newPlace[index]), into: &bytes, at: at + 6, size: 2)
            }
            out.events[i].bytes = bytes
        }
        // Les canaux à leur nouvelle place ; ce qui suivait chaque place (noms des patterns après le premier) y reste.
        var rebuilt = Array(out.events[..<starts[0]])
        for place in 0..<n {
            var section = Array(out.events[ranges[order[place]]])
            section[0].bytes = FLPBytes.le(place, size: 2)
            rebuilt += section
            let gapEnd = place + 1 < n ? starts[place + 1] : out.events.count
            rebuilt += out.events[ranges[place].upperBound..<gapEnd]
        }
        guard rebuilt.count == events.count else { return nil }
        out.events = rebuilt
        return out
    }
}
