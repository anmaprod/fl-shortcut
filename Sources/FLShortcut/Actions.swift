// Audit : SEC-05 (liste blanche d'ids), audit 04 (versions minimales, « Disponible à partir de FL X »),
//         PROTOCOL.md §6 (table des 38 actions, ids figés).
import Foundation

/// Une action exécutée par le script FL. Les ids sont ceux de PROTOCOL.md §6 : ne jamais renuméroter.
struct FLActionInfo: Identifiable, Hashable {
    enum Category: String, CaseIterable {
        case composition = "Composition"
        case recording = "Enregistrement"
        case mix = "Mix"
        case navigation = "Navigation"
    }

    let id: Int
    /// Clé stable du protocole (« play », « save »…), utilisée aussi pour l'import de profils.
    let key: String
    let label: String
    let category: Category
    /// Version minimale de FL Studio (texte affiché et comparé à la version lue dans le bundle).
    let minFL: String
}

enum FLActions {
    /// Version minimale de FL pour le scripting Python (audit 04 §0).
    static let pythonMinFL = "20.7"

    static let all: [FLActionInfo] = [
        FLActionInfo(id: 1, key: "play", label: "Lecture / Pause", category: .recording, minFL: "20.7"),
        FLActionInfo(id: 2, key: "stop", label: "Stop", category: .recording, minFL: "20.7"),
        FLActionInfo(id: 3, key: "rec", label: "Lancer le REC", category: .recording, minFL: "20.7"),
        FLActionInfo(id: 4, key: "metro", label: "Métronome", category: .recording, minFL: "20.7"),
        FLActionInfo(id: 5, key: "count", label: "Décompte", category: .recording, minFL: "20.7"),
        FLActionInfo(id: 6, key: "loop", label: "Enregistrement en boucle", category: .recording, minFL: "20.7"),
        FLActionInfo(id: 7, key: "wait", label: "Attendre une note", category: .recording, minFL: "20.7"),
        FLActionInfo(id: 8, key: "marker", label: "Poser un marqueur", category: .recording, minFL: "20.7"),
        FLActionInfo(id: 9, key: "arm", label: "Armer la piste (Mixer sélectionnée)", category: .recording, minFL: "20.7"),
        FLActionInfo(id: 10, key: "tap", label: "Tap tempo", category: .composition, minFL: "20.7"),
        FLActionInfo(id: 11, key: "newpat", label: "Nouveau pattern + Piano Roll", category: .composition, minFL: "20.7"),
        FLActionInfo(id: 12, key: "clone", label: "Cloner le pattern", category: .composition, minFL: "21.0.3"),
        FLActionInfo(id: 13, key: "pnext", label: "Pattern suivant", category: .composition, minFL: "20.7"),
        FLActionInfo(id: 14, key: "pprev", label: "Pattern précédent", category: .composition, minFL: "20.7"),
        FLActionInfo(id: 15, key: "chnext", label: "Instrument suivant", category: .composition, minFL: "20.7"),
        FLActionInfo(id: 16, key: "chprev", label: "Instrument précédent", category: .composition, minFL: "20.7"),
        FLActionInfo(id: 17, key: "snap", label: "Grille suivante", category: .composition, minFL: "20.7"),
        FLActionInfo(id: 18, key: "quant", label: "Quantize rapide", category: .composition, minFL: "20.8"),
        FLActionInfo(id: 19, key: "presetnext", label: "Preset suivant", category: .composition, minFL: "20.8.1"),
        FLActionInfo(id: 20, key: "presetprev", label: "Preset précédent", category: .composition, minFL: "20.8.1"),
        FLActionInfo(id: 21, key: "mute", label: "Mute piste Mixer sélectionnée", category: .mix, minFL: "20.7"),
        FLActionInfo(id: 22, key: "solo", label: "Solo piste Mixer sélectionnée", category: .mix, minFL: "20.7"),
        FLActionInfo(id: 23, key: "unsolo", label: "Retirer tous les solos", category: .mix, minFL: "20.7"),
        FLActionInfo(id: 24, key: "bypass", label: "Bypass des effets de la piste", category: .mix, minFL: "20.9.1"),
        FLActionInfo(id: 25, key: "mono", label: "Master en mono", category: .mix, minFL: "20.8.2"),
        FLActionInfo(id: 26, key: "trnext", label: "Piste Mixer suivante", category: .mix, minFL: "20.7"),
        FLActionInfo(id: 27, key: "trprev", label: "Piste Mixer précédente", category: .mix, minFL: "20.7"),
        FLActionInfo(id: 28, key: "volup", label: "Volume piste +0,5 dB", category: .mix, minFL: "20.7"),
        FLActionInfo(id: 29, key: "voldn", label: "Volume piste −0,5 dB", category: .mix, minFL: "20.7"),
        FLActionInfo(id: 30, key: "pl", label: "Ouvrir la Playlist", category: .navigation, minFL: "20.7"),
        FLActionInfo(id: 31, key: "cr", label: "Ouvrir le Channel Rack", category: .navigation, minFL: "20.7"),
        FLActionInfo(id: 32, key: "pr", label: "Ouvrir le Piano Roll", category: .navigation, minFL: "20.7"),
        FLActionInfo(id: 33, key: "mx", label: "Ouvrir le Mixer", category: .navigation, minFL: "20.7"),
        FLActionInfo(id: 34, key: "br", label: "Ouvrir le Browser", category: .navigation, minFL: "20.7"),
        FLActionInfo(id: 35, key: "plmx", label: "Playlist ↔ Mixer", category: .navigation, minFL: "20.7"),
        FLActionInfo(id: 36, key: "undo", label: "Annuler", category: .navigation, minFL: "20.7"),
        FLActionInfo(id: 37, key: "redo", label: "Rétablir", category: .navigation, minFL: "20.7"),
        FLActionInfo(id: 38, key: "save", label: "Sauvegarder", category: .navigation, minFL: "20.7"),
    ]

