// Organiser sur le fichier du projet, côté Mac : FL enregistre le projet ouvert (⌘S, FL au premier plan), son
// fichier est retrouvé (celui que FL vient d'écrire : les fenêtres de FL le disent par macOS, sinon Spotlight et les
// dossiers habituels ; déjà enregistré, FL ne le réécrit pas : celui que ses fenêtres désignent), puis FL ouvre la
// copie rangée comme un double-clic dans le Finder. Introuvable (premier essai du propriétaire, 24/10, sur chaque
// projet) : il le montre (« Choisir le fichier… »), et le diagnostic dit ce que la recherche a vu. Aucune lecture de
// l'écran ; seuls les chemins des fichiers sont lus, jamais journalisés.
import AppKit
import ApplicationServices
import Foundation

enum ProjectFileLive {
    static func access() -> ProjectFileAccess {
        ProjectFileAccess(save: { save(known: $0) }, open: { open($0) }, isOpen: { isOpen($0) },
                          search: { lastSearch }, answerDialog: { answerDialog() })
    }

    // MARK: - Fichier montré par l'utilisateur, et ce que la recherche a trouvé (diagnostic)

    private static let lock = NSLock()
    private static var shown: URL?
    private static var searched = ""

    /// Le projet montré par l'utilisateur (« Choisir le fichier… » de l'Organiser) : cherché en premier.
    static var chosen: URL? {
        get { lock.lock(); defer { lock.unlock() }; return shown }
        set { lock.lock(); shown = newValue; lock.unlock() }
    }

    /// La dernière recherche, en nombres et mots fixes (jamais un nom ni un chemin).
    static var lastSearch: String {
        get { lock.lock(); defer { lock.unlock() }; return searched }
        set { lock.lock(); searched = newValue; lock.unlock() }
    }

    /// Ce que la recherche a vu, pour le diagnostic.
    private struct Search {
        var windows = 0
        var names = 0
        var candidates = 0
        var recent = 0
        var scanned = 0
        var taken = "aucun"

        var text: String {
            "fenêtres=\(windows) noms=\(names) candidats=\(candidates) récents=\(recent) parcourus=\(scanned) pris=\(taken)"
        }
    }

    /// La fenêtre de FL porte le nom de ce fichier, ou le désigne (macOS) : FL l'a ouvert.
    static func isOpen(_ url: URL) -> Bool {
        guard let pid = OrganizerEnvironment.flPID() else { return false }
        let window = mainWindow(pid: pid)
        if let document = window.document, URL(string: document)?.standardizedFileURL == url.standardizedFileURL {
            return true
        }
        return window.title?.contains(url.deletingPathExtension().lastPathComponent) ?? false
    }

