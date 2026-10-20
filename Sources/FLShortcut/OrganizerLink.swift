// Organiser : le lien avec FL pour les opérations 2 à 18 du script (PROTOCOL.md §8 ; 9 à 12 : script v6, 14 à 16 :
// v11, patterns, noms de tout genre, envois du Mixer et page à mettre devant : v12). Les octets de chaque opération et
// le décodage des listes sont purs (testés) ; `RequestOrganizerLink` les envoie par le lien, à 20 par seconde au plus
// comme le veut le script. Les noms des sons servent à l'aperçu et aux nouveaux noms seulement : jamais journalisés.
import Foundation

/// Genre d'éléments de FL : canaux du Channel rack, pistes du Mixer ou de la Playlist, patterns.
enum ItemKind: UInt8 {
    case channels = 1, mixer = 2, playlist = 3, patterns = 4
}

/// Un canal du Channel rack, tel que le script le décrit.
struct ChannelInfo: Equatable {
    let index: Int
    /// Type de canal de FL (`channels.getChannelType`) : 0 échantillon (ou inconnu avant l'API 19), 2 plugin,
    /// 3 layer, 4 clip audio, 5 automation.
    let type: Int
    let mixerTrack: Int
    let color: RGBColor
    let name: String

    static let layerType = 3
    static let automationType = 5
}

struct MixerTrackInfo: Equatable {
    let index: Int
    let color: RGBColor
    let name: String

    /// Nom donné par FL à une piste jamais renommée (« Insert 3 », ou vide).
    var hasDefaultName: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed == "Insert \(index)"
    }
}

/// Un pattern : index 0 = pattern 1 de FL.
struct PatternInfo: Equatable {
    let index: Int
    let color: RGBColor
    /// Coupé par le script (aperçu et « Revenir comme avant »).
    let name: String

    /// Nom donné par FL à un pattern jamais renommé (« Pattern 3 », ou vide).
    var hasDefaultName: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed == "Pattern \(index + 1)"
    }
}

/// Une piste de la Playlist : index 0 = piste 1 de FL.
struct PlaylistTrackInfo: Equatable {
    let index: Int
    let selected: Bool
    let color: RGBColor
    /// Coupé à 24 octets par le script (aperçu seulement).
    let name: String

    /// Nom donné par FL à une piste jamais renommée (« Track 3 », ou vide).
    var hasDefaultName: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty || trimmed == "Track \(index + 1)"
    }
}

/// Refus de FL (raison du CC 116), panne du lien ou arrêt, avec un message pour l'utilisateur.
enum OrganizerError: Error, Equatable {
    case refused(Int)
    case failed(String)
    /// Échap pendant l'écoute.
    case cancelled
    /// La page de FL où les éléments sont déplacés (Channel rack, Mixer) n'est plus devant.
    case interrupted
    /// Après l'application, FL ne montre pas ce qui était prévu.
    case mismatch
    /// Le script chargé dans FL est l'ancien (sans les opérations 9 à 12) : FL doit être redémarré.
    case outdatedScript
    /// FL ne répond pas : le script n'est pas chargé (Controller type « generic controller », ports différents…).
    case noResponse
    /// FL Studio n'est pas ouvert.
    case flClosed
    /// Pas un son reçu de FL pendant toute l'écoute (autorisation « Audio du système », sortie de FL coupée…).
    case noSound

