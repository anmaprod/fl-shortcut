// Bibliothèque des macros en blocs : `Application Support/FL Shortcuts/macros.json`, à part du profil.
// - Pourquoi à part : une ancienne version de l'app qui relit le profil y verrait une macro inconnue et la perdrait à
//   la réécriture ; elle ne touche jamais ce fichier. Le raccourci garde seulement une référence (`Remap.macroRef`,
//   doublée d'un lien caché dans `unknownAction` que les anciennes versions conservent).
// - Écriture atomique en 0600 (SecureFile : fichier temporaire, fsync, rename), regroupée sur une file utilitaire ;
//   copie « macros.precedente.json » une fois par lancement avant la première écriture ; fichier illisible, plus
//   récent ou en partie illisible : copie datée gardée, jamais écrasé sans copie. Fichier inaccessible, ou copie de
//   secours impossible : plus jamais réécrit pendant ce lancement, et `problem` le dit (menu, page Macros, créateur).
// - Programmes compilés (développés et validés) sur le thread principal, en cache par (id, révision) : un changement
//   ne recompile que la macro modifiée. Rien ne tourne au repos.
import Combine
import Foundation

/// Stockage de la bibliothèque, injectable pour les tests.
protocol MacroLibraryStorage: AnyObject {
    func read() throws -> Data?
    func write(_ data: Data) throws
    /// Copie de secours ; renvoie le nom du fichier créé.
    func backup(_ data: Data, label: String) throws -> String
}

final class FileMacroLibraryStorage: MacroLibraryStorage {
    let url: URL

    init(url: URL = AppPaths.macrosURL) { self.url = url }

    func read() throws -> Data? {
        if let perms = SecureFile.permissions(at: url.path), perms.owner != getuid() {
            throw SecureFile.Failure.notOwned(url.path)
        }
        return try SecureFile.read(url, maxBytes: MacroLibraryCodec.maxBytes)
    }

    func write(_ data: Data) throws {
        try SecureFile.ensureDirectory(url.deletingLastPathComponent())
        try SecureFile.writeAtomically(data, to: url, mode: 0o600)
    }

    func backup(_ data: Data, label: String) throws -> String {
        // La copie « précédente » est unique (remplacée à chaque lancement) ; les autres sont datées.
        let name = label == MacroLibraryStore.previousLabel
            ? "macros.\(label).json" : "macros.\(label)-\(Int(Date().timeIntervalSince1970)).json"
        let dir = url.deletingLastPathComponent()
        try SecureFile.ensureDirectory(dir)
        try SecureFile.writeAtomically(data, to: dir.appendingPathComponent(name), mode: 0o600)
        return name
    }
}

/// Stockage en mémoire (tests, et bibliothèque d'un Store de test).
final class MemoryMacroLibraryStorage: MacroLibraryStorage {
    var data: Data?
    var writes = 0
    var backups: [String: Data] = [:]
    var readError: Error?
    var writeError: Error?
    var backupError: Error?

    init(data: Data? = nil) { self.data = data }

    func read() throws -> Data? {
        if let readError { throw readError }
        return data
    }

    func write(_ d: Data) throws {
        if let writeError { throw writeError }
        writes += 1
        data = d
    }

    func backup(_ d: Data, label: String) throws -> String {
        if let backupError { throw backupError }
        let name = "macros.\(label).json"
        backups[name] = d
        return name
    }
}

/// Format du fichier : { "version": 1, "macros": [ … ] }. Décodage tolérant macro par macro (une macro illisible
/// est ignorée et comptée, un bloc inconnu est conservé tel quel et bloque sa macro).
enum MacroLibraryCodec {
    static let currentVersion = 1
    static let maxBytes = 8 << 20
    static let maxMacros = 500

    struct Decoded {
        var macros: [MacroDoc]
        var version: Int
        /// Macros illisibles ignorées.
        var dropped: Int
    }

    enum Failure: Error, LocalizedError {
        case unreadable
        case tooMany

        var errorDescription: String? {
            switch self {
            case .unreadable: return "Format de bibliothèque illisible."
            case .tooMany: return "Trop de macros (\(MacroLibraryCodec.maxMacros) au plus)."
            }
        }
    }

    private struct FileIn: Decodable {
        let version: Int?
        let macros: [Lossy<MacroDoc>]
    }

    private struct FileOut: Encodable {
        let version: Int
        let macros: [MacroDoc]
    }

    static func decode(_ data: Data) throws -> Decoded {
        guard let file = try? JSONDecoder().decode(FileIn.self, from: data) else { throw Failure.unreadable }
        guard file.macros.count <= maxMacros else { throw Failure.tooMany }
        var seen = Set<UUID>()
        var macros: [MacroDoc] = []
        for item in file.macros {
            guard var doc = item.value else { continue }
            if !seen.insert(doc.id).inserted { doc.id = UUID() }       // ids en double : ForEach indéfini
            macros.append(doc)
        }
        return Decoded(macros: macros, version: file.version ?? currentVersion, dropped: file.macros.count - macros.count)
    }

