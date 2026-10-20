// Registre des blocs : l'endroit unique d'où l'interface, l'exécution, la validation, le journal et la documentation
// tirent leurs informations. `BlockRegistry.spec` est un switch exhaustif (pas un dictionnaire) : un BlockType ajouté
// sans fiche est une erreur de compilation. Textes en français ; identifiants JSON stables en ASCII (contrat).
import Foundation

enum BlockType: String, CaseIterable, Codable {
    case key, menuLetters, menuKey, click, delay, waitWindow, waitWindowClose
    /// Glisser-déposer : appui à un endroit de FL, glissé jusqu'à un autre, relâché.
    case drag
    case trackMenu, chooseFile, dropFile, flAction, flActionValue, selectInput, feedbackCheck
    /// Nom et couleur de la piste ou du canal sélectionné (lien avec FL, PROTOCOL.md §7).
    case nameColor
    /// La carte son branchée devient la sortie et l'entrée du Mac.
    case soundCard
    /// Ouvre l'Organiser sur la page de FL devant (Channel rack, Mixer ou Playlist) ; la suite se passe dans sa
    /// fenêtre.
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

    /// Nom affiché de la catégorie (palette, recherche) ; le rawValue reste tel quel.
    var label: String {
        switch self {
        case .clavier: return String(localized: "Clavier")
        case .souris: return String(localized: "Souris")
        case .fenetres: return String(localized: "Fenêtres et attentes")
        case .fl: return String(localized: "FL Studio")
        case .controle: return String(localized: "Contrôle")
        }
    }
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
    func fail(_ text: String) -> String { String(localized: "Étape \(path) : \(text)") }
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
        case .drag: return Specs.drag
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

    static func label(of body: BlockBody) -> String { body.type.map { spec($0).label } ?? String(localized: "Bloc inconnu") }

    static func estimateMs(_ body: BlockBody) -> Int { body.type.map { spec($0).estimationMs(body) } ?? 0 }
}

// MARK: - Fiches

private enum Specs {
    static let base: BlockNeeds = [.flAuPremierPlan, .clavierAuRepos]

    static func seconds(_ ms: Int) -> String {
        ms % 1000 == 0 ? String(localized: "\(ms / 1000) s") : String(format: "%.1f s", Double(ms) / 1000).replacingOccurrences(of: ".", with: ",")
    }

    static func times(_ n: Int) -> String { n > 1 ? " × \(n)" : "" }

    static func windowName(_ k: WindowKind) -> String { k == .dialog ? String(localized: "Boîte de dialogue") : String(localized: "Menu") }

    static func describe(_ c: Condition) -> String {
        switch c {
        case .windowOpen(let k):
            return k == .dialog ? String(localized: "une boîte de dialogue est ouverte") : String(localized: "un menu de FL est ouvert")
        case .flState(let q, let op, let v): return String(localized: "FL : \(q) \(op.symbol) \(v)")
        case .variable(let name, let op, let v): return "\(name.displaySafe(max: 16)) \(op.symbol) \(v)"
        case .lastBlockFailed: return String(localized: "le bloc précédent a échoué")
        case .not(let inner): return String(localized: "non (\(describe(inner)))")
        case .all(let list): return list.map { describe($0) }.joined(separator: String(localized: " et "))
        case .any(let list): return list.map { describe($0) }.joined(separator: String(localized: " ou "))
        }
    }

    static func describe(_ v: IntSource) -> String {
        switch v {
        case .constant(let n): return "\(n)"
        case .variable(let name): return name.displaySafe(max: 16)
        case .flState(let q): return String(localized: "FL : \(q)")
        }
    }

    static func describe(_ t: ClickTarget) -> String {
        switch t {
        case .flWindow: return String(localized: "fenêtre de FL")
        case .openMenu: return String(localized: "menu ouvert")
        case .button: return String(localized: "bouton retrouvé à son image")
        case .named: return String(localized: "bouton retrouvé à son nom")
        case .track: return String(localized: "piste visée")
        case .lastClick: return String(localized: "après le clic précédent")
        case .startCursor: return String(localized: "curseur au départ")
        case .cursorXWindowY: return String(localized: "colonne du curseur")
        case .toLearn: return String(localized: "à montrer dans FL")
        }
    }

    /// Lettres a à z seulement (lettres soulignées des menus de FL).
    static func lettersOK(_ letters: [Character]) -> Bool {
        letters.allSatisfy { ("a"..."z").contains($0) }
    }

    static func keyProblem(_ combo: KeyCombo, _ ctx: ValidationContext, what: String = String(localized: "touche")) -> String? {
        guard combo.isValidKey else { return ctx.fail(String(localized: "\(what) non prise en charge.")) }
        if let why = ctx.forbidden.reason(for: combo) { return ctx.fail(String(localized: "\(what) interdite (\(why)).")) }
        return nil
    }

