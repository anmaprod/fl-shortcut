// Catalogue de tous les raccourcis, rangés par fenêtre de FL Studio (retour utilisateur : « tout sur la
// première page, section par section, sans avoir à chercher »). Chaque entrée a une valeur d'origine et un
// bouton « Réinitialiser ».
// - Actions FL Shortcut (script MIDI) : valeur d'origine = profil Recommandé (ou aucune touche).
// - Raccourcis natifs de FL : valeur d'origine = la touche de FL. Les changer crée un raccourci « Touche de FL »
//   (ta touche → la touche de FL, dans la fenêtre concernée) ; réinitialiser le retire.
import Foundation

enum FLSection: String, CaseIterable, Identifiable {
    case general, transport, playlist, pianoRoll, channelRack, mixer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "Général"
        case .transport: return "Lecture et enregistrement"
        case .playlist: return "Playlist"
        case .pianoRoll: return "Piano Roll"
        case .channelRack: return "Channel Rack"
        case .mixer: return "Mixer"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "Fenêtres, annuler, sauvegarder — partout dans FL"
        case .transport: return "Lecture, REC, métronome, décompte"
        case .playlist: return "Patterns et outils de la Playlist"
        case .pianoRoll: return "Grille, quantize et outils du Piano Roll"
        case .channelRack: return "Instruments et presets"
        case .mixer: return "Pistes, mute, solo, volume, effets"
        }
    }

    /// Symbole SF de la section.
    var symbol: String {
        switch self {
        case .general: return "square.grid.2x2.fill"
        case .transport: return "record.circle.fill"
        case .playlist: return "rectangle.split.3x1.fill"
        case .pianoRoll: return "pianokeys"
        case .channelRack: return "square.stack.3d.up.fill"
        case .mixer: return "slider.vertical.3"
        }
    }

    /// Fenêtre de FL où un raccourci natif de la section s'applique.
    var context: ShortcutContext {
        switch self {
        case .playlist: return .playlist
        case .pianoRoll: return .pianoRoll
        case .mixer: return .mixer
        default: return .everywhere
        }
    }
}

struct CatalogEntry: Identifiable, Hashable {
    enum Kind: Hashable {
        case action(Int)          // action du script FL Shortcut
        case native(KeyCombo)     // raccourci d'origine de FL Studio
    }

    let id: String
    let section: FLSection
    let title: String
    let detail: String
    let kind: Kind
    /// Touche d'origine : profil Recommandé pour une action, la touche de FL pour un raccourci natif.
    let defaultTrigger: KeyCombo?
}

enum Catalog {
    /// Section de chaque action du script (clé du protocole).
    static let actionSection: [String: FLSection] = [
        "pl": .general, "cr": .general, "pr": .general, "mx": .general, "br": .general, "plmx": .general,
        "undo": .general, "redo": .general, "save": .general,
        "play": .transport, "stop": .transport, "rec": .transport, "metro": .transport, "count": .transport,
        "loop": .transport, "wait": .transport, "marker": .transport, "tap": .transport,
        "newpat": .playlist, "clone": .playlist, "pnext": .playlist, "pprev": .playlist,
        "snap": .pianoRoll, "quant": .pianoRoll,
        "chnext": .channelRack, "chprev": .channelRack, "presetnext": .channelRack, "presetprev": .channelRack,
        "arm": .mixer, "mute": .mixer, "solo": .mixer, "unsolo": .mixer, "bypass": .mixer, "mono": .mixer,
        "trnext": .mixer, "trprev": .mixer, "volup": .mixer, "voldn": .mixer,
    ]

