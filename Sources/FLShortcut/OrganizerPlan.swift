// Organiser : ce qui sera fait dans tout le projet, d'après ce qu'est chaque son du Channel rack (sa famille, sa
// sorte) : sons sans aucune note supprimés (leurs pistes du Mixer remises comme neuves), Channel rack regroupé
// (familles, puis sortes), pistes du Mixer dans le même ordre avec un bus par famille juste après ses pistes (808 avec
// les drums), chaque son envoyé seulement à son bus (un son envoyé au Master prend une piste libre), pistes de la
// Playlist dans le même ordre, le tout coloré par famille et renommé simplement (« Kick », « Kick 2 », « 808 »…) ; un
// pattern, une piste de la Playlist ou du Mixer où ne joue qu'un son prend le nom de ce son dans le Channel rack
// (retour de l'utilisateur : « Mélodie 4 » dans la Playlist pour le son « Mélodie 3 »). Pur (testé) : l'application et
// « Revenir comme avant » sont dans OrganizerApply.
import Foundation

/// Ce que l'utilisateur garde dans « Organiser ».
struct OrganizerOptions: Equatable {
    var rack = true
    var patterns = true
    var mixer = true
    var playlist = true
    /// Renommer (sinon : couleurs et ordre seulement).
    var rename = true
    /// Mixer : un bus par famille (les 808 avec les drums), chaque son envoyé seulement à son bus (retour de
    /// l'utilisateur) ; sinon les envois restent et les pistes reliées restent côte à côte.
    var buses = true
    /// Sons sans aucune note supprimés du Channel rack, leurs pistes du Mixer remises comme neuves (retour de
    /// l'utilisateur : « je veux qu'elles disparaissent »).
    var deleteUnused = true
    /// Playlist : un son par piste (retour de l'utilisateur : « deux sons différents ne doivent pas être sur la même
    /// ligne ») ; `maxSplits` : les premiers seulement (ceux que FL a laissé faire).
    var splitTracks = true
    var maxSplits: Int?
}

/// Un pattern descendu de la piste de la Playlist qu'il partage avec un autre son vers une piste vide, à lui.
struct PlaylistSplit: Equatable {
    /// Le pattern (index 0 = pattern 1 de FL), sa piste et la piste vide où vont tous ses clips (index 0 = piste 1).
    let pattern: Int
    let from: Int
    let to: Int
    /// Un de ses sons et une position de la chanson où il joue (vérifié sur `to`, piste seule) ; un son du pattern
    /// qui reste sur `from`, et où il joue (vérifié aussi : FL n'a pas descendu tous les clips).
    let sound: Int
    let at: Double
    let kept: Int
    let keptAt: Double
}

/// Famille et sorte d'un élément (sorte nil : sa famille seule).
struct Verdict: Equatable {
    var family: SoundFamily
    var kind: SoundKind? = nil

    /// « Kick », « 808 »…, sinon le nom de la famille ; nil pour « À vérifier » (pas renommé).
    var baseName: String? {
        guard family != .unsure else { return nil }
        return kind?.name ?? family.trackName
    }

    /// Le bus du Mixer où il va (808 : Drums).
    var busFamily: SoundFamily { kind?.busFamily ?? family }
}

struct OrganizerPlan: Equatable {
    struct Area: Equatable {
        /// Couleur et nom prévus de chaque élément, par index d'origine (Mixer : numéro de la piste).
        var colors: [Int: RGBColor] = [:]
        var names: [Int: String] = [:]
        /// Remontées (Channel rack : ⌥↑ ; Mixer : ⌥←, place 0 = piste 1) et la disposition finale (place → index
        /// d'origine ; Mixer : place → numéro de la piste d'origine). Vides : rien ne bouge.
        var moves: [Move] = []
        var final: [Int] = []
        /// Ce qu'est chaque élément (aperçu, icônes).
        var verdicts: [Int: Verdict] = [:]
        /// Mixer : pistes vers lesquelles chaque piste d'origine enverra seulement (0 = le Master), et les bus
        /// (piste d'origine → famille).
        var routes: [Int: [Int]] = [:]
        var buses: [Int: SoundFamily] = [:]
        /// Mixer : son envoyé au Master → la piste libre qu'il prend (retour de l'utilisateur : la boucle de batterie
        /// n'était pas dans le Mixer) ; pistes des sons supprimés, remises comme neuves (nom de FL, couleur de FL).
        var links: [Int: Int] = [:]
        var resets: Set<Int> = []

