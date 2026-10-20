// Organiser : réglage de chaque famille (une couleur ou un dégradé, une icône), plan de regroupement du Channel rack,
// application de tout le plan dans FL (OrganizerPlan) et « Revenir comme avant ». Le plan, les couleurs et les noms
// sont purs (testés) ; l'application passe par OrganizerLink (couleurs, noms, sélection, page devant, vérification)
// et par des touches envoyées à FL seul pour déplacer un élément : ⌥↑ remonte un canal du Channel rack, ⌥← une piste
// du Mixer. FL ne permet pas de déplacer les pistes de la Playlist ni les patterns depuis un script : ils gardent leur
// place.
import Foundation

/// Réglage d'une famille, gardé dans les préférences.
struct FamilyStyle: Codable, Equatable {
    var color: RGBColor
    /// Dégradé : de `color` à `fade`, réparti sur les sons de la famille dans leur ordre final.
    var fade: RGBColor?
    var icon: FLIcon?

    init(color: RGBColor, fade: RGBColor? = nil, icon: FLIcon? = nil) {
        self.color = color
        self.fade = fade
        self.icon = icon
    }

    /// Couleur de chaque son de la famille, dans l'ordre (même arrondi que l'opération 8 du script).
    func colors(count: Int) -> [RGBColor] {
        guard count > 0 else { return [] }
        guard let fade, count > 1 else { return Array(repeating: color, count: count) }
        return (0..<count).map { color.lerp(fade, Double($0) / Double(count - 1)) }
    }

    private enum CodingKeys: String, CodingKey { case color, fade, icon }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let hex = try c.decode(String.self, forKey: .color)
        guard let color = RGBColor(hex: hex) else {
            throw DecodingError.dataCorruptedError(forKey: .color, in: c, debugDescription: "couleur invalide")
        }
        self.color = color
        fade = try c.decodeIfPresent(String.self, forKey: .fade).flatMap { RGBColor(hex: $0) }
        icon = try c.decodeIfPresent(String.self, forKey: .icon).flatMap { FLIcon(code: $0) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(color.hex, forKey: .color)
        try c.encodeIfPresent(fade?.hex, forKey: .fade)
        try c.encodeIfPresent(icon?.code, forKey: .icon)
    }
}

/// Réglages des familles (préférence `organize.families`) ; valeurs de départ de la conception.
enum FamilyStyles {
    static let key = "organize.families"

    static let initial: [SoundFamily: FamilyStyle] = [
        .drums: FamilyStyle(color: RGBColor(r: 0xE0, g: 0x45, b: 0x3A)),
        .bass: FamilyStyle(color: RGBColor(r: 0x8E, g: 0x5B, b: 0xE8)),
        .melody: FamilyStyle(color: RGBColor(r: 0x3F, g: 0xA7, b: 0xE0)),
        .vocals: FamilyStyle(color: RGBColor(r: 0xF2, g: 0xA9, b: 0x3B)),
        .fx: FamilyStyle(color: RGBColor(r: 0x4F, g: 0xC4, b: 0x8E)),
        .unsure: FamilyStyle(color: RGBColor(r: 0x8A, g: 0x8F, b: 0x98)),
    ]

    /// Les réglages gardés ; une famille absente prend sa valeur de départ (tout illisible → valeurs de départ).
    static func load(from defaults: UserDefaults = .standard) -> [SoundFamily: FamilyStyle] {
        var out = initial
        guard let data = defaults.data(forKey: key),
              let saved = try? JSONDecoder().decode([String: FamilyStyle].self, from: data) else { return out }
        for (name, style) in saved {
            if let family = SoundFamily(rawValue: name) { out[family] = style }
        }
        return out
    }

    static func save(_ styles: [SoundFamily: FamilyStyle], to defaults: UserDefaults = .standard) {
        var named: [String: FamilyStyle] = [:]
        for (family, style) in styles { named[family.rawValue] = style }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        if let data = try? encoder.encode(named) { defaults.set(data, forKey: key) }
    }
}

/// Une remontée : le canal à la place `from` monte de `up` places (⌥↑ × up).
struct Move: Equatable {
    let from: Int
    let up: Int
}

