// Créateur de macros : logique pure (aucune vue), testable.
// - Liste à plat avec retrait selon l'imbrication (projection recalculée en O(n) seulement après une modification) :
//   une ligne par bloc, plus une ligne de fin par liste d'un conteneur (« Fin de la boucle », « Sinon »…) qui sert de
//   point d'insertion et de dépôt à l'intérieur.
// - Opérations sur l'arbre par id de bloc (insérer, retirer, déplacer, dupliquer), profondeur bornée.
// - Phrase de chaque ligne en français (verbe + valeur en pastille), badges (pause fixe, lien FL, à apprendre,
//   problème), palette des blocs (avec recherche) et cible d'un clic montré dans FL.
import CoreGraphics
import Foundation

// MARK: - Adresse d'un bloc

/// Un pas du chemin d'un bloc : la liste de son parent (0 : corps ou « alors », 1 : « sinon ») puis sa place.
struct BlockStep: Hashable {
    var slot: Int
    var index: Int
}

/// Où insérer : liste `slot` du conteneur `container` (chemin vide : la racine), à la place `index`.
struct InsertionPoint: Equatable {
    var container: [BlockStep]
    var slot: Int
    var index: Int

    static func rootEnd(_ blocks: [Block]) -> InsertionPoint { InsertionPoint(container: [], slot: 0, index: blocks.count) }
}

/// Destination d'un déplacement, exprimée par ids (stable pendant que la source est retirée).
enum MoveTarget: Equatable {
    case before(UUID)
    case end(container: UUID, slot: Int)
    case rootEnd
}

// MARK: - Ligne de la liste

enum MacroBadge: Hashable {
    /// Pause fixe : trop courte sur un projet lourd, trop longue ailleurs.
    case pauseFixe
    /// Échoue sans le lien avec FL (aucun équivalent au clavier).
    case lienFL
    /// Position ou entrée à montrer dans FL.
    case aApprendre(String)
    /// Le bloc bloque la macro (message de la validation).
    case probleme(String)
    /// « Si l'étape échoue : continuer ».
    case continueSiEchec

    var title: String {
        switch self {
        case .pauseFixe: return "Pause fixe"
        case .lienFL: return "Lien FL"
        case .aApprendre: return "À apprendre"
        case .probleme: return "À corriger"
        case .continueSiEchec: return "Continue si échec"
        }
    }

    var help: String {
        switch self {
        case .pauseFixe: return "Une pause fixe est trop courte sur un projet lourd : préfère « Attendre une fenêtre » quand FL ouvre quelque chose."
        case .lienFL: return "Ce bloc demande le lien avec FL (script MIDI) : sans lui, il échoue."
        case .aApprendre(let why), .probleme(let why): return why
        case .continueSiEchec: return "Si ce bloc échoue, la macro continue (l'échec est signalé à la fin)."
        }
    }
}

struct MacroStepRow: Identifiable, Equatable {
    enum Kind: Equatable {
        case block
        /// Fin de la liste `slot` d'un conteneur (insertion et dépôt à l'intérieur).
        case end(slot: Int)
    }

    /// « b:<id> » pour un bloc, « e<slot>:<id> » pour une fin de liste.
    let id: String
    let blockID: UUID
    let kind: Kind
    /// « 3 », « 3.2 » : même numérotation que les messages d'erreur (« Macro arrêtée au bloc 3.2 »).
    let number: String
    let depth: Int
    let type: BlockType?
    let category: BlockCategory?
    let symbol: String
    let verb: String
    let value: String?
    let note: String?
    /// Actif en tenant compte des parents (un bloc dans une boucle désactivée ne tourne pas).
    let enabled: Bool
    /// Case à cocher du bloc lui-même.
    let ownEnabled: Bool
    let badges: [MacroBadge]
    let isContainer: Bool

    static func blockRowID(_ id: UUID) -> String { "b:" + id.uuidString }
}

// MARK: - Opérations

enum MacroOutline {
    // MARK: Lecture

    static func block(at path: [BlockStep], in blocks: [Block]) -> Block? {
        var list = blocks
        var found: Block?
        for (i, step) in path.enumerated() {
            if i > 0 {
                guard let parent = found, parent.body.children.indices.contains(step.slot) else { return nil }
                list = parent.body.children[step.slot]
            }
            guard list.indices.contains(step.index) else { return nil }
            found = list[step.index]
        }
        return found
    }

