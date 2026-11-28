// Raccourcis d'une page rangés en cartes (maquette du 28/10, « à l'identique », 29/10) : chaque page de FL a ses
// groupes (Playlist : Outils, Sélection, Édition, Zoom, Marqueurs…), une carte par groupe avec son titre au-dessus,
// sur deux colonnes quand la page est large. Les actions en plus du script gardent leur carte.
import Foundation

enum CatalogGroups {
    /// Un groupe : son titre et les raccourcis d'origine de FL qu'il range (fin de l'identifiant, après
    /// « fl.<page>. »).
    struct Group {
        let title: String
        let keys: [String]
    }

    /// Les groupes de chaque page, dans l'ordre affiché. Chaque raccourci d'origine de FL est dans un groupe et un
    /// seul (vérifié par les tests) ; un raccourci ajouté plus tard sans groupe tombe dans « Autres ».
    static func groups(for section: FLSection) -> [Group] {
        switch section {
        case .general:
            return [
                Group(title: String(localized: "Projet"),
                      keys: ["cmd-z", "cmd-opt-z", "cmd-s", "cmd-shift-s", "cmd-n", "cmd-o"]),
                Group(title: String(localized: "Export"), keys: ["cmd-r", "cmd-shift-r", "cmd-shift-m"]),
                Group(title: String(localized: "Fenêtres"),
                      keys: ["cmd-shift-h", "f5", "f6", "f7", "f8", "f9", "opt-f8", "f10", "f11", "f12", "f1", "f3",
                             "tab", "esc", "return"]),
                Group(title: String(localized: "Projets récents"), keys: (0...9).map { "opt-\($0)" }),
            ]
        case .transport:
            return [
                Group(title: String(localized: "Lecture"),
                      keys: ["space", "cmd-space", "l", "np0", "npmul", "npdiv", "bksp", "cmd-h"]),
                Group(title: String(localized: "Enregistrement"), keys: ["r", "cmd-m", "cmd-p", "cmd-i", "cmd-b", "cmd-e"]),
                Group(title: String(localized: "Clavier-piano"), keys: ["cmd-t"] + (2...6).map { "opt-np\($0)" }),
            ]
        case .patterns:
            return [
                Group(title: String(localized: "Choisir"), keys: (1...9).map { "np\($0)" } + ["npplus", "npminus"]),
                Group(title: String(localized: "Créer et renommer"), keys: ["cmd-f4", "f4", "f2"]),
            ]
        case .playlist:
            return [
                Group(title: String(localized: "Outils"), keys: ["p", "b", "d", "t", "s", "c", "e", "y", "z"]),
                Group(title: String(localized: "Sélection"),
                      keys: ["cmd-a", "cmd-d", "shift-i", "shift-c", "shift-g", "opt-g", "cmd-left", "cmd-right",
                             "cmd-return"]),
                Group(title: String(localized: "Édition"),
                      keys: ["cmd-c", "cmd-x", "cmd-v", "cmd-b", "del", "7", "8", "9", "opt-m", "opt-shift-m",
                             "shift-left", "shift-right", "shift-up", "shift-down", "cmd-opt-c", "cmd-opt-shift-c",
                             "cmd-opt-home", "shift-m", "shift-q"]),
                Group(title: String(localized: "Zoom"),
                      keys: ["pgup", "pgdn", "5", "6", "home"] + (0...6).map { "shift-\($0)" }),
                Group(title: String(localized: "Marqueurs"), keys: ["opt-t", "opt-npmul", "opt-npdiv", "cmd-t", "shift-opt-t"]),
                Group(title: String(localized: "Affichage"), keys: ["bksp", "opt-p", "cmd-opt-g", "cmd-f8", "cmd-p"]),
            ]
        case .pianoRoll:
            return [
                Group(title: String(localized: "Outils"), keys: ["p", "b", "d", "t", "c", "e", "y", "z"]),
                Group(title: String(localized: "Outils de notes"),
                      keys: ["opt-a", "opt-e", "opt-f", "opt-k", "opt-l", "opt-o", "opt-q", "opt-r", "opt-s", "opt-u",
                             "opt-w", "opt-x", "opt-y", "cmd-opt-q", "cmd-l", "cmd-u", "cmd-g"]),
                Group(title: String(localized: "Sélection"),
                      keys: ["cmd-a", "cmd-d", "shift-i", "shift-c", "shift-g", "opt-g", "shift-m", "shift-r",
                             "cmd-left", "cmd-right", "cmd-return"]),
                Group(title: String(localized: "Édition"),
                      keys: ["cmd-c", "cmd-x", "cmd-v", "shift-cmd-v", "cmd-b", "del", "opt-left", "opt-right", "opt-up",
                             "opt-down", "shift-left", "shift-right", "shift-up", "shift-down", "cmd-up", "cmd-down",
                             "opt-m", "opt-shift-m", "shift-d", "s", "o", "cmd-i", "cmd-m", "cmd-opt-home", "opt-c",
                             "shift-n"]),
                Group(title: String(localized: "Zoom"), keys: ["pgup", "pgdn"] + (0...5).map { "shift-\($0)" }),
                Group(title: String(localized: "Instruments"), keys: ["g", "h", "j", "k", "shift-h", "shift-k", "opt-v"]),
                Group(title: String(localized: "Affichage"),
                      keys: ["m", "f", "shift-f", "opt-b", "opt-n", "cmd-opt-g", "shift-opt-t", "bksp"]),
            ]
        case .channelRack:
            return [
                Group(title: String(localized: "Mute"), keys: (1...9).map { "\($0)" } + ["0"]),
                Group(title: String(localized: "Solo"), keys: (1...9).map { "cmd-\($0)" } + ["cmd-0"]),
                Group(title: String(localized: "Canaux"),
                      keys: ["down", "up", "pgup", "pgdn", "opt-c", "opt-del", "opt-down", "opt-up", "opt-g", "opt-m",
                             "opt-u", "opt-z", "cmd-l", "cmd-opt-r", "shift-down", "shift-up", "cmd-return"]),
                Group(title: String(localized: "Pas"), keys: ["cmd-c", "cmd-v", "cmd-x", "shift-cmd-left", "shift-cmd-right"]),
            ]
        case .mixer:
            return [
                Group(title: String(localized: "Pistes"),
                      keys: ["s", "opt-left", "opt-right", "opt-r", "opt-s", "opt-w", "cmd-a", "cmd-shift-s",
                             "ctrl-return", "f2"]),
                Group(title: String(localized: "Liens"), keys: ["opt-l", "cmd-l", "shift-cmd-l"]),
            ]
        case .browser:
            return [Group(title: String(localized: "Navigation"), keys: ["return", "shift-up", "shift-down"])]
        }
    }

