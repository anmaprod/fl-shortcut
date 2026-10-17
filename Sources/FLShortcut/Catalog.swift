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
        case .general: return "Général"
        case .transport: return "Lecture et enregistrement"
        case .patterns: return "Patterns"
        case .playlist: return "Playlist"
        case .pianoRoll: return "Piano Roll"
        case .channelRack: return "Channel Rack"
        case .mixer: return "Mixer"
        case .browser: return "Browser"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return "Fichier, fenêtres, annuler — partout dans FL"
        case .transport: return "Lecture, REC, métronome, décompte"
        case .patterns: return "Choisir, créer et renommer les patterns"
        case .playlist: return "Outils, sélection, zoom, marqueurs"
        case .pianoRoll: return "Outils, notes, quantize, instruments"
        case .channelRack: return "Canaux, mute, solo, pas"
        case .mixer: return "Pistes, solo, liens, rendu"
        case .browser: return "Parcourir et charger des sons"
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
                                        detail: "Raccourci d'origine de FL Studio", kind: .native(combo),
                                        defaultTrigger: combo))
            }
            switch section {
        case .general:
            n("cmd-z", "Annuler / rétablir la dernière modification", ch("z", 6, cmd: true))
            n("cmd-opt-z", "Annuler pas à pas", ch("z", 6, cmd: true, opt: true))
            n("cmd-s", "Enregistrer le projet", ch("s", 1, cmd: true))
            n("cmd-shift-s", "Enregistrer sous", ch("s", 1, cmd: true, shift: true))
            n("cmd-n", "Enregistrer une nouvelle version", ch("n", 45, cmd: true))
            n("cmd-o", "Ouvrir un projet", ch("o", 31, cmd: true))
            n("cmd-r", "Exporter en WAV", ch("r", 15, cmd: true))
            n("cmd-shift-r", "Exporter en MP3", ch("r", 15, cmd: true, shift: true))
            n("cmd-shift-m", "Exporter en MIDI", ch("m", 46, cmd: true, shift: true))
            n("cmd-shift-h", "Réorganiser les fenêtres", ch("h", 4, cmd: true, shift: true))
            n("f5", "Afficher / masquer la Playlist", kc(96))
            n("f6", "Afficher / masquer le Channel Rack", kc(97))
            n("f7", "Afficher / masquer le Piano Roll", kc(98))
            n("f8", "Ouvrir le Plugin Picker", kc(100))
            n("f9", "Afficher / masquer le Mixer", kc(101))
            n("opt-f8", "Afficher / masquer le Browser", kc(100, opt: true))
            n("f10", "Réglages MIDI", kc(109))
            n("f11", "Infos du morceau", kc(103))
            n("f12", "Fermer toutes les fenêtres", kc(111))
            n("f1", "Aide", kc(122))
            n("f3", "Choisir un outil de la fenêtre active", kc(99))
            n("tab", "Passer d'une fenêtre à l'autre", kc(48))
            n("esc", "Fermer la fenêtre", kc(53))
            n("return", "Agrandir / réduire la Playlist", kc(36))
            n("opt-0", "Ouvrir le projet récent 0", kc(29, opt: true))
            n("opt-1", "Ouvrir le projet récent 1", kc(18, opt: true))
            n("opt-2", "Ouvrir le projet récent 2", kc(19, opt: true))
            n("opt-3", "Ouvrir le projet récent 3", kc(20, opt: true))
            n("opt-4", "Ouvrir le projet récent 4", kc(21, opt: true))
            n("opt-5", "Ouvrir le projet récent 5", kc(23, opt: true))
            n("opt-6", "Ouvrir le projet récent 6", kc(22, opt: true))
            n("opt-7", "Ouvrir le projet récent 7", kc(26, opt: true))
            n("opt-8", "Ouvrir le projet récent 8", kc(28, opt: true))
            n("opt-9", "Ouvrir le projet récent 9", kc(25, opt: true))
        case .transport:
            n("space", "Lecture / Stop", kc(49))
            n("cmd-space", "Lecture / Pause", kc(49, cmd: true))
            n("r", "Activer / couper l'enregistrement", ch("r", 15))
            n("l", "Bascule Pattern / Song", ch("l", 37))
            n("cmd-m", "Métronome", ch("m", 46, cmd: true))
            n("cmd-p", "Décompte avant l'enregistrement", ch("p", 35, cmd: true))
            n("cmd-i", "Attendre une note pour lancer l'enregistrement", ch("i", 34, cmd: true))
            n("cmd-b", "Mélanger les notes enregistrées (blend)", ch("b", 11, cmd: true))
            n("cmd-e", "Mode Step Edit", ch("e", 14, cmd: true))
            n("cmd-h", "Couper tous les sons (panique)", ch("h", 4, cmd: true))
            n("cmd-t", "Clavier d'ordinateur → clavier-piano", ch("t", 17, cmd: true))
            n("bksp", "Magnétisme : Ligne / Aucun", kc(51))
            n("np0", "Avance rapide", kc(82))
            n("npmul", "Mesure suivante (mode Song)", kc(67))
            n("npdiv", "Mesure précédente (mode Song)", kc(75))
            n("opt-np2", "Clavier-piano : octave 2", kc(84, opt: true))
            n("opt-np3", "Clavier-piano : octave 3", kc(85, opt: true))
            n("opt-np4", "Clavier-piano : octave 4", kc(86, opt: true))
            n("opt-np5", "Clavier-piano : octave 5", kc(87, opt: true))
            n("opt-np6", "Clavier-piano : octave 6", kc(88, opt: true))
        case .patterns:
            n("np1", "Choisir le pattern 1", kc(83))
            n("np2", "Choisir le pattern 2", kc(84))
            n("np3", "Choisir le pattern 3", kc(85))
            n("np4", "Choisir le pattern 4", kc(86))
            n("np5", "Choisir le pattern 5", kc(87))
            n("np6", "Choisir le pattern 6", kc(88))
            n("np7", "Choisir le pattern 7", kc(89))
            n("np8", "Choisir le pattern 8", kc(91))
            n("np9", "Choisir le pattern 9", kc(92))
            n("npplus", "Pattern suivant", kc(69))
            n("npminus", "Pattern précédent", kc(78))
            n("cmd-f4", "Pattern vide suivant", kc(118, cmd: true))
            n("f4", "Pattern vide suivant, avec son nom", kc(118))
            n("f2", "Renommer le pattern (et changer sa couleur)", kc(120))
        case .playlist:
            n("p", "Outil crayon", ch("p", 35))
            n("b", "Outil pinceau", ch("b", 11))
            n("d", "Outil suppression", ch("d", 2))
            n("t", "Outil mute", ch("t", 17))
            n("s", "Outil slip", ch("s", 1))
            n("c", "Outil découpe", ch("c", 8))
            n("e", "Outil sélection", ch("e", 14))
            n("y", "Outil lecture", ch("y", 16))
            n("z", "Outil zoom", ch("z", 6))
            n("5", "Zoomer sur la sélection", kc(23))
            n("6", "Zoomer sur les Performance Clips", kc(22))
            n("7", "Transposer vers le bas", kc(26))
            n("8", "Transposer vers le haut", kc(28))
            n("9", "Inverser (clips audio)", kc(25))
            n("bksp", "Magnétisme global", kc(51))
            n("del", "Supprimer la source du clip / pattern", kc(117))
            n("home", "Tête de lecture au début", kc(115))
            n("opt-m", "Mettre la sélection en mute", ch("m", 46, opt: true))
            n("opt-shift-m", "Enlever le mute de la sélection", ch("m", 46, opt: true, shift: true))
            n("opt-g", "Dégrouper la sélection", ch("g", 5, opt: true))
            n("opt-p", "Ouvrir le Picker Panel", ch("p", 35, opt: true))
            n("opt-t", "Ajouter un marqueur", ch("t", 17, opt: true))
            n("opt-npmul", "Marqueur suivant", kc(67, opt: true))
            n("opt-npdiv", "Marqueur précédent", kc(75, opt: true))
            n("cmd-a", "Tout sélectionner", ch("a", 0, cmd: true))
            n("cmd-opt-c", "Consolider les clips (depuis le premier)", ch("c", 8, cmd: true, opt: true))
            n("cmd-opt-shift-c", "Consolider les clips (depuis le début)", ch("c", 8, cmd: true, opt: true, shift: true))
            n("cmd-opt-g", "Couleur de la grille", ch("g", 5, cmd: true, opt: true))
            n("cmd-opt-home", "Redimensionner par la gauche", kc(115, cmd: true, opt: true))
            n("cmd-b", "Dupliquer la sélection à droite", ch("b", 11, cmd: true))
            n("cmd-c", "Copier", ch("c", 8, cmd: true))
            n("cmd-d", "Désélectionner", ch("d", 2, cmd: true))
            n("cmd-f8", "Ouvrir le Project Picker", kc(100, cmd: true))
            n("cmd-left", "Sélectionner le temps avant", kc(123, cmd: true))
            n("cmd-right", "Sélectionner le temps après", kc(124, cmd: true))
            n("cmd-p", "Mode Performance", ch("p", 35, cmd: true))
            n("cmd-t", "Ajouter un marqueur de temps", ch("t", 17, cmd: true))
            n("cmd-v", "Coller", ch("v", 9, cmd: true))
            n("cmd-x", "Couper", ch("x", 7, cmd: true))
            n("cmd-return", "Sélectionner le temps autour de la sélection", kc(36, cmd: true))
            n("pgup", "Zoom avant", kc(116))
            n("pgdn", "Zoom arrière", kc(121))
            n("shift-0", "Centrer sur la tête de lecture", kc(29, shift: true))
            n("shift-1", "Zoom horizontal niveau 1", kc(18, shift: true))
            n("shift-2", "Zoom horizontal niveau 2", kc(19, shift: true))
            n("shift-3", "Zoom horizontal niveau 3", kc(20, shift: true))
            n("shift-4", "Tout afficher", kc(21, shift: true))
            n("shift-5", "Zoomer sur la sélection", kc(23, shift: true))
            n("shift-6", "Ajuster à la zone Performance", kc(22, shift: true))
            n("shift-opt-t", "Choisir une signature rythmique", ch("t", 17, opt: true, shift: true))
            n("shift-c", "Sélectionner les clips de même source", ch("c", 8, shift: true))
            n("shift-g", "Grouper les clips", ch("g", 5, shift: true))
            n("shift-i", "Inverser la sélection", ch("i", 34, shift: true))
            n("shift-left", "Déplacer la sélection à gauche", kc(123, shift: true))
            n("shift-right", "Déplacer la sélection à droite", kc(124, shift: true))
            n("shift-up", "Déplacer la sélection vers le haut", kc(126, shift: true))
            n("shift-down", "Déplacer la sélection vers le bas", kc(125, shift: true))
            n("shift-m", "Changer le mode de stretch", ch("m", 46, shift: true))
            n("shift-q", "Quantize rapide du début des clips", ch("q", 12, shift: true))
        case .pianoRoll:
            n("p", "Outil crayon", ch("p", 35))
            n("b", "Outil pinceau", ch("b", 11))
            n("d", "Outil suppression", ch("d", 2))
            n("t", "Outil mute", ch("t", 17))
            n("c", "Outil découpe", ch("c", 8))
            n("e", "Outil sélection", ch("e", 14))
            n("y", "Outil lecture", ch("y", 16))
            n("z", "Outil zoom", ch("z", 6))
            n("s", "Notes glissées (slide)", ch("s", 1))
            n("o", "Portamento", ch("o", 31))
            n("f", "Propriété suivante dans la zone d'événements", ch("f", 3))
            n("g", "Instrument au-dessus", ch("g", 5))
            n("h", "Instrument au-dessus avec des notes", ch("h", 4))
            n("j", "Instrument en dessous avec des notes", ch("j", 38))
            n("k", "Instrument en dessous", ch("k", 40))
            n("m", "Mode d'affichage du clavier", ch("m", 46))
            n("bksp", "Magnétisme global", kc(51))
            n("del", "Supprimer la sélection", kc(117))
            n("pgup", "Zoom avant", kc(116))
            n("pgdn", "Zoom arrière", kc(121))
            n("opt-a", "Arpégiateur", ch("a", 0, opt: true))
            n("opt-left", "Décaler à gauche", kc(123, opt: true))
            n("opt-right", "Décaler à droite", kc(124, opt: true))
            n("opt-up", "Décaler vers le haut", kc(126, opt: true))
            n("opt-down", "Décaler vers le bas", kc(125, opt: true))
            n("opt-b", "Aides de notes", ch("b", 11, opt: true))
            n("opt-c", "Couleur des notes", ch("c", 8, opt: true))
            n("opt-e", "Riff Machine", ch("e", 14, opt: true))
            n("opt-f", "Flam", ch("f", 3, opt: true))
            n("opt-g", "Dégrouper les notes", ch("g", 5, opt: true))
            n("opt-k", "Outil Limit", ch("k", 40, opt: true))
            n("opt-l", "Outil Articulate", ch("l", 37, opt: true))
            n("opt-m", "Mettre la sélection en mute", ch("m", 46, opt: true))
            n("opt-shift-m", "Enlever le mute de la sélection", ch("m", 46, opt: true, shift: true))
            n("opt-n", "Vue forme d'onde", ch("n", 45, opt: true))
            n("opt-o", "Outil LFO", ch("o", 31, opt: true))
            n("opt-q", "Quantize", ch("q", 12, opt: true))
            n("opt-r", "Outil Randomize", ch("r", 15, opt: true))
            n("opt-s", "Outil Strum", ch("s", 1, opt: true))
            n("opt-u", "Outil Chop", ch("u", 32, opt: true))
            n("opt-v", "Ghost channels", ch("v", 9, opt: true))
            n("opt-w", "Claw Machine", ch("w", 13, opt: true))
            n("opt-x", "Scale Levels", ch("x", 7, opt: true))
            n("opt-y", "Score Flipper", ch("y", 16, opt: true))
            n("cmd-a", "Tout sélectionner", ch("a", 0, cmd: true))
            n("cmd-opt-g", "Couleur de la grille", ch("g", 5, cmd: true, opt: true))
            n("cmd-opt-home", "Redimensionner par la gauche", kc(115, cmd: true, opt: true))
            n("cmd-b", "Dupliquer la sélection à droite", ch("b", 11, cmd: true))
            n("cmd-c", "Copier", ch("c", 8, cmd: true))
            n("cmd-d", "Désélectionner", ch("d", 2, cmd: true))
            n("cmd-g", "Coller les notes entre elles (glue)", ch("g", 5, cmd: true))
            n("cmd-i", "Insérer la valeur du contrôleur", ch("i", 34, cmd: true))
            n("cmd-l", "Legato rapide", ch("l", 37, cmd: true))
            n("cmd-left", "Sélectionner le temps avant", kc(123, cmd: true))
            n("cmd-right", "Sélectionner le temps après", kc(124, cmd: true))
            n("cmd-m", "Importer un fichier MIDI", ch("m", 46, cmd: true))
            n("cmd-opt-q", "Quantize rapide", ch("q", 12, cmd: true, opt: true))
            n("cmd-return", "Sélectionner le temps autour de la sélection", kc(36, cmd: true))
            n("cmd-u", "Chop rapide", ch("u", 32, cmd: true))
            n("cmd-up", "Transposer d'une octave vers le haut", kc(126, cmd: true))
            n("cmd-down", "Transposer d'une octave vers le bas", kc(125, cmd: true))
            n("cmd-v", "Coller", ch("v", 9, cmd: true))
            n("cmd-x", "Couper", ch("x", 7, cmd: true))
            n("shift-0", "Centrer sur la tête de lecture", kc(29, shift: true))
            n("shift-1", "Zoom horizontal niveau 1", kc(18, shift: true))
            n("shift-2", "Zoom horizontal niveau 2", kc(19, shift: true))
            n("shift-3", "Zoom horizontal niveau 3", kc(20, shift: true))
            n("shift-4", "Tout afficher", kc(21, shift: true))
            n("shift-5", "Zoomer sur la sélection", kc(23, shift: true))
            n("shift-opt-t", "Choisir une signature rythmique", ch("t", 17, opt: true, shift: true))
            n("shift-c", "Sélectionner par couleur", ch("c", 8, shift: true))
            n("shift-cmd-v", "Coller depuis le presse-papiers MIDI", ch("v", 9, cmd: true, shift: true))
            n("shift-d", "Effacer la longueur des notes", ch("d", 2, shift: true))
            n("shift-f", "Parcourir les propriétés de note", ch("f", 3, shift: true))
            n("shift-g", "Grouper la sélection", ch("g", 5, shift: true))
            n("shift-h", "Instrument suivant avec des notes", ch("h", 4, shift: true))
            n("shift-i", "Inverser la sélection", ch("i", 34, shift: true))
            n("shift-k", "Instrument suivant", ch("k", 40, shift: true))
            n("shift-left", "Déplacer la sélection à gauche", kc(123, shift: true))
            n("shift-right", "Déplacer la sélection à droite", kc(124, shift: true))
            n("shift-up", "Déplacer la sélection vers le haut", kc(126, shift: true))
            n("shift-down", "Déplacer la sélection vers le bas", kc(125, shift: true))
            n("shift-m", "Sélectionner des groupes de notes au hasard", ch("m", 46, shift: true))
            n("shift-n", "Désactiver l'accord choisi", ch("n", 45, shift: true))
            n("shift-r", "Sélection au hasard", ch("r", 15, shift: true))
        case .channelRack:
            n("1", "Mute du canal 1", kc(18))
            n("2", "Mute du canal 2", kc(19))
            n("3", "Mute du canal 3", kc(20))
            n("4", "Mute du canal 4", kc(21))
            n("5", "Mute du canal 5", kc(23))
            n("6", "Mute du canal 6", kc(22))
            n("7", "Mute du canal 7", kc(26))
            n("8", "Mute du canal 8", kc(28))
            n("9", "Mute du canal 9", kc(25))
            n("0", "Mute du canal 10", kc(29))
            n("cmd-1", "Solo du canal 1", kc(18, cmd: true))
            n("cmd-2", "Solo du canal 2", kc(19, cmd: true))
            n("cmd-3", "Solo du canal 3", kc(20, cmd: true))
            n("cmd-4", "Solo du canal 4", kc(21, cmd: true))
            n("cmd-5", "Solo du canal 5", kc(23, cmd: true))
            n("cmd-6", "Solo du canal 6", kc(22, cmd: true))
            n("cmd-7", "Solo du canal 7", kc(26, cmd: true))
            n("cmd-8", "Solo du canal 8", kc(28, cmd: true))
            n("cmd-9", "Solo du canal 9", kc(25, cmd: true))
            n("cmd-0", "Solo du canal 10", kc(29, cmd: true))
            n("down", "Canal en dessous", kc(125))
            n("up", "Canal au-dessus", kc(126))
            n("pgup", "Groupe de canaux suivant", kc(116))
            n("pgdn", "Groupe de canaux précédent", kc(121))
            n("opt-c", "Cloner les canaux", ch("c", 8, opt: true))
            n("opt-del", "Supprimer les canaux", kc(117, opt: true))
            n("opt-down", "Descendre les canaux", kc(125, opt: true))
            n("opt-up", "Monter les canaux", kc(126, opt: true))
            n("opt-g", "Grouper les canaux", ch("g", 5, opt: true))
            n("opt-m", "Afficher les sélecteurs de piste Mixer", ch("m", 46, opt: true))
            n("opt-u", "Dézipper les canaux", ch("u", 32, opt: true))
            n("opt-z", "Zipper les canaux", ch("z", 6, opt: true))
            n("cmd-opt-r", "Re-stretch de tous les clips audio", ch("r", 15, cmd: true, opt: true))
            n("cmd-c", "Copier les pas / la partition", ch("c", 8, cmd: true))
            n("cmd-l", "Envoyer vers des pistes Mixer libres", ch("l", 37, cmd: true))
            n("cmd-v", "Coller les pas / la partition", ch("v", 9, cmd: true))
            n("cmd-x", "Couper les pas / la partition", ch("x", 7, cmd: true))
            n("cmd-return", "Aller à la Playlist", kc(36, cmd: true))
            n("shift-cmd-left", "Décaler les pas à gauche", kc(123, cmd: true, shift: true))
            n("shift-cmd-right", "Décaler les pas à droite", kc(124, cmd: true, shift: true))
            n("shift-down", "Étendre la sélection vers le bas", kc(125, shift: true))
            n("shift-up", "Étendre la sélection vers le haut", kc(126, shift: true))
        case .mixer:
            n("s", "Solo de la piste", ch("s", 1))
            n("opt-l", "Sélectionner les canaux liés à la piste", ch("l", 37, opt: true))
            n("opt-left", "Déplacer la piste à gauche", kc(123, opt: true))
            n("opt-right", "Déplacer la piste à droite", kc(124, opt: true))
            n("opt-r", "Rendu des pistes armées en .wav", ch("r", 15, opt: true))
            n("opt-s", "Solo avec les pistes reliées", ch("s", 1, opt: true))
            n("opt-w", "Vue « Wave » des vumètres", ch("w", 13, opt: true))
            n("cmd-a", "Sélectionner toutes les pistes", ch("a", 0, cmd: true))
            n("cmd-l", "Lier les canaux à la piste", ch("l", 37, cmd: true))
            n("cmd-shift-s", "Enregistrer l'état de la piste", ch("s", 1, cmd: true, shift: true))
            n("ctrl-return", "Propriétés de la piste", kc(36, ctrl: true))
            n("f2", "Renommer la piste", kc(120))
            n("shift-cmd-l", "Lier les canaux à partir de cette piste", ch("l", 37, cmd: true, shift: true))
        case .browser:
            n("return", "Remplacer le canal par l'élément choisi", kc(36))
            n("shift-up", "Élément précédent, avec préécoute", kc(126, shift: true))
            n("shift-down", "Élément suivant, avec préécoute", kc(125, shift: true))
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
        return isFLKey ? "« \(title) »\(place), touche d'origine de FL" : "« \(title) »\(place), ton raccourci"
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
                    rows[i].takenBy = titles[other] ?? "un raccourci personnalisé"
                    break
                }
            }
        }
        return (rows, othersList)
    }

    /// Nom lisible d'un raccourci hors catalogue.
    func remapTitle(_ r: Remap) -> String {
        if r.kind == .keystroke { return "Envoie " + (r.target?.display ?? "une touche") }
        if r.kind == .macro {
            if let ref = r.macroRef {
                return "Macro : " + (library.doc(ref)?.name.displaySafe() ?? "introuvable (supprimée ?)")
            }
            return "Macro : " + (r.macro?.name.displaySafe() ?? "à configurer")
        }
        return FLActions.all.first { $0.id == r.actionID }?.label ?? "Raccourci personnalisé"
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