        var isEmpty: Bool { colors.isEmpty && names.isEmpty && moves.isEmpty && routes.isEmpty && links.isEmpty }
    }

    var rack = Area()
    var patterns = Area()
    var mixer = Area()
    var playlist = Area()
    /// Sons sans aucune note supprimés du Channel rack avant tout le reste (index d'origine, dans l'ordre).
    var deleted: [Int] = []
    /// Playlist : patterns descendus chacun sur sa piste, avant ses noms, couleurs et son ordre (prévus d'après).
    var splits: [PlaylistSplit] = []
    /// Analyse sur le fichier : la piste de chaque clip dans la copie rangée (OrganizerProjectFile).
    var layout: PlaylistLayout.Result?
    /// Ce qui a servi à faire le plan : il est refait sur le Channel rack une fois les sons supprimés.
    struct Source: Equatable {
        var families: [Int: SoundFamily]
        var kinds: [Int: SoundKind]
        var options: OrganizerOptions
    }
    var source: Source?

    var isEmpty: Bool {
        rack.isEmpty && patterns.isEmpty && mixer.isEmpty && playlist.isEmpty && deleted.isEmpty && splits.isEmpty
    }

    /// Patterns descendus au plus : au-delà, la Playlist reste comme elle est.
    static let maxSplits = 32
    /// Couleur d'une piste de la Playlist jamais touchée (gris de FL).
    static let plainTrack = RGBColor(r: 64, g: 64, b: 64)

