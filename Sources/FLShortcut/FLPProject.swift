// Ce que l'Organiser lit dans un projet de FL (.flp) : les canaux du Channel rack, les sons qui jouent dans chaque
// pattern (leurs notes), chaque clip de la Playlist (pattern ou canal, piste, position, longueur) ; puis la copie
// rangée, où seuls les clips changent de piste. Tout est lu, rien n'est deviné : ce qui ne ressemble pas exactement à
// ce qui est attendu arrête tout (`FLPError.unsupported`). Format : PROTOCOL.md §9. Pur (testé).
import Foundation

struct FLPProject: Equatable {
    struct Channel: Equatable {
        /// Rang dans le Channel rack (0 = premier canal).
        let iid: Int
        /// Type écrit par FL (0 échantillon, 2 plugin, 3 layer…) ; nil s'il n'est pas écrit.
        let type: Int?
        /// Nom montré par FL ; nil s'il n'est pas écrit (FL montre alors celui de l'échantillon ou du plugin).
        let name: String?
        /// Canaux que joue un layer.
        let children: [Int]
    }

    struct Clip: Equatable {
        enum Source: Hashable {
            /// Pattern (1 = pattern 1).
            case pattern(Int)
            /// Canal du Channel rack (clip audio, automation).
            case channel(Int)
        }

        /// Rang du clip dans la Playlist du fichier (pour l'écrire).
        let item: Int
        let source: Source
        /// Début et longueur, en pas (`ppq` par noire).
        let position: Int
        let length: Int
        /// 0 = piste 1.
        let track: Int

        var end: Int { position + max(length, 1) }
    }

    enum Event {
        static let channelType: UInt8 = 21
        static let channel: UInt8 = 64
        static let pattern: UInt8 = 65
        static let children: UInt8 = 94
        static let arrangement: UInt8 = 99
        /// Arrangement ouvert (écrit après les arrangements).
        static let currentArrangement: UInt8 = 100
        /// Groupe affiché par le Channel rack (-1 : « All »), écrit avant les canaux.
        static let channelGroup: UInt8 = 146
        static let patternName: UInt8 = 193
        static let channelName: UInt8 = 203
        static let mixerName: UInt8 = 204
        static let notes: UInt8 = 224
        static let playlist: UInt8 = 233
        static let mixerParams: UInt8 = 236
        static let track: UInt8 = 238
        static let trackName: UInt8 = 239
    }

    /// Une note : 24 octets (position, drapeaux, canal sur 2 octets à la place 6…).
    static let noteSize = 24
    /// Un clip de la Playlist : 88 octets (FL 2024 et plus), 60 (FL 21) ou 32 (avant).
    static let itemSizes = [88, 60, 32]
    /// Écrit dans chaque clip devant son numéro : au-delà, un pattern ; en dessous, un canal.
    static let patternBase = 0x5000

    let ppq: Int
    let channels: [Channel]
    /// Pour chaque pattern qui a des notes (1 = pattern 1) : ses canaux et leur nombre de notes.
    let notes: [Int: [Int: Int]]
    /// Nom de chaque pattern nommé (1 = pattern 1).
    let patternNames: [Int: String]
    /// Clips de la Playlist (celle de l'arrangement qui en a).
    let clips: [Clip]
    /// Pistes de la Playlist (500 dans FL 20 et plus).
    let trackCount: Int
    /// Où écrire : l'événement de la Playlist, la taille d'un clip, l'événement de chaque piste (dans l'ordre).
    let playlistEvent: Int?
    let itemSize: Int
    let trackEvents: [Int]
    /// Événement du groupe affiché par le Channel rack (nil : pas écrit) ; vrai si ce n'est pas « All ».
    let groupEvent: Int?
    let showsGroup: Bool
    /// Pistes coupées (mute) dans FL (0 = piste 1) : un clip qui en part ou y arrive changerait de son.
    let mutedTracks: Set<Int>

    /// Dans une piste (238) : 1 à cette place si elle joue, 0 si elle est coupée.
    static let trackEnabled = 12

