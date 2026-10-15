import Foundation
@testable import FLShortcut

/// Disposition simulée (QWERTY US, AZERTY français, russe…).
struct FakeLayout: KeyboardLayout {
    var plain: [UInt16: String]
    var withCommand: [UInt16: String]? = nil

    func character(for keyCode: UInt16) -> String? { plain[keyCode] }
    func commandCharacter(for keyCode: UInt16) -> String? { (withCommand ?? plain)[keyCode] }

    static let qwerty = FakeLayout(plain: [
        0: "a", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "z", 7: "x", 8: "c", 9: "v", 11: "b",
        12: "q", 13: "w", 14: "e", 15: "r", 16: "y", 17: "t", 31: "o", 32: "u", 34: "i", 35: "p",
        37: "l", 38: "j", 40: "k", 43: ",", 45: "n", 46: "m",
    ])

    static let azerty = FakeLayout(plain: [
        0: "q", 1: "s", 2: "d", 3: "f", 4: "h", 5: "g", 6: "w", 7: "x", 8: "c", 9: "v", 11: "b",
        12: "a", 13: "z", 14: "e", 15: "r", 16: "y", 17: "t", 31: "o", 32: "u", 34: "i", 35: "p",
        37: "l", 38: "j", 40: "k", 41: "m", 45: "n", 46: ",", 33: "^",
    ])

    /// Aucune lettre latine : toutes les résolutions tombent sur les positions de repli QWERTY.
    static let russian = FakeLayout(plain: [0: "ф", 1: "ы", 2: "в", 3: "а", 12: "й", 13: "ц", 46: "ь"])
}

/// Transport MIDI simulé : enregistre ce qui est envoyé.
final class FakeTransport: MIDITransport {
    var isReady = true
    var sent: [[CCMessage]] = []
    var fail = false
    /// Appelé après chaque envoi (sous le verrou du lien : répondre de façon asynchrone).
    var onSend: (([CCMessage]) -> Void)?

    func send(_ messages: [CCMessage]) -> Bool {
        guard !fail else { return false }
        sent.append(messages)
        onSend?(messages)
        return true
    }

    var pings: Int { sent.filter { $0 == [.ping] }.count }
    var frames: [[CCMessage]] { sent.filter { $0.count == 8 } }
}

/// Horloge contrôlée.
final class FakeClock {
    var now = Date(timeIntervalSince1970: 1_000_000)
    func advance(_ s: TimeInterval) { now = now.addingTimeInterval(s) }
}

/// Stockage de profil en mémoire.
final class MemoryProfileStorage: ProfileStorage {
    var data: Data?
    var writes = 0
    var backups: [String: Data] = [:]
    var readError: Error?
    var writeError: Error?

    init(data: Data? = nil) { self.data = data }

    func read() throws -> Data? {
        if let readError { throw readError }
        return data
    }

    func write(_ d: Data) throws {
        if let writeError { throw writeError }
        writes += 1
        data = d
    }

    func backup(_ d: Data, label: String) throws -> String {
        let name = "profile.\(label).json"
        backups[name] = d
        return name
    }
}

enum Bytes {
    /// Trame HELLO telle que l'émet le script (ordre de `hello_messages()`).
    static func hello(nonce: [UInt8], api: UInt8 = 13, proto: UInt8 = 2, caps: [UInt8]) -> [UInt8] {
        var pairs: [(UInt8, UInt8)] = [(120, 1)]
        for (i, n) in nonce.enumerated() { pairs.append((121 + UInt8(i), n)) }
        pairs.append((125, api))
        pairs.append((126, proto))
        for (k, v) in caps.enumerated() { pairs.append((90 + UInt8(k), v)) }
        pairs.append((120, 127))
        return pairs.flatMap { [0xBF, $0.0, $0.1] }
    }

    static func cc(_ cc: UInt8, _ value: UInt8) -> [UInt8] { [0xBF, cc, value] }

    /// Masque « tout disponible » pour les 38 actions.
    static var allCaps: [UInt8] { CapabilityMask(bits: (1 << 38) - 1).ccValues }
}