    /// `families` et `kinds` : ce qu'est chaque son du Channel rack (index du canal), modifiable dans l'aperçu.
    static func make(_ result: OrganizerResult, families: [Int: SoundFamily], kinds: [Int: SoundKind],
                     styles: [SoundFamily: FamilyStyle], options: OrganizerOptions = OrganizerOptions()) -> OrganizerPlan {
        func verdict(_ channel: Int) -> Verdict? {
            families[channel].map { Verdict(family: $0, kind: OrganizerApplier.kind(channel, families: families, kinds: kinds)) }
        }
        var plan = OrganizerPlan()
        plan.source = Source(families: families, kinds: kinds, options: options)
        if options.deleteUnused { plan.deleted = result.unused.sorted() }
        let deleted = Set(plan.deleted)

        // Channel rack : l'ordre des familles, puis des sortes ; les noms numérotés dans cet ordre.
        let channels = result.channels.sorted { $0.index < $1.index }
        let rack = OrganizerApplier.rackPlan(channels, families: families, kinds: kinds)
        var rackPlace: [Int: Int] = [:]
        for (place, index) in rack.final.enumerated() { rackPlace[index] = place }
        let channelNames = numbered(rack.final.compactMap { i in verdict(i)?.baseName.map { (index: i, name: $0) } })
        if options.rack {
            plan.rack.moves = rack.moves
            plan.rack.final = rack.final
            plan.rack.colors = OrganizerApplier.plannedColors(families: families, styles: styles, order: rack.final)
            if options.rename {
                var current: [Int: String] = [:]
                for channel in channels { current[channel.index] = channel.name }
                plan.rack.names = channelNames.filter { current[$0.key] != $0.value }
            }
            for channel in channels { if let v = verdict(channel.index) { plan.rack.verdicts[channel.index] = v } }
        }

        // Le nom qu'un pattern ou une piste où ne joue qu'un son prend : celui de ce son dans le Channel rack, s'il y est
        // renommé.
        let sameName: (Set<Int>) -> String? = { sounds in
            let classified = sounds.filter { verdict($0) != nil }
            guard options.rack, options.rename, classified.count == 1, let only = classified.first else { return nil }
            return channelNames[only]
        }

        // Patterns : le nom qu'ils ont déjà s'il dit ce qu'ils sont (« kick », « hi hat »), sinon ce qui y joue (un
        // « Drums 1 » qui ne joue que des kicks devient « Kick ») ; renommés, sauf un nom de partie du morceau
        // (« Intro ») : « Serum 2 #3 », nom donné par FL d'après le son, devient « Mélodie » (retour de l'utilisateur).
        if options.patterns {
            var verdicts: [Int: Verdict] = [:]
            var renamable = Set<Int>()
            var current: [Int: String] = [:]
            var fixed: [Int: String] = [:]
            for pattern in result.patterns {
                let sounds = result.patternSounds[pattern.index] ?? []
                let heard = groupVerdict(sounds.sorted().compactMap(verdict))
                let v = named(pattern.name, heard: heard)
                verdicts[pattern.index] = v
                if v == heard, let name = sameName(sounds) { fixed[pattern.index] = name }
                if !SoundNames.isSection(pattern.name) { renamable.insert(pattern.index) }
                current[pattern.index] = pattern.name
            }
            plan.patterns = area(verdicts, order: result.patterns.map(\.index), current: current, styles: styles,
                                 rename: options.rename, renamable: renamable, fixed: fixed)
        }

        // Mixer : même ordre que le Channel rack.
        if options.mixer {
            plan.mixer = mixerArea(result, verdict: verdict, rackPlace: rackPlace, channelNames: channelNames,
                                   styles: styles, rename: options.rename, buses: options.buses, deleted: deleted,
                                   cleanup: options.deleteUnused)
        }

        // Playlist : chaque piste prend ce que jouent ses sons (ou ce qu'elle fait entendre, pour un clip audio),
        // renommée, sauf un nom de partie du morceau (« Intro ») ; les pistes rangées comme le Channel rack (retour de
        // l'utilisateur), celles qui ne jouent rien après.
        if options.playlist {
            // Un son par piste : la Playlist prévue telle qu'elle sera une fois les patterns descendus.
            var result = result
            // Place d'un groupe de sons : sa famille, sa sorte, puis son premier son dans le Channel rack.
            let key: (Set<Int>) -> (Int, Int, Int) = { sounds in
                guard let v = groupVerdict(sounds.sorted().compactMap(verdict)), v.family != .unsure
                else { return (Int.max, 0, 0) }
                return (v.family.rank, v.kind?.rackRank ?? SoundKind.rackOrder.count,
                        sounds.compactMap { rackPlace[$0] }.min() ?? Int.max / 2)
            }
            if let project = result.project {
                // Analyse sur le fichier : chaque clip ira, dans la copie rangée, sur la piste de ses sons (les mêmes
                // sons, la même piste), les pistes déjà dans l'ordre des familles ; rien à descendre ni à remonter dans
                // FL. Les pistes perdent leur ancien nom dans la copie : elles sont nommées d'après ce qui y joue.
                if let layout = PlaylistLayout.make(project.clips, group: { project.groups[$0.item] ?? .silent(0) },
                                                    key: key, trackCount: project.trackCount) {
                    plan.layout = layout
                    var listed: [Int: PlaylistTrackInfo] = [:]
                    for track in result.playlist { listed[track.index] = track }
                    result.playlist = (0..<layout.count).map {
                        listed[$0] ?? PlaylistTrackInfo(index: $0, selected: false, color: Self.plainTrack, name: "")
                    }
                    result.trackSounds = layout.sounds
                } else {
                    result.playlist = []
                    result.trackSounds = [:]
                }
                result.trackItems = []
            } else if options.splitTracks {
                plan.splits = Array(playlistSplits(result, key: key).prefix(options.maxSplits ?? Self.maxSplits))
                result = result.splitting(plan.splits)
            }
            var heard: [Int: Verdict] = [:]
            for (track, sounds) in result.trackSounds {
                if let v = groupVerdict(sounds.sorted().compactMap(verdict)) { heard[track] = v }
            }
            for item in result.trackItems where heard[item.index] == nil {
                heard[item.index] = Verdict(family: item.family, kind: item.kind)
            }
            var verdicts: [Int: Verdict] = [:]
            var renamable = Set<Int>()
            var current: [Int: String] = [:]
            var fixed: [Int: String] = [:]
            for track in result.playlist {
                let v = named(track.name, heard: heard[track.index])
                verdicts[track.index] = v
                if v == heard[track.index], let name = sameName(result.trackSounds[track.index] ?? []) {
                    fixed[track.index] = name
                }
                if !SoundNames.isSection(track.name) { renamable.insert(track.index) }
                current[track.index] = track.name
            }
            let order = playlistOrder(result, verdicts: verdicts, rackPlace: rackPlace)
            plan.playlist = area(verdicts, order: order, current: current, styles: styles, rename: options.rename,
                                 renamable: renamable, fixed: fixed)
            let indices = result.playlist.map(\.index).sorted()
            if result.project == nil, order != indices, let span = indices.last {
                plan.playlist.moves = RegroupPlan.moves(from: Array(0...span), to: order)
                plan.playlist.final = order
            }
        }
        return plan
    }

