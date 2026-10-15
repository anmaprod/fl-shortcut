// Bloc « Nom et couleur » : nommer et colorer l'élément sélectionné de la page de FL qui est devant (piste du Mixer,
// canal du Channel rack, piste de la Playlist), par la commande avec données du lien (PROTOCOL.md §7, opération 1).
// Le nom n'est jamais écrit dans un journal.
import Foundation

/// Couleur 24 bits, écrite « E0453A » (6 chiffres hexadécimaux, sans « # »).
struct RGBColor: Equatable, Hashable {
    let r: UInt8
    let g: UInt8
    let b: UInt8

    init(r: UInt8, g: UInt8, b: UInt8) {
        self.r = r
        self.g = g
        self.b = b
    }

    /// Accepte « E0453A », « #e0453a » ; refuse toute autre longueur ou tout caractère non hexadécimal.
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, text.unicodeScalars.allSatisfy({ $0.isASCII && $0.properties.isASCIIHexDigit }),
              let v = UInt32(text, radix: 16) else { return nil }
        self.init(r: UInt8((v >> 16) & 0xFF), g: UInt8((v >> 8) & 0xFF), b: UInt8(v & 0xFF))
    }

    var hex: String { String(format: "%02X%02X%02X", r, g, b) }
}

/// Données de l'opération 1 : `[1, drapeaux (bit 0 nom, bit 1 couleur), R, G, B, n, nom UTF-8 (n octets)]`.
struct NameColorPayload: Equatable {
    /// Le script compte les points de code (Python) : même mesure ici.
    static let maxNameScalars = 64
    /// La longueur du nom tient sur un octet.
    static let maxNameBytes = 255

    /// Nom sans espaces de début ni de fin ; nil s'il est vide.
    let name: String?
    let color: RGBColor?

    init(name: String?, color: RGBColor?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        self.name = trimmed?.isEmpty == false ? trimmed : nil
        self.color = color
    }

    /// Nom acceptable par le script : 64 caractères au plus, 255 octets au plus, aucun caractère de contrôle.
    static func nameProblem(_ name: String) -> String? {
        let scalars = name.unicodeScalars
        if scalars.contains(where: { $0.value < 32 || $0.value == 127 }) { return "le nom contient un caractère invisible." }
        if scalars.count > maxNameScalars || name.utf8.count > maxNameBytes { return "nom trop long (64 caractères au plus)." }
        return nil
    }

    var bytes: [UInt8] {
        let raw = Array((name ?? "").utf8.prefix(Self.maxNameBytes))
        let flags: UInt8 = (name != nil ? 1 : 0) | (color != nil ? 2 : 0)
        let c = color ?? RGBColor(r: 0, g: 0, b: 0)
        return [1, flags, c.r, c.g, c.b, UInt8(raw.count)] + raw
    }

    var units: [UInt8] { Pack7.pack(bytes) }
}
