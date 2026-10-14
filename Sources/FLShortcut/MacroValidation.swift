// Validation des macros en blocs (SEC-05) et programme compilé.
// - Règles de tout l'arbre ici (nombre de blocs, imbrication, conditions, pire durée estimée, variables), règles
//   propres à chaque bloc dans le registre (MacroRegistry.swift). Messages au format historique « Étape 3 : … ».
// - Un bloc inconnu (format plus récent) bloque la macro : elle n'est jamais exécutée sans lui.
// - MacroProgram : blocs développés et validés UNE fois sur le thread principal (Store.recompute, fiche du
//   raccourci), gardés en cache ; le thread du tap ne fait plus qu'une recherche et une mise en file.
import Foundation

enum MacroValidation {
    static let maxBlocks = 200
    static let maxDepth = 4
    static let maxConditionDepth = 3
    static let maxConditionTerms = 6
    static let maxDelayMs = 5_000
    static let maxWaitMs = 120_000
    static let maxRepeat = 50
    static let maxWhile = 100
    static let maxEstimateMs = 300_000
    static let maxNameLength = 60
    static let maxNoteLength = 120
    static let maxVariables = 8

    /// Seules clés UserDefaults qu'un bloc peut lire et écrire (jamais une clé quelconque venue d'un fichier).
    static let learnedEnterKeys: Set<String> = ["macroMenuEnterAfterLetter"]
    static let learnedPathKeys: Set<String> = ["macroSpots.v2.input"]
    /// Requêtes d'état de FL prévues (PROTOCOL.md, incrément 4).
    static let flQueries: Set<String> = ["isrec", "isplay", "track", "armed", "muted", "solo", "window", "channel",
                                         "pattern", "tempo"]

    /// Raison pour laquelle ces blocs ne peuvent pas tourner, ou nil.
    static func problem(in blocks: [Block], variables: [VariableDecl] = [], context: ValidationContext) -> String? {
        guard !blocks.isEmpty else { return "La macro est vide." }
        if let path = firstUnknown(blocks), case .unknown(let type, _)? = block(at: path, in: blocks)?.body {
            return "Étape \(path) : bloc inconnu (« \(type.displaySafe(max: 30)) »), venu d'une version plus récente de "
                + "FL Shortcut : la macro est bloquée."
        }
        guard count(blocks) <= maxBlocks else { return "Macro trop longue (\(maxBlocks) blocs au plus)." }
        guard depth(blocks) <= maxDepth else { return "Blocs trop imbriqués (\(maxDepth) niveaux au plus)." }
        guard variables.count <= maxVariables else { return "Trop de variables (\(maxVariables) au plus)." }
        var names = Set<String>()
        for v in variables {
            guard isVariableName(v.name), !names.contains(v.name) else { return "Nom de variable invalide." }
            names.insert(v.name)
        }
        var ctx = context
        ctx.variables = names
        if let why = check(blocks, prefix: "", ctx: ctx) { return why }
        guard estimateMs(blocks) <= maxEstimateMs else { return "Macro trop longue (durée totale)." }
        return nil
    }

    /// Macro de la bibliothèque : nom, format, puis ses blocs.
    static func problem(in doc: MacroDoc, context: ValidationContext) -> String? {
        guard doc.format <= 2 else { return "Macro d'une version plus récente de FL Shortcut : elle est bloquée." }
        guard !doc.name.isEmpty, doc.name.count <= maxNameLength else { return "Nom de macro invalide." }
        return problem(in: doc.blocks, variables: doc.variables, context: context)
    }

    private static func check(_ blocks: [Block], prefix: String, offset: Int = 0, ctx: ValidationContext) -> String? {
        for (i, b) in blocks.enumerated() {
            var c = ctx
            c.path = path(prefix, offset + i + 1)
            if let note = b.note, note.count > maxNoteLength { return c.fail("note trop longue.") }
            guard let type = b.body.type else { return c.fail("bloc inconnu.") }
            if let why = BlockRegistry.spec(type).valider(b.body, c) { return why }
            for (start, child) in childLists(b.body) {
                if let why = check(child, prefix: c.path, offset: start, ctx: ctx) { return why }
            }
        }
        return nil
    }

    /// Chemin d'un bloc : « 3 », puis « 3.2 » pour le 2e bloc imbriqué dans le bloc 3.
    static func path(_ prefix: String, _ number: Int) -> String { prefix.isEmpty ? "\(number)" : "\(prefix).\(number)" }