enum RegroupPlan {
    /// Tri stable par famille (ordre des familles ; canaux non écoutés, layers et automations, à la fin), et dans une
    /// famille par ce qu'est le son (`kinds`, même ordre que `order` : les Kick ensemble, puis les Snare… ; les sons
    /// qui ne disent rien après). `final[p]` est l'index d'origine du canal qui finit à la place p. Au plus
    /// n × (n − 1) / 2 pas.
    static func make(order: [SoundFamily?], kinds: [SoundKind?] = []) -> (moves: [Move], final: [Int]) {
        let rank: [Int] = order.map { $0?.rank ?? SoundFamily.order.count }
        let sub: [Int] = order.indices.map { i -> Int in
            guard i < kinds.count, let kind = kinds[i], kind.family == order[i] else { return SoundKind.allCases.count }
            return kind.rank
        }
        let final = Array(order.indices).sorted { a, b in
            if rank[a] != rank[b] { return rank[a] < rank[b] }
            if sub[a] != sub[b] { return sub[a] < sub[b] }
            return a < b
        }
        return (moves(from: Array(order.indices), to: final), final)
    }

    /// Remontées qui ramènent la disposition `final` (place → index d'origine) dans l'ordre d'origine.
    static func back(final: [Int]) -> [Move] {
        moves(from: final, to: final.sorted())
    }

    /// Chaque élément de `target`, dans l'ordre, est remonté à sa place (tri par insertion).
    static func moves(from current: [Int], to target: [Int]) -> [Move] {
        var arrangement = current
        var out: [Move] = []
        for (place, id) in target.enumerated() {
            guard let at = arrangement.firstIndex(of: id), at > place else { continue }
            out.append(Move(from: at, up: at - place))
            arrangement.remove(at: at)
            arrangement.insert(id, at: place)
        }
        return out
    }

    /// Disposition après une remontée (sans effet hors limites).
    static func applying(_ move: Move, to arrangement: [Int]) -> [Int] {
        guard move.up > 0, arrangement.indices.contains(move.from), move.from - move.up >= 0 else { return arrangement }
        var out = arrangement
        let id = out.remove(at: move.from)
        out.insert(id, at: move.from - move.up)
        return out
    }
}

/// Ce qu'il faut pour « Revenir comme avant » dans une page de FL.
struct AreaSnapshot: Equatable {
    /// Couleur et nom d'origine de chaque élément touché, par index d'origine (Mixer : numéro de la piste).
    var colors: [Int: RGBColor] = [:]
    var names: [Int: String] = [:]
    /// Place → index d'origine, après ce qui a déjà été fait (Mixer : place 0 = piste 1, numéros des pistes) ; vide
    /// si rien ne bouge.
    var arrangement: [Int] = []
}

/// Ce qu'il faut pour « Revenir comme avant » : chaque page touchée, jusqu'à là où l'application s'est arrêtée.
struct OrganizerSnapshot: Equatable {
    var rack: AreaSnapshot?
    var patterns: AreaSnapshot?
    var mixer: AreaSnapshot?
    var playlist: AreaSnapshot?

    var isEmpty: Bool { rack == nil && patterns == nil && mixer == nil && playlist == nil }
}

struct ApplyOutcome: Equatable {
    var snapshot: OrganizerSnapshot
    /// nil si tout a été fait et vérifié.
    var error: OrganizerError?
}

final class OrganizerApplier {
    private let link: OrganizerLink
    private let moveUp: (Int) -> Int
    private let moveLeft: (Int) -> Int
    private let placeIcon: (FLIcon) -> OrganizerError?

    /// `moveUp(n)` envoie ⌥↑ n fois à FL seul (Channel rack devant), `moveLeft(n)` ⌥← (Mixer devant) ; chacun
    /// renvoie le nombre de pas faits. `placeIcon` pose une icône sur l'élément sélectionné par la fenêtre de FL
    /// (F2) ; nil si c'est fait.
    init(link: OrganizerLink, moveUp: @escaping (Int) -> Int, moveLeft: @escaping (Int) -> Int = { _ in 0 },
         placeIcon: @escaping (FLIcon) -> OrganizerError? = { _ in nil }) {
        self.link = link
        self.moveUp = moveUp
        self.moveLeft = moveLeft
        self.placeIcon = placeIcon
    }

    /// Ce qu'est chaque son classé (par index du canal), quand c'est connu (Kick, 808…).
    static func kinds(of result: OrganizerResult) -> [Int: SoundKind] {
        var out: [Int: SoundKind] = [:]
        for item in result.items {
            if let kind = item.kind { out[item.index] = kind }
        }
        return out
    }

