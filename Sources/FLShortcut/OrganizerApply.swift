// Organiser : réglage de chaque famille (une couleur ou un dégradé, une icône), plan de regroupement du Channel rack,
// application dans FL et « Revenir comme avant ». Le plan et les couleurs sont purs (testés) ; l'application passe
// par OrganizerLink (couleurs, sélection, vérification) et par ⌥↑ envoyé à FL seul pour remonter un canal.
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
    /// Tri stable par famille (ordre des familles ; canaux non écoutés, layers et automations, à la fin). `final[p]` est
    /// l'index d'origine du canal qui finit à la place p. Au plus n × (n − 1) / 2 pas.
    static func make(order: [SoundFamily?]) -> (moves: [Move], final: [Int]) {
        let rank: [Int] = order.map { $0?.rank ?? SoundFamily.order.count }
        let final = Array(order.indices).sorted { rank[$0] != rank[$1] ? rank[$0] < rank[$1] : $0 < $1 }
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

/// Ce qu'il faut pour « Revenir comme avant ».
struct OrganizerSnapshot: Equatable {
    let kind: ItemKind
    /// Couleur d'origine de chaque élément (par index d'origine).
    let colors: [Int: RGBColor]
    /// Channel rack : place → index d'origine, après ce qui a déjà été fait ; vide pour le Mixer.
    var arrangement: [Int]
}

struct ApplyOutcome: Equatable {
    var snapshot: OrganizerSnapshot
    /// nil si tout a été fait et vérifié.
    var error: OrganizerError?
}

final class OrganizerApplier {
    private let link: OrganizerLink
    private let moveUp: (Int) -> Int
    private let placeIcon: (FLIcon) -> OrganizerError?

    /// `moveUp(n)` envoie ⌥↑ n fois à FL seul (15 ms entre deux, Channel rack devant à chaque pas) et renvoie le
    /// nombre de pas faits. `placeIcon` pose une icône sur l'élément sélectionné par la fenêtre de FL (F2) ; nil si
    /// c'est fait.
    init(link: OrganizerLink, moveUp: @escaping (Int) -> Int,
         placeIcon: @escaping (FLIcon) -> OrganizerError? = { _ in nil }) {
        self.link = link
        self.moveUp = moveUp
        self.placeIcon = placeIcon
    }

    /// Icône de chaque élément (par index d'origine) : celle de sa famille ; aucune si la famille n'en a pas.
    static func plannedIcons(families: [Int: SoundFamily], styles: [SoundFamily: FamilyStyle]) -> [Int: FLIcon] {
        var out: [Int: FLIcon] = [:]
        for (index, family) in families {
            if let icon = (styles[family] ?? FamilyStyles.initial[family])?.icon { out[index] = icon }
        }
        return out
    }

    /// Icônes en dernier (FL ne dit pas lesquelles étaient là : « Revenir comme avant » ne les retire pas). Chaque
    /// élément est sélectionné seul, puis la pose passe par la fenêtre de FL ; la page doit rester devant.
    private func placeIcons(_ icons: [Int: FLIcon], kind: ItemKind, place: (Int) -> Int?) throws {
        let page: FLWindow = kind == .channels ? .channelRack : .mixer
        for index in icons.keys.sorted() {
            guard let icon = icons[index], let at = place(index) else { continue }
            guard link.window == page else {
                throw kind == .channels ? OrganizerError.interrupted
                                        : OrganizerError.failed("Le Mixer n'est plus devant : icônes non posées.")
            }
            try link.selectOne(kind, at)
            if let error = placeIcon(icon) { throw error }
        }
    }

    /// Famille de départ de chaque élément à colorer : canaux écoutés ou pistes du Mixer reliées.
    static func families(of result: OrganizerResult) -> [Int: SoundFamily] {
        switch result.page {
        case .channelRack:
            var out: [Int: SoundFamily] = [:]
            for item in result.items { out[item.index] = item.family }
            return out
        case .mixer:
            return result.mixerFamilies
        }
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

    private static func failure(_ error: Error) -> OrganizerError {
        (error as? OrganizerError) ?? .failed("Organiser : étape impossible (\(type(of: error))).")
    }

    func apply(result: OrganizerResult, families: [Int: SoundFamily],
               styles: [SoundFamily: FamilyStyle]) -> ApplyOutcome {
        switch result.page {
        case .mixer: return applyMixer(result, families, styles)
        case .channelRack: return applyRack(result, families, styles)
        }
    }

    private func applyMixer(_ result: OrganizerResult, _ families: [Int: SoundFamily],
                            _ styles: [SoundFamily: FamilyStyle]) -> ApplyOutcome {
        var originals: [Int: RGBColor] = [:]
        for track in result.mixer { originals[track.index] = track.color }
        let colors = Self.plannedColors(families: families, styles: styles, order: result.mixer.map(\.index))
        var outcome = ApplyOutcome(snapshot: OrganizerSnapshot(kind: .mixer, colors: originals, arrangement: []))
        do {
            try link.setColors(.mixer, Self.pairs(colors))
            var now: [Int: RGBColor] = [:]
            for track in try link.listMixer() { now[track.index] = track.color }
            if colors.contains(where: { now[$0.key] != $0.value }) {
                outcome.error = .mismatch
            } else {
                try placeIcons(Self.plannedIcons(families: families, styles: styles), kind: .mixer) { $0 }
            }
        } catch {
            outcome.error = Self.failure(error)
        }
        return outcome
    }

    private func applyRack(_ result: OrganizerResult, _ families: [Int: SoundFamily],
                           _ styles: [SoundFamily: FamilyStyle]) -> ApplyOutcome {
        let channels = result.channels.sorted { $0.index < $1.index }
        var originals: [Int: RGBColor] = [:]
        for channel in channels { originals[channel.index] = channel.color }
        let plan = RegroupPlan.make(order: channels.map { families[$0.index] })
        let colors = Self.plannedColors(families: families, styles: styles, order: plan.final)
        var outcome = ApplyOutcome(snapshot: OrganizerSnapshot(kind: .channels, colors: originals,
                                                               arrangement: Array(channels.indices)))
        do {
            // Couleurs d'abord (les places sont encore celles d'origine), puis les remontées.
            try link.setColors(.channels, Self.pairs(colors))
            try move(plan.moves, &outcome.snapshot.arrangement)
            let now: [RGBColor?] = try link.listChannels().channels.map { $0.color }
            let expected: [RGBColor?] = outcome.snapshot.arrangement.map { colors[$0] ?? originals[$0] }
            if now != expected {
                outcome.error = .mismatch
            } else {
                let arrangement = outcome.snapshot.arrangement
                try placeIcons(Self.plannedIcons(families: families, styles: styles), kind: .channels) {
                    arrangement.firstIndex(of: $0)
                }
            }
        } catch {
            outcome.error = Self.failure(error)
        }
        return outcome
    }

    /// Remontées une par une ; la disposition suit ce qui a vraiment été fait.
    private func move(_ moves: [Move], _ arrangement: inout [Int]) throws {
        for step in moves {
            guard link.window == .channelRack else { throw OrganizerError.interrupted }
            try link.selectOne(.channels, step.from)
            let done = moveUp(step.up)
            arrangement = RegroupPlan.applying(Move(from: step.from, up: done), to: arrangement)
            if done < step.up { throw OrganizerError.interrupted }
        }
    }

    /// « Revenir comme avant » : couleurs d'origine (selon la disposition actuelle), puis ordre d'origine.
    func undo(_ snapshot: OrganizerSnapshot) -> ApplyOutcome {
        var outcome = ApplyOutcome(snapshot: snapshot)
        do {
            switch snapshot.kind {
            case .mixer:
                try link.setColors(.mixer, Self.pairs(snapshot.colors))
            case .channels:
                var byPlace: [Int: RGBColor] = [:]
                for (place, id) in snapshot.arrangement.enumerated() { byPlace[place] = snapshot.colors[id] }
                try link.setColors(.channels, Self.pairs(byPlace))
                try move(RegroupPlan.back(final: snapshot.arrangement), &outcome.snapshot.arrangement)
            }
        } catch {
            outcome.error = Self.failure(error)
        }
        return outcome
    }
}