    static func path(of id: UUID, in blocks: [Block], prefix: [BlockStep] = [], slot: Int = 0) -> [BlockStep]? {
        for (i, b) in blocks.enumerated() {
            let p = prefix + [BlockStep(slot: slot, index: i)]
            if b.id == id { return p }
            for (s, child) in b.body.children.enumerated() {
                if let found = path(of: id, in: child, prefix: p, slot: s) { return found }
            }
        }
        return nil
    }

    static func block(_ id: UUID, in blocks: [Block]) -> Block? {
        path(of: id, in: blocks).flatMap { block(at: $0, in: blocks) }
    }

    /// Le bloc `id` est dans le sous-arbre de `b` (lui compris).
    static func subtree(_ b: Block, contains id: UUID) -> Bool {
        b.id == id || b.body.children.joined().contains { subtree($0, contains: id) }
    }

    // MARK: Modifications

    /// Applique `f` à une liste de l'arbre : la liste `slot` du conteneur `container` (vide : la racine).
    @discardableResult
    static func withList<R>(_ blocks: inout [Block], container: [BlockStep], slot: Int, _ f: (inout [Block]) -> R) -> R? {
        if container.isEmpty { return slot == 0 ? f(&blocks) : nil }
        return descend(&blocks, path: container[...], slot: slot, f)
    }

    private static func descend<R>(_ list: inout [Block], path: ArraySlice<BlockStep>, slot: Int,
                                   _ f: (inout [Block]) -> R) -> R? {
        guard let step = path.first else { return f(&list) }
        guard list.indices.contains(step.index) else { return nil }
        let rest = path.dropFirst()
        let childSlot = rest.first?.slot ?? slot
        var lists = list[step.index].body.children
        guard lists.indices.contains(childSlot) else { return nil }
        let result = descend(&lists[childSlot], path: rest, slot: slot, f)
        list[step.index].body = list[step.index].body.replacingChildren(lists)
        return result
    }

    @discardableResult
    static func update(_ blocks: inout [Block], id: UUID, _ change: (inout Block) -> Void) -> Bool {
        guard let p = path(of: id, in: blocks), let last = p.last else { return false }
        return withList(&blocks, container: Array(p.dropLast()), slot: last.slot) { list in change(&list[last.index]) } != nil
    }

    /// Retire un bloc (et ce qu'il contient) ; renvoie le bloc et sa place.
    @discardableResult
    static func remove(_ blocks: inout [Block], id: UUID) -> (block: Block, at: InsertionPoint)? {
        guard let p = path(of: id, in: blocks), let last = p.last else { return nil }
        let point = InsertionPoint(container: Array(p.dropLast()), slot: last.slot, index: last.index)
        guard let removed = withList(&blocks, container: point.container, slot: point.slot, { $0.remove(at: last.index) }) else {
            return nil
        }
        return (removed, point)
    }

    @discardableResult
    static func insert(_ new: Block, into blocks: inout [Block], at point: InsertionPoint) -> Bool {
        withList(&blocks, container: point.container, slot: point.slot) { list in
            list.insert(new, at: min(max(point.index, 0), list.count))
        } != nil
    }

    /// Déplace un bloc (avec ce qu'il contient). Refusé : dans lui-même, ou au-delà de l'imbrication permise.
    @discardableResult
    static func move(_ blocks: inout [Block], id: UUID, to target: MoveTarget) -> Bool {
        guard let source = block(id, in: blocks) else { return false }
        switch target {
        case .before(let other): if subtree(source, contains: other) { return false }
        case .end(let container, _): if subtree(source, contains: container) { return false }
        case .rootEnd: break
        }
        var copy = blocks
        guard let removed = remove(&copy, id: id) else { return false }
        let point: InsertionPoint
        switch target {
        case .before(let other):
            guard let p = path(of: other, in: copy), let last = p.last else { return false }
            point = InsertionPoint(container: Array(p.dropLast()), slot: last.slot, index: last.index)
        case .end(let container, let slot):
            guard let p = path(of: container, in: copy), let c = block(at: p, in: copy),
                  c.body.children.indices.contains(slot) else { return false }
            point = InsertionPoint(container: p, slot: slot, index: c.body.children[slot].count)
        case .rootEnd:
            point = .rootEnd(copy)
        }
        guard insert(removed.block, into: &copy, at: point),
              MacroValidation.depth(copy) <= MacroValidation.maxDepth else { return false }
        blocks = copy
        return true
    }

