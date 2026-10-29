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
    /// Position ou entrée à montrer dans FL.
    case aApprendre(String)
    /// Le bloc bloque la macro (message de la validation).
    case probleme(String)
    /// « Si l'étape échoue : continuer ».
    case continueSiEchec

    var title: String {
        switch self {
        case .pauseFixe: return String(localized: "Pause fixe")
        case .aApprendre: return String(localized: "À apprendre")
        case .probleme: return String(localized: "À corriger")
        case .continueSiEchec: return String(localized: "Continue si échec")
        }
    }

    var help: String {
        switch self {
        case .pauseFixe: return String(localized: "Mieux vaut attendre une boîte ou un menu de FL.")
        case .aApprendre(let why), .probleme(let why): return why
        case .continueSiEchec: return String(localized: "Si ce bloc échoue, la macro continue.")
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
        guard let removed = remove(&copy, id: id), let point = insertionPoint(for: target, in: copy),
              insert(removed.block, into: &copy, at: point),
              MacroValidation.depth(copy) <= MacroValidation.maxDepth else { return false }
        blocks = copy
        return true
    }

    /// Place d'insertion d'une cible exprimée par ids : avant un bloc (à son niveau), à la fin d'une liste d'un
    /// conteneur, ou tout en bas. Sert au rangement des lignes et au glisser depuis la palette.
    static func insertionPoint(for target: MoveTarget, in blocks: [Block]) -> InsertionPoint? {
        switch target {
        case .before(let other):
            guard let p = path(of: other, in: blocks), let last = p.last else { return nil }
            return InsertionPoint(container: Array(p.dropLast()), slot: last.slot, index: last.index)
        case .end(let container, let slot):
            guard let p = path(of: container, in: blocks), let c = block(at: p, in: blocks),
                  c.body.children.indices.contains(slot) else { return nil }
            return InsertionPoint(container: p, slot: slot, index: c.body.children[slot].count)
        case .rootEnd:
            return .rootEnd(blocks)
        }
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
        // `page` : page de FL ouverte au-dessus (« Cliquer sur… » hors de sa page est signalé sur sa ligne).
        func walk(_ list: [Block], prefix: String, offset: Int, depth: Int, parentEnabled: Bool, page inherited: FLPage?) {
            var page = inherited
            for (i, b) in list.enumerated() {
                let number = MacroValidation.path(prefix, offset + i + 1)
                let enabled = parentEnabled && b.enabled
                var ctx = context
                ctx.path = number
                var misplaced: String?
                if case .pageOption(let id?, _) = b.body, let own = PageOptions.page(of: id), own != page {
                    misplaced = PageOptions.misplacedMessage((number, page))
                }
                out.append(row(b, number: number, depth: depth, enabled: enabled, context: ctx, layout: layout,
                               learnedInput: learnedInput, misplaced: misplaced))
                let lists = MacroValidation.childLists(b.body)
                for (slot, entry) in lists.enumerated() {
                    walk(entry.blocks, prefix: number, offset: entry.start, depth: depth + 1, parentEnabled: enabled,
                         page: page)
                    out.append(endRow(b, slot: slot, slots: lists.count, depth: depth, enabled: enabled))
                }
                if case .openPage(let p) = b.body { page = p }
            }
        }
        walk(blocks, prefix: "", offset: 0, depth: 0, parentEnabled: true, page: nil)
        return out
    }

    private static func row(_ b: Block, number: String, depth: Int, enabled: Bool, context: ValidationContext,
                            layout: KeyboardLayout, learnedInput: Bool, misplaced: String? = nil) -> MacroStepRow {
        let spec = b.body.type.map(BlockRegistry.spec)
        let phrase = self.phrase(b.body, layout: layout)
        var problem: String?
        if let spec {
            problem = spec.valider(b.body, context) ?? misplaced
            if problem == nil, let note = b.note, note.count > MacroValidation.maxNoteLength {
                problem = context.fail(String(localized: "note trop longue."))
            }
        } else {
            problem = context.fail(String(localized: "bloc d'une version plus récente de FL Shortcuts : la macro est bloquée."))
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
            verb = slot == 0 ? String(localized: "Sinon") : String(localized: "Fin du « Si »")
        } else {
            verb = String(localized: "Fin de la boucle")
        }
        return MacroStepRow(id: "e\(slot):" + b.id.uuidString, blockID: b.id, kind: .end(slot: slot), number: "",
                       depth: depth, type: nil, category: b.body.type.map { BlockRegistry.spec($0).category },
                       symbol: slot + 1 < slots ? "arrow.turn.down.right" : "arrow.turn.left.up", verb: verb,
                       value: nil, note: nil, enabled: enabled, ownEnabled: true, badges: [], isContainer: false)
    }

    /// « Étape 3.2 : position invalide. » → « Position invalide. »
    static func stripPath(_ message: String) -> String {
        guard let rest = MacroValidation.splitStep(message)?.text else { return message }
        return rest.prefix(1).uppercased() + rest.dropFirst()
    }

    static func badges(_ b: Block, problem: String?, learnedInput: Bool) -> [MacroBadge] {
        var out: [MacroBadge] = []
        switch b.body {
        case .click(.toLearn, _):
            out.append(.aApprendre(String(localized: "Endroit à montrer dans FL.")))
        case .drag(.toLearn, _), .drag(_, .toLearn):
            out.append(.aApprendre(String(localized: "Glisser à montrer dans FL.")))
        default:
            if let problem { out.append(.probleme(problem)) }
        }
        switch b.body {
        case .delay: out.append(.pauseFixe)
        case .flAction("mute", .none), .pageOption("mixer.mute"?, _):
            // Sans le script : le bouton mute de la piste, montré une fois sur ce Mac.
            if !MuteSwitch.isLearned { out.append(.aApprendre(MuteSwitch.toLearn)) }
        case .flAction("solo", .none):
            break                                   // sans le script : bouton mute (clic droit) ou touche S
        // « Lien FL » retiré avec l'utilisateur : sans le lien, l'échec du bloc le dit au moment voulu.
        case .selectInput where !learnedInput:
            out.append(.aApprendre(String(localized: "Entrée « 1 » à montrer une fois.")))
        default: break
        }
        if b.onFailure == .keepGoing { out.append(.continueSiEchec) }
        return out
    }

    // MARK: Phrases

    static func seconds(_ ms: Int) -> String {
        ms % 1000 == 0 ? String(localized: "\(ms / 1000) s")
                       : String(format: "%.1f s", Double(ms) / 1000).replacingOccurrences(of: ".", with: ",")
    }

    static func duration(_ ms: Int) -> String { ms < 1000 ? String(localized: "\(ms) ms") : seconds(ms) }

    private static func times(_ n: Int) -> String { n > 1 ? " × \(n)" : "" }

    private static func letters(_ l: [Character]) -> String { l.map { String($0).uppercased() }.joined(separator: " › ") }

    static func actionLabel(_ key: String) -> String {
        FLActions.id(forKey: key).flatMap { FLActions.info($0)?.label } ?? key.displaySafe(max: 20)
    }

    static func targetText(_ t: ClickTarget) -> String {
        switch t {
        case .track(let dx, let dy):
            return dx == 0 && dy == 0 ? String(localized: "sur la piste visée") : String(localized: "près de la piste visée")
        case .flWindow(_, _, _, _, let title?): return String(localized: "à l'endroit appris (« \(title.displaySafe(max: 30)) »)")
        case .flWindow: return String(localized: "à l'endroit appris (fenêtre de FL)")
        case .openMenu: return String(localized: "à l'endroit appris (menu ouvert)")
        case .button: return String(localized: "sur le bouton retrouvé à son image")
        case .named(let spot): return String(localized: "sur « \(spot.label.displaySafe(max: 30)) »")
        case .lastClick: return String(localized: "près du clic précédent")
        case .startCursor: return String(localized: "près du curseur")
        case .cursorXWindowY: return String(localized: "dans la colonne du curseur")
        case .toLearn: return String(localized: "à montrer dans FL")
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
            return (String(localized: "Appuyer sur"), k.combo.displayName(layout: layout) + times(n))
        case .menuLetters(let l, let e):
            return (String(localized: "Lettres du menu"), letters(l) + (e == .never ? "" : String(localized: " puis Entrée")))
        case .menuKey(let k, let n):
            return (String(localized: "Dans le menu"), k.symbol + times(n))
        case .click(let t, let b):
            return (b == .right ? String(localized: "Clic droit") : String(localized: "Clic"), targetText(t))
        case .drag(.toLearn, _), .drag(_, .toLearn):
            return (String(localized: "Glisser-déposer"), String(localized: "à montrer dans FL"))
        case .drag:
            return (String(localized: "Glisser-déposer"), String(localized: "de l'endroit appris jusqu'à l'autre"))
        case .delay(let ms):
            return (String(localized: "Pause"), duration(ms))
        case .waitWindow(let k, let ms):
            return (k == .dialog ? String(localized: "Attendre une boîte de dialogue") : String(localized: "Attendre un menu de FL"),
                    String(localized: "\(seconds(ms)) au plus"))
        case .waitWindowClose(let k, let ms):
            return (k == .dialog ? String(localized: "Attendre la fermeture de la boîte") : String(localized: "Attendre la fermeture du menu"),
                    String(localized: "\(seconds(ms)) au plus"))
        case .trackMenu(let l, let labels, let target, _):
            let value = labels.isEmpty ? letters(l) : labels.map { $0.displaySafe(max: 40) }.joined(separator: " › ")
            return (target == .cursor ? String(localized: "Menu de la piste sous le curseur") : String(localized: "Menu de la piste"), value)
        case .chooseFile(let path):
            return (String(localized: "Choisir le preset"),
                    path.isEmpty ? String(localized: "à choisir") : URL(fileURLWithPath: path).lastPathComponent.displaySafe(max: 40))
        case .dropFile(let path):
            return (String(localized: "Ouvrir le preset"),
                    path.isEmpty ? String(localized: "à choisir") : URL(fileURLWithPath: path).lastPathComponent.displaySafe(max: 40))
        case .flAction(let key, _), .flActionValue(let key, _):
            return (String(localized: "Action de FL"), actionLabel(key))
        case .selectInput:
            return (String(localized: "Choisir l'entrée"), String(localized: "(none) → 1"))
        case .feedbackCheck:
            return (String(localized: "Vérifier le larsen"), nil)
        case .nameColor(let name, let color, let fade, _):
            return (String(localized: "Nom et couleur"), NameColorPayload.summary(name: name, color: color, fade: fade))
        case .soundCard:
            return (String(localized: "Carte son branchée"), String(localized: "sortie et entrée du Mac"))
        case .organize:
            return (String(localized: "Organiser"), String(localized: "range, colore, renomme le projet"))
        case .openPage(let page):
            return (String(localized: "Ouvrir une page de FL"), page?.title ?? String(localized: "à choisir"))
        case .pageOption:
            return (String(localized: "Cliquer sur"), resumeAfter(""))
        case .menuBar(let titles):
            return (String(localized: "Menu de FL"),
                    titles.isEmpty ? String(localized: "à choisir") : titles.map { $0.displaySafe(max: 30) }.joined(separator: " › "))
        case .menuAX(let titles, _):
            return (String(localized: "Menu"), titles.map { $0.displaySafe(max: 30) }.joined(separator: " › "))
        case .ifElse:
            // Préfixe tiré du même texte que le résumé du registre (« Si … ») : traduit pareil, il s'enlève pareil.
            return (String(localized: "Si"), resumeAfter(String(localized: "Si ")))
        case .repeatCount(let n, _):
            return (String(localized: "Répéter"), String(localized: "\(n) fois"))
        case .repeatWhile:
            return (String(localized: "Tant que"), resumeAfter(String(localized: "Tant que ")))
        case .waitUntil:
            return (String(localized: "Attendre que"), resumeAfter(String(localized: "Jusqu'à ce que ")))
        case .setVariable:
            return (String(localized: "Régler la variable"), resumeAfter(""))
        case .stop(let message):
            return (String(localized: "Arrêter la macro"), message.flatMap { $0.isEmpty ? nil : $0.displaySafe(max: 60) })
        case .comment(let text):
            return (text.isEmpty ? String(localized: "Commentaire") : text.displaySafe(max: 100), nil)
        case .unknown(let type, _):
            return (String(localized: "Bloc inconnu"), type.displaySafe(max: 30))
        }
    }

    // MARK: Macro entière

    /// Ce que montre la bibliothèque : lien FL utilisé, positions ou entrée à apprendre (blocs actifs).
    static func flags(_ blocks: [Block], learnedInput: Bool) -> (usesLink: Bool, toLearn: Bool) {
        var link = false, learn = false
        func walk(_ list: [Block]) {
            for b in list where b.enabled {
                switch b.body {
                case .flAction, .flActionValue, .nameColor, .openPage: link = true
                case .pageOption(let id?, _) where PageOptions.usesLink(id): link = true
                case .click(.toLearn, _), .drag(.toLearn, _), .drag(_, .toLearn): learn = true
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

    /// Glisser-déposer montré dans FL.
    enum DragShown: Equatable {
        case shown(from: ClickTarget, to: ClickTarget)
        /// Appui et relâché à moins de 4 points : un simple clic.
        case tooShort
        /// Hors des fenêtres de FL, ou dans un menu.
        case outside
    }

    /// Pure (testée) : les deux bouts d'un glisser montré, retenus comme des clics montrés (`learnedTarget`), par
    /// rapport aux fenêtres de FL d'avant l'appui ; jamais dans un menu.
    static func dragTargets(from a: CGPoint, to b: CGPoint, windows: [(layer: Int, bounds: CGRect)],
                            titles: (String?, String?) = (nil, nil)) -> DragShown {
        guard hypot(b.x - a.x, b.y - a.y) >= 4 else { return .tooShort }
        guard let from = learnedTarget(at: a, windows: windows, title: titles.0),
              let to = learnedTarget(at: b, windows: windows, title: titles.1) else { return .outside }
        if case .openMenu = from { return .outside }
        if case .openMenu = to { return .outside }
        return .shown(from: from, to: to)
    }

    /// Cible d'un clic montré par l'utilisateur, d'après les fenêtres de FL juste avant le clic (de l'avant vers
    /// l'arrière) : dans un menu de FL, relative à ce menu (FL le décale pour qu'il tienne à l'écran) ; dans une
    /// fenêtre de FL (fenêtre principale, fenêtre détachée, réglages comme Options › Audio, boîte de dialogue :
    /// niveaux 0 à 8), relative à son coin le plus proche, taille retenue (c'est elle qu'on retrouve au rejeu ; refus
    /// si elle change). Ailleurs : nil.
    /// `title` : fenêtre de plugin sous le clic (titre lu par l'Accessibilité) : retenue avec son nom, même tout en
    /// haut des niveaux (une fenêtre de plugin qui reste devant n'est pas un menu).
    static func learnedTarget(at p: CGPoint, windows: [(layer: Int, bounds: CGRect)], title: String? = nil) -> ClickTarget? {
        guard let w = windows.first(where: { $0.bounds.contains(p) }) else { return nil }
        let b = w.bounds
        if w.layer > 8, title == nil {
            let hop = MacroSpots.PopupHop(offset: CGVector(dx: p.x - b.minX, dy: p.y - b.minY), size: b.size)
            let target = ClickTarget.openMenu(hop)
            return target.isFinite ? target : nil
        }
        guard MacroEffectsMac.clickWindowLayers.contains(w.layer) || title != nil else { return nil }
        let left = p.x - b.minX <= b.maxX - p.x
        let top = p.y - b.minY <= b.maxY - p.y
        let corner: Corner = top ? (left ? .topLeft : .topRight) : (left ? .bottomLeft : .bottomRight)
        let dx = Double(p.x - (left ? b.minX : b.maxX)), dy = Double(p.y - (top ? b.minY : b.maxY))
        let target = ClickTarget.flWindow(corner: corner, dx: dx, dy: dy, size: b.size, title: title)
        return target.isFinite ? target : nil
    }
}

// MARK: - Palette

/// Une entrée de la palette : un type de bloc avec ses réglages de départ (deux entrées peuvent partager un type :
/// « Mute de la piste » et « Solo de la piste » sont des actions de FL).
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
        let mixer = AppMode.nativeEquivalent(of: 33, layout: layout) ?? KeyCombo(keyCode: 101)
        return [
            // Clavier
            // Palette triée avec l'utilisateur : seulement les blocs qui servent vraiment. Les autres types restent compris
            // (anciennes macros, modèles) mais ne sont plus proposés : lettres d'un menu (les enregistrer avec « Enregistrer clics et touches »),
            // arrêter la macro (inutile sans condition), commentaire (doublon de la note du bloc), tant que.
            item("key", .key) { .key(KeyRef(KeyCombo(keyCode: 49), char: " "), times: 1) },
            item("menuKey", .menuKey) { .menuKey(.down, times: 1) },
            // Souris
            // Un seul bloc de clic : bouton gauche ou droit, endroit montré dans FL, piste visée, près du clic précédent…
            // (l'ancien « Clic droit sur la piste » en était un doublon).
            item("clickLearned", .click, label: String(localized: "Clic à un endroit appris"),
                 aide: String(localized: "Clic gauche ou droit à un endroit que tu montres une fois dans FL.")) {
                .click(.toLearn, button: .left)
            },
            item("drag", .drag) { .drag(from: .toLearn, to: .toLearn) },
            // Fenêtres et attentes : un seul « Attendre » (boîte ou menu qui s'ouvre ou se ferme, ou temps fixe), réglé
            // dans l'inspecteur. Les clics appris attendent déjà leur fenêtre tout seuls.
            // Icône : une horloge (28/10, « revois son logo »).
            item("wait", .waitWindow, label: String(localized: "Attendre"),
                 aide: String(localized: "Attend une boîte ou un menu de FL, ou fait une pause."),
                 symbol: "clock") {
                .waitWindow(.dialog, timeoutMs: 4_000)
            },
            // FL Studio. En tête, les menus de FL (File, Edit, Tools…) parcourus comme dans FL, jusqu'à l'élément
            // voulu (demandé par l'utilisateur : File › Export › … ; au-dessus de « Ouvrir une page de FL »).
            item("menuBar", .menuBar) { .menuBar(titles: []) },
            item("openPage", .openPage) { .openPage(nil) },
            item("pageOption", .pageOption) { .pageOption(id: nil, name: "") },
            // « Menu de la piste » retiré avec l'utilisateur : outil technique (clic droit sur la piste, puis une ligne
            // du menu), que « Cliquer sur… » et « Enregistrer clics et touches » remplacent. Toujours compris.
            // « Ouvrir un preset (boîte Open) » retiré avec l'utilisateur : « Ouvrir un preset » (le fichier déposé sur
            // la piste, ancien « Déposer un preset ») fait la même chose, plus vite ; toujours compris dans les anciennes
            // macros.
            item("dropFile", .dropFile) { .dropFile(path: "") },
            item("flAction", .flAction) {
                .flAction(key: "mx", fallback: .key(KeyRef(mixer)))
            },
            // Armer la piste, allumer le REC, choisir l'entrée 1 et vérifier le larsen : retirés avec l'utilisateur
            // (l'enregistrement rapide sera refait) ; toujours compris dans les anciennes macros.
            // « Mute de la piste » et « Solo de la piste » retirés le 29/10 (demande du propriétaire) : toujours compris
            // dans les anciennes macros.
            item("nameColor", .nameColor) { .nameColor(name: nil, color: NameColorPayload.defaultColor) },
            item("soundCard", .soundCard) { .soundCard },
            item("organize", .organize) { .organize },
            // Contrôle (Répéter, Si… sinon) retiré de la palette le 28/10 (« supprime l'option contrôle ») : toujours
            // compris dans les anciennes macros.
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
            let text = fold(item.label + " " + item.aide + " " + item.category.label)
            return words.allSatisfy { text.contains($0) }
        }
        let first = words[0]
        return hits.filter { fold($0.label).hasPrefix(first) } + hits.filter { !fold($0.label).hasPrefix(first) }
    }
}
