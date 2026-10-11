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
        didSet { recompute(); scheduleSave() }
    }
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
    @Published var loadWarning: String? = nil
    @Published private(set) var saveError: String? = nil
    @Published private(set) var toggleCombo = KeyCombo(keyCode: 3, command: true, option: true, control: true)
    /// Dernier état avant un remplacement (profil, import) : permet d'annuler.
    @Published private(set) var undoSnapshot: [Remap]? = nil

    private(set) var index = ShortcutIndex()
    private(set) var forbidden = ForbiddenTargets.physical
    private(set) var conflicts = ConflictTable.empty
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
         saveDelay: TimeInterval = 0.3) {
        self.storage = storage
        self.layout = layout
        self.defaults = defaults
        self.systemHotKeys = systemHotKeys
        self.pushToTap = pushToTap
        self.saveDelay = saveDelay
        enabled = defaults.object(forKey: "enabled") as? Bool ?? true

        let loaded = Store.load(storage: storage, layout: layout)
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
    }

    static func load(storage: ProfileStorage, layout: KeyboardLayout) -> LoadResult {
        let stored: Data?
        do {
            stored = try storage.read()
        } catch {
            return LoadResult(remaps: ProfilePreset.recommended.remaps(layout: layout),
                              warning: "Profil inaccessible (\(error.localizedDescription)). Profil recommandé chargé.",
                              needsSave: false)
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
                    notes.append("Copie de l'ancien profil : \(name).")
                    needsSave = true                     // migration vers v2, original conservé
                }
            }
            if decoded.dropped > 0 { notes.append("\(decoded.dropped) raccourci(s) illisible(s) ignoré(s).") }
            let unknown = decoded.remaps.filter { $0.kind == .flAction && $0.actionID == nil }.count
            if unknown > 0 { notes.append("\(unknown) raccourci(s) avec une action inconnue, désactivé(s).") }
            return LoadResult(remaps: decoded.remaps, warning: notes.isEmpty ? nil : notes.joined(separator: " "),
                              needsSave: needsSave)
        } catch {
            let name = try? storage.backup(data, label: "illisible")
            let where_ = name.map { " Une copie a été gardée (\($0))." } ?? ""
            return LoadResult(remaps: ProfilePreset.recommended.remaps(layout: layout),
                              warning: "Profil illisible : profil recommandé chargé.\(where_)", needsSave: false)
        }
    }

    // MARK: Analyse et configuration du tap

    func issues(for id: UUID) -> [ShortcutIssue] { issues[id] ?? [] }

    func recompute() {
        let ctx = AnalysisContext(toggle: toggleCombo, forbidden: forbidden, conflicts: conflicts,
                                  availability: availability)
        let found = ShortcutAnalyzer.analyze(remaps, context: ctx)
        if found != issues { issues = found }
        index = ShortcutIndex(remaps: remaps, blocked: ShortcutAnalyzer.blocked(found))
        pushConfig()
        if pushToTap {
            // « La piste sur laquelle j'ai cliqué » : suivie seulement s'il existe une macro automatique active.
            let auto = remaps.filter { $0.enabled && $0.macro?.template == .autoRecord }
            TrackMemory.shared.setActive(!auto.isEmpty)
            // Ports MIDI présents (sans aucun trafic) seulement si une macro arme la piste ou lance le REC.
            MIDILink.shared.setOnDemand(auto.contains { $0.macro?.armAndInput == true || $0.macro?.startRecording == true })
        }
    }

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
        let ctx = AnalysisContext(toggle: toggleCombo, forbidden: forbidden, conflicts: conflicts, availability: availability)
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
                let message = failure.map { "Enregistrement impossible : \($0)" }
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
            saveError = "Enregistrement impossible : \(error.localizedDescription)"
        }
    }
}