    /// Place d'insertion « sous la sélection » : après le bloc choisi (même niveau), à la fin d'une liste si une
    /// ligne de fin est choisie, sinon tout en bas.
    static func insertionPoint(after row: MacroStepRow?, in blocks: [Block]) -> InsertionPoint {
        guard let row, let p = path(of: row.blockID, in: blocks), let last = p.last else { return .rootEnd(blocks) }
        switch row.kind {
        case .block:
            return InsertionPoint(container: Array(p.dropLast()), slot: last.slot, index: last.index + 1)
        case .end(let slot):
            let count = block(at: p, in: blocks)?.body.children.dropFirst(slot).first?.count ?? 0
            return InsertionPoint(container: p, slot: slot, index: count)
        }
    }

    /// Profondeur d'imbrication d'une place d'insertion (0 : racine).
    static func depth(of point: InsertionPoint) -> Int { point.container.count }

    // MARK: Projection à plat

    /// Lignes de la liste. `context` : validation stricte de la bibliothèque (chemin de chaque bloc posé ici).
    static func rows(_ blocks: [Block], layout: KeyboardLayout, context: ValidationContext,
                     learnedInput: Bool) -> [MacroStepRow] {
        var out: [MacroStepRow] = []
        out.reserveCapacity(blocks.count + 4)
        func walk(_ list: [Block], prefix: String, offset: Int, depth: Int, parentEnabled: Bool) {
            for (i, b) in list.enumerated() {
                let number = MacroValidation.path(prefix, offset + i + 1)
                let enabled = parentEnabled && b.enabled
                var ctx = context
                ctx.path = number
                out.append(row(b, number: number, depth: depth, enabled: enabled, context: ctx, layout: layout,
                               learnedInput: learnedInput))
                let lists = MacroValidation.childLists(b.body)
                for (slot, entry) in lists.enumerated() {
                    walk(entry.blocks, prefix: number, offset: entry.start, depth: depth + 1, parentEnabled: enabled)
                    out.append(endRow(b, slot: slot, slots: lists.count, depth: depth, enabled: enabled))
                }
            }
        }
        walk(blocks, prefix: "", offset: 0, depth: 0, parentEnabled: true)
        return out
    }

    private static func row(_ b: Block, number: String, depth: Int, enabled: Bool, context: ValidationContext,
                            layout: KeyboardLayout, learnedInput: Bool) -> MacroStepRow {
        let spec = b.body.type.map(BlockRegistry.spec)
        let phrase = self.phrase(b.body, layout: layout)
        var problem: String?
        if let spec {
            problem = spec.valider(b.body, context)
            if problem == nil, let note = b.note, note.count > MacroValidation.maxNoteLength {
                problem = context.fail("note trop longue.")
            }
        } else {
            problem = context.fail("bloc d'une version plus récente de FL Shortcut : la macro est bloquée.")
        }
        return MacroStepRow(id: MacroStepRow.blockRowID(b.id), blockID: b.id, kind: .block, number: number, depth: depth,
                       type: b.body.type, category: spec?.category, symbol: spec?.symbol ?? "questionmark.square.dashed",
                       verb: phrase.verb, value: phrase.value,
                       note: b.note.flatMap { $0.isEmpty ? nil : $0.displaySafe(max: 120) },
                       enabled: enabled, ownEnabled: b.enabled,
                       badges: badges(b, problem: problem.map(stripPath), learnedInput: learnedInput),
                       isContainer: !b.body.children.isEmpty)
    }

    private static func endRow(_ b: Block, slot: Int, slots: Int, depth: Int, enabled: Bool) -> MacroStepRow {
        let verb: String
        if case .ifElse = b.body {
            verb = slot == 0 ? "Sinon" : "Fin du « Si »"
        } else {
            verb = "Fin de la boucle"
        }
        return MacroStepRow(id: "e\(slot):" + b.id.uuidString, blockID: b.id, kind: .end(slot: slot), number: "",
                       depth: depth, type: nil, category: b.body.type.map { BlockRegistry.spec($0).category },
                       symbol: slot + 1 < slots ? "arrow.turn.down.right" : "arrow.turn.left.up", verb: verb,
                       value: nil, note: nil, enabled: enabled, ownEnabled: true, badges: [], isContainer: false)
    }