    /// FL enregistre ; le fichier qu'il vient d'écrire. Un projet déjà enregistré, que FL ne réécrit pas : le fichier
    /// de sa fenêtre (ou celui montré par l'utilisateur) tel quel, sa lecture vérifiant que c'est bien le projet
    /// ouvert (mêmes canaux, mêmes patterns). Rien de trouvé : l'utilisateur le montre (`projectNotFound`).
    static func save(known: URL?) -> Result<URL, OrganizerError> {
        guard let pid = OrganizerEnvironment.flPID() else { return .failure(.flClosed) }
        var search = Search()
        defer { lastSearch = search.text }
        let candidates = self.candidates(pid: pid, known: known, search: &search)
        var before: [URL: Date] = [:]
        for url in candidates { before[url] = modified(url) }
        let start = Date()
        guard sendSave(pid: pid) else {
            search.taken = "premier-plan"
            return .failure(.failed(String(localized: "FL Studio doit être au premier plan pour enregistrer ton projet : clique dans sa fenêtre, puis sur « Réessayer ».")))
        }
        func written(_ url: URL) -> Bool {
            guard let date = modified(url), date >= start.addingTimeInterval(-1) else { return false }
            return before[url].map { date > $0 } ?? true
        }
        // FL écrit le projet (s'il a changé) : 6 secondes au plus. Spotlight note un fichier écrit avec un peu de
        // retard : relu chaque seconde, pour le fichier écrit à l'instant quand la fenêtre ne dit pas lequel.
        let deadline = Date().addingTimeInterval(6)
        var nextLook = Date().addingTimeInterval(1)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
            if let url = candidates.first(where: written) {
                search.taken = "écrit"
                return .success(settled(url))
            }
            if Date() >= nextLook {
                nextLook = Date().addingTimeInterval(1)
                let found = spotlightRecent(since: start.addingTimeInterval(-1))
                search.recent = max(search.recent, found.count)
                if let url = newest(found) {
                    search.taken = "récent"
                    return .success(settled(url))
                }
            }
        }
        if let url = candidates.first(where: written) {
            search.taken = "écrit"
            return .success(settled(url))
        }
        if candidates.isEmpty, let url = walk(since: start.addingTimeInterval(-1), search: &search) {
            search.taken = "dossier"
            return .success(settled(url))
        }
        if let url = candidates.first {
            search.taken = "déjà-enregistré"
            return .success(url)
        }
        MacroLog.shared.write("ORGANIZE", "project file not found after save (\(search.text))")
        return .failure(.projectNotFound)
    }

    /// FL enregistre le projet qu'il montre (ce fichier) : ⌘S, FL au premier plan, puis 4 secondes au plus pour
    /// l'écrire (rien à écrire s'il n'a pas changé). Faux si FL n'a pas pu passer au premier plan.
    static func saveShown(_ url: URL) -> Bool {
        guard let pid = OrganizerEnvironment.flPID() else { return false }
        let before = modified(url)
        let start = Date()
        guard sendSave(pid: pid) else { return false }
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
            if let date = modified(url), date >= start.addingTimeInterval(-1), before.map({ date > $0 }) ?? true {
                Thread.sleep(forTimeInterval: 0.5)                 // FL finit d'écrire
                return true
            }
        }
        return true
    }

    /// FL ouvre ce fichier (comme un double-clic dans le Finder) ; faux si macOS dit que ça n'a pas pu se faire
    /// (10 secondes au plus pour le savoir).
    static func open(_ url: URL) -> Bool {
        guard let pid = OrganizerEnvironment.flPID(),
              let app = NSRunningApplication(processIdentifier: pid)?.bundleURL else { return false }
        let done = DispatchSemaphore(value: 0)
        let failed = NSLock()
        var refused = false
        let start = {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = true
            NSWorkspace.shared.open([url], withApplicationAt: app, configuration: configuration) { _, error in
                if error != nil {
                    MacroLog.shared.write("ORGANIZE", "FL could not open the project file")
                    failed.lock()
                    refused = true
                    failed.unlock()
                }
                done.signal()
            }
        }
        if Thread.isMainThread {
            start()
            return true
        }
        DispatchQueue.main.async(execute: start)
        _ = done.wait(timeout: .now() + 10)
        failed.lock()
        defer { failed.unlock() }
        return !refused
    }

    // MARK: - Le fichier du projet

    /// Fichiers qui peuvent être le projet ouvert, du plus sûr au moins sûr : celui montré par l'utilisateur, celui
    /// qu'on attend, ceux que les fenêtres de FL désignent (macOS), puis ceux qui portent le nom de leur titre
    /// (Spotlight), le plus récent d'abord. Jamais une copie de secours de FL.
    private static func candidates(pid: Int32, known: URL?, search: inout Search) -> [URL] {
        var out: [URL] = []
        func add(_ url: URL?) {
            guard let url, url.isFileURL, url.pathExtension.lowercased() == "flp", !isBackup(url), !out.contains(url),
                  FileManager.default.fileExists(atPath: url.path) else { return }
            out.append(url)
        }
        add(chosen)
        add(known)
        let windows = self.windows(pid: pid)
        search.windows = windows.count
        for window in windows {
            if let document = window.document { add(URL(string: document)) }
        }
        var names: [String] = []
        for window in windows {
            for name in ProjectFile.titleNames(window.title ?? "") where !names.contains(name) { names.append(name) }
        }
        search.names = names.count
        var named: [URL] = []
        for name in names {
            for path in spotlight("kMDItemFSName == \"\(escaped(name)).flp\"c") {
                let url = URL(fileURLWithPath: path)
                if !named.contains(url) { named.append(url) }
            }
        }
        for url in named.sorted(by: { (modified($0) ?? .distantPast) > (modified($1) ?? .distantPast) }) { add(url) }
        search.candidates = out.count
        return out
    }

    /// Titre et document de la fenêtre principale de FL (attributs de macOS, pas l'écran).
    private static func mainWindow(pid: Int32) -> (title: String?, document: String?) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return (nil, nil) }
        return describe(value as! AXUIElement)
    }

    /// Titre et document de chaque fenêtre de FL (attributs de macOS, pas l'écran) ; sinon de sa fenêtre principale.
    private static func windows(pid: Int32) -> [(title: String?, document: String?)] {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        var out: [(title: String?, document: String?)] = []
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
           let list = value as? [AXUIElement] {
            for window in list.prefix(20) {
                let info = describe(window)
                if info.title != nil || info.document != nil { out.append(info) }
            }
        }
        if out.isEmpty {
            let main = mainWindow(pid: pid)
            if main.title != nil || main.document != nil { out.append(main) }
        }
        return out
    }

    private static func describe(_ window: AXUIElement) -> (title: String?, document: String?) {
        func text(_ attribute: String) -> String? {
            var out: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, attribute as CFString, &out) == .success else { return nil }
            return out as? String
        }
        return (text(kAXTitleAttribute), text(kAXDocumentAttribute))
    }

    /// Les .flp écrits depuis `date` que Spotlight connaît déjà (jamais une copie de secours).
    private static func spotlightRecent(since date: Date) -> [URL] {
        let stamp = ISO8601DateFormatter().string(from: date)
        return spotlight("kMDItemFSName == \"*.flp\"c && kMDItemFSContentChangeDate >= $time.iso(\(stamp))")
            .map { URL(fileURLWithPath: $0) }
            .filter { !isBackup($0) && (modified($0).map { $0 >= date } ?? false) }
    }

    private static func newest(_ urls: [URL]) -> URL? {
        urls.max { (modified($0) ?? .distantPast) < (modified($1) ?? .distantPast) }
    }

    /// Un .flp écrit à l'instant, cherché dans les dossiers où l'on range ses projets : celui de FL d'abord
    /// (Documents › Image-Line › FL Studio › Projects), puis Documents, Bureau, Musique (4 secondes au plus).
    private static func walk(since date: Date, search: inout Search) -> URL? {
        var best: (url: URL, date: Date)?
        func consider(_ url: URL) {
            guard url.pathExtension.lowercased() == "flp", !isBackup(url), let changed = modified(url), changed >= date
            else { return }
            if best.map({ changed > $0.date }) ?? true { best = (url, changed) }
        }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let folders = ["Documents/Image-Line/FL Studio/Projects", "Documents", "Desktop", "Music"]
            .map { home.appendingPathComponent($0) }
        let budget = Date().addingTimeInterval(4)
        for folder in folders where Date() < budget {
            guard let walk = FileManager.default.enumerator(
                at: folder, includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in walk {
                if Date() > budget { break }
                if walk.level > 6 {
                    walk.skipDescendants()
                    continue
                }
                search.scanned += 1
                consider(url)
            }
            if best != nil { break }                           // trouvé : pas plus loin
        }
        return best?.url
    }

    /// Copie de secours de FL (l'ancienne version, gardée à chaque enregistrement) ou enregistrement automatique :
    /// jamais pris pour le projet.
    private static func isBackup(_ url: URL) -> Bool {
        let name = url.lastPathComponent.lowercased()
        return url.pathComponents.contains { $0.lowercased() == "backup" }
            || name.contains("(overwritten") || name.contains("autosave")
    }

    /// Fichier fini d'écrire : sa taille ne bouge plus (2 secondes au plus).
    private static func settled(_ url: URL) -> URL {
        var size = -1
        for _ in 0..<10 {
            let now = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? -1
            if now == size, now > 0 { break }
            size = now
            Thread.sleep(forTimeInterval: 0.2)
        }
        return url
    }

    private static func modified(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }

    /// Une boîte de FL qui bloque l'ouverture de la copie (« Invalid project data folder ») : FL devant, Entrée valide
    /// son choix par défaut (« Do nothing », comme l'utilisateur l'aurait fait). Lue par les titres des fenêtres de FL
    /// (attributs de macOS, pas l'écran). nil : aucune boîte, ou FL pas devant.
    static func answerDialog() -> String? {
        guard let pid = OrganizerEnvironment.flPID(),
              windows(pid: pid).contains(where: { ProjectFile.isBlockingDialog($0.title ?? "") }) else { return nil }
        if EventTap.shared.currentConfig.frontmostPID != pid {
            _ = NSRunningApplication(processIdentifier: pid)?.activate(options: [])
            var waited = 0
            while EventTap.shared.currentConfig.frontmostPID != pid, waited < 10 {
                Thread.sleep(forTimeInterval: 0.1)
                waited += 1
            }
        }
        guard EventTap.shared.currentConfig.frontmostPID == pid else { return nil }
        MacroEffectsMac(pid: pid).postKey(KeyCombo(keyCode: 36), pid: pid)       // Entrée : « Ok »
        return "dossier-données"
    }

    /// ⌘S envoyé à FL seul, FL au premier plan.
    private static func sendSave(pid: Int32) -> Bool {
        if EventTap.shared.currentConfig.frontmostPID != pid {
            _ = NSRunningApplication(processIdentifier: pid)?.activate(options: [])
            var waited = 0
            while EventTap.shared.currentConfig.frontmostPID != pid, waited < 10 {
                Thread.sleep(forTimeInterval: 0.1)
                waited += 1
            }
        }
        guard EventTap.shared.currentConfig.frontmostPID == pid else { return false }
        let s = KeyNames.commandKeyCode(for: "s") ?? 1
        MacroEffectsMac(pid: pid).postKey(KeyCombo(keyCode: s, command: true), pid: pid)
        return true
    }

    private static func escaped(_ name: String) -> String {
        name.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "*", with: "\\*")
    }

    /// Chemins trouvés par Spotlight (3 secondes au plus, 50 au plus).
    private static func spotlight(_ query: String) -> [String] {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
        task.arguments = [query]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        guard (try? task.run()) != nil else { return [] }
        let deadline = Date().addingTimeInterval(3)
        while task.isRunning, Date() < deadline { Thread.sleep(forTimeInterval: 0.05) }
        if task.isRunning { task.terminate() }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return Array(String(decoding: data, as: UTF8.self).split(separator: "\n").map(String.init).prefix(50))
    }
}
