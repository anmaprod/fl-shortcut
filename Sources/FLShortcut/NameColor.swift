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

    /// Couleur à `t` (0 = soi, 1 = `other`) en ligne droite sur chaque composante, arrondie au plus proche comme le
    /// script (`int(a + (b − a) × t + 0,5)`) et comme « Gradient color… » de FL.
    func lerp(_ other: RGBColor, _ t: Double) -> RGBColor {
        func mix(_ a: UInt8, _ b: UInt8) -> UInt8 {
            let v = (Double(a) + (Double(b) - Double(a)) * min(max(t, 0), 1) + 0.5).rounded(.down)
            return UInt8(min(max(v, 0), 255))
        }
        return RGBColor(r: mix(r, other.r), g: mix(g, other.g), b: mix(b, other.b))
    }
}

/// Case de la grille des icônes de FL (« Change icon… ») : 14 colonnes, 15 rangées, 0-indexées ; écrite « 3-7 ».
/// (0, 0) est « Reset » : aucune icône.
struct FLIcon: Equatable, Hashable {
    static let columns = 14
    static let rows = 15

    let column: Int
    let row: Int

    init?(column: Int, row: Int) {
        guard (0..<Self.columns).contains(column), (0..<Self.rows).contains(row) else { return nil }
        self.column = column
        self.row = row
    }

    init?(code: String) {
        let parts = code.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, let c = Int(parts[0]), let r = Int(parts[1]),
              String(c) == parts[0], String(r) == parts[1] else { return nil }
        self.init(column: c, row: r)
    }

    var code: String { "\(column)-\(row)" }
    var isReset: Bool { column == 0 && row == 0 }
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
        if scalars.contains(where: { $0.value < 32 || $0.value == 127 }) { return String(localized: "le nom contient un caractère invisible.") }
        if scalars.count > maxNameScalars || name.utf8.count > maxNameBytes { return String(localized: "nom trop long (64 caractères au plus).") }
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

    /// Ligne du bloc : « Kick · #E0453A », « Kick », « couleur #E0453A », « dégradé #F2A0D8 → #C02890 ».
    static func summary(name: String?, color: RGBColor?, fade: RGBColor? = nil, icon: FLIcon? = nil) -> String {
        if let color, let fade { return String(localized: "dégradé #\(color.hex) → #\(fade.hex)") }
        let n = NameColorPayload(name: name, color: color)
        var parts: [String] = []
        if let name = n.name { parts.append(name.displaySafe(max: 40)) }
        if let color = n.color { parts.append(n.name == nil ? String(localized: "couleur #\(color.hex)") : "#\(color.hex)") }
        if let icon { parts.append(String(localized: "icône \(FLIconGrid.cell(icon)?.name ?? icon.code)")) }
        return parts.isEmpty ? String(localized: "nom et couleur à choisir") : parts.joined(separator: " · ")
    }

    /// Message d'un refus expliqué par FL (CC 116).
    static func message(forReason reason: Int) -> String {
        switch reason {
        case 1: return String(localized: "Ouvre le Mixer, le Channel rack ou la Playlist.")
        case 2: return String(localized: "Sélectionne une piste ou un canal.")
        case 3: return String(localized: "Sélectionne une seule piste ou un seul canal.")
        case 4: return String(localized: "Arrête la lecture d'abord.")
        case 6: return String(localized: "Ta version de FL ne le permet pas sur cette page : mets FL à jour.")
        case 7: return String(localized: "Sélectionne au moins 2 pistes pour un dégradé.")
        default: return String(localized: "FL a refusé le nom ou la couleur.")
        }
    }
}

/// Les 10 dernières couleurs choisies dans FL Shortcuts, la plus récente d'abord (préférences, codes « E0453A »).
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

// MARK: - Fenêtre de couleur de FL (« Color selector »)

/// Teinte, saturation, luminance comme les affiche FL : teinte en degrés (0…359), saturation et luminance sur 240
/// (échelle de Windows). Relevé sur FL : RVB 88, 110, 124 → 203, 40, 100.
struct FLHSL: Equatable {
    var hue: Int
    var saturation: Int
    var luminance: Int

    static let scale = 240.0
}

extension RGBColor {
    var flHSL: FLHSL {
        let r = Double(self.r) / 255, g = Double(self.g) / 255, b = Double(self.b) / 255
        let maxV = max(r, g, b), minV = min(r, g, b), delta = maxV - minV
        let l = (maxV + minV) / 2
        var h = 0.0, s = 0.0
        if delta > 0 {
            s = l < 0.5 ? delta / (maxV + minV) : delta / (2 - maxV - minV)
            if maxV == r { h = (g - b) / delta + (g < b ? 6 : 0) } else if maxV == g { h = (b - r) / delta + 2 } else { h = (r - g) / delta + 4 }
            h *= 60
        }
        return FLHSL(hue: Int(h.rounded()) % 360, saturation: Int((s * FLHSL.scale).rounded()),
                     luminance: Int((l * FLHSL.scale).rounded()))
    }