    /// « Étape 3.2 : position invalide. » → « Position invalide. »
    static func stripPath(_ message: String) -> String {
        guard message.hasPrefix("Étape "), let colon = message.range(of: " : ") else { return message }
        let rest = message[colon.upperBound...]
        return rest.prefix(1).uppercased() + rest.dropFirst()
    }

    static func badges(_ b: Block, problem: String?, learnedInput: Bool) -> [MacroBadge] {
        var out: [MacroBadge] = []
        switch b.body {
        case .click(.toLearn, _):
            out.append(.aApprendre("Position à montrer dans FL : choisis le bloc puis « Montrer dans FL… »."))
        default:
            if let problem { out.append(.probleme(problem)) }
        }
        switch b.body {
        case .delay: out.append(.pauseFixe)
        case .flAction(_, .none): out.append(.lienFL)
        case .selectInput where !learnedInput:
            out.append(.aApprendre("L'entrée « 1 » est montrée une seule fois, pendant la macro : une bulle te le demande."))
        default: break
        }
        if b.onFailure == .keepGoing { out.append(.continueSiEchec) }
        return out
    }

    // MARK: Phrases

    static func seconds(_ ms: Int) -> String {
        ms % 1000 == 0 ? "\(ms / 1000) s"
                       : String(format: "%.1f s", Double(ms) / 1000).replacingOccurrences(of: ".", with: ",")
    }

    static func duration(_ ms: Int) -> String { ms < 1000 ? "\(ms) ms" : seconds(ms) }

    private static func times(_ n: Int) -> String { n > 1 ? " × \(n)" : "" }

    private static func letters(_ l: [Character]) -> String { l.map { String($0).uppercased() }.joined(separator: " › ") }

    static func actionLabel(_ key: String) -> String {
        FLActions.id(forKey: key).flatMap { FLActions.info($0)?.label } ?? key.displaySafe(max: 20)
    }

    static func targetText(_ t: ClickTarget) -> String {
        switch t {
        case .track(let dx, let dy): return dx == 0 && dy == 0 ? "sur la piste visée" : "près de la piste visée"
        case .flWindow: return "à l'endroit appris (fenêtre de FL)"
        case .openMenu: return "à l'endroit appris (menu ouvert)"
        case .lastClick: return "près du clic précédent"
        case .startCursor: return "près du curseur"
        case .cursorXWindowY: return "dans la colonne du curseur"
        case .toLearn: return "à montrer dans FL"
        }
    }

    /// Verbe et valeur (affichée en pastille) d'une ligne : « Appuyer sur [⌘S × 2] ».
    static func phrase(_ body: BlockBody, layout: KeyboardLayout) -> (verb: String, value: String?) {
        func resumeAfter(_ prefix: String) -> String? {
            guard let type = body.type else { return nil }
            let r = BlockRegistry.spec(type).resume(body, layout)
            return r.hasPrefix(prefix) ? String(r.dropFirst(prefix.count)) : r
        }
        switch body {
        case .key(let k, let n):
            return ("Appuyer sur", k.combo.displayName(layout: layout) + times(n))
        case .menuLetters(let l, let e):
            return ("Lettres du menu", letters(l) + (e == .never ? "" : " puis Entrée"))
        case .menuKey(let k, let n):
            return ("Dans le menu", k.symbol + times(n))
        case .click(let t, let b):
            return (b == .right ? "Clic droit" : "Clic", targetText(t))
        case .delay(let ms):
            return ("Pause", duration(ms))
        case .waitWindow(let k, let ms):
            return (k == .dialog ? "Attendre une boîte de dialogue" : "Attendre un menu de FL", "\(seconds(ms)) au plus")
        case .waitWindowClose(let k, let ms):
            return (k == .dialog ? "Attendre la fermeture de la boîte" : "Attendre la fermeture du menu",
                    "\(seconds(ms)) au plus")
        case .trackMenu(let l, let labels, let target, _):
            let value = labels.isEmpty ? letters(l) : labels.map { $0.displaySafe(max: 40) }.joined(separator: " › ")
            return (target == .cursor ? "Menu de la piste sous le curseur" : "Menu de la piste", value)
        case .chooseFile(let path):
            return ("Choisir le preset", path.isEmpty ? "à choisir" : URL(fileURLWithPath: path).lastPathComponent.displaySafe(max: 40))
        case .flAction(let key, _), .flActionValue(let key, _):
            return ("Action de FL", actionLabel(key))
        case .selectInput:
            return ("Choisir l'entrée", "(none) → 1")
        case .feedbackCheck:
            return ("Vérifier le larsen", nil)
        case .menuAX(let titles, _):
            return ("Menu", titles.map { $0.displaySafe(max: 30) }.joined(separator: " › "))
        case .ifElse:
            return ("Si", resumeAfter("Si "))
        case .repeatCount(let n, _):
            return ("Répéter", "\(n) fois")
        case .repeatWhile:
            return ("Tant que", resumeAfter("Tant que "))
        case .waitUntil:
            return ("Attendre que", resumeAfter("Jusqu'à ce que "))
        case .setVariable:
            return ("Régler la variable", resumeAfter(""))
        case .stop(let message):
            return ("Arrêter la macro", message.flatMap { $0.isEmpty ? nil : $0.displaySafe(max: 60) })
        case .comment(let text):
            return (text.isEmpty ? "Commentaire" : text.displaySafe(max: 100), nil)
        case .unknown(let type, _):
            return ("Bloc inconnu", type.displaySafe(max: 30))
        }
    }