    init(_ file: FLPFile) throws {
        var channels: [Channel] = []
        var channel: (iid: Int, type: Int?, name: String?, children: [Int])?
        var notes: [Int: [Int: Int]] = [:]
        var names: [Int: String] = [:]
        var pattern: Int?
        var arrangements: [(index: Int, playlist: Int?, tracks: [Int])] = []
        var current: Int?
        var group: (event: Int, value: UInt32)?
        func closeChannel() {
            if let c = channel { channels.append(Channel(iid: c.iid, type: c.type, name: c.name, children: c.children)) }
            channel = nil
        }
        for (i, event) in file.events.enumerated() {
            switch event.id {
            case Event.channel:
                // Un canal commence par son numéro suivi de son type ; le même numéro d'événement sert ailleurs (réglages
                // MIDI du projet, avant les canaux) : ignoré.
                guard i + 1 < file.events.count, file.events[i + 1].id == Event.channelType else { break }
                closeChannel()
                guard Int(event.value) == channels.count else { throw FLPError.unsupported("canaux") }
                channel = (Int(event.value), Int(file.events[i + 1].value), nil, [])
            case Event.channelName:
                if channel != nil, channel?.name == nil { channel?.name = event.text }
            case Event.children:
                channel?.children.append(Int(event.value))
            case Event.pattern:
                // Les patterns (noms, couleurs) sont écrits au milieu du premier canal : il ne prend plus rien après.
                closeChannel()
                guard event.value >= 1 else { throw FLPError.unsupported("patterns") }
                pattern = Int(event.value)
            case Event.patternName:
                if let pattern { names[pattern] = event.text }
            case Event.notes:
                guard let pattern, event.bytes.count % Self.noteSize == 0 else { throw FLPError.unsupported("notes") }
                for start in stride(from: 0, to: event.bytes.count, by: Self.noteSize) {
                    let on = Int(FLPBytes.uint(event.bytes, at: start + 6, size: 2))
                    notes[pattern, default: [:]][on, default: 0] += 1
                }
            case Event.arrangement:
                closeChannel()
                pattern = nil
                arrangements.append((Int(event.value), nil, []))
            case Event.currentArrangement:
                if !arrangements.isEmpty { current = Int(event.value) }
            case Event.channelGroup:
                if channels.isEmpty, channel == nil, group == nil { group = (i, event.value) }
            case Event.playlist:
                guard !arrangements.isEmpty, arrangements[arrangements.count - 1].playlist == nil
                else { throw FLPError.unsupported("playlist") }
                arrangements[arrangements.count - 1].playlist = i
            case Event.track:
                guard !arrangements.isEmpty else { throw FLPError.unsupported("pistes") }
                arrangements[arrangements.count - 1].tracks.append(i)
            case Event.mixerName, Event.mixerParams:
                // Le Mixer suit les canaux : un nom d'effet n'est jamais pris pour celui d'un canal.
                closeChannel()
            default:
                break
            }
        }
        closeChannel()
        // L'en-tête dit combien de canaux le projet a : la lecture doit les avoir tous trouvés.
        guard file.channelCount == 0 || channels.count == Int(file.channelCount) else {
            throw FLPError.unsupported("canaux")
        }
        self.channels = channels
        self.notes = notes
        self.patternNames = names
        ppq = Int(file.ppq)
        guard ppq > 0 else { throw FLPError.unsupported("ppq") }
        guard notes.values.allSatisfy({ $0.keys.allSatisfy { $0 < channels.count } }) else {
            throw FLPError.unsupported("notes")
        }

        groupEvent = group?.event
        showsGroup = group.map { $0.value != 0xFFFF_FFFF } ?? false
        // L'arrangement rangé : celui qui est ouvert dans FL ; sans le savoir, le seul qui a des clips.
        let filled = arrangements.filter { a in a.playlist.map { !file.events[$0].bytes.isEmpty } ?? false }
        let open = current.flatMap { c in arrangements.first { $0.index == c } }
        guard open != nil || filled.count <= 1 else { throw FLPError.unsupported("arrangements") }
        guard let arrangement = open ?? filled.first, let playlist = arrangement.playlist,
              !file.events[playlist].bytes.isEmpty else {
            playlistEvent = nil
            itemSize = Self.itemSizes[0]
            trackEvents = (open ?? arrangements.first)?.tracks ?? []
            trackCount = trackEvents.count
            mutedTracks = []
            clips = []
            return
        }
        playlistEvent = playlist
        trackEvents = arrangement.tracks
        trackCount = trackEvents.count
        guard trackCount > 0 else { throw FLPError.unsupported("pistes") }
        var muted = Set<Int>()
        for (t, index) in trackEvents.enumerated() {
            let data = file.events[index].bytes
            // Chaque piste dit son numéro (1 = piste 1), sa couleur et si elle joue : dans l'ordre, sans trou.
            guard data.count > Self.trackEnabled, FLPBytes.uint(data, at: 0, size: 4) == t + 1 else {
                throw FLPError.unsupported("pistes")
            }
            if data[Self.trackEnabled] == 0 { muted.insert(t) }
        }
        mutedTracks = muted
        let bytes = file.events[playlist].bytes
        guard let size = Self.itemSize(bytes) else { throw FLPError.unsupported("clips") }
        itemSize = size
        var clips: [Clip] = []
        for (n, start) in stride(from: 0, to: bytes.count, by: size).enumerated() {
            let index = Int(FLPBytes.uint(bytes, at: start + 6, size: 2))
            let reversed = Int(FLPBytes.uint(bytes, at: start + 12, size: 2))
            guard reversed < trackCount else { throw FLPError.unsupported("clips") }
            let source: Clip.Source = index > Self.patternBase ? .pattern(index - Self.patternBase) : .channel(index)
            if case .channel(let c) = source, c >= channels.count { throw FLPError.unsupported("clips") }
            clips.append(Clip(item: n, source: source, position: Int(FLPBytes.uint(bytes, at: start, size: 4)),
                              length: Int(FLPBytes.uint(bytes, at: start + 8, size: 4)),
                              track: trackCount - 1 - reversed))
        }
        self.clips = clips
    }