    /// `pretty` : lisible dans un éditeur (le fichier) ; sans : plus court (sauvegarde en ligne).
    static func encode(_ macros: [MacroDoc], pretty: Bool = true) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(FileOut(version: currentVersion, macros: macros))
    }
}

/// Bibliothèque des macros en blocs (thread principal). Le Store la relit à chaque changement (`onChange`).
final class MacroLibraryStore: ObservableObject {
    static let shared = MacroLibraryStore(storage: FileMacroLibraryStorage())
    /// Copie du fichier tel qu'il était au lancement, faite avant la première écriture.
    static let previousLabel = "precedente"

    @Published private(set) var macros: [MacroDoc] = []
    // Chaque avertissement et chaque erreur d'enregistrement rejoint les derniers problèmes (message d'aide).
    @Published var loadWarning: String? { didSet { if let v = loadWarning, v != oldValue { ProblemLog.shared.add(v) } } }
    @Published private(set) var saveError: String? { didSet { if let v = saveError, v != oldValue { ProblemLog.shared.add(v) } } }
    /// Appelé après chaque changement (Store.recompute : index du tap, besoins des macros).
    var onChange: (() -> Void)?

    private let storage: MacroLibraryStorage
    private let saveDelay: TimeInterval
    private let saveQueue = DispatchQueue(label: "FLShortcut.macros-save", qos: .utility)
    private var pendingSave: DispatchWorkItem?
    /// Contenu lu au lancement, copié une seule fois avant la première écriture.
    private let previousContent = Locked<Data?>(nil)
    /// Fichier présent mais inaccessible (droits, lien symbolique…), ou copie de secours impossible : jamais réécrit.
    @Published private(set) var writesDisabled = false
    private var programCache: [UUID: MacroProgram] = [:]
    private var cacheForbidden: ForbiddenTargets?

    static let writesDisabledMessage = "Tes macros ne peuvent pas être enregistrées : le fichier n'a pas pu être copié avant d'être remplacé."

    /// Ce que l'utilisateur doit savoir (menu, page Macros même vide, créateur) : jamais de macro perdue sans prévenir.
    var problem: String? {
        saveError ?? loadWarning ?? (writesDisabled ? Self.writesDisabledMessage : nil)
    }

    init(storage: MacroLibraryStorage, saveDelay: TimeInterval = 0.3) {
        self.storage = storage
        self.saveDelay = saveDelay
        load()
    }

    private func load() {
        let stored: Data?
        do {
            stored = try storage.read()
        } catch {
            writesDisabled = true
            loadWarning = "Bibliothèque de macros inaccessible (\(error.localizedDescription)) : elle n'est pas modifiée."
            return
        }
        guard let data = stored else { return }                       // aucune macro encore
        do {
            let decoded = try MacroLibraryCodec.decode(data)
            macros = decoded.macros
            previousContent.withLock { $0 = data }
            var notes: [String] = []
            if decoded.version > MacroLibraryCodec.currentVersion {
                let name = keepCopy(data, label: "plus-recente")
                notes.append("Bibliothèque d'une version plus récente de FL Shortcuts"
                             + (name.map { " (copie : \($0))." } ?? ", copie impossible : elle n'est pas modifiée."))
            }
            if decoded.dropped > 0 {
                let name = keepCopy(data, label: "partielle")
                notes.append("\(decoded.dropped) macro(s) illisible(s) ignorée(s)"
                             + (name.map { " (copie : \($0))." } ?? ", copie impossible : le fichier n'est pas modifié."))
            }
            if !notes.isEmpty { loadWarning = notes.joined(separator: " ") }
        } catch {
            if let name = keepCopy(data, label: "illisible") {
                loadWarning = "Le fichier des macros était illisible : une copie datée a été gardée dans Application Support › FL Shortcuts (\(name))."
            } else {
                loadWarning = "Le fichier des macros est illisible et n'a pas pu être copié : il n'est pas modifié, tes nouvelles macros ne seront pas enregistrées."
            }
        }
    }

    /// Copie de secours avant tout remplacement ; impossible : plus aucune écriture (jamais écrasé sans copie).
    private func keepCopy(_ data: Data, label: String) -> String? {
        if let name = try? storage.backup(data, label: label) { return name }
        writesDisabled = true
        return nil
    }

    // MARK: Lecture

    func doc(_ id: UUID) -> MacroDoc? { macros.first { $0.id == id } }

    /// « Nouvelle macro », puis « Nouvelle macro 2 »… (noms uniques, 60 caractères au plus).
    func uniqueName(_ base: String) -> String {
        let root = String(base.prefix(MacroValidation.maxNameLength - 4)).trimmingCharacters(in: .whitespaces)
        let taken = Set(macros.map(\.name))
        guard taken.contains(root) else { return root.isEmpty ? "Macro" : root }
        var n = 2
        while taken.contains("\(root) \(n)") { n += 1 }
        return "\(root) \(n)"
    }