    /// Le même plan sur le projet une fois des sons supprimés (`result`, `map` : index d'avant → maintenant), sans
    /// rien supprimer de plus.
    func replanned(_ result: OrganizerResult, map: [Int: Int], styles: [SoundFamily: FamilyStyle]) -> OrganizerPlan {
        guard let source else { return self }
        // Rien de plus à supprimer : ni les sons supprimés (déjà partis), ni ceux que FL n'a pas supprimés.
        var rest = result
        rest.unused = []
        func moved<T>(_ values: [Int: T]) -> [Int: T] {
            var out: [Int: T] = [:]
            for (index, value) in values { if let now = map[index] { out[now] = value } }
            return out
        }
        return Self.make(rest, families: moved(source.families), kinds: moved(source.kinds), styles: styles,
                         options: source.options)
    }

    /// Pur (testé) : les patterns à descendre pour qu'aucune piste de la Playlist ne mêle deux sons. Seul un pattern
    /// sûr bouge : chacun de ses sons ne joue dans aucun autre pattern ni sur aucune autre piste, et une position de
    /// la chanson où il joue est connue (la vérification l'y écoute). Sur chaque piste où jouent au moins deux de ces
    /// patterns, le premier dans l'ordre des familles (`key`) reste ; les autres vont, dans cet ordre, sur les pistes
    /// vides qui suivent la dernière lue.
    static func playlistSplits(_ result: OrganizerResult, key: (Set<Int>) -> (Int, Int, Int)) -> [PlaylistSplit] {
        let patterns = result.patternSounds.filter { !$0.value.isEmpty }
        var owners: [Int: Set<Int>] = [:]
        for (pattern, sounds) in patterns { for sound in sounds { owners[sound, default: []].insert(pattern) } }
        var places: [Int: Set<Int>] = [:]
        for (track, sounds) in result.trackSounds { for sound in sounds { places[sound, default: []].insert(track) } }
        var next = ((result.playlist.map(\.index) + Array(result.trackSounds.keys)).max() ?? -1) + 1
        func heardAt(_ sounds: Set<Int>) -> (sound: Int, at: Double)? {
            for sound in sounds.sorted() { if let at = result.soundAt[sound] { return (sound, at) } }
            return nil
        }
        var out: [PlaylistSplit] = []
        for track in result.trackSounds.keys.sorted() {
            let sounds = result.trackSounds[track] ?? []
            let here = patterns.filter { pattern, own in
                guard !own.isDisjoint(with: sounds), heardAt(own) != nil else { return false }
                let onlyPattern: Set<Int> = [pattern], onlyTrack: Set<Int> = [track]
                return own.allSatisfy { owners[$0] == onlyPattern && places[$0] == onlyTrack }
            }
            guard here.count >= 2 else { continue }
            let ordered = here.keys.sorted { a, b in
                let ka = key(here[a]!), kb = key(here[b]!)
                return (ka.0, ka.1, ka.2, a) < (kb.0, kb.1, kb.2, b)
            }
            guard let stay = heardAt(here[ordered[0]]!) else { continue }
            for pattern in ordered.dropFirst() {
                guard let moved = heardAt(here[pattern]!) else { continue }
                out.append(PlaylistSplit(pattern: pattern, from: track, to: next, sound: moved.sound, at: moved.at,
                                         kept: stay.sound, keptAt: stay.at))
                next += 1
            }
        }
        return out
    }

    /// Le même plan, les patterns descendus limités aux `count` premiers (ceux que FL a laissé faire) : la Playlist
    /// prévue de nouveau, sans rien supprimer de plus.
    func limitingSplits(to count: Int, _ result: OrganizerResult, styles: [SoundFamily: FamilyStyle]) -> OrganizerPlan {
        guard var source else { return self }
        source.options.maxSplits = count
        var rest = result
        rest.unused = []
        return Self.make(rest, families: source.families, kinds: source.kinds, styles: styles, options: source.options)
    }

