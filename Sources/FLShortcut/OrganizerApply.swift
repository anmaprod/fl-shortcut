// Organiser : réglage de chaque famille (une couleur ou un dégradé, une icône), plan de regroupement du Channel rack,
// application de tout le plan dans FL (OrganizerPlan) et « Revenir comme avant ». Le plan, les couleurs et les noms
// sont purs (testés) ; l'application passe par OrganizerLink (couleurs, noms, sélection, page devant, vérification)
// et par ce que ferait l'utilisateur, envoyé à FL seul : ⌥↑ remonte un canal du Channel rack, ⌥← une piste du Mixer,
// ⌥ + Suppr supprime les sons sélectionnés (sons sans aucune note : on ne peut pas les remettre), et le menu d'une
// piste de la Playlist la remonte (« Move up » : FL ne permet pas de la déplacer depuis un script). Les patterns
// gardent leur place.
import Foundation

/// Réglage d'une famille, gardé dans les préférences.
struct FamilyStyle: Codable, Equatable {
    var color: RGBColor
    /// Dégradé : de `color` à `fade`, réparti sur les sons de la famille dans leur ordre final.
    var fade: RGBColor?
    var icon: FLIcon?
    /// La piste du Mixer où commence la famille (« Drums de 27 à 32 », la 808 comprise, demande du propriétaire du
    /// 25/10) ; nil : rangement automatique.
    var mixerStart: Int?

    init(color: RGBColor, fade: RGBColor? = nil, icon: FLIcon? = nil, mixerStart: Int? = nil) {
        self.color = color
        self.fade = fade
        self.icon = icon
        self.mixerStart = mixerStart
    }

    /// Dernière piste du Mixer de FL (125 pistes en plus du Master).
    static let maxMixerTrack = 125

    /// Couleur de chaque son de la famille, dans l'ordre (même arrondi que l'opération 8 du script).
    func colors(count: Int) -> [RGBColor] {
        guard count > 0 else { return [] }
        guard let fade, count > 1 else { return Array(repeating: color, count: count) }
        return (0..<count).map { color.lerp(fade, Double($0) / Double(count - 1)) }
    }

    private enum CodingKeys: String, CodingKey { case color, fade, icon, mixer }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let hex = try c.decode(String.self, forKey: .color)
        guard let color = RGBColor(hex: hex) else {
            throw DecodingError.dataCorruptedError(forKey: .color, in: c, debugDescription: "couleur invalide")
        }
        self.color = color
        fade = try c.decodeIfPresent(String.self, forKey: .fade).flatMap { RGBColor(hex: $0) }
        // « Reset » n'est pas une icône (retour du 31/10 : il retire l'icône dans FL) : une famille sans icône.
        icon = try c.decodeIfPresent(String.self, forKey: .icon).flatMap { FLIcon(code: $0) }.flatMap { $0.isReset ? nil : $0 }
        let start: Int? = try? c.decodeIfPresent(Int.self, forKey: .mixer)
        mixerStart = start.flatMap { (1...Self.maxMixerTrack).contains($0) ? $0 : nil }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(color.hex, forKey: .color)
        try c.encodeIfPresent(fade?.hex, forKey: .fade)
        try c.encodeIfPresent(icon?.code, forKey: .icon)
        try c.encodeIfPresent(mixerStart, forKey: .mixer)
    }
}

/// Réglages des familles (préférence `organize.families`) ; valeurs de départ de la conception.
enum FamilyStyles {
    static let key = "organize.families"

    /// Couleurs de départ (05/11, « des couleurs un peu plus suisse style ») : rouge signal, bleu outremer, jaune,
    /// rose, vert d'eau, gris ; franches, et bien lisibles sur le fond sombre de FL.
    static let initial: [SoundFamily: FamilyStyle] = [
        .drums: FamilyStyle(color: RGBColor(r: 0xFF, g: 0x3B, b: 0x1F)),
        .bass: FamilyStyle(color: RGBColor(r: 0x2F, g: 0x55, b: 0xFF)),
        .melody: FamilyStyle(color: RGBColor(r: 0xFF, g: 0xC4, b: 0x00)),
        .vocals: FamilyStyle(color: RGBColor(r: 0xFF, g: 0x5F, b: 0xA2)),
        .fx: FamilyStyle(color: RGBColor(r: 0x19, g: 0xC3, b: 0xA0)),
        .unsure: FamilyStyle(color: RGBColor(r: 0x8C, g: 0x8C, b: 0x8C)),
    ]

    /// Les couleurs de départ d'avant le 05/11 : gardées telles quelles (jamais choisies), elles prennent les nouvelles.
    static let previous: [SoundFamily: RGBColor] = [
        .drums: RGBColor(r: 0xE0, g: 0x45, b: 0x3A), .bass: RGBColor(r: 0x8E, g: 0x5B, b: 0xE8),
        .melody: RGBColor(r: 0x3F, g: 0xA7, b: 0xE0), .vocals: RGBColor(r: 0xF2, g: 0xA9, b: 0x3B),
        .fx: RGBColor(r: 0x4F, g: 0xC4, b: 0x8E), .unsure: RGBColor(r: 0x8A, g: 0x8F, b: 0x98),
    ]

    /// Couleurs proposées dans « Couleurs de base » (Options de l'Organiser) : la palette suisse de l'app.
    static let palette: [RGBColor] = [
        RGBColor(r: 0xFF, g: 0x3B, b: 0x1F), RGBColor(r: 0xFF, g: 0x8A, b: 0x00), RGBColor(r: 0xFF, g: 0xC4, b: 0x00),
        RGBColor(r: 0x19, g: 0xC3, b: 0xA0), RGBColor(r: 0x00, g: 0xA6, b: 0x51), RGBColor(r: 0x00, g: 0xB5, b: 0xE2),
        RGBColor(r: 0x2F, g: 0x55, b: 0xFF), RGBColor(r: 0xB4, g: 0x4B, b: 0xFF), RGBColor(r: 0xFF, g: 0x5F, b: 0xA2),
        RGBColor(r: 0x8C, g: 0x8C, b: 0x8C),
    ]

