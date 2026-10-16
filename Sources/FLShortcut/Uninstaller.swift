// Désinstallation complète : rien ne reste sur le Mac.
// Deux façons de la lancer :
//   - menu « Désinstaller FL Shortcuts… » de l'app ;
//   - « Désinstaller FL Shortcuts.app » fourni dans le .dmg (même exécutable, clé FLSUninstaller dans
//     son Info.plist), qui ferme FL Shortcuts s'il tourne puis supprime tout.
// Supprimé : l'app (mise à la Corbeille), tes raccourcis et réglages, la clé du Trousseau, le script installé
// dans FL Studio, l'autorisation Accessibilité, l'état de fenêtre sauvegardé et les caches.
import AppKit
import Foundation

enum Uninstaller {
    static let bundleID = "app.flshortcut.FLShortcut"

    /// Vrai si cet exécutable est lancé comme « Désinstaller FL Shortcuts.app ».
    static var isUninstallerBundle: Bool {
        Bundle.main.object(forInfoDictionaryKey: "FLSUninstaller") as? Bool == true
    }

    /// Lancé depuis le .dmg : boîte de dialogue seule, sans icône dans la barre des menus, puis fin.
    static func runStandaloneIfNeeded() {
        guard isUninstallerBundle else { return }
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        app.finishLaunching()
        confirmAndRun()
        exit(0)
    }

    /// Demande confirmation, supprime tout, affiche le bilan. Depuis l'app, celle-ci quitte ensuite.
    static func confirmAndRun() {
        NSApp.activate(ignoringOtherApps: true)
        let ask = NSAlert()
        ask.alertStyle = .warning
        ask.messageText = "Désinstaller FL Shortcuts ?"
        ask.informativeText = "L'app, tes raccourcis, ses réglages et son autorisation clavier seront supprimés. "
            + "FL Studio garde ses raccourcis d'origine."
        ask.addButton(withTitle: "Désinstaller")
        ask.addButton(withTitle: "Annuler")
        if #available(macOS 11.0, *) { ask.buttons.first?.hasDestructiveAction = true }
        guard ask.runModal() == .alertFirstButtonReturn else { return }

        let removed = removeEverything()

        let done = NSAlert()
        done.messageText = "FL Shortcuts est désinstallé"
        done.informativeText = removed.isEmpty
            ? "Il n'y avait plus rien à supprimer."
            : "Supprimé :\n• " + removed.joined(separator: "\n• ")
        done.addButton(withTitle: "OK")
        done.runModal()
        if !isUninstallerBundle { NSApp.terminate(nil) }
    }