    var message: String {
        switch self {
        case .cancelled: return String(localized: "Organiser arrêté : FL est remis comme avant.")
        case .interrupted:
            return String(localized: "La page de FL a changé pendant le rangement : Organiser s'est arrêté. « Revenir comme avant » défait ce qui a été fait.")
        case .mismatch: return String(localized: "FL n'a pas tout pris : vérifie dans FL, ou clique sur « Revenir comme avant ».")
        case .noResponse:
            return String(localized: "FL ne répond pas : le script FL Shortcuts n'est pas chargé dans FL. Vérifie ces réglages, puis « Réessayer ».")
        case .flClosed: return String(localized: "FL Studio n'est pas ouvert.")
        case .noSound:
            return String(localized: """
                Aucun son reçu de FL pendant l'écoute. Vérifie que FL Shortcuts a l'autorisation « Audio du système » \
                (Réglages Système › Confidentialité et sécurité › Enregistrement de l'écran et de l'audio du système), \
                et que les sons choisis jouent bien dans FL (Master pas coupé), puis « Réessayer ».
                """)
        case .outdatedScript:
            return String(localized: "FL utilise encore l'ancienne version du lien : redémarre FL Studio (il charge la nouvelle au lancement), puis clique sur « Réessayer ».")
        case .refused(1): return String(localized: "Ouvre le Channel rack, le Mixer ou la Playlist de FL (clique dedans), puis clique sur « Réessayer ».")
        case .refused(2): return String(localized: "Sélectionne au moins un élément dans FL.")
        case .refused(4): return String(localized: "FL joue : appuie sur Stop, puis relance Organiser.")
        case .refused(6): return String(localized: "Ta version de FL ne permet pas cette étape : mets FL Studio à jour.")
        case .refused(7): return String(localized: "Sélectionne au moins 2 pistes pour un dégradé.")
        case .refused(let r): return String(localized: "FL a refusé l'opération (raison \(r)).")
        case .failed(let why): return why.prefix(1).uppercased() + String(why.dropFirst())
        }
    }
}

enum OrganizerPayload {
    static let pageSize = 16
    static let maxColors = 64
    /// Opération 10 : 16 noms au plus par commande, 64 octets UTF-8 au plus chacun (script v12 ; 32 avant).
    static let maxNames = 16
    static let nameBytes = 64

    static func be16(_ n: Int) -> [UInt8] {
        let v = UInt16(clamping: n)
        return [UInt8(v >> 8), UInt8(v & 0xFF)]
    }

    static func list(_ kind: ItemKind, start: Int) -> [UInt8] { [2, kind.rawValue] + be16(start) }

    static func audition(channel: Int, note: UInt8, velocity: UInt8) -> [UInt8] {
        [3] + be16(channel) + [min(note, 127), min(velocity, 127)]
    }

    /// Une commande par paquet de 64 couleurs au plus.
    static func setColors(_ kind: ItemKind, _ colors: [(index: Int, color: RGBColor)]) -> [[UInt8]] {
        stride(from: 0, to: colors.count, by: maxColors).map { from in
            let chunk = colors[from..<min(from + maxColors, colors.count)]
            return [4, kind.rawValue, UInt8(chunk.count)] + chunk.flatMap { be16($0.index) + [$0.color.r, $0.color.g, $0.color.b] }
        }
    }

    static func selectOne(_ kind: ItemKind, _ index: Int) -> [UInt8] { [5, kind.rawValue] + be16(index) }
    /// `pattern` : 1 = le premier pattern de FL ; nil : celui qui est ouvert (script v11 pour le pattern).
    static func playSolo(_ channel: Int, pattern: Int? = nil) -> [UInt8] {
        [6] + be16(channel) + (pattern.map(be16) ?? [])
    }
    /// Opération 6 sans canal seul : tous audibles (repérage des sons de chaque pattern).
    static let allChannels = 0xFFFF
    /// Opérations 14 à 16 (script v11) : ce qui joue, les patterns, toute la chanson à une position.
    static func activity(_ kind: ItemKind) -> [UInt8] { [14, kind.rawValue] }
    static let patterns: [UInt8] = [15]
    static func playSong(_ fraction: Double) -> [UInt8] {
        [16] + be16(Int((min(max(fraction, 0), 1) * 1000).rounded()))
    }
    static let stopRestore: [UInt8] = [7]

    static func gradient(first a: RGBColor, last b: RGBColor) -> [UInt8] { [8, a.r, a.g, a.b, b.r, b.g, b.b] }

    static let page: [UInt8] = [9]

    /// Opération 17 (script v12) : les pistes du Mixer vers lesquelles cette piste envoie.
    static func routes(_ track: Int) -> [UInt8] { [17] + be16(track) }

