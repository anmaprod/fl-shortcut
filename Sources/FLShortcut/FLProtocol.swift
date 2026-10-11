// Audit : SEC-01 (trames authentifiées HMAC-SHA256 tronqué 28 bits, nonce de session, anti-rejeu côté script),
//         SEC-10 (PING limité côté appli, rejets → resynchronisation bornée), REL-06 (statut du lien),
//         audit 04 §8.2 (masque de capacités du HELLO). Contrat : PROTOCOL.md v2 (§3, §4, §5).
// Ce fichier est pur (Foundation + CryptoKit) : entièrement testable sans CoreMIDI.
import CryptoKit
import Foundation

/// Constantes du protocole v2. Doivent rester identiques à `Resources/device_FLShortcut.py`.
enum FLProtocol {
    static let version = 2
    /// Canal 16 (0-indexé : 15), statut Control Change `0xBF`.
    static let channel: UInt8 = 15
    static let statusCC: UInt8 = 0xB0 | 15

    // Appli → FL
    static let ccPing: UInt8 = 103
    static let ccFrameFirst: UInt8 = 104          // 104…111 : seq (3), action (1), MAC (4)
    // FL → appli
    static let ccCapsFirst: UInt8 = 90            // 90…95 : masque de capacités (6 × 7 bits)
    static let capsCount = 6
    static let ccWindow: UInt8 = 117
    static let ccHeartbeat: UInt8 = 118
    static let ccAck: UInt8 = 119
    static let ccHello: UInt8 = 120               // 1 = début, 127 = fin
    static let ccNonceFirst: UInt8 = 121          // 121…124
    static let ccAPI: UInt8 = 125
    static let ccProto: UInt8 = 126
    static let helloStart: UInt8 = 1
    static let helloEnd: UInt8 = 127

    static let seqMax: UInt32 = (1 << 21) - 1
    static let keyLength = 16
    static let maxActionID = 42
    /// « Relié » : HELLO reçu et battement depuis moins de 6 s (PROTOCOL.md §5).
    static let aliveTimeout: TimeInterval = 6
    /// PING au lancement puis après 6 s sans battement ; le script ignore plus de 4 PING/s.
    static let pingInterval: TimeInterval = 6
    /// Plafond des PING sans réponse (FL ouvert mais lien pas activé dans ses réglages MIDI).
    static let maxPingInterval: TimeInterval = 60
    static let resyncPingInterval: TimeInterval = 2

    /// Les 3 octets de 7 bits de la séquence (poids fort d'abord).
    static func seqBytes(_ seq: UInt32) -> [UInt8] {
        [UInt8((seq >> 14) & 0x7F), UInt8((seq >> 7) & 0x7F), UInt8(seq & 0x7F)]
    }

    /// 4 premiers octets du HMAC en big-endian, décalés de 4 bits (28 bits), découpés en 4 × 7 bits.
    static func mac28(_ digest: [UInt8]) -> [UInt8] {
        precondition(digest.count >= 4)
        let v = (UInt32(digest[0]) << 24 | UInt32(digest[1]) << 16 | UInt32(digest[2]) << 8 | UInt32(digest[3])) >> 4
        return [UInt8((v >> 21) & 0x7F), UInt8((v >> 14) & 0x7F), UInt8((v >> 7) & 0x7F), UInt8(v & 0x7F)]
    }

    /// Clé en 32 caractères hexadécimaux minuscules (format injecté dans le script).
    static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}

/// Un Control Change sur le canal 16.
struct CCMessage: Equatable, Hashable {
    let cc: UInt8
    let value: UInt8

    var bytes: [UInt8] { [FLProtocol.statusCC, cc & 0x7F, value & 0x7F] }

    static let ping = CCMessage(cc: FLProtocol.ccPing, value: 1)
    /// Réveil bref (macros) : le script se rendort tout seul 8 s après le dernier message (PROTOCOL.md §4).
    static let pingBrief = CCMessage(cc: FLProtocol.ccPing, value: 2)
}

/// Calcul du MAC des trames (CryptoKit `HMAC<SHA256>`).
struct FrameSigner {
    private let key: SymmetricKey

    init?(keyBytes: [UInt8]) {
        guard keyBytes.count == FLProtocol.keyLength else { return nil }
        key = SymmetricKey(data: keyBytes)
    }

    /// Message signé : nonce[4] ‖ seq_hi ‖ seq_mid ‖ seq_lo ‖ action.
    static func message(nonce: [UInt8], seq: UInt32, action: UInt8) -> [UInt8] {
        nonce + FLProtocol.seqBytes(seq) + [action]
    }

    func mac(nonce: [UInt8], seq: UInt32, action: UInt8) -> [UInt8] {
        let msg = Self.message(nonce: nonce, seq: seq, action: action)
        let code = HMAC<SHA256>.authenticationCode(for: msg, using: key)
        let digest = code.withUnsafeBytes { Array($0) }
        return FLProtocol.mac28(digest)
    }
}

enum FrameEncoder {
    /// Trame de 8 CC (104…111) ou `nil` si un paramètre sort du protocole.
    static func frame(seq: UInt32, action: Int, nonce: [UInt8], signer: FrameSigner) -> [CCMessage]? {
        guard (1...FLProtocol.seqMax).contains(seq),
              (1...FLProtocol.maxActionID).contains(action),
              nonce.count == 4, nonce.allSatisfy({ $0 < 128 }) else { return nil }
        let a = UInt8(action)
        let values = FLProtocol.seqBytes(seq) + [a] + signer.mac(nonce: nonce, seq: seq, action: a)
        return values.enumerated().map { CCMessage(cc: FLProtocol.ccFrameFirst + UInt8($0.offset), value: $0.element) }
    }
}