    // MARK: Macro entière

    /// Ce que montre la bibliothèque : lien FL utilisé, positions ou entrée à apprendre (blocs actifs).
    static func flags(_ blocks: [Block], learnedInput: Bool) -> (usesLink: Bool, toLearn: Bool) {
        var link = false, learn = false
        func walk(_ list: [Block]) {
            for b in list where b.enabled {
                switch b.body {
                case .flAction, .flActionValue: link = true
                case .click(.toLearn, _): learn = true
                case .selectInput: if !learnedInput { learn = true }
                default: break
                }
                b.body.children.forEach(walk)
            }
        }
        walk(blocks)
        return (link, learn)
    }

    // MARK: Clic montré dans FL

    /// Cible d'un clic montré par l'utilisateur, d'après les fenêtres de FL juste avant le clic (de l'avant vers
    /// l'arrière) : dans un menu de FL, relative à ce menu (FL le décale pour qu'il tienne à l'écran) ; dans une
    /// fenêtre normale, relative à son coin le plus proche, taille retenue (refus si elle change). Ailleurs : nil.
    static func learnedTarget(at p: CGPoint, windows: [(layer: Int, bounds: CGRect)]) -> ClickTarget? {
        guard let w = windows.first(where: { $0.bounds.contains(p) }) else { return nil }
        let b = w.bounds
        if w.layer > 8 {
            let hop = MacroSpots.PopupHop(offset: CGVector(dx: p.x - b.minX, dy: p.y - b.minY), size: b.size)
            let target = ClickTarget.openMenu(hop)
            return target.isFinite ? target : nil
        }
        guard w.layer == 0 else { return nil }
        let left = p.x - b.minX <= b.maxX - p.x
        let top = p.y - b.minY <= b.maxY - p.y
        let corner: Corner = top ? (left ? .topLeft : .topRight) : (left ? .bottomLeft : .bottomRight)
        let dx = Double(p.x - (left ? b.minX : b.maxX)), dy = Double(p.y - (top ? b.minY : b.maxY))
        let target = ClickTarget.flWindow(corner: corner, dx: dx, dy: dy, size: b.size)
        return target.isFinite ? target : nil
    }
}

// MARK: - Palette

/// Une entrée de la palette : un type de bloc avec ses réglages de départ (deux entrées peuvent partager un type :
/// « Armer la piste » et « Allumer le REC » sont des actions de FL).
struct PaletteItem: Identifiable {
    let id: String
    let type: BlockType
    let label: String
    let aide: String
    let symbol: String
    let category: BlockCategory
    /// Pas encore réglable dans le créateur (conditions : incrément suivant) : grisé, « bientôt ».
    let soon: Bool
    let make: () -> BlockBody
}