    /// Opération 18 (script v12) : cette page de FL devant (codes de `FLWindow` : 0 Mixer, 1 Channel rack,
    /// 2 Playlist) ; nil pour une autre page.
    static func show(_ window: FLWindow) -> [UInt8]? {
        switch window {
        case .mixer: return [18, 0]
        case .channelRack: return [18, 1]
        case .playlist: return [18, 2]
        default: return nil
        }
    }

    /// Opération 13 (script v7) : bascule le mute, ou le solo, du canal `index` (0 = canal 1 du Channel rack).
    static func toggleChannel(_ index: Int, solo: Bool) -> [UInt8] { [13, solo ? 1 : 0] + be16(index) }

    /// Nom en UTF-8, coupé à `nameBytes` octets sans couper un caractère ; nil s'il est vide.
    static func nameUTF8(_ name: String) -> [UInt8]? {
        var out: [UInt8] = []
        for character in name.trimmingCharacters(in: .whitespacesAndNewlines) {
            let bytes = Array(String(character).utf8)
            guard out.count + bytes.count <= nameBytes else { break }
            out += bytes
        }
        return out.isEmpty ? nil : out
    }

    /// Octets d'une commande qui tiennent dans `FLProtocol.maxDataUnits` unités une fois en 7 bits.
    static let maxCommandBytes = FLProtocol.maxDataUnits * 7 / 8

    /// Une commande par paquet de 16 noms au plus, et qui tient dans une trame ; un nom vide n'est pas envoyé.
    static func setNames(_ kind: ItemKind, _ names: [(index: Int, name: String)]) -> [[UInt8]] {
        var out: [[UInt8]] = []
        var entries: [[UInt8]] = []
        func flush() {
            guard !entries.isEmpty else { return }
            out.append([10, kind.rawValue, UInt8(entries.count)] + entries.flatMap { $0 })
            entries = []
        }
        for item in names {
            guard let bytes = nameUTF8(item.name) else { continue }
            let entry = be16(item.index) + [UInt8(bytes.count)] + bytes
            if entries.count == maxNames || 3 + entries.reduce(0, { $0 + $1.count }) + entry.count > maxCommandBytes {
                flush()
            }
            entries.append(entry)
        }
        flush()
        return out
    }

    static func playTrack(_ index: Int) -> [UInt8] { [11] + be16(index) }

    /// Position dans la chanson (0…1), en pour mille.
    static func seek(_ fraction: Double) -> [UInt8] {
        [12] + be16(Int((min(max(fraction, 0), 1) * 1000).rounded()))
    }

    /// Une page de la réponse de `list`.
    struct Page<Item: Equatable>: Equatable {
        var total: Int
        var start: Int
        var items: [Item]
        var filtered: Bool
    }

    private struct Reader {
        let bytes: [UInt8]
        var at = 0
        mutating func u8() -> Int? {
            guard at < bytes.count else { return nil }
            defer { at += 1 }
            return Int(bytes[at])
        }
        mutating func u16() -> Int? {
            guard let hi = u8(), let lo = u8() else { return nil }
            return hi << 8 | lo
        }
        mutating func color() -> RGBColor? {
            guard let r = u8(), let g = u8(), let b = u8() else { return nil }
            return RGBColor(r: UInt8(r), g: UInt8(g), b: UInt8(b))
        }
        mutating func name() -> String? {
            guard let n = u8(), at + n <= bytes.count else { return nil }
            defer { at += n }
            return String(decoding: bytes[at..<at + n], as: UTF8.self)
        }
    }

    /// En-tête `[genre, total (2), début (2), n, filtré]` : nil si ce n'est pas une réponse de ce genre.
    private static func header(_ r: inout Reader, kind: ItemKind) -> (total: Int, start: Int, n: Int, filtered: Bool)? {
        guard r.u8() == Int(kind.rawValue), let total = r.u16(), let start = r.u16(), let n = r.u8(),
              let filtered = r.u8(), n <= pageSize, start + n <= total else { return nil }
        return (total, start, n, filtered != 0)
    }

