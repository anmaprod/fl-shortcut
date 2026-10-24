// Audit : SEC-05 (liste noire NON contournable des cibles « Touche de FL » dangereuses : ⌘Q, ⌘⇧Q, ⌃⌘Q, ⌘W,
//         ⌘⌫, ⌘⌦, ⌘⌥Échap, ⌘⇥, ⌘Espace ; appliquée à l'édition, à l'import, au chargement ET juste avant
//         chaque injection), REL-11 / audit 05 §4.2 (conflits macOS, dont les raccourcis système lus dans
//         com.apple.symbolichotkeys, et conflits avec les raccourcis natifs de FL), REL-18 (résolution selon la
//         disposition active, recalculée à chaque changement).
import Foundation

/// Cibles interdites : les touches qui produisent « q » / « w » (avec ⌘, et seules) dans la disposition active
/// (AZERTY : ⌘Q est sur la touche 0, ⌘W sur la 6). Disposition sans ces lettres ou illisible : touches physiques Q
/// (12) et W (13). Les positions 12 et 13 ne sont plus bloquées dans toutes les dispositions : en AZERTY ce sont
/// ⌘A et ⌘Z, refusés à tort. Recalculé à chaque changement de disposition et revérifié juste avant chaque envoi.
struct ForbiddenTargets: Hashable {
    var quitKeys: Set<UInt16>
    var closeKeys: Set<UInt16>

    static let physical = ForbiddenTargets(quitKeys: [12], closeKeys: [13])

    static func make(layout: KeyboardLayout) -> ForbiddenTargets {
        func codes(_ letter: String) -> Set<UInt16> {
            Set([KeyNames.commandKeyCode(for: letter, layout: layout), KeyNames.keyCode(for: letter, layout: layout)]
                .compactMap { $0 })
        }
        let q = codes("q"), w = codes("w")
        return ForbiddenTargets(quitKeys: q.isEmpty ? physical.quitKeys : q, closeKeys: w.isEmpty ? physical.closeKeys : w)
    }

    /// Raison du refus, ou `nil` si la cible est autorisée.
    func reason(for c: KeyCombo) -> String? {
        guard c.command else { return nil }
        if quitKeys.contains(c.keyCode) { return String(localized: "⌘Q quitte l'application (⌃⌘Q verrouille la session)") }
        if closeKeys.contains(c.keyCode) { return String(localized: "⌘W ferme la fenêtre ou le projet") }
        switch c.keyCode {
        case 51, 117: return String(localized: "⌘⌫ supprime (fichiers, corbeille)")
        case 53 where c.option: return String(localized: "⌘⌥Échap ouvre « Forcer à quitter »")
        case 48: return String(localized: "⌘⇥ change d'application")
        case 49: return String(localized: "⌘Espace ouvre Spotlight")
        default: return nil
        }
    }

    func isForbidden(_ c: KeyCombo) -> Bool { reason(for: c) != nil }
}

/// Raccourcis déjà pris par macOS ou par FL. Avertissements seulement (pas de blocage).
struct ConflictTable: Equatable {
    var macOS: [KeyCombo: String] = [:]
    var fl: [KeyCombo: String] = [:]

    static let empty = ConflictTable()

    func macOSConflict(_ c: KeyCombo) -> String? { macOS[c] }
    func flConflict(_ c: KeyCombo) -> String? { fl[c] }