    /// Famille de chaque son classé (par index du canal).
    static func families(of result: OrganizerResult) -> [Int: SoundFamily] {
        var out: [Int: SoundFamily] = [:]
        for item in result.items { out[item.index] = item.family }
        return out
    }

    /// Ce qu'est l'élément s'il va avec sa famille (une famille changée dans l'aperçu fait oublier l'ancien : un
    /// « Kick » mis en Basse s'appelle « Basse »).
    static func kind(_ index: Int, families: [Int: SoundFamily], kinds: [Int: SoundKind]) -> SoundKind? {
        guard let kind = kinds[index], kind.family == families[index] else { return nil }
        return kind
    }

    /// Plan de regroupement du Channel rack : par famille, puis par ce qu'est chaque son.
    static func rackPlan(_ channels: [ChannelInfo], families: [Int: SoundFamily],
                         kinds: [Int: SoundKind]) -> (moves: [Move], final: [Int]) {
        RegroupPlan.make(order: channels.map { families[$0.index] },
                         kinds: channels.map { Self.kind($0.index, families: families, kinds: kinds) })
    }

    /// Icône de chaque élément : celle de sa famille ; aucune si la famille n'en a pas.
    static func plannedIcons(families: [Int: SoundFamily], styles: [SoundFamily: FamilyStyle]) -> [Int: FLIcon] {
        var out: [Int: FLIcon] = [:]
        for (index, family) in families {
            if let icon = (styles[family] ?? FamilyStyles.initial[family])?.icon { out[index] = icon }
        }
        return out
    }

    /// Couleur prévue de chaque élément (par index d'origine), famille par famille dans l'ordre `order`.
    static func plannedColors(families: [Int: SoundFamily], styles: [SoundFamily: FamilyStyle],
                              order: [Int]) -> [Int: RGBColor] {
        var out: [Int: RGBColor] = [:]
        for family in SoundFamily.order {
            guard let style = styles[family] ?? FamilyStyles.initial[family] else { continue }
            let members = order.filter { families[$0] == family }
            for (index, color) in zip(members, style.colors(count: members.count)) { out[index] = color }
        }
        return out
    }

    private static func pairs(_ colors: [Int: RGBColor]) -> [(index: Int, color: RGBColor)] {
        colors.keys.sorted().compactMap { index in colors[index].map { (index: index, color: $0) } }
    }

    private static func namePairs(_ names: [Int: String]) -> [(index: Int, name: String)] {
        names.keys.sorted().compactMap { index in names[index].map { (index: index, name: $0) } }
    }

    private static func failure(_ error: Error) -> OrganizerError {
        (error as? OrganizerError)
            ?? .failed(String(localized: "Organiser : étape impossible (\(String(describing: type(of: error))))."))
    }

    /// Tout le plan, page par page : Channel rack, patterns, Mixer, Playlist. Une page que FL n'a pas toute prise
    /// (vérifiée en relisant) n'arrête pas les suivantes : elle est dite à la fin (`mismatch`) ; une erreur arrête là.
    /// Le mémo de chaque page est posé avant d'y toucher : « Revenir comme avant » défait ce qui a été fait.
    func apply(_ plan: OrganizerPlan, result: OrganizerResult, styles: [SoundFamily: FamilyStyle]) -> ApplyOutcome {
        var outcome = ApplyOutcome(snapshot: OrganizerSnapshot())
        var verified = true
        do {
            if !plan.rack.isEmpty {
                outcome.snapshot.rack = AreaSnapshot()
                let ok = try applyRack(plan.rack, result, styles, &outcome.snapshot.rack!)
                if !ok { verified = false }
            }
            if !plan.patterns.isEmpty {
                outcome.snapshot.patterns = AreaSnapshot()
                let ok = try applyPatterns(plan.patterns, result, &outcome.snapshot.patterns!)
                if !ok { verified = false }
            }
            if !plan.mixer.isEmpty {
                outcome.snapshot.mixer = AreaSnapshot()
                let ok = try applyMixer(plan.mixer, result, styles, &outcome.snapshot.mixer!)
                if !ok { verified = false }
            }
            if !plan.playlist.isEmpty {
                outcome.snapshot.playlist = AreaSnapshot()
                let ok = try applyPlaylist(plan.playlist, result, &outcome.snapshot.playlist!)
                if !ok { verified = false }
            }
            if !verified { outcome.error = .mismatch }
        } catch {
            outcome.error = Self.failure(error)
        }
        return outcome
    }