    /// La Playlist prévue de nouveau sur ce projet (clips réunis sur la piste de leur son, lus dans FL), sans pattern
    /// à descendre en entier.
    func replannedPlaylist(_ result: OrganizerResult, styles: [SoundFamily: FamilyStyle]) -> Area {
        guard var source else { return playlist }
        source.options.splitTracks = false
        var rest = result
        rest.unused = []
        return Self.make(rest, families: source.families, kinds: source.kinds, styles: styles,
                         options: source.options).playlist
    }

    /// Pistes de la Playlist lues, dans l'ordre du Channel rack : familles dans leur ordre, puis sortes ; à égalité,
    /// celle dont le premier son est le plus haut dans le Channel rack, puis leur ordre d'avant. Celles qui ne jouent
    /// rien de classé suivent, dans leur ordre.
    private static func playlistOrder(_ result: OrganizerResult, verdicts: [Int: Verdict],
                                      rackPlace: [Int: Int]) -> [Int] {
        let tracks = result.playlist.map(\.index).sorted()
        func key(_ t: Int) -> (Int, Int, Int, Int) {
            guard let v = verdicts[t], v.family != .unsure else { return (Int.max, 0, 0, t) }
            let first = (result.trackSounds[t] ?? []).compactMap { rackPlace[$0] }.min() ?? Int.max / 2
            return (v.family.rank, v.kind?.rackRank ?? SoundKind.rackOrder.count, first, t)
        }
        return tracks.sorted { key($0) < key($1) }
    }

    /// Ce qu'est un pattern ou une piste : son nom s'il dit précisément ce qu'il est (« kick », « Lead »), sinon ce
    /// qui y joue, sinon son nom général (« Drums 2 »). Un nom que l'Organiser a pu donner cède à ce qui y joue s'il
    /// dit autre chose (« Snare » pour un arpège, « Snare 3 » pour un hi-hat).
    private static func named(_ name: String, heard: Verdict?) -> Verdict? {
        guard let kind = SoundNames.kind(of: name), !kind.isGeneral || heard == nil else { return heard }
        if SoundNames.isGenerated(name), let heard, !SoundNames.keeps(kind, heard: heard) { return heard }
        return Verdict(family: kind.family, kind: kind)
    }

    /// Couleurs (dégradé de chaque famille dans l'ordre donné) et noms numérotés dans cet ordre ; `fixed` : les noms
    /// déjà décidés (celui de l'unique son), jamais repris par la numérotation. Un nom déjà porté n'est pas reposé.
    private static func area(_ verdicts: [Int: Verdict], order: [Int], current: [Int: String],
                             styles: [SoundFamily: FamilyStyle], rename: Bool, renamable: Set<Int>,
                             fixed: [Int: String] = [:]) -> Area {
        var out = Area()
        out.verdicts = verdicts
        out.colors = OrganizerApplier.plannedColors(families: verdicts.mapValues(\.family), styles: styles, order: order)
        if rename {
            let bases = order.compactMap { i -> (index: Int, name: String)? in
                guard renamable.contains(i), fixed[i] == nil else { return nil }
                return verdicts[i]?.baseName.map { (index: i, name: $0) }
            }
            var names = numbered(bases, taken: Set(fixed.values))
            for (i, name) in fixed where renamable.contains(i) { names[i] = name }
            out.names = names.filter { current[$0.key] != $0.value }
        }
        return out
    }

