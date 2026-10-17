// Registre des blocs : l'endroit unique d'où l'interface, l'exécution, la validation, le journal et la documentation
// tirent leurs informations. `BlockRegistry.spec` est un switch exhaustif (pas un dictionnaire) : un BlockType ajouté
// sans fiche est une erreur de compilation. Textes en français ; identifiants JSON stables en ASCII (contrat).
import Foundation

enum BlockType: String, CaseIterable, Codable {
    case key, menuLetters, menuKey, click, delay, waitWindow, waitWindowClose
    case trackMenu, chooseFile, dropFile, flAction, flActionValue, selectInput, feedbackCheck
    /// Nom et couleur de la piste ou du canal sélectionné (lien avec FL, PROTOCOL.md §7).
    case nameColor
    /// La carte son branchée devient la sortie et l'entrée du Mac.
    case soundCard
    /// Ouvre l'Organiser sur la page de FL devant (Channel rack ou Mixer) ; la suite se passe dans sa fenêtre.
    case organize
    /// Met devant une page de FL, seulement si elle n'y est pas déjà (MacroPages.swift).
    case openPage
    /// « Cliquer sur… » : une option de la page ouverte au-dessus.
    case pageOption
    /// Élément d'un menu de FL dans la barre des menus de macOS, par ses titres (créé par « Enregistrer des clics »).
    case menuBar
    /// Ancienne étape `menu` : seulement pour reprendre les anciennes macros (absente de la palette).
    case menuAX
    case ifElse = "if", repeatCount = "repeat", repeatWhile = "while", waitUntil, setVariable, stop, comment
}

enum BlockCategory: String, CaseIterable {
    case clavier = "Clavier"
    case souris = "Souris"
    case fenetres = "Fenêtres et attentes"
    case fl = "FL Studio"
    case controle = "Contrôle"
}

/// Ce dont un bloc a besoin, agrégé par MacroProgram (et, à l'incrément 2, par Store.recompute pour la mémoire de
/// la piste et les ports MIDI à la demande).
struct BlockNeeds: OptionSet, Hashable {
    let rawValue: Int

    static let flAuPremierPlan = BlockNeeds(rawValue: 1 << 0)
    /// Le clavier doit être au repos avant le premier événement : attendu avant le premier bloc…
    static let clavierAuRepos = BlockNeeds(rawValue: 1 << 1)
    /// … sauf si ce bloc l'attend lui-même, juste avant son premier clic (menu de la piste).
    static let attenteClavierInterne = BlockNeeds(rawValue: 1 << 2)
    /// Vise la dernière piste cliquée dans FL (TrackMemory).
    static let pisteVisee = BlockNeeds(rawValue: 1 << 3)
    /// En tête de macro : refus d'emblée si la piste visée est hors de FL (« clique d'abord sur ta piste »).
    static let pisteRequise = BlockNeeds(rawValue: 1 << 4)
    /// Passe par le lien avec FL (réveil bref) ; un repli clavier peut exister.
    static let lienMIDI = BlockNeeds(rawValue: 1 << 5)
    /// Demande l'extension du lien (paramètres, requêtes : incrément 4).
    static let extensionsMIDI = BlockNeeds(rawValue: 1 << 6)
    /// Vérification du larsen lancée dès le début de la macro (Core Audio peut être lent).
    static let larsenEnAvance = BlockNeeds(rawValue: 1 << 7)
    /// Clics envoyés par le flux du système (pointeur déplacé puis remis).
    static let cliqueHID = BlockNeeds(rawValue: 1 << 8)
}

struct ParamSpec {
    let id: String
    let label: String
    let kind: ParamKind
    let aide: String?

    init(_ id: String, _ label: String, _ kind: ParamKind, aide: String? = nil) {
        self.id = id
        self.label = label
        self.kind = kind
        self.aide = aide
    }
}

enum ParamKind {
    case touche, ms(ClosedRange<Int>), nombre(ClosedRange<Int>), lettres(max: Int), toucheMenu
    case cible, fenetre, fichier(extensions: [String]), actionFL, condition, variable, texte(max: Int), blocs
    case couleur, icone
}

enum Conteneur { case aucun, corps, siSinon }

enum PolitiqueImport: Equatable {
    case ok
    case aRelire(String)
    case retirerPositions
}

struct Plateformes: OptionSet {
    let rawValue: Int
    static let mac = Plateformes(rawValue: 1)
    static let windows = Plateformes(rawValue: 2)
}

/// Contexte de validation d'un bloc : liste noire de la disposition active, chemin du bloc (« 3.2 ») et variables.
struct ValidationContext {
    var forbidden: ForbiddenTargets
    /// Fichiers : sous le dossier personnel et en .fst (macros de la bibliothèque, imports). Le modèle et les
    /// anciennes macros gardent les règles d'avant (un preset peut être sur un autre disque).
    var strictFiles = false
    /// Copie personnalisée du modèle « Enregistrement rapide » : comme le modèle en ligne, le preset peut être hors
    /// du dossier personnel (disque externe) ; .fst toujours exigé.
    var presetAnywhere = false
    var variables: Set<String> = []
    var path = "1"

    init(forbidden: ForbiddenTargets, strictFiles: Bool = false, variables: Set<String> = []) {
        self.forbidden = forbidden
        self.strictFiles = strictFiles
        self.variables = variables
    }

    /// Message d'erreur au format historique : « Étape 3 : touche interdite (…). »
    func fail(_ text: String) -> String { "Étape \(path) : \(text)" }
}

struct BlockSpec {
    let type: BlockType
    let label: String                    // « Touche », « Lettres d'un menu de FL », « Si… sinon »
    let category: BlockCategory
    let symbol: String                   // SF Symbol de la palette
    let aide: String                     // phrase de la palette ET de MACROS.md
    let params: [ParamSpec]              // l'inspecteur est construit à partir de ce schéma
    let conteneur: Conteneur
    let dansLaPalette: Bool
    let needs: (BlockBody) -> BlockNeeds
    let parDefaut: () -> BlockBody
    let resume: (BlockBody, KeyboardLayout) -> String   // ligne de la liste : « ⌘S × 2 »
    let journal: (BlockBody) -> String                  // JAMAIS une touche, un chemin ou un nom de piste
    let estimationMs: (BlockBody) -> Int
    let valider: (BlockBody, ValidationContext) -> String?
    let import_: PolitiqueImport
    let plateformes: Plateformes
}

