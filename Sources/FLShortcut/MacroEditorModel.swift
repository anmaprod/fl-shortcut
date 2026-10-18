// Créateur de macros : son état. Créé quand le créateur s'affiche dans la fenêtre principale et libéré au retour
// (flèche ←, EditorView) ; `close()` d'abord : après, plus rien n'écrit dans la bibliothèque.
// - Au retour : macro neuve → « Enregistrer » ou « Supprimer » (vide : supprimée sans question) ; macro modifiée →
//   « Enregistrer » ou « Annuler les modifications » (retour à l'état de l'ouverture) ; sinon, retour direct.
// - Édition sur un BROUILLON : enregistré dans la bibliothèque par « Enregistrer » (⌘S) ou 0,5 s après la dernière
//   modification, jamais à chaque frappe (le Store ne recalcule l'index qu'à l'enregistrement).
// - Liste à plat recalculée en O(n) seulement après une modification (MacroOutline) ; lignes Equatable.
// - Annuler / Rétablir (⌘Z / ⇧⌘Z) par le gestionnaire d'annulation de la fenêtre ; les frappes d'un même champ
//   sont regroupées en une seule étape.
// - « Tester » : FL passe devant, puis la macro tourne par le même chemin qu'un raccourci, suivie bloc par bloc
//   (MacroRunMonitor, branché seulement pendant l'essai). Ports MIDI à la demande : annoncés au Store seulement
//   pendant l'essai. Dernière piste cliquée : suivie tant que le créateur montre une macro qui la vise (sinon
//   l'essai ne connaîtrait pas la piste cliquée avant « Tester ») ; rien une fois la fenêtre fermée.
import AppKit
import Combine
import Foundation

final class MacroEditorModel: ObservableObject {
    @Published private(set) var draft: MacroDoc?
    @Published private(set) var rows: [MacroStepRow] = []
    @Published var selection: String?
    @Published private(set) var dirty = false
    /// Ce qui empêche la macro de tourner (validation stricte de la bibliothèque), sinon nil.
    @Published private(set) var problem: String?
    @Published private(set) var estimateMs = 0
    @Published private(set) var needs: BlockNeeds = []
    /// Message court en bas de la liste (déplacement refusé, macro supprimée…).
    @Published var notice: String?
    /// Raccourci affiché : celui du raccourci relié, ou celui proposé s'il est refusé (avec ses problèmes).
    @Published private(set) var trigger: KeyCombo?
    @Published private(set) var triggerIssues: [ShortcutIssue] = []
    /// FL est en train de passer au premier plan avant un essai.
    @Published private(set) var preparingTest = false

    let monitor = MacroRunMonitor()
    weak var undoManager: UndoManager?
    weak var window: NSWindow?

    /// Macro d'exemple de la mesure de l'interface : jamais enregistrée.
    private(set) var ephemeral = false
    private let store: Store
    private var library: MacroLibraryStore { store.library }
    private let layout: KeyboardLayout
    private var pendingSave: DispatchWorkItem?
    private var lastUndoKey: String?
    private var lastUndoAt = Date.distantPast
    private var learnedInput = false
    private var terminateObserver: NSObjectProtocol?
    /// Fenêtre fermée : plus d'enregistrement ni d'essai.
    private var closed = false
    /// Essai en préparation ou en cours : tous les besoins de la macro sont annoncés.
    private var testing = false

    static let saveDelay: TimeInterval = 0.5

    /// Modèles vivants (créés moins libérés) : lu par le rapport de mesure `debug.report`, pour vérifier que la
    /// fenêtre du créateur libère bien son modèle à la fermeture.
    private static let live = Locked(0)
    static var liveCount: Int { live.value }
    /// Dernier modèle créé, jamais retenu : le rapport de mesure y lit l'ordre des blocs (genre de bloc seulement).
    private(set) static weak var newest: MacroEditorModel?