    static func enterProblem(_ e: EnterPolicy, _ ctx: ValidationContext) -> String? {
        if case .learned(let key) = e, !MacroValidation.learnedEnterKeys.contains(key) {
            return ctx.fail(String(localized: "mémoire de l'Entrée inconnue."))
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
        type: .key, label: String(localized: "Touche ou raccourci"), category: .clavier, symbol: "keyboard",
        aide: String(localized: "Envoie une touche ou un raccourci clavier à FL (⌘A, ⇧⌘S, F9…), seulement quand FL est au premier plan. Clique le champ puis tape le raccourci, ou coche ⌘ ⌥ ⌃ ⇧. Les raccourcis dangereux (⌘Q, ⌘W…) sont refusés."),
        params: [ParamSpec("key", String(localized: "Touche"), .touche), ParamSpec("times", String(localized: "Nombre de fois"), .nombre(1...20))],
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
            guard (1...20).contains(n) else { return ctx.fail(String(localized: "nombre de fois hors limites.")) }
            return keyProblem(k.combo, ctx)
        },
        import_: .aRelire("touche envoyée à FL"), plateformes: .mac)

    static let menuLetters = BlockSpec(
        type: .menuLetters, label: String(localized: "Lettres d'un menu de FL"), category: .clavier, symbol: "character.cursor.ibeam",
        aide: String(localized: "Tape les lettres soulignées d'un menu de FL déjà ouvert (F de File, O de Open…), seulement si un menu ouvert par la macro est encore là."),
        params: [ParamSpec("letters", String(localized: "Lettres"), .lettres(max: 8)), ParamSpec("finalEnter", String(localized: "Entrée à la fin"), .toucheMenu)],
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
            guard (1...8).contains(l.count), lettersOK(l) else { return ctx.fail(String(localized: "lettres de menu invalides (a à z).")) }
            return enterProblem(e, ctx)
        },
        import_: .ok, plateformes: .mac)

    static let menuKey = BlockSpec(
        type: .menuKey, label: String(localized: "Touche de menu"), category: .clavier, symbol: "arrow.up.arrow.down",
        aide: String(localized: "Flèche, Entrée ou Échap dans un menu de FL ouvert par la macro (jamais ailleurs)."),
        params: [ParamSpec("menuKey", String(localized: "Touche"), .toucheMenu), ParamSpec("times", String(localized: "Nombre de fois"), .nombre(1...20))],
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
            return (1...20).contains(n) ? nil : ctx.fail(String(localized: "nombre de fois hors limites."))
        },
        import_: .ok, plateformes: .mac)

    // MARK: Souris

    static let click = BlockSpec(
        type: .click, label: String(localized: "Clic"), category: .souris, symbol: "cursorarrow.click",
        aide: String(localized: "Clic gauche ou droit à un endroit retrouvé à chaque fois (coin d'une fenêtre de FL, piste visée, menu ouvert, fenêtre d'un plugin comme Serum…). Toujours dans une fenêtre de FL ou de ses plugins, jamais sous une autre app."),
        params: [ParamSpec("target", String(localized: "Où"), .cible), ParamSpec("button", String(localized: "Bouton"), .nombre(0...1))],
        conteneur: .aucun, dansLaPalette: true,
        needs: { body in
            var n: BlockNeeds = base.union(.cliqueHID)
            if case .click(.track, _) = body { n.insert(.pisteVisee) }
            return n
        },
        parDefaut: { .click(.track(dx: 0, dy: 0), button: .left) },
        resume: { body, _ in
            guard case .click(let t, let b) = body else { return "" }
            return (b == .right ? String(localized: "Clic droit · ") : String(localized: "Clic · ")) + describe(t)
        },
        journal: { _ in "click" },
        estimationMs: { _ in 300 },
        valider: { body, ctx in
            guard case .click(let t, let b) = body else { return nil }
            if case .toLearn = t { return ctx.fail(String(localized: "position à montrer dans FL (« Montrer dans FL… » dans le créateur).")) }
            guard t.isFinite else { return ctx.fail(String(localized: "position invalide.")) }
            if case .openMenu = t, b == .right { return ctx.fail(String(localized: "clic droit impossible dans un menu ouvert.")) }
            return nil
        },
        import_: .retirerPositions, plateformes: .mac)

    static let drag = BlockSpec(
        type: .drag, label: String(localized: "Glisser-déposer"), category: .souris, symbol: "hand.draw",
        aide: String(localized: "Reste cliqué à un endroit de FL (un son du Browser, un clip, un plugin…), glisse jusqu'à un autre endroit de FL et lâche. Les deux endroits se montrent une fois en faisant le geste dans FL ; toujours dans les fenêtres de FL, jamais sous une autre app."),
        params: [ParamSpec("from", String(localized: "Glisser"), .cible)],
        conteneur: .aucun, dansLaPalette: true,
        needs: { body in
            var n: BlockNeeds = base.union(.cliqueHID)
            if case .drag(let a, let b) = body, a.isTrack || b.isTrack { n.insert(.pisteVisee) }
            return n
        },
        parDefaut: { .drag(from: .lastClick(dx: 0, dy: 0), to: .startCursor(dx: 0, dy: 0)) },
        resume: { body, _ in
            guard case .drag(let a, let b) = body else { return "" }
            return describe(a) + " → " + describe(b)
        },
        journal: { _ in "drag" },
        estimationMs: { _ in 700 },
        valider: { body, ctx in
            guard case .drag(let a, let b) = body else { return nil }
            if a == .toLearn || b == .toLearn {
                return ctx.fail(String(localized: "glisser à montrer dans FL (« Montrer dans FL… » dans le créateur)."))
            }
            guard a.isFinite, b.isFinite else { return ctx.fail(String(localized: "position invalide.")) }
            if case .openMenu = a { return ctx.fail(String(localized: "glisser impossible depuis un menu ouvert.")) }
            if case .openMenu = b { return ctx.fail(String(localized: "glisser impossible vers un menu ouvert.")) }
            return nil
        },
        import_: .retirerPositions, plateformes: .mac)

    // MARK: Fenêtres et attentes

    static let delay = BlockSpec(
        type: .delay, label: String(localized: "Attendre un temps fixe"), category: .fenetres, symbol: "hourglass",
        aide: String(localized: "Attend un moment (5 s au plus). Échap l'interrompt. À éviter : mieux vaut attendre qu'une fenêtre s'ouvre ou se ferme."),
        params: [ParamSpec("wait", String(localized: "Attendre"), .fenetre), ParamSpec("ms", String(localized: "Durée (ms)"), .ms(0...MacroValidation.maxDelayMs))],
        conteneur: .aucun, dansLaPalette: true,
        needs: { _ in base },
        parDefaut: { .delay(ms: 200) },
        resume: { body, _ in
            guard case .delay(let ms) = body else { return "" }
            return ms < 1000 ? String(localized: "\(ms) ms") : seconds(ms)
        },
        journal: { _ in "delay" },
        estimationMs: { body in
            guard case .delay(let ms) = body else { return 0 }
            return max(ms, 0)
        },
        valider: { body, ctx in
            guard case .delay(let ms) = body else { return nil }
            return (0...MacroValidation.maxDelayMs).contains(ms) ? nil : ctx.fail(String(localized: "pause hors limites."))
        },
        import_: .ok, plateformes: .mac)

    static func waitValidator(_ body: BlockBody, _ ctx: ValidationContext) -> String? {
        switch body {
        case .waitWindow(_, let ms), .waitWindowClose(_, let ms):
            return (100...MacroValidation.maxWaitMs).contains(ms) ? nil : ctx.fail(String(localized: "attente hors limites."))
        default:
            return nil
        }
    }

    static let waitWindow = BlockSpec(
        type: .waitWindow, label: String(localized: "Attendre une fenêtre"), category: .fenetres, symbol: "macwindow.badge.plus",
        aide: String(localized: "Attend qu'une boîte de dialogue ou un menu de FL s'ouvre (120 s au plus)."),
        params: [ParamSpec("wait", String(localized: "Attendre"), .fenetre), ParamSpec("timeoutMs", String(localized: "Au plus (ms)"), .ms(100...MacroValidation.maxWaitMs))],
        conteneur: .aucun, dansLaPalette: true,
        needs: { _ in base },
        parDefaut: { .waitWindow(.dialog, timeoutMs: 4_000) },
        resume: { body, _ in
            guard case .waitWindow(let k, let ms) = body else { return "" }
            return String(localized: "\(windowName(k)) · \(seconds(ms)) au plus")
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
        type: .waitWindowClose, label: String(localized: "Attendre la fermeture"), category: .fenetres, symbol: "macwindow",
        aide: String(localized: "Attend que la boîte ou le menu se ferme (par exemple pendant que tu choisis ton preset, 120 s au plus)."),
        params: [ParamSpec("wait", String(localized: "Attendre"), .fenetre), ParamSpec("timeoutMs", String(localized: "Au plus (ms)"), .ms(100...MacroValidation.maxWaitMs))],
        conteneur: .aucun, dansLaPalette: true,
        needs: { _ in base },
        parDefaut: { .waitWindowClose(.dialog, timeoutMs: 8_000) },
        resume: { body, _ in
            guard case .waitWindowClose(let k, let ms) = body else { return "" }
            return String(localized: "\(windowName(k)) fermée · \(seconds(ms)) au plus")
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
        type: .trackMenu, label: String(localized: "Menu de la piste"), category: .fl, symbol: "list.bullet.rectangle",
        aide: String(localized: "Clic droit sur la dernière piste cliquée dans le Mixer, puis l'élément choisi dans la liste (ouvrir un état de piste, renommer…), au clavier : rien à apprendre."),
        params: [ParamSpec("letters", String(localized: "Élément"), .lettres(max: 3)), ParamSpec("finalEnter", String(localized: "Entrée à la fin"), .toucheMenu)],
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
                  labels.allSatisfy({ !$0.isEmpty && $0.count <= 160 }) else { return ctx.fail(String(localized: "titres de menu invalides.")) }
            guard (1...3).contains(l.count), lettersOK(l) else {
                return ctx.fail(String(localized: "choisis l'élément du menu de la piste (ou 1 à 3 lettres soulignées, a à z)."))
            }
            if e == .never { return ctx.fail(String(localized: "le menu de la piste doit se fermer sur son dernier élément.")) }
            return enterProblem(e, ctx)
        },
        import_: .ok, plateformes: .mac)

    static let chooseFile = BlockSpec(
        type: .chooseFile, label: String(localized: "Ouvrir un preset (boîte Open)"), category: .fl, symbol: "doc.badge.arrow.up",
        aide: String(localized: "Quand FL a ouvert sa boîte « Open » (preset d'un plugin, d'un canal…) : va au fichier .fst choisi et l'ouvre. À placer après les clics qui ouvrent la boîte et un « Attendre »."),
        params: [ParamSpec("path", String(localized: "Fichier"), .fichier(extensions: ["fst"]))],
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
        type: .dropFile, label: String(localized: "Déposer un preset sur la piste"), category: .fl, symbol: "square.and.arrow.down.on.square",
        aide: String(localized: "Glisse le fichier sur la dernière piste cliquée dans le Mixer, comme depuis le Finder : FL y charge l'état de piste, sans menu ni boîte « Open »."),
        params: [ParamSpec("path", String(localized: "Fichier"), .fichier(extensions: ["fst"]))],
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
            return ctx.fail(String(localized: "chemin de fichier invalide."))
        }
        if ctx.strictFiles {
            let home = NSHomeDirectory() + "/"
            let parts = p.split(separator: "/")
            let placeOK = ctx.presetAnywhere ? p.hasPrefix("/") : p.hasPrefix(home)
            guard placeOK, !parts.contains(".."), URL(fileURLWithPath: p).pathExtension.lowercased() == "fst" else {
                return ctx.fail(ctx.presetAnywhere ? String(localized: "preset .fst attendu.")
                                                   : String(localized: "preset .fst attendu dans ton dossier personnel."))
            }
        }
        return nil
    }

    static let flAction = BlockSpec(
        type: .flAction, label: String(localized: "Action de FL"), category: .fl, symbol: "bolt.horizontal",
        aide: String(localized: "Lance une action de FL par le lien avec FL (réveil bref, puis il se rendort). Sans lien : son équivalent au clavier, s'il existe."),
        params: [ParamSpec("action", String(localized: "Action"), .actionFL), ParamSpec("fallback", String(localized: "Sans lien"), .touche)],
        conteneur: .aucun, dansLaPalette: true,
        needs: { body in
            var n: BlockNeeds = base.union(.lienMIDI)
            if case .flAction(_, .trackMenuArm) = body { n.formUnion([.cliqueHID, .pisteVisee]) }
            // Mute / solo sans le script : bouton mute de la piste cliquée juste avant (MacroMuteSolo.swift).
            if case .flAction(let key, .none) = body, MuteSolo.handlesWithoutLink(key) { n.formUnion([.cliqueHID, .pisteVisee]) }
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
            guard FLActions.id(forKey: key) != nil else { return ctx.fail(String(localized: "action de FL inconnue.")) }
            switch fallback {
            case .none: return nil
            case .trackMenuArm:
                return key == "armon" ? nil : ctx.fail(String(localized: "le menu de la piste ne sait qu'armer la piste."))
            case .key(let k):
                return keyProblem(k.combo, ctx, what: key == "recon" ? String(localized: "touche REC") : String(localized: "touche de secours"))
            }
        },
        import_: .aRelire("passe par le lien avec FL"), plateformes: .mac)

    static let flActionValue = BlockSpec(
        type: .flActionValue, label: String(localized: "Action de FL avec valeur"), category: .fl, symbol: "slider.horizontal.3",
        aide: String(localized: "Action de FL avec un nombre (piste N, pattern N…). Demande l'extension du lien avec FL."),
        params: [ParamSpec("action", String(localized: "Action"), .actionFL), ParamSpec("value", String(localized: "Valeur"), .variable)],
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
            guard FLActions.id(forKey: key) != nil else { return ctx.fail(String(localized: "action de FL inconnue.")) }
            return MacroValidation.sourceProblem(v, ctx)
        },
        import_: .aRelire("passe par le lien avec FL"), plateformes: .mac)

    static let selectInput = BlockSpec(
        type: .selectInput, label: String(localized: "Choisir l'entrée 1"), category: .fl, symbol: "mic",
        aide: String(localized: "« (none) » → entrée 1 de la piste. Montré une seule fois (une bulle le demande), puis refait seul."),
        params: [],
        conteneur: .aucun, dansLaPalette: true,
        needs: { _ in base.union([.cliqueHID, .pisteVisee]) },
        parDefaut: { MacroTemplates.inputOne },
        resume: { _, _ in String(localized: "« (none) » → entrée 1") },
        journal: { _ in "selectInput" },
        estimationMs: { _ in 3_000 },
        valider: { body, ctx in
            guard case .selectInput(.legacy(let key)) = body else { return nil }
            return MacroValidation.learnedPathKeys.contains(key) ? nil : ctx.fail(String(localized: "positions apprises inconnues."))
        },
        import_: .retirerPositions, plateformes: .mac)

    static let nameColor = BlockSpec(
        type: .nameColor, label: String(localized: "Nom et couleur"), category: .fl, symbol: "paintpalette",
        aide: String(localized: "Donne un nom et/ou une couleur à la piste ou au canal sélectionné dans la page de FL qui est devant (Mixer, Channel rack ou Playlist), par le lien avec FL, et une icône de FL par sa fenêtre (F2). Un seul élément doit être sélectionné."),
        params: [ParamSpec("name", String(localized: "Nom"), .texte(max: NameColorPayload.maxNameScalars)),
                 ParamSpec("color", String(localized: "Couleur"), .couleur),
                 ParamSpec("icon", String(localized: "Icône"), .icone)],
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
                guard payload.color != nil else { return ctx.fail(String(localized: "un dégradé demande ses deux couleurs.")) }
                guard payload.name == nil else { return ctx.fail(String(localized: "un dégradé ne change pas le nom : retire le nom.")) }
                guard icon == nil else { return ctx.fail(String(localized: "un dégradé ne pose pas d'icône : retire l'icône.")) }
            }
            guard payload.name != nil || payload.color != nil || icon != nil else {
                return ctx.fail(String(localized: "donne un nom ou une couleur."))
            }
            if let n = payload.name, let why = NameColorPayload.nameProblem(n) { return ctx.fail(why) }
            return nil
        },
        import_: .aRelire("renomme et colore dans FL"), plateformes: .mac)

    static let soundCard = BlockSpec(
        type: .soundCard, label: String(localized: "Carte son branchée"), category: .fl, symbol: "hifispeaker.and.homepod",
        aide: String(localized: "La carte son branchée (USB, Thunderbolt…) devient la sortie et l'entrée du Mac ; FL la suit tout seul s'il est réglé une fois sur « Default audio device » (Output) et « Default input device » (Input) dans Options › Audio settings."),
        params: [],
        conteneur: .aucun, dansLaPalette: true,
        needs: { _ in [] },
        parDefaut: { .soundCard },
        resume: { _, _ in String(localized: "sortie et entrée du Mac") },
        journal: { _ in "soundCard" },
        estimationMs: { _ in 200 },
        valider: { _, _ in nil },
        import_: .ok, plateformes: .mac)

    static let organize = BlockSpec(
        type: .organize, label: String(localized: "Tout organiser"), category: .fl, symbol: "square.stack.3d.up",
        aide: String(localized: "Ouvre l'Organiser sur tout le projet : chaque son est reconnu d'après son nom (« BEAM KICK » : Kick), sinon écouté sans que tu l'entendes ; tu vérifies l'aperçu, puis « Tout organiser » range le Channel rack (les Kick ensemble, puis les Snare…), met le Mixer dans le même ordre (pistes reliées côte à côte), colore et renomme simplement sons, patterns, pistes du Mixer et de la Playlist. « Revenir comme avant » défait tout."),
        params: [],
        conteneur: .aucun, dansLaPalette: true,
        needs: { _ in base.union(.lienMIDI) },
        parDefaut: { .organize },
        resume: { _, _ in String(localized: "range, colore, renomme le projet") },
        journal: { _ in "organize" },
        estimationMs: { _ in 200 },
        valider: { _, _ in nil },
        import_: .ok, plateformes: .mac)

    static let feedbackCheck = BlockSpec(
        type: .feedbackCheck, label: String(localized: "Vérifier le larsen"), category: .fl, symbol: "speaker.wave.2",
        aide: String(localized: "Micro et haut-parleurs de l'ordinateur sans casque : explique comment éviter le larsen. Vérifié dès le début de la macro, affiché à la fin."),
        params: [],
        conteneur: .aucun, dansLaPalette: true,
        needs: { _ in base.union(.larsenEnAvance) },
        parDefaut: { .feedbackCheck },
        resume: { _, _ in String(localized: "Micro et sortie de l'ordinateur") },
        journal: { _ in "feedbackCheck" },
        estimationMs: { _ in 3_000 },
        valider: { _, _ in nil },
        import_: .ok, plateformes: .mac)

    static let openPage = BlockSpec(
        type: .openPage, label: String(localized: "Ouvrir une page de FL"), category: .fl, symbol: "macwindow",
        aide: String(localized: "Met devant une page de FL (Playlist, Channel Rack, Mixer…), seulement si elle n'y est pas déjà. Les options de « Cliquer sur… » juste en dessous sont celles de cette page."),
        params: [ParamSpec("page", String(localized: "Page"), .fenetre)],
        conteneur: .aucun, dansLaPalette: true,
        needs: { _ in base.union(.lienMIDI) },
        parDefaut: { .openPage(.mixer) },
        resume: { body, _ in
            guard case .openPage(let page) = body else { return "" }
            return page?.title ?? String(localized: "page à choisir")
        },
        journal: { body in
            guard case .openPage(let page) = body else { return "openPage" }
            return "openPage \(page?.rawValue ?? "?")"
        },
        estimationMs: { _ in 600 },
        valider: { body, ctx in
            guard case .openPage(let page) = body else { return nil }
            return page == nil ? ctx.fail(String(localized: "choisis la page de FL à ouvrir.")) : nil
        },
        import_: .ok, plateformes: .mac)

    static let pageOption = BlockSpec(
        type: .pageOption, label: String(localized: "Cliquer sur…"), category: .fl, symbol: "cursorarrow.click.2",
        aide: String(localized: "Une option de la page de FL ouverte juste au-dessus : ajouter un instrument ou un effet, armer la piste, mute ou solo d'un canal par son numéro, renommer la piste, ou un raccourci de FL de cette page. Jamais de clic de souris. Ajouté avec « Ouvrir une page de FL » au-dessus."),
        params: [ParamSpec("option", String(localized: "Option"), .actionFL), ParamSpec("name", String(localized: "Valeur"), .texte(max: PageOptions.maxName))],
        conteneur: .aucun, dansLaPalette: true,
        needs: { body in
            guard case .pageOption(let id?, _) = body, PageOptions.usesLink(id) else { return base }
            // Armer, mute ou solo sans le lien : par la piste visée (comme « Action de FL »).
            let byTrack: Set<String> = ["mixer.armon", "mixer.mute", "mixer.solo"]
            return byTrack.contains(id) ? base.union([.lienMIDI, .cliqueHID, .pisteVisee]) : base.union(.lienMIDI)
        },
        // Valide sous la page par défaut d'« Ouvrir une page de FL » (Mixer) ; la palette les donne à choisir.
        parDefaut: { .pageOption(id: "mixer.armon", name: "") },
        resume: { body, layout in
            guard case .pageOption(let id, let name) = body else { return "" }
            guard let id, let option = PageOptions.option(id, layout: layout) else { return String(localized: "option à choisir") }
            let value = name.trimmingCharacters(in: .whitespaces)
            switch option.field {
            case .channel?:
                guard let n = PageOptions.channel(value), case .channelToggle(let solo) = option.kind else { return option.label }
                return String(localized: "\(solo ? "Solo" : "Mute") du canal \(n)")
            case .plugin?, .name?:
                return value.isEmpty ? option.label : String(localized: "\(option.label) : \(value.displaySafe(max: 30))")
            case nil:
                return option.label
            }
        },
        journal: { body in
            guard case .pageOption(let id, _) = body else { return "pageOption" }
            return "pageOption \(id.flatMap { PageOptions.page(of: $0)?.rawValue } ?? "?")"
        },
        estimationMs: { _ in 800 },
        valider: { body, ctx in
            guard case .pageOption(let id, let name) = body else { return nil }
            guard let id else { return ctx.fail(String(localized: "choisis l'option à cliquer.")) }
            guard PageOptions.isKnown(id) else { return ctx.fail(String(localized: "option de FL inconnue.")) }
            if let field = PageOptions.field(of: id), let problem = PageOptions.valueProblem(field, name) {
                return ctx.fail(problem)
            }
            return nil
        },
        import_: .ok, plateformes: .mac)

    static let menuBar = BlockSpec(
        type: .menuBar, label: String(localized: "Menu de FL"), category: .fl, symbol: "menubar.rectangle",
        aide: String(localized: "Choisit un élément des menus de FL (File › Export › …) : tu parcours ses menus comme dans FL, puis la macro le choisit par son nom dans la barre des menus de macOS, grâce à l'Accessibilité : rien n'est cliqué à l'écran."),
        params: [],
        conteneur: .aucun, dansLaPalette: true,
        needs: { _ in base },
        parDefaut: { .menuBar(titles: []) },
        resume: { body, _ in
            guard case .menuBar(let titles) = body else { return "" }
            return titles.isEmpty ? String(localized: "à choisir") : titles.map { $0.displaySafe(max: 30) }.joined(separator: " › ")
        },
        journal: { _ in "menuBar" },
        estimationMs: { _ in 400 },
        valider: { body, ctx in
            guard case .menuBar(let titles) = body else { return nil }
            guard !titles.isEmpty else { return ctx.fail(String(localized: "choisis l'élément dans les menus de FL.")) }
            guard (2...MenuBarAX.maxDepth).contains(titles.count),
                  titles.allSatisfy({ !$0.trimmingCharacters(in: .whitespaces).isEmpty && $0.count <= 80 }) else {
                return ctx.fail(String(localized: "chemin de menu invalide."))
            }
            return nil
        },
        import_: .ok, plateformes: .mac)

    static let menuAX = BlockSpec(
        type: .menuAX, label: String(localized: "Menu (ancien format)"), category: .fl, symbol: "filemenu.and.selection",
        aide: String(localized: "Choisit un élément de menu par son titre (Accessibilité), sinon par des clics de secours appris. Repris des anciennes macros, absent de la palette."),
        params: [ParamSpec("titles", String(localized: "Titres"), .texte(max: 80)), ParamSpec("fallback", String(localized: "Clics de secours"), .cible)],
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
                return ctx.fail(String(localized: "titres de menu invalides."))
            }
            guard fallback.count <= 3, fallback.allSatisfy(\.isFinite) else { return ctx.fail(String(localized: "positions de secours invalides.")) }
            return nil
        },
        import_: .retirerPositions, plateformes: .mac)

    // MARK: Contrôle

    static let ifElse = BlockSpec(
        type: .ifElse, label: String(localized: "Si… sinon"), category: .controle, symbol: "arrow.triangle.branch",
        aide: String(localized: "Fait les blocs « alors » si la condition est vraie, sinon les blocs « sinon »."),
        params: [ParamSpec("condition", String(localized: "Condition"), .condition), ParamSpec("then", String(localized: "Alors"), .blocs), ParamSpec("else", String(localized: "Sinon"), .blocs)],
        conteneur: .siSinon, dansLaPalette: true,
        needs: { body in body.condition.map { base.union(conditionNeeds($0)) } ?? base },
        parDefaut: { .ifElse(.windowOpen(.dialog), then: [], otherwise: []) },
        resume: { body, _ in body.condition.map { String(localized: "Si ") + describe($0) } ?? String(localized: "Si") },
        journal: { _ in "if" },
        estimationMs: { body in
            guard case .ifElse(_, let then, let otherwise) = body else { return 0 }
            return 50 + max(MacroValidation.estimateMs(then), MacroValidation.estimateMs(otherwise))
        },
        valider: { body, ctx in body.condition.flatMap { MacroValidation.conditionProblem($0, ctx) } },
        import_: .ok, plateformes: .mac)

    static let repeatCount = BlockSpec(
        type: .repeatCount, label: String(localized: "Répéter"), category: .controle, symbol: "repeat",
        aide: String(localized: "Répète les blocs N fois (\(MacroValidation.maxRepeat) au plus)."),
        params: [ParamSpec("count", String(localized: "Nombre de fois"), .nombre(1...MacroValidation.maxRepeat)), ParamSpec("blocks", String(localized: "Blocs"), .blocs)],
        conteneur: .corps, dansLaPalette: true,
        needs: { _ in base },
        parDefaut: { .repeatCount(2, []) },
        resume: { body, _ in
            guard case .repeatCount(let n, _) = body else { return "" }
            return String(localized: "\(n) fois")
        },
        journal: { _ in "repeat" },
        estimationMs: { body in
            guard case .repeatCount(let n, let blocks) = body else { return 0 }
            return MacroValidation.times(max(n, 0), MacroValidation.estimateMs(blocks))
        },
        valider: { body, ctx in
            guard case .repeatCount(let n, _) = body else { return nil }
            return (1...MacroValidation.maxRepeat).contains(n) ? nil : ctx.fail(String(localized: "nombre de répétitions hors limites."))
        },
        import_: .ok, plateformes: .mac)

    static let repeatWhile = BlockSpec(
        type: .repeatWhile, label: String(localized: "Tant que"), category: .controle, symbol: "arrow.clockwise",
        aide: String(localized: "Répète les blocs tant que la condition est vraie (\(MacroValidation.maxWhile) tours au plus)."),
        params: [ParamSpec("condition", String(localized: "Condition"), .condition),
                 ParamSpec("maxIterations", String(localized: "Tours au plus"), .nombre(1...MacroValidation.maxWhile)), ParamSpec("blocks", String(localized: "Blocs"), .blocs)],
        conteneur: .corps, dansLaPalette: true,
        needs: { body in body.condition.map { base.union(conditionNeeds($0)) } ?? base },
        parDefaut: { .repeatWhile(.windowOpen(.menu), maxIterations: 10, []) },
        resume: { body, _ in body.condition.map { String(localized: "Tant que ") + describe($0) } ?? String(localized: "Tant que") },
        journal: { _ in "while" },
        estimationMs: { body in
            guard case .repeatWhile(_, let max, let blocks) = body else { return 0 }
            return MacroValidation.times(Swift.max(max, 0), 50 + MacroValidation.estimateMs(blocks))
        },
        valider: { body, ctx in
            guard case .repeatWhile(let c, let max, _) = body else { return nil }
            guard (1...MacroValidation.maxWhile).contains(max) else { return ctx.fail(String(localized: "nombre de tours hors limites.")) }
            return MacroValidation.conditionProblem(c, ctx)
        },
        import_: .ok, plateformes: .mac)

    static let waitUntil = BlockSpec(
        type: .waitUntil, label: String(localized: "Attendre que"), category: .controle, symbol: "clock.badge.checkmark",
        aide: String(localized: "Attend que la condition devienne vraie (vérifiée 4 fois par seconde, 120 s au plus)."),
        params: [ParamSpec("condition", String(localized: "Condition"), .condition), ParamSpec("timeoutMs", String(localized: "Au plus (ms)"), .ms(100...MacroValidation.maxWaitMs))],
        conteneur: .aucun, dansLaPalette: true,
        needs: { body in body.condition.map { base.union(conditionNeeds($0)) } ?? base },
        parDefaut: { .waitUntil(.windowOpen(.dialog), timeoutMs: 4_000) },
        resume: { body, _ in
            guard case .waitUntil(let c, let ms) = body else { return "" }
            return String(localized: "Jusqu'à ce que \(describe(c)) · \(seconds(ms)) au plus")
        },
        journal: { _ in "waitUntil" },
        estimationMs: { body in
            guard case .waitUntil(_, let ms) = body else { return 0 }
            return max(ms, 0)
        },
        valider: { body, ctx in
            guard case .waitUntil(let c, let ms) = body else { return nil }
            guard (100...MacroValidation.maxWaitMs).contains(ms) else { return ctx.fail(String(localized: "attente hors limites.")) }
            return MacroValidation.conditionProblem(c, ctx)
        },
        import_: .ok, plateformes: .mac)

    static let setVariable = BlockSpec(
        type: .setVariable, label: String(localized: "Régler une variable"), category: .controle, symbol: "number",
        aide: String(localized: "Donne une valeur (nombre entier) à une variable de la macro."),
        params: [ParamSpec("variable", String(localized: "Variable"), .variable), ParamSpec("value", String(localized: "Valeur"), .variable)],
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
            guard ctx.variables.contains(name) else { return ctx.fail(String(localized: "variable inconnue.")) }
            return MacroValidation.sourceProblem(v, ctx)
        },
        import_: .ok, plateformes: .mac)

    static let stop = BlockSpec(
        type: .stop, label: String(localized: "Arrêter la macro"), category: .controle, symbol: "stop.circle",
        aide: String(localized: "Arrête la macro ici, avec un message facultatif."),
        params: [ParamSpec("message", String(localized: "Message"), .texte(max: 120))],
        conteneur: .aucun, dansLaPalette: true,
        needs: { _ in base },
        parDefaut: { .stop(message: nil) },
        resume: { body, _ in
            guard case .stop(let m) = body, let m else { return String(localized: "Fin de la macro") }
            return m.displaySafe(max: 60)
        },
        journal: { _ in "stop" },
        estimationMs: { _ in 0 },
        valider: { body, ctx in
            guard case .stop(let m) = body, let m else { return nil }
            return m.count <= MacroValidation.maxNoteLength ? nil : ctx.fail(String(localized: "message trop long."))
        },
        import_: .ok, plateformes: .mac)

    static let comment = BlockSpec(
        type: .comment, label: String(localized: "Commentaire"), category: .controle, symbol: "text.bubble",
        aide: String(localized: "Note pour toi, ignorée à l'exécution."),
        params: [ParamSpec("text", String(localized: "Texte"), .texte(max: 200))],
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
            return t.count <= 200 ? nil : ctx.fail(String(localized: "commentaire trop long."))
        },
        import_: .ok, plateformes: .mac)
}