enum BlockRegistry {
    /// Switch exhaustif : un BlockType ajouté sans fiche = erreur de compilation.
    static func spec(_ t: BlockType) -> BlockSpec {
        switch t {
        case .key: return Specs.key
        case .menuLetters: return Specs.menuLetters
        case .menuKey: return Specs.menuKey
        case .click: return Specs.click
        case .delay: return Specs.delay
        case .waitWindow: return Specs.waitWindow
        case .waitWindowClose: return Specs.waitWindowClose
        case .trackMenu: return Specs.trackMenu
        case .chooseFile: return Specs.chooseFile
        case .dropFile: return Specs.dropFile
        case .flAction: return Specs.flAction
        case .flActionValue: return Specs.flActionValue
        case .selectInput: return Specs.selectInput
        case .feedbackCheck: return Specs.feedbackCheck
        case .nameColor: return Specs.nameColor
        case .soundCard: return Specs.soundCard
        case .organize: return Specs.organize
        case .openPage: return Specs.openPage
        case .pageOption: return Specs.pageOption
        case .menuBar: return Specs.menuBar
        case .menuAX: return Specs.menuAX
        case .ifElse: return Specs.ifElse
        case .repeatCount: return Specs.repeatCount
        case .repeatWhile: return Specs.repeatWhile
        case .waitUntil: return Specs.waitUntil
        case .setVariable: return Specs.setVariable
        case .stop: return Specs.stop
        case .comment: return Specs.comment
        }
    }

    /// Palette de l'éditeur (incrément 2), par catégorie, sans les blocs cachés.
    static var palette: [(BlockCategory, [BlockSpec])] {
        BlockCategory.allCases.map { cat in
            (cat, BlockType.allCases.map(spec).filter { $0.category == cat && $0.dansLaPalette })
        }
    }

    static func needs(of body: BlockBody) -> BlockNeeds { body.type.map { spec($0).needs(body) } ?? [] }

    /// Nom du bloc dans le journal : nom de l'ancienne étape quand il y en a une (« waitDialog », « armTrack »…),
    /// pour que le journal reste comparable d'une version à l'autre.
    static func journal(of body: BlockBody) -> String { body.type.map { spec($0).journal(body) } ?? "unknown" }

    static func label(of body: BlockBody) -> String { body.type.map { spec($0).label } ?? "Bloc inconnu" }

    static func estimateMs(_ body: BlockBody) -> Int { body.type.map { spec($0).estimationMs(body) } ?? 0 }
}

// MARK: - Fiches

private enum Specs {
    static let base: BlockNeeds = [.flAuPremierPlan, .clavierAuRepos]

    static func seconds(_ ms: Int) -> String {
        ms % 1000 == 0 ? "\(ms / 1000) s" : String(format: "%.1f s", Double(ms) / 1000).replacingOccurrences(of: ".", with: ",")
    }

    static func times(_ n: Int) -> String { n > 1 ? " × \(n)" : "" }

    static func windowName(_ k: WindowKind) -> String { k == .dialog ? "Boîte de dialogue" : "Menu" }

    static func describe(_ c: Condition) -> String {
        switch c {
        case .windowOpen(let k): return k == .dialog ? "une boîte de dialogue est ouverte" : "un menu de FL est ouvert"
        case .flState(let q, let op, let v): return "FL : \(q) \(op.symbol) \(v)"
        case .variable(let name, let op, let v): return "\(name.displaySafe(max: 16)) \(op.symbol) \(v)"
        case .lastBlockFailed: return "le bloc précédent a échoué"
        case .not(let inner): return "non (\(describe(inner)))"
        case .all(let list): return list.map { describe($0) }.joined(separator: " et ")
        case .any(let list): return list.map { describe($0) }.joined(separator: " ou ")
        }
    }

    static func describe(_ v: IntSource) -> String {
        switch v {
        case .constant(let n): return "\(n)"
        case .variable(let name): return name.displaySafe(max: 16)
        case .flState(let q): return "FL : \(q)"
        }
    }

    static func describe(_ t: ClickTarget) -> String {
        switch t {
        case .flWindow: return "fenêtre de FL"
        case .openMenu: return "menu ouvert"
        case .button: return "bouton retrouvé à son image"
        case .named: return "bouton retrouvé à son nom"
        case .track: return "piste visée"
        case .lastClick: return "après le clic précédent"
        case .startCursor: return "curseur au départ"
        case .cursorXWindowY: return "colonne du curseur"
        case .toLearn: return "à montrer dans FL"
        }
    }

    /// Lettres a à z seulement (lettres soulignées des menus de FL).
    static func lettersOK(_ letters: [Character]) -> Bool {
        letters.allSatisfy { ("a"..."z").contains($0) }
    }

    static func keyProblem(_ combo: KeyCombo, _ ctx: ValidationContext, what: String = "touche") -> String? {
        guard combo.isValidKey else { return ctx.fail("\(what) non prise en charge.") }
        if let why = ctx.forbidden.reason(for: combo) { return ctx.fail("\(what) interdite (\(why)).") }
        return nil
    }

    static func enterProblem(_ e: EnterPolicy, _ ctx: ValidationContext) -> String? {
        if case .learned(let key) = e, !MacroValidation.learnedEnterKeys.contains(key) {
            return ctx.fail("mémoire de l'Entrée inconnue.")
        }
        return nil
    }

    static func conditionNeeds(_ c: Condition) -> BlockNeeds {
        switch c {
        case .flState: return [.lienMIDI, .extensionsMIDI]
        case .not(let inner): return conditionNeeds(inner)
        case .all(let list), .any(let list): return list.reduce([]) { $0.union(conditionNeeds($1)) }
        case .windowOpen, .variable, .lastBlockFailed: return []
        }
    }

    static func sourceNeeds(_ v: IntSource) -> BlockNeeds {
        if case .flState = v { return [.lienMIDI, .extensionsMIDI] }
        return []
    }

    // MARK: Clavier