    /// Pistes du Mixer reliées à un son classé (les sons laissés de côté ou supprimés ne comptent pas), dans l'ordre
    /// du Channel rack ; un son classé envoyé au Master prend d'abord une piste libre. Avec `buses` : un bus par
    /// famille juste après ses pistes (une piste sans son qui reçoit déjà surtout de cette famille, sinon une piste
    /// libre), chaque piste envoyée seulement à son bus, le bus au Master ; « À vérifier » : sans bus. Sans : les
    /// pistes reliées par un envoi côte à côte, celle qui reçoit après celles qui lui envoient. Les autres pistes
    /// suivent, dans leur ordre ; avec `cleanup`, celles des sons supprimés et celles qui ont un nom sans aucun son
    /// relié ni envoi reçu (retour de l'utilisateur : deux pistes « en trop », en noir) sont remises comme neuves (nom
    /// et couleur de FL ; leurs effets restent). Une piste avec un seul son prend le nom de ce son ; un bus
    /// « <famille> Bus », s'il a encore le nom de FL.
    private static func mixerArea(_ result: OrganizerResult, verdict: (Int) -> Verdict?, rackPlace: [Int: Int],
                                  channelNames: [Int: String], styles: [SoundFamily: FamilyStyle],
                                  rename: Bool, buses: Bool, deleted: Set<Int>, cleanup: Bool) -> Area {
        let last = result.mixer.count - 2                         // la dernière piste est « Current »
        guard last >= 1 else { return Area() }
        var out = Area()
        let sounds = OrganizerSession.sounds(result.channels)
        let kept = sounds.filter { !deleted.contains($0.index) }
        // Pistes libérées par les sons supprimés (ici ou avant : `freed`), qu'aucun son gardé n'utilise.
        let keptTracks = Set(kept.map(\.mixerTrack))
        let freed = Set(sounds.filter { deleted.contains($0.index) }.map(\.mixerTrack)).union(result.freed)
            .filter { (1...last).contains($0) && !keptTracks.contains($0) }
        // Envois entre pistes (sans le Master).
        var sources: [Int: [Int]] = [:]
        for (from, dests) in result.routes where (1...last).contains(from) {
            for d in dests where (1...last).contains(d) && d != from { sources[d, default: []].append(from) }
        }
        // Pistes libres : nom de FL (ou libérée), aucun son gardé ni canal relié, aucun envoi connu vers elle ou
        // depuis elle ; les libérées en dernier.
        let routed = Set(sources.keys).union(sources.values.flatMap { $0 })
        let everUsed = Set(result.channels.map(\.mixerTrack))
        var free = result.mixer.filter { t in
            (1...last).contains(t.index) && !keptTracks.contains(t.index) && !routed.contains(t.index)
                && ((t.hasDefaultName && !everUsed.contains(t.index)) || freed.contains(t.index))
        }.map(\.index).sorted { (freed.contains($0) ? 1 : 0, $0) < (freed.contains($1) ? 1 : 0, $1) }
        // Un son classé envoyé au Master : une piste libre, dans l'ordre du Channel rack.
        for channel in kept.sorted(by: { (rackPlace[$0.index] ?? .max) < (rackPlace[$1.index] ?? .max) })
        where channel.mixerTrack == 0 && verdict(channel.index) != nil && !free.isEmpty {
            out.links[channel.index] = free.removeFirst()
        }
        var linked: [Int: [Int]] = [:]                          // piste -> sons, dans l'ordre du Channel rack
        for channel in kept where verdict(channel.index) != nil {
            let track = out.links[channel.index] ?? channel.mixerTrack
            if (1...last).contains(track) { linked[track, default: []].append(channel.index) }
        }
        for track in linked.keys { linked[track]?.sort { (rackPlace[$0] ?? .max) < (rackPlace[$1] ?? .max) } }
        var key: [Int: Double] = [:]
        for (track, sounds) in linked {
            key[track] = Double(sounds.compactMap { rackPlace[$0] }.min() ?? Int.max / 2)
            if let v = groupVerdict(sounds.compactMap(verdict)) { out.verdicts[track] = v }
        }
        func sortKey(_ t: Int) -> (Double, Int) { (key[t] ?? Double(Int.max / 2), t) }

        var layout: [Int] = []
        if !linked.isEmpty {
            if buses {
                layout = busLayout(linked: linked, sources: sources, free: &free, sortKey: sortKey, out: &out)
            } else {
                layout = groupedLayout(linked: linked, sources: sources, key: &key, out: &out)
            }
        }
        // Pistes des sons supprimés pas reprises, et pistes nommées sans aucun son ni envoi reçu : comme neuves (nom
        // de FL, couleur des pistes jamais touchées).
        let idle = cleanup ? Set(result.mixer.filter { t in
            (1...last).contains(t.index) && !t.hasDefaultName && !everUsed.contains(t.index) && sources[t.index] == nil
        }.map(\.index)) : []
        out.resets = freed.union(idle).subtracting(layout).subtracting(out.links.values)
        let relevant = Set(layout)
        if let span = relevant.max() {
            let current = Array(1...span)
            let target = layout + current.filter { !relevant.contains($0) }
            out.moves = RegroupPlan.moves(from: current, to: target)
            out.final = target
            out.colors = OrganizerApplier.plannedColors(families: out.verdicts.mapValues(\.family), styles: styles,
                                                        order: target)
        }
        let fresh = defaultColor(result, used: everUsed, routed: routed)
        var byIndex: [Int: MixerTrackInfo] = [:]
        for track in result.mixer { byIndex[track.index] = track }
        for track in out.resets {
            if let fresh, byIndex[track]?.color != fresh { out.colors[track] = fresh }
            if byIndex[track]?.hasDefaultName == false { out.names[track] = "" }
        }
        if rename {
            var bases: [(index: Int, name: String)] = []
            var taken = Set<String>()
            for track in layout {
                if let sounds = linked[track], sounds.count == 1, let name = channelNames[sounds[0]] {
                    out.names[track] = name
                    taken.insert(name)
                } else if let base = out.verdicts[track]?.baseName {
                    if linked[track] != nil {
                        bases.append((track, base))
                    } else if byIndex[track]?.hasDefaultName ?? false || freed.contains(track) {
                        bases.append((track, String(localized: "\(base) Bus")))
                    }
                }
            }
            out.names.merge(numbered(bases, taken: taken)) { a, _ in a }
            out.names = out.names.filter { byIndex[$0.key]?.name != $0.value }
        }
        return out
    }

