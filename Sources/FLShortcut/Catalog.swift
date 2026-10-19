// Catalogue de TOUS les raccourcis, rangés par fenêtre de FL Studio (retour utilisateur : « tout sur la première
// page, section par section, sans avoir à chercher »). Chaque entrée a une touche d'origine et « Réinitialiser ».
// - Raccourcis d'origine de FL : liste complète du manuel d'Image-Line (« Keyboard shortcuts »), en notation Mac
//   (Ctrl → ⌘, Alt → ⌥, Retour arrière → ⌫, Suppr → ⌦). Les raccourcis à la souris n'y sont pas (rien à remapper).
//   Les changer crée un raccourci « Touche de FL » (ta touche → la touche de FL, dans la fenêtre concernée) ;
//   « Réinitialiser » le retire. La touche d'origine continue de marcher.
// - Actions en plus (script FL Shortcuts) : touche d'origine = profil Recommandé, ou aucune.
import Foundation

enum FLSection: String, CaseIterable, Identifiable {
    case general, transport, patterns, playlist, pianoRoll, channelRack, mixer, browser

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return String(localized: "Général")
        case .transport: return String(localized: "Lecture et enregistrement")
        case .patterns: return String(localized: "Patterns")
        case .playlist: return String(localized: "Playlist")
        case .pianoRoll: return String(localized: "Piano Roll")
        case .channelRack: return String(localized: "Channel Rack")
        case .mixer: return String(localized: "Mixer")
        case .browser: return String(localized: "Browser")
        }
    }

    var subtitle: String {
        switch self {
        case .general: return String(localized: "Fichier, fenêtres, annuler — partout dans FL")
        case .transport: return String(localized: "Lecture, REC, métronome, décompte")
        case .patterns: return String(localized: "Choisir, créer et renommer les patterns")
        case .playlist: return String(localized: "Outils, sélection, zoom, marqueurs")
        case .pianoRoll: return String(localized: "Outils, notes, quantize, instruments")
        case .channelRack: return String(localized: "Canaux, mute, solo, pas")
        case .mixer: return String(localized: "Pistes, solo, liens, rendu")
        case .browser: return String(localized: "Parcourir et charger des sons")
        }
    }

    /// Symbole SF de la section (barre latérale : symboles au trait, monochromes).
    var symbol: String {
        switch self {
        case .general: return "square.grid.2x2"
        case .transport: return "record.circle"
        case .patterns: return "square.stack"
        case .playlist: return "rectangle.split.3x1"
        case .pianoRoll: return "pianokeys"
        case .channelRack: return "square.stack.3d.up"
        case .mixer: return "slider.vertical.3"
        case .browser: return "folder"
        }
    }

    /// Fenêtre de FL où un raccourci d'origine de la section s'applique.
    var context: ShortcutContext {
        switch self {
        case .playlist: return .playlist
        case .pianoRoll: return .pianoRoll
        case .mixer: return .mixer
        case .channelRack: return .channelRack
        case .browser: return .browser
        case .general, .transport, .patterns: return .everywhere
        }
    }
}

struct CatalogEntry: Identifiable, Hashable {
    enum Kind: Hashable {
        case action(Int)          // action du script FL Shortcuts
        case native(KeyCombo)     // raccourci d'origine de FL Studio
    }

    let id: String
    let section: FLSection
    let title: String
    let detail: String
    let kind: Kind
    /// Touche d'origine : profil Recommandé pour une action, la touche de FL pour un raccourci d'origine.
    let defaultTrigger: KeyCombo?

    var isNative: Bool {
        if case .native = kind { return true }
        return false
    }
}

enum Catalog {
    /// Section de chaque action du script (clé du protocole).
    static let actionSection: [String: FLSection] = [
        "pl": .general, "cr": .general, "pr": .general, "mx": .general, "br": .general, "plmx": .general,
        "undo": .general, "redo": .general, "save": .general,
        "play": .transport, "stop": .transport, "rec": .transport, "recon": .transport, "metro": .transport, "count": .transport,
        "loop": .transport, "wait": .transport, "marker": .transport, "tap": .transport,
        "newpat": .patterns, "clone": .patterns, "pnext": .patterns, "pprev": .patterns,
        "snap": .pianoRoll, "quant": .pianoRoll,
        "chnext": .channelRack, "chprev": .channelRack, "presetnext": .channelRack, "presetprev": .channelRack,
        "arm": .mixer, "armon": .mixer, "mute": .mixer, "solo": .mixer, "unsolo": .mixer, "bypass": .mixer, "mono": .mixer,
        "trnext": .mixer, "trprev": .mixer, "volup": .mixer, "voldn": .mixer,
    ]

