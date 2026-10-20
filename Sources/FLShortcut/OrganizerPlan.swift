// Organiser : ce qui sera fait dans tout le projet, d'après ce qu'est chaque son du Channel rack (sa famille, sa
// sorte) : Channel rack regroupé (familles, puis sortes), pistes du Mixer dans le même ordre (pistes reliées par un
// envoi côte à côte, la piste qui reçoit après celles qui lui envoient), patterns et pistes de la Playlist (que FL ne
// laisse pas déplacer), le tout coloré par famille et renommé simplement (« Kick », « Kick 2 », « 808 »…). Pur
// (testé) : l'application et « Revenir comme avant » sont dans OrganizerApply.
import Foundation

/// Ce que l'utilisateur garde dans « Tout organiser ».
struct OrganizerOptions: Equatable {
    var rack = true
    var patterns = true
    var mixer = true
    var playlist = true
    /// Renommer (sinon : couleurs et ordre seulement).
    var rename = true
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

        var isEmpty: Bool { colors.isEmpty && names.isEmpty && moves.isEmpty }
    }

    var rack = Area()
    var patterns = Area()
    var mixer = Area()
    var playlist = Area()

    var isEmpty: Bool { rack.isEmpty && patterns.isEmpty && mixer.isEmpty && playlist.isEmpty }

    /// `families` et `kinds` : ce qu'est chaque son du Channel rack (index du canal), modifiable dans l'aperçu.
    static func make(_ result: OrganizerResult, families: [Int: SoundFamily], kinds: [Int: SoundKind],
                     styles: [SoundFamily: FamilyStyle], options: OrganizerOptions = OrganizerOptions()) -> OrganizerPlan {
        func verdict(_ channel: Int) -> Verdict? {
            families[channel].map { Verdict(family: $0, kind: OrganizerApplier.kind(channel, families: families, kinds: kinds)) }
        }
        var plan = OrganizerPlan()

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

        // Patterns : le nom qu'ils ont déjà s'il dit ce qu'ils sont (« kick », « hi hat »), sinon ce qui y joue (un
        // « Drums 1 » qui ne joue que des kicks devient « Kick ») ; renommés s'ils ont encore le nom de FL ou un nom
        // qui dit ce qu'ils sont (un « Intro » garde son nom).
        if options.patterns {
            var verdicts: [Int: Verdict] = [:]
            var renamable = Set<Int>()
            var current: [Int: String] = [:]
            for pattern in result.patterns {
                let heard = result.patternSounds[pattern.index].flatMap { groupVerdict($0.sorted().compactMap(verdict)) }
                verdicts[pattern.index] = named(pattern.name, heard: heard)
                if pattern.hasDefaultName || SoundNames.kind(of: pattern.name) != nil { renamable.insert(pattern.index) }
                current[pattern.index] = pattern.name
            }
            plan.patterns = area(verdicts, order: result.patterns.map(\.index), current: current, styles: styles,
                                 rename: options.rename, renamable: renamable)
        }

        // Mixer : même ordre que le Channel rack.
        if options.mixer {
            plan.mixer = mixerArea(result, verdict: verdict, rackPlace: rackPlace, channelNames: channelNames,
                                   styles: styles, rename: options.rename)
        }

        // Playlist : chaque piste prend ce que jouent ses sons (ou ce qu'elle fait entendre, pour un clip audio) ;
        // renommée si elle a encore le nom de FL ou un nom qui dit déjà ce qu'elle est (« Drums 2 », « kick »).
        if options.playlist {
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
            for track in result.playlist {
                verdicts[track.index] = named(track.name, heard: heard[track.index])
                if track.hasDefaultName || SoundNames.kind(of: track.name) != nil { renamable.insert(track.index) }
                current[track.index] = track.name
            }
            plan.playlist = area(verdicts, order: result.playlist.map(\.index), current: current, styles: styles,
                                 rename: options.rename, renamable: renamable)
        }
        return plan
    }

    /// Ce qu'est un pattern ou une piste : son nom s'il dit précisément ce qu'il est (« kick », « Lead »), sinon ce
    /// qui y joue, sinon son nom général (« Drums 2 »).
    private static func named(_ name: String, heard: Verdict?) -> Verdict? {
        guard let kind = SoundNames.kind(of: name), !kind.isGeneral || heard == nil else { return heard }
        return Verdict(family: kind.family, kind: kind)
    }

    /// Couleurs (dégradé de chaque famille dans l'ordre donné) et noms numérotés dans cet ordre ; un nom déjà porté
    /// n'est pas reposé.
    private static func area(_ verdicts: [Int: Verdict], order: [Int], current: [Int: String],
                             styles: [SoundFamily: FamilyStyle], rename: Bool, renamable: Set<Int>) -> Area {
        var out = Area()
        out.verdicts = verdicts
        out.colors = OrganizerApplier.plannedColors(families: verdicts.mapValues(\.family), styles: styles, order: order)
        if rename {
            out.names = numbered(order.compactMap { i in
                guard renamable.contains(i) else { return nil }
                return verdicts[i]?.baseName.map { (index: i, name: $0) }
            }).filter { current[$0.key] != $0.value }
        }
        return out
    }

    /// Pistes du Mixer reliées à un son (et celles qui en reçoivent les envois) : dans l'ordre du Channel rack, les
    /// pistes reliées par un envoi côte à côte, celle qui reçoit après celles qui lui envoient ; les autres pistes
    /// suivent, dans leur ordre. Une piste avec un seul son prend le nom de ce son ; une piste de groupe (aucun son,
    /// des envois reçus) « <famille> Bus », si elle a encore le nom de FL.
    private static func mixerArea(_ result: OrganizerResult, verdict: (Int) -> Verdict?, rackPlace: [Int: Int],
                                  channelNames: [Int: String], styles: [SoundFamily: FamilyStyle],
                                  rename: Bool) -> Area {
        let last = result.mixer.count - 2                         // la dernière piste est « Current »
        guard last >= 1 else { return Area() }
        var linked: [Int: [Int]] = [:]                          // piste -> sons, dans l'ordre du Channel rack
        for channel in OrganizerSession.sounds(result.channels) where (1...last).contains(channel.mixerTrack) {
            linked[channel.mixerTrack, default: []].append(channel.index)
        }
        for track in linked.keys { linked[track]?.sort { (rackPlace[$0] ?? .max) < (rackPlace[$1] ?? .max) } }
        // Envois entre pistes utiles, et pistes de groupe (qui reçoivent sans avoir de son).
        var sources: [Int: [Int]] = [:]
        for (from, dests) in result.routes where (1...last).contains(from) {
            for d in dests where (1...last).contains(d) && d != from { sources[d, default: []].append(from) }
        }
        var relevant = Set(linked.keys)
        var grew = true
        while grew {
            grew = false
            for (d, froms) in sources where !relevant.contains(d) && froms.contains(where: { relevant.contains($0) }) {
                relevant.insert(d)
                grew = true
            }
        }
        guard !relevant.isEmpty else { return Area() }

        // Clés de rangement : la place du premier son dans le Channel rack ; une piste de groupe juste après la
        // dernière piste qui lui envoie.
        var key: [Int: Double] = [:]
        for (track, sounds) in linked { key[track] = Double(sounds.compactMap { rackPlace[$0] }.min() ?? Int.max / 2) }
        for _ in 0..<relevant.count {                           // groupes de groupes : une passe par niveau
            for track in relevant where linked[track] == nil {
                let fromKeys = (sources[track] ?? []).compactMap { key[$0] }
                if let top = fromKeys.max() { key[track] = top + 0.5 }
            }
        }
        // Ensembles reliés par des envois : chacun d'un bloc, rangés par leur plus petite clé.
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
        let sortKey = { (t: Int) -> (Double, Int) in (key[t] ?? Double(Int.max / 2), t) }
        let layout = blocks.values
            .map { $0.sorted { sortKey($0) < sortKey($1) } }
            .sorted { sortKey($0[0]) < sortKey($1[0]) }
            .flatMap { $0 }
        let span = relevant.max() ?? 0
        let current = Array(1...span)
        let target = layout + current.filter { !relevant.contains($0) }

        var out = Area()
        out.moves = RegroupPlan.moves(from: current, to: target)
        out.final = target
        // Ce qu'est chaque piste : ses sons, ou ceux des pistes qui lui envoient.
        for track in layout {
            if let sounds = linked[track] {
                if let v = groupVerdict(sounds.compactMap(verdict)) { out.verdicts[track] = v }
            } else if let v = groupVerdict((sources[track] ?? []).compactMap { out.verdicts[$0] }) {
                out.verdicts[track] = Verdict(family: v.family)
            }
        }
        out.colors = OrganizerApplier.plannedColors(families: out.verdicts.mapValues(\.family), styles: styles,
                                                    order: target)
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
                    } else if result.mixer.first(where: { $0.index == track })?.hasDefaultName ?? false {
                        bases.append((track, String(localized: "\(base) Bus")))
                    }
                }
            }
            out.names.merge(numbered(bases, taken: taken)) { a, _ in a }
            var current: [Int: String] = [:]
            for track in result.mixer { current[track.index] = track.name }
            out.names = out.names.filter { current[$0.key] != $0.value }
        }
        return out
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