    /// Couleur d'une piste du Mixer jamais touchée (la plus fréquente parmi celles qui ont le nom de FL, sans son ni
    /// envoi) ; nil s'il n'y en a pas.
    private static func defaultColor(_ result: OrganizerResult, used: Set<Int>, routed: Set<Int>) -> RGBColor? {
        let last = result.mixer.count - 2
        guard last >= 1 else { return nil }
        var counts: [RGBColor: Int] = [:]
        for t in result.mixer where (1...last).contains(t.index) && t.hasDefaultName && !used.contains(t.index)
            && !routed.contains(t.index) {
            counts[t.color, default: 0] += 1
        }
        return counts.max { a, b in a.value != b.value ? a.value < b.value : a.key.hex > b.key.hex }?.key
    }

    /// Un bus par famille : les pistes de la famille (808 : Drums) dans l'ordre du Channel rack, puis son bus ; les
    /// familles dans l'ordre de leur premier son ; une piste « À vérifier » seule à sa place. Un bus pris dans `free`
    /// en est retiré.
    private static func busLayout(linked: [Int: [Int]], sources: [Int: [Int]], free: inout [Int],
                                  sortKey: (Int) -> (Double, Int), out: inout Area) -> [Int] {
        var members: [SoundFamily: [Int]] = [:]
        var alone: [Int] = []
        for track in linked.keys {
            if let v = out.verdicts[track], v.family != .unsure {
                members[v.busFamily, default: []].append(track)
            } else {
                alone.append(track)
            }
        }
        // Bus déjà là : une piste sans son qui reçoit le plus de pistes de la famille.
        var taken = Set(linked.keys)
        var busOf: [SoundFamily: Int] = [:]
        for family in SoundFamily.order {
            guard let tracks = members[family] else { continue }
            let mine = Set(tracks)
            let candidates = sources.compactMap { d, froms -> (track: Int, count: Int)? in
                guard !taken.contains(d) else { return nil }
                let count = froms.filter { mine.contains($0) }.count
                return count > 0 ? (d, count) : nil
            }
            if let best = candidates.max(by: { a, b in a.count != b.count ? a.count < b.count : a.track > b.track }) {
                busOf[family] = best.track
                taken.insert(best.track)
            }
        }
        // Sinon une piste libre.
        free.removeAll { taken.contains($0) }
        for family in SoundFamily.order where members[family] != nil && busOf[family] == nil && !free.isEmpty {
            busOf[family] = free.removeFirst()
        }
        var blocks: [[Int]] = alone.map { [$0] }
        for (family, tracks) in members {
            let sorted = tracks.sorted { sortKey($0) < sortKey($1) }
            guard let bus = busOf[family] else {
                blocks.append(sorted)
                continue
            }
            blocks.append(sorted + [bus])
            for t in sorted { out.routes[t] = [bus] }
            out.routes[bus] = [0]
            out.buses[bus] = family
            out.verdicts[bus] = Verdict(family: family)
        }
        return blocks.sorted { sortKey($0[0]) < sortKey($1[0]) }.flatMap { $0 }
    }