    static func decodeChannels(_ bytes: [UInt8]) -> Page<ChannelInfo>? {
        var r = Reader(bytes: bytes)
        guard let h = header(&r, kind: .channels) else { return nil }
        var items: [ChannelInfo] = []
        for i in 0..<h.n {
            guard let type = r.u8(), let fx = r.u16(), let color = r.color(), let name = r.name() else { return nil }
            items.append(ChannelInfo(index: h.start + i, type: type, mixerTrack: fx, color: color, name: name))
        }
        guard r.at == bytes.count else { return nil }
        return Page(total: h.total, start: h.start, items: items, filtered: h.filtered)
    }

    /// Réponse de l'opération 9 : le code de la page devant.
    static func decodePage(_ bytes: [UInt8]) -> FLWindow? {
        guard bytes.count == 1 else { return nil }
        return FLWindow(code: bytes[0])
    }

    /// Réponse de l'opération 11 : la longueur de la chanson en mesures (0 si FL ne la donne pas).
    static func decodeBars(_ bytes: [UInt8]) -> Int? {
        guard bytes.count == 2 else { return nil }
        return Int(bytes[0]) << 8 | Int(bytes[1])
    }

    /// Réponse de l'opération 14 : `[genre, n (2), bits]` → index des éléments qui jouent ; nil si illisible.
    static func decodeActivity(_ bytes: [UInt8], kind: ItemKind) -> Set<Int>? {
        guard bytes.count >= 3, bytes[0] == kind.rawValue else { return nil }
        let n = Int(bytes[1]) << 8 | Int(bytes[2])
        guard bytes.count == 3 + (n + 7) / 8 else { return nil }
        var out = Set<Int>()
        for i in 0..<n where bytes[3 + i / 8] & (1 << UInt8(i % 8)) != 0 { out.insert(i) }
        return out
    }

    /// Réponse de l'opération 15 : nombre de patterns et pattern ouvert.
    static func decodePatterns(_ bytes: [UInt8]) -> (count: Int, current: Int)? {
        guard bytes.count == 4 else { return nil }
        return (Int(bytes[0]) << 8 | Int(bytes[1]), Int(bytes[2]) << 8 | Int(bytes[3]))
    }

    static func decodePlaylist(_ bytes: [UInt8]) -> Page<PlaylistTrackInfo>? {
        var r = Reader(bytes: bytes)
        guard let h = header(&r, kind: .playlist) else { return nil }
        var items: [PlaylistTrackInfo] = []
        for i in 0..<h.n {
            guard let selected = r.u8(), let color = r.color(), let name = r.name() else { return nil }
            items.append(PlaylistTrackInfo(index: h.start + i, selected: selected != 0, color: color, name: name))
        }
        guard r.at == bytes.count else { return nil }
        return Page(total: h.total, start: h.start, items: items, filtered: h.filtered)
    }

    static func decodePatternList(_ bytes: [UInt8]) -> Page<PatternInfo>? {
        var r = Reader(bytes: bytes)
        guard let h = header(&r, kind: .patterns) else { return nil }
        var items: [PatternInfo] = []
        for i in 0..<h.n {
            guard let color = r.color(), let name = r.name() else { return nil }
            items.append(PatternInfo(index: h.start + i, color: color, name: name))
        }
        guard r.at == bytes.count else { return nil }
        return Page(total: h.total, start: h.start, items: items, filtered: h.filtered)
    }

    /// Réponse de l'opération 17 : `[piste (2), n, (destination (2)) × n]` ; nil si illisible ou d'une autre piste.
    static func decodeRoutes(_ bytes: [UInt8], track: Int) -> [Int]? {
        var r = Reader(bytes: bytes)
        guard r.u16() == track, let n = r.u8() else { return nil }
        var out: [Int] = []
        for _ in 0..<n {
            guard let d = r.u16() else { return nil }
            out.append(d)
        }
        return r.at == bytes.count ? out : nil
    }