enum PaletteCatalog {
    static func items(layout: KeyboardLayout) -> [PaletteItem] {
        func item(_ id: String, _ type: BlockType, label: String? = nil, aide: String? = nil, symbol: String? = nil,
                  soon: Bool = false, _ make: @escaping () -> BlockBody) -> PaletteItem {
            let spec = BlockRegistry.spec(type)
            return PaletteItem(id: id, type: type, label: label ?? spec.label, aide: aide ?? spec.aide,
                               symbol: symbol ?? spec.symbol, category: spec.category, soon: soon, make: make)
        }
        let rec = AppMode.nativeEquivalent(of: 3, layout: layout) ?? KeyCombo(keyCode: MacroLibrary.fallbackRecKeyCode)
        let mixer = AppMode.nativeEquivalent(of: 33, layout: layout) ?? KeyCombo(keyCode: 101)
        return [
            // Clavier
            item("key", .key) { .key(KeyRef(KeyCombo(keyCode: 49), char: " "), times: 1) },
            item("menuLetters", .menuLetters) { .menuLetters(["f"], finalEnter: .never) },
            item("menuKey", .menuKey) { .menuKey(.down, times: 1) },
            // Souris
            item("clickLearned", .click, label: "Clic à un endroit appris",
                 aide: "Clic à un endroit que tu montres une fois dans FL (« Montrer dans FL… »), retrouvé ensuite par rapport à la fenêtre ou au menu de FL. Jamais hors de FL ni sous une autre app.") {
                .click(.toLearn, button: .left)
            },
            item("clickTrack", .click, label: "Clic droit sur la piste",
                 aide: "Clic droit sur la dernière piste cliquée dans le Mixer : ouvre le menu de la piste (à suivre de « Attendre un menu »).",
                 symbol: "cursorarrow.rays") {
                .click(.track(dx: 0, dy: 0), button: .right)
            },
            // Fenêtres et attentes
            item("delay", .delay) { .delay(ms: 200) },
            item("waitWindow", .waitWindow) { .waitWindow(.dialog, timeoutMs: 4_000) },
            item("waitWindowClose", .waitWindowClose) { .waitWindowClose(.dialog, timeoutMs: 8_000) },
            // FL Studio
            item("trackMenu", .trackMenu) {
                .trackMenu(letters: ["f", "o"], labels: ["File", "Open mixer track state"], target: .lastClicked,
                           finalEnter: .ifNeeded)
            },
            item("chooseFile", .chooseFile) { .chooseFile(path: "") },
            item("flAction", .flAction,
                 aide: "Une action de FL Shortcut (Mixer, Playlist, métronome…) : par le lien avec FL s'il est installé, sinon la touche équivalente de FL.") {
                .flAction(key: "mx", fallback: .key(KeyRef(mixer)))
            },
            item("arm", .flAction, label: "Armer la piste",
                 aide: "Arme la dernière piste cliquée si elle ne l'est pas : par le lien avec FL, sinon par le menu de la piste (« Arm selected track(s) », qui n'éteint jamais).",
                 symbol: "record.circle") {
                .flAction(key: "armon", fallback: .trackMenuArm)
            },
            item("rec", .flAction, label: "Allumer le REC",
                 aide: "Allume le REC s'il est éteint (lien avec FL) ; sans lien, la touche REC de FL, qui l'inverse.",
                 symbol: "record.circle.fill") {
                .flAction(key: "recon", fallback: .key(KeyRef(rec)))
            },
            item("selectInput", .selectInput) { MacroTemplates.inputOne },
            item("feedbackCheck", .feedbackCheck) { .feedbackCheck },
            // Contrôle
            item("repeat", .repeatCount) { .repeatCount(2, []) },
            item("stop", .stop) { .stop(message: nil) },
            item("comment", .comment) { .comment("Note") },
            item("if", .ifElse, soon: true) { .ifElse(.windowOpen(.dialog), then: [], otherwise: []) },
            item("while", .repeatWhile, soon: true) { .repeatWhile(.windowOpen(.menu), maxIterations: 10, []) },
            item("waitUntil", .waitUntil, soon: true) { .waitUntil(.windowOpen(.dialog), timeoutMs: 4_000) },
        ]
    }

    /// Texte sans casse ni accents (« fenetre » trouve « Fenêtres »).
    static func fold(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
    }

    /// Recherche : chaque mot doit apparaître dans le nom, l'aide ou la catégorie ; les noms qui commencent par la
    /// recherche d'abord.
    static func search(_ items: [PaletteItem], _ query: String) -> [PaletteItem] {
        let words = fold(query).split(whereSeparator: { $0 == " " }).map(String.init)
        guard !words.isEmpty else { return items }
        let hits = items.filter { item in
            let text = fold(item.label + " " + item.aide + " " + item.category.rawValue)
            return words.allSatisfy { text.contains($0) }
        }
        let first = words[0]
        return hits.filter { fold($0.label).hasPrefix(first) } + hits.filter { !fold($0.label).hasPrefix(first) }
    }
}