    /// Taille d'un clip : celle (une seule) pour laquelle chaque clip porte la marque des clips à sa place.
    static func itemSize(_ bytes: [UInt8]) -> Int? {
        let fits = itemSizes.filter { size in
            bytes.count % size == 0 && stride(from: 0, to: bytes.count, by: size).allSatisfy {
                FLPBytes.uint(bytes, at: $0 + 4, size: 2) == patternBase
            }
        }
        return fits.count == 1 ? fits[0] : nil
    }

    /// Sons qui jouent dans ce pattern (1 = pattern 1) : ses canaux qui ont des notes, un layer remplacé par ce qu'il
    /// joue.
    func sounds(of pattern: Int) -> Set<Int> {
        played(Set((notes[pattern] ?? [:]).keys))
    }

    /// Type d'un layer dans le fichier.
    static let layerType = 3

    /// Un layer joue ses canaux (et ceux des layers qu'il contient).
    func played(_ channels: Set<Int>) -> Set<Int> {
        var out = Set<Int>()
        var todo = Array(channels)
        var seen = Set<Int>()
        while let c = todo.popLast() {
            guard seen.insert(c).inserted else { continue }
            let layer = c < self.channels.count && self.channels[c].type == Self.layerType
            let children = layer ? self.channels[c].children : []
            if children.isEmpty { out.insert(c) } else { todo += children }
        }
        return out
    }

    /// Le Channel rack de la copie montre tous les sons (« All ») : la suite se fait sur tous. Rien d'autre ne change.
    func showingAll(_ file: FLPFile) -> FLPFile {
        var out = file
        if let groupEvent { out.events[groupEvent].bytes = [0xFF, 0xFF, 0xFF, 0xFF] }
        return out
    }

