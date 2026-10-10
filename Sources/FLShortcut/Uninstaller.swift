// Désinstallation complète : rien ne reste sur le Mac.
// Deux façons de la lancer :
//   - menu « Désinstaller FL Shortcut… » de l'app ;
//   - « Désinstaller FL Shortcut.app » fourni dans le .dmg (même exécutable, clé FLSUninstaller dans
//     son Info.plist), qui ferme FL Shortcut s'il tourne puis supprime tout.
// Supprimé : l'app (mise à la Corbeille), tes raccourcis et réglages, la clé du Trousseau, le script installé
// dans FL Studio, l'autorisation Accessibilité, l'état de fenêtre sauvegardé et les caches.
import AppKit
import Foundation

enum Uninstaller {
    static let bundleID = "app.flshortcut.FLShortcut"

    /// Vrai si cet exécutable est lancé comme « Désinstaller FL Shortcut.app ».
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
        ask.messageText = "Désinstaller FL Shortcut ?"
        ask.informativeText = "L'app, tes raccourcis, ses réglages et son autorisation clavier seront supprimés. "
            + "FL Studio garde ses raccourcis d'origine."
        ask.addButton(withTitle: "Désinstaller")
        ask.addButton(withTitle: "Annuler")
        if #available(macOS 11.0, *) { ask.buttons.first?.hasDestructiveAction = true }
        guard ask.runModal() == .alertFirstButtonReturn else { return }

        let removed = removeEverything()

        let done = NSAlert()
        done.messageText = "FL Shortcut est désinstallé"
        done.informativeText = removed.isEmpty
            ? "Il n'y avait plus rien à supprimer."
            : "Supprimé :\n• " + removed.joined(separator: "\n• ")
        done.addButton(withTitle: "OK")
        done.runModal()
        if !isUninstallerBundle { NSApp.terminate(nil) }
    }

    /// Supprime tout ce que FL Shortcut a pu créer. Renvoie la liste lisible de ce qui a été retiré.
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
        scriptFolders.append(home.appendingPathComponent(
            "Documents/Image-Line/FL Studio/Settings/Hardware/\(FLScriptInstaller.folderName)", isDirectory: true))
        for folder in Set(scriptFolders.map(\.standardizedFileURL)) where isOurScriptFolder(folder) {
            if (try? fm.removeItem(at: folder)) != nil { removed.append("le script FL Shortcut dans FL Studio") }
        }

        // 3. Clé du Trousseau (et son fichier de repli).
        let secrets = PreferredSecretStore()
        if secrets.load() != nil { removed.append("la clé dans le Trousseau") }
        secrets.delete()

        // 4. Raccourcis et données.
        let support = AppPaths.supportDirectory
        if fm.fileExists(atPath: support.path), (try? fm.removeItem(at: support)) != nil {
            removed.append("tes raccourcis et données")
        }

        // 5. Réglages, état des fenêtres, caches.
        defaults?.removePersistentDomain(forName: bundleID)
        CFPreferencesAppSynchronize(bundleID as CFString)
        var hadPrefs = false
        for url in [lib.appendingPathComponent("Preferences/\(bundleID).plist"),
                    lib.appendingPathComponent("Saved Application State/\(bundleID).savedState"),
                    lib.appendingPathComponent("Caches/\(bundleID)"),
                    lib.appendingPathComponent("HTTPStorages/\(bundleID)"),
                    lib.appendingPathComponent("HTTPStorages/\(bundleID).binarycookies"),
                    lib.appendingPathComponent("WebKit/\(bundleID)")] where fm.fileExists(atPath: url.path) {
            if (try? fm.removeItem(at: url)) != nil { hadPrefs = true }
        }
        if hadPrefs { removed.append("les réglages et caches") }

        // 6. Autorisation Accessibilité (la ligne disparaît des Réglages Système).
        if run("/usr/bin/tccutil", ["reset", "Accessibility", bundleID]) { removed.append("l'autorisation clavier") }

        // 7. L'app elle-même, à la Corbeille (récupérable tant que la Corbeille n'est pas vidée).
        var apps = Set<URL>()
        if !isUninstallerBundle { apps.insert(Bundle.main.bundleURL) }
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) { apps.insert(url) }
        for dir in [URL(fileURLWithPath: "/Applications"), home.appendingPathComponent("Applications")] {
            let url = dir.appendingPathComponent("FL Shortcut.app")
            if fm.fileExists(atPath: url.path) { apps.insert(url) }
        }
        for url in apps where !url.path.hasPrefix("/Volumes/") {     // jamais l'image disque elle-même
            if (try? fm.trashItem(at: url, resultingItemURL: nil)) != nil {
                removed.append("l'app (\(url.deletingLastPathComponent().path.replacingOccurrences(of: home.path, with: "~")))")
            }
        }
        return removed
    }

    /// Notre dossier de script : ne contient que device_FLShortcut.py (et des fichiers du Finder / cache Python).
    private static func isOurScriptFolder(_ folder: URL) -> Bool {
        guard folder.lastPathComponent == FLScriptInstaller.folderName,
              let entries = try? FileManager.default.contentsOfDirectory(atPath: folder.path),
              entries.contains(FLScriptInstaller.fileName) else { return false }
        let allowed: Set<String> = [FLScriptInstaller.fileName, ".DS_Store", "__pycache__"]
        return entries.allSatisfy { allowed.contains($0) || $0.hasPrefix("._") }
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