    static let key = BlockSpec(
        type: .key, label: "Touche ou raccourci", category: .clavier, symbol: "keyboard",
        aide: "Envoie une touche ou un raccourci clavier à FL (⌘A, ⇧⌘S, F9…), seulement quand FL est au premier plan. Clique le champ puis tape le raccourci, ou coche ⌘ ⌥ ⌃ ⇧. Les raccourcis dangereux (⌘Q, ⌘W…) sont refusés.",
        params: [ParamSpec("key", "Touche", .touche), ParamSpec("times", "Nombre de fois", .nombre(1...20))],
        conteneur: .aucun, dansLaPalette: true,
        needs: { _ in base },
        parDefaut: { .key(KeyRef(KeyCombo(keyCode: 49), char: " "), times: 1) },
        resume: { body, layout in
            guard case .key(let k, let n) = body else { return "" }
            return k.combo.displayName(layout: layout) + times(n)
        },
        journal: { _ in "key" },
        estimationMs: { body in
            guard case .key(_, let n) = body else { return 0 }
            return 50 * max(n, 1)
        },
        valider: { body, ctx in
            guard case .key(let k, let n) = body else { return nil }
            guard (1...20).contains(n) else { return ctx.fail("nombre de fois hors limites.") }
            return keyProblem(k.combo, ctx)
        },
        import_: .aRelire("touche envoyée à FL"), plateformes: .mac)

    static let menuLetters = BlockSpec(
        type: .menuLetters, label: "Lettres d'un menu de FL", category: .clavier, symbol: "character.cursor.ibeam",
        aide: "Tape les lettres soulignées d'un menu de FL déjà ouvert (F de File, O de Open…), seulement si un menu ouvert par la macro est encore là.",
        params: [ParamSpec("letters", "Lettres", .lettres(max: 8)), ParamSpec("finalEnter", "Entrée à la fin", .toucheMenu)],
        conteneur: .aucun, dansLaPalette: true,
        needs: { _ in base },
        parDefaut: { .menuLetters(["f"], finalEnter: .never) },
        resume: { body, _ in
            guard case .menuLetters(let l, _) = body else { return "" }
            return l.map { String($0).uppercased() }.joined(separator: " › ")
        },
        journal: { _ in "menuLetters" },
        estimationMs: { body in
            guard case .menuLetters(let l, _) = body else { return 0 }
            return 600 * l.count + 800
        },
        valider: { body, ctx in
            guard case .menuLetters(let l, let e) = body else { return nil }
            guard (1...8).contains(l.count), lettersOK(l) else { return ctx.fail("lettres de menu invalides (a à z).") }
            return enterProblem(e, ctx)
        },
        import_: .ok, plateformes: .mac)

    static let menuKey = BlockSpec(
        type: .menuKey, label: "Touche de menu", category: .clavier, symbol: "arrow.up.arrow.down",
        aide: "Flèche, Entrée ou Échap dans un menu de FL ouvert par la macro (jamais ailleurs).",
        params: [ParamSpec("menuKey", "Touche", .toucheMenu), ParamSpec("times", "Nombre de fois", .nombre(1...20))],
        conteneur: .aucun, dansLaPalette: true,
        needs: { _ in base },
        parDefaut: { .menuKey(.down, times: 1) },
        resume: { body, _ in
            guard case .menuKey(let k, let n) = body else { return "" }
            return k.symbol + times(n)
        },
        journal: { _ in "menuKey" },
        estimationMs: { body in
            guard case .menuKey(_, let n) = body else { return 0 }
            return 50 * max(n, 1)
        },
        valider: { body, ctx in
            guard case .menuKey(_, let n) = body else { return nil }
            return (1...20).contains(n) ? nil : ctx.fail("nombre de fois hors limites.")
        },
        import_: .ok, plateformes: .mac)

    // MARK: Souris

    static let click = BlockSpec(
        type: .click, label: "Clic", category: .souris, symbol: "cursorarrow.click",
        aide: "Clic gauche ou droit à un endroit retrouvé à chaque fois (coin d'une fenêtre de FL, piste visée, menu ouvert, fenêtre d'un plugin comme Serum…). Toujours dans une fenêtre de FL ou de ses plugins, jamais sous une autre app.",
        params: [ParamSpec("target", "Où", .cible), ParamSpec("button", "Bouton", .nombre(0...1))],
        conteneur: .aucun, dansLaPalette: true,
        needs: { body in
            var n: BlockNeeds = base.union(.cliqueHID)
            if case .click(.track, _) = body { n.insert(.pisteVisee) }
            return n
        },
        parDefaut: { .click(.track(dx: 0, dy: 0), button: .left) },
        resume: { body, _ in
            guard case .click(let t, let b) = body else { return "" }
            return (b == .right ? "Clic droit · " : "Clic · ") + describe(t)
        },
        journal: { _ in "click" },
        estimationMs: { _ in 300 },
        valider: { body, ctx in
            guard case .click(let t, let b) = body else { return nil }
            if case .toLearn = t { return ctx.fail("position à montrer dans FL (« Montrer dans FL… » dans le créateur).") }
            guard t.isFinite else { return ctx.fail("position invalide.") }
            if case .openMenu = t, b == .right { return ctx.fail("clic droit impossible dans un menu ouvert.") }
            return nil
        },
        import_: .retirerPositions, plateformes: .mac)

    // MARK: Fenêtres et attentes

    static let delay = BlockSpec(
        type: .delay, label: "Attendre un temps fixe", category: .fenetres, symbol: "hourglass",
        aide: "Attend un moment (5 s au plus). Échap l'interrompt. À éviter : mieux vaut attendre qu'une fenêtre s'ouvre ou se ferme.",
        params: [ParamSpec("wait", "Attendre", .fenetre), ParamSpec("ms", "Durée (ms)", .ms(0...MacroValidation.maxDelayMs))],
        conteneur: .aucun, dansLaPalette: true,
        needs: { _ in base },
        parDefaut: { .delay(ms: 200) },
        resume: { body, _ in
            guard case .delay(let ms) = body else { return "" }
            return ms < 1000 ? "\(ms) ms" : seconds(ms)
        },
        journal: { _ in "delay" },
        estimationMs: { body in
            guard case .delay(let ms) = body else { return 0 }
            return max(ms, 0)
        },
        valider: { body, ctx in
            guard case .delay(let ms) = body else { return nil }
            return (0...MacroValidation.maxDelayMs).contains(ms) ? nil : ctx.fail("pause hors limites.")
        },
        import_: .ok, plateformes: .mac)