    /// Channel rack : couleurs et noms (places d'origine), remontées, relecture de l'ordre et des couleurs, icônes.
    private func applyRack(_ area: OrganizerPlan.Area, _ result: OrganizerResult, _ styles: [SoundFamily: FamilyStyle],
                           _ snap: inout AreaSnapshot) throws -> Bool {
        let channels = result.channels.sorted { $0.index < $1.index }
        for channel in channels {
            if area.colors[channel.index] != nil { snap.colors[channel.index] = channel.color }
            if area.names[channel.index] != nil { snap.names[channel.index] = channel.name }
        }
        snap.arrangement = Array(channels.indices)
        let icons = Self.plannedIcons(families: area.verdicts.mapValues { $0.family }, styles: styles)
        if !area.moves.isEmpty || !icons.isEmpty { try link.show(.channelRack) }
        try link.setColors(.channels, Self.pairs(area.colors))
        try link.setNames(.channels, Self.namePairs(area.names))
        // Noms tels qu'ils sont maintenant dans FL, par index d'origine : pour relire l'ordre.
        let names = channels.map { area.names[$0.index] ?? $0.name }
        do {
            try move(area.moves, &snap.arrangement, page: .channelRack, kind: .channels, offset: 0, key: moveUp)
        } catch {
            // Arrêt en route : l'ordre relu dans FL, pour que « Revenir comme avant » remette chaque chose à sa place.
            if let listed = try? link.listChannels(),
               let seen = Self.arrangement(names: listed.map { $0.name }, original: names) {
                snap.arrangement = seen
            }
            throw error
        }
        let listed = try link.listChannels()
        // L'ordre que FL montre vraiment (une touche ⌥↑ perdue) : « Revenir comme avant » remet alors chaque couleur
        // sur son son, et le regroupement manqué est dit.
        var regrouped = true
        if let seen = Self.arrangement(names: listed.map { $0.name }, original: names) {
            regrouped = seen == snap.arrangement
            snap.arrangement = seen
        }
        let now: [RGBColor?] = listed.map { $0.color }
        let expected: [RGBColor?] = snap.arrangement.map { area.colors[$0] ?? channels[$0].color }
        guard regrouped, now == expected else { return false }
        let arrangement = snap.arrangement
        try placeIcons(icons, kind: .channels) { arrangement.firstIndex(of: $0) }
        return true
    }

    /// Patterns : couleurs et noms, puis relecture.
    private func applyPatterns(_ area: OrganizerPlan.Area, _ result: OrganizerResult,
                               _ snap: inout AreaSnapshot) throws -> Bool {
        for pattern in result.patterns {
            if area.colors[pattern.index] != nil { snap.colors[pattern.index] = pattern.color }
            if area.names[pattern.index] != nil { snap.names[pattern.index] = pattern.name }
        }
        try link.setColors(.patterns, Self.pairs(area.colors))
        try link.setNames(.patterns, Self.namePairs(area.names))
        var colors: [Int: RGBColor] = [:]
        var names: [Int: String] = [:]
        for pattern in try link.listPatterns() {
            colors[pattern.index] = pattern.color
            names[pattern.index] = pattern.name
        }
        return area.colors.allSatisfy { colors[$0.key] == $0.value } && Self.namesMatch(area.names, names)
    }