    /// Fin de l'identifiant d'un raccourci d'origine de FL (« fl.playlist.cmd-a » → « cmd-a »).
    static func key(of entry: CatalogEntry) -> String {
        let prefix = "fl.\(entry.section.rawValue)."
        return entry.id.hasPrefix(prefix) ? String(entry.id.dropFirst(prefix.count)) : entry.id
    }

    /// Pur (testé) : les raccourcis d'origine d'une page, carte par carte, chacun dans l'ordre du catalogue ; sans
    /// groupe : « Autres », à la fin. Les cartes vides ne sont pas gardées.
    static func cards<Row>(for section: FLSection, rows: [Row], entry: (Row) -> CatalogEntry) -> [(title: String, rows: [Row])] {
        let groups = groups(for: section)
        var index: [String: Int] = [:]
        for (i, group) in groups.enumerated() {
            for key in group.keys where index[key] == nil { index[key] = i }
        }
        var filled = Array(repeating: [Row](), count: groups.count)
        var others: [Row] = []
        for row in rows {
            if let i = index[key(of: entry(row))] { filled[i].append(row) } else { others.append(row) }
        }
        var out = zip(groups, filled).filter { !$0.1.isEmpty }.map { (title: $0.0.title, rows: $0.1) }
        if !others.isEmpty { out.append((title: String(localized: "Autres"), rows: others)) }
        return out
    }
}