    static func waitValidator(_ body: BlockBody, _ ctx: ValidationContext) -> String? {
        switch body {
        case .waitWindow(_, let ms), .waitWindowClose(_, let ms):
            return (100...MacroValidation.maxWaitMs).contains(ms) ? nil : ctx.fail("attente hors limites.")
        default:
            return nil
        }
    }

    static let waitWindow = BlockSpec(
        type: .waitWindow, label: "Attendre une fenêtre", category: .fenetres, symbol: "macwindow.badge.plus",
        aide: "Attend qu'une boîte de dialogue ou un menu de FL s'ouvre (120 s au plus).",
        params: [ParamSpec("wait", "Attendre", .fenetre), ParamSpec("timeoutMs", "Au plus (ms)", .ms(100...MacroValidation.maxWaitMs))],
        conteneur: .aucun, dansLaPalette: true,
        needs: { _ in base },
        parDefaut: { .waitWindow(.dialog, timeoutMs: 4_000) },
        resume: { body, _ in
            guard case .waitWindow(let k, let ms) = body else { return "" }
            return "\(windowName(k)) · \(seconds(ms)) au plus"
        },
        journal: { body in
            guard case .waitWindow(let k, _) = body else { return "waitWindow" }
            return k == .dialog ? "waitDialog" : "waitMenu"
        },
        estimationMs: { body in
            guard case .waitWindow(_, let ms) = body else { return 0 }
            return max(ms, 0)
        },
        valider: waitValidator,
        import_: .ok, plateformes: .mac)

    static let waitWindowClose = BlockSpec(
        type: .waitWindowClose, label: "Attendre la fermeture", category: .fenetres, symbol: "macwindow",
        aide: "Attend que la boîte ou le menu se ferme (par exemple pendant que tu choisis ton preset, 120 s au plus).",
        params: [ParamSpec("wait", "Attendre", .fenetre), ParamSpec("timeoutMs", "Au plus (ms)", .ms(100...MacroValidation.maxWaitMs))],
        conteneur: .aucun, dansLaPalette: true,
        needs: { _ in base },
        parDefaut: { .waitWindowClose(.dialog, timeoutMs: 8_000) },
        resume: { body, _ in
            guard case .waitWindowClose(let k, let ms) = body else { return "" }
            return "\(windowName(k)) fermée · \(seconds(ms)) au plus"
        },
        journal: { body in
            guard case .waitWindowClose(let k, _) = body else { return "waitWindowClose" }
            return k == .dialog ? "waitDialogClose" : "waitMenuClose"
        },
        estimationMs: { body in
            guard case .waitWindowClose(_, let ms) = body else { return 0 }
            return max(ms, 0)
        },
        valider: waitValidator,
        import_: .ok, plateformes: .mac)

    // MARK: FL Studio

    static let trackMenu = BlockSpec(
        type: .trackMenu, label: "Menu de la piste", category: .fl, symbol: "list.bullet.rectangle",
        aide: "Clic droit sur la dernière piste cliquée dans le Mixer, puis l'élément choisi dans la liste (ouvrir un état de piste, renommer…), au clavier : rien à apprendre.",
        params: [ParamSpec("letters", "Élément", .lettres(max: 3)), ParamSpec("finalEnter", "Entrée à la fin", .toucheMenu)],
        conteneur: .aucun, dansLaPalette: true,
        needs: { body in
            var n: BlockNeeds = base.union([.attenteClavierInterne, .cliqueHID])
            if case .trackMenu(_, _, .lastClicked, _) = body { n.formUnion([.pisteVisee, .pisteRequise]) }
            return n
        },
        parDefaut: { MacroTemplates.openStateMenu },
        resume: { body, _ in
            guard case .trackMenu(let l, let labels, _, _) = body else { return "" }
            return labels.isEmpty ? l.map { String($0).uppercased() }.joined(separator: " › ")
                                  : labels.map { $0.displaySafe(max: 40) }.joined(separator: " › ")
        },
        journal: { _ in "trackMenu" },
        estimationMs: { _ in 4_000 },
        valider: { body, ctx in
            guard case .trackMenu(let l, let labels, _, let e) = body else { return nil }
            // Lettres des sous-menus puis celle de l'élément (1 à 3, a à z) : « R » pour un élément du menu lui-même,
            // « F O » pour File › Open mixer track state.
            guard labels.count <= 3,
                  labels.allSatisfy({ !$0.isEmpty && $0.count <= 160 }) else { return ctx.fail("titres de menu invalides.") }
            guard (1...3).contains(l.count), lettersOK(l) else {
                return ctx.fail("choisis l'élément du menu de la piste (ou 1 à 3 lettres soulignées, a à z).")
            }
            if e == .never { return ctx.fail("le menu de la piste doit se fermer sur son dernier élément.") }
            return enterProblem(e, ctx)
        },
        import_: .ok, plateformes: .mac)

    static let chooseFile = BlockSpec(
        type: .chooseFile, label: "Ouvrir un preset (boîte Open)", category: .fl, symbol: "doc.badge.arrow.up",
        aide: "Quand FL a ouvert sa boîte « Open » (preset d'un plugin, d'un canal…) : va au fichier .fst choisi et l'ouvre. À placer après les clics qui ouvrent la boîte et un « Attendre ».",
        params: [ParamSpec("path", "Fichier", .fichier(extensions: ["fst"]))],
        conteneur: .aucun, dansLaPalette: true,
        needs: { _ in base },
        parDefaut: { .chooseFile(path: NSHomeDirectory() + "/Documents/Image-Line/FL Studio/Presets/Mixer presets/Preset.fst") },
        resume: { body, _ in
            guard case .chooseFile(let path) = body else { return "" }
            return URL(fileURLWithPath: path).lastPathComponent.displaySafe(max: 40)
        },
        journal: { _ in "chooseFile" },
        estimationMs: { _ in 3_000 },
        valider: { body, ctx in
            guard case .chooseFile(let p) = body else { return nil }
            return presetFileProblem(p, ctx)
        },
        import_: .aRelire("fichier à rechoisir sur cette machine"), plateformes: .mac)