    /// Tous les raccourcis, dans l'ordre d'affichage : par section, raccourcis natifs de FL puis actions.
    static func entries(layout: KeyboardLayout) -> [CatalogEntry] {
        func key(_ ch: String, _ fallback: UInt16) -> UInt16 { KeyNames.keyCode(for: ch, layout: layout) ?? fallback }
        func cmd(_ ch: String, _ fallback: UInt16, shift: Bool = false) -> KeyCombo {
            KeyCombo(keyCode: KeyNames.commandKeyCode(for: ch, layout: layout) ?? fallback, command: true, shift: shift)
        }

        var defaults: [Int: KeyCombo] = [:]
        for r in ProfilePreset.recommended.remaps(layout: layout) {
            if let id = r.actionID, let t = r.trigger { defaults[id] = t }
        }

        var out: [CatalogEntry] = []
        func native(_ section: FLSection, _ id: String, _ title: String, _ detail: String, _ combo: KeyCombo) {
            out.append(CatalogEntry(id: "fl.\(section.rawValue).\(id)", section: section, title: title, detail: detail,
                                    kind: .native(combo), defaultTrigger: combo))
        }

        for section in FLSection.allCases {
            switch section {
            case .general:
                native(section, "f5", "Afficher la Playlist", "Raccourci de FL : F5", KeyCombo(keyCode: 96))
                native(section, "f6", "Afficher le Channel Rack", "Raccourci de FL : F6", KeyCombo(keyCode: 97))
                native(section, "f7", "Afficher le Piano Roll", "Raccourci de FL : F7", KeyCombo(keyCode: 98))
                native(section, "f8", "Choisir un plugin", "Raccourci de FL : F8", KeyCombo(keyCode: 100))
                native(section, "f9", "Afficher le Mixer", "Raccourci de FL : F9", KeyCombo(keyCode: 101))
                native(section, "save", "Enregistrer le projet", "Raccourci de FL", cmd("s", 1))
                native(section, "undo", "Annuler", "Raccourci de FL", cmd("z", 6))
                native(section, "open", "Ouvrir un projet", "Raccourci de FL", cmd("o", 31))
                native(section, "new", "Nouveau projet", "Raccourci de FL", cmd("n", 45))
                native(section, "wav", "Exporter en WAV", "Raccourci de FL", cmd("r", 15))
            case .transport:
                native(section, "space", "Lecture / Stop", "Raccourci de FL : barre d'espace", KeyCombo(keyCode: 49))
                native(section, "rec", "Enregistrement", "Raccourci de FL", KeyCombo(keyCode: key("r", 15)))
                native(section, "mode", "Bascule Pattern / Song", "Raccourci de FL", KeyCombo(keyCode: key("l", 37)))
            case .playlist, .pianoRoll:
                let tools: [(String, UInt16, String)] = section == .playlist
                    ? [("p", 35, "Outil crayon"), ("b", 11, "Outil pinceau"), ("d", 2, "Outil suppression"),
                       ("t", 17, "Outil mute"), ("s", 1, "Outil slip"), ("c", 8, "Outil découpe"),
                       ("e", 14, "Outil sélection"), ("z", 6, "Outil zoom"), ("y", 16, "Outil lecture")]
                    : [("p", 35, "Outil crayon"), ("b", 11, "Outil pinceau"), ("d", 2, "Outil suppression"),
                       ("t", 17, "Outil mute"), ("c", 8, "Outil découpe"), ("e", 14, "Outil sélection"),
                       ("z", 6, "Outil zoom"), ("y", 16, "Outil lecture")]
                for (ch, fallback, title) in tools {
                    native(section, ch, title, "Raccourci de FL dans la \(section == .playlist ? "Playlist" : "fenêtre Piano Roll")",
                           KeyCombo(keyCode: key(ch, fallback)))
                }
            case .channelRack, .mixer:
                break
            }
            for info in FLActions.all where actionSection[info.key] == section {
                out.append(CatalogEntry(id: "action.\(info.key)", section: section, title: info.label, detail: info.detail,
                                        kind: .action(info.id), defaultTrigger: defaults[info.id]))
            }
        }
        return out
    }
}

/// État d'une entrée dans le profil actuel.
struct CatalogRow: Identifiable {
    let entry: CatalogEntry
    /// Raccourci du profil qui porte cette entrée (s'il y en a un).
    let remap: Remap?
    /// Touche actuelle : celle du profil, sinon la touche d'origine (natif) ou aucune (action).
    let current: KeyCombo?
    var id: String { entry.id }
    var isDefault: Bool { current == entry.defaultTrigger }
}

extension Store {
    var catalog: [CatalogEntry] { Catalog.entries(layout: layout) }

    /// Associe chaque entrée du catalogue au raccourci du profil qui la porte ; le reste va dans `others`.
    func catalogRows() -> (rows: [CatalogRow], others: [Remap]) {
        var claimed = Set<UUID>()
        var rows: [CatalogRow] = []
        for entry in catalog {
            switch entry.kind {
            case .action(let id):
                let remap = remaps.first { $0.kind == .flAction && $0.actionID == id && !claimed.contains($0.id) }
                if let remap { claimed.insert(remap.id) }
                let current = (remap?.enabled ?? false) ? remap?.trigger : nil
                rows.append(CatalogRow(entry: entry, remap: remap, current: current))
            case .native(let combo):
                let remap = remaps.first {
                    $0.kind == .keystroke && $0.target == combo && $0.context == entry.section.context && !claimed.contains($0.id)
                }
                if let remap { claimed.insert(remap.id) }
                let current = (remap?.enabled ?? false) ? (remap?.trigger ?? combo) : combo
                rows.append(CatalogRow(entry: entry, remap: remap, current: current))
            }
        }
        return (rows, remaps.filter { !claimed.contains($0.id) })
    }

    /// Brouillon de raccourci pour une entrée avec une nouvelle touche (sert à l'analyse des conflits).
    func draft(for row: CatalogRow, trigger: KeyCombo?) -> Remap {
        switch row.entry.kind {
        case .action(let id):
            var r = row.remap ?? Remap(trigger: nil, action: id)
            r.trigger = trigger
            r.enabled = true
            return r
        case .native(let combo):
            var r = row.remap ?? Remap(trigger: nil, sends: combo, context: row.entry.section.context)
            r.trigger = trigger
            r.enabled = true
            return r
        }
    }

    /// Change la touche d'une entrée. `nil` = aucune touche (actions seulement).
    func setTrigger(_ trigger: KeyCombo?, for row: CatalogRow) {
        switch row.entry.kind {
        case .action:
            if trigger == nil {
                if let remap = row.remap { delete(remap.id) }
            } else {
                upsert(draft(for: row, trigger: trigger))
            }
        case .native(let combo):
            if trigger == nil || trigger == combo {
                if let remap = row.remap { delete(remap.id) }   // la touche de FL suffit
            } else {
                upsert(draft(for: row, trigger: trigger))
            }
        }
    }

    /// Revient à la touche d'origine.
    func reset(_ row: CatalogRow) { setTrigger(row.entry.defaultTrigger, for: row) }

    /// Tout remettre comme à l'origine (profil Recommandé), annulable.
    func resetAll() { apply(preset: .recommended) }
}
