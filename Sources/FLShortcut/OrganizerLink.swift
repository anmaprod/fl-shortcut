// Organiser : le lien avec FL pour les opérations 2 à 8 du script v5 (PROTOCOL.md §8). Les octets de chaque
// opération et le décodage des listes sont purs (testés) ; `RequestOrganizerLink` les envoie par le lien, à 20 par
// seconde au plus comme le veut le script. Les noms des sons servent à l'aperçu seulement : jamais journalisés.
import Foundation

/// Genre d'éléments de FL : canaux du Channel rack ou pistes du Mixer.
enum ItemKind: UInt8 {
    case channels = 1, mixer = 2
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
}

/// Refus de FL (raison du CC 116) ou panne du lien, avec un message pour l'utilisateur.
enum OrganizerError: Error, Equatable {
    case refused(Int)
    case failed(String)

    var message: String {
        switch self {
        case .refused(1): return "Ouvre le Channel rack ou le Mixer de FL, puis relance Organiser."
        case .refused(2): return "Sélectionne au moins un élément dans FL."
        case .refused(4): return "FL joue : appuie sur Stop, puis relance Organiser."
        case .refused(6): return "Ta version de FL ne permet pas cette étape : mets FL Studio à jour."
        case .refused(7): return "Sélectionne au moins 2 pistes pour un dégradé."
        case .refused(let r): return "FL a refusé l'opération (raison \(r))."
        case .failed(let why): return why
        }
    }
}

enum OrganizerPayload {
    static let pageSize = 16
    static let maxColors = 64

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
    static func playSolo(_ channel: Int) -> [UInt8] { [6] + be16(channel) }
    static let stopRestore: [UInt8] = [7]

    static func gradient(first a: RGBColor, last b: RGBColor) -> [UInt8] { [8, a.r, a.g, a.b, b.r, b.g, b.b] }

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
    /// Page de FL devant (CC 117).
    var window: FLWindow { get }
    func listChannels() throws -> (channels: [ChannelInfo], filtered: Bool)
    func listMixer() throws -> [MixerTrackInfo]
    func setColors(_ kind: ItemKind, _ colors: [(index: Int, color: RGBColor)]) throws
    func selectOne(_ kind: ItemKind, _ index: Int) throws
    func playSolo(_ channel: Int) throws
    /// Toujours sans erreur : FL est remis comme avant autant que possible (appelé aussi après une erreur).
    func stopRestore()
    func audition(_ channel: Int, note: UInt8, velocity: UInt8) throws
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

    var window: FLWindow { currentWindow() }

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
        case .failed(let why): throw OrganizerError.failed(why)
        }
    }

    func listChannels() throws -> (channels: [ChannelInfo], filtered: Bool) {
        var all: [ChannelInfo] = []
        var filtered = false
        for _ in 0..<Self.maxPages {
            guard let page = OrganizerPayload.decodeChannels(try send(OrganizerPayload.list(.channels, start: all.count))),
                  page.start == all.count else { throw OrganizerError.failed("liste des canaux illisible") }
            all += page.items
            filtered = filtered || page.filtered
            if all.count >= page.total || page.items.isEmpty { return (all, filtered) }
        }
        throw OrganizerError.failed("trop de canaux")
    }

    func listMixer() throws -> [MixerTrackInfo] {
        var all: [MixerTrackInfo] = []
        for _ in 0..<Self.maxPages {
            guard let page = OrganizerPayload.decodeMixer(try send(OrganizerPayload.list(.mixer, start: all.count))),
                  page.start == all.count else { throw OrganizerError.failed("liste du Mixer illisible") }
            all += page.items
            if all.count >= page.total || page.items.isEmpty { return all }
        }
        throw OrganizerError.failed("trop de pistes")
    }

    func setColors(_ kind: ItemKind, _ colors: [(index: Int, color: RGBColor)]) throws {
        for chunk in OrganizerPayload.setColors(kind, colors) { try send(chunk) }
    }

    func selectOne(_ kind: ItemKind, _ index: Int) throws { try send(OrganizerPayload.selectOne(kind, index)) }
    func playSolo(_ channel: Int) throws { try send(OrganizerPayload.playSolo(channel)) }

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