    static func decodeMixer(_ bytes: [UInt8]) -> Page<MixerTrackInfo>? {
        var r = Reader(bytes: bytes)
        guard let h = header(&r, kind: .mixer) else { return nil }
        var items: [MixerTrackInfo] = []
        for i in 0..<h.n {
            guard let color = r.color(), let name = r.name() else { return nil }
            items.append(MixerTrackInfo(index: h.start + i, color: color, name: name))
        }
        guard r.at == bytes.count else { return nil }
        return Page(total: h.total, start: h.start, items: items, filtered: h.filtered)
    }
}

/// Ce dont l'Organiser a besoin de FL (un faux dans les tests).
protocol OrganizerLink: AnyObject {
    /// Page de FL devant, vérifiée pendant l'application (déplacements, icônes).
    var window: FLWindow { get }
    /// Page de FL devant, demandée au script (opération 9) ; script v5 : celle reçue au réveil (CC 117).
    func page() throws -> FLWindow
    /// Canaux affichés par le Channel rack : ceux du groupe choisi s'il en montre un (« Unsorted »…), avec les index
    /// que les autres opérations attendent.
    func listChannels() throws -> [ChannelInfo]
    func listMixer() throws -> [MixerTrackInfo]
    /// Les `limit` premières pistes de la Playlist (toutes si elle en a moins).
    func listPlaylist(limit: Int) throws -> [PlaylistTrackInfo]
    /// Tous les patterns (script v12 : un script plus ancien répond `outdatedScript`).
    func listPatterns() throws -> [PatternInfo]
    /// Pistes du Mixer vers lesquelles cette piste envoie (sans le Master).
    func routes(from track: Int) throws -> [Int]
    /// Cette page de FL devant (Channel rack, Mixer, Playlist), comme ses raccourcis F6, F9, F5.
    func show(_ window: FLWindow) throws
    func setColors(_ kind: ItemKind, _ colors: [(index: Int, color: RGBColor)]) throws
    func setNames(_ kind: ItemKind, _ names: [(index: Int, name: String)]) throws
    func selectOne(_ kind: ItemKind, _ index: Int) throws
    /// Ce canal seul audible, dans ce pattern (1 = le premier ; nil : celui qui est ouvert) ;
    /// `OrganizerPayload.allChannels` : tous audibles.
    func playSolo(_ channel: Int, pattern: Int?) throws
    /// Nombre de patterns et pattern ouvert (script v11).
    func patterns() throws -> (count: Int, current: Int)
    /// Canaux affichés dont une note joue en ce moment, d'après FL (script v11, API 9).
    func activeChannels() throws -> Set<Int>
    /// Pistes de la Playlist dont un clip passe sous la tête de lecture (index 0 = piste 1).
    func activeTracks() throws -> Set<Int>
    /// Toute la chanson jouée à cette position (0…1), tout audible (pistes et sons coupés compris) ; renvoie sa
    /// longueur en mesures (0 : inconnue).
    func playSong(at fraction: Double) throws -> Int
    /// Piste de la Playlist seule audible (tous les sons du Channel rack audibles), chanson jouée depuis son début ;
    /// renvoie sa longueur en mesures (0 si inconnue).
    func playTrack(_ index: Int) throws -> Int
    /// Position (0…1) de la chanson pendant l'écoute d'une piste seule.
    func seek(_ fraction: Double) throws
    /// Toujours sans erreur : FL est remis comme avant autant que possible (appelé aussi après une erreur).
    func stopRestore()
    func audition(_ channel: Int, note: UInt8, velocity: UInt8) throws
}

extension OrganizerLink {
    func playSolo(_ channel: Int) throws { try playSolo(channel, pattern: nil) }
}

/// Opérations envoyées une par une, 60 ms au moins entre deux (le script refuse plus de 20 trames par seconde).
final class RequestOrganizerLink: OrganizerLink {
    static let minInterval: TimeInterval = 0.06
    /// Garde-fou : 4 096 éléments au plus (256 pages).
    static let maxPages = 256

    private let request: ([UInt8]) -> RequestReply
    private let currentWindow: () -> FLWindow
    private let sleep: (TimeInterval) -> Void
    private var last: Date?
    /// Une opération 9 à 12 a déjà répondu : le script est le v6 (un refus 5 est alors une vraie donnée refusée).
    private var newOpsSeen = false

