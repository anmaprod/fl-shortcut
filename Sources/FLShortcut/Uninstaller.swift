// Désinstallation complète : rien ne reste sur le Mac, et le bilan le vérifie.
// Deux façons de la lancer :
//   - menu « Désinstaller FL Shortcuts… » de l'app ;
//   - « Désinstaller FL Shortcuts.app » fourni dans le .dmg (même exécutable, clé FLSUninstaller dans
//     son Info.plist), qui ferme FL Shortcuts s'il tourne puis supprime tout.
// Supprimé, sous le nom actuel comme sous l'ancien (« FL Shortcut ») : l'app et le désinstalleur (Corbeille ; ceux
// du .pkg, avec le mot de passe), tes raccourcis et macros, réglages, état des fenêtres, caches, journal, la clé et
// la session du Trousseau, le script installé dans FL Studio, les autorisations (clavier, écran, son), l'identité
// de signature des compilations locales ; tes macros exportées (Documents) seulement si tu le demandes.
// À la fin, chaque chemin est revérifié : ce que macOS a refusé de supprimer (protection des apps, mot de passe
// refusé) est dit, et montré dans le Finder pour le glisser à la Corbeille.
import AppKit
import Foundation

enum Uninstaller {
    static let bundleID = "app.flshortcut.FLShortcut"
    static let uninstallerID = "app.flshortcut.Uninstaller"
    static let pkgID = "app.flshortcut.pkg"
    /// Nom actuel et ancien nom de l'app.
    static let names = ["FL Shortcuts", AppPaths.oldName]
    /// L'app et le désinstalleur, au nom actuel et à l'ancien nom (« FL Shortcut », avant « FL Shortcuts »).
    static let appNames = names.flatMap { ["\($0).app", "Désinstaller \($0).app"] }

    /// Une trace laissée sur le Mac : son chemin, et ce qu'elle est (bilan).
    struct Trace: Equatable {
        let url: URL
        let label: String
    }

    /// Bilan : ce qui a été retiré (en clair) et ce qui est encore là après vérification.
    struct Report: Equatable {
        var removed: [String] = []
        var remaining: [Trace] = []
    }

    /// Vrai si cet exécutable est lancé comme « Désinstaller FL Shortcuts.app ».
    static var isUninstallerBundle: Bool {
        Bundle.main.object(forInfoDictionaryKey: "FLSUninstaller") as? Bool == true
    }

    // MARK: Où l'app laisse des traces (pur, testé)

    /// Les apps aux emplacements connus (Applications du Mac et du compte).
    static func appLocations(home: URL) -> [URL] {
        [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")].flatMap { dir in
            appNames.map { dir.appendingPathComponent($0) }
        }
    }

    /// Tout ce que l'app (ou une version à l'ancien nom) crée dans le dossier personnel, hors apps, Trousseau,
    /// script de FL et macros exportées (traités à part).
    static func dataTraces(home: URL) -> [Trace] {
        let lib = home.appendingPathComponent("Library")
        var out: [Trace] = []
        for name in names {
            out.append(Trace(url: lib.appendingPathComponent("Application Support/\(name)"), label: "tes raccourcis et tes macros"))
            out.append(Trace(url: lib.appendingPathComponent("Logs/\(name)"), label: "le journal des macros"))
        }
        for id in [bundleID, uninstallerID] {
            out.append(Trace(url: lib.appendingPathComponent("Preferences/\(id).plist"), label: "les réglages"))
            out.append(Trace(url: lib.appendingPathComponent("Saved Application State/\(id).savedState"), label: "l'état des fenêtres"))
            for cache in ["Caches/\(id)", "HTTPStorages/\(id)", "HTTPStorages/\(id).binarycookies", "WebKit/\(id)"] {
                out.append(Trace(url: lib.appendingPathComponent(cache), label: "les caches"))
            }
        }
        // Compilations locales (build.sh, « Compiler FL Shortcuts.command ») : trousseau de signature à part.
        out.append(Trace(url: lib.appendingPathComponent("Keychains/flshortcut-dev.keychain-db"),
                         label: "l'identité de signature des compilations locales"))
        return out
    }

    /// Ce qui va à la Corbeille plutôt qu'être effacé : visible par l'utilisateur, récupérable.
    static func desktopTraces(home: URL) -> [Trace] {
        names.map { Trace(url: home.appendingPathComponent("Desktop/\($0) – captures"), label: "les captures sur le Bureau") }
    }

    /// Dossiers d'échange (Documents › FL Shortcuts › Macros, Raccourcis) : des fichiers à l'utilisateur.
    static func exportFolders(home: URL) -> [URL] {
        names.map { home.appendingPathComponent("Documents/\($0)") }
    }

