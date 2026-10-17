// Désinstallation complète : rien ne reste sur le Mac, et le bilan le vérifie.
// Lancée depuis l'app seulement : menu de l'icône en haut de l'écran, ou menu ⋯ de la fenêtre, « Désinstaller
// FL Shortcuts… » (plus d'app « Désinstaller » à part ; celles des anciennes versions sont retirées aussi).
// Supprimé, sous le nom actuel comme sous l'ancien (« FL Shortcut ») : l'app et les anciens désinstalleurs (Corbeille ;
// ceux du .pkg, avec le mot de passe), tes raccourcis et macros, réglages, état des fenêtres, caches, journal, la clé et
// la session du Trousseau, le script installé dans FL Studio, les autorisations (clavier, écran, son), l'identité
// de signature des compilations locales ; tes macros exportées (Documents) seulement si tu le demandes.
// À la fin, chaque chemin est revérifié : ce que macOS a refusé de supprimer (protection des apps, mot de passe
// refusé) est dit, et montré dans le Finder pour le glisser à la Corbeille.
import AppKit
import Foundation
import Security

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

    /// Ce que l'app y range : « Macros » et « Raccourcis » ; le reste du dossier n'est jamais touché.
    static func exportSubfolders(_ folder: URL) -> [URL] {
        ["Macros", "Raccourcis"].map { folder.appendingPathComponent($0, isDirectory: true) }
    }

    /// Des fichiers exportés existent (macros ou raccourcis).
    static func hasExports(home: URL) -> Bool {
        exportFolders(home: home).flatMap(exportSubfolders).contains { sub in
            ((try? FileManager.default.contentsOfDirectory(atPath: sub.path)) ?? []).contains { !$0.hasPrefix(".") }
        }
    }

    /// Désinstallation faite : toute fermeture de l'app passe par quitAfterUninstall (AppDelegate), jamais par la
    /// fermeture normale qui réécrirait profil, macros et réglages.
    static var didUninstall = false

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

    /// « Désinstaller FL Shortcuts… » (menu de l'icône, menu ⋯) : la fenêtre en 3 étapes (UninstallView.swift).
    @MainActor
    static func confirmAndRun() { UninstallWindow.shared.show() }

    /// Fin : l'app quitte sans la fermeture normale, qui réécrirait le profil, les macros et les réglages
    /// (applicationWillTerminate, fenêtres) qui viennent d'être effacés ; ce qui a pu être réécrit est effacé à nouveau.
    static func quitAfterUninstall() -> Never {
        sweepAgain(home: FileManager.default.homeDirectoryForCurrentUser)
        exit(0)
    }

    /// Réglages et fichiers de l'app réécrits après la suppression (fenêtres, réglages) : effacés une dernière fois.
    private static func sweepAgain(home: URL) {
        CommunitySessionKeychain().delete()
        UserDefaults.standard.removePersistentDomain(forName: bundleID)
        CFPreferencesAppSynchronize(bundleID as CFString)
        for trace in dataTraces(home: home) where trace.url.pathExtension != "keychain-db" && exists(trace.url) {
            try? FileManager.default.removeItem(at: trace.url)
        }
    }

    // MARK: Ce qui demande Touch ID ou le mot de passe

    /// Nos apps de /Applications que ce compte ne peut pas déplacer (installées par le .pkg, elles appartiennent au
    /// système), et le reçu du .pkg : une seule demande pour tout, avant toute suppression.
    struct PrivilegedWork: Equatable {
        var apps: [URL] = []
        var receipt = false
        var isEmpty: Bool { apps.isEmpty && !receipt }
    }

    /// Une de nos apps (ou un ancien désinstalleur) : un paquet .app avec notre identifiant, jamais autre chose.
    static func isOurApp(_ url: URL) -> Bool {
        url.pathExtension == "app" && [bundleID, uninstallerID].contains(Bundle(url: url)?.bundleIdentifier ?? "")
    }

    static func privilegedWork(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> PrivilegedWork {
        var seen = Set<String>()
        let apps = ([Bundle.main.bundleURL] + appLocations(home: home)).map(\.standardizedFileURL)
            .filter { seen.insert($0.path).inserted }
            .filter { $0.path.hasPrefix("/Applications/") && appNames.contains($0.lastPathComponent) && exists($0) }
            .filter(isOurApp)
            .filter { SecureFile.permissions(at: $0.path)?.owner != getuid() }
        return PrivilegedWork(apps: apps, receipt: FileManager.default.fileExists(atPath: "/var/db/receipts/\(pkgID).bom"))
    }

    /// Commande lancée avec les droits d'administrateur : chemins fixes connus, jamais une donnée extérieure.
    static func privilegedScript(_ work: PrivilegedWork) -> String {
        var commands: [String] = []
        if !work.apps.isEmpty {
            commands.append("/bin/rm -rf " + work.apps.map { "'" + $0.path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
                .joined(separator: " "))
        }
        if work.receipt { commands.append("/usr/sbin/pkgutil --forget \(pkgID) >/dev/null") }
        return commands.joined(separator: "; ")
    }

    enum PrivilegedResult: Equatable {
        case done
        /// L'utilisateur a refusé (Annuler dans la fenêtre de macOS) : rien n'est supprimé.
        case cancelled
        case failed(String)
    }

    /// Touch ID ou le mot de passe, une seule fois (fenêtre de macOS), pour ce qui appartient au système.
    /// `sudo` : `sudo -n` à la place (machine de la CI).
    static func runPrivileged(_ work: PrivilegedWork, sudo: Bool = false) -> PrivilegedResult {
        guard !work.isEmpty else { return .done }
        let script = privilegedScript(work)
        if sudo { return run("/usr/bin/sudo", ["-n", "/bin/sh", "-c", script]) ? .done : .failed("sudo -n refusé") }
        let source = "do shell script \"" + script.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"") + "\" with administrator privileges"
        var error: NSDictionary?
        _ = NSAppleScript(source: source)?.executeAndReturnError(&error)
        guard let error else { return .done }
        // Erreurs négatives : l'autorisation n'a pas été donnée (-128 Annuler, -60005 mot de passe faux…) : rien
        // n'est supprimé. Positives : la commande a tourné mais a échoué (le bilan dit ce qui reste).
        if let n = error[NSAppleScript.errorNumber] as? Int, n < 0 { return .cancelled }
        return .failed(error[NSAppleScript.errorMessage] as? String ?? "erreur inconnue")
    }

    // MARK: Suppression

    /// Supprime tout ce que FL Shortcuts a pu créer, puis revérifie chaque chemin.
    /// `interactive` : l'app tourne (tap et MIDI arrêtés, écritures en attente faites). `privilegedDone` : ce qui
    /// appartient au système a déjà été retiré (fenêtre de désinstallation, après Touch ID) ; sinon `sudo -n` s'il
    /// est permis (essai de la CI), ou rien (ce qui reste est dit dans le bilan).
    @discardableResult
    static func removeEverything(interactive: Bool = true, removeExports: Bool = false, sudo: Bool = false,
                                 privilegedDone: Bool = false) -> Report {
        var removed: [String] = []
        func note(_ label: String) { if !removed.contains(label) { removed.append(label) } }
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser

        // 1. Arrêter ce qui tourne ; écritures en attente faites tout de suite, pour qu'aucune n'arrive après la
        // suppression.
        if interactive {
            EventTap.shared.stop()
            MIDILink.shared.stop()
            Store.shared.saveNow()
            Store.shared.library.saveNow()
        }

        // 2. Script installé dans FL Studio : seulement nos dossiers (rien d'autre dedans).
        let defaults = UserDefaults.standard
        let scripts = scriptFolders(home: home, recorded: defaults.string(forKey: ScriptIntegrity.pathKey))
        for folder in scripts where FLScriptInstaller.isOurScriptFolder(folder) {
            if (try? fm.removeItem(at: folder)) != nil { note("le script FL Shortcuts dans FL Studio") }
        }

        // 3. Trousseau : clé du script (et son fichier de repli), session du compte (jamais le mot de passe).
        // Seule la présence est lue, jamais le secret : rangé par une autre version de l'app, le lire ferait
        // demander le mot de passe du Mac au milieu de la désinstallation.
        if inKeychain(account: "fl-script-key") || exists(FileSecretStore().url) { note("la clé dans le Trousseau") }
        PreferredSecretStore().delete()
        if inKeychain(account: "community-session") { note("la session de ton compte dans le Trousseau") }
        CommunitySessionKeychain().delete()
        if interactive { MainActor.assumeIsolated { CommunityStore.shared.forgetSession() } }

        // 4. Réglages (vidés dans cfprefsd avant d'effacer le fichier), données, caches, journal.
        for id in [bundleID, uninstallerID] {
            UserDefaults(suiteName: id)?.removePersistentDomain(forName: id)
            CFPreferencesAppSynchronize(id as CFString)
        }
        defaults.removePersistentDomain(forName: bundleID)
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
                for sub in exportSubfolders(folder) where exists(sub) {
                    if (try? fm.trashItem(at: sub, resultingItemURL: nil)) != nil { note("tes fichiers exportés (Corbeille)") }
                }
            }
            if isEmptyFolder(folder) { try? fm.removeItem(at: folder) }
        }

        // 6. Autorisations : toutes celles de l'app et des anciens désinstalleurs (clavier, écran, son…).
        for id in [bundleID, uninstallerID] {
            if run("/usr/bin/tccutil", ["reset", "All", id]), id == bundleID { note("les autorisations (clavier, écran, son)") }
        }

        // 7. Les apps, à la Corbeille (récupérables tant que la Corbeille n'est pas vidée). Installées par le .pkg,
        // elles appartiennent au système : mot de passe une fois. macOS peut aussi les protéger (« Gestion des
        // apps ») : elles restent alors, et le bilan le dit.
        var apps: [URL] = [Bundle.main.bundleURL]
        for id in [bundleID, uninstallerID] {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { apps.append(url) }
        }
        apps += appLocations(home: home)
        var seen = Set<String>()
        apps = apps.map(\.standardizedFileURL)
            .filter { seen.insert($0.path).inserted && !$0.path.hasPrefix("/Volumes/") && exists($0) && isOurApp($0) }
        var privileged: [URL] = []
        for url in apps where exists(url) {
            if (try? fm.trashItem(at: url, resultingItemURL: nil)) != nil {
                note(label(for: url, home: home))
            } else if url.path.hasPrefix("/Applications/"), appNames.contains(url.lastPathComponent) {
                privileged.append(url)                   // seulement nos apps de /Applications, jamais un autre chemin
            }
        }
        let receipt = fm.fileExists(atPath: "/var/db/receipts/\(pkgID).bom")
        if !privilegedDone, sudo, !privileged.isEmpty || receipt {
            _ = runPrivileged(PrivilegedWork(apps: privileged, receipt: receipt), sudo: true)
        }
        for url in privileged where !exists(url) { note(label(for: url, home: home)) }
        if receipt, !fm.fileExists(atPath: "/var/db/receipts/\(pkgID).bom") { note("le reçu d'installation du .pkg") }

        // 8. Vérification : ce qui est encore là, chemin par chemin.
        var remaining: [Trace] = []
        for url in apps where exists(url) { remaining.append(Trace(url: url, label: label(for: url, home: home))) }
        remaining += dataTraces(home: home).filter { exists($0.url) }
        remaining += desktopTraces(home: home).filter { exists($0.url) }
        remaining += scripts.filter { exists($0) && FLScriptInstaller.isOurScriptFolder($0) }
            .map { Trace(url: $0, label: "le script FL Shortcuts dans FL Studio") }
        if removeExports {
            remaining += exportFolders(home: home).flatMap(exportSubfolders).filter(exists)
                .map { Trace(url: $0, label: "tes fichiers exportés") }
        }
        if interactive { didUninstall = true }
        return Report(removed: removed, remaining: remaining)
    }

    // MARK: Outils

    /// Existe, même si c'est un lien cassé (lstat).
    private static func exists(_ url: URL) -> Bool { SecureFile.kind(at: url.path) != .none }

    /// Élément de l'app dans le Trousseau : sa présence seulement (rien n'est demandé en retour, donc rien n'est
    /// déchiffré et aucune demande de mot de passe ne s'affiche).
    private static func inKeychain(account: String) -> Bool {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: bundleID,
                                    kSecAttrAccount as String: account,
                                    kSecMatchLimit as String: kSecMatchLimitOne]
        return SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess
    }

    private static func isEmptyFolder(_ url: URL) -> Bool {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: url.path) else { return false }
        return entries.allSatisfy { $0 == ".DS_Store" || $0 == "Macros" || $0 == "Raccourcis" }
            && entries.filter { $0 == "Macros" || $0 == "Raccourcis" }.allSatisfy {
                (try? FileManager.default.contentsOfDirectory(atPath: url.appendingPathComponent($0).path))?
                    .allSatisfy { $0 == ".DS_Store" } ?? false
            }
    }

    private static func label(for url: URL, home: URL) -> String {
        let what = url.lastPathComponent.hasPrefix("Désinstaller") ? "l'ancien désinstalleur" : "l'app"
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
