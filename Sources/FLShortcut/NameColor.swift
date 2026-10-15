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

    /// Rouge de départ du bloc (un bloc neuf est valable tel quel).
    static let defaultColor = RGBColor(r: 0xE0, g: 0x45, b: 0x3A)

    /// Ligne du bloc : « Kick · #E0453A », « Kick », « couleur #E0453A ».
    static func summary(name: String?, color: RGBColor?) -> String {
        let n = NameColorPayload(name: name, color: color)
        switch (n.name, n.color) {
        case let (name?, color?): return "\(name.displaySafe(max: 40)) · #\(color.hex)"
        case let (name?, nil): return name.displaySafe(max: 40)
        case let (nil, color?): return "couleur #\(color.hex)"
        case (nil, nil): return "nom et couleur à choisir"
        }
    }

    /// Message d'un refus expliqué par FL (CC 116).
    static func message(forReason reason: Int) -> String {
        switch reason {
        case 1: return "Ouvre le Mixer, le Channel rack ou la Playlist."
        case 2: return "Sélectionne une piste ou un canal."
        case 3: return "Sélectionne une seule piste ou un seul canal."
        case 4: return "Arrête la lecture d'abord."
        case 6: return "Ta version de FL ne le permet pas sur cette page : mets FL à jour."
        default: return "FL a refusé le nom ou la couleur."
        }
    }
}

/// Les 10 dernières couleurs choisies dans FL Shortcut, la plus récente d'abord (préférences, codes « E0453A »).
enum RecentColors {
    static let key = "nameColor.recentColors"
    static let limit = 10

    static func list(defaults: UserDefaults = .standard) -> [RGBColor] {
        var seen = Set<RGBColor>()
        let all = (defaults.array(forKey: key) ?? []).compactMap { ($0 as? String).flatMap(RGBColor.init(hex:)) }
        return Array(all.filter { seen.insert($0).inserted }.prefix(limit))
    }

    static func remember(_ c: RGBColor, defaults: UserDefaults = .standard) {
        let others = list(defaults: defaults).filter { $0 != c }
        defaults.set(([c] + others).prefix(limit).map(\.hex), forKey: key)
    }
}