    /// La copie rangée : chaque clip sur sa nouvelle piste (`tracks` : rang du clip → piste, 0 = piste 1). Les pistes
    /// où il y a des clips, avant ou après, perdent leur nom, reprennent la couleur des pistes jamais touchées et
    /// jouent (leur nom disait ce qu'elles jouaient avant ; l'Organiser les nomme ensuite d'après ce qui y joue). Un
    /// clip sur une piste coupée arrête tout (il se mettrait à jouer). Tout le reste est recopié octet pour octet.
    func rearranged(_ file: FLPFile, tracks: [Int: Int]) throws -> FLPFile {
        var out = showingAll(file)
        guard let playlistEvent else { return out }
        guard clips.allSatisfy({ !mutedTracks.contains($0.track) }) else { throw FLPError.unsupported("piste coupée") }
        var bytes = out.events[playlistEvent].bytes
        for (item, track) in tracks {
            guard (0..<clips.count).contains(item), (0..<trackCount).contains(track) else {
                throw FLPError.unsupported("clips")
            }
            FLPBytes.put(UInt32(trackCount - 1 - track), into: &bytes, at: item * itemSize + 12, size: 2)
        }
        out.events[playlistEvent].bytes = bytes

        let touched = Set(clips.map(\.track)).union(clips.map { tracks[$0.item] ?? $0.track })
        var counts: [UInt32: Int] = [:]
        for index in trackEvents { counts[FLPBytes.uint(file.events[index].bytes, at: 4, size: 4), default: 0] += 1 }
        let plain = counts.max { $0.value != $1.value ? $0.value < $1.value : $0.key > $1.key }?.key ?? 0
        var removed: [Int] = []
        for track in touched.sorted() {
            let index = trackEvents[track]
            FLPBytes.put(plain, into: &out.events[index].bytes, at: 4, size: 4)
            out.events[index].bytes[Self.trackEnabled] = 1
            var next = index + 1
            while next < out.events.count, next <= index + 3, out.events[next].id != Event.track,
                  out.events[next].id != Event.arrangement {
                if out.events[next].id == Event.trackName { removed.append(next) }
                next += 1
            }
        }
        for index in removed.sorted(by: >) { out.events.remove(at: index) }
        return out
    }
}

/// Playlist rangée : chaque son sur sa piste, tous les clips qui jouent les mêmes sons réunis sur la même piste.
enum PlaylistLayout {
    /// Ce que joue un clip.
    enum Group: Hashable {
        /// Ses sons (rangs du Channel rack).
        case sounds(Set<Int>)
        /// Un pattern où rien ne joue : seul sur sa piste.
        case silent(Int)
        /// Un canal qui n'est pas un son (automation) : seul sur sa piste.
        case other(Int)
    }

    struct Result: Equatable {
        /// Nouvelle piste de chaque clip (rang du clip → piste, 0 = piste 1).
        var tracks: [Int: Int] = [:]
        /// Sons qui jouent sur chaque piste (les pistes sans son n'y sont pas).
        var sounds: [Int: Set<Int>] = [:]
        /// Pistes utilisées (les premières).
        var count = 0
    }

    /// Pur (testé) : chaque groupe a sa piste, les groupes de sons dans l'ordre de `key` (familles, sortes, place dans
    /// le Channel rack) puis de leur premier clip ; ensuite les patterns muets, puis le reste (automations). Un clip qui
    /// en chevaucherait un autre du même groupe va sur une piste de plus, juste dessous : jamais l'un sur l'autre.
    /// nil : plus de pistes qu'il n'y en a dans FL.
    static func make(_ clips: [FLPProject.Clip], group: (FLPProject.Clip) -> Group,
                     key: (Set<Int>) -> (Int, Int, Int), trackCount: Int) -> Result? {
        var members: [Group: [FLPProject.Clip]] = [:]
        for clip in clips { members[group(clip), default: []].append(clip) }
        func sorted(_ g: Group) -> [FLPProject.Clip] {
            members[g]!.sorted { ($0.position, $0.track, $0.item) < ($1.position, $1.track, $1.item) }
        }
        func rank(_ g: Group) -> [Int] {
            let first = sorted(g)[0]
            switch g {
            case .sounds(let s):
                let k = key(s)
                return [0, k.0, k.1, k.2, first.position, first.track, first.item]
            case .silent: return [1, 0, 0, 0, first.position, first.track, first.item]
            case .other: return [2, 0, 0, 0, first.position, first.track, first.item]
            }
        }
        let order = members.keys.map { (group: $0, rank: rank($0)) }.sorted { $0.rank.lexicographicallyPrecedes($1.rank) }
        var out = Result()
        for (g, _) in order {
            var lanes: [[FLPProject.Clip]] = []
            for clip in sorted(g) {
                let free = lanes.firstIndex { lane in lane.allSatisfy { $0.end <= clip.position || clip.end <= $0.position } }
                if let free { lanes[free].append(clip) } else { lanes.append([clip]) }
            }
            for lane in lanes {
                let track = out.count
                out.count += 1
                for clip in lane { out.tracks[clip.item] = track }
                if case .sounds(let s) = g, !s.isEmpty { out.sounds[track] = s }
            }
        }
        return out.count <= trackCount ? out : nil
    }
}