    /// Supprime tout ce que FL Shortcuts a pu créer. Renvoie la liste lisible de ce qui a été retiré.
    @discardableResult
    static func removeEverything() -> [String] {
        var removed: [String] = []
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let lib = home.appendingPathComponent("Library")

        // 1. Arrêter ce qui tourne (l'app principale si on est le désinstalleur, ou nous-mêmes).
        if isUninstallerBundle {
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) {
                app.terminate()
            }
            Thread.sleep(forTimeInterval: 0.8)
            for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleID) where !app.isTerminated {
                app.forceTerminate()
            }
        } else {
            EventTap.shared.stop()
            MIDILink.shared.stop()
        }

        // 2. Script installé dans FL Studio (ancien mode avec actions MIDI) : seulement notre dossier.
        // Depuis le désinstalleur : réglages d'une autre app (même utilisateur). Depuis l'app : les siens.
        let defaults: UserDefaults? = isUninstallerBundle ? UserDefaults(suiteName: bundleID) : UserDefaults.standard
        var scriptFolders: [URL] = []
        if let path = defaults?.string(forKey: ScriptIntegrity.pathKey) {
            scriptFolders.append(URL(fileURLWithPath: path).deletingLastPathComponent())
        }
        for name in [FLScriptInstaller.folderName, FLScriptInstaller.oldFolderName] {   // nom actuel et ancien nom
            scriptFolders.append(home.appendingPathComponent(
                "Documents/Image-Line/FL Studio/Settings/Hardware/\(name)", isDirectory: true))
        }
        var hadScript = false
        for folder in Set(scriptFolders.map(\.standardizedFileURL)) where FLScriptInstaller.isOurScriptFolder(folder) {
            if (try? fm.removeItem(at: folder)) != nil { hadScript = true }
        }
        if hadScript { removed.append("le script FL Shortcuts dans FL Studio") }

        // 3. Clé du Trousseau (et son fichier de repli).
        let secrets = PreferredSecretStore()
        if secrets.load() != nil { removed.append("la clé dans le Trousseau") }
        secrets.delete()
        CommunitySessionKeychain().delete()             // session de la Communauté (jamais le mot de passe)

        // 4. Raccourcis et données.
        let oldSupport = AppPaths.supportDirectory.deletingLastPathComponent()
            .appendingPathComponent(AppPaths.oldName, isDirectory: true)          // ancien nom, s'il est resté
        var hadData = false
        for support in Set([AppPaths.supportDirectory, oldSupport].map(\.standardizedFileURL)) where fm.fileExists(atPath: support.path) {
            if (try? fm.removeItem(at: support)) != nil { hadData = true }
        }
        if hadData { removed.append("tes raccourcis et données") }

        // 5. Réglages, état des fenêtres, caches, journal des macros.
        defaults?.removePersistentDomain(forName: bundleID)
        CFPreferencesAppSynchronize(bundleID as CFString)
        var hadPrefs = false
        for url in [lib.appendingPathComponent("Preferences/\(bundleID).plist"),
                    lib.appendingPathComponent("Saved Application State/\(bundleID).savedState"),
                    lib.appendingPathComponent("Caches/\(bundleID)"),
                    lib.appendingPathComponent("HTTPStorages/\(bundleID)"),
                    lib.appendingPathComponent("HTTPStorages/\(bundleID).binarycookies"),
                    lib.appendingPathComponent("WebKit/\(bundleID)"),
                    lib.appendingPathComponent("Logs/FL Shortcuts"),
                    lib.appendingPathComponent("Logs/\(AppPaths.oldName)")] where fm.fileExists(atPath: url.path) {
            if (try? fm.removeItem(at: url)) != nil { hadPrefs = true }
        }
        if hadPrefs { removed.append("les réglages, caches et journaux") }

        // 6. Autorisations (les lignes disparaissent des Réglages Système).
        if run("/usr/bin/tccutil", ["reset", "Accessibility", bundleID]) { removed.append("l'autorisation clavier") }
        if run("/usr/bin/tccutil", ["reset", "ScreenCapture", bundleID]) { removed.append("l'autorisation d'écran") }

        // 7. Captures « Capturer FL » laissées sur le Bureau.
        if let desktop = fm.urls(for: .desktopDirectory, in: .userDomainMask).first {
            var trashed = false
            for name in ["FL Shortcuts", AppPaths.oldName] {
                let captures = desktop.appendingPathComponent("\(name) – captures", isDirectory: true)
                if fm.fileExists(atPath: captures.path), (try? fm.trashItem(at: captures, resultingItemURL: nil)) != nil {
                    trashed = true
                }
            }
            if trashed { removed.append("les captures sur le Bureau") }
        }

        // 8. L'app et le désinstalleur, à la Corbeille (récupérables tant que la Corbeille n'est pas vidée).
        // Installés par le .pkg, ils appartiennent au système : macOS demande alors le mot de passe une fois.
        var apps = Set<URL>()
        if !isUninstallerBundle { apps.insert(Bundle.main.bundleURL) }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) { apps.insert(url) }
        for dir in [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")] {
            for name in appNames {
                let url = dir.appendingPathComponent(name)
                if fm.fileExists(atPath: url.path) { apps.insert(url) }
            }
        }
        // Suppression avec mot de passe (définitive) : seulement nos apps installées par le .pkg dans /Applications
        // (nom actuel ou ancien nom), jamais un autre chemin.
        let pkgInstalled = Set(appNames.map { "/Applications/" + $0 })
        var privileged: [URL] = []
        var seen = Set<String>()
        for url in apps.map(\.standardizedFileURL) where !url.path.hasPrefix("/Volumes/") {   // jamais l'image disque
            guard seen.insert(url.path).inserted, fm.fileExists(atPath: url.path) else { continue }
            if (try? fm.trashItem(at: url, resultingItemURL: nil)) != nil {
                removed.append(label(for: url, home: home))
            } else if pkgInstalled.contains(url.path) {
                privileged.append(url)
            }
        }
        let receipt = fm.fileExists(atPath: "/var/db/receipts/\(pkgID).bom")
        if !privileged.isEmpty || receipt {
            // Chemins fixes connus (aucune donnée extérieure) ; un seul mot de passe pour le tout.
            let quoted = privileged.map { "'" + $0.path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
            var commands: [String] = []
            if !quoted.isEmpty { commands.append("/bin/rm -rf " + quoted.joined(separator: " ")) }
            if receipt { commands.append("/usr/sbin/pkgutil --forget \(pkgID)") }
            let source = "do shell script \"" + commands.joined(separator: "; ")
                .replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
                + "\" with administrator privileges"
            var error: NSDictionary?
            if NSAppleScript(source: source)?.executeAndReturnError(&error) != nil, error == nil {
                removed += privileged.map { label(for: $0, home: home) }
            }
        }
        return removed
    }

    static let pkgID = "app.flshortcut.pkg"

    /// L'app et le désinstalleur, au nom actuel et à l'ancien nom (« FL Shortcut », avant « FL Shortcuts »).
    static let appNames = ["FL Shortcuts", AppPaths.oldName].flatMap { ["\($0).app", "Désinstaller \($0).app"] }

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