    /// Listes imbriquées avec le numéro de départ de leurs blocs : « alors » et corps commencent à 1, « sinon »
    /// poursuit la numérotation après « alors » (comme la liste à plat de l'éditeur).
    static func childLists(_ body: BlockBody) -> [(start: Int, blocks: [Block])] {
        switch body {
        case .ifElse(_, let then, let otherwise):
            return [(0, then), (then.count, otherwise)]
        case .repeatCount(_, let blocks), .repeatWhile(_, _, let blocks):
            return [(0, blocks)]
        default:
            return []
        }
    }

    static func conditionProblem(_ c: Condition, _ ctx: ValidationContext) -> String? {
        guard conditionDepth(c) <= maxConditionDepth, conditionTerms(c) <= maxConditionTerms else {
            return ctx.fail("condition trop compliquée (\(maxConditionDepth) niveaux, \(maxConditionTerms) termes au plus).")
        }
        return conditionLeaves(c).lazy.compactMap { leaf -> String? in
            switch leaf {
            case .variable(let name, _, _):
                return ctx.variables.contains(name) ? nil : ctx.fail("variable inconnue.")
            case .flState(let q, _, _):
                return flQueries.contains(q) ? nil : ctx.fail("état de FL inconnu.")
            default:
                return nil
            }
        }.first
    }

    static func sourceProblem(_ v: IntSource, _ ctx: ValidationContext) -> String? {
        switch v {
        case .constant: return nil
        case .variable(let name): return ctx.variables.contains(name) ? nil : ctx.fail("variable inconnue.")
        case .flState(let q): return flQueries.contains(q) ? nil : ctx.fail("état de FL inconnu.")
        }
    }

    static func isVariableName(_ s: String) -> Bool {
        guard let first = s.first, ("a"..."z").contains(first), s.count <= 16 else { return false }
        return s.allSatisfy { ("a"..."z").contains($0) || ("0"..."9").contains($0) || $0 == "_" }
    }

    // MARK: Mesures de l'arbre

    /// Blocs au total, imbrication comprise.
    static func count(_ blocks: [Block]) -> Int {
        blocks.reduce(0) { $0 + 1 + $1.body.children.reduce(0) { $0 + count($1) } }
    }

    /// Niveaux d'imbrication (0 : aucun bloc dans un autre).
    static func depth(_ blocks: [Block]) -> Int {
        blocks.map { b in b.body.children.map { 1 + depth($0) }.max() ?? 0 }.max() ?? 0
    }

    static func conditionDepth(_ c: Condition) -> Int {
        switch c {
        case .not(let inner): return 1 + conditionDepth(inner)
        case .all(let list), .any(let list): return 1 + (list.map(conditionDepth).max() ?? 0)
        default: return 1
        }
    }

    static func conditionTerms(_ c: Condition) -> Int { conditionLeaves(c).count }

    static func conditionLeaves(_ c: Condition) -> [Condition] {
        switch c {
        case .not(let inner): return conditionLeaves(inner)
        case .all(let list), .any(let list): return list.flatMap(conditionLeaves)
        default: return [c]
        }
    }

    /// Pire durée estimée (blocs actifs ; corps × nombre de tours ; délais d'attente), saturée.
    static func estimateMs(_ blocks: [Block]) -> Int {
        blocks.filter(\.enabled).reduce(0) { total, b in
            let (sum, overflow) = total.addingReportingOverflow(BlockRegistry.estimateMs(b.body))
            return overflow ? Int.max / 2 : min(sum, Int.max / 2)
        }
    }

    /// Produit saturé (boucles imbriquées).
    static func times(_ n: Int, _ ms: Int) -> Int {
        let (p, overflow) = n.multipliedReportingOverflow(by: ms)
        return overflow ? Int.max / 2 : min(p, Int.max / 2)
    }

    /// Besoins agrégés des blocs actifs (arbre entier).
    static func needs(of blocks: [Block]) -> BlockNeeds {
        blocks.filter(\.enabled).reduce(into: BlockNeeds()) { acc, b in
            acc.formUnion(BlockRegistry.needs(of: b.body))
            for list in b.body.children { acc.formUnion(needs(of: list)) }
        }
    }

    /// Chemin du premier bloc inconnu (« 3.2 »), nil s'il n'y en a pas.
    static func firstUnknown(_ blocks: [Block], prefix: String = "", offset: Int = 0) -> String? {
        for (i, b) in blocks.enumerated() {
            let p = path(prefix, offset + i + 1)
            if case .unknown = b.body { return p }
            for (start, child) in childLists(b.body) {
                if let found = firstUnknown(child, prefix: p, offset: start) { return found }
            }
        }
        return nil
    }