    init(flHSL v: FLHSL) {
        let h = Double(((v.hue % 360) + 360) % 360) / 360
        let s = min(max(Double(v.saturation) / FLHSL.scale, 0), 1)
        let l = min(max(Double(v.luminance) / FLHSL.scale, 0), 1)
        self.init(hue: h, saturation: s, lightness: l)
    }

    /// HSL classique (0…1 chacun).
    init(hue h: Double, saturation s: Double, lightness l: Double) {
        guard s > 0 else {
            let v = UInt8((l * 255).rounded())
            self.init(r: v, g: v, b: v)
            return
        }
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s
        let p = 2 * l - q
        func channel(_ t0: Double) -> UInt8 {
            var t = t0
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            let v: Double
            if t < 1 / 6 { v = p + (q - p) * 6 * t } else if t < 1 / 2 { v = q } else if t < 2 / 3 { v = p + (q - p) * (2 / 3 - t) * 6 } else { v = p }
            return UInt8(min(max(v * 255, 0), 255).rounded())
        }
        self.init(r: channel(h + 1 / 3), g: channel(h), b: channel(h - 1 / 3))
    }
}

/// Roue de la fenêtre de couleur de FL : 16 secteurs (rouge en haut, sens des aiguilles d'une montre), un disque
/// gris au centre, 3 anneaux de couleurs (pâle, moyen, vif : valeurs relevées sur la vidéo de FL de l'utilisateur)
/// et 2 anneaux de teintes sombres.
enum FLColorWheel {
    static let sectors = 16
    /// Rayons relatifs (rayon extérieur = 1) des bords : disque central, puis anneaux 1 à 5 (relevés sur FL :
    /// 42, 82, 122, 162, 202 et 242 px).
    static let edges: [Double] = [0.174, 0.339, 0.504, 0.669, 0.835, 1.0]
    static let center = RGBColor(r: 168, g: 168, b: 168)

    private static func list(_ v: [(UInt8, UInt8, UInt8)]) -> [RGBColor] { v.map { RGBColor(r: $0.0, g: $0.1, b: $0.2) } }

    static let pale = list([(253, 203, 203), (255, 224, 206), (255, 240, 200), (247, 253, 204), (219, 248, 198),
                            (201, 243, 202), (189, 249, 210), (196, 254, 236), (193, 254, 254), (197, 236, 253),
                            (202, 217, 255), (212, 205, 255), (232, 204, 255), (251, 202, 250), (254, 202, 242),
                            (252, 200, 219)])
    static let medium = list([(253, 152, 155), (249, 181, 145), (250, 223, 150), (241, 255, 149), (187, 249, 144),
                              (148, 250, 152), (127, 252, 174), (127, 252, 215), (129, 254, 255), (139, 219, 255),
                              (153, 182, 253), (173, 157, 254), (215, 156, 254), (246, 155, 245), (255, 152, 231),
                              (255, 153, 192)])
    static let vivid = list([(254, 105, 110), (253, 156, 103), (255, 214, 99), (232, 253, 92), (155, 244, 88),
                             (89, 250, 102), (46, 252, 135), (46, 253, 197), (46, 253, 254), (84, 197, 251),
                             (104, 147, 253), (129, 110, 240), (194, 110, 250), (244, 110, 246), (252, 105, 223),
                             (253, 106, 161)])

    /// Anneau 0 : centre ; 1 pâle ; 2 moyen ; 3 vif ; 4 et 5 : la teinte vive assombrie.
    static func color(ring: Int, sector: Int) -> RGBColor {
        let k = ((sector % sectors) + sectors) % sectors
        switch ring {
        case 0: return center
        case 1: return pale[k]
        case 2: return medium[k]
        case 3: return vivid[k]
        default:
            var v = vivid[k].flHSL
            v.luminance = ring == 4 ? 90 : 56
            return RGBColor(flHSL: v)
        }
    }

    /// Case sous un point, en coordonnées relatives au centre (rayon extérieur = 1, y vers le bas) ; nil hors de la
    /// roue.
    static func hit(dx: Double, dy: Double) -> (ring: Int, sector: Int)? {
        let r = (dx * dx + dy * dy).squareRoot()
        guard r <= edges[edges.count - 1] else { return nil }
        guard let ring = edges.firstIndex(where: { r <= $0 }) else { return nil }
        if ring == 0 { return (0, 0) }
        var angle = atan2(dx, -dy) * 180 / .pi          // 0° en haut, sens des aiguilles d'une montre
        if angle < 0 { angle += 360 }
        let step = 360.0 / Double(sectors)
        let sector = Int(((angle + step / 2) / step).rounded(.down)) % sectors
        return (ring, sector)
    }
}