    /// Sans bus : les pistes reliées par un envoi d'un bloc, celle qui reçoit juste après la dernière qui lui envoie.
    private static func groupedLayout(linked: [Int: [Int]], sources: [Int: [Int]], key: inout [Int: Double],
                                      out: inout Area) -> [Int] {
        var relevant = Set(linked.keys)
        var grew = true
        while grew {
            grew = false
            for (d, froms) in sources where !relevant.contains(d) && froms.contains(where: { relevant.contains($0) }) {
                relevant.insert(d)
                grew = true
            }
        }
        for _ in 0..<relevant.count {                           // groupes de groupes : une passe par niveau
            for track in relevant where linked[track] == nil {
                let fromKeys = (sources[track] ?? []).compactMap { key[$0] }
                if let top = fromKeys.max() { key[track] = top + 0.5 }
            }
        }
        var group: [Int: Int] = [:]
        func root(_ t: Int) -> Int {
            var t = t
            while let up = group[t], up != t { t = up }
            return t
        }
        for track in relevant { group[track] = track }
        for (d, froms) in sources where relevant.contains(d) {
            for from in froms where relevant.contains(from) {
                let a = root(from), b = root(d)
                if a != b { group[max(a, b)] = min(a, b) }
            }
        }
        var blocks: [Int: [Int]] = [:]
        for track in relevant { blocks[root(track), default: []].append(track) }
        let keys = key
        func ordered(_ t: Int) -> (Double, Int) { (keys[t] ?? Double(Int.max / 2), t) }
        let layout = blocks.values
            .map { $0.sorted { ordered($0) < ordered($1) } }
            .sorted { ordered($0[0]) < ordered($1[0]) }
            .flatMap { $0 }
        // Une piste de groupe : la famille des pistes qui lui envoient.
        for track in layout where linked[track] == nil {
            if let v = groupVerdict((sources[track] ?? []).compactMap { out.verdicts[$0] }) {
                out.verdicts[track] = Verdict(family: v.family)
            }
        }
        return layout
    }

    /// Pur (testé) : ce qu'est un ensemble de sons : la famille la plus présente (« À vérifier » seulement s'il n'y a
    /// rien d'autre ; égalité : l'ordre des familles), et leur sorte quand tous ceux de cette famille disent la même ;
    /// nil s'il n'y a rien.
    static func groupVerdict(_ members: [Verdict]) -> Verdict? {
        let sure = members.filter { $0.family != .unsure }
        let pool = sure.isEmpty ? members : sure
        var counts: [SoundFamily: Int] = [:]
        for v in pool { counts[v.family, default: 0] += 1 }
        guard let family = counts.max(by: { a, b in a.value != b.value ? a.value < b.value : a.key.rank > b.key.rank })?.key
        else { return nil }
        let same = pool.filter { $0.family == family }
        let kinds = Set(same.compactMap(\.kind))
        let kind = kinds.count == 1 && same.allSatisfy { $0.kind != nil } ? kinds.first : nil
        return Verdict(family: family, kind: kind)
    }

    /// Pur (testé) : noms numérotés dans l'ordre donné (« Kick », « Kick 2 »…), sans reprendre un nom de `taken`.
    static func numbered(_ bases: [(index: Int, name: String)], taken: Set<String> = []) -> [Int: String] {
        var count: [String: Int] = [:]
        var used = taken
        var out: [Int: String] = [:]
        for item in bases {
            var n = count[item.name, default: 0]
            var name = item.name
            repeat {
                n += 1
                name = n == 1 ? item.name : "\(item.name) \(n)"
            } while used.contains(name)
            count[item.name] = n
            used.insert(name)
            out[item.index] = name
        }
        return out
    }
}

extension OrganizerResult {
    /// Pur (testé) : la Playlist une fois ces patterns descendus : leurs sons quittent leur piste pour la nouvelle,
    /// une piste vide (sans nom ; sa vraie couleur est relue dans FL avant d'y toucher).
    func splitting(_ splits: [PlaylistSplit]) -> OrganizerResult {
        var out = self
        for split in splits {
            let moved = patternSounds[split.pattern] ?? []
            out.trackSounds[split.from]?.subtract(moved)
            out.trackSounds[split.to] = moved
            if !out.playlist.contains(where: { $0.index == split.to }) {
                out.playlist.append(PlaylistTrackInfo(index: split.to, selected: false,
                                                      color: RGBColor(r: 0x56, g: 0x5D, b: 0x6A), name: ""))
            }
        }
        out.playlist.sort { $0.index < $1.index }
        return out
    }
}