    /// Table construite pour une disposition donnée, plus les raccourcis système actifs lus dans les préférences.
    static func make(layout: KeyboardLayout, systemHotKeys: [KeyCombo: String]) -> ConflictTable {
        var mac: [KeyCombo: String] = [:]
        func cmd(_ ch: String, _ fallback: UInt16, shift: Bool = false, option: Bool = false, control: Bool = false) -> KeyCombo {
            KeyCombo(keyCode: KeyNames.commandKeyCode(for: ch, layout: layout) ?? fallback,
                     command: true, option: option, control: control, shift: shift)
        }
        mac[cmd("q", 12)] = String(localized: "macOS : quitter l'application")
        mac[cmd("w", 13)] = String(localized: "macOS : fermer la fenêtre")
        mac[cmd("h", 4)] = String(localized: "macOS : masquer l'application")
        mac[cmd("m", 46)] = String(localized: "macOS : placer la fenêtre dans le Dock")
        mac[cmd(",", 43)] = String(localized: "macOS : réglages de l'application")
        mac[cmd("q", 12, control: true)] = String(localized: "macOS : verrouiller l'écran")
        mac[KeyCombo(keyCode: 48, command: true)] = String(localized: "macOS : changer d'application")
        mac[KeyCombo(keyCode: 49, command: true)] = String(localized: "macOS : Spotlight")
        mac[KeyCombo(keyCode: 49, control: true)] = String(localized: "macOS : changer de source de saisie")
        mac[KeyCombo(keyCode: 49, command: true, control: true)] = String(localized: "macOS : emoji et symboles")
        mac[KeyCombo(keyCode: 126, control: true)] = String(localized: "macOS : Mission Control")
        mac[KeyCombo(keyCode: 125, control: true)] = String(localized: "macOS : fenêtres de l'application")
        mac[KeyCombo(keyCode: 123, control: true)] = String(localized: "macOS : bureau de gauche (Spaces)")
        mac[KeyCombo(keyCode: 124, control: true)] = String(localized: "macOS : bureau de droite (Spaces)")
        mac[KeyCombo(keyCode: 53, command: true, option: true)] = String(localized: "macOS : forcer à quitter")
        mac[KeyCombo(keyCode: 20, command: true, shift: true)] = String(localized: "macOS : capture d'écran")
        mac[KeyCombo(keyCode: 21, command: true, shift: true)] = String(localized: "macOS : capture d'une zone")
        mac[KeyCombo(keyCode: 23, command: true, shift: true)] = String(localized: "macOS : outil de capture")
        for (combo, label) in systemHotKeys { mac[combo] = label }

        var fl: [KeyCombo: String] = [:]
        fl[KeyCombo(keyCode: 49)] = String(localized: "FL : lecture / stop")
        fl[KeyCombo(keyCode: 96)] = String(localized: "FL : Playlist (F5)")
        fl[KeyCombo(keyCode: 97)] = String(localized: "FL : Channel Rack (F6)")
        fl[KeyCombo(keyCode: 98)] = String(localized: "FL : Piano Roll (F7)")
        fl[KeyCombo(keyCode: 100)] = String(localized: "FL : Plugin picker (F8)")
        fl[KeyCombo(keyCode: 101)] = String(localized: "FL : Mixer (F9)")
        fl[cmd("s", 1)] = String(localized: "FL : enregistrer le projet")
        fl[cmd("z", 6)] = String(localized: "FL : annuler")
        fl[cmd("o", 31)] = String(localized: "FL : ouvrir un projet")
        fl[cmd("n", 45)] = String(localized: "FL : nouveau projet")
        fl[cmd("r", 15)] = String(localized: "FL : exporter en WAV")
        let bare: [(String, UInt16, String)] = [
            ("l", 37, String(localized: "FL : bascule Pattern / Song")), ("r", 15, String(localized: "FL : enregistrement")),
            ("p", 35, String(localized: "FL : outil crayon")), ("b", 11, String(localized: "FL : outil pinceau")),
            ("d", 2, String(localized: "FL : outil suppression")), ("t", 17, String(localized: "FL : outil mute")),
            ("s", 1, String(localized: "FL : outil slip / solo du Mixer")), ("c", 8, String(localized: "FL : outil découpe")),
            ("e", 14, String(localized: "FL : outil sélection")), ("z", 6, String(localized: "FL : outil zoom")),
            ("y", 16, String(localized: "FL : outil lecture")),
        ]
        for (ch, fallback, label) in bare {
            fl[KeyCombo(keyCode: KeyNames.keyCode(for: ch, layout: layout) ?? fallback)] = label
        }
        return ConflictTable(macOS: mac, fl: fl)
    }
}

/// Raccourcis système actifs (Réglages › Clavier › Raccourcis), lus dans com.apple.symbolichotkeys.
enum SystemHotKeys {
    private static let names: [Int: String] = [
        118: String(localized: "Passer au bureau 1"), 119: String(localized: "Passer au bureau 2"),
        120: String(localized: "Passer au bureau 3"), 121: String(localized: "Passer au bureau 4"),
        122: String(localized: "Passer au bureau 5"), 123: String(localized: "Passer au bureau 6"),
        124: String(localized: "Passer au bureau 7"), 125: String(localized: "Passer au bureau 8"),
        126: String(localized: "Passer au bureau 9"),
        79: String(localized: "Bureau de gauche"), 81: String(localized: "Bureau de droite"),
        32: String(localized: "Mission Control"), 33: String(localized: "Fenêtres de l'application"),
        36: String(localized: "Afficher le bureau"), 60: String(localized: "Source de saisie précédente"),
        61: String(localized: "Source de saisie suivante"),
        64: String(localized: "Spotlight"), 65: String(localized: "Fenêtre Spotlight"),
        28: String(localized: "Capture d'écran"), 29: String(localized: "Capture dans le presse-papiers"),
        30: String(localized: "Capture d'une zone"), 31: String(localized: "Capture d'une zone dans le presse-papiers"),
        184: String(localized: "Outil de capture"),
    ]

    /// Lecture tolérante : toute entrée mal formée est ignorée.
    static func read() -> [KeyCombo: String] {
        guard let value = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString,
                                                    "com.apple.symbolichotkeys" as CFString),
              let dict = value as? [String: Any] else { return [:] }
        return parse(dict)
    }

    /// `parameters` = [caractère, keyCode, modificateurs NSEvent (⇧ 1<<17, ⌃ 1<<18, ⌥ 1<<19, ⌘ 1<<20)].
    static func parse(_ dict: [String: Any]) -> [KeyCombo: String] {
        var out: [KeyCombo: String] = [:]
        for (key, raw) in dict {
            guard let id = Int(key), let entry = raw as? [String: Any] else { continue }
            let enabled = (entry["enabled"] as? Bool) ?? ((entry["enabled"] as? Int).map { $0 != 0 } ?? false)
            guard enabled, let value = entry["value"] as? [String: Any],
                  let params = value["parameters"] as? [Int], params.count >= 3,
                  (0...127).contains(params[1]) else { continue }
            let mods = params[2]
            let combo = KeyCombo(keyCode: UInt16(params[1]),
                                 command: mods & (1 << 20) != 0, option: mods & (1 << 19) != 0,
                                 control: mods & (1 << 18) != 0, shift: mods & (1 << 17) != 0)
            out[combo] = String(localized: "macOS : ") + (names[id] ?? String(localized: "raccourci système (Réglages › Clavier)"))
        }
        return out
    }
}
