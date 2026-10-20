// Audit : REL-01 (chargement tolérant, copie de secours du fichier illisible / v1 migré, défauts figés au
//         premier lancement, message non bloquant), REL-02 (écriture atomique 0600, erreur publiée),
//         REL-18 (changement de disposition : libellés, ⌃⌥⌘F, liste noire et conflits recalculés),
//         REL-20 (index et avertissements issus de la même analyse), REL-21 (écritures regroupées sur une file
//         utilitaire, vidées à la fermeture ; restauration annulable), SEC-05 (profil 0600, propriétaire vérifié,
//         import validé puis confirmé), REL-03 (configuration poussée en bloc vers le tap).
import Combine
import Foundation

/// Stockage du profil, injectable pour les tests.
protocol ProfileStorage: AnyObject {
    func read() throws -> Data?
    func write(_ data: Data) throws
    /// Copie de secours ; renvoie le nom du fichier créé.
    func backup(_ data: Data, label: String) throws -> String
}

final class FileProfileStorage: ProfileStorage {
    let url: URL

    init(url: URL = AppPaths.profileURL) { self.url = url }

    func read() throws -> Data? {
        if let perms = SecureFile.permissions(at: url.path), perms.owner != getuid() {
            throw SecureFile.Failure.notOwned(url.path)
        }
        return try SecureFile.read(url, maxBytes: 4 << 20)
    }

    func write(_ data: Data) throws {
        try SecureFile.ensureDirectory(url.deletingLastPathComponent())
        try SecureFile.writeAtomically(data, to: url, mode: 0o600)
    }

    func backup(_ data: Data, label: String) throws -> String {
        let name = "profile.\(label)-\(Int(Date().timeIntervalSince1970)).json"
        try SecureFile.ensureDirectory(url.deletingLastPathComponent())
        try SecureFile.writeAtomically(data, to: url.deletingLastPathComponent().appendingPathComponent(name), mode: 0o600)
        return name
    }
}

final class Store: ObservableObject {
    static let shared = Store()

    @Published var remaps: [Remap] {
        didSet { recompute(); scheduleSave(); onDataChange?() }
    }
    /// Après chaque changement des raccourcis ou des macros (sauvegarde en ligne du compte : AccountBackup).
    var onDataChange: (() -> Void)?
    /// Le profil n'a pas pu être lu entièrement au lancement (Store.load) : jusqu'à son remplacement par la
    /// sauvegarde du compte, il n'est jamais envoyé à la place de celle-ci.
    private(set) var loadIncomplete = false
    @Published var enabled: Bool {
        didSet {
            defaults.set(enabled, forKey: "enabled")
            pushConfig()
        }
    }
    /// Enregistrement d'un raccourci dans l'éditeur : le tap laisse tout passer (REL-19).
    @Published var recording = false {
        didSet { pushConfig() }
    }
    @Published private(set) var issues: [UUID: [ShortcutIssue]] = [:]
    // Chaque avertissement et chaque erreur d'enregistrement rejoint les derniers problèmes (message d'aide).
    @Published var loadWarning: String? = nil { didSet { if let v = loadWarning, v != oldValue { ProblemLog.shared.add(v) } } }
    @Published private(set) var saveError: String? = nil { didSet { if let v = saveError, v != oldValue { ProblemLog.shared.add(v) } } }
    @Published private(set) var toggleCombo = KeyCombo(keyCode: 3, command: true, option: true, control: true)
    /// Dernier état avant un remplacement (profil, import) : permet d'annuler.
    @Published private(set) var undoSnapshot: [Remap]? = nil

    private(set) var index = ShortcutIndex()
    private(set) var forbidden = ForbiddenTargets.physical
    private(set) var conflicts = ConflictTable.empty
    /// Bibliothèque des macros en blocs (macros.json) ; chaque changement relance `recompute`.
    let library: MacroLibraryStore
    /// Programmes de la bibliothèque compilés au dernier `recompute` (en cache par id et révision).
    private(set) var programs: [UUID: MacroProgram] = [:]
    /// Besoins agrégés des macros que les raccourcis peuvent lancer (et de l'essai en cours dans le créateur).
    private(set) var activeNeeds: BlockNeeds = []
    /// Besoins de la macro essayée dans le créateur (piste visée, lien MIDI), le temps de l'essai ; vide sinon.
    private var editorNeeds: BlockNeeds = []
    /// Disponibilité des actions (masque du script ou version de FL), fournie par AppStatus.
    var availability: (Int) -> ActionAvailability = ({ _ in .unverified }) {
        didSet { recompute() }
    }