    /// Tous les raccourcis, dans l'ordre d'affichage : par section, raccourcis d'origine de FL puis actions en plus.
    static func entries(layout: KeyboardLayout) -> [CatalogEntry] {
        /// Lettre résolue selon la disposition (AZERTY…), repli QWERTY. Avec ⌘ : la touche qui produit la lettre avec ⌘.
        func ch(_ letter: String, _ fallback: UInt16, cmd: Bool = false, opt: Bool = false, ctrl: Bool = false,
                shift: Bool = false) -> KeyCombo {
            let code = (cmd ? KeyNames.commandKeyCode(for: letter, layout: layout) : KeyNames.keyCode(for: letter, layout: layout))
                ?? fallback
            return KeyCombo(keyCode: code, command: cmd, option: opt, control: ctrl, shift: shift)
        }
        /// Touche physique (chiffres de la rangée, pavé numérique, F1…F12, flèches…).
        func kc(_ code: UInt16, cmd: Bool = false, opt: Bool = false, ctrl: Bool = false, shift: Bool = false) -> KeyCombo {
            KeyCombo(keyCode: code, command: cmd, option: opt, control: ctrl, shift: shift)
        }

        var defaults: [Int: KeyCombo] = [:]
        for r in ProfilePreset.recommended.remaps(layout: layout) {
            if let id = r.actionID, let t = r.trigger { defaults[id] = t }
        }

        var out: [CatalogEntry] = []
        for section in FLSection.allCases {
            func n(_ id: String, _ title: String, _ combo: KeyCombo) {
                out.append(CatalogEntry(id: "fl.\(section.rawValue).\(id)", section: section, title: title,
                                        detail: String(localized: "Raccourci d'origine de FL Studio"), kind: .native(combo),
                                        defaultTrigger: combo))
            }
            switch section {
        case .general:
            n("cmd-z", String(localized: "Annuler / rétablir la dernière modification"), ch("z", 6, cmd: true))
            n("cmd-opt-z", String(localized: "Annuler pas à pas"), ch("z", 6, cmd: true, opt: true))
            n("cmd-s", String(localized: "Enregistrer le projet"), ch("s", 1, cmd: true))
            n("cmd-shift-s", String(localized: "Enregistrer sous"), ch("s", 1, cmd: true, shift: true))
            n("cmd-n", String(localized: "Enregistrer une nouvelle version"), ch("n", 45, cmd: true))
            n("cmd-o", String(localized: "Ouvrir un projet"), ch("o", 31, cmd: true))
            n("cmd-r", String(localized: "Exporter en WAV"), ch("r", 15, cmd: true))
            n("cmd-shift-r", String(localized: "Exporter en MP3"), ch("r", 15, cmd: true, shift: true))
            n("cmd-shift-m", String(localized: "Exporter en MIDI"), ch("m", 46, cmd: true, shift: true))
            n("cmd-shift-h", String(localized: "Réorganiser les fenêtres"), ch("h", 4, cmd: true, shift: true))
            n("f5", String(localized: "Afficher / masquer la Playlist"), kc(96))
            n("f6", String(localized: "Afficher / masquer le Channel Rack"), kc(97))
            n("f7", String(localized: "Afficher / masquer le Piano Roll"), kc(98))
            n("f8", String(localized: "Ouvrir le Plugin Picker"), kc(100))
            n("f9", String(localized: "Afficher / masquer le Mixer"), kc(101))
            n("opt-f8", String(localized: "Afficher / masquer le Browser"), kc(100, opt: true))
            n("f10", String(localized: "Réglages MIDI"), kc(109))
            n("f11", String(localized: "Infos du morceau"), kc(103))
            n("f12", String(localized: "Fermer toutes les fenêtres"), kc(111))
            n("f1", String(localized: "Aide"), kc(122))
            n("f3", String(localized: "Choisir un outil de la fenêtre active"), kc(99))
            n("tab", String(localized: "Passer d'une fenêtre à l'autre"), kc(48))
            n("esc", String(localized: "Fermer la fenêtre"), kc(53))
            n("return", String(localized: "Agrandir / réduire la Playlist"), kc(36))
            n("opt-0", String(localized: "Ouvrir le projet récent 0"), kc(29, opt: true))
            n("opt-1", String(localized: "Ouvrir le projet récent 1"), kc(18, opt: true))
            n("opt-2", String(localized: "Ouvrir le projet récent 2"), kc(19, opt: true))
            n("opt-3", String(localized: "Ouvrir le projet récent 3"), kc(20, opt: true))
            n("opt-4", String(localized: "Ouvrir le projet récent 4"), kc(21, opt: true))
            n("opt-5", String(localized: "Ouvrir le projet récent 5"), kc(23, opt: true))
            n("opt-6", String(localized: "Ouvrir le projet récent 6"), kc(22, opt: true))
            n("opt-7", String(localized: "Ouvrir le projet récent 7"), kc(26, opt: true))
            n("opt-8", String(localized: "Ouvrir le projet récent 8"), kc(28, opt: true))
            n("opt-9", String(localized: "Ouvrir le projet récent 9"), kc(25, opt: true))
        case .transport:
            n("space", String(localized: "Lecture / Stop"), kc(49))
            n("cmd-space", String(localized: "Lecture / Pause"), kc(49, cmd: true))
            n("r", String(localized: "Activer / couper l'enregistrement"), ch("r", 15))
            n("l", String(localized: "Bascule Pattern / Song"), ch("l", 37))
            n("cmd-m", String(localized: "Métronome"), ch("m", 46, cmd: true))
            n("cmd-p", String(localized: "Décompte avant l'enregistrement"), ch("p", 35, cmd: true))
            n("cmd-i", String(localized: "Attendre une note pour lancer l'enregistrement"), ch("i", 34, cmd: true))
            n("cmd-b", String(localized: "Mélanger les notes enregistrées (blend)"), ch("b", 11, cmd: true))
            n("cmd-e", String(localized: "Mode Step Edit"), ch("e", 14, cmd: true))
            n("cmd-h", String(localized: "Couper tous les sons (panique)"), ch("h", 4, cmd: true))
            n("cmd-t", String(localized: "Clavier d'ordinateur → clavier-piano"), ch("t", 17, cmd: true))
            n("bksp", String(localized: "Magnétisme : Ligne / Aucun"), kc(51))
            n("np0", String(localized: "Avance rapide"), kc(82))
            n("npmul", String(localized: "Mesure suivante (mode Song)"), kc(67))
            n("npdiv", String(localized: "Mesure précédente (mode Song)"), kc(75))
            n("opt-np2", String(localized: "Clavier-piano : octave 2"), kc(84, opt: true))
            n("opt-np3", String(localized: "Clavier-piano : octave 3"), kc(85, opt: true))
            n("opt-np4", String(localized: "Clavier-piano : octave 4"), kc(86, opt: true))
            n("opt-np5", String(localized: "Clavier-piano : octave 5"), kc(87, opt: true))
            n("opt-np6", String(localized: "Clavier-piano : octave 6"), kc(88, opt: true))
        case .patterns:
            n("np1", String(localized: "Choisir le pattern 1"), kc(83))
            n("np2", String(localized: "Choisir le pattern 2"), kc(84))
            n("np3", String(localized: "Choisir le pattern 3"), kc(85))
            n("np4", String(localized: "Choisir le pattern 4"), kc(86))
            n("np5", String(localized: "Choisir le pattern 5"), kc(87))
            n("np6", String(localized: "Choisir le pattern 6"), kc(88))
            n("np7", String(localized: "Choisir le pattern 7"), kc(89))
            n("np8", String(localized: "Choisir le pattern 8"), kc(91))
            n("np9", String(localized: "Choisir le pattern 9"), kc(92))
            n("npplus", String(localized: "Pattern suivant"), kc(69))
            n("npminus", String(localized: "Pattern précédent"), kc(78))
            n("cmd-f4", String(localized: "Pattern vide suivant"), kc(118, cmd: true))
            n("f4", String(localized: "Pattern vide suivant, avec son nom"), kc(118))
            n("f2", String(localized: "Renommer le pattern (et changer sa couleur)"), kc(120))
        case .playlist:
            n("p", String(localized: "Outil crayon"), ch("p", 35))
            n("b", String(localized: "Outil pinceau"), ch("b", 11))
            n("d", String(localized: "Outil suppression"), ch("d", 2))
            n("t", String(localized: "Outil mute"), ch("t", 17))
            n("s", String(localized: "Outil slip"), ch("s", 1))
            n("c", String(localized: "Outil découpe"), ch("c", 8))
            n("e", String(localized: "Outil sélection"), ch("e", 14))
            n("y", String(localized: "Outil lecture"), ch("y", 16))
            n("z", String(localized: "Outil zoom"), ch("z", 6))
            n("5", String(localized: "Zoomer sur la sélection"), kc(23))
            n("6", String(localized: "Zoomer sur les Performance Clips"), kc(22))
            n("7", String(localized: "Transposer vers le bas"), kc(26))
            n("8", String(localized: "Transposer vers le haut"), kc(28))
            n("9", String(localized: "Inverser (clips audio)"), kc(25))
            n("bksp", String(localized: "Magnétisme global"), kc(51))
            n("del", String(localized: "Supprimer la source du clip / pattern"), kc(117))
            n("home", String(localized: "Tête de lecture au début"), kc(115))
            n("opt-m", String(localized: "Mettre la sélection en mute"), ch("m", 46, opt: true))
            n("opt-shift-m", String(localized: "Enlever le mute de la sélection"), ch("m", 46, opt: true, shift: true))
            n("opt-g", String(localized: "Dégrouper la sélection"), ch("g", 5, opt: true))
            n("opt-p", String(localized: "Ouvrir le Picker Panel"), ch("p", 35, opt: true))
            n("opt-t", String(localized: "Ajouter un marqueur"), ch("t", 17, opt: true))
            n("opt-npmul", String(localized: "Marqueur suivant"), kc(67, opt: true))
            n("opt-npdiv", String(localized: "Marqueur précédent"), kc(75, opt: true))
            n("cmd-a", String(localized: "Tout sélectionner"), ch("a", 0, cmd: true))
            n("cmd-opt-c", String(localized: "Consolider les clips (depuis le premier)"), ch("c", 8, cmd: true, opt: true))
            n("cmd-opt-shift-c", String(localized: "Consolider les clips (depuis le début)"), ch("c", 8, cmd: true, opt: true, shift: true))
            n("cmd-opt-g", String(localized: "Couleur de la grille"), ch("g", 5, cmd: true, opt: true))
            n("cmd-opt-home", String(localized: "Redimensionner par la gauche"), kc(115, cmd: true, opt: true))
            n("cmd-b", String(localized: "Dupliquer la sélection à droite"), ch("b", 11, cmd: true))
            n("cmd-c", String(localized: "Copier"), ch("c", 8, cmd: true))
            n("cmd-d", String(localized: "Désélectionner"), ch("d", 2, cmd: true))
            n("cmd-f8", String(localized: "Ouvrir le Project Picker"), kc(100, cmd: true))
            n("cmd-left", String(localized: "Sélectionner le temps avant"), kc(123, cmd: true))
            n("cmd-right", String(localized: "Sélectionner le temps après"), kc(124, cmd: true))
            n("cmd-p", String(localized: "Mode Performance"), ch("p", 35, cmd: true))
            n("cmd-t", String(localized: "Ajouter un marqueur de temps"), ch("t", 17, cmd: true))
            n("cmd-v", String(localized: "Coller"), ch("v", 9, cmd: true))
            n("cmd-x", String(localized: "Couper"), ch("x", 7, cmd: true))
            n("cmd-return", String(localized: "Sélectionner le temps autour de la sélection"), kc(36, cmd: true))
            n("pgup", String(localized: "Zoom avant"), kc(116))
            n("pgdn", String(localized: "Zoom arrière"), kc(121))
            n("shift-0", String(localized: "Centrer sur la tête de lecture"), kc(29, shift: true))
            n("shift-1", String(localized: "Zoom horizontal niveau 1"), kc(18, shift: true))
            n("shift-2", String(localized: "Zoom horizontal niveau 2"), kc(19, shift: true))
            n("shift-3", String(localized: "Zoom horizontal niveau 3"), kc(20, shift: true))
            n("shift-4", String(localized: "Tout afficher"), kc(21, shift: true))
            n("shift-5", String(localized: "Zoomer sur la sélection"), kc(23, shift: true))
            n("shift-6", String(localized: "Ajuster à la zone Performance"), kc(22, shift: true))
            n("shift-opt-t", String(localized: "Choisir une signature rythmique"), ch("t", 17, opt: true, shift: true))
            n("shift-c", String(localized: "Sélectionner les clips de même source"), ch("c", 8, shift: true))
            n("shift-g", String(localized: "Grouper les clips"), ch("g", 5, shift: true))
            n("shift-i", String(localized: "Inverser la sélection"), ch("i", 34, shift: true))
            n("shift-left", String(localized: "Déplacer la sélection à gauche"), kc(123, shift: true))
            n("shift-right", String(localized: "Déplacer la sélection à droite"), kc(124, shift: true))
            n("shift-up", String(localized: "Déplacer la sélection vers le haut"), kc(126, shift: true))
            n("shift-down", String(localized: "Déplacer la sélection vers le bas"), kc(125, shift: true))
            n("shift-m", String(localized: "Changer le mode de stretch"), ch("m", 46, shift: true))
            n("shift-q", String(localized: "Quantize rapide du début des clips"), ch("q", 12, shift: true))
        case .pianoRoll:
            n("p", String(localized: "Outil crayon"), ch("p", 35))
            n("b", String(localized: "Outil pinceau"), ch("b", 11))
            n("d", String(localized: "Outil suppression"), ch("d", 2))
            n("t", String(localized: "Outil mute"), ch("t", 17))
            n("c", String(localized: "Outil découpe"), ch("c", 8))
            n("e", String(localized: "Outil sélection"), ch("e", 14))
            n("y", String(localized: "Outil lecture"), ch("y", 16))
            n("z", String(localized: "Outil zoom"), ch("z", 6))
            n("s", String(localized: "Notes glissées (slide)"), ch("s", 1))
            n("o", String(localized: "Portamento"), ch("o", 31))
            n("f", String(localized: "Propriété suivante dans la zone d'événements"), ch("f", 3))
            n("g", String(localized: "Instrument au-dessus"), ch("g", 5))
            n("h", String(localized: "Instrument au-dessus avec des notes"), ch("h", 4))
            n("j", String(localized: "Instrument en dessous avec des notes"), ch("j", 38))
            n("k", String(localized: "Instrument en dessous"), ch("k", 40))
            n("m", String(localized: "Mode d'affichage du clavier"), ch("m", 46))
            n("bksp", String(localized: "Magnétisme global"), kc(51))
            n("del", String(localized: "Supprimer la sélection"), kc(117))
            n("pgup", String(localized: "Zoom avant"), kc(116))
            n("pgdn", String(localized: "Zoom arrière"), kc(121))
            n("opt-a", String(localized: "Arpégiateur"), ch("a", 0, opt: true))
            n("opt-left", String(localized: "Décaler à gauche"), kc(123, opt: true))
            n("opt-right", String(localized: "Décaler à droite"), kc(124, opt: true))
            n("opt-up", String(localized: "Décaler vers le haut"), kc(126, opt: true))
            n("opt-down", String(localized: "Décaler vers le bas"), kc(125, opt: true))
            n("opt-b", String(localized: "Aides de notes"), ch("b", 11, opt: true))
            n("opt-c", String(localized: "Couleur des notes"), ch("c", 8, opt: true))
            n("opt-e", String(localized: "Riff Machine"), ch("e", 14, opt: true))
            n("opt-f", String(localized: "Flam"), ch("f", 3, opt: true))
            n("opt-g", String(localized: "Dégrouper les notes"), ch("g", 5, opt: true))
            n("opt-k", String(localized: "Outil Limit"), ch("k", 40, opt: true))
            n("opt-l", String(localized: "Outil Articulate"), ch("l", 37, opt: true))
            n("opt-m", String(localized: "Mettre la sélection en mute"), ch("m", 46, opt: true))
            n("opt-shift-m", String(localized: "Enlever le mute de la sélection"), ch("m", 46, opt: true, shift: true))
            n("opt-n", String(localized: "Vue forme d'onde"), ch("n", 45, opt: true))
            n("opt-o", String(localized: "Outil LFO"), ch("o", 31, opt: true))
            n("opt-q", String(localized: "Quantize"), ch("q", 12, opt: true))
            n("opt-r", String(localized: "Outil Randomize"), ch("r", 15, opt: true))
            n("opt-s", String(localized: "Outil Strum"), ch("s", 1, opt: true))
            n("opt-u", String(localized: "Outil Chop"), ch("u", 32, opt: true))
            n("opt-v", String(localized: "Ghost channels"), ch("v", 9, opt: true))
            n("opt-w", String(localized: "Claw Machine"), ch("w", 13, opt: true))
            n("opt-x", String(localized: "Scale Levels"), ch("x", 7, opt: true))
            n("opt-y", String(localized: "Score Flipper"), ch("y", 16, opt: true))
            n("cmd-a", String(localized: "Tout sélectionner"), ch("a", 0, cmd: true))
            n("cmd-opt-g", String(localized: "Couleur de la grille"), ch("g", 5, cmd: true, opt: true))
            n("cmd-opt-home", String(localized: "Redimensionner par la gauche"), kc(115, cmd: true, opt: true))
            n("cmd-b", String(localized: "Dupliquer la sélection à droite"), ch("b", 11, cmd: true))
            n("cmd-c", String(localized: "Copier"), ch("c", 8, cmd: true))
            n("cmd-d", String(localized: "Désélectionner"), ch("d", 2, cmd: true))
            n("cmd-g", String(localized: "Coller les notes entre elles (glue)"), ch("g", 5, cmd: true))
            n("cmd-i", String(localized: "Insérer la valeur du contrôleur"), ch("i", 34, cmd: true))
            n("cmd-l", String(localized: "Legato rapide"), ch("l", 37, cmd: true))
            n("cmd-left", String(localized: "Sélectionner le temps avant"), kc(123, cmd: true))
            n("cmd-right", String(localized: "Sélectionner le temps après"), kc(124, cmd: true))
            n("cmd-m", String(localized: "Importer un fichier MIDI"), ch("m", 46, cmd: true))
            n("cmd-opt-q", String(localized: "Quantize rapide"), ch("q", 12, cmd: true, opt: true))
            n("cmd-return", String(localized: "Sélectionner le temps autour de la sélection"), kc(36, cmd: true))
            n("cmd-u", String(localized: "Chop rapide"), ch("u", 32, cmd: true))
            n("cmd-up", String(localized: "Transposer d'une octave vers le haut"), kc(126, cmd: true))
            n("cmd-down", String(localized: "Transposer d'une octave vers le bas"), kc(125, cmd: true))
            n("cmd-v", String(localized: "Coller"), ch("v", 9, cmd: true))
            n("cmd-x", String(localized: "Couper"), ch("x", 7, cmd: true))
            n("shift-0", String(localized: "Centrer sur la tête de lecture"), kc(29, shift: true))
            n("shift-1", String(localized: "Zoom horizontal niveau 1"), kc(18, shift: true))
            n("shift-2", String(localized: "Zoom horizontal niveau 2"), kc(19, shift: true))
            n("shift-3", String(localized: "Zoom horizontal niveau 3"), kc(20, shift: true))
            n("shift-4", String(localized: "Tout afficher"), kc(21, shift: true))
            n("shift-5", String(localized: "Zoomer sur la sélection"), kc(23, shift: true))
            n("shift-opt-t", String(localized: "Choisir une signature rythmique"), ch("t", 17, opt: true, shift: true))
            n("shift-c", String(localized: "Sélectionner par couleur"), ch("c", 8, shift: true))
            n("shift-cmd-v", String(localized: "Coller depuis le presse-papiers MIDI"), ch("v", 9, cmd: true, shift: true))
            n("shift-d", String(localized: "Effacer la longueur des notes"), ch("d", 2, shift: true))
            n("shift-f", String(localized: "Parcourir les propriétés de note"), ch("f", 3, shift: true))
            n("shift-g", String(localized: "Grouper la sélection"), ch("g", 5, shift: true))
            n("shift-h", String(localized: "Instrument suivant avec des notes"), ch("h", 4, shift: true))
            n("shift-i", String(localized: "Inverser la sélection"), ch("i", 34, shift: true))
            n("shift-k", String(localized: "Instrument suivant"), ch("k", 40, shift: true))
            n("shift-left", String(localized: "Déplacer la sélection à gauche"), kc(123, shift: true))
            n("shift-right", String(localized: "Déplacer la sélection à droite"), kc(124, shift: true))
            n("shift-up", String(localized: "Déplacer la sélection vers le haut"), kc(126, shift: true))
            n("shift-down", String(localized: "Déplacer la sélection vers le bas"), kc(125, shift: true))
            n("shift-m", String(localized: "Sélectionner des groupes de notes au hasard"), ch("m", 46, shift: true))
            n("shift-n", String(localized: "Désactiver l'accord choisi"), ch("n", 45, shift: true))
            n("shift-r", String(localized: "Sélection au hasard"), ch("r", 15, shift: true))
        case .channelRack:
            n("1", String(localized: "Mute du canal 1"), kc(18))
            n("2", String(localized: "Mute du canal 2"), kc(19))
            n("3", String(localized: "Mute du canal 3"), kc(20))
            n("4", String(localized: "Mute du canal 4"), kc(21))
            n("5", String(localized: "Mute du canal 5"), kc(23))
            n("6", String(localized: "Mute du canal 6"), kc(22))
            n("7", String(localized: "Mute du canal 7"), kc(26))
            n("8", String(localized: "Mute du canal 8"), kc(28))
            n("9", String(localized: "Mute du canal 9"), kc(25))
            n("0", String(localized: "Mute du canal 10"), kc(29))
            n("cmd-1", String(localized: "Solo du canal 1"), kc(18, cmd: true))
            n("cmd-2", String(localized: "Solo du canal 2"), kc(19, cmd: true))
            n("cmd-3", String(localized: "Solo du canal 3"), kc(20, cmd: true))
            n("cmd-4", String(localized: "Solo du canal 4"), kc(21, cmd: true))
            n("cmd-5", String(localized: "Solo du canal 5"), kc(23, cmd: true))
            n("cmd-6", String(localized: "Solo du canal 6"), kc(22, cmd: true))
            n("cmd-7", String(localized: "Solo du canal 7"), kc(26, cmd: true))
            n("cmd-8", String(localized: "Solo du canal 8"), kc(28, cmd: true))
            n("cmd-9", String(localized: "Solo du canal 9"), kc(25, cmd: true))
            n("cmd-0", String(localized: "Solo du canal 10"), kc(29, cmd: true))
            n("down", String(localized: "Canal en dessous"), kc(125))
            n("up", String(localized: "Canal au-dessus"), kc(126))
            n("pgup", String(localized: "Groupe de canaux suivant"), kc(116))
            n("pgdn", String(localized: "Groupe de canaux précédent"), kc(121))
            n("opt-c", String(localized: "Cloner les canaux"), ch("c", 8, opt: true))
            n("opt-del", String(localized: "Supprimer les canaux"), kc(117, opt: true))
            n("opt-down", String(localized: "Descendre les canaux"), kc(125, opt: true))
            n("opt-up", String(localized: "Monter les canaux"), kc(126, opt: true))
            n("opt-g", String(localized: "Grouper les canaux"), ch("g", 5, opt: true))
            n("opt-m", String(localized: "Afficher les sélecteurs de piste Mixer"), ch("m", 46, opt: true))
            n("opt-u", String(localized: "Dézipper les canaux"), ch("u", 32, opt: true))
            n("opt-z", String(localized: "Zipper les canaux"), ch("z", 6, opt: true))
            n("cmd-opt-r", String(localized: "Re-stretch de tous les clips audio"), ch("r", 15, cmd: true, opt: true))
            n("cmd-c", String(localized: "Copier les pas / la partition"), ch("c", 8, cmd: true))
            n("cmd-l", String(localized: "Envoyer vers des pistes Mixer libres"), ch("l", 37, cmd: true))
            n("cmd-v", String(localized: "Coller les pas / la partition"), ch("v", 9, cmd: true))
            n("cmd-x", String(localized: "Couper les pas / la partition"), ch("x", 7, cmd: true))
            n("cmd-return", String(localized: "Aller à la Playlist"), kc(36, cmd: true))
            n("shift-cmd-left", String(localized: "Décaler les pas à gauche"), kc(123, cmd: true, shift: true))
            n("shift-cmd-right", String(localized: "Décaler les pas à droite"), kc(124, cmd: true, shift: true))
            n("shift-down", String(localized: "Étendre la sélection vers le bas"), kc(125, shift: true))
            n("shift-up", String(localized: "Étendre la sélection vers le haut"), kc(126, shift: true))
        case .mixer:
            n("s", String(localized: "Solo de la piste"), ch("s", 1))
            n("opt-l", String(localized: "Sélectionner les canaux liés à la piste"), ch("l", 37, opt: true))
            n("opt-left", String(localized: "Déplacer la piste à gauche"), kc(123, opt: true))
            n("opt-right", String(localized: "Déplacer la piste à droite"), kc(124, opt: true))
            n("opt-r", String(localized: "Rendu des pistes armées en .wav"), ch("r", 15, opt: true))
            n("opt-s", String(localized: "Solo avec les pistes reliées"), ch("s", 1, opt: true))
            n("opt-w", String(localized: "Vue « Wave » des vumètres"), ch("w", 13, opt: true))
            n("cmd-a", String(localized: "Sélectionner toutes les pistes"), ch("a", 0, cmd: true))
            n("cmd-l", String(localized: "Lier les canaux à la piste"), ch("l", 37, cmd: true))
            n("cmd-shift-s", String(localized: "Enregistrer l'état de la piste"), ch("s", 1, cmd: true, shift: true))
            n("ctrl-return", String(localized: "Propriétés de la piste"), kc(36, ctrl: true))
            n("f2", String(localized: "Renommer la piste"), kc(120))
            n("shift-cmd-l", String(localized: "Lier les canaux à partir de cette piste"), ch("l", 37, cmd: true, shift: true))
        case .browser:
            n("return", String(localized: "Remplacer le canal par l'élément choisi"), kc(36))
            n("shift-up", String(localized: "Élément précédent, avec préécoute"), kc(126, shift: true))
            n("shift-down", String(localized: "Élément suivant, avec préécoute"), kc(125, shift: true))
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
    /// Touche actuelle : celle du profil, sinon la touche d'origine (FL) ou aucune (action en plus).
    let current: KeyCombo?
    var id: String { entry.id }
    var isDefault: Bool { current == entry.defaultTrigger }
    /// Un autre de tes raccourcis utilise la touche de cette entrée (sa touche d'origine dans FL, ou ta touche).
    var takenBy: String? = nil
}

/// Recherche avec un raccourci appuyé : ce qui se lance sur ces touches (touche actuelle), ou les portait dans FL
/// (touche d'origine, même si elle a été changée depuis).
enum KeySearch {
    static func matches(_ row: CatalogRow, _ combo: KeyCombo) -> Bool {
        row.current == combo || row.entry.defaultTrigger == combo
    }

    static func matches(_ remap: Remap, _ combo: KeyCombo) -> Bool {
        remap.trigger == combo
    }
}

/// Ce qui utilise déjà une touche : un de tes raccourcis, ou une touche d'origine de FL.
struct KeyClash: Identifiable {
    let row: CatalogRow?          // entrée du catalogue (nil : raccourci personnalisé hors catalogue)
    let remap: Remap?             // ton raccourci qui porte la touche (nil : touche d'origine de FL)
    let title: String
    let section: String?
    var id: String { row?.id ?? remap?.id.uuidString ?? title }
    var isFLKey: Bool { remap == nil }

    var line: String {
        let place = section.map { " (\($0))" } ?? ""
        return isFLKey ? String(localized: "« \(title) »\(place), touche d'origine de FL")
            : String(localized: "« \(title) »\(place), ton raccourci")
    }
}

extension Store {
    var catalog: [CatalogEntry] {
        if let cached = catalogCache { return cached }
        var entries = Catalog.entries(layout: layout)
        if AppMode.light {
            // Mode léger : seules les actions qui ont une touche équivalente dans FL restent.
            entries.removeAll {
                if case .action(let id) = $0.kind { return AppMode.nativeEquivalent(of: id, layout: layout) == nil }
                return false
            }
        }
        catalogCache = entries
        return entries
    }

    /// Associe chaque entrée du catalogue au raccourci du profil qui la porte ; le reste va dans `others`.
    /// Les raccourcis d'origine que FL Shortcuts refuse d'envoyer (⌘⌫, ⌘Q…) ne sont pas proposés.
    func catalogRows() -> (rows: [CatalogRow], others: [Remap]) {
        var claimed = Set<UUID>()
        var rows: [CatalogRow] = []
        rows.reserveCapacity(catalog.count)
        for entry in catalog {
            switch entry.kind {
            case .action(let id):
                let remap = remaps.first { $0.kind == .flAction && $0.actionID == id && !claimed.contains($0.id) }
                if let remap { claimed.insert(remap.id) }
                let current = (remap?.enabled ?? false) ? remap?.trigger : nil
                rows.append(CatalogRow(entry: entry, remap: remap, current: current))
            case .native(let combo):
                guard forbiddenReason(combo) == nil else { continue }
                let remap = remaps.first {
                    $0.kind == .keystroke && $0.target == combo && $0.context == entry.section.context && !claimed.contains($0.id)
                }
                if let remap { claimed.insert(remap.id) }
                let current = (remap?.enabled ?? false) ? (remap?.trigger ?? combo) : combo
                rows.append(CatalogRow(entry: entry, remap: remap, current: current))
            }
        }
        // Touches prises : une touche d'origine de FL (ou ta touche) réutilisée par un AUTRE de tes raccourcis.
        // Les doublons propres à FL (même touche d'origine dans deux fenêtres) ne sont pas signalés.
        var owners: [KeyCombo: [String]] = [:]
        for row in rows {
            if let r = row.remap, r.enabled, let t = r.trigger { owners[t, default: []].append(row.id) }
        }
        let othersList = remaps.filter { !claimed.contains($0.id) }
        for r in othersList where r.enabled {
            if let t = r.trigger { owners[t, default: []].append(r.id.uuidString) }
        }
        let titles = Dictionary(rows.map { ($0.id, $0.entry.title) }, uniquingKeysWith: { a, _ in a })
        for i in rows.indices {
            var keys: [KeyCombo] = []
            if case .native(let k) = rows[i].entry.kind { keys.append(k) }
            if let c = rows[i].current, !keys.contains(c) { keys.append(c) }
            for k in keys {
                if let other = owners[k]?.first(where: { $0 != rows[i].id }) {
                    rows[i].takenBy = titles[other] ?? String(localized: "un raccourci personnalisé")
                    break
                }
            }
        }
        return (rows, othersList)
    }

    /// Nom lisible d'un raccourci hors catalogue.
    func remapTitle(_ r: Remap) -> String {
        if r.kind == .keystroke { return String(localized: "Envoie ") + (r.target?.display ?? String(localized: "une touche")) }
        if r.kind == .macro {
            if let ref = r.macroRef {
                return String(localized: "Macro : ")
                    + (library.doc(ref)?.name.displaySafe() ?? String(localized: "introuvable (supprimée ?)"))
            }
            return String(localized: "Macro : ") + (r.macro?.name.displaySafe() ?? String(localized: "à configurer"))
        }
        return FLActions.all.first { $0.id == r.actionID }?.label ?? String(localized: "Raccourci personnalisé")
    }

    /// Tout ce qui utilise déjà `trigger`, hors l'entrée qu'on modifie. Une même touche ne sert qu'une fois ;
    /// seule exception : revenir à la touche d'origine de FL de l'entrée elle-même.
    func clashes(for trigger: KeyCombo, editing row: CatalogRow) -> [KeyClash] {
        if case .native(let own) = row.entry.kind, own == trigger { return [] }
        let (rows, others) = catalogRows()
        var out: [KeyClash] = []
        for other in rows where other.id != row.id {
            if let r = other.remap, r.enabled, r.trigger == trigger {
                out.append(KeyClash(row: other, remap: r, title: other.entry.title, section: other.entry.section.title))
            } else if case .native(let k) = other.entry.kind, k == trigger {
                out.append(KeyClash(row: other, remap: nil, title: other.entry.title, section: other.entry.section.title))
            }
        }
        for r in others where r.enabled && r.trigger == trigger && r.id != row.remap?.id {
            out.append(KeyClash(row: nil, remap: r, title: remapTitle(r), section: nil))
        }
        return out
    }

    /// Libère la touche : tes raccourcis qui l'utilisaient la perdent (un raccourci d'origine revient à sa seule
    /// touche de FL). Renvoie l'entrée à qui proposer tout de suite une nouvelle touche.
    @discardableResult
    func release(_ clashes: [KeyClash]) -> String? {
        for c in clashes {
            guard let r = c.remap else { continue }          // touche d'origine de FL : rien à retirer
            if let row = c.row {
                if let remap = row.remap { delete(remap.id) }
            } else {
                var off = r
                off.trigger = nil
                upsert(off)
            }
        }
        return clashes.first(where: { $0.row != nil })?.row?.id
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

    /// Change la touche d'une entrée. `nil` = aucune touche (actions en plus seulement).
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
