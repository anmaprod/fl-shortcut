// Organiser sur le fichier du projet, côté Mac : FL enregistre le projet ouvert (⌘S, FL au premier plan), son
// fichier est retrouvé (celui que FL vient d'écrire : la fenêtre de FL le dit par macOS, sinon Spotlight et les
// dossiers habituels), puis FL ouvre la copie rangée comme un double-clic dans le Finder. Aucune lecture de l'écran ;
// seuls les chemins des fichiers sont lus, jamais journalisés.
import AppKit
import ApplicationServices
import Foundation

enum ProjectFileLive {
    static func access() -> ProjectFileAccess {
        ProjectFileAccess(save: { save(known: $0) }, open: { open($0) })
    }

    /// FL enregistre ; le fichier qu'il vient d'écrire. Le projet jamais enregistré (FL demande où) ou FL qui ne
    /// répond pas : rien après 8 secondes, l'utilisateur l'enregistre lui-même et réessaie.
    static func save(known: URL?) -> Result<URL, OrganizerError> {
        guard let pid = OrganizerEnvironment.flPID() else { return .failure(.flClosed) }
        let candidates = self.candidates(pid: pid, known: known)
        var before: [URL: Date] = [:]
        for url in candidates { before[url] = modified(url) }
        let start = Date()
        guard sendSave(pid: pid) else {
            return .failure(.failed(String(localized: "FL Studio doit être au premier plan pour enregistrer ton projet : clique dans sa fenêtre, puis sur « Réessayer ».")))
        }
        func written(_ url: URL) -> Bool {
            guard let date = modified(url), date >= start.addingTimeInterval(-1) else { return false }
            return before[url].map { date > $0 } ?? true
        }
        // Aucun fichier connu : FL a le temps d'écrire, puis on cherche un .flp écrit à l'instant.
        let deadline = Date().addingTimeInterval(candidates.isEmpty ? 1.5 : 8)
        while Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
            if let url = candidates.first(where: written) { return .success(settled(url)) }
        }
        if let url = recent(since: start.addingTimeInterval(-1)) { return .success(settled(url)) }
        MacroLog.shared.write("ORGANIZE", "project file not found after save (\(candidates.count) candidates)")
        return .failure(.failed(String(localized: "FL n'a pas enregistré ton projet (ou il n'a jamais été enregistré). Enregistre-le dans FL (Fichier › Enregistrer), puis clique sur « Réessayer ».")))
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

    /// Fichiers qui peuvent être le projet ouvert : celui qu'on attend, celui que la fenêtre de FL dit (macOS), ceux
    /// qui portent le nom de son titre (Spotlight).
    private static func candidates(pid: Int32, known: URL?) -> [URL] {
        var out: [URL] = []
        func add(_ url: URL?) {
            guard let url, url.isFileURL, url.pathExtension.lowercased() == "flp", !out.contains(url) else { return }
            out.append(url)
        }
        add(known)
        let window = mainWindow(pid: pid)
        if let document = window.document { add(URL(string: document)) }
        for name in ProjectFile.titleNames(window.title ?? "") {
            for path in spotlight("kMDItemFSName == \"\(escaped(name)).flp\"c") { add(URL(fileURLWithPath: path)) }
        }
        return out
    }

    /// Titre et document de la fenêtre principale de FL (attributs de macOS, pas l'écran).
    private static func mainWindow(pid: Int32) -> (title: String?, document: String?) {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.5)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXMainWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return (nil, nil) }
        let window = value as! AXUIElement
        func text(_ attribute: String) -> String? {
            var out: CFTypeRef?
            guard AXUIElementCopyAttributeValue(window, attribute as CFString, &out) == .success else { return nil }
            return out as? String
        }
        return (text(kAXTitleAttribute), text(kAXDocumentAttribute))
    }

    /// Un .flp écrit à l'instant : Spotlight, sinon les dossiers où l'on range ses projets (3 secondes au plus).
    private static func recent(since date: Date) -> URL? {
        let stamp = ISO8601DateFormatter().string(from: date)
        var best: (url: URL, date: Date)?
        func consider(_ url: URL) {
            guard url.pathExtension.lowercased() == "flp", !isBackup(url), let changed = modified(url), changed >= date
            else { return }
            if best.map({ changed > $0.date }) ?? true { best = (url, changed) }
        }
        for path in spotlight("kMDItemFSName == \"*.flp\"c && kMDItemFSContentChangeDate >= $time.iso(\(stamp))") {
            consider(URL(fileURLWithPath: path))
        }
        if let best { return best.url }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let folders = ["Documents", "Desktop", "Music"].map { home.appendingPathComponent($0) }
        let budget = Date().addingTimeInterval(3)
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
                consider(url)
            }
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