    static let dropFile = BlockSpec(
        type: .dropFile, label: "Déposer un preset sur la piste", category: .fl, symbol: "square.and.arrow.down.on.square",
        aide: "Glisse le fichier sur la dernière piste cliquée dans le Mixer, comme depuis le Finder : FL y charge l'état de piste, sans menu ni boîte « Open ».",
        params: [ParamSpec("path", "Fichier", .fichier(extensions: ["fst"]))],
        conteneur: .aucun, dansLaPalette: true,
        needs: { _ in base.union([.cliqueHID, .pisteVisee, .pisteRequise]) },
        parDefaut: { .dropFile(path: NSHomeDirectory() + "/Documents/Image-Line/FL Studio/Presets/Mixer presets/Preset.fst") },
        resume: { body, _ in
            guard case .dropFile(let path) = body else { return "" }
            return URL(fileURLWithPath: path).lastPathComponent.displaySafe(max: 40)
        },
        journal: { _ in "dropFile" },
        estimationMs: { _ in 600 },
        valider: { body, ctx in
            guard case .dropFile(let p) = body else { return nil }
            return presetFileProblem(p, ctx)
        },
        import_: .aRelire("fichier à rechoisir sur cette machine"), plateformes: .mac)

    /// Chemin d'un preset (choisi dans la boîte « Open » ou déposé sur la piste) : mêmes règles pour les deux blocs.
    private static func presetFileProblem(_ p: String, _ ctx: ValidationContext) -> String? {
        guard !p.isEmpty, p.count <= 1024,
              !p.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            return ctx.fail("chemin de fichier invalide.")
        }
        if ctx.strictFiles {
            let home = NSHomeDirectory() + "/"
            let parts = p.split(separator: "/")
            let placeOK = ctx.presetAnywhere ? p.hasPrefix("/") : p.hasPrefix(home)
            guard placeOK, !parts.contains(".."), URL(fileURLWithPath: p).pathExtension.lowercased() == "fst" else {
                return ctx.fail(ctx.presetAnywhere ? "preset .fst attendu." : "preset .fst attendu dans ton dossier personnel.")
            }
        }
        return nil
    }

    static let flAction = BlockSpec(
        type: .flAction, label: "Action de FL", category: .fl, symbol: "bolt.horizontal",
        aide: "Lance une action de FL par le lien avec FL (réveil bref, puis il se rendort). Sans lien : son équivalent au clavier, s'il existe.",
        params: [ParamSpec("action", "Action", .actionFL), ParamSpec("fallback", "Sans lien", .touche)],
        conteneur: .aucun, dansLaPalette: true,
        needs: { body in
            var n: BlockNeeds = base.union(.lienMIDI)
            if case .flAction(_, .trackMenuArm) = body { n.formUnion([.cliqueHID, .pisteVisee]) }
            return n
        },
        parDefaut: { .flAction(key: "armon", fallback: .trackMenuArm) },
        resume: { body, _ in
            guard case .flAction(let key, _) = body else { return "" }
            return FLActions.id(forKey: key).flatMap { FLActions.info($0)?.label } ?? key.displaySafe(max: 20)
        },
        journal: { body in
            guard case .flAction(let key, _) = body else { return "flAction" }
            switch key {
            case "armon": return "armTrack"
            case "recon": return "recordOn"
            default: return FLActions.id(forKey: key) != nil ? "flAction \(key)" : "flAction ?"
            }
        },
        estimationMs: { _ in 3_000 },
        valider: { body, ctx in
            guard case .flAction(let key, let fallback) = body else { return nil }
            guard FLActions.id(forKey: key) != nil else { return ctx.fail("action de FL inconnue.") }
            switch fallback {
            case .none: return nil
            case .trackMenuArm:
                return key == "armon" ? nil : ctx.fail("le menu de la piste ne sait qu'armer la piste.")
            case .key(let k):
                return keyProblem(k.combo, ctx, what: key == "recon" ? "touche REC" : "touche de secours")
            }
        },
        import_: .aRelire("passe par le lien avec FL"), plateformes: .mac)

    static let flActionValue = BlockSpec(
        type: .flActionValue, label: "Action de FL avec valeur", category: .fl, symbol: "slider.horizontal.3",
        aide: "Action de FL avec un nombre (piste N, pattern N…). Demande l'extension du lien avec FL.",
        params: [ParamSpec("action", "Action", .actionFL), ParamSpec("value", "Valeur", .variable)],
        conteneur: .aucun, dansLaPalette: false,
        needs: { body in
            guard case .flActionValue(_, let v) = body else { return base }
            return base.union([.lienMIDI, .extensionsMIDI]).union(sourceNeeds(v))
        },
        parDefaut: { .flActionValue(key: "trnext", value: .constant(1)) },
        resume: { body, _ in
            guard case .flActionValue(let key, let v) = body else { return "" }
            let name = FLActions.id(forKey: key).flatMap { FLActions.info($0)?.label } ?? key.displaySafe(max: 20)
            return "\(name) · \(describe(v))"
        },
        journal: { body in
            guard case .flActionValue(let key, _) = body, FLActions.id(forKey: key) != nil else { return "flActionValue ?" }
            return "flActionValue \(key)"
        },
        estimationMs: { _ in 3_000 },
        valider: { body, ctx in
            guard case .flActionValue(let key, let v) = body else { return nil }
            guard FLActions.id(forKey: key) != nil else { return ctx.fail("action de FL inconnue.") }
            return MacroValidation.sourceProblem(v, ctx)
        },
        import_: .aRelire("passe par le lien avec FL"), plateformes: .mac)

    static let selectInput = BlockSpec(
        type: .selectInput, label: "Choisir l'entrée 1", category: .fl, symbol: "mic",
        aide: "« (none) » → entrée 1 de la piste. Montré une seule fois (une bulle le demande), puis refait seul.",
        params: [],
        conteneur: .aucun, dansLaPalette: true,
        needs: { _ in base.union([.cliqueHID, .pisteVisee]) },
        parDefaut: { MacroTemplates.inputOne },
        resume: { _, _ in "« (none) » → entrée 1" },
        journal: { _ in "selectInput" },
        estimationMs: { _ in 3_000 },
        valider: { body, ctx in
            guard case .selectInput(.legacy(let key)) = body else { return nil }
            return MacroValidation.learnedPathKeys.contains(key) ? nil : ctx.fail("positions apprises inconnues.")
        },
        import_: .retirerPositions, plateformes: .mac)

    static let nameColor = BlockSpec(
        type: .nameColor, label: "Nom et couleur", category: .fl, symbol: "paintpalette",
        aide: "Donne un nom et/ou une couleur à la piste ou au canal sélectionné dans la page de FL qui est devant (Mixer, Channel rack ou Playlist), par le lien avec FL, et une icône de FL par sa fenêtre (F2). Un seul élément doit être sélectionné.",
        params: [ParamSpec("name", "Nom", .texte(max: NameColorPayload.maxNameScalars)),
                 ParamSpec("color", "Couleur", .couleur),
                 ParamSpec("icon", "Icône", .icone)],
        conteneur: .aucun, dansLaPalette: true,
        needs: { _ in base.union(.lienMIDI) },
        parDefaut: { .nameColor(name: nil, color: NameColorPayload.defaultColor) },
        resume: { body, _ in
            guard case .nameColor(let name, let color, let fade, let icon) = body else { return "" }
            return NameColorPayload.summary(name: name, color: color, fade: fade, icon: icon)
        },
        journal: { _ in "nameColor" },
        estimationMs: { body in
            // L'icône passe par deux fenêtres de FL (nom, grille).
            if case .nameColor(_, _, _, .some) = body { return 1_800 }
            return 300
        },
        valider: { body, ctx in
            guard case .nameColor(let name, let color, let fade, let icon) = body else { return nil }
            let payload = NameColorPayload(name: name, color: color)
            if fade != nil {
                // Comme « Gradient color… » de FL : une couleur de départ, et jamais de nom (plusieurs pistes).
                guard payload.color != nil else { return ctx.fail("un dégradé demande ses deux couleurs.") }
                guard payload.name == nil else { return ctx.fail("un dégradé ne change pas le nom : retire le nom.") }
                guard icon == nil else { return ctx.fail("un dégradé ne pose pas d'icône : retire l'icône.") }
            }
            guard payload.name != nil || payload.color != nil || icon != nil else {
                return ctx.fail("donne un nom ou une couleur.")
            }
            if let n = payload.name, let why = NameColorPayload.nameProblem(n) { return ctx.fail(why) }
            return nil
        },
        import_: .aRelire("renomme et colore dans FL"), plateformes: .mac)

    static let soundCard = BlockSpec(
        type: .soundCard, label: "Carte son branchée", category: .fl, symbol: "hifispeaker.and.homepod",
        aide: "La carte son branchée (USB, Thunderbolt…) devient la sortie et l'entrée du Mac ; FL la suit tout seul s'il est réglé une fois sur « Default audio device » (Output) et « Default input device » (Input) dans Options › Audio settings.",
        params: [],
        conteneur: .aucun, dansLaPalette: true,
        needs: { _ in [] },
        parDefaut: { .soundCard },
        resume: { _, _ in "sortie et entrée du Mac" },
        journal: { _ in "soundCard" },
        estimationMs: { _ in 200 },
        valider: { _, _ in nil },
        import_: .ok, plateformes: .mac)

    static let organize = BlockSpec(
        type: .organize, label: "Organiser la page ouverte", category: .fl, symbol: "square.stack.3d.up",
        aide: "Ouvre l'Organiser sur la page de FL qui est devant : il écoute chaque son du Channel rack (sans que tu l'entendes), le classe en Drums, Basse, Mélodies, Voix, FX ; tu vérifies l'aperçu, puis il colore (une couleur ou un dégradé par famille) et regroupe les sons. Sur le Mixer, il colore les pistes. « Revenir comme avant » défait tout.",
        params: [],
        conteneur: .aucun, dansLaPalette: true,
        needs: { _ in base.union(.lienMIDI) },
        parDefaut: { .organize },
        resume: { _, _ in "écoute, classe, colore" },
        journal: { _ in "organize" },
        estimationMs: { _ in 200 },
        valider: { _, _ in nil },
        import_: .ok, plateformes: .mac)

    static let feedbackCheck = BlockSpec(
        type: .feedbackCheck, label: "Vérifier le larsen", category: .fl, symbol: "speaker.wave.2",
        aide: "Micro et haut-parleurs de l'ordinateur sans casque : explique comment éviter le larsen. Vérifié dès le début de la macro, affiché à la fin.",
        params: [],
        conteneur: .aucun, dansLaPalette: true,
        needs: { _ in base.union(.larsenEnAvance) },
        parDefaut: { .feedbackCheck },
        resume: { _, _ in "Micro et sortie de l'ordinateur" },
        journal: { _ in "feedbackCheck" },
        estimationMs: { _ in 3_000 },
        valider: { _, _ in nil },
        import_: .ok, plateformes: .mac)

    static let openPage = BlockSpec(
        type: .openPage, label: "Ouvrir une page de FL", category: .fl, symbol: "macwindow",
        aide: "Met devant une page de FL (Playlist, Channel Rack, Mixer…), seulement si elle n'y est pas déjà. Les options de « Cliquer sur… » juste en dessous sont celles de cette page.",
        params: [ParamSpec("page", "Page", .fenetre)],
        conteneur: .aucun, dansLaPalette: true,
        needs: { _ in base.union(.lienMIDI) },
        parDefaut: { .openPage(.mixer) },
        resume: { body, _ in
            guard case .openPage(let page) = body else { return "" }
            return page?.title ?? "page à choisir"
        },
        journal: { body in
            guard case .openPage(let page) = body else { return "openPage" }
            return "openPage \(page?.rawValue ?? "?")"
        },
        estimationMs: { _ in 600 },
        valider: { body, ctx in
            guard case .openPage(let page) = body else { return nil }
            return page == nil ? ctx.fail("choisis la page de FL à ouvrir.") : nil
        },
        import_: .ok, plateformes: .mac)

    static let pageOption = BlockSpec(
        type: .pageOption, label: "Cliquer sur…", category: .fl, symbol: "cursorarrow.click.2",
        aide: "Une option de la page de FL ouverte juste au-dessus : ajouter un instrument ou un effet, armer la piste, solo, ou un raccourci de FL de cette page. Ajouté avec « Ouvrir une page de FL » au-dessus.",
        params: [ParamSpec("option", "Option", .actionFL), ParamSpec("name", "Plugin", .texte(max: PageOptions.maxName))],
        conteneur: .aucun, dansLaPalette: true,
        needs: { body in
            guard case .pageOption(let id?, _) = body, PageOptions.usesLink(id) else { return base }
            // Armer la piste sans le lien : par le menu de la piste visée (comme « Action de FL »).
            return id == "mixer.armon" ? base.union([.lienMIDI, .cliqueHID, .pisteVisee]) : base.union(.lienMIDI)
        },
        // Valide sous la page par défaut d'« Ouvrir une page de FL » (Mixer) ; la palette les donne à choisir.
        parDefaut: { .pageOption(id: "mixer.armon", name: "") },
        resume: { body, layout in
            guard case .pageOption(let id, let name) = body else { return "" }
            guard let id, let option = PageOptions.option(id, layout: layout) else { return "option à choisir" }
            return option.needsName && !name.isEmpty ? "\(option.label) : \(name.displaySafe(max: 30))" : option.label
        },
        journal: { body in
            guard case .pageOption(let id, _) = body else { return "pageOption" }
            return "pageOption \(id.flatMap { PageOptions.page(of: $0)?.rawValue } ?? "?")"
        },
        estimationMs: { _ in 800 },
        valider: { body, ctx in
            guard case .pageOption(let id, let name) = body else { return nil }
            guard let id else { return ctx.fail("choisis l'option à cliquer.") }
            guard PageOptions.isKnown(id) else { return ctx.fail("option de FL inconnue.") }
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            if PageOptions.needsName(id), trimmed.isEmpty || trimmed.count > PageOptions.maxName {
                return ctx.fail("écris le nom du plugin à ajouter (comme dans FL).")
            }
            return nil
        },
        import_: .ok, plateformes: .mac)

    static let menuBar = BlockSpec(
        type: .menuBar, label: "Menu de FL (barre des menus)", category: .fl, symbol: "menubar.rectangle",
        aide: "Choisit un élément des menus de FL dans la barre des menus de macOS (Options › Audio settings…) par son nom, grâce à l'Accessibilité : rien n'est cliqué à l'écran. Créé par « Enregistrer des clics ».",
        params: [],
        conteneur: .aucun, dansLaPalette: false,
        needs: { _ in base },
        parDefaut: { .menuBar(titles: ["Options", "Audio settings"]) },
        resume: { body, _ in
            guard case .menuBar(let titles) = body else { return "" }
            return titles.map { $0.displaySafe(max: 30) }.joined(separator: " › ")
        },
        journal: { _ in "menuBar" },
        estimationMs: { _ in 400 },
        valider: { body, ctx in
            guard case .menuBar(let titles) = body else { return nil }
            guard (2...MenuBarAX.maxDepth).contains(titles.count),
                  titles.allSatisfy({ !$0.trimmingCharacters(in: .whitespaces).isEmpty && $0.count <= 80 }) else {
                return ctx.fail("chemin de menu invalide.")
            }
            return nil
        },
        import_: .ok, plateformes: .mac)

    static let menuAX = BlockSpec(
        type: .menuAX, label: "Menu (ancien format)", category: .fl, symbol: "filemenu.and.selection",
        aide: "Choisit un élément de menu par son titre (Accessibilité), sinon par des clics de secours appris. Repris des anciennes macros, absent de la palette.",
        params: [ParamSpec("titles", "Titres", .texte(max: 80)), ParamSpec("fallback", "Clics de secours", .cible)],
        conteneur: .aucun, dansLaPalette: false,
        needs: { _ in base.union(.cliqueHID) },
        parDefaut: { .menuAX(titles: ["File"], fallback: []) },
        resume: { body, _ in
            guard case .menuAX(let titles, _) = body else { return "" }
            return titles.map { $0.displaySafe(max: 30) }.joined(separator: " › ")
        },
        journal: { _ in "menu" },
        estimationMs: { _ in 2_000 },
        valider: { body, ctx in
            guard case .menuAX(let titles, let fallback) = body else { return nil }
            guard (1...3).contains(titles.count), titles.allSatisfy({ !$0.isEmpty && $0.count <= 80 }) else {
                return ctx.fail("titres de menu invalides.")
            }
            guard fallback.count <= 3, fallback.allSatisfy(\.isFinite) else { return ctx.fail("positions de secours invalides.") }
            return nil
        },
        import_: .retirerPositions, plateformes: .mac)

    // MARK: Contrôle

    static let ifElse = BlockSpec(
        type: .ifElse, label: "Si… sinon", category: .controle, symbol: "arrow.triangle.branch",
        aide: "Fait les blocs « alors » si la condition est vraie, sinon les blocs « sinon ».",
        params: [ParamSpec("condition", "Condition", .condition), ParamSpec("then", "Alors", .blocs), ParamSpec("else", "Sinon", .blocs)],
        conteneur: .siSinon, dansLaPalette: true,
        needs: { body in body.condition.map { base.union(conditionNeeds($0)) } ?? base },
        parDefaut: { .ifElse(.windowOpen(.dialog), then: [], otherwise: []) },
        resume: { body, _ in body.condition.map { "Si " + describe($0) } ?? "Si" },
        journal: { _ in "if" },
        estimationMs: { body in
            guard case .ifElse(_, let then, let otherwise) = body else { return 0 }
            return 50 + max(MacroValidation.estimateMs(then), MacroValidation.estimateMs(otherwise))
        },
        valider: { body, ctx in body.condition.flatMap { MacroValidation.conditionProblem($0, ctx) } },
        import_: .ok, plateformes: .mac)

    static let repeatCount = BlockSpec(
        type: .repeatCount, label: "Répéter", category: .controle, symbol: "repeat",
        aide: "Répète les blocs N fois (\(MacroValidation.maxRepeat) au plus).",
        params: [ParamSpec("count", "Nombre de fois", .nombre(1...MacroValidation.maxRepeat)), ParamSpec("blocks", "Blocs", .blocs)],
        conteneur: .corps, dansLaPalette: true,
        needs: { _ in base },
        parDefaut: { .repeatCount(2, []) },
        resume: { body, _ in
            guard case .repeatCount(let n, _) = body else { return "" }
            return "\(n) fois"
        },
        journal: { _ in "repeat" },
        estimationMs: { body in
            guard case .repeatCount(let n, let blocks) = body else { return 0 }
            return MacroValidation.times(max(n, 0), MacroValidation.estimateMs(blocks))
        },
        valider: { body, ctx in
            guard case .repeatCount(let n, _) = body else { return nil }
            return (1...MacroValidation.maxRepeat).contains(n) ? nil : ctx.fail("nombre de répétitions hors limites.")
        },
        import_: .ok, plateformes: .mac)

    static let repeatWhile = BlockSpec(
        type: .repeatWhile, label: "Tant que", category: .controle, symbol: "arrow.clockwise",
        aide: "Répète les blocs tant que la condition est vraie (\(MacroValidation.maxWhile) tours au plus).",
        params: [ParamSpec("condition", "Condition", .condition),
                 ParamSpec("maxIterations", "Tours au plus", .nombre(1...MacroValidation.maxWhile)), ParamSpec("blocks", "Blocs", .blocs)],
        conteneur: .corps, dansLaPalette: true,
        needs: { body in body.condition.map { base.union(conditionNeeds($0)) } ?? base },
        parDefaut: { .repeatWhile(.windowOpen(.menu), maxIterations: 10, []) },
        resume: { body, _ in body.condition.map { "Tant que " + describe($0) } ?? "Tant que" },
        journal: { _ in "while" },
        estimationMs: { body in
            guard case .repeatWhile(_, let max, let blocks) = body else { return 0 }
            return MacroValidation.times(Swift.max(max, 0), 50 + MacroValidation.estimateMs(blocks))
        },
        valider: { body, ctx in
            guard case .repeatWhile(let c, let max, _) = body else { return nil }
            guard (1...MacroValidation.maxWhile).contains(max) else { return ctx.fail("nombre de tours hors limites.") }
            return MacroValidation.conditionProblem(c, ctx)
        },
        import_: .ok, plateformes: .mac)

    static let waitUntil = BlockSpec(
        type: .waitUntil, label: "Attendre que", category: .controle, symbol: "clock.badge.checkmark",
        aide: "Attend que la condition devienne vraie (vérifiée 4 fois par seconde, 120 s au plus).",
        params: [ParamSpec("condition", "Condition", .condition), ParamSpec("timeoutMs", "Au plus (ms)", .ms(100...MacroValidation.maxWaitMs))],
        conteneur: .aucun, dansLaPalette: true,
        needs: { body in body.condition.map { base.union(conditionNeeds($0)) } ?? base },
        parDefaut: { .waitUntil(.windowOpen(.dialog), timeoutMs: 4_000) },
        resume: { body, _ in
            guard case .waitUntil(let c, let ms) = body else { return "" }
            return "Jusqu'à ce que \(describe(c)) · \(seconds(ms)) au plus"
        },
        journal: { _ in "waitUntil" },
        estimationMs: { body in
            guard case .waitUntil(_, let ms) = body else { return 0 }
            return max(ms, 0)
        },
        valider: { body, ctx in
            guard case .waitUntil(let c, let ms) = body else { return nil }
            guard (100...MacroValidation.maxWaitMs).contains(ms) else { return ctx.fail("attente hors limites.") }
            return MacroValidation.conditionProblem(c, ctx)
        },
        import_: .ok, plateformes: .mac)

    static let setVariable = BlockSpec(
        type: .setVariable, label: "Régler une variable", category: .controle, symbol: "number",
        aide: "Donne une valeur (nombre entier) à une variable de la macro.",
        params: [ParamSpec("variable", "Variable", .variable), ParamSpec("value", "Valeur", .variable)],
        conteneur: .aucun, dansLaPalette: false,
        needs: { body in
            guard case .setVariable(_, let v) = body else { return base }
            return base.union(sourceNeeds(v))
        },
        parDefaut: { .setVariable("n", .constant(0)) },
        resume: { body, _ in
            guard case .setVariable(let name, let v) = body else { return "" }
            return "\(name.displaySafe(max: 16)) = \(describe(v))"
        },
        journal: { _ in "setVariable" },
        estimationMs: { body in
            guard case .setVariable(_, let v) = body else { return 0 }
            if case .flState = v { return 500 }
            return 0
        },
        valider: { body, ctx in
            guard case .setVariable(let name, let v) = body else { return nil }
            guard ctx.variables.contains(name) else { return ctx.fail("variable inconnue.") }
            return MacroValidation.sourceProblem(v, ctx)
        },
        import_: .ok, plateformes: .mac)

    static let stop = BlockSpec(
        type: .stop, label: "Arrêter la macro", category: .controle, symbol: "stop.circle",
        aide: "Arrête la macro ici, avec un message facultatif.",
        params: [ParamSpec("message", "Message", .texte(max: 120))],
        conteneur: .aucun, dansLaPalette: true,
        needs: { _ in base },
        parDefaut: { .stop(message: nil) },
        resume: { body, _ in
            guard case .stop(let m) = body, let m else { return "Fin de la macro" }
            return m.displaySafe(max: 60)
        },
        journal: { _ in "stop" },
        estimationMs: { _ in 0 },
        valider: { body, ctx in
            guard case .stop(let m) = body, let m else { return nil }
            return m.count <= MacroValidation.maxNoteLength ? nil : ctx.fail("message trop long.")
        },
        import_: .ok, plateformes: .mac)

    static let comment = BlockSpec(
        type: .comment, label: "Commentaire", category: .controle, symbol: "text.bubble",
        aide: "Note pour toi, ignorée à l'exécution.",
        params: [ParamSpec("text", "Texte", .texte(max: 200))],
        conteneur: .aucun, dansLaPalette: true,
        needs: { _ in [] },
        parDefaut: { .comment("Note") },
        resume: { body, _ in
            guard case .comment(let t) = body else { return "" }
            return t.displaySafe(max: 60)
        },
        journal: { _ in "comment" },
        estimationMs: { _ in 0 },
        valider: { body, ctx in
            guard case .comment(let t) = body else { return nil }
            return t.count <= 200 ? nil : ctx.fail("commentaire trop long.")
        },
        import_: .ok, plateformes: .mac)
}