    init(store: Store = .shared) {
        MacroEditorModel.live.withLock { $0 += 1 }
        self.store = store
        layout = store.layout
        // L'app quitte pendant l'attente des 0,5 s : la dernière modification est enregistrée quand même.
        terminateObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                                                   object: nil, queue: .main) { [weak self] _ in
            self?.saveNow()
            self?.store.library.saveNow()                 // l'ordre des observateurs de la fermeture n'est pas garanti
        }
        MacroEditorModel.newest = self
    }

    deinit {
        MacroEditorModel.live.withLock { $0 -= 1 }
        if let terminateObserver { NotificationCenter.default.removeObserver(terminateObserver) }
    }

    // MARK: Lecture

    var selectedRow: MacroStepRow? { rows.first { $0.id == selection } }

    var selectedBlock: Block? {
        guard let row = selectedRow, row.kind == .block, let draft else { return nil }
        return MacroOutline.block(row.blockID, in: draft.blocks)
    }

    /// Raccourci du profil qui lance cette macro.
    var shortcut: Remap? { draft.flatMap { store.remaps(forMacro: $0.id).first } }

    var validationContext: ValidationContext {
        var ctx = ValidationContext(forbidden: store.forbidden, strictFiles: true,
                                    variables: Set(draft?.variables.map(\.name) ?? []))
        ctx.presetAnywhere = draft?.origin == .template(MacroTemplates.autoRecordID)   // même règle que la bibliothèque
        return ctx
    }

    /// Nom enregistré quand le champ est vide (la liste et le menu des macros n'affichent jamais une ligne vide).
    static let untitled = "Macro sans nom"
    /// Dernière demande d'ouverture traitée (MacroCreatorLink) : une même demande n'est jamais rejouée.
    var handledRequestSerial: Int?

    // MARK: Ouverture

    /// Ouvre une macro de la bibliothèque (la précédente est enregistrée d'abord). nil : la première, s'il y en a.
    func load(_ id: UUID?) {
        saveNow()
        ephemeral = false
        let doc = id.flatMap(library.doc) ?? library.macros.first
        open(doc)
    }

    /// Macro d'exemple, jamais enregistrée (mesure de l'interface et capture pour la relecture).
    func loadSample(_ doc: MacroDoc) {
        saveNow()
        ephemeral = true
        open(doc)
    }

    private func open(_ doc: MacroDoc?) {
        undoManager?.removeAllActions(withTarget: self)
        monitor.clear()
        notice = nil
        draft = doc
        opened = doc
        isNewMacro = false
        dirty = false
        learnedInput = MacroSpots.loadPath(.input) != nil
        refresh()
        selection = rows.first(where: { $0.kind == .block })?.id
        trigger = shortcut?.trigger
        triggerIssues = []
        refreshTriggerIssues()
    }

    /// L'entrée « 1 » vient d'être oubliée ou apprise : badges « À apprendre » à jour.
    func refreshLearnedState() {
        learnedInput = MacroSpots.loadPath(.input) != nil
        refresh()
    }

    /// Nouvelle macro vide dans la bibliothèque, ouverte aussitôt.
    func newMacro() {
        let doc = library.add(MacroDoc(name: library.uniqueName("Nouvelle macro"), blocks: []))
        load(doc.id)
        markNew()
    }

    // MARK: Retour (flèche ←)

    /// Macro telle qu'à son ouverture (« Annuler les modifications »).
    private var opened: MacroDoc?
    /// Macro créée à l'instant (nouvelle, modèle) : au retour, l'enregistrer ou la supprimer.
    private(set) var isNewMacro = false

    func markNew() { isNewMacro = true }

    enum Leave: Equatable {
        case close
        /// Macro neuve restée vide : supprimée sans question.
        case discardEmpty
        case askNew(name: String)
        case askChanges(name: String)
    }

    /// Ce que demande le retour aux raccourcis.
    func leaveCheck() -> Leave {
        guard !closed, !ephemeral, let draft else { return .close }
        if isNewMacro { return draft.blocks.isEmpty ? .discardEmpty : .askNew(name: draft.name) }
        guard let opened, opened.name != draft.name || opened.blocks != draft.blocks || opened.variables != draft.variables
        else { return .close }
        return .askChanges(name: draft.name)
    }

    /// « Supprimer » : la macro créée à l'instant quitte la bibliothèque, avec son raccourci s'il en a un.
    func discardNew() {
        guard !closed, isNewMacro, let draft else { return }
        pendingSave?.cancel()
        pendingSave = nil
        dirty = false
        for remap in store.remaps(forMacro: draft.id) { store.delete(remap.id) }
        _ = library.remove(draft.id)
    }

    /// « Annuler les modifications » : la macro revient telle qu'à son ouverture (nom, blocs, variables).
    func revertChanges() {
        guard !closed, let opened, var current = library.doc(opened.id) else { return }
        pendingSave?.cancel()
        pendingSave = nil
        dirty = false
        current.name = opened.name
        current.blocks = opened.blocks
        current.variables = opened.variables
        _ = library.update(current)
        draft = library.doc(opened.id) ?? current
        refresh()
    }

    /// Fenêtre fermée (une seule fois, les appels suivants ne font rien) : « Montrer dans FL… » annulé (son clic
    /// n'écrira rien), brouillon enregistré, essai en préparation abandonné, besoins rendus (rien au repos).
    func close() {
        guard !closed else { return }
        ClickTeacher.shared.cancel(nil)
        ClickSequenceRecorder.shared.cancel(returning: false)
        saveNow()
        closed = true
        preparingTest = false
        testing = false
        undoManager?.removeAllActions(withTarget: self)
        store.setEditorNeeds([])
    }

    // MARK: Projection

    private func refresh() {
        guard let draft else {
            rows = []
            problem = nil
            estimateMs = 0
            needs = []
            if !testing { store.setEditorNeeds([]) }
            return
        }
        let ctx = validationContext
        rows = MacroOutline.rows(draft.blocks, layout: layout, context: ctx, learnedInput: learnedInput)
        problem = MacroValidation.problem(in: draft, context: ctx)
        refreshTriggerIssues()
        estimateMs = MacroValidation.estimateMs(draft.blocks)
        needs = MacroValidation.needs(of: draft.blocks)
        if !testing { store.setEditorNeeds(openNeeds) }
        if let s = selection, !rows.contains(where: { $0.id == s }) { selection = nil }
    }

    // MARK: Modifications (annulables)

    /// Applique une modification au brouillon : annulable, liste recalculée, enregistrement dans 0,5 s.
    /// `coalesce` : même clé dans la seconde et demie = même étape d'annulation (frappes d'un champ).
    private func mutate(_ actionName: String, coalesce: String? = nil, select: String? = nil,
                        _ change: (inout MacroDoc) -> Void) {
        guard var doc = draft else { return }
        let before = doc
        let beforeSelection = selection
        change(&doc)
        guard doc != before else { return }
        let now = Date()
        if coalesce == nil || coalesce != lastUndoKey || now.timeIntervalSince(lastUndoAt) > 1.5 {
            undoManager?.registerUndo(withTarget: self) { model in
                model.restore(before, selection: beforeSelection, actionName: actionName)
            }
            undoManager?.setActionName(actionName)
        }
        lastUndoKey = coalesce
        lastUndoAt = now
        draft = doc
        if !monitor.running, monitor.outcome != nil || monitor.refusal != nil || !monitor.statuses.isEmpty {
            monitor.clear()
        }
        refresh()
        if let select { selection = select }
        markDirty()
    }

    private func restore(_ doc: MacroDoc, selection newSelection: String?, actionName: String) {
        guard let current = draft else { return }
        let currentSelection = selection
        undoManager?.registerUndo(withTarget: self) { model in
            model.restore(current, selection: currentSelection, actionName: actionName)
        }
        undoManager?.setActionName(actionName)
        lastUndoKey = nil
        draft = doc
        refresh()
        selection = newSelection
        markDirty()
    }

    func rename(_ name: String) {
        let clean = String(name.prefix(MacroValidation.maxNameLength))
        mutate("Renommer la macro", coalesce: "name") { $0.name = clean }
    }

    /// Modifie un bloc (inspecteur). `key` : champ modifié, pour regrouper les frappes.
    func updateBlock(_ id: UUID, key: String, actionName: String = "Modifier le bloc", _ change: (inout Block) -> Void) {
        mutate(actionName, coalesce: "\(id)-\(key)") { doc in
            _ = MacroOutline.update(&doc.blocks, id: id, change)
        }
    }

    func setEnabled(_ id: UUID, _ on: Bool) {
        updateBlock(id, key: "enabled", actionName: on ? "Activer le bloc" : "Désactiver le bloc") { $0.enabled = on }
    }

    /// Ajoute un bloc de la palette sous la sélection (ou dans la boucle si sa ligne de fin est choisie).
    func insert(_ item: PaletteItem) {
        guard let draft else { return }
        insert(item, at: MacroOutline.insertionPoint(after: selectedRow, in: draft.blocks))
    }

    /// Bloc glissé depuis la palette et lâché dans la liste : il prend la place de la ligne `row` (les suivantes
    /// descendent) ; lâché avant une ligne de fin : à la fin de cette boucle ; après la dernière ligne : tout en bas.
    func insert(_ item: PaletteItem, beforeRow row: Int) {
        guard let draft, let point = MacroOutline.insertionPoint(for: target(beforeRow: row), in: draft.blocks) else { return }
        insert(item, at: point)
    }

    /// Cible d'un dépôt juste avant la ligne `row` de la liste à plat (rangement des lignes, glisser de la palette).
    private func target(beforeRow row: Int) -> MoveTarget {
        guard rows.indices.contains(row) else { return .rootEnd }
        switch rows[row].kind {
        case .block: return .before(rows[row].blockID)
        case .end(let slot): return .end(container: rows[row].blockID, slot: slot)
        }
    }

    private func insert(_ item: PaletteItem, at point: InsertionPoint) {
        guard !item.soon, let draft else { return }
        let block = Block(item.make())
        // « Cliquer sur… » sans page juste au-dessus : « Ouvrir une page de FL » arrive avec lui, choisi pour qu'on
        // règle sa page d'abord.
        let page = Block(.openPage(nil))
        let withPage = MacroOutline.needsPage(block, at: point, in: draft.blocks)
        guard MacroValidation.count(draft.blocks) + (withPage ? 2 : 1) <= MacroValidation.maxBlocks else {
            notice = "Macro trop longue : \(MacroValidation.maxBlocks) blocs au plus."
            return
        }
        if !block.body.children.isEmpty || block.body.type == .repeatCount,
           MacroOutline.depth(of: point) + 1 > MacroValidation.maxDepth {
            notice = "Trop de boucles l'une dans l'autre (\(MacroValidation.maxDepth) niveaux au plus)."
            NSSound.beep()
            return
        }
        notice = nil
        mutate("Ajouter « \(item.label) »", select: MacroStepRow.blockRowID(withPage ? page.id : block.id)) { doc in
            _ = MacroOutline.insertWithPage(block, page: page, into: &doc.blocks, at: point)
        }
        if withPage {
            notice = "« Ouvrir une page de FL » ajouté juste au-dessus : choisis d'abord la page, puis l'option à cliquer dans cette page."
        }
    }

    /// « Enregistrer clics et touches » : FL passe devant, chaque clic et chaque touche de l'utilisateur deviendra
    /// un bloc (à « Terminer »).
    func recordClicks() {
        guard !closed, draft != nil, !monitor.running, !preparingTest else { return }
        guard let pid = EventTap.shared.currentConfig.flPIDs.first,
              ClickSequenceRecorder.shared.start(pid: pid, returnTo: window, completion: { [weak self] result in
                  self?.insertRecorded(result)
              }) else {
            notice = "Ouvre FL Studio, puis recommence."
            return
        }
        notice = nil
    }

    /// Blocs des clics enregistrés, dans l'ordre sous la sélection : une seule étape d'annulation.
    func insertRecorded(_ result: ClickSequenceCompiler.Result) {
        guard !closed, let draft else { return }
        let skipped = result.ignored == 0 ? ""
            : " \(result.ignored) geste\(result.ignored > 1 ? "s" : "") hors de FL (ou dans un menu refermé) ignoré\(result.ignored > 1 ? "s" : "")."
        guard !result.blocks.isEmpty else {
            notice = "Aucun clic ni aucune touche dans FL enregistrés." + skipped
            return
        }
        guard MacroValidation.count(draft.blocks) + result.blocks.count <= MacroValidation.maxBlocks else {
            notice = "Macro trop longue : \(MacroValidation.maxBlocks) blocs au plus."
            return
        }
        let blocks = result.blocks.map { Block($0) }
        var point = MacroOutline.insertionPoint(after: selectedRow, in: draft.blocks)
        mutate("Enregistrer clics et touches", select: blocks.last.map { MacroStepRow.blockRowID($0.id) }) { doc in
            for b in blocks {
                _ = MacroOutline.insert(b, into: &doc.blocks, at: point)
                point.index += 1
            }
        }
        let n = blocks.count
        notice = "\(n) bloc\(n > 1 ? "s" : "") ajouté\(n > 1 ? "s" : "") d'après tes clics et tes touches." + skipped
    }

    func duplicateSelection() {
        guard let block = selectedBlock, let draft else { return }
        guard MacroValidation.count(draft.blocks) + MacroValidation.count([block]) <= MacroValidation.maxBlocks else {
            notice = "Macro trop longue : \(MacroValidation.maxBlocks) blocs au plus."
            return
        }
        guard let copy = MacroTemplates.freshIDs([block]).first, let row = selectedRow else { return }
        let point = MacroOutline.insertionPoint(after: row, in: draft.blocks)
        mutate("Dupliquer", select: MacroStepRow.blockRowID(copy.id)) { doc in
            _ = MacroOutline.insert(copy, into: &doc.blocks, at: point)
        }
    }

    func deleteSelection() {
        guard let row = selectedRow, row.kind == .block else { return }
        let position = rows.firstIndex(of: row) ?? 0
        mutate("Supprimer le bloc") { doc in
            _ = MacroOutline.remove(&doc.blocks, id: row.blockID)
        }
        // La ligne qui prend sa place (sinon la précédente) reste choisie : ⌫ ⌫ efface de proche en proche.
        let candidates = rows.indices.contains(position) ? [rows[position]] + rows[..<position].reversed()
                                                        : Array(rows.reversed())
        selection = candidates.first(where: { $0.kind == .block })?.id
    }

    /// Glisser-déposer dans la liste à plat (`onMove`) : le bloc part avec ce qu'il contient.
    func move(fromOffsets offsets: IndexSet, toOffset to: Int) {
        guard offsets.count == 1, let from = offsets.first, rows.indices.contains(from), rows[from].kind == .block,
              to != from, to != from + 1 else { return }
        let id = rows[from].blockID
        let destination = target(beforeRow: to)
        var moved = false
        mutate("Déplacer le bloc", select: MacroStepRow.blockRowID(id)) { doc in
            moved = MacroOutline.move(&doc.blocks, id: id, to: destination)
        }
        if !moved {
            notice = "Déplacement impossible : un bloc ne va pas dans lui-même, et \(MacroValidation.maxDepth) niveaux au plus."
            NSSound.beep()
        }
    }

    // MARK: Enregistrement

    private func markDirty() {
        guard !ephemeral, !closed else { return }
        dirty = true
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveNow() }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.saveDelay, execute: work)
    }

    /// Enregistre le brouillon dans la bibliothèque (révision +1 : le Store recompile cette macro seulement).
    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        guard dirty, !ephemeral, var draft else { return }
        dirty = false
        if draft.name.trimmingCharacters(in: .whitespaces).isEmpty { draft.name = Self.untitled }
        if library.update(draft) == nil {
            notice = "Cette macro n'est plus dans la bibliothèque : tes modifications ne sont pas enregistrées."
        }
    }

    // MARK: Raccourci

    /// Choisit le raccourci de la macro (avertissements de conflit habituels). Refusé : affiché avec la raison,
    /// pas enregistré. Effacé (⌫) : le raccourci est retiré.
    func setTrigger(_ combo: KeyCombo?) {
        guard let draft, !ephemeral else { return }
        let existing = store.remaps(forMacro: draft.id)
        guard let combo else {
            for r in existing { store.delete(r.id) }
            trigger = nil
            triggerIssues = []
            return
        }
        var remap = existing.first ?? Remap(trigger: combo, macroRef: draft.id)
        remap.trigger = combo
        let issues = self.issues(for: remap)
        trigger = combo
        triggerIssues = issues
        guard !issues.contains(where: \.isBlocking) else { return }
        store.upsert(remap)
    }

    /// Problèmes du raccourci : ceux du Store (conflits, touche réservée…), sauf l'état de la macro, pris du
    /// brouillon tel qu'il est. Macro pas encore prête : le raccourci est gardé, inactif jusqu'à ce que le bloc
    /// manquant soit réglé, et le message le dit en nommant ce bloc.
    private func issues(for remap: Remap) -> [ShortcutIssue] {
        var issues = store.draftIssues(remap).filter {
            switch $0 {
            case .noTrigger, .macroInvalid: return false
            default: return true
            }
        }
        if let problem, let draft { issues.append(.macroWaiting(MacroValidation.shortcutWaiting(problem, in: draft.blocks))) }
        return issues
    }

    /// Le brouillon a changé : le message du raccourci suit (bloc réglé : il disparaît ; bloc vidé : il revient).
    private func refreshTriggerIssues() {
        guard let draft, let trigger, !ephemeral else { return }
        let remap = store.remaps(forMacro: draft.id).first ?? Remap(trigger: trigger, macroRef: draft.id)
        triggerIssues = issues(for: remap)
    }

    // MARK: Essai

    /// Besoins annoncés hors essai : la dernière piste cliquée seulement (jamais pour l'exemple de la mesure).
    private var openNeeds: BlockNeeds { closed || ephemeral ? [] : needs.intersection(.pisteVisee) }

    /// Programme du brouillon tel qu'il est (sans cache : il change à chaque modification), ou ce qui l'empêche.
    func programForTest() -> (program: MacroProgram?, problem: String?) {
        guard let draft else { return (nil, "Aucune macro ouverte.") }
        let ctx = validationContext
        if let why = MacroValidation.problem(in: draft, context: ctx) { return (nil, why) }
        return (MacroProgram(blocks: draft.blocks, name: draft.name,
                             source: .blocks(id: draft.id, revision: draft.revision),
                             variables: draft.variables, context: ctx), nil)
    }

    /// « Tester » : FL passe devant, puis la macro tourne exactement comme depuis son raccourci. Échap l'arrête.
    func test() {
        guard !closed, !monitor.running, !preparingTest else { return }
        saveNow()
        notice = nil
        let compiled = programForTest()
        guard let program = compiled.program else {
            monitor.refuse(compiled.problem ?? "Macro invalide.")
            return
        }
        guard let pid = EventTap.shared.currentConfig.flPIDs.first,
              let fl = NSRunningApplication(processIdentifier: pid) else {
            monitor.refuse("Ouvre FL Studio, puis recommence.")
            return
        }
        monitor.clear()
        preparingTest = true
        // Ports MIDI à la demande : seulement le temps de l'essai.
        testing = true
        store.setEditorNeeds(needs)
        CreatorPresence.stepAside()        // jamais un clic de l'essai sur le créateur
        fl.activate(options: [])
        waitForFL(program, pid: pid, tries: 40)
    }

    private func waitForFL(_ program: MacroProgram, pid: Int32, tries: Int) {
        guard !closed else { return }                       // fenêtre fermée pendant la préparation
        if EventTap.shared.currentConfig.frontmostPID == pid {
            // Un court instant : la fenêtre de FL finit de passer devant.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in self?.launch(program, pid: pid) }
            return
        }
        guard tries > 0 else {
            endTest()
            monitor.refuse("FL Studio n'est pas passé au premier plan : recommence.")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.waitForFL(program, pid: pid, tries: tries - 1)
        }
    }

    private func launch(_ program: MacroProgram, pid: Int32) {
        guard !closed else { return }
        preparingTest = false
        let result = monitor.start(program, pid: pid) { [weak self] _ in
            guard let self, !self.closed else { return }
            self.endTest()
            // Retour dans le créateur pour lire le résultat (FL reste tel que la macro l'a laissé).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                guard let self, !self.closed, let window = self.window else { return }
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
        }
        switch result {
        case .started: break
        case .busy:
            endTest()
            monitor.refuse("Une macro tourne déjà.")
        case .refused:
            endTest()
            monitor.refuse("FL Studio n'était plus au premier plan : recommence sans changer de fenêtre.")
        }
    }

    /// Essai fini ou abandonné : retour aux besoins hors essai.
    private func endTest() {
        preparingTest = false
        testing = false
        CreatorPresence.comeBack()
        store.setEditorNeeds(openNeeds)
    }

    /// « Montrer le bloc » du bandeau de résultat.
    func showFailedBlock() {
        guard let id = monitor.failedBlock else { return }
        selection = MacroStepRow.blockRowID(id)
    }

    /// Libellé du bandeau : « Échec au bloc 4 (Attendre une fenêtre) : … ».
    func outcomeText(_ outcome: MacroOutcome) -> String {
        switch outcome {
        case .done:
            return "Macro terminée" + (monitor.totalMs > 0 ? " en \(MacroOutline.seconds(max(monitor.totalMs / 100 * 100, 100)))" : "")
        case .doneWithWarning(let why):
            return "Macro terminée, mais \(why)"
        case .failed(let step, let reason):
            let label = draft.flatMap { MacroValidation.block(at: "\(step)", in: $0.blocks) }
                .map { " (\(BlockRegistry.label(of: $0.body)))" } ?? ""
            return "Échec au bloc \(step)\(label) : \(reason)"
        case .failedInBlock(let path, let label, let reason):
            return "Échec au bloc \(path) (\(label)) : \(reason)"
        case .stopped(let message):
            return message.map { "Arrêtée : \($0.displaySafe(max: 80))" } ?? "Arrêtée par le bloc « Arrêter la macro »"
        case .cancelled(let reason):
            return "Essai arrêté : \(reason)"
        }
    }
}