    init(request: @escaping ([UInt8]) -> RequestReply, window: @escaping () -> FLWindow,
         sleep: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }) {
        self.request = request
        currentWindow = window
        self.sleep = sleep
    }

    /// Par le lien de l'appli.
    static func live() -> RequestOrganizerLink {
        RequestOrganizerLink(request: { MIDILink.shared.runRequest($0) },
                             window: { MIDILink.shared.core.routingView().window })
    }

    /// Demandée au script à chaque fois (audit : celle reçue par le lien pouvait dater d'avant son sommeil et laisser
    /// passer ⌥↑ vers une autre page) ; celle reçue par le lien seulement si le script ne répond pas.
    var window: FLWindow {
        (try? page()) ?? currentWindow()
    }

    /// Script v5 (l'opération 9 lui est inconnue : refus 5) : la page que le script envoie juste après son réveil,
    /// attendue 0,6 s au plus.
    func page() throws -> FLWindow {
        do {
            guard let window = OrganizerPayload.decodePage(try send(OrganizerPayload.page)) else {
                throw OrganizerError.failed(String(localized: "page de FL illisible"))
            }
            newOpsSeen = true
            return window
        } catch OrganizerError.refused(5) {
            for _ in 0..<12 {
                let routed = currentWindow()
                if routed != .unknown { return routed }
                sleep(0.05)
            }
            throw OrganizerError.outdatedScript
        }
    }

    @discardableResult
    private func send(_ bytes: [UInt8]) throws -> [UInt8] {
        if let last {
            let wait = Self.minInterval - Date().timeIntervalSince(last)
            if wait > 0 { sleep(wait) }
        }
        defer { last = Date() }
        switch request(bytes) {
        case .answered(let answer): return answer
        case .refused(let reason): throw OrganizerError.refused(reason)
        case .failed(let why): throw why == LinkCore.noResponse ? OrganizerError.noResponse : OrganizerError.failed(why)
        }
    }

    func listChannels() throws -> [ChannelInfo] {
        var all: [ChannelInfo] = []
        for _ in 0..<Self.maxPages {
            guard let page = OrganizerPayload.decodeChannels(try send(OrganizerPayload.list(.channels, start: all.count))),
                  page.start == all.count else { throw OrganizerError.failed(String(localized: "liste des canaux illisible")) }
            all += page.items
            if all.count >= page.total || page.items.isEmpty { return all }
        }
        throw OrganizerError.failed(String(localized: "trop de canaux"))
    }

    func listMixer() throws -> [MixerTrackInfo] {
        var all: [MixerTrackInfo] = []
        for _ in 0..<Self.maxPages {
            guard let page = OrganizerPayload.decodeMixer(try send(OrganizerPayload.list(.mixer, start: all.count))),
                  page.start == all.count else { throw OrganizerError.failed(String(localized: "liste du Mixer illisible")) }
            all += page.items
            if all.count >= page.total || page.items.isEmpty { return all }
        }
        throw OrganizerError.failed(String(localized: "trop de pistes"))
    }

    func listPlaylist(limit: Int) throws -> [PlaylistTrackInfo] {
        var all: [PlaylistTrackInfo] = []
        for _ in 0..<Self.maxPages {
            guard let page = OrganizerPayload.decodePlaylist(try send(OrganizerPayload.list(.playlist, start: all.count))),
                  page.start == all.count else { throw OrganizerError.failed(String(localized: "liste de la Playlist illisible")) }
            all += page.items
            if all.count >= min(page.total, limit) || page.items.isEmpty { return Array(all.prefix(limit)) }
        }
        throw OrganizerError.failed(String(localized: "trop de pistes"))
    }

    func listPatterns() throws -> [PatternInfo] {
        var all: [PatternInfo] = []
        for _ in 0..<Self.maxPages {
            let answer = try v11 { try send(OrganizerPayload.list(.patterns, start: all.count)) }
            guard let page = OrganizerPayload.decodePatternList(answer), page.start == all.count else {
                throw OrganizerError.failed(String(localized: "liste des patterns illisible"))
            }
            all += page.items
            if all.count >= page.total || page.items.isEmpty { return all }
        }
        throw OrganizerError.failed(String(localized: "trop de patterns"))
    }

    func routes(from track: Int) throws -> [Int] {
        let answer = try v11 { try send(OrganizerPayload.routes(track)) }
        guard let routes = OrganizerPayload.decodeRoutes(answer, track: track) else {
            throw OrganizerError.failed(String(localized: "réponse de FL illisible"))
        }
        return routes
    }

    func show(_ window: FLWindow) throws {
        guard let bytes = OrganizerPayload.show(window) else { return }
        try v11 { try send(bytes) }
    }

    func setColors(_ kind: ItemKind, _ colors: [(index: Int, color: RGBColor)]) throws {
        for chunk in OrganizerPayload.setColors(kind, colors) { try send(chunk) }
    }

    func setNames(_ kind: ItemKind, _ names: [(index: Int, name: String)]) throws {
        for chunk in OrganizerPayload.setNames(kind, names) { try newOps { try send(chunk) } }
    }

    func playTrack(_ index: Int) throws -> Int {
        let answer = try newOps { try send(OrganizerPayload.playTrack(index)) }
        guard let bars = OrganizerPayload.decodeBars(answer) else { throw OrganizerError.failed(String(localized: "réponse de FL illisible")) }
        return bars
    }

    func seek(_ fraction: Double) throws { try newOps { try send(OrganizerPayload.seek(fraction)) } }

    /// Opérations 10 à 12 : un script v5 les refuse (5) sans rien faire ; FL doit charger la nouvelle version.
    @discardableResult
    private func newOps<T>(_ body: () throws -> T) throws -> T {
        do {
            let out = try body()
            newOpsSeen = true
            return out
        } catch OrganizerError.refused(5) where !newOpsSeen {
            throw OrganizerError.outdatedScript
        }
    }

    func selectOne(_ kind: ItemKind, _ index: Int) throws { try send(OrganizerPayload.selectOne(kind, index)) }

    func playSolo(_ channel: Int, pattern: Int?) throws {
        if pattern == nil {
            try send(OrganizerPayload.playSolo(channel))
        } else {
            try v11 { try send(OrganizerPayload.playSolo(channel, pattern: pattern)) }
        }
    }

    func patterns() throws -> (count: Int, current: Int) {
        let answer = try v11 { try send(OrganizerPayload.patterns) }
        guard let info = OrganizerPayload.decodePatterns(answer) else { throw OrganizerError.failed(String(localized: "réponse de FL illisible")) }
        return info
    }

    func activeChannels() throws -> Set<Int> { try activity(.channels) }
    func activeTracks() throws -> Set<Int> { try activity(.playlist) }

    private func activity(_ kind: ItemKind) throws -> Set<Int> {
        let answer = try v11 { try send(OrganizerPayload.activity(kind)) }
        guard let set = OrganizerPayload.decodeActivity(answer, kind: kind) else {
            throw OrganizerError.failed(String(localized: "réponse de FL illisible"))
        }
        return set
    }

    func playSong(at fraction: Double) throws -> Int {
        let answer = try v11 { try send(OrganizerPayload.playSong(fraction)) }
        guard let bars = OrganizerPayload.decodeBars(answer) else { throw OrganizerError.failed(String(localized: "réponse de FL illisible")) }
        return bars
    }

    /// Opérations du script v11 et v12 : un script plus ancien les refuse (5) ; FL doit charger la nouvelle version.
    @discardableResult
    private func v11<T>(_ body: () throws -> T) throws -> T {
        do {
            return try body()
        } catch OrganizerError.refused(5) {
            throw OrganizerError.outdatedScript
        }
    }

    func stopRestore() {
        // Deux essais : c'est ce qui remet les sourdines de l'utilisateur.
        for _ in 0..<2 {
            if (try? send(OrganizerPayload.stopRestore)) != nil { return }
        }
    }

    func audition(_ channel: Int, note: UInt8, velocity: UInt8) throws {
        try send(OrganizerPayload.audition(channel: channel, note: note, velocity: velocity))
    }
}