    /// Les réglages gardés ; une famille absente prend sa valeur de départ (tout illisible → valeurs de départ).
    static func load(from defaults: UserDefaults = .standard) -> [SoundFamily: FamilyStyle] {
        var out = initial
        guard let data = defaults.data(forKey: key),
              let saved = try? JSONDecoder().decode([String: FamilyStyle].self, from: data) else { return out }
        for (name, style) in saved {
            guard let family = SoundFamily(rawValue: name) else { continue }
            var kept = style
            if kept.fade == nil, kept.color == previous[family], let fresh = initial[family] { kept.color = fresh.color }
            out[family] = kept
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

    static let orderKey = "organize.familyOrder"

    /// L'ordre des familles glissées dans l'aperçu (vide : l'ordre de départ) ; jamais qu'une liste de familles.
    static func loadOrder(from defaults: UserDefaults = .standard) -> [SoundFamily] {
        OrganizerOptions.completeOrder((defaults.stringArray(forKey: orderKey) ?? []).compactMap(SoundFamily.init(rawValue:)))
    }

    static func saveOrder(_ order: [SoundFamily], to defaults: UserDefaults = .standard) {
        defaults.set(order.map(\.rawValue), forKey: orderKey)
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
    static func make(order: [SoundFamily?], kinds: [SoundKind?] = [],
                     familyRank: (SoundFamily) -> Int = { $0.rank }) -> (moves: [Move], final: [Int]) {
        let rank: [Int] = order.map { $0.map(familyRank) ?? Int.max / 2 }
        let sub: [Int] = order.indices.map { i -> Int in
            guard i < kinds.count, let kind = kinds[i], kind.family == order[i] else { return SoundKind.rackOrder.count }
            return kind.rackRank
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
    /// Mixer : envois d'origine des pistes changées (numéros d'origine ; 0 = le Master).
    var routes: [Int: [Int]] = [:]
}

/// Ce qu'il faut pour « Revenir comme avant » : chaque page touchée, jusqu'à là où l'application s'est arrêtée.
struct OrganizerSnapshot: Equatable {
    var rack: AreaSnapshot?
    var patterns: AreaSnapshot?
    var mixer: AreaSnapshot?
    var playlist: AreaSnapshot?
    /// Sons envoyés au Master reliés à une piste : leur piste d'avant (index d'origine du canal).
    var links: [Int: Int]?
    /// Patterns descendus chacun sur sa piste de la Playlist, dans l'ordre (remontés à l'envers).
    var splits: [PlaylistSplit]?
    /// Clips de la Playlist réunis sur la piste de leur son, dans l'ordre (remis à l'envers).
    var clipMoves: [ClipMove]?
    /// Rangé dans une copie du projet : l'original, que « Revenir comme avant » rouvre dans FL (il n'a pas bougé).
    var original: URL?

    var isEmpty: Bool {
        rack == nil && patterns == nil && mixer == nil && playlist == nil && links == nil && splits == nil
            && clipMoves == nil && original == nil
    }
}

struct ApplyOutcome: Equatable {
    var snapshot: OrganizerSnapshot
    /// nil si tout a été fait et vérifié.
    var error: OrganizerError?
    /// Sons sans aucune note supprimés ; ou laissés là, FL ne les ayant pas supprimés (ils restent sélectionnés).
    var deleted = 0
    var notDeleted = 0
    /// Pistes de la Playlist pas rangées (FL n'a pas montré leur menu) : noms et couleurs sont posés.
    var playlistUnordered = false
    /// Channel rack ou Mixer dont FL n'a pas laissé finir le rangement (page qui ne restait pas devant) : couleurs et
    /// noms y sont posés, et tout le reste (autres pages, icônes) a continué (12/11).
    var unordered: [FLWindow] = []
    /// Patterns descendus chacun sur sa piste ; d'autres prévus, que FL n'a pas laissé descendre (pistes qui gardent
    /// deux sons).
    var split = 0
    var playlistMixed = false
    /// Clips de la Playlist réunis sur la piste de leur son (lus dans la fenêtre de FL) ; ceux qui n'ont pas pu y aller.
    var reunited = 0
    var clipsLeft = 0
    /// Icônes pas posées (la raison, sans aucun nom) : tout le reste est fait.
    var iconsMissed: String?
    /// La copie rangée ouverte dans FL ; FL ne l'a pas enregistrée à la fin (à faire soi-même : ⌘S).
    var copy: URL?
    var copyNotSaved = false
    /// Numéros d'icône de FL appris dans la copie enregistrée (code de la grille → numéro) : la Playlist les reçoit
    /// au rangement suivant (07/11 au soir).
    var learnedIconIDs: [String: UInt32] = [:]
    /// Pareil pour le Mixer, appris à part (12/11 : ses numéros peuvent différer de ceux du Channel rack).
    var learnedMixerIconIDs: [String: UInt32] = [:]
    /// Étapes de l'application en mots et nombres (diagnostic : jamais un nom).
    var trace: [String] = []
}

extension OrganizerResult {
    /// Pur (testé) : le projet une fois ces canaux supprimés de FL (les suivants remontent d'autant), et l'index de
    /// chaque canal gardé, avant → maintenant. Les pistes du Mixer que seuls eux utilisaient vont dans `freed`.
    func removing(_ deleted: Set<Int>) -> (result: OrganizerResult, map: [Int: Int]) {
        var map: [Int: Int] = [:]
        var kept: [ChannelInfo] = []
        for c in channels.sorted(by: { $0.index < $1.index }) where !deleted.contains(c.index) {
            map[c.index] = kept.count
            kept.append(ChannelInfo(index: kept.count, type: c.type, mixerTrack: c.mixerTrack, color: c.color, name: c.name))
        }
        var out = remapped(map, channels: kept)
        let keptTracks = Set(kept.map(\.mixerTrack))
        out.freed = freed.union(channels.filter { deleted.contains($0.index) }.map(\.mixerTrack))
            .filter { $0 > 0 && !keptTracks.contains($0) }
        return (out, map)
    }

    /// Pur (testé) : le projet une fois ses canaux rangés dans l'ordre `order` (place → index d'avant, chaque canal une
    /// fois) dans la copie (13/11), et l'index de chaque canal, avant → maintenant. nil si `order` n'est pas un ordre
    /// de tous les canaux.
    func reordering(_ order: [Int]) -> (result: OrganizerResult, map: [Int: Int])? {
        let byIndex = Dictionary(channels.map { ($0.index, $0) }, uniquingKeysWith: { first, _ in first })
        guard order.count == channels.count, Set(order) == Set(byIndex.keys) else { return nil }
        var map: [Int: Int] = [:]
        var placed: [ChannelInfo] = []
        for (place, index) in order.enumerated() {
            guard let c = byIndex[index] else { return nil }
            map[index] = place
            placed.append(ChannelInfo(index: place, type: c.type, mixerTrack: c.mixerTrack, color: c.color, name: c.name))
        }
        var out = remapped(map, channels: placed)
        out.freed = freed
        return (out, map)
    }

    /// Les mêmes sons sous leur nouvel index (`map` : avant → maintenant ; un son absent de `map` est retiré).
    private func remapped(_ map: [Int: Int], channels kept: [ChannelInfo]) -> OrganizerResult {
        func moved(_ set: Set<Int>) -> Set<Int> { Set(set.compactMap { map[$0] }) }
        let items = self.items.compactMap { item -> OrganizerItem? in
            guard let now = map[item.index] else { return nil }
            return OrganizerItem(index: now, name: item.name, family: item.family, confidence: item.confidence,
                                 testNotes: item.testNotes, mixerTrack: item.mixerTrack, color: item.color,
                                 kind: item.kind, byName: item.byName)
        }
        var out = OrganizerResult(channels: kept, items: items)
        out.patterns = patterns
        out.patternSounds = patternSounds.mapValues(moved).filter { !$0.value.isEmpty }
        out.mixer = mixer
        out.routes = routes
        out.playlist = playlist
        out.trackSounds = trackSounds.mapValues(moved).filter { !$0.value.isEmpty }
        out.trackItems = trackItems
        out.unused = moved(unused)
        for (channel, position) in soundAt { if let now = map[channel] { out.soundAt[now] = position } }
        out.project = project?.moving(map)
        return out
    }
}

final class OrganizerApplier {
    private let link: OrganizerLink
    private let moveUp: (Int) -> Int
    private let moveLeft: (Int) -> Int
    private let placeIcon: (FLIcon, IconTarget) -> OrganizerError?
    private let deleteSelected: () -> Bool
    private let moveTrack: (Int, Int) -> Int
    private let moveClips: (Int?, Int) -> Int
    private let readClips: () -> PlaylistView?
    private let moveClip: (ClipMove) -> ClipMoveResult
    private let wait: (TimeInterval) -> Void
    /// Écoute d'une piste seule, pour vérifier qu'un pattern a bien changé de piste.
    private let listen: TimeInterval
    /// Le fichier du projet (analyse sur le fichier : la Playlist rangée dans une copie) ; le nom de pattern posé dans
    /// la copie pour savoir que FL l'a ouverte.
    private let files: ProjectFileAccess?
    private let marker: String
    /// Où en est l'application (texte pour la fenêtre : « FL ouvre la copie rangée… 12 s »).
    private let report: (String) -> Void
    /// Fois où une page de FL a été remise devant pendant les déplacements (diagnostic).
    private var restored = 0
    /// Pourquoi, à chaque fois (diagnostic du 12/11 : « page remise 5 » ne disait pas si FL était passé derrière, si
    /// une autre fenêtre de FL était devant ou si la touche n'avait rien fait). Des mots et des nombres seulement.
    private var restoreCauses: [String] = []
    /// Pages dont FL n'a pas laissé finir le rangement (12/11) : le reste a continué.
    private var unordered: [FLWindow] = []
    /// Icônes ratées (sautées, les suivantes continuent) et leur trace pour le diagnostic.
    private var iconsMissedCount = 0
    private var iconTrace: [String] = []
    /// Icônes connues déjà écrites dans la copie (12/11) : celles-là ne passent plus par la fenêtre de FL.
    private var iconsWrittenInCopy = 0
    /// La copie rangée est ouverte dans FL (analyse sur le fichier) : les clics n'apprennent qu'un numéro par icône, et
    /// toutes les icônes s'écrivent dans la copie à la fin (12/11, `finishIcons`).
    private var organizingCopy = false
    /// Toutes les icônes prévues à leur place finale (Channel rack : place ; Mixer : piste), pour l'écriture finale.
    private var finalRackIcons: [Int: FLIcon] = [:]
    private var finalMixerIcons: [Int: FLIcon] = [:]
    /// Les icônes des pistes de la Playlist rangée d'après les numéros connus (nil : Playlist pas rangée).
    private var playlistIconsFor: (([String: UInt32]) -> [Int: UInt32])?
    /// Première icône manquée : les suivantes ne sont plus essayées, le reste du rangement continue.
    private var iconMiss: OrganizerError?
    /// Icônes prévues, posées à la toute fin (07/11, « dès que je veux mettre des icônes… ça oublie les couleurs des
    /// patterns, de la Playlist, du Mixer, ça oublie de les ranger ») : avant, celles du Channel rack se posaient
    /// avant les patterns, le Mixer et la Playlist, et le moindre accroc pendant une icône arrêtait tout le reste.
    private var pendingIcons: [(icons: [Int: FLIcon], kind: ItemKind, places: [Int: Int])] = []
    /// Icônes posées dans le Channel rack (place finale) : relues dans la copie enregistrée pour apprendre leur numéro.
    private var placedRack: [(icon: FLIcon, place: Int)] = []
    /// Numéro de FL de chaque icône de la grille, appris des rangements précédents (code → numéro).
    private let iconIDs: [String: UInt32]
    /// Icônes posées dans le Mixer (piste finale) et numéros du Mixer appris de même (12/11 : dans crash out 3, les
    /// drums ont 75 dans le Channel rack et 105 dans le Mixer ; jamais un numéro de l'un écrit dans l'autre).
    private var placedMixer: [(icon: FLIcon, place: Int)] = []
    private let mixerIconIDs: [String: UInt32]
    /// En quoi une page relue n'était pas comme prévu (diagnostic, 12/11 : « appliqué-mismatch » ne disait pas
    /// laquelle). Des mots et des nombres seulement.
    private var checks: [String] = []
    /// Icônes posées au second essai (12/11, « ça en saute 1 sur 2… peut-être que c'est trop rapide »).
    private var iconRetries = 0
    /// Boîtes de FL répondues pendant l'ouverture de la copie (4 au plus : jamais Entrée sans fin).
    private var dialogAnswers = 0

    /// `moveUp(n)` envoie ⌥↑ n fois à FL seul (Channel rack devant), `moveLeft(n)` ⌥← (Mixer devant) ; chacun
    /// renvoie le nombre de pas faits. `placeIcon` pose une icône sur l'élément sélectionné par la fenêtre de FL
    /// (clic droit sur son nom › « Change icon… ») ; nil si c'est fait. `deleteSelected` supprime les canaux sélectionnés (⌥ + Suppr, Channel rack devant) ;
    /// faux si rien n'a pu être envoyé. `moveTrack(place, n)` remonte la piste de la Playlist à cette place (0 = la
    /// piste 1) de n places par son menu ; le nombre de places faites. `moveClips(pattern, n)` décale de n pistes (vers
    /// le bas ; négatif : vers le haut) tous les clips de ce pattern (1 = le premier ; nil : la sélection en cours) ;
    /// le nombre de pas faits. `readClips` lit la Playlist dans la fenêtre de FL (nil : impossible) ; `moveClip`
    /// déplace un seul clip et le vérifie (ClipMover).
    init(link: OrganizerLink, moveUp: @escaping (Int) -> Int, moveLeft: @escaping (Int) -> Int = { _ in 0 },
         placeIcon: @escaping (FLIcon, IconTarget) -> OrganizerError? = { _, _ in nil },
         deleteSelected: @escaping () -> Bool = { false },
         moveTrack: @escaping (Int, Int) -> Int = { _, _ in 0 },
         moveClips: @escaping (Int?, Int) -> Int = { _, _ in 0 },
         readClips: @escaping () -> PlaylistView? = { nil },
         moveClip: @escaping (ClipMove) -> ClipMoveResult = { _ in .notDone },
         wait: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
         listen: TimeInterval = 1.5,
         files: ProjectFileAccess? = nil,
         iconIDs: [String: UInt32] = [:],
         mixerIconIDs: [String: UInt32] = [:],
         marker: String = ProjectFile.marker(Int.random(in: 1000...9999)),
         report: @escaping (String) -> Void = { _ in }) {
        self.files = files
        self.iconIDs = iconIDs
        self.mixerIconIDs = mixerIconIDs
        self.marker = marker
        self.report = report
        self.link = link
        self.moveUp = moveUp
        self.moveLeft = moveLeft
        self.placeIcon = placeIcon
        self.deleteSelected = deleteSelected
        self.moveTrack = moveTrack
        self.moveClips = moveClips
        self.readClips = readClips
        self.moveClip = moveClip
        self.wait = wait
        self.listen = listen
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
                         kinds: [Int: SoundKind], options: OrganizerOptions = OrganizerOptions()) -> (moves: [Move], final: [Int]) {
        RegroupPlan.make(order: channels.map { families[$0.index] },
                         kinds: channels.map { Self.kind($0.index, families: families, kinds: kinds) },
                         familyRank: options.familyRank)
    }

    /// Icône de chaque élément : celle de sa famille ; aucune si la famille n'en a pas.
    /// Pur (testé) : les icônes prévues dont le numéro de FL est appris (jamais deviné), par élément.
    static func knownIcons(_ icons: [Int: FLIcon], ids: [String: UInt32]) -> [Int: UInt32] {
        icons.compactMapValues { ids[$0.code] }
    }

    static func plannedIcons(families: [Int: SoundFamily], styles: [SoundFamily: FamilyStyle]) -> [Int: FLIcon] {
        var out: [Int: FLIcon] = [:]
        for (index, family) in families {
            if let icon = (styles[family] ?? FamilyStyles.initial[family])?.icon, !icon.isReset { out[index] = icon }
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

    /// Tout le plan, page par page : sons sans note supprimés (puis le plan refait sur ce qui reste), sons envoyés au
    /// Master reliés à leur piste, Channel rack, patterns, Mixer, Playlist. Une page que FL n'a pas toute prise
    /// (vérifiée en relisant) n'arrête pas les suivantes : elle est dite à la fin (`mismatch`) ; une erreur arrête là.
    /// Le mémo de chaque page est posé avant d'y toucher : « Revenir comme avant » défait ce qui a été fait (sauf les
    /// sons supprimés).
    func apply(_ plan: OrganizerPlan, result: OrganizerResult, styles: [SoundFamily: FamilyStyle]) -> ApplyOutcome {
        var outcome = ApplyOutcome(snapshot: OrganizerSnapshot())
        var verified = true
        var plan = plan
        var result = result
        restored = 0
        restoreCauses = []
        unordered = []
        iconsMissedCount = 0
        iconTrace = []
        organizingCopy = false
        finalRackIcons = [:]
        finalMixerIcons = [:]
        playlistIconsFor = nil
        iconsWrittenInCopy = 0
        iconMiss = nil
        pendingIcons = []
        placedRack = []
        placedMixer = []
        checks = []
        iconRetries = 0
        do {
            if let project = result.project {
                // Toujours dans une copie (son Channel rack sur « All ») ; la Playlist n'y est rangée que si on l'a
                // demandé.
                try openOrganizedCopy(project, &plan, &result, &outcome, styles: styles,
                                      arrange: plan.source?.options.playlist == true)
            }
            if !plan.deleted.isEmpty {
                if let shifted = try deleteUnused(plan.deleted, result, trace: &outcome.trace) {
                    // FL a pu n'en supprimer qu'une partie : les autres restent de côté (sélectionnés à la fin).
                    outcome.deleted = shifted.gone
                    outcome.notDeleted = plan.deleted.count - shifted.gone
                    result = shifted.result
                    plan = plan.replanned(shifted.result, map: shifted.map, styles: styles)
                } else {
                    // Rien de supprimé : le plan sans suppression (les sons restent de côté, leurs pistes aussi).
                    outcome.notDeleted = plan.deleted.count
                    var same: [Int: Int] = [:]
                    for channel in result.channels { same[channel.index] = channel.index }
                    plan = plan.replanned(result, map: same, styles: styles)
                }
            }
            if !plan.mixer.links.isEmpty {
                outcome.snapshot.links = [:]
                let ok = try applyLinks(plan.mixer.links, result, &outcome.snapshot.links!)
                if !ok {
                    verified = false
                    checks.append("liens")
                }
            }
            if !plan.rack.isEmpty {
                outcome.snapshot.rack = AreaSnapshot()
                let ok = try applyRack(plan.rack, result, styles, &outcome.snapshot.rack!)
                if !ok { verified = false }
            }
            if !plan.patterns.isEmpty {
                outcome.snapshot.patterns = AreaSnapshot()
                let ok = try applyPatterns(plan.patterns, result, &outcome.snapshot.patterns!)
                if !ok {
                    verified = false
                    checks.append("patterns")
                }
            }
            if !plan.mixer.isEmpty {
                outcome.snapshot.mixer = AreaSnapshot()
                let ok = try applyMixer(plan.mixer, result, styles, &outcome.snapshot.mixer!)
                if !ok { verified = false }
            }
            if result.project == nil, plan.source?.options.playlist == true, plan.source?.options.splitTracks == true,
               let view = readClips(), !view.clips.isEmpty {
                // Les clips lus dans la fenêtre de FL : chaque son sur sa piste, ses clips réunis (les patterns
                // descendus en entier ne savent pas réunir les clips d'un son posés sur plusieurs pistes).
                try reunite(view, &plan, &result, &outcome, styles: styles)
            } else if !plan.splits.isEmpty {
                outcome.snapshot.splits = []
                let done = try applySplits(plan.splits, &outcome.snapshot.splits!)
                outcome.split = done
                if done < plan.splits.count {
                    // FL n'a pas laissé faire : la Playlist prévue de nouveau avec ceux qui sont descendus.
                    outcome.playlistMixed = true
                    let replanned = plan.limitingSplits(to: done, result, styles: styles)
                    plan.playlist = replanned.playlist
                    plan.splits = replanned.splits
                }
                if outcome.snapshot.splits?.isEmpty == true { outcome.snapshot.splits = nil }
                // Les nouvelles pistes telles que FL les montre (nom et couleur d'avant, pour « Revenir comme avant »).
                if let last = plan.splits.map(\.to).max() {
                    result.playlist = try link.listPlaylist(limit: last + 1)
                }
            }
            if !plan.playlist.isEmpty {
                outcome.snapshot.playlist = AreaSnapshot()
                let ok = try applyPlaylist(plan.playlist, result, &outcome.snapshot.playlist!,
                                           unordered: &outcome.playlistUnordered)
                if !ok {
                    verified = false
                    checks.append("playlist")
                }
            }
            // Tout le reste est fait : les icônes maintenant (une icône ratée ne défait et n'arrête plus rien).
            try placePendingIcons()
            if outcome.notDeleted > 0 {
                // Sons sans note pas supprimés : sélectionnés de nouveau à leur place d'arrivée (les déplacements ont
                // changé la sélection), pour que l'utilisateur les supprime lui-même.
                let arrangement = outcome.snapshot.rack?.arrangement ?? []
                let places = result.unused.compactMap { arrangement.isEmpty ? $0 : arrangement.firstIndex(of: $0) }
                try? link.selectChannels(Set(places), count: result.channels.count)
            }
            if !verified { outcome.error = .mismatch }
            if let copy = outcome.copy, let files, case .failure = files.save(copy) {
                // La copie rangée n'a pas été enregistrée par FL : l'utilisateur le fera (⌘S).
                outcome.copyNotSaved = true
            } else if let copy = outcome.copy, let files, !placedRack.isEmpty || !placedMixer.isEmpty
                        || iconsWrittenInCopy > 0 || !finalRackIcons.isEmpty || !finalMixerIcons.isEmpty {
                let saved = try? files.read(copy)
                // Le numéro que FL donne à chaque icône posée (relu dans la copie enregistrée) : la Playlist le
                // recevra au rangement suivant (aucun numéro deviné : jamais une mauvaise icône).
                outcome.learnedIconIDs = Self.learnIconIDs(placedRack, in: saved.flatMap { try? FLPProject($0) })
                if !outcome.learnedIconIDs.isEmpty { outcome.trace.append("icônes apprises \(outcome.learnedIconIDs.count)") }
                outcome.learnedMixerIconIDs = Self.learnMixerIconIDs(placedMixer, in: saved)
                if !outcome.learnedMixerIconIDs.isEmpty {
                    outcome.trace.append("icônes apprises mixer \(outcome.learnedMixerIconIDs.count)")
                }
                // Icônes écrites dans la copie : celles que FL a gardées en l'enregistrant (diagnostic, 12/11).
                if iconsWrittenInCopy > 0, let saved {
                    let kept = FLPProject.iconCounts(saved)
                    outcome.trace.append("icônes relues rack \(kept.channels) mixer \(kept.inserts)")
                }
                if organizingCopy, let saved {
                    let rackIDs = iconIDs.merging(outcome.learnedIconIDs) { _, learned in learned }
                    let mixerIDs = mixerIconIDs.merging(outcome.learnedMixerIconIDs) { _, learned in learned }
                    if let reopened = finishIcons(saved, copy: copy, original: outcome.snapshot.original,
                                                  rackIDs: rackIDs, mixerIDs: mixerIDs, files: files,
                                                  trace: &outcome.trace) {
                        outcome.copy = reopened
                    }
                }
            }
        } catch {
            outcome.error = Self.failure(error)
            if case .refused? = outcome.error, let refusal = link.lastRefusal { outcome.trace.append("refus \(refusal)") }
        }
        if restored > 0 { outcome.trace.append("page remise \(restored)") }
        if !restoreCauses.isEmpty { outcome.trace.append("remise " + Self.countedCauses(restoreCauses)) }
        outcome.unordered = unordered
        if !unordered.isEmpty { outcome.trace.append("pas rangé " + unordered.map { "\($0)" }.joined(separator: ",")) }
        if !checks.isEmpty { outcome.trace.append("écart " + checks.joined(separator: ", ")) }
        outcome.trace.append(contentsOf: iconTrace)
        if let iconMiss {
            // Dite après « Icônes non posées : » : la raison telle quelle, sans majuscule.
            if case .failed(let why) = iconMiss { outcome.iconsMissed = why } else { outcome.iconsMissed = iconMiss.message }
            outcome.trace.append("icônes non posées")
        }
        return outcome
    }

    /// FL ouvre la copie rangée attendue : un nom de pattern posé pour ça dans la copie, lu par le script (au plus
    /// `openChecks` fois, toutes les demi-secondes, 3 minutes : un gros projet charge ses plugins).
    static let openChecks = 360

    /// Analyse sur le fichier : FL enregistre le projet, qui doit être resté tel qu'à l'analyse (sinon rien n'est
    /// touché) ; la copie rangée est écrite à côté de l'original (chaque clip sur la piste de ses sons, rien d'autre ne
    /// change) et FL l'ouvre. Le nom de pattern qui la marque est remis aussitôt, puis tout le reste (suppressions,
    /// Channel rack, patterns, Mixer, noms et couleurs des pistes) se fait dans la copie. L'original ne bouge pas :
    /// « Revenir comme avant » le rouvre.
    private func openOrganizedCopy(_ project: ProjectSnapshot, _ plan: inout OrganizerPlan,
                                   _ result: inout OrganizerResult, _ outcome: inout ApplyOutcome,
                                   styles: [SoundFamily: FamilyStyle], arrange: Bool) throws {
        guard let files else {
            throw OrganizerError.failed(String(localized: "Le fichier de ton projet n'est pas accessible : rien n'a été touché."))
        }
        let layout = arrange ? plan.layout : nil
        if arrange && layout == nil {
            throw OrganizerError.failed(String(localized: "Ta Playlist a plus de pistes à remplir que FL n'en a : rien n'a été touché."))
        }
        // La copie montre tous les sons (« All ») : le groupe affiché, compté par le script, est celui de l'analyse.
        link.allChannels = false
        let read = try ProjectFile.read(files, known: project.url, channels: result.channels, patterns: result.patterns)
        // Séparé son par son comme à l'analyse : les mêmes clips, les mêmes sons, sinon le projet a changé.
        let split = try ProjectFile.splitting(read.project, read.file)
        let notSounds = Set(result.channels.filter { $0.type == ChannelInfo.automationType }.map(\.index))
        guard split.project.clips == project.clips,
              ProjectFile.sounds(split.project, notSounds: notSounds).patterns == result.patternSounds else {
            throw OrganizerError.failed(String(localized: "Ton projet a changé depuis l'analyse : rien n'a été touché. Ferme l'Organiser, puis relance-le."))
        }
        var copy: FLPFile
        do {
            copy = try layout.map { layout in
                let options = plan.source?.options
                let iconsFor: ([String: UInt32]) -> [Int: UInt32] = { ids in
                    Self.playlistIcons(layout, styles: styles, ids: ids) { rank in
                        SoundFamily.allCases.first { options?.familyRank($0) == rank }
                    }
                }
                playlistIconsFor = iconsFor
                let icons = iconsFor(iconIDs)
                if !icons.isEmpty { outcome.trace.append("icônes playlist \(icons.count)") }
                return try split.project.rearranged(split.file, tracks: layout.tracks, grouped: layout.grouped,
                                                    headers: Set(layout.headers.keys), icons: icons)
            }
                ?? split.project.showingAll(split.file)
        } catch {
            let what = "clips"
            throw OrganizerError.failed(String(localized: "L'Organiser ne sait pas encore ranger ce projet sans risque (\(what)) : rien n'a été touché."))
        }
        // 12/11 (« il faut que ça soit beaucoup plus rapide… à l'instant T… pas dans Mixer ») : les icônes dont le
        // numéro de FL est déjà appris sont écrites dans la copie (Channel rack et Mixer) ; seules les autres passent
        // encore par la fenêtre de FL, à la fin.
        let rackIcons = Self.knownIcons(Self.plannedIcons(families: plan.rack.verdicts.mapValues { $0.family },
                                                          styles: styles), ids: iconIDs)
        let mixerIcons = Self.knownIcons(Self.plannedIcons(families: plan.mixer.verdicts.mapValues { $0.family },
                                                           styles: styles), ids: mixerIconIDs)
        if !iconIDs.isEmpty || !mixerIconIDs.isEmpty {
            // Case de la grille = numéro de FL (des nombres seulement) : la même table servira à Windows.
            func table(_ ids: [String: UInt32]) -> String {
                ids.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: " ")
            }
            outcome.trace.append("icônes connues rack \(table(iconIDs)) mixer \(table(mixerIconIDs))")
        }
        if !rackIcons.isEmpty || !mixerIcons.isEmpty {
            let written = FLPProject.withIcons(copy, channels: rackIcons, inserts: mixerIcons)
            copy = written.file
            iconsWrittenInCopy = written.channels.count + written.inserts.count
            outcome.trace.append("icônes copie rack \(written.channels.count)/\(rackIcons.count) "
                                 + "mixer \(written.inserts.count)/\(mixerIcons.count)")
        }
        // 13/11 (« tout est génial sauf dans channel rack ça n'a pas tout rangé ») : le Channel rack rangé dans la copie,
        // ses sons à leur place avant que FL l'ouvre (plus de ⌥↑ que FL pouvait couper) ; la suite travaille sur les
        // nouvelles places. Un fichier d'une forme inattendue : rangé dans FL comme avant.
        var rackOrder: [Int]?
        let final = plan.rack.final
        if !final.isEmpty, final != Array(0..<final.count) {
            if let reordered = FLPProject.reorderingChannels(copy, order: final), let moved = result.reordering(final) {
                copy = reordered
                rackOrder = final
                result = moved.result
                plan = plan.reordered(moved.result, map: moved.map, styles: styles)
                outcome.trace.append("rack copie \(final.count) reste \(plan.rack.moves.count)")
            } else {
                outcome.trace.append("rack copie non")
            }
        }
        guard var marked = ProjectFile.marking(copy, marker: marker) else {
            let what = "patterns"
            throw OrganizerError.failed(String(localized: "L'Organiser ne sait pas encore ranger ce projet sans risque (\(what)) : rien n'a été touché."))
        }
        // Un dossier de données qui n'existe plus (projet déplacé) : FL bloquerait l'ouverture de la copie sur sa
        // question ; la copie ne le garde pas (l'original, lui, ne bouge pas).
        if let cleaned = ProjectFile.withoutMissingDataFolder(marked.file, projectFolder: read.url.deletingLastPathComponent(),
                                                              exists: files.exists) {
            marked.file = cleaned
            outcome.trace.append("dossier-données=retiré")
        }
        let url = ProjectFile.copyURL(for: read.url, exists: files.exists)
        do {
            try files.write(marked.file, url)
        } catch {
            throw ProjectFile.denied(error) ? ProjectFile.deniedError
                : OrganizerError.failed(String(localized: "La copie rangée n'a pas pu être écrite à côté de ton projet : rien n'a été touché."))
        }
        guard files.open(url) else {
            throw OrganizerError.failed(String(localized: "FL n'a pas pu ouvrir la copie rangée : elle est à côté de ton projet, ouvre-la dans FL. Ton projet n'a pas bougé."))
        }
        outcome.copy = url
        outcome.snapshot.original = read.url
        organizingCopy = true
        MacroLog.shared.write("ORGANIZE", "organized copy written (\(project.clips.count) clips, \(layout?.count ?? 0) tracks), opening")
        // FL l'a ouverte quand le script lit la marque, ou quand sa fenêtre porte le nom de la copie.
        report(String(localized: "FL ouvre la copie rangée…"))
        let started = Date()
        var opened = false
        var how = "non"                                         // diagnostic : le script a lu la marque, ou la fenêtre
        for check in 0..<Self.openChecks {
            wait(0.5)
            answerDialogs(&outcome.trace)
            if showsMark(marked.mark) {
                how = "marque"
            } else if files.isOpen(url) {
                how = "fenêtre"
            }
            if how != "non" {
                opened = true
                break
            }
            if check % 4 == 3 {
                let seconds = Int(Date().timeIntervalSince(started))
                report(String(localized: "FL ouvre la copie rangée… \(seconds) s"))
            }
        }
        outcome.trace.append("ouverture=\(how) \(Int(Date().timeIntervalSince(started))) s")
        MacroLog.shared.write("ORGANIZE", "copy \(opened ? "open" : "not open") after \(Int(Date().timeIntervalSince(started))) s")
        guard opened else {
            throw OrganizerError.failed(String(localized: "FL n'a pas ouvert la copie rangée à temps : elle est à côté de ton projet, ouvre-la dans FL, puis relance l'Organiser. Ton projet n'a pas bougé."))
        }
        report(String(localized: "FL charge les sons de la copie…"))
        let calmFrom = Date()
        try waitUntilCalm(channels: result.channels.count, trace: &outcome.trace)
        outcome.trace.append("calme \(Int(Date().timeIntervalSince(calmFrom))) s")
        MacroLog.shared.write("ORGANIZE", "FL answers after \(Int(Date().timeIntervalSince(calmFrom))) s, arranging")
        // La marque remise : le nom d'avant (une marque restée d'un essai où FL l'avait ouverte trop tard n'est jamais
        // reprise). Un canal garde son nom d'avant (le Channel rack est comparé à l'analyse avant les suppressions).
        switch marked.mark {
        case .pattern(let n):
            let before = read.project.patternNames[n].flatMap { ProjectFile.isMarker($0) ? nil : $0 }
            let name = plan.patterns.names[n - 1] ?? before ?? "Pattern \(n)"
            try retrying { try link.setNames(.patterns, [(index: n - 1, name: name)]) }
        case .channel(let c):
            // Channel rack rangé dans la copie : le canal marqué était à une autre place dans le projet d'origine.
            let was = rackOrder.map { $0.indices.contains(c) ? $0[c] : c } ?? c
            let before = read.project.channels.indices.contains(was)
                ? read.project.channels[was].name.flatMap { ProjectFile.isMarker($0) ? nil : $0 } : nil
            let name = before ?? result.channels.first { $0.index == c }?.name ?? "Channel \(c + 1)"
            try retrying { try link.setNames(.channels, [(index: c, name: name)]) }
        }
        report(String(localized: "Rangement dans la copie…"))
        if let layout {
            result.playlist = try retrying { try link.listPlaylist(limit: layout.count) }
            plan.playlist = plan.replannedPlaylist(result, styles: styles)
        }
    }

    /// La marque de la copie, lue par le script.
    private func showsMark(_ mark: ProjectFile.Mark) -> Bool {
        let name: String?
        switch mark {
        case .pattern(let n): name = (try? link.listPatterns())?.first { $0.index == n - 1 }?.name
        case .channel(let c): name = (try? link.listChannels())?.first { $0.index == c }?.name
        }
        return name.map { ProjectFile.same($0, marker) } ?? false
    }

    /// Une boîte de FL qui attend une réponse pendant l'ouverture de la copie : répondue par son choix par défaut.
    private func answerDialogs(_ trace: inout [String]) {
        guard dialogAnswers < 4, let name = files?.answerDialog() else { return }
        dialogAnswers += 1
        trace.append("boîte=\(name)")
        MacroLog.shared.write("ORGANIZE", "FL dialog answered (\(name))")
    }

    /// FL a ouvert la copie mais charge encore ses plugins et ses sons (« Opening: Fruity Wrapper ») : il ne répond pas
    /// toujours vite (vidéo du propriétaire : « FL n'a pas confirmé » ; puis essai du 24/10 sur un gros projet : « FL
    /// charge les sons de la copie… » sans fin apparente, la règle d'avant voulait 3 réponses en moins d'une seconde).
    /// La suite attend qu'il réponde deux fois de suite en moins de 3 s AVEC tous les sons de l'analyse (25/10 : une
    /// boîte de FL ouverte pendant le chargement, il répondait avec un Channel rack pas encore rempli), 2 min 30 au
    /// plus ; le temps passé est montré, et le diagnostic dit combien de réponses sont venues et la plus lente.
    static let calmChecks = 150
    static let calmAnswer: TimeInterval = 3
    static let calmLimit: TimeInterval = 150

    private func waitUntilCalm(channels expected: Int, trace: inout [String]) throws {
        var calm = 0
        var count = -1
        var answers = 0
        var slowest: TimeInterval = 0
        let started = Date()
        for check in 0..<Self.calmChecks {
            wait(0.5)
            answerDialogs(&trace)
            let asked = Date()
            let listed = try? link.listChannels()
            let took = Date().timeIntervalSince(asked)
            if let listed {
                answers += 1
                slowest = max(slowest, took)
                count = listed.count
            }
            calm = listed != nil && took < Self.calmAnswer ? calm + 1 : 0
            if (calm >= 2 && count == expected) || Date().timeIntervalSince(started) > Self.calmLimit { break }
            if check % 4 == 3 {
                let seconds = Int(Date().timeIntervalSince(started))
                report(String(localized: "FL charge les sons de la copie… \(seconds) s"))
            }
        }
        trace.append("réponses=\(answers) lente=\(Int((slowest * 10).rounded()))ds")
        guard calm >= 2 else {
            throw OrganizerError.failed(String(localized: "FL ne répond plus assez vite depuis l'ouverture de la copie rangée. Elle est ouverte dans FL avec sa Playlist rangée : relance l'Organiser dessus pour finir le reste. Ton projet d'origine n'a pas bougé."))
        }
        // La copie montre tous les sons (« All ») : autant que l'analyse, sinon rien ne serait à sa place.
        guard count == expected else {
            throw OrganizerError.failed(String(localized: "La copie rangée ouverte dans FL n'a pas les mêmes sons que l'analyse (\(count) au lieu de \(expected)) : rien d'autre n'a été fait. Ton projet n'a pas bougé."))
        }
    }

    /// Une demande à FL réessayée (3 fois, une seconde d'écart) : juste après l'ouverture, FL peut encore être occupé.
    /// Un refus de FL n'est pas réessayé.
    private func retrying<T>(_ request: () throws -> T) throws -> T {
        var last: Error = OrganizerError.noResponse
        for attempt in 0..<3 {
            if attempt > 0 { wait(1) }
            do {
                return try request()
            } catch OrganizerError.refused(let reason) {
                throw OrganizerError.refused(reason)
            } catch {
                last = error
            }
        }
        throw last
    }

    /// Relectures du Channel rack après la suppression (0,35 s d'écart, 6 s au plus) : FL supprime les sons un par un
    /// (vidéo du propriétaire, 25/10 : relu trop tôt, il n'avait pas fini et l'Organiser s'arrêtait).
    static let deleteChecks = 17
    static let deleteCheck: TimeInterval = 0.35

    /// Sons sans aucune note supprimés : sélectionnés seuls par le script (relus), Channel rack devant, puis « Delete
    /// selected » de FL (⌥ + Suppr). Le Channel rack est relu jusqu'à ce que FL ait fini (tous partis, ou deux fois le
    /// même) ; ce que FL a vraiment supprimé (`removed`) sert pour la suite, même s'il n'en a supprimé qu'une partie.
    /// nil si rien n'est parti (les sons restent sélectionnés : l'utilisateur peut les supprimer lui-même ; le reste
    /// se fait sans eux). Un autre son supprimé, ou un Channel rack changé autrement : arrêt (dans la copie, « Revenir
    /// comme avant » rouvre l'original).
    private func deleteUnused(_ deleted: [Int], _ result: OrganizerResult, trace: inout [String]) throws
        -> (result: OrganizerResult, map: [Int: Int], gone: Int)? {
        let channels = result.channels.sorted { $0.index < $1.index }
        guard try link.listChannels().map(\.name) == channels.map(\.name) else {
            throw OrganizerError.failed(String(localized: "Le Channel rack a changé depuis l'analyse : relance Organiser."))
        }
        let set = Set(deleted)
        try link.selectChannels(set, count: channels.count)
        guard try link.selectedChannels() == set else { return nil }
        try link.show(.channelRack)
        guard link.window == .channelRack, deleteSelected() else { return nil }
        let expected = result.removing(set).result.channels.map(\.name)
        var previous: [ChannelInfo]?
        var now = try link.listChannels()
        for check in 0..<Self.deleteChecks {
            if now.map(\.name) == expected { break }
            if let previous, check >= 3, Self.sameRack(previous, now) { break }
            previous = now
            wait(Self.deleteCheck)
            now = try link.listChannels()
        }
        let gone = Self.removed(before: channels, after: now, planned: set)
        let others = gone.map { $0.subtracting(set).count } ?? -1
        trace.append("suppression prévus=\(set.count) avant=\(channels.count) après=\(now.count) partis=\(gone?.count ?? -1) autres=\(others)")
        guard let gone else {
            throw OrganizerError.failed(String(localized: "Après la suppression des sons sans note, le Channel rack de la copie rangée ne correspond plus à l'analyse : Organiser s'est arrêté. « Revenir comme avant » rouvre ton projet d'origine, qui n'a pas bougé."))
        }
        guard others == 0 else {
            throw OrganizerError.failed(String(localized: "FL a supprimé d'autres sons que ceux sans note dans la copie rangée : Organiser s'est arrêté. « Revenir comme avant » rouvre ton projet d'origine, qui n'a pas bougé."))
        }
        guard !gone.isEmpty else { return nil }
        let shifted = result.removing(gone)
        return (shifted.result, shifted.map, gone.count)
    }

    private static func sameRack(_ a: [ChannelInfo], _ b: [ChannelInfo]) -> Bool {
        a.count == b.count && zip(a, b).allSatisfy { sameChannel($0, $1) }
    }

    /// Un même canal avant et après des suppressions : son nom, sa sorte, sa piste du Mixer et sa couleur (sa place
    /// change).
    private static func sameChannel(_ a: ChannelInfo, _ b: ChannelInfo) -> Bool {
        a.name == b.name && a.type == b.type && a.mixerTrack == b.mixerTrack && a.color == b.color
    }

    /// Pur (testé) : les canaux (index d'avant) que FL a supprimés, d'après le Channel rack relu : `after` doit être
    /// `before` moins quelques canaux, dans le même ordre. Deux canaux pareils : celui qui était prévu (`planned`) est
    /// pris pour le supprimé. nil : FL montre autre chose (un canal renommé, déplacé ou ajouté).
    static func removed(before: [ChannelInfo], after: [ChannelInfo], planned: Set<Int>) -> Set<Int>? {
        let n = before.count, m = after.count
        guard m <= n else { return nil }
        let impossible = Int.max / 2
        // cost[i][j] : le moins de canaux non prévus supprimés pour que before[i…] devienne after[j…].
        var cost = [[Int]](repeating: [Int](repeating: impossible, count: m + 1), count: n + 1)
        cost[n][m] = 0
        for i in stride(from: n - 1, through: 0, by: -1) {
            let drop = planned.contains(before[i].index) ? 0 : 1
            for j in stride(from: m, through: 0, by: -1) {
                var best = min(impossible, cost[i + 1][j] + drop)
                if j < m, sameChannel(before[i], after[j]) { best = min(best, cost[i + 1][j + 1]) }
                cost[i][j] = best
            }
        }
        guard cost[0][0] < impossible else { return nil }
        var out: Set<Int> = []
        var a = 0, b = 0
        while a < n {
            // Garder le canal quand c'est aussi bien : le moins de suppressions possible.
            if b < m, sameChannel(before[a], after[b]), cost[a + 1][b + 1] == cost[a][b] {
                b += 1
            } else {
                out.insert(before[a].index)
            }
            a += 1
        }
        return out
    }

    /// Sons envoyés au Master reliés chacun à sa piste libre, avant tout déplacement (index d'origine), relus.
    private func applyLinks(_ links: [Int: Int], _ result: OrganizerResult, _ saved: inout [Int: Int]) throws -> Bool {
        var before: [Int: Int] = [:]
        for channel in result.channels { before[channel.index] = channel.mixerTrack }
        for (channel, track) in links.sorted(by: { $0.key < $1.key }) {
            saved[channel] = before[channel] ?? 0
            try link.linkChannel(channel, to: track)
        }
        var now: [Int: Int] = [:]
        for channel in try link.listChannels() { now[channel.index] = channel.mixerTrack }
        return links.allSatisfy { now[$0.key] == $0.value }
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
        // 12/11 (diagnostic du propriétaire « appliqué-interrupted… page remise 5 » : couleurs des patterns, du Mixer
        // et de la Playlist jamais posées, icônes non plus) : une page que FL ne laisse pas finir de ranger n'arrête
        // plus que son rangement ; le reste continue, et c'est dit à la fin. Seul un arrêt demandé (Échap, Arrêter)
        // arrête tout.
        var stopped = false
        do {
            try move(area.moves, &snap.arrangement, page: .channelRack, kind: .channels, offset: 0, key: moveUp)
        } catch OrganizerError.interrupted {
            stopped = true
        } catch {
            // Arrêt en route : l'ordre relu dans FL, pour que « Revenir comme avant » remette chaque chose à sa place.
            if let listed = try? link.listChannels(),
               let seen = Self.arrangement(names: listed.map { $0.name }, original: names) {
                snap.arrangement = seen
            }
            throw error
        }
        var listed = try link.listChannels()
        // L'ordre que FL montre vraiment (une touche ⌥↑ perdue) : une seconde passe depuis cet ordre ; s'il reste un
        // écart, « Revenir comme avant » remet chaque couleur sur son son, et le regroupement manqué est dit.
        var regrouped = true
        if !stopped, let seen = Self.arrangement(names: listed.map { $0.name }, original: names), seen != area.final,
           !area.final.isEmpty {
            snap.arrangement = seen
            do {
                try move(RegroupPlan.moves(from: seen, to: area.final), &snap.arrangement, page: .channelRack,
                         kind: .channels, offset: 0, key: moveUp)
            } catch OrganizerError.interrupted {
                stopped = true
            }
            listed = try link.listChannels()
        }
        // L'ordre relu dans FL (aussi après un arrêt en route) : « Revenir comme avant » et les icônes le suivent.
        var orderRead = false
        if let seen = Self.arrangement(names: listed.map { $0.name }, original: names) {
            regrouped = area.final.isEmpty || seen == area.final
            snap.arrangement = seen
            orderRead = true
        }
        if stopped { unordered.append(.channelRack) }
        let now: [RGBColor?] = listed.map { $0.color }
        let expected: [RGBColor?] = snap.arrangement.map { area.colors[$0] ?? channels[$0].color }
        let wrongColors = zip(now, expected).filter { pair in pair.0 != pair.1 }.count + abs(now.count - expected.count)
        if !(regrouped || stopped) { checks.append("rack ordre") }
        if wrongColors > 0 { checks.append("rack couleurs \(wrongColors)/\(expected.count)") }
        let verifiedPage = (regrouped || stopped) && wrongColors == 0
        // 12/11 (« les icônes… des fois ça marche et des fois ça marche pas ») : un écart relu (l'ordre, une couleur)
        // laissait aussi les icônes de la page, donc aucun numéro appris ni d'icône dans la Playlist la fois suivante.
        // Elles suivent l'ordre relu dans FL ; sans ordre relu seulement, elles restent de côté (jamais sur un autre son).
        guard verifiedPage || orderRead else { return false }
        let arrangement = snap.arrangement
        var places: [Int: Int] = [:]
        for index in icons.keys { if let at = arrangement.firstIndex(of: index) { places[index] = at } }
        for (index, icon) in icons { if let at = places[index] { finalRackIcons[at] = icon } }
        // Dans la copie, seules les icônes au numéro inconnu passent par la fenêtre de FL, pour l'apprendre ; les
        // autres sont écrites dans le fichier (12/11).
        let byHand = organizingCopy ? icons.filter { iconIDs[$0.value.code] == nil } : icons
        if !byHand.isEmpty { pendingIcons.append((icons: byHand, kind: .channels, places: places)) }
        return verifiedPage
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
        // Envois (numéros d'origine, avant tout déplacement : FL les fait suivre les pistes) : ceux d'avant gardés
        // pour « Revenir comme avant », posés, relus.
        var routesOK = true
        for track in area.routes.keys.sorted() {
            let wanted = Set(area.routes[track] ?? [])
            let before = try link.routes(from: track)
            guard Set(before) != wanted else { continue }
            snap.routes[track] = before
            try link.setRoutes(track, to: wanted.sorted())
            let after = try link.routes(from: track)
            if Set(after) != wanted { routesOK = false }
        }
        // Pistes des sons supprimés : leur nom de FL remis une fois les pistes à leur place (un nom de FL suit sa
        // place, il ne servirait pas à relire l'ordre).
        let named = area.names.filter { !$0.value.isEmpty }
        let resets = area.names.keys.filter { area.names[$0]?.isEmpty == true }.sorted()
        try link.setColors(.mixer, Self.pairs(area.colors))
        try link.setNames(.mixer, Self.namePairs(named))
        // Noms tels qu'ils sont maintenant dans FL, par piste d'origine (pistes 1…span) : pour relire l'ordre.
        let names: [String] = span > 0 ? (1...span).map { named[$0] ?? byIndex[$0]?.name ?? "" } : []
        let icons = Self.plannedIcons(families: area.verdicts.mapValues { $0.family }, styles: styles)
        if !area.moves.isEmpty || !icons.isEmpty { try link.show(.mixer) }
        // Comme le Channel rack (12/11) : un rangement que FL ne laisse pas finir n'arrête que lui.
        var stopped = false
        do {
            try move(area.moves, &snap.arrangement, page: .mixer, kind: .mixer, offset: 1, key: moveLeft)
        } catch OrganizerError.interrupted {
            stopped = true
        } catch {
            if span > 0, let listed = try? link.listMixer(),
               let seen = Self.arrangement(names: Self.tracks(listed, 1...span).map { $0.name }, original: names) {
                snap.arrangement = seen.map { $0 + 1 }
            }
            throw error
        }
        var listed = try link.listMixer()
        // Seconde passe depuis l'ordre que FL montre, s'il n'est pas celui prévu (une touche ⌥← perdue).
        if !stopped, span > 0,
           let seen = Self.arrangement(names: Self.tracks(listed, 1...span).map { $0.name }, original: names),
           seen.map({ $0 + 1 }) != area.final {
            let start = seen.map { $0 + 1 }
            snap.arrangement = start
            do {
                try move(RegroupPlan.moves(from: start, to: area.final), &snap.arrangement, page: .mixer,
                         kind: .mixer, offset: 1, key: moveLeft)
            } catch OrganizerError.interrupted {
                stopped = true
            }
            listed = try link.listMixer()
        }
        if stopped { unordered.append(.mixer) }
        var now: [Int: MixerTrackInfo] = [:]
        for track in listed { now[track.index] = track }
        var regrouped = true
        var orderRead = span == 0
        if span > 0, let seen = Self.arrangement(names: Self.tracks(listed, 1...span).map { $0.name }, original: names) {
            let tracks = seen.map { $0 + 1 }
            regrouped = tracks == area.final
            snap.arrangement = tracks
            orderRead = true
        }
        // Chaque piste d'origine est maintenant à la place où l'ordre relu la met.
        let arrangement = snap.arrangement
        func place(_ original: Int) -> Int {
            guard let at = arrangement.firstIndex(of: original) else { return original }
            return at + 1
        }
        let wrongColors = area.colors.filter { now[place($0.key)]?.color != $0.value }.count
        let colorsOK = wrongColors == 0
        var read: [Int: String] = [:]
        for index in named.keys { if let t = now[place(index)] { read[index] = t.name } }
        var resetOK = true
        if !resets.isEmpty {
            try link.setNames(.mixer, resets.map { (index: place($0), name: "") })
            var after: [Int: MixerTrackInfo] = [:]
            for track in try link.listMixer() { after[track.index] = track }
            resetOK = resets.allSatisfy { after[place($0)]?.hasDefaultName == true }
        }
        let namesOK = Self.namesMatch(named, read)
        if !(regrouped || stopped) { checks.append("mixer ordre") }
        if !colorsOK { checks.append("mixer couleurs \(wrongColors)/\(area.colors.count)") }
        if !routesOK { checks.append("mixer envois") }
        if !resetOK { checks.append("mixer remises") }
        if !namesOK { checks.append("mixer noms") }
        let verifiedPage = (regrouped || stopped) && colorsOK && routesOK && resetOK && namesOK
        // Comme le Channel rack (12/11) : un écart relu ne laisse plus les icônes, posées d'après l'ordre relu.
        guard verifiedPage || orderRead else { return false }
        var places: [Int: Int] = [:]
        for index in icons.keys { places[index] = place(index) }
        for (index, icon) in icons { if let at = places[index] { finalMixerIcons[at] = icon } }
        let byHand = organizingCopy ? icons.filter { mixerIconIDs[$0.value.code] == nil } : icons
        if !byHand.isEmpty { pendingIcons.append((icons: byHand, kind: .mixer, places: places)) }
        return verifiedPage
    }

    /// Pur (testé) : le numéro de FL de chaque icône posée, relu sur le canal à sa place dans la copie enregistrée.
    static func learnIconIDs(_ placed: [(icon: FLIcon, place: Int)], in project: FLPProject?) -> [String: UInt32] {
        guard let project else { return [:] }
        var out: [String: UInt32] = [:]
        for (icon, place) in placed where project.channels.indices.contains(place) {
            if let id = project.channels[place].icon, id != 0 { out[icon.code] = id }
        }
        return out
    }

    /// Ce qui manque encore dans la copie enregistrée : Channel rack (rang du son → numéro), Mixer (piste → numéro),
    /// Playlist (piste → numéro).
    struct IconWrites: Equatable {
        var rack: [Int: UInt32] = [:]
        var mixer: [Int: UInt32] = [:]
        var tracks: [Int: UInt32] = [:]
        var isEmpty: Bool { rack.isEmpty && mixer.isEmpty && tracks.isEmpty }
    }

    /// Pur (testé) : les icônes voulues (`rack` : place finale → numéro ; `mixer` : piste → numéro ; `tracks` : piste de
    /// la Playlist → numéro) qui ne sont pas déjà dans ce fichier, et seulement là où FL a sa case pour l'icône.
    static func iconsToWrite(_ project: FLPProject, _ file: FLPFile, rack: [Int: UInt32], mixer: [Int: UInt32],
                             tracks: [Int: UInt32]) -> IconWrites {
        var out = IconWrites()
        for (place, id) in rack where project.channels.indices.contains(place) {
            let channel = project.channels[place]
            if let now = channel.icon, now != id { out.rack[channel.iid] = id }
        }
        if let prefixes = FLPProject.insertPrefixes(file.events) {
            let now = FLPProject.insertIcons(file)
            for (insert, id) in mixer where prefixes[insert] != nil && now[insert] != id { out.mixer[insert] = id }
        }
        let now = project.trackIcons(file)
        for (track, id) in tracks { if let current = now[track], current != id { out.tracks[track] = id } }
        return out
    }

    /// Pur (testé) : la copie avec ces icônes (Playlist d'abord : des octets changés, aucune place ne bouge ; puis le
    /// Channel rack et le Mixer).
    static func withAllIcons(_ file: FLPFile, project: FLPProject, _ writes: IconWrites) -> FLPFile {
        let tracked = project.withTrackIcons(file, writes.tracks)
        return FLPProject.withIcons(tracked, channels: writes.rack, inserts: writes.mixer).file
    }

    /// 12/11 (« ça n'a toujours pas fonctionné dans la playlist, dans mixer "melodie" a été oublié et dans channel
    /// rack "arp" a été oublié ») : les clics n'apprennent plus qu'un numéro par icône ; toutes les icônes dont le numéro
    /// est connu sont ensuite écrites dans la copie enregistrée (Channel rack, Mixer, Playlist), réécrite sous le nom
    /// suivant (jamais par-dessus un fichier) puis rouverte dans FL ; la copie d'avant part à la Corbeille. Rien de plus
    /// à écrire : rien n'est rouvert. Renvoie la copie ouverte dans FL si elle a changé. Jamais d'erreur : tout le reste
    /// est déjà fait, l'accroc est seulement dit.
    private func finishIcons(_ saved: FLPFile, copy: URL, original: URL?, rackIDs: [String: UInt32],
                             mixerIDs: [String: UInt32], files: ProjectFileAccess, trace: inout [String]) -> URL? {
        guard let project = try? FLPProject(saved) else { return nil }
        let writes = Self.iconsToWrite(project, saved, rack: Self.knownIcons(finalRackIcons, ids: rackIDs),
                                       mixer: Self.knownIcons(finalMixerIcons, ids: mixerIDs),
                                       tracks: playlistIconsFor?(rackIDs) ?? [:])
        let unknown = finalRackIcons.values.filter { rackIDs[$0.code] == nil }.count
            + finalMixerIcons.values.filter { mixerIDs[$0.code] == nil }.count
        guard !writes.isEmpty else {
            if unknown == 0 { iconMiss = nil }                // tout est déjà là
            return nil
        }
        guard let marked = ProjectFile.marking(Self.withAllIcons(saved, project: project, writes), marker: marker) else {
            trace.append("icônes fichier : pas de marque")
            return nil
        }
        // Le nom que FL montre maintenant à la place de la marque : remis une fois la copie rouverte.
        let shown: String?
        switch marked.mark {
        case .pattern(let n): shown = (try? link.listPatterns())?.first { $0.index == n - 1 }?.name
        case .channel(let c): shown = (try? link.listChannels())?.first { $0.index == c }?.name
        }
        let url = ProjectFile.copyURL(for: original ?? copy, exists: files.exists)
        do {
            try files.write(marked.file, url)
        } catch {
            trace.append("icônes fichier : copie pas écrite")
            return nil
        }
        report(String(localized: "FL rouvre la copie avec toutes ses icônes…"))
        guard files.open(url) else {
            files.trash(url)
            trace.append("icônes fichier : FL n'a pas rouvert la copie")
            return nil
        }
        let started = Date()
        var opened = false
        for _ in 0..<Self.openChecks {
            wait(0.5)
            answerDialogs(&trace)
            if showsMark(marked.mark) {
                opened = true
                break
            }
        }
        guard opened else {
            trace.append("icônes fichier : FL n'a pas rouvert la copie")
            return nil
        }
        // La marque remise : le nom que FL montrait juste avant, sinon celui du fichier (jamais une marque).
        func plain(_ name: String?) -> String? { name.flatMap { ProjectFile.isMarker($0) ? nil : $0 } }
        switch marked.mark {
        case .pattern(let n):
            let name = plain(shown) ?? plain(project.patternNames[n]) ?? "Pattern \(n)"
            _ = try? retrying { try link.setNames(.patterns, [(index: n - 1, name: name)]) }
        case .channel(let c):
            let saved = project.channels.indices.contains(c) ? project.channels[c].name : nil
            let name = plain(shown) ?? plain(saved) ?? "Channel \(c + 1)"
            _ = try? retrying { try link.setNames(.channels, [(index: c, name: name)]) }
        }
        var calmTrace: [String] = []
        if (try? waitUntilCalm(channels: project.channels.count, trace: &calmTrace)) == nil {
            trace.append("icônes fichier : FL lent")
        }
        if case .failure = files.save(url) { trace.append("icônes fichier : copie pas enregistrée") }
        files.trash(copy)
        trace.append("icônes fichier rack \(writes.rack.count) mixer \(writes.mixer.count) playlist \(writes.tracks.count)"
                     + " rouverte \(Int(Date().timeIntervalSince(started))) s")
        MacroLog.shared.write("ORGANIZE", "icons written in the copy, reopened after \(Int(Date().timeIntervalSince(started))) s")
        if unknown == 0 { iconMiss = nil }
        return url
    }

    /// Pur (testé) : le numéro que FL a donné à chaque icône posée dans le Mixer, relu piste par piste dans la copie
    /// enregistrée (`place` : la piste du Mixer, Master = 0).
    static func learnMixerIconIDs(_ placed: [(icon: FLIcon, place: Int)], in file: FLPFile?) -> [String: UInt32] {
        guard let file else { return [:] }
        let icons = FLPProject.insertIcons(file)
        var out: [String: UInt32] = [:]
        for (icon, place) in placed { if let id = icons[place] { out[icon.code] = id } }
        return out
    }

    /// Pur (testé) : l'icône de chaque piste de la Playlist rangée : celle de sa famille sur sa piste de tête et sur
    /// les pistes groupées dessous, seulement si son numéro dans FL est connu.
    static func playlistIcons(_ layout: PlaylistLayout.Result, styles: [SoundFamily: FamilyStyle], ids: [String: UInt32],
                              family: (Int) -> SoundFamily?) -> [Int: UInt32] {
        guard !ids.isEmpty else { return [:] }
        var out: [Int: UInt32] = [:]
        var current: UInt32?
        let last = max(layout.count, (layout.headers.keys.max() ?? -1) + 1)
        for track in 0..<last {
            if let rank = layout.headers[track] {
                current = family(rank).flatMap { (styles[$0] ?? FamilyStyles.initial[$0])?.icon }
                    .flatMap { $0.isReset ? nil : ids[$0.code] }
                if let current { out[track] = current }
            } else if layout.grouped.contains(track) {
                if let current { out[track] = current }
            } else {
                current = nil
            }
        }
        return out
    }

    /// Pistes du Mixer de cette plage, dans l'ordre.
    private static func tracks(_ listed: [MixerTrackInfo], _ range: ClosedRange<Int>) -> [MixerTrackInfo] {
        listed.filter { range.contains($0.index) }.sorted { $0.index < $1.index }
    }

    /// Playlist : couleurs et noms (pistes d'origine), vérifiés sur les pistes touchées ; puis, Playlist devant, les
    /// pistes remontées une à une par leur menu (« Move up »). FL qui ne laisse pas faire : `unordered` (noms et
    /// couleurs restent posés, « Revenir comme avant » défait ce qui a bougé).
    private func applyPlaylist(_ area: OrganizerPlan.Area, _ result: OrganizerResult, _ snap: inout AreaSnapshot,
                               unordered: inout Bool) throws -> Bool {
        for track in result.playlist {
            if area.colors[track.index] != nil { snap.colors[track.index] = track.color }
            // Nom de FL lu vide : remis en « Track n » (un nom vide ne peut pas être posé).
            if area.names[track.index] != nil {
                snap.names[track.index] = track.name.isEmpty ? "Track \(track.index + 1)" : track.name
            }
        }
        try link.setColors(.playlist, Self.pairs(area.colors))
        try link.setNames(.playlist, Self.namePairs(area.names))
        var ok = true
        let last = max(area.colors.keys.max() ?? -1, area.names.keys.max() ?? -1)
        if last >= 0 {
            var colors: [Int: RGBColor] = [:]
            var names: [Int: String] = [:]
            for track in try link.listPlaylist(limit: last + 1) {
                colors[track.index] = track.color
                names[track.index] = track.name
            }
            ok = area.colors.allSatisfy { colors[$0.key] == $0.value } && Self.namesMatch(area.names, names)
        }
        guard !area.moves.isEmpty else { return ok }
        snap.arrangement = Array(0..<area.final.count)
        try link.show(.playlist)
        for step in area.moves {
            let done = moveTrack(step.from, step.up)
            snap.arrangement = RegroupPlan.applying(Move(from: step.from, up: done), to: snap.arrangement)
            if done < step.up {
                unordered = true
                break
            }
        }
        return ok
    }

    /// Playlist, un son par piste et chaque son sur une seule piste : les clips lus dans la fenêtre de FL, chacun
    /// déplacé seul vers la piste de son son (ClipLayout.moves) et vérifié ; un clip qui ne se fait pas reste à sa
    /// place (`clipsLeft`), les autres continuent ; au troisième, la suite s'arrête (FL ne laisse pas faire). Puis la
    /// Playlist prévue de nouveau sur les clips à leur place (noms, couleurs, ordre).
    private func reunite(_ view: PlaylistView, _ plan: inout OrganizerPlan, _ result: inout OrganizerResult,
                         _ outcome: inout ApplyOutcome, styles: [SoundFamily: FamilyStyle]) throws {
        // Pistes vides : aucun clip lu, aucun son entendu à l'analyse (un clip audio y est peut-être).
        let used = Set(result.trackSounds.keys).union(result.trackItems.map(\.index)).union(view.clips.map(\.track))
        let free = view.visible.filter { !used.contains($0) }
        let moves = ClipLayout.moves(view.clips, sounds: result.patternSounds, free: free)
        var done: [ClipMove] = []
        var failed = 0
        outcome.snapshot.clipMoves = []
        for move in moves {
            let moved = moveClip(move)
            if moved == .stuck {
                throw OrganizerError.failed(String(localized: "Un clip de la Playlist n'a pas pu être remis à sa place : annule dans FL (Edit › Undo), puis réessaie."))
            }
            guard moved == .done else {
                failed += 1
                if failed >= 3 { break }
                continue
            }
            done.append(move)
            outcome.snapshot.clipMoves?.append(move)
        }
        outcome.clipsLeft = moves.count - done.count
        MacroLog.shared.write("PLAYLIST", "clips reunited \(done.count)/\(moves.count)")
        outcome.reunited = done.count
        if done.isEmpty { outcome.snapshot.clipMoves = nil }
        let after = ClipLayout.applying(done, to: view.clips)
        result.trackSounds = ClipLayout.trackSounds(result.trackSounds, before: view.clips, after: after,
                                                    sounds: result.patternSounds)
        let last = max(result.trackSounds.keys.max() ?? -1, result.trackItems.map(\.index).max() ?? -1,
                       result.playlist.count - 1)
        if last >= 0 { result.playlist = try link.listPlaylist(limit: last + 1) }
        plan.splits = []
        plan.playlist = plan.replannedPlaylist(result, styles: styles)
    }

    /// Playlist, un son par piste : chaque pattern à descendre est ouvert par le script, tous ses clips sélectionnés
    /// (⌘D puis ⇧C de FL, « Select by selected source ») et descendus sur sa piste vide (⇧↓), puis vérifié à l'écoute,
    /// piste seule : son son joue sur la nouvelle piste, et l'autre son de l'ancienne y joue encore (sans sélection,
    /// FL aurait descendu tous les clips). Au moindre doute, les clips remontent (⇧↑, même sélection) et tout
    /// s'arrête là. Renvoie le nombre de patterns descendus (dans `done`, pour « Revenir comme avant »).
    private func applySplits(_ splits: [PlaylistSplit], _ done: inout [PlaylistSplit]) throws -> Int {
        for split in splits {
            let rows = split.to - split.from
            let moved = moveClips(split.pattern + 1, rows)
            if moved == rows, heard(split.to, at: split.at).contains(split.sound),
               heard(split.from, at: split.keptAt).contains(split.kept) {
                done.append(split)
                continue
            }
            MacroLog.shared.write("PLAYLIST", "split \(done.count + 1) not confirmed (\(moved)/\(rows) steps)")
            guard moved > 0 else { break }
            let back = moveClips(nil, -moved)
            guard back == moved, heard(split.from, at: split.keptAt).contains(split.kept) else {
                throw OrganizerError.failed(String(localized: "Des clips de la Playlist n'ont pas pu être remis à leur place : annule dans FL (Edit › Undo), puis réessaie."))
            }
            break
        }
        MacroLog.shared.write("PLAYLIST", "split \(done.count)/\(splits.count)")
        return done.count
    }

    /// Sons qui jouent sur cette piste seule, à cette position de la chanson (écoutée `listen`, FL remis ensuite).
    private func heard(_ track: Int, at position: Double) -> Set<Int> {
        defer { link.stopRestore() }
        guard (try? link.playTrack(track)) != nil else { return [] }
        if position > 0 { try? link.seek(position) }
        wait(0.2)
        _ = try? link.heardChannels()
        wait(listen)
        return (try? link.heardChannels()) ?? []
    }

    /// Noms comparés tels que le script les lit (coupés) : le nom relu est le début du nom posé.
    static func namesMatch(_ sent: [Int: String], _ read: [Int: String]) -> Bool {
        sent.allSatisfy { item in
            guard let got = read[item.key], let bytes = OrganizerPayload.nameUTF8(item.value) else { return false }
            let readBytes = Array(got.utf8)
            return !readBytes.isEmpty && Array(bytes.prefix(readBytes.count)) == readBytes
        }
    }

    /// Les icônes du Channel rack puis du Mixer, après tout le reste. N'importe quel accroc (page de FL qui a changé,
    /// FL qui ne répond pas, nom introuvable) n'arrête que les icônes, dit à la fin ; seul Échap arrête tout.
    private func placePendingIcons() throws {
        let jobs = pendingIcons
        pendingIcons = []
        // 12/11 : le Mixer passe même si le Channel rack a raté des icônes.
        for job in jobs {
            do {
                try placeIcons(job.icons, kind: job.kind, oncePerIcon: organizingCopy) { job.places[$0] }
            } catch OrganizerError.interrupted {
                throw OrganizerError.interrupted
            } catch {
                if iconMiss == nil { iconMiss = Self.failure(error) }
            }
        }
        if iconRetries > 0 { iconTrace.append("icônes au 2e essai \(iconRetries)") }
        if iconsMissedCount > 0 { iconTrace.append("icônes ratées \(iconsMissedCount)") }
    }

    /// Ratés de suite après lesquels une page laisse ses icônes (FL ne laisse plus faire : inutile d'attendre).
    static let iconFailuresInARow = 3
    /// Pause avant le second essai d'une icône ratée.
    static let iconRetryPause: TimeInterval = 0.8

    /// Icônes en dernier (FL ne dit pas lesquelles étaient là : « Revenir comme avant » ne les retire pas). Chaque
    /// élément est sélectionné seul, puis la pose passe par la fenêtre de FL (son nom y est retrouvé d'après les
    /// noms relus dans l'ordre de FL) ; la page est remise devant si elle ne l'est plus. Une icône manquée n'arrête
    /// que les icônes (capture du 31/10 : le Mixer n'était plus rangé) ; Échap arrête tout.
    /// 12/11 (capture du propriétaire : icônes sur Basse, Basse 2, Clap, Clap 2, puis plus rien ni dans le Mixer : Perc
    /// avait raté et tout s'arrêtait) : un élément raté est sauté et les suivants continuent, du haut vers le bas de la
    /// page ; la page s'arrête après `iconFailuresInARow` ratés de suite. La première raison est dite à la fin ; seul
    /// Échap arrête tout.
    /// `oncePerIcon` (copie rangée, 12/11) : un seul élément par icône, pour apprendre son numéro ; les autres
    /// éléments de la même icône sont écrits dans le fichier à la fin (un raté : l'élément suivant de cette icône).
    private func placeIcons(_ icons: [Int: FLIcon], kind: ItemKind, oncePerIcon: Bool = false,
                            place: (Int) -> Int?) throws {
        guard !icons.isEmpty else { return }
        let page: FLWindow = kind == .channels ? .channelRack : .mixer
        if link.window != page { try link.show(page) }
        let names = kind == .channels ? IconTarget.channelNames(try link.listChannels())
                                      : IconTarget.mixerNames(try link.listMixer())
        let order = icons.keys.compactMap { index in place(index).map { (index: index, at: $0) } }
            .sorted { $0.at < $1.at }
        func attempt(_ icon: FLIcon, at: Int) throws -> OrganizerError? {
            if link.window != page { try link.show(page) }
            guard link.window == page else {
                return .failed(String(localized: "la page de FL a changé pendant les icônes"))
            }
            try link.selectOne(kind, at)
            return placeIcon(icon, IconTarget(kind: kind, place: at, names: names))
        }
        var inARow = 0
        var learned = Set<String>()
        for (index, at) in order {
            guard let icon = icons[index] else { continue }
            if oncePerIcon, learned.contains(icon.code) { continue }
            var failure = try attempt(icon, at: at)
            // 12/11 (« ça en saute 1 sur 2… peut-être que c'est trop rapide ») : une icône ratée est réessayée une
            // fois, après avoir laissé FL souffler un instant.
            if let first = failure, first != .interrupted {
                wait(Self.iconRetryPause)
                failure = try attempt(icon, at: at)
                if failure == nil { iconRetries += 1 }
            }
            guard let failure else {
                inARow = 0
                learned.insert(icon.code)
                if kind == .channels {
                    placedRack.append((icon: icon, place: at))
                } else {
                    placedMixer.append((icon: icon, place: at))
                }
                continue
            }
            if failure == .interrupted { throw failure }
            if iconMiss == nil { iconMiss = failure }
            iconsMissedCount += 1
            inARow += 1
            if inARow >= Self.iconFailuresInARow { return }
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

    /// Une page de FL qui n'est plus devant pendant les déplacements (FL qui finit d'ouvrir la copie, une fenêtre de
    /// plugin : capture du propriétaire, Channel rack à moitié rangé) est remise devant ; arrêt si elle repart encore
    /// `pageRetries` fois DE SUITE (12/11 : comptées sur tout le rangement d'une page, cinq accrocs réparés un à un
    /// arrêtaient tout ; un déplacement réussi remet le compte à zéro).
    static let pageRetries = 4

    /// Pur (testé) : les causes dans l'ordre où elles sont apparues, chacune avec son nombre (« rack FL derrière 3,
    /// mixer fenêtre plugin 1 »).
    static func countedCauses(_ causes: [String]) -> String {
        var order: [String] = []
        var counts: [String: Int] = [:]
        for cause in causes {
            if counts[cause] == nil { order.append(cause) }
            counts[cause, default: 0] += 1
        }
        return order.map { "\($0) \(counts[$0] ?? 0)" }.joined(separator: ", ")
    }

    private static func pageName(_ page: FLWindow) -> String {
        switch page {
        case .channelRack: return "rack"
        case .mixer: return "mixer"
        case .playlist: return "playlist"
        case .pianoRoll: return "pianoroll"
        case .browser: return "browser"
        case .plugin: return "plugin"
        case .unknown: return "inconnue"
        }
    }

    /// Déplacements un par un (élément sélectionné puis touches) ; la disposition suit ce qui a vraiment été fait.
    /// `offset` : index FL de la place 0 (Mixer : 1, le Master ne bouge pas). Page plus devant ou touches perdues :
    /// la page remise devant, puis le reste du déplacement.
    private func move(_ moves: [Move], _ arrangement: inout [Int], page: FLWindow, kind: ItemKind, offset: Int,
                      key: (Int) -> Int) throws {
        var retries = 0
        func restore(_ cause: String) throws {
            retries += 1
            restored += 1
            restoreCauses.append("\(Self.pageName(page)) \(cause)")
            guard retries <= Self.pageRetries else { throw OrganizerError.interrupted }
            try? link.show(page)
            wait(0.5)
        }
        for step in moves {
            var place = step.from
            var left = step.up
            while left > 0 {
                let shown = link.window
                guard shown == page else {
                    try restore("fenêtre \(Self.pageName(shown))")
                    continue
                }
                try link.selectOne(kind, place + offset)
                // Négatif : FL n'était pas au premier plan (aucune touche envoyée).
                let sent = key(left)
                let done = min(max(sent, 0), left)
                arrangement = RegroupPlan.applying(Move(from: place, up: done), to: arrangement)
                place -= done
                left -= done
                if done == 0 { try restore(sent < 0 ? "FL derrière" : "touche sans effet") } else { retries = 0 }
            }
        }
    }

    /// « Revenir comme avant » : Playlist, Mixer, patterns, Channel rack (couleurs et noms d'origine remis sur la
    /// place actuelle de chaque élément, puis l'ordre d'origine), puis les sons reliés à une piste renvoyés au Master.
    /// Chaque page remise sort du mémo : un retour interrompu reprend là où il s'est arrêté. Les sons supprimés ne
    /// reviennent pas.
    func undo(_ snapshot: OrganizerSnapshot) -> ApplyOutcome {
        var outcome = ApplyOutcome(snapshot: snapshot)
        if let original = snapshot.original {
            // Rangé dans une copie : l'original, qui n'a pas bougé, rouvert dans FL (tout revient, sons supprimés
            // compris). FL demande peut-être s'il faut enregistrer la copie : l'utilisateur choisit.
            guard let files, files.open(original) else {
                outcome.error = .failed(String(localized: "FL n'a pas pu rouvrir ton projet d'origine : il est toujours là, ouvre-le dans FL."))
                return outcome
            }
            outcome.snapshot = OrganizerSnapshot()
            return outcome
        }
        do {
            if var s = snapshot.playlist {
                // Couleurs et noms d'origine sur la place actuelle de chaque piste, puis l'ordre d'origine.
                let arrangement = s.arrangement
                func current(_ original: Int) -> Int { arrangement.firstIndex(of: original) ?? original }
                var colors: [Int: RGBColor] = [:]
                for (original, color) in s.colors { colors[current(original)] = color }
                var names: [Int: String] = [:]
                for (original, name) in s.names { names[current(original)] = name }
                try link.setColors(.playlist, Self.pairs(colors))
                try link.setNames(.playlist, Self.namePairs(names))
                s.colors = [:]
                s.names = [:]
                outcome.snapshot.playlist = s
                var places = arrangement
                let back = RegroupPlan.back(final: places)
                if !back.isEmpty { try link.show(.playlist) }
                for step in back {
                    let done = moveTrack(step.from, step.up)
                    places = RegroupPlan.applying(Move(from: step.from, up: done), to: places)
                    outcome.snapshot.playlist?.arrangement = places
                    if done < step.up { throw OrganizerError.interrupted }
                }
                outcome.snapshot.playlist = nil
            }
            if let moves = snapshot.clipMoves {
                // Les pistes revenues à leur place : chaque clip réuni retourne sur sa piste d'avant.
                for move in moves.reversed() {
                    guard moveClip(move.reversed) == .done else { throw OrganizerError.interrupted }
                    outcome.snapshot.clipMoves?.removeLast()
                }
                outcome.snapshot.clipMoves = nil
            }
            if let splits = snapshot.splits {
                // Les pistes revenues à leur place : chaque pattern descendu remonte sur sa piste d'avant.
                for split in splits.reversed() {
                    let rows = split.to - split.from
                    if moveClips(split.pattern + 1, -rows) != rows { throw OrganizerError.interrupted }
                    outcome.snapshot.splits?.removeLast()
                }
                outcome.snapshot.splits = nil
            }
            if snapshot.mixer != nil {
                try undoArranged(&outcome.snapshot.mixer!, kind: .mixer, page: .mixer, offset: 1, key: moveLeft)
                // Les envois d'origine, une fois chaque piste revenue à sa place.
                for (track, dests) in (outcome.snapshot.mixer?.routes ?? [:]).sorted(by: { $0.key < $1.key }) {
                    try link.setRoutes(track, to: dests)
                    outcome.snapshot.mixer?.routes[track] = nil
                }
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
            // Les sons envoyés au Master y retournent, une fois chaque canal revenu à sa place.
            for (channel, track) in (snapshot.links ?? [:]).sorted(by: { $0.key < $1.key }) {
                try link.linkChannel(channel, to: track)
                outcome.snapshot.links?[channel] = nil
            }
            outcome.snapshot.links = nil
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
