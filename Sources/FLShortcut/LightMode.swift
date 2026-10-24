// Mode léger (par défaut) : FL Shortcuts ne met RIEN dans FL Studio. Pas de script, pas de port MIDI.
// Il ne fait qu'envoyer des touches d'origine de FL, seulement quand FL est au premier plan.
// - Raccourcis d'origine déplacés : ta touche → la touche de FL (FL l'applique à sa fenêtre active).
// - Actions qui ont un équivalent clavier dans FL : ta touche → cette touche de FL.
// - Les autres actions (mute/solo de piste, volume ±0,5 dB, preset suivant…) demandent le script : masquées.
import Foundation

enum AppMode {
    /// Préférence (sans interface pour l'instant) : vrai = actions MIDI avec le script dans FL.
    static let midiActionsKey = "midiActions"

    static var light: Bool { !UserDefaults.standard.bool(forKey: midiActionsKey) }

    /// Touche d'origine de FL (notation Mac) qui fait la même chose que l'action, si elle existe.
    static func nativeEquivalent(of id: Int, layout: KeyboardLayout) -> KeyCombo? {
        guard let key = FLActions.all.first(where: { $0.id == id })?.key else { return nil }
        func ch(_ letter: String, _ fallback: UInt16, cmd: Bool = false, opt: Bool = false) -> KeyCombo {
            let code = (cmd ? KeyNames.commandKeyCode(for: letter, layout: layout) : KeyNames.keyCode(for: letter, layout: layout))
                ?? fallback
            return KeyCombo(keyCode: code, command: cmd, option: opt, control: false, shift: false)
        }
        func kc(_ code: UInt16, cmd: Bool = false, opt: Bool = false) -> KeyCombo {
            KeyCombo(keyCode: code, command: cmd, option: opt, control: false, shift: false)
        }
        switch key {
        case "play": return kc(49)                       // Espace : lecture / stop
        case "rec": return ch("r", 15)
        case "metro": return ch("m", 46, cmd: true)
        case "count": return ch("p", 35, cmd: true)
        case "wait": return ch("i", 34, cmd: true)
        case "newpat": return kc(118, cmd: true)         // ⌘F4 : pattern vide suivant
        case "pnext": return kc(69)                      // + du pavé numérique
        case "pprev": return kc(78)                      // − du pavé numérique
        case "quant": return ch("q", 12, cmd: true, opt: true)
        case "pl": return kc(96)                         // F5
        case "cr": return kc(97)                         // F6
        case "pr": return kc(98)                         // F7
        case "mx": return kc(101)                        // F9
        case "br": return kc(100, opt: true)             // ⌥F8
        case "undo": return ch("z", 6, cmd: true, opt: true)
        case "save": return ch("s", 1, cmd: true)
        default: return nil
        }
    }

    /// Table action → touche de FL, vide hors mode léger.
    static func actionNatives(layout: KeyboardLayout) -> [Int: KeyCombo] {
        guard light else { return [:] }
        var out: [Int: KeyCombo] = [:]
        for info in FLActions.all {
            if let k = nativeEquivalent(of: info.id, layout: layout) { out[info.id] = k }
        }
        return out
    }
}