/// Fenêtre FL active (CC 117).
enum FLWindow: Int, Equatable, CaseIterable {
    case mixer = 0, channelRack = 1, playlist = 2, pianoRoll = 3, browser = 4, plugin = 5, unknown = 127

    init(code: UInt8) { self = FLWindow(rawValue: Int(code)) ?? .unknown }
}

/// Contenu du HELLO (PROTOCOL.md §3).
struct HelloInfo: Equatable {
    var nonce: [UInt8]
    var apiVersion: Int
    var protocolVersion: Int
    var capabilities: CapabilityMask
}

enum IncomingEvent: Equatable {
    case hello(HelloInfo)
    /// HELLO complet mais version de protocole différente de 2.
    case incompatible(protocolVersion: Int)
    case heartbeat
    case window(FLWindow)
    /// id de l'action exécutée, ou 0 si la trame a été rejetée / l'action a échoué.
    case ack(Int)
}

/// Découpe un flux d'octets MIDI en messages (statut courant géré, SysEx et temps réel ignorés).
struct MIDIByteParser {
    private var status: UInt8 = 0
    private var data: [UInt8] = []

    mutating func feed<S: Sequence>(_ bytes: S) -> [(status: UInt8, data1: UInt8, data2: UInt8)] where S.Element == UInt8 {
        var out: [(status: UInt8, data1: UInt8, data2: UInt8)] = []
        for b in bytes {
            if b >= 0xF8 { continue }                       // temps réel : n'interrompt rien
            if b >= 0x80 {
                status = b >= 0xF0 ? 0 : b                  // SysEx / commun : ignoré jusqu'au prochain statut
                data.removeAll(keepingCapacity: true)
                continue
            }
            guard status != 0 else { continue }
            data.append(b)
            let kind = status & 0xF0
            let needed = (kind == 0xC0 || kind == 0xD0) ? 1 : 2
            if data.count == needed {
                out.append((status, data[0], needed == 2 ? data[1] : 0))
                data.removeAll(keepingCapacity: true)
            }
        }
        return out
    }
}

/// Machine à états des messages FL → appli.
struct IncomingDecoder {
    private struct Partial {
        var nonce: [UInt8?] = [nil, nil, nil, nil]
        var api: UInt8?
        var proto: UInt8?
        var caps: [UInt8?] = Array(repeating: nil, count: FLProtocol.capsCount)
    }

    private var partial: Partial?

    mutating func feed(status: UInt8, data1 cc: UInt8, data2 value: UInt8) -> IncomingEvent? {
        guard status == FLProtocol.statusCC, cc < 128, value < 128 else { return nil }
        switch cc {
        case FLProtocol.ccHello:
            if value == FLProtocol.helloStart {
                partial = Partial()
                return nil
            }
            if value == FLProtocol.helloEnd {
                defer { partial = nil }
                return finish()
            }
            partial = nil
            return nil
        case FLProtocol.ccNonceFirst..<(FLProtocol.ccNonceFirst + 4):
            partial?.nonce[Int(cc - FLProtocol.ccNonceFirst)] = value
            return nil
        case FLProtocol.ccAPI:
            partial?.api = value
            return nil
        case FLProtocol.ccProto:
            partial?.proto = value
            return nil
        case FLProtocol.ccCapsFirst..<(FLProtocol.ccCapsFirst + UInt8(FLProtocol.capsCount)):
            partial?.caps[Int(cc - FLProtocol.ccCapsFirst)] = value
            return nil
        case FLProtocol.ccWindow:
            return .window(FLWindow(code: value))
        case FLProtocol.ccHeartbeat:
            return .heartbeat
        case FLProtocol.ccAck:
            return .ack(Int(value))
        default:
            return nil
        }
    }

    private func finish() -> IncomingEvent? {
        guard let p = partial, let api = p.api, let proto = p.proto else { return nil }
        let nonce = p.nonce.compactMap { $0 }
        let caps = p.caps.compactMap { $0 }
        guard nonce.count == 4, caps.count == FLProtocol.capsCount else { return nil }
        guard Int(proto) == FLProtocol.version else { return .incompatible(protocolVersion: Int(proto)) }
        return .hello(HelloInfo(nonce: nonce, apiVersion: Int(api), protocolVersion: Int(proto),
                                capabilities: CapabilityMask(ccValues: caps)))
    }
}

/// Statut affiché (PROTOCOL.md §5).
enum LinkStatus: Equatable {
    case linked          // « Relié »
    case inactive        // « Lien inactif »
    case flClosed        // « FL fermé »

    var label: String {
        switch self {
        case .linked: return "Relié"
        case .inactive: return "Lien inactif"
        case .flClosed: return "FL fermé"
        }
    }

    static func resolve(flRunning: Bool, alive: Bool) -> LinkStatus {
        guard flRunning else { return .flClosed }
        return alive ? .linked : .inactive
    }
}

/// Ce que le tap clavier a besoin de savoir du lien, au moment d'une frappe.
struct LinkRoutingView: Equatable {
    var linked: Bool
    var window: FLWindow
    var capabilities: CapabilityMask?
    var canSign: Bool

    static let offline = LinkRoutingView(linked: false, window: .unknown, capabilities: nil, canSign: false)

    /// Fenêtre connue seulement si le lien est vivant (sinon on ne filtre pas par fenêtre : on laisse passer).
    var knownWindow: FLWindow? { linked && window != .unknown ? window : nil }

    func canRun(_ id: Int) -> Bool {
        linked && canSign && FLActions.isKnown(id) && (capabilities?.contains(id) ?? false)
    }
}