    /// Mixer : couleurs et noms (pistes d'origine), puis Mixer devant et chaque piste décalée à gauche (⌥←),
    /// relecture de l'ordre, des couleurs et des noms, icônes. Le Master ne bouge jamais.
    private func applyMixer(_ area: OrganizerPlan.Area, _ result: OrganizerResult, _ styles: [SoundFamily: FamilyStyle],
                            _ snap: inout AreaSnapshot) throws -> Bool {
        var byIndex: [Int: MixerTrackInfo] = [:]
        for track in result.mixer { byIndex[track.index] = track }
        for index in area.colors.keys { if let t = byIndex[index] { snap.colors[index] = t.color } }
        for index in area.names.keys { if let t = byIndex[index] { snap.names[index] = t.name } }
        let span = area.final.count                                   // pistes 1…span
        snap.arrangement = span > 0 ? Array(1...span) : []
        try link.setColors(.mixer, Self.pairs(area.colors))
        try link.setNames(.mixer, Self.namePairs(area.names))
        // Noms tels qu'ils sont maintenant dans FL, par piste d'origine (pistes 1…span) : pour relire l'ordre.
        let names: [String] = span > 0 ? (1...span).map { area.names[$0] ?? byIndex[$0]?.name ?? "" } : []
        let icons = Self.plannedIcons(families: area.verdicts.mapValues { $0.family }, styles: styles)
        if !area.moves.isEmpty || !icons.isEmpty { try link.show(.mixer) }
        do {
            try move(area.moves, &snap.arrangement, page: .mixer, kind: .mixer, offset: 1, key: moveLeft)
        } catch {
            if span > 0, let listed = try? link.listMixer(),
               let seen = Self.arrangement(names: Self.tracks(listed, 1...span).map { $0.name }, original: names) {
                snap.arrangement = seen.map { $0 + 1 }
            }
            throw error
        }
        let listed = try link.listMixer()
        var now: [Int: MixerTrackInfo] = [:]
        for track in listed { now[track.index] = track }
        var regrouped = true
        if span > 0, let seen = Self.arrangement(names: Self.tracks(listed, 1...span).map { $0.name }, original: names) {
            let tracks = seen.map { $0 + 1 }
            regrouped = tracks == snap.arrangement
            snap.arrangement = tracks
        }
        // Chaque piste d'origine est maintenant à la place où l'ordre relu la met.
        let arrangement = snap.arrangement
        func place(_ original: Int) -> Int {
            guard let at = arrangement.firstIndex(of: original) else { return original }
            return at + 1
        }
        let colorsOK = area.colors.allSatisfy { now[place($0.key)]?.color == $0.value }
        var read: [Int: String] = [:]
        for index in area.names.keys { if let t = now[place(index)] { read[index] = t.name } }
        guard regrouped, colorsOK, Self.namesMatch(area.names, read) else { return false }
        try placeIcons(icons, kind: .mixer) { place($0) }
        return true
    }

    /// Pistes du Mixer de cette plage, dans l'ordre.
    private static func tracks(_ listed: [MixerTrackInfo], _ range: ClosedRange<Int>) -> [MixerTrackInfo] {
        listed.filter { range.contains($0.index) }.sorted { $0.index < $1.index }
    }

    /// Playlist : couleurs et noms, puis vérification sur les pistes touchées (lues jusqu'à la dernière).
    private func applyPlaylist(_ area: OrganizerPlan.Area, _ result: OrganizerResult,
                               _ snap: inout AreaSnapshot) throws -> Bool {
        for track in result.playlist {
            if area.colors[track.index] != nil { snap.colors[track.index] = track.color }
            // Nom de FL lu vide : remis en « Track n » (un nom vide ne peut pas être posé).
            if area.names[track.index] != nil {
                snap.names[track.index] = track.name.isEmpty ? "Track \(track.index + 1)" : track.name
            }
        }
        try link.setColors(.playlist, Self.pairs(area.colors))
        try link.setNames(.playlist, Self.namePairs(area.names))
        let last = max(area.colors.keys.max() ?? -1, area.names.keys.max() ?? -1)
        guard last >= 0 else { return true }
        var colors: [Int: RGBColor] = [:]
        var names: [Int: String] = [:]
        for track in try link.listPlaylist(limit: last + 1) {
            colors[track.index] = track.color
            names[track.index] = track.name
        }
        return area.colors.allSatisfy { colors[$0.key] == $0.value } && Self.namesMatch(area.names, names)
    }

    /// Noms comparés tels que le script les lit (coupés) : le nom relu est le début du nom posé.
    static func namesMatch(_ sent: [Int: String], _ read: [Int: String]) -> Bool {
        sent.allSatisfy { item in
            guard let got = read[item.key], let bytes = OrganizerPayload.nameUTF8(item.value) else { return false }
            let readBytes = Array(got.utf8)
            return !readBytes.isEmpty && Array(bytes.prefix(readBytes.count)) == readBytes
        }
    }

    /// Icônes en dernier (FL ne dit pas lesquelles étaient là : « Revenir comme avant » ne les retire pas). Chaque
    /// élément est sélectionné seul, puis la pose passe par la fenêtre de FL ; la page doit rester devant.
    private func placeIcons(_ icons: [Int: FLIcon], kind: ItemKind, place: (Int) -> Int?) throws {
        let page: FLWindow = kind == .channels ? .channelRack : .mixer
        for index in icons.keys.sorted() {
            guard let icon = icons[index], let at = place(index) else { continue }
            guard link.window == page else { throw OrganizerError.interrupted }
            try link.selectOne(kind, at)
            if let error = placeIcon(icon) { throw error }
        }
    }

