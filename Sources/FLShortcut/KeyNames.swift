// Audit : REL-16 (masque NoDeadKeys au lieu du numéro de bit), REL-17 (pavé numérique, F13-F20, Entrée du pavé,
//         caractères de contrôle / zone privée filtrés), REL-18 (disposition injectable, cache invalidable).
import Carbon
import Foundation

/// Disposition clavier : injectable pour les tests (AZERTY, QWERTZ, russe simulés).
protocol KeyboardLayout {
    /// Caractère produit sans modificateur.
    func character(for keyCode: UInt16) -> String?
    /// Caractère produit avec ⌘ enfoncé (diffère pour « Dvorak – QWERTY ⌘ »). Sert aux raccourcis ⌘.
    func commandCharacter(for keyCode: UInt16) -> String?
}

extension KeyboardLayout {
    func commandCharacter(for keyCode: UInt16) -> String? { character(for: keyCode) }
}

/// Disposition active du système (Text Input Sources). À appeler depuis le thread principal.
struct SystemKeyboardLayout: KeyboardLayout {
    func character(for keyCode: UInt16) -> String? {
        translate(keyCode, modifierState: 0)
    }

    func commandCharacter(for keyCode: UInt16) -> String? {
        // modifierKeyState = (modificateurs Carbon >> 8) & 0xFF ; cmdKey = 1 << 8.
        translate(keyCode, modifierState: UInt32((cmdKey >> 8) & 0xFF))
    }

    private func translate(_ keyCode: UInt16, modifierState: UInt32) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        // REL-16 : c'est le MASQUE (1 << bit) qu'il faut passer, pas le numéro du bit.
        let options = OptionBits(1 << kUCKeyTranslateNoDeadKeysBit)
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), modifierState,
                                  UInt32(LMGetKbdType()), options,
                                  &deadKeyState, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}

/// Noms lisibles des touches, selon la disposition clavier active (AZERTY, QWERTY…).
enum KeyNames {
    private static let special: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Espace", 51: "⌫", 53: "Échap", 117: "⌦", 114: "Aide",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "Début", 119: "Fin", 116: "PgPréc", 121: "PgSuiv",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20",
        // Rangée des chiffres : on affiche le chiffre, même en AZERTY
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
        // Pavé numérique (REL-17) : distinct de la rangée des chiffres
        82: "0 (pavé)", 83: "1 (pavé)", 84: "2 (pavé)", 85: "3 (pavé)", 86: "4 (pavé)",
        87: "5 (pavé)", 88: "6 (pavé)", 89: "7 (pavé)", 91: "8 (pavé)", 92: "9 (pavé)",
        65: ". (pavé)", 67: "× (pavé)", 69: "+ (pavé)", 75: "÷ (pavé)", 78: "− (pavé)", 81: "= (pavé)",
        76: "⌤", 71: "⌧",
        // Touches JIS
        102: "英数", 104: "かな", 93: "¥", 94: "_ (JIS)",
    ]

    /// Touches de fonction (F1-F20) : une touche seule de ce type n'est pas « tapée » en saisie de texte.
    static let functionKeys: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111,
                                            105, 107, 113, 106, 64, 79, 80, 90]

    static func name(for keyCode: UInt16, layout: KeyboardLayout = SystemKeyboardLayout()) -> String {
        if let s = special[keyCode] { return s }
        if let c = layout.character(for: keyCode), isPrintable(c) {
            return c.uppercased()
        }
        return "Touche \(keyCode)"
    }

    /// Code de touche qui produit ce caractère dans la disposition donnée.
    static func keyCode(for character: String, layout: KeyboardLayout = SystemKeyboardLayout()) -> UInt16? {
        let target = character.lowercased()
        for code in UInt16(0)..<UInt16(128) where layout.character(for: code)?.lowercased() == target {
            return code
        }
        return nil
    }

    /// Code de touche qui produit ce caractère quand ⌘ est enfoncé (raccourcis ⌘).
    static func commandKeyCode(for character: String, layout: KeyboardLayout = SystemKeyboardLayout()) -> UInt16? {
        let target = character.lowercased()
        for code in UInt16(0)..<UInt16(128) where layout.commandCharacter(for: code)?.lowercased() == target {
            return code
        }
        return nil
    }

    /// Exclut les caractères de contrôle (Entrée du pavé = U+0003) et la zone privée (F13… = U+F700…U+F8FF).
    static func isPrintable(_ s: String) -> Bool {
        guard !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        for scalar in s.unicodeScalars {
            if CharacterSet.controlCharacters.contains(scalar) { return false }
            if (0xE000...0xF8FF).contains(scalar.value) { return false }
        }
        return true
    }
}
