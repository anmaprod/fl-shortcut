import Carbon

/// Noms lisibles des touches, selon la disposition clavier active (AZERTY, QWERTY…).
enum KeyNames {
    private static let special: [UInt16: String] = [
        36: "↩", 48: "⇥", 49: "Espace", 51: "⌫", 53: "Échap", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "Début", 119: "Fin", 116: "PgPréc", 121: "PgSuiv",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        // Rangée des chiffres : on affiche le chiffre, même en AZERTY
        18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6", 26: "7", 28: "8", 25: "9", 29: "0",
    ]

    static func name(for keyCode: UInt16) -> String {
        if let s = special[keyCode] { return s }
        if let c = character(for: keyCode), !c.trimmingCharacters(in: .whitespaces).isEmpty {
            return c.uppercased()
        }
        return "Touche \(keyCode)"
    }

    /// Code de touche qui produit ce caractère dans la disposition active.
    static func keyCode(for character: String) -> UInt16? {
        let target = character.lowercased()
        for code in UInt16(0)..<UInt16(128) where self.character(for: code)?.lowercased() == target {
            return code
        }
        return nil
    }

    static func character(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeyState, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}