    /// Pur (testé) : place → index d'origine, d'après les noms relus dans FL ; nil si un nom se répète ou ne
    /// correspond pas (la disposition supposée reste alors).
    static func arrangement(names now: [String], original: [String]) -> [Int]? {
        guard now.count == original.count, Set(original).count == original.count else { return nil }
        var at: [String: Int] = [:]
        for (index, name) in original.enumerated() { at[name] = index }
        let out = now.compactMap { at[$0] }
        return out.count == now.count && Set(out).count == out.count ? out : nil
    }

    /// Déplacements un par un (élément sélectionné puis touches) ; la disposition suit ce qui a vraiment été fait.
    /// `offset` : index FL de la place 0 (Mixer : 1, le Master ne bouge pas).
    private func move(_ moves: [Move], _ arrangement: inout [Int], page: FLWindow, kind: ItemKind, offset: Int,
                      key: (Int) -> Int) throws {
        for step in moves {
            guard link.window == page else { throw OrganizerError.interrupted }
            try link.selectOne(kind, step.from + offset)
            let done = key(step.up)
            arrangement = RegroupPlan.applying(Move(from: step.from, up: done), to: arrangement)
            if done < step.up { throw OrganizerError.interrupted }
        }
    }

    /// « Revenir comme avant » : Playlist, Mixer, patterns puis Channel rack (couleurs et noms d'origine remis sur la
    /// place actuelle de chaque élément, puis l'ordre d'origine). Chaque page remise sort du mémo : un retour
    /// interrompu reprend là où il s'est arrêté.
    func undo(_ snapshot: OrganizerSnapshot) -> ApplyOutcome {
        var outcome = ApplyOutcome(snapshot: snapshot)
        do {
            if let s = snapshot.playlist {
                try link.setColors(.playlist, Self.pairs(s.colors))
                try link.setNames(.playlist, Self.namePairs(s.names))
                outcome.snapshot.playlist = nil
            }
            if snapshot.mixer != nil {
                try undoArranged(&outcome.snapshot.mixer!, kind: .mixer, page: .mixer, offset: 1, key: moveLeft)
                outcome.snapshot.mixer = nil
            }
            if let s = snapshot.patterns {
                try link.setColors(.patterns, Self.pairs(s.colors))
                try link.setNames(.patterns, Self.namePairs(s.names))
                outcome.snapshot.patterns = nil
            }
            if snapshot.rack != nil {
                try undoArranged(&outcome.snapshot.rack!, kind: .channels, page: .channelRack, offset: 0, key: moveUp)
                outcome.snapshot.rack = nil
            }
        } catch {
            outcome.error = Self.failure(error)
        }
        return outcome
    }

    /// Couleurs et noms d'origine sur la place actuelle de chaque élément, puis déplacements vers l'ordre d'origine.
    /// `offset` : index FL de la place 0 (Mixer : 1, et la disposition y est en numéros de pistes).
    private func undoArranged(_ s: inout AreaSnapshot, kind: ItemKind, page: FLWindow, offset: Int,
                              key: (Int) -> Int) throws {
        let arrangement = s.arrangement
        func current(_ original: Int) -> Int {
            guard let place = arrangement.firstIndex(of: original) else { return original }
            return place + offset
        }
        var colors: [Int: RGBColor] = [:]
        for (original, color) in s.colors { colors[current(original)] = color }
        var names: [Int: String] = [:]
        for (original, name) in s.names { names[current(original)] = name }
        try link.setColors(kind, Self.pairs(colors))
        try link.setNames(kind, Self.namePairs(names))
        s.colors = [:]
        s.names = [:]
        // Places (0 = premier élément déplaçable) → index d'origine, ramenés à la même base pour le plan de retour.
        var places = arrangement.map { $0 - offset }
        let back = RegroupPlan.back(final: places)
        guard !back.isEmpty else { return }
        try link.show(page)
        defer { s.arrangement = places.map { $0 + offset } }
        try move(back, &places, page: page, kind: kind, offset: offset, key: key)
    }
}