    private static let byID: [Int: FLActionInfo] = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    private static let byKey: [String: FLActionInfo] = Dictionary(uniqueKeysWithValues: all.map { ($0.key, $0) })

    static func info(_ id: Int) -> FLActionInfo? { byID[id] }
    static func isKnown(_ id: Int) -> Bool { byID[id] != nil }
    static func id(forKey key: String) -> Int? { byKey[key]?.id }

    /// Correspondance des actions du format v1 (FLAction.rawValue) vers les ids v2.
    /// `loopMode` (Pattern ↔ Song) et `nextWindow` n'ont pas d'équivalent en v2 : ils sont conservés
    /// comme actions inconnues, désactivées (REL-01).
    static let v1Names: [String: Int] = [
        "playPause": 1, "stop": 2, "record": 3, "undo": 36, "redo": 37,
        "showPlaylist": 30, "showMixer": 33, "showChannelRack": 31, "showPianoRoll": 32, "showBrowser": 34,
        "togglePlaylistMixer": 35, "muteSelected": 21, "soloSelected": 22, "metronome": 4,
        "nextPattern": 13, "prevPattern": 14,
    ]
}

/// Version de FL Studio lue dans le bundle (`CFBundleShortVersionString`), audit 04 §3 et §8.2.
struct FLVersion: Comparable, Hashable, CustomStringConvertible {
    let parts: [Int]

    /// Accepte « 21.0.3 », « 2024.1.0 », « 24.1.1.4234 »… Les années (2024) deviennent 24.
    init?(_ text: String) {
        var out: [Int] = []
        for piece in text.split(separator: ".").prefix(4) {
            let digits = piece.prefix { $0.isNumber }
            guard !digits.isEmpty, let n = Int(digits) else { break }
            out.append(n)
        }
        guard !out.isEmpty else { return nil }
        if out[0] >= 2000 { out[0] -= 2000 }
        parts = out
    }

    var description: String { parts.map(String.init).joined(separator: ".") }

    private func component(_ i: Int) -> Int { i < parts.count ? parts[i] : 0 }

    static func < (a: FLVersion, b: FLVersion) -> Bool {
        let n = max(a.parts.count, b.parts.count)
        for i in 0..<n where a.component(i) != b.component(i) {
            return a.component(i) < b.component(i)
        }
        return false
    }

    static func == (a: FLVersion, b: FLVersion) -> Bool { !(a < b) && !(b < a) }

    func hash(into hasher: inout Hasher) {
        var trimmed = parts
        while trimmed.count > 1, trimmed.last == 0 { trimmed.removeLast() }
        hasher.combine(trimmed)
    }

    var supportsPython: Bool {
        guard let min = FLVersion(FLActions.pythonMinFL) else { return false }
        return self >= min
    }
}

/// Masque de capacités du HELLO (PROTOCOL.md §3) : bit `id-1` = action `id` disponible.
struct CapabilityMask: Equatable {
    var bits: UInt64

    init(bits: UInt64) { self.bits = bits & ((1 << 42) - 1) }

    /// `values[k]` = valeur du CC 90+k, soit `(mask >> 7k) & 0x7F`.
    init(ccValues values: [UInt8]) {
        var b: UInt64 = 0
        for (k, v) in values.prefix(6).enumerated() {
            b |= UInt64(v & 0x7F) << (7 * UInt64(k))
        }
        self.init(bits: b)
    }

    func contains(_ id: Int) -> Bool {
        guard (1...42).contains(id) else { return false }
        return bits & (1 << UInt64(id - 1)) != 0
    }

    var ccValues: [UInt8] {
        (0..<6).map { UInt8(truncatingIfNeeded: (bits >> (7 * UInt64($0))) & 0x7F) }
    }
}

/// Disponibilité d'une action, pour griser l'éditeur (audit 04 §8.2).
enum ActionAvailability: Equatable {
    case available
    case unverified                       // ni handshake ni version connue
    case unavailable(reason: String)

    var isUsable: Bool {
        if case .unavailable = self { return false }
        return true
    }
}

enum AvailabilityResolver {
    /// Le masque du script fait foi ; à défaut, la version lue dans le bundle de FL.
    static func availability(of id: Int, caps: CapabilityMask?, flVersion: FLVersion?) -> ActionAvailability {
        guard let info = FLActions.info(id) else { return .unavailable(reason: "Action inconnue") }
        let message = "Disponible à partir de FL \(info.minFL)"
        if let caps {
            if caps.contains(id) { return .available }
            if caps.bits == 0 { return .unavailable(reason: "Le script FL n'a pas de clé : réinstalle-le") }
            return .unavailable(reason: message)
        }
        guard let flVersion else { return .unverified }
        guard flVersion.supportsPython else {
            return .unavailable(reason: "Les actions FL demandent FL Studio \(FLActions.pythonMinFL) ou plus récent")
        }
        if let min = FLVersion(info.minFL), flVersion < min { return .unavailable(reason: message) }
        return .available
    }
}