    /// Dossiers du script dans FL Studio (le chemin enregistré, et l'emplacement par défaut sous les deux noms).
    static func scriptFolders(home: URL, recorded: String?) -> [URL] {
        var folders = recorded.map { [URL(fileURLWithPath: $0).deletingLastPathComponent()] } ?? []
        for name in [FLScriptInstaller.folderName, FLScriptInstaller.oldFolderName] {
            folders.append(home.appendingPathComponent("Documents/Image-Line/FL Studio/Settings/Hardware/\(name)", isDirectory: true))
        }
        var seen = Set<String>()
        return folders.map(\.standardizedFileURL).filter { seen.insert($0.path).inserted }
    }

    // MARK: Lancement

    /// Lancé depuis le .dmg : boîte de dialogue seule, sans icône dans la barre des menus, puis fin.
    static func runStandaloneIfNeeded() {
        guard isUninstallerBundle else { return }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.finishLaunching()
        confirmAndRun()
        exit(0)
    }

    /// Essai de la CI (`--essai-desinstallation`, avec FLS_ESSAI_DESINSTALLATION=1) : tout supprimer sans aucune
    /// fenêtre, écrire le bilan, quitter (0 : plus rien ne reste). FLS_ESSAI_SUDO=1 : ce qui demande le mot de passe
    /// passe par `sudo -n` (machine de la CI) au lieu de la fenêtre de macOS.
    static func runCheckIfRequested() {
        guard CommandLine.arguments.contains("--essai-desinstallation"),
              ProcessInfo.processInfo.environment["FLS_ESSAI_DESINSTALLATION"] == "1" else { return }
        let report = removeEverything(interactive: false, removeExports: true,
                                      sudo: ProcessInfo.processInfo.environment["FLS_ESSAI_SUDO"] == "1")
        for line in report.removed { print("supprimé : \(line)") }
        for trace in report.remaining { print("RESTE : \(trace.url.path) (\(trace.label))") }
        print(report.remaining.isEmpty ? "PASS: plus aucune trace" : "FAIL: \(report.remaining.count) trace(s)")
        exit(report.remaining.isEmpty ? 0 : 1)
    }

    /// Demande confirmation, supprime tout, affiche le bilan vérifié. Depuis l'app, celle-ci quitte ensuite.
    static func confirmAndRun() {
        NSApp.activate(ignoringOtherApps: true)
        let home = FileManager.default.homeDirectoryForCurrentUser
        let exports = exportFolders(home: home).filter { !isEmptyFolder($0) && FileManager.default.fileExists(atPath: $0.path) }

        let ask = NSAlert()
        ask.alertStyle = .warning
        ask.messageText = "Désinstaller FL Shortcuts ?"
        ask.informativeText = "L'app, tes raccourcis, tes macros, ses réglages et ses autorisations seront supprimés de "
            + "ce Mac. FL Studio garde ses raccourcis d'origine. Ton compte et ta sauvegarde en ligne restent : "
            + "supprime-les d'abord dans « Mon compte » si tu veux tout effacer."
        var exportBox: NSButton?
        if !exports.isEmpty {
            let box = NSButton(checkboxWithTitle: "Supprimer aussi mes fichiers exportés (Documents › FL Shortcuts)",
                               target: nil, action: nil)
            box.state = .off
            ask.accessoryView = box
            exportBox = box
        }
        ask.addButton(withTitle: "Désinstaller")
        ask.addButton(withTitle: "Annuler")
        ask.buttons.first?.hasDestructiveAction = true
        guard ask.runModal() == .alertFirstButtonReturn else { return }

        let report = removeEverything(interactive: true, removeExports: exportBox?.state == .on)

        let done = NSAlert()
        var text = report.removed.isEmpty ? "Il n'y avait plus rien à supprimer."
            : "Supprimé :\n• " + report.removed.joined(separator: "\n• ")
        if report.remaining.isEmpty {
            done.messageText = "FL Shortcuts est désinstallé"
            text += "\n\nPlus rien ne reste sur ce Mac."
            done.addButton(withTitle: "OK")
        } else {
            done.messageText = "Il reste une dernière étape"
            text += "\n\nmacOS n'a pas laissé supprimer :\n• "
                + report.remaining.map { "\($0.url.lastPathComponent) (\($0.url.deletingLastPathComponent().path))" }
                    .joined(separator: "\n• ")
                + "\n\nGlisse-les dans la Corbeille : le Finder te demandera ton mot de passe si besoin."
            done.addButton(withTitle: "Afficher dans le Finder")
            done.addButton(withTitle: "OK")
        }
        if !exports.isEmpty, exportBox?.state != .on {
            text += "\n\nTes fichiers exportés restent dans Documents › FL Shortcuts."
        }
        done.informativeText = text
        if done.runModal() == .alertFirstButtonReturn, !report.remaining.isEmpty {
            NSWorkspace.shared.activateFileViewerSelecting(report.remaining.map(\.url))
        }
        if !isUninstallerBundle {
            // Pas la fermeture normale : elle réécrirait le profil, les macros et les réglages (applicationWillTerminate,
            // fenêtres) qui viennent d'être effacés. Ce qui a pu être réécrit pendant le bilan est effacé à nouveau.
            sweepAgain(home: home)
            exit(0)
        }
    }