    /// Programmes compilés (développés et validés), en cache par (id, révision) et liste noire.
    func programs(forbidden: ForbiddenTargets) -> [UUID: MacroProgram] {
        if cacheForbidden != forbidden {
            programCache = [:]
            cacheForbidden = forbidden
        }
        var out: [UUID: MacroProgram] = [:]
        out.reserveCapacity(macros.count)
        for doc in macros {
            if let hit = programCache[doc.id], hit.source == .blocks(id: doc.id, revision: doc.revision) {
                out[doc.id] = hit
            } else {
                out[doc.id] = MacroProgram.compile(doc, forbidden: forbidden)
            }
        }
        programCache = out
        return out
    }

    // MARK: Modifications (thread principal)

    /// Ajoute une macro (id déjà pris : un neuf). `index` : place dans la liste (annulation d'une suppression).
    @discardableResult
    func add(_ doc: MacroDoc, at index: Int? = nil) -> MacroDoc {
        var d = doc
        if macros.contains(where: { $0.id == d.id }) { d.id = UUID() }
        if let index, (0...macros.count).contains(index) {
            macros.insert(d, at: index)
        } else {
            macros.append(d)
        }
        changed()
        return d
    }

    /// Enregistre une version modifiée : révision +1 si le contenu a changé (clé du cache). nil si elle n'existe plus.
    @discardableResult
    func update(_ doc: MacroDoc) -> MacroDoc? {
        guard let i = macros.firstIndex(where: { $0.id == doc.id }) else { return nil }
        let old = macros[i]
        guard !Self.sameContent(old, doc) else { return old }
        var d = doc
        d.revision = old.revision + 1
        macros[i] = d
        changed()
        return d
    }

    /// Retire une macro ; renvoie ce qu'il faut pour l'annuler.
    @discardableResult
    func remove(_ id: UUID) -> (doc: MacroDoc, index: Int)? {
        guard let i = macros.firstIndex(where: { $0.id == id }) else { return nil }
        let doc = macros.remove(at: i)
        changed()
        return (doc, i)
    }

    /// Remplace toute la bibliothèque (sauvegarde du compte reprise, déconnexion : Store.replaceAll).
    func replaceAll(_ docs: [MacroDoc]) {
        macros = docs
        changed()
    }

    /// Copie datée de la bibliothèque (avant de la remplacer par la sauvegarde du compte).
    @discardableResult
    func keepCurrentCopy(label: String) -> String? {
        (try? MacroLibraryCodec.encode(macros)).flatMap { try? storage.backup($0, label: label) }
    }

    static func sameContent(_ a: MacroDoc, _ b: MacroDoc) -> Bool {
        a.name == b.name && a.blocks == b.blocks && a.variables == b.variables && a.origin == b.origin && a.format == b.format
    }

    private func changed() {
        scheduleSave()
        onChange?()
    }

    // MARK: Sauvegarde

    private enum SaveOutcome {
        case saved
        case failed(String)
        /// Copie du fichier d'origine impossible : rien n'est écrit, et plus rien ne le sera pendant ce lancement.
        case backupFailed(String)
    }

    private func makeSave(_ snapshot: [MacroDoc]) -> () -> SaveOutcome {
        let storage = self.storage
        let previous = previousContent
        return {
            // Copie du fichier d'origine, une fois par lancement, avant de le remplacer. Gardée à faire tant qu'elle
            // échoue : une écriture déjà en file ne remplace jamais le fichier sans copie.
            if let old = previous.withLock({ $0 }) {
                do {
                    _ = try storage.backup(old, label: Self.previousLabel)
                } catch {
                    return .backupFailed(error.localizedDescription)
                }
                previous.withLock { $0 = nil }
            }
            do {
                try storage.write(MacroLibraryCodec.encode(snapshot))
                return .saved
            } catch {
                return .failed(error.localizedDescription)
            }
        }
    }

    private func publish(_ outcome: SaveOutcome) {
        let message: String?
        switch outcome {
        case .saved:
            message = nil
        case .failed(let why):
            message = "Tes macros ne peuvent pas être enregistrées : \(why)"
        case .backupFailed(let why):
            writesDisabled = true
            pendingSave?.cancel()
            pendingSave = nil
            message = "Tes macros ne peuvent pas être enregistrées : la copie de secours du fichier a échoué (\(why)). Le fichier n'est pas remplacé."
        }
        if saveError != message { saveError = message }
    }

    private func scheduleSave() {
        guard !writesDisabled else { return }
        pendingSave?.cancel()
        let save = makeSave(macros)
        let work = DispatchWorkItem { [weak self] in
            let outcome = save()
            DispatchQueue.main.async { self?.publish(outcome) }
        }
        pendingSave = work
        saveQueue.asyncAfter(deadline: .now() + saveDelay, execute: work)
    }

    /// Écriture immédiate (fermeture de l'app, tests).
    func saveNow() {
        guard !writesDisabled else { return }
        let hadPending = pendingSave != nil
        pendingSave?.cancel()
        pendingSave = nil
        saveQueue.sync {}                              // attend une écriture déjà commencée
        guard hadPending else { return }
        publish(makeSave(macros)())
    }
}