    private let storage: ProfileStorage
    let layout: KeyboardLayout
    /// Catalogue (≈ 310 entrées) calculé une fois, recalculé seulement si la disposition clavier change.
    var catalogCache: [CatalogEntry]?
    private let defaults: UserDefaults
    private let systemHotKeys: () -> [KeyCombo: String]
    private let pushToTap: Bool
    private let saveDelay: TimeInterval
    private let saveQueue = DispatchQueue(label: "FLShortcut.profile-save", qos: .utility)
    private var pendingSave: DispatchWorkItem?
    private var layoutObserver: NSObjectProtocol?

    init(storage: ProfileStorage = FileProfileStorage(),
         layout: KeyboardLayout = SystemKeyboardLayout(),
         defaults: UserDefaults = .standard,
         systemHotKeys: @escaping () -> [KeyCombo: String] = SystemHotKeys.read,
         pushToTap: Bool = true,
         saveDelay: TimeInterval = 0.3,
         library: MacroLibraryStore? = nil) {
        self.storage = storage
        // Hors de l'app (tests) : bibliothèque en mémoire, jamais le fichier de l'utilisateur.
        self.library = library ?? (pushToTap ? MacroLibraryStore.shared
                                             : MacroLibraryStore(storage: MemoryMacroLibraryStorage(), saveDelay: 0))
        self.layout = layout
        self.defaults = defaults
        self.systemHotKeys = systemHotKeys
        self.pushToTap = pushToTap
        self.saveDelay = saveDelay
        enabled = defaults.object(forKey: "enabled") as? Bool ?? true

        let loaded = Store.load(storage: storage, layout: layout)
        loadIncomplete = loaded.incomplete
        var initial = loaded.remaps
        var needsSave = loaded.needsSave
        // Une seule fois : ancien « Enregistrement rapide » jamais réglé (armement demandé, aucune position
        // apprise : il ne pouvait pas tourner) → modèle automatique.
        if !defaults.bool(forKey: Self.autoRecordMigrationKey) {
            defaults.set(true, forKey: Self.autoRecordMigrationKey)
            for i in initial.indices where initial[i].macro?.template == .quickRecord
                && initial[i].macro?.spots.isEmpty == true && initial[i].macro?.armAndInput == true {
                initial[i].macro?.template = .autoRecord
                needsSave = true
            }
        }
        // Une seule fois : la macro d'exemple rejoint un profil existant (jamais le profil « Vide », jamais à la
        // place d'une touche déjà prise). Ajoutée avant la publication du profil : une seule écriture.
        if !defaults.bool(forKey: Self.exampleMacroKey) {
            defaults.set(true, forKey: Self.exampleMacroKey)
            let example = ProfilePreset.exampleMacro(layout: layout)
            if !initial.isEmpty, !initial.contains(where: { $0.kind == .macro }),
               !initial.contains(where: { $0.trigger == example.trigger }) {
                initial.append(example)
                needsSave = true
            }
        }
        remaps = initial
        loadWarning = loaded.warning
        self.library.onChange = { [weak self] in
            self?.recompute()
            self?.onDataChange?()
        }
        refreshLayoutDependentState()
        if needsSave { saveNow() }

        if pushToTap {
            layoutObserver = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name("com.apple.Carbon.TISNotifySelectedKeyboardInputSourceChanged"),
                object: nil, queue: .main) { [weak self] _ in
                    self?.refreshLayoutDependentState()
                    self?.objectWillChange.send()
                }
        }
    }

    deinit {
        if let layoutObserver { DistributedNotificationCenter.default().removeObserver(layoutObserver) }
    }

    // MARK: Chargement

    static let exampleMacroKey = "exampleMacroAdded"
    static let autoRecordMigrationKey = "autoRecordMigrated"

    struct LoadResult {
        var remaps: [Remap]
        var warning: String?
        var needsSave: Bool
        /// Profil illisible, inaccessible ou en partie illisible : ce qui est chargé n'est pas ce que l'utilisateur
        /// avait (la sauvegarde en ligne ne doit pas l'envoyer à la place de la bonne).
        var incomplete = false
    }

    static func load(storage: ProfileStorage, layout: KeyboardLayout) -> LoadResult {
        let stored: Data?
        do {
            stored = try storage.read()
        } catch {
            return LoadResult(remaps: ProfilePreset.recommended.remaps(layout: layout),
                              warning: String(localized: "Profil inaccessible (\(error.localizedDescription)). Profil recommandé chargé."),
                              needsSave: false, incomplete: true)
        }
        // Nom distinct : `guard let data` dans la portée d'une constante locale `data` ne compile pas.
        guard let data = stored else {
            // Premier lancement : on fige tout de suite les défauts de la disposition du moment.
            return LoadResult(remaps: ProfilePreset.recommended.remaps(layout: layout), warning: nil, needsSave: true)
        }
        do {
            let decoded = try ProfileCodec.decode(data)
            var notes: [String] = []
            var needsSave = false
            if decoded.dropped > 0 || decoded.sourceVersion < ProfileCodec.currentVersion {
                let label = decoded.sourceVersion < ProfileCodec.currentVersion ? "v1" : "partiel"
                if let name = try? storage.backup(data, label: label) {
                    notes.append(String(localized: "Copie de l'ancien profil : \(name)."))
                    needsSave = true                     // migration vers v2, original conservé
                }
            }
            if decoded.dropped > 0 { notes.append(String(localized: "\(decoded.dropped) raccourci(s) illisible(s) ignoré(s).")) }
            let unknown = decoded.remaps.filter { $0.kind == .flAction && $0.actionID == nil }.count
            if unknown > 0 { notes.append(String(localized: "\(unknown) raccourci(s) avec une action inconnue, désactivé(s).")) }
            return LoadResult(remaps: decoded.remaps, warning: notes.isEmpty ? nil : notes.joined(separator: " "),
                              needsSave: needsSave, incomplete: decoded.dropped > 0)
        } catch {
            let name = try? storage.backup(data, label: "illisible")
            let where_ = name.map { String(localized: " Une copie a été gardée (\($0)).") } ?? ""
            return LoadResult(remaps: ProfilePreset.recommended.remaps(layout: layout),
                              warning: String(localized: "Profil illisible : profil recommandé chargé.\(where_)"), needsSave: false,
                              incomplete: true)
        }
    }

    // MARK: Analyse et configuration du tap

    func issues(for id: UUID) -> [ShortcutIssue] { issues[id] ?? [] }

    func recompute() {
        // Thread principal : programmes de la bibliothèque compilés ici (seulement ceux qui ont changé), jamais
        // dans le thread du tap.
        programs = library.programs(forbidden: forbidden)
        let ctx = AnalysisContext(toggle: toggleCombo, forbidden: forbidden, conflicts: conflicts,
                                  availability: availability, programs: programs)
        let found = ShortcutAnalyzer.analyze(remaps, context: ctx)
        if found != issues { issues = found }
        index = ShortcutIndex(remaps: remaps, blocked: ShortcutAnalyzer.blocked(found), forbidden: forbidden,
                              programs: programs)
        pushConfig()
        // Besoins des macros que les raccourcis peuvent vraiment lancer (et de celle essayée dans le créateur).
        activeNeeds = index.macroPrograms.reduce(editorNeeds) { $0.union($1.needs) }
        if pushToTap {
            // « La piste sur laquelle j'ai cliqué » : suivie seulement si une macro vise la dernière piste cliquée.
            TrackMemory.shared.setActive(activeNeeds.contains(.pisteVisee))
            // Ports MIDI présents (sans aucun trafic) dès que le lien avec FL est installé : FL les trouve en démarrant et
            // y relie son script tout seul (Controller type, Port), sans réglage à faire.
            MIDILink.shared.setOnDemand(true)
        }
    }

    /// « Tester » dans le créateur annonce les besoins de sa macro le temps de l'essai (vide à la fin de l'essai et à
    /// la fermeture) : ouvrir le créateur ne crée aucun port MIDI.
    func setEditorNeeds(_ needs: BlockNeeds) {
        guard needs != editorNeeds else { return }
        editorNeeds = needs
        recompute()
    }

    /// Raccourcis qui lancent cette macro de la bibliothèque.
    func remaps(forMacro id: UUID) -> [Remap] { remaps.filter { $0.kind == .macro && $0.macroRef == id } }

    private func refreshLayoutDependentState() {
        catalogCache = nil
        toggleCombo = KeyCombo(keyCode: KeyNames.keyCode(for: "f", layout: layout) ?? 3,
                               command: true, option: true, control: true)
        forbidden = ForbiddenTargets.make(layout: layout)
        conflicts = ConflictTable.make(layout: layout, systemHotKeys: systemHotKeys())
        recompute()
    }

    private func pushConfig() {
        guard pushToTap else { return }
        let snapshot = (enabled, index, toggleCombo, forbidden, recording)
        let natives = AppMode.actionNatives(layout: layout)
        let light = AppMode.light
        EventTap.shared.updateConfig {
            $0.enabled = snapshot.0
            $0.index = snapshot.1
            $0.toggle = snapshot.2
            $0.forbidden = snapshot.3
            $0.recording = snapshot.4
            $0.actionNatives = natives
            $0.anyContext = light
        }
    }

    // MARK: Édition

    func add() { remaps.append(Remap()) }

    /// Ajoute ou remplace un raccourci (fiche d'édition).
    func upsert(_ remap: Remap) {
        if let i = remaps.firstIndex(where: { $0.id == remap.id }) { remaps[i] = remap } else { remaps.append(remap) }
    }

    /// Problèmes d'un brouillon, analysé après les autres raccourcis (un doublon est signalé sur lui), avec
    /// exactement les mêmes règles que l'index du tap (REL-20).
    func draftIssues(_ draft: Remap) -> [ShortcutIssue] {
        var list = remaps.filter { $0.id != draft.id }
        var probe = draft
        probe.enabled = true
        list.append(probe)
        let ctx = AnalysisContext(toggle: toggleCombo, forbidden: forbidden, conflicts: conflicts, availability: availability,
                                  programs: programs)
        return ShortcutAnalyzer.analyze(list, context: ctx)[draft.id] ?? []
    }

    func delete(_ id: UUID) { remaps.removeAll { $0.id == id } }

    func apply(preset: ProfilePreset) {
        undoSnapshot = remaps
        remaps = preset.remaps(layout: layout)
    }

    func undoReplace() {
        guard let previous = undoSnapshot else { return }
        undoSnapshot = nil
        remaps = previous
    }

    /// Raison du refus d'une cible « Touche de FL », ou `nil`.
    func forbiddenReason(_ combo: KeyCombo) -> String? { forbidden.reason(for: combo) }

    // MARK: Import / export

    func exportData() throws -> Data { try ProfileCodec.encode(remaps) }

    func prepareImport(_ data: Data) throws -> ImportPreview {
        try ProfileImporter.prepare(data, forbidden: forbidden, layout: layout)
    }

    func applyImport(_ preview: ImportPreview) {
        undoSnapshot = remaps
        remaps = preview.remaps
    }

    // MARK: Sauvegarde en ligne (AccountBackup)

    /// Remplace raccourcis et macros d'un coup (sauvegarde du compte reprise, déconnexion), écrits tout de suite ;
    /// pas d'« Annuler » vers l'état d'avant.
    func replaceAll(_ new: [Remap], macros: [MacroDoc]) {
        undoSnapshot = nil
        loadIncomplete = false
        library.replaceAll(macros)
        remaps = new
        saveNow()
        library.saveNow()
    }

    /// Raccourcis du premier lancement (profil recommandé, macro d'exemple comprise), sans aucune macro en blocs :
    /// ce que la déconnexion laisse sur le Mac.
    func freshRemaps() -> [Remap] { ProfilePreset.recommended.remaps(layout: layout) }

    /// Rien de personnel sur ce Mac : raccourcis du premier lancement et aucune macro en blocs (identifiants mis à
    /// part, ils changent à chaque création).
    var isUntouched: Bool {
        library.macros.isEmpty && Self.withoutIDs(remaps) == Self.withoutIDs(freshRemaps())
    }

    /// Profil encodé sans ses identifiants (UUID), pour comparer deux profils de même contenu.
    static func withoutIDs(_ remaps: [Remap]) -> String {
        let text = (try? ProfileCodec.encode(remaps)).map { String(decoding: $0, as: UTF8.self) } ?? ""
        return text.replacingOccurrences(of: "[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}",
                                         with: "-", options: .regularExpression)
    }

    /// Copie datée du profil dans Application Support (avant de le remplacer par la sauvegarde du compte).
    @discardableResult
    func keepCopy(label: String) -> String? {
        (try? ProfileCodec.encode(remaps)).flatMap { try? storage.backup($0, label: label) }
    }

    // MARK: Sauvegarde

    private func scheduleSave() {
        pendingSave?.cancel()
        let snapshot = remaps
        let storage = self.storage
        let work = DispatchWorkItem { [weak self] in
            var failure: String?
            do {
                try storage.write(ProfileCodec.encode(snapshot))
            } catch {
                failure = error.localizedDescription
            }
            DispatchQueue.main.async {
                guard let self else { return }
                let message = failure.map { String(localized: "Enregistrement impossible : \($0)") }
                if self.saveError != message { self.saveError = message }   // pas de publication inutile
            }
        }
        pendingSave = work
        saveQueue.asyncAfter(deadline: .now() + saveDelay, execute: work)
    }

    /// Écriture immédiate (fermeture de l'appli, premier lancement).
    func saveNow() {
        pendingSave?.cancel()
        pendingSave = nil
        saveQueue.sync {}                              // attend une écriture déjà commencée
        do {
            try storage.write(ProfileCodec.encode(remaps))
            saveError = nil
        } catch {
            saveError = String(localized: "Enregistrement impossible : \(error.localizedDescription)")
        }
    }
}