    /// Bloc désigné par un chemin (« 3.2 ») ; dans un « si », la numérotation du sinon suit celle du alors.
    static func block(at path: String, in blocks: [Block]) -> Block? {
        var list = blocks
        var found: Block?
        for part in path.split(separator: ".") {
            guard let n = Int(part), list.indices.contains(n - 1) else { return nil }
            let b = list[n - 1]
            found = b
            list = b.body.children.flatMap { $0 }
        }
        return found
    }
}

// MARK: - Programme compilé

/// Programme prêt à tourner : blocs développés et validés sur le thread principal, partagé (jamais copié ni
/// revalidé) par l'index du tap. Immuable.
final class MacroProgram: Equatable, @unchecked Sendable {
    enum Source: Hashable {
        /// Modèle « Enregistrement rapide » ou ancienne macro, portés par le raccourci (profil).
        case inline(Macro)
        /// Macro en blocs (bibliothèque, essais).
        case blocks(id: UUID, revision: Int)
    }

    let source: Source
    let name: String
    let blocks: [Block]
    let variables: [VariableDecl]
    /// Besoins agrégés des blocs actifs.
    let needs: BlockNeeds
    /// nil = prêt à tourner.
    let problem: String?

    var isRunnable: Bool { problem == nil }

    /// Titre du journal : noms des blocs du premier niveau (« trackMenu > waitDialog > … », comme avant).
    var title: String {
        blocks.filter { $0.enabled && $0.body.type != .comment }.map { BlockRegistry.journal(of: $0.body) }
            .joined(separator: " > ")
    }

    init(blocks: [Block], name: String, source: Source, variables: [VariableDecl] = [], context: ValidationContext) {
        self.source = source
        self.name = name
        self.blocks = blocks
        self.variables = variables
        needs = MacroValidation.needs(of: blocks)
        problem = MacroValidation.problem(in: blocks, variables: variables, context: context)
    }

    /// Macro qui ne peut pas être développée (positions à apprendre…).
    init(failed why: String, name: String, source: Source) {
        self.source = source
        self.name = name
        blocks = []
        variables = []
        needs = []
        problem = why
    }

    static func == (a: MacroProgram, b: MacroProgram) -> Bool {
        a === b || (a.source == b.source && a.problem == b.problem && a.blocks == b.blocks)
    }

    // MARK: Cache (clé : la macro du raccourci et la liste noire de la disposition active)

    private struct CacheKey: Hashable {
        let macro: Macro
        let forbidden: ForbiddenTargets
    }

    private static let cache = Locked<[CacheKey: MacroProgram]>([:])
    private static let cacheLimit = 64

    /// Macro d'un raccourci → programme (développé, validé), en cache : `Store.recompute` ne refait que ce qui a
    /// changé. Thread principal en général ; sûr ailleurs (verrou).
    static func compile(_ macro: Macro, forbidden: ForbiddenTargets) -> MacroProgram {
        let key = CacheKey(macro: macro, forbidden: forbidden)
        if let hit = cache.withLock({ $0[key] }) { return hit }
        let program: MacroProgram
        switch MacroLibrary.blocks(for: macro, forbidden: forbidden) {
        case .success(let blocks):
            program = MacroProgram(blocks: blocks, name: macro.name, source: .inline(macro),
                                   context: ValidationContext(forbidden: forbidden))
        case .failure(let e):
            program = MacroProgram(failed: e.message, name: macro.name, source: .inline(macro))
        }
        cache.withLock { c in
            if c.count >= cacheLimit { c.removeAll() }
            c[key] = program
        }
        return program
    }

    /// Macro de la bibliothèque (incrément 2) : règles strictes des fichiers.
    static func compile(_ doc: MacroDoc, forbidden: ForbiddenTargets) -> MacroProgram {
        let ctx = ValidationContext(forbidden: forbidden, strictFiles: true)
        if let why = MacroValidation.problem(in: doc, context: ctx) {
            return MacroProgram(failed: why, name: doc.name, source: .blocks(id: doc.id, revision: doc.revision))
        }
        return MacroProgram(blocks: doc.blocks, name: doc.name, source: .blocks(id: doc.id, revision: doc.revision),
                            variables: doc.variables, context: ctx)
    }
}
