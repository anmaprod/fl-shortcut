// Fichier de projet de FL Studio (.flp), lu et réécrit événement par événement, à l'octet près : l'Organiser y lit
// exactement ce que joue chaque pattern et où chaque clip est posé dans la Playlist, puis écrit une copie rangée (le
// fichier d'origine n'est jamais touché). Format : PROTOCOL.md §9. Pur (testé) : ni FL ni le Mac.
import Foundation

/// Un événement du fichier : son numéro et ses octets (1, 2 ou 4 pour les numéros < 192, sinon de longueur libre).
struct FLPEvent: Equatable {
    let id: UInt8
    var bytes: [UInt8]

    /// Nombre d'octets d'un événement d'après son numéro ; nil : longueur écrite devant (numéros 192 et plus).
    static func fixedSize(_ id: UInt8) -> Int? {
        switch id {
        case 0..<64: return 1
        case 64..<128: return 2
        case 128..<192: return 4
        default: return nil
        }
    }

    /// Valeur d'un événement de 1, 2 ou 4 octets.
    var value: UInt32 { FLPBytes.uint(bytes, at: 0, size: bytes.count) }

    /// Texte d'un événement de texte : UTF-16 (petit-boutiste) terminé par un zéro.
    var text: String {
        var units: [UInt16] = []
        var i = 0
        while i + 1 < bytes.count {
            let unit = UInt16(bytes[i]) | UInt16(bytes[i + 1]) << 8
            if unit == 0 { break }
            units.append(unit)
            i += 2
        }
        return String(decoding: units, as: UTF16.self)
    }
}

enum FLPError: Error, Equatable {
    /// Pas un projet de FL (en-tête « FLhd » absent).
    case notProject
    /// Fichier coupé ou abîmé.
    case damaged
    /// Projet lu, mais d'une forme que l'Organiser ne sait pas ranger sans risque (raison pour le diagnostic).
    case unsupported(String)
}

/// Lecture et écriture des nombres du fichier (petit-boutistes).
enum FLPBytes {
    static func uint(_ bytes: [UInt8], at offset: Int, size: Int) -> UInt32 {
        var value: UInt32 = 0
        for k in 0..<size { value |= UInt32(bytes[offset + k]) << (8 * UInt32(k)) }
        return value
    }

    static func put(_ value: UInt32, into bytes: inout [UInt8], at offset: Int, size: Int) {
        for k in 0..<size { bytes[offset + k] = UInt8(truncatingIfNeeded: value >> (8 * UInt32(k))) }
    }

    static func le(_ value: Int, size: Int) -> [UInt8] {
        (0..<size).map { UInt8(truncatingIfNeeded: value >> (8 * $0)) }
    }

    /// Longueur d'un événement de longueur libre : 7 bits par octet, le bit du haut dit qu'un octet suit.
    static func varint(_ value: Int) -> [UInt8] {
        var out: [UInt8] = []
        var rest = value
        repeat {
            var byte = UInt8(rest & 0x7F)
            rest >>= 7
            if rest > 0 { byte |= 0x80 }
            out.append(byte)
        } while rest > 0
        return out
    }
}

/// Le fichier entier : en-tête, puis la suite des événements.
struct FLPFile: Equatable {
    var format: UInt16
    var channelCount: UInt16
    /// Pas par noire (positions et longueurs de la Playlist et des notes).
    var ppq: UInt16
    var events: [FLPEvent]
    /// Ce qui suivrait l'en-tête ou les événements : gardé tel quel.
    var headerExtra: [UInt8] = []
    var trailer: [UInt8] = []

    init(format: UInt16 = 0, channelCount: UInt16, ppq: UInt16, events: [FLPEvent]) {
        self.format = format
        self.channelCount = channelCount
        self.ppq = ppq
        self.events = events
    }

    init(bytes: [UInt8]) throws {
        var reader = Reader(bytes: bytes)
        guard bytes.count >= 4, try reader.take(4) == Array("FLhd".utf8) else { throw FLPError.notProject }
        let headerSize = try reader.int(4)
        guard headerSize >= 6 else { throw FLPError.damaged }
        format = UInt16(try reader.int(2))
        channelCount = UInt16(try reader.int(2))
        ppq = UInt16(try reader.int(2))
        headerExtra = try reader.take(headerSize - 6)
        guard try reader.take(4) == Array("FLdt".utf8) else { throw FLPError.damaged }
        let size = try reader.int(4)
        guard size <= bytes.count - reader.offset else { throw FLPError.damaged }
        let end = reader.offset + size
        var events: [FLPEvent] = []
        while reader.offset < end {
            let id = try reader.byte()
            let size = try FLPEvent.fixedSize(id) ?? reader.varint()
            guard size <= end - reader.offset else { throw FLPError.damaged }
            events.append(FLPEvent(id: id, bytes: try reader.take(size)))
        }
        self.events = events
        trailer = Array(bytes[end...])
    }

    init(contentsOf url: URL) throws {
        try self.init(bytes: [UInt8](try Data(contentsOf: url)))
    }

    func encoded() -> [UInt8] {
        var data: [UInt8] = []
        for event in events {
            data.append(event.id)
            if FLPEvent.fixedSize(event.id) == nil { data += FLPBytes.varint(event.bytes.count) }
            data += event.bytes
        }
        var out = Array("FLhd".utf8) + FLPBytes.le(6 + headerExtra.count, size: 4)
        out += FLPBytes.le(Int(format), size: 2) + FLPBytes.le(Int(channelCount), size: 2)
        out += FLPBytes.le(Int(ppq), size: 2) + headerExtra
        out += Array("FLdt".utf8) + FLPBytes.le(data.count, size: 4) + data
        return out + trailer
    }

    private struct Reader {
        let bytes: [UInt8]
        var offset = 0

        mutating func byte() throws -> UInt8 {
            guard offset < bytes.count else { throw FLPError.damaged }
            offset += 1
            return bytes[offset - 1]
        }

        mutating func take(_ count: Int) throws -> [UInt8] {
            guard count >= 0, count <= bytes.count - offset else { throw FLPError.damaged }
            offset += count
            return Array(bytes[offset - count..<offset])
        }

        mutating func int(_ size: Int) throws -> Int {
            Int(FLPBytes.uint(try take(size), at: 0, size: size))
        }

        /// Au plus 4 octets (assez pour 256 Mo) : au-delà, le fichier est abîmé.
        mutating func varint() throws -> Int {
            var value = 0
            for shift in stride(from: 0, through: 21, by: 7) {
                let b = try byte()
                value |= Int(b & 0x7F) << shift
                if b & 0x80 == 0 { return value }
            }
            throw FLPError.damaged
        }
    }
}