    /// Réglages et fichiers de l'app réécrits après la suppression (fenêtres, réglages) : effacés une dernière fois.
    private static func sweepAgain(home: URL) {
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        CFPreferencesAppSynchronize(bundleID as CFString)
        for trace in dataTraces(home: home) where trace.url.pathExtension != "keychain-db" && exists(trace.url) {
            try? FileManager.default.removeItem(at: trace.url)
        }
    }

    // MARK: Suppression

    /// Supprime tout ce que FL Shortcuts a pu créer, puis revérifie chaque chemin.
    /// `interactive` : fenêtre de mot de passe de macOS pour les apps installées par le .pkg ; sans, rien n'est demandé
    /// (essai de la CI). `sudo` : à la place, `sudo -n` (CI seulement).
    @discardableResult
    static func removeEverything(interactive: Bool = true, removeExports: Bool = false, sudo: Bool = false) -> Report {
        var removed: [String] = []
        func note(_ label: String) { if !removed.contains(label) { removed.append(label) } }
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        // 1. Arrêter ce qui tourne : l'app principale si on est le désinstalleur (elle enregistre en quittant : on
        // attend qu'elle ait fini, 3 s au plus), ou nous-mêmes (écritures en attente faites tout de suite, pour
        // qu'aucune n'arrive après la suppression).
        if isUninstallerBundle {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            running.forEach { $0.terminate() }
            let end = Date().addingTimeInterval(3)
            while running.contains(where: { !$0.isTerminated }), Date() < end { Thread.sleep(forTimeInterval: 0.1) }
            running.filter { !$0.isTerminated }.forEach { $0.forceTerminate() }
            Thread.sleep(forTimeInterval: 0.3)
        } else if interactive {
            EventTap.shared.stop()
            MIDILink.shared.stop()
            Store.shared.saveNow()
            Store.shared.library.saveNow()
        }

        // 2. Script installé dans FL Studio : seulement nos dossiers (rien d'autre dedans).
        // Depuis le désinstalleur : réglages d'une autre app (même utilisateur). Depuis l'app : les siens.
        let defaults: UserDefaults? = isUninstallerBundle ? UserDefaults(suiteName: bundleID) : UserDefaults.standard
        let scripts = scriptFolders(home: home, recorded: defaults?.string(forKey: ScriptIntegrity.pathKey))
        for folder in scripts where FLScriptInstaller.isOurScriptFolder(folder) {
            if (try? fm.removeItem(at: folder)) != nil { note("le script FL Shortcuts dans FL Studio") }
        }

        // 3. Trousseau : clé du script (et son fichier de repli), session du compte (jamais le mot de passe).
        let secrets = PreferredSecretStore()
        if secrets.load() != nil { note("la clé dans le Trousseau") }
        secrets.delete()
        let session = CommunitySessionKeychain()
        if session.load() != nil { note("la session de ton compte dans le Trousseau") }
        session.delete()

        // 4. Réglages (vidés dans cfprefsd avant d'effacer le fichier), données, caches, journal.
        for id in [bundleID, uninstallerID] {
            UserDefaults(suiteName: id)?.removePersistentDomain(forName: id)
            CFPreferencesAppSynchronize(id as CFString)
        }
        defaults?.removePersistentDomain(forName: bundleID)
        for trace in dataTraces(home: home) where exists(trace.url) {
            if trace.url.pathExtension == "keychain-db" {
                _ = run("/usr/bin/security", ["delete-keychain", trace.url.path])   // le retire aussi de la liste
            }
            if !exists(trace.url) || (try? fm.removeItem(at: trace.url)) != nil { note(trace.label) }
        }
        for trace in desktopTraces(home: home) where exists(trace.url) {
            if (try? fm.trashItem(at: trace.url, resultingItemURL: nil)) != nil { note(trace.label) }
        }

        // 5. Macros exportées : à la Corbeille si demandé ; un dossier vide est retiré de toute façon.
        for folder in exportFolders(home: home) where exists(folder) {
            if removeExports {
                if (try? fm.trashItem(at: folder, resultingItemURL: nil)) != nil { note("tes fichiers exportés (Corbeille)") }
            } else if isEmptyFolder(folder) {
                try? fm.removeItem(at: folder)
            }
        }

        // 6. Autorisations : toutes celles de l'app et du désinstalleur (clavier, écran, son…).
        for id in [bundleID, uninstallerID] {
            if run("/usr/bin/tccutil", ["reset", "All", id]), id == bundleID { note("les autorisations (clavier, écran, son)") }
        }

        // 7. Les apps, à la Corbeille (récupérables tant que la Corbeille n'est pas vidée). Installées par le .pkg,
        // elles appartiennent au système : mot de passe une fois. macOS peut aussi les protéger (« Gestion des
        // apps ») : elles restent alors, et le bilan le dit.
        var apps: [URL] = []
        if !isUninstallerBundle { apps.append(Bundle.main.bundleURL) }
        for id in [bundleID, uninstallerID] {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { apps.append(url) }
        }
        apps += appLocations(home: home)
        var seen = Set<String>()
        apps = apps.map(\.standardizedFileURL).filter { seen.insert($0.path).inserted && !$0.path.hasPrefix("/Volumes/") }
        var privileged: [URL] = []
        for url in apps where exists(url) {
            if (try? fm.trashItem(at: url, resultingItemURL: nil)) != nil {
                note(label(for: url, home: home))
            } else if url.path.hasPrefix("/Applications/"), appNames.contains(url.lastPathComponent) {
                privileged.append(url)                   // seulement nos apps de /Applications, jamais un autre chemin
            }
        }
        let receipt = fm.fileExists(atPath: "/var/db/receipts/\(pkgID).bom")
        if !privileged.isEmpty || receipt {
            let quoted = privileged.map { "'" + $0.path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
            var commands: [String] = []
            if !quoted.isEmpty { commands.append("/bin/rm -rf " + quoted.joined(separator: " ")) }
            if receipt { commands.append("/usr/sbin/pkgutil --forget \(pkgID)") }
            let script = commands.joined(separator: "; ")
            if sudo {
                _ = run("/usr/bin/sudo", ["-n", "/bin/sh", "-c", script])
            } else if interactive {
                // Chemins fixes connus (aucune donnée extérieure) ; un seul mot de passe pour le tout.
                let source = "do shell script \"" + script
                    .replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                    + "\" with administrator privileges"
                var error: NSDictionary?
                _ = NSAppleScript(source: source)?.executeAndReturnError(&error)
            }
            for url in privileged where !exists(url) { note(label(for: url, home: home)) }
        }

        // 8. Vérification : ce qui est encore là, chemin par chemin.
        var remaining: [Trace] = []
        for url in apps where exists(url) { remaining.append(Trace(url: url, label: label(for: url, home: home))) }
        remaining += dataTraces(home: home).filter { exists($0.url) }
        remaining += desktopTraces(home: home).filter { exists($0.url) }
        remaining += scripts.filter { exists($0) && FLScriptInstaller.isOurScriptFolder($0) }
            .map { Trace(url: $0, label: "le script FL Shortcuts dans FL Studio") }
        if removeExports {
            remaining += exportFolders(home: home).filter(exists).map { Trace(url: $0, label: "tes fichiers exportés") }
        }
        return Report(removed: removed, remaining: remaining)
    }

    // MARK: Outils

    /// Existe, même si c'est un lien cassé (lstat).
    private static func exists(_ url: URL) -> Bool { SecureFile.kind(at: url.path) != .none }

    private static func isEmptyFolder(_ url: URL) -> Bool {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return false }
        return entries.allSatisfy { $0 == ".DS_Store" || $0 == "Macros" || $0 == "Raccourcis" }
            && entries.filter { $0 == "Macros" || $0 == "Raccourcis" }.allSatisfy {
                (try? FileManager.default.contentsOfDirectory(atPath: url.appendingPathComponent($0).path))?
                    .allSatisfy { $0 == ".DS_Store" } ?? false
            }
    }

    private static func label(for url: URL, home: URL) -> String {
        let what = url.lastPathComponent.hasPrefix("Désinstaller") ? "le désinstalleur" : "l'app"
        return "\(what) (\(url.deletingLastPathComponent().path.replacingOccurrences(of: home.path, with: "~")))"
    }

    @discardableResult
    private static func run(_ tool: String, _ args: [String]) -> Bool {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        return p.terminationStatus == 0
    }
}
