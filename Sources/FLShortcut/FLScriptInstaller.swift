// Audit : SEC-06 (aucun lien symbolique suivi : dossier cible vérifié, fichier temporaire dans le même dossier
//         puis rename(2) atomique ; dossier choisi vérifié), SEC-01 / PROTOCOL.md §2 (clé de 16 octets par
//         installation injectée à la place de l'unique `__FLSHORTCUT_KEY__`, stockée au Trousseau),
//         REL-22 (dossier « Hardware » exigé, remplacement atomique, empreinte SHA-256 du script installé
//         pour détecter une modification), audit 04 §3 (FL < 20.7 : pas d'installation, message clair ;
//         rappel de redémarrer FL ; port de sortie apparié).
import AppKit
import CryptoKit
import Foundation

/// Injection de la clé dans le script (pur, testé).
enum ScriptTemplate {
    static let placeholder = "__FLSHORTCUT_KEY__"
    static let keyLine = "KEY_HEX = \"__FLSHORTCUT_KEY__\""

    enum Failure: Error, LocalizedError, Equatable {
        case invalidKey
        case placeholderCount(Int)
        case keyLineMissing

        var errorDescription: String? {
            switch self {
            case .invalidKey: return String(localized: "Clé invalide (16 octets attendus).")
            case .placeholderCount(let n): return String(localized: "Script FL invalide : \(n) emplacement(s) de clé au lieu d'un seul.")
            case .keyLineMissing: return String(localized: "Script FL invalide : ligne KEY_HEX introuvable.")
            }
        }
    }

    static func occurrences(of needle: String, in text: String) -> Int {
        text.components(separatedBy: needle).count - 1
    }

    /// Remplace l'unique occurrence du marqueur, qui doit se trouver sur la ligne `KEY_HEX = "__FLSHORTCUT_KEY__"`,
    /// par 32 caractères hexadécimaux minuscules.
    static func inject(key: [UInt8], into template: String) throws -> String {
        guard key.count == FLProtocol.keyLength else { throw Failure.invalidKey }
        let count = occurrences(of: placeholder, in: template)
        guard count == 1 else { throw Failure.placeholderCount(count) }
        let lines = template.components(separatedBy: "\n")
        guard let index = lines.firstIndex(where: { $0 == keyLine || $0 == keyLine + "\r" }) else {
            throw Failure.keyLineMissing
        }
        var out = lines
        out[index] = lines[index].replacingOccurrences(of: placeholder, with: FLProtocol.hex(key))
        return out.joined(separator: "\n")
    }
}

/// Empreinte du script installé (REL-22) : détecte une modification ou une suppression.
enum ScriptIntegrity {
    enum State: Equatable {
        case notInstalled, ok, modified, missing, unreadable
    }

    static let hashKey = "installedScriptSHA256"
    static let pathKey = "installedScriptPath"

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func record(_ data: Data, at url: URL, defaults: UserDefaults = .standard) {
        defaults.set(sha256Hex(data), forKey: hashKey)
        defaults.set(url.path, forKey: pathKey)
    }

    static func check(defaults: UserDefaults = .standard) -> State {
        guard let path = defaults.string(forKey: pathKey), let expected = defaults.string(forKey: hashKey) else {
            return .notInstalled
        }
        do {
            let url = URL(fileURLWithPath: path)
            guard let data = try SecureFile.read(url, maxBytes: 4 << 20) else { return .missing }
            guard sha256Hex(data) == expected else { return .modified }
            // Audit 03 (WIN-10/11, valable aussi sur Mac) : un autre fichier Python ou un dossier dans le dossier
            // du script pourrait masquer un module de FL (`transport.py`, `midi.py`…) et exécuter du code dans FL.
            return hasForeignEntries(in: url.deletingLastPathComponent(), keeping: url.lastPathComponent) ? .modified : .ok
        } catch {
            return .unreadable
        }
    }

    /// Vrai si le dossier contient autre chose que notre script (fichiers cachés du Finder exceptés).
    static func hasForeignEntries(in folder: URL, keeping name: String, fileManager: FileManager = .default) -> Bool {
        guard let entries = try? fileManager.contentsOfDirectory(atPath: folder.path) else { return false }
        let ignored: Set<String> = [name, ".DS_Store", "__pycache__"]
        return entries.contains { !ignored.contains($0) && !$0.hasPrefix("._") }
    }
}

/// Validation du dossier « Settings/Hardware » de FL (pur, testé).
enum HardwareFolder {
    /// Accepte « …/Settings/Hardware », ou un dossier parent qui le contient (« Settings », « FL Studio »).
    static func resolve(_ chosen: URL, isDirectory: (URL) -> Bool) -> URL? {
        let url = chosen.standardizedFileURL
        if url.lastPathComponent.caseInsensitiveCompare("Hardware") == .orderedSame,
           url.deletingLastPathComponent().lastPathComponent.caseInsensitiveCompare("Settings") == .orderedSame {
            return url
        }
        let candidates = [url.appendingPathComponent("Hardware", isDirectory: true),
                          url.appendingPathComponent("Settings/Hardware", isDirectory: true),
                          url.appendingPathComponent("FL Studio/Settings/Hardware", isDirectory: true)]
        return candidates.first(where: isDirectory)
    }
}

enum FLScriptInstaller {
    static let fileName = "device_FLShortcut.py"
    static let folderName = "FL Shortcuts"
    /// Dossier du script avant le nouveau nom de l'app : remplacé à la mise à jour du script, retiré à la désinstallation.
    static let oldFolderName = AppPaths.oldName
    private static let chosenFolderKey = "hardwareFolderPath"

    static var defaultHardwareFolder: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Documents/Image-Line/FL Studio/Settings/Hardware", isDirectory: true)
    }

    /// Écrit le script dans `<hardware>/FL Shortcuts/device_FLShortcut.py` sans suivre de lien (SEC-06).
    @discardableResult
    static func write(script: Data, hardware: URL) throws -> URL {
        try SecureFile.checkDirectory(hardware)
        let folder = hardware.appendingPathComponent(folderName, isDirectory: true)
        try SecureFile.ensureDirectory(folder)
        let dest = folder.appendingPathComponent(fileName)
        try SecureFile.writeAtomically(script, to: dest, mode: 0o600)
        guard SecureFile.kind(at: dest.path) == .regular else { throw SecureFile.Failure.notARegularFile(dest.path) }
        return dest
    }

    /// Met à jour le script déjà installé quand l'app en embarque une nouvelle version, AVEC LA MÊME CLÉ :
    /// seulement si le script installé est intact (empreinte enregistrée identique), jamais s'il a été modifié.
    /// Installé sous l'ancien nom de l'app (dossier « FL Shortcut ») : le script passe dans « FL Shortcuts » et l'ancien
    /// dossier est retiré, pour que FL ne propose pas deux fois le Controller type.
    /// Renvoie vrai si le fichier a été réécrit (FL le relira à son prochain lancement).
    @discardableResult
    static func updateInstalledIfNeeded(secrets: SecretStore = PreferredSecretStore(),
                                        defaults: UserDefaults = .standard) -> Bool {
        guard ScriptIntegrity.check(defaults: defaults) == .ok,
              let path = defaults.string(forKey: ScriptIntegrity.pathKey),
              let key = secrets.load(),
              let scriptURL = Bundle.main.url(forResource: "device_FLShortcut", withExtension: "py"),
              let template = try? String(contentsOf: scriptURL, encoding: .utf8),
              let text = try? ScriptTemplate.inject(key: key, into: template) else { return false }
        let data = Data(text.utf8)
        let installed = URL(fileURLWithPath: path)
        let oldFolder = installed.deletingLastPathComponent()
        let moving = oldFolder.lastPathComponent == oldFolderName
        guard let current = try? SecureFile.read(installed, maxBytes: 4 << 20), current != data || moving else { return false }
        let hardware = oldFolder.deletingLastPathComponent()
        guard let dest = try? write(script: data, hardware: hardware),
              dest.path == installed.path || moving else { return false }
        ScriptIntegrity.record(data, at: dest, defaults: defaults)
        if moving, isOurScriptFolder(oldFolder) { try? FileManager.default.removeItem(at: oldFolder) }
        return true
    }

    /// Script embarqué dans l'app, avec son marqueur de clé.
    static func bundledTemplate() -> String? {
        guard let url = Bundle.main.url(forResource: "device_FLShortcut", withExtension: "py") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }

    /// Lien installé (clé présente) mais script absent de FL Studio (supprimé, jamais arrivé, réglages de l'app
    /// effacés…) : FL ne propose alors pas le Controller type « FL Shortcuts ». Le script est réécrit avec la même clé,
    /// dans le dossier « Hardware » enregistré s'il existe encore, sinon dans celui de FL par défaut ; FL le lira à
    /// son prochain lancement. Renvoie le chemin écrit ; nil si rien à faire (script en place, modifié par quelqu'un,
    /// pas de clé) ou si aucun dossier de FL n'est trouvé. `usable` : dossier existant et sans lien (SEC-06).
    @discardableResult
    static func repairIfNeeded(secrets: SecretStore = PreferredSecretStore(), defaults: UserDefaults = .standard,
                               template: String? = bundledTemplate(),
                               defaultHardware: URL = defaultHardwareFolder,
                               usable: (URL) -> Bool = { SecureFile.kind(at: $0.path) == .directory
                                   && !SecureFile.pathContainsSymlink($0) }) -> URL? {
        let state = ScriptIntegrity.check(defaults: defaults)
        guard state == .notInstalled || state == .missing, let template, let key = secrets.load(),
              let text = try? ScriptTemplate.inject(key: key, into: template) else { return nil }
        var folders: [URL] = []
        if let path = defaults.string(forKey: ScriptIntegrity.pathKey) {
            folders.append(URL(fileURLWithPath: path).deletingLastPathComponent().deletingLastPathComponent())
        }
        if let saved = defaults.string(forKey: chosenFolderKey) {
            folders.append(URL(fileURLWithPath: saved, isDirectory: true))
        }
        folders.append(defaultHardware)
        guard let hardware = folders.first(where: usable) else { return nil }
        let data = Data(text.utf8)
        guard let dest = try? write(script: data, hardware: hardware) else { return nil }
        ScriptIntegrity.record(data, at: dest, defaults: defaults)
        defaults.set(hardware.path, forKey: chosenFolderKey)
        return dest
    }

    /// Script enregistré et s'il est toujours là (nil : jamais installé).
    static func installedScript(defaults: UserDefaults = .standard) -> (url: URL, present: Bool)? {
        guard let path = defaults.string(forKey: ScriptIntegrity.pathKey) else { return nil }
        let url = URL(fileURLWithPath: path)
        return (url, SecureFile.kind(at: url.path) == .regular)
    }

    /// « Documents › Image-Line › FL Studio › Settings › Hardware › FL Shortcuts » : dossier du script, depuis le
    /// dossier de l'utilisateur.
    static func displayFolder(of script: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> String {
        let folder = script.deletingLastPathComponent().standardizedFileURL.pathComponents
        let base = home.standardizedFileURL.pathComponents
        let parts = folder.starts(with: base) ? folder.dropFirst(base.count) : folder.dropFirst()
        return parts.joined(separator: " › ")
    }

    /// Notre dossier de script (nouveau ou ancien nom) : ne contient que device_FLShortcut.py (et des fichiers du
    /// Finder / le cache Python). Rien d'autre n'est jamais supprimé.
    static func isOurScriptFolder(_ folder: URL, fileManager: FileManager = .default) -> Bool {
        guard [folderName, oldFolderName].contains(folder.lastPathComponent),
              SecureFile.kind(at: folder.path) == .directory,
              let entries = try? fileManager.contentsOfDirectory(atPath: folder.path),
              entries.contains(fileName) else { return false }
        let allowed: Set<String> = [fileName, ".DS_Store", "__pycache__"]
        return entries.allSatisfy { allowed.contains($0) || $0.hasPrefix("._") }
    }

    /// `chooseFolder` : le dossier de FL est demandé même si celui par défaut existe (FL range ses réglages ailleurs).
    /// `quiet` : pas d'alerte de réussite (l'Organiser montre lui-même l'étape suivante). Vrai si le script est
    /// installé ; faux si c'est annulé ou impossible (déjà dit dans une alerte).
    @discardableResult
    static func installWithAlert(secrets: SecretStore = PreferredSecretStore(), chooseFolder: Bool = false,
                                 quiet: Bool = false) -> Bool {
        NSApp.activate(ignoringOtherApps: true)

        guard let template = bundledTemplate() else {
            alert(String(localized: "Script introuvable"),
                  String(localized: "Le fichier \(fileName) manque dans l'application."), style: .critical)
            return false
        }

        if let version = FLDetector.installedVersion(), !version.supportsPython {
            alert(String(localized: "FL Studio trop ancien"),
                  String(localized: """
                      Les actions FL demandent FL Studio \(FLActions.pythonMinFL) ou plus récent (tu as \(version.description)). \
                      Les raccourcis « Touche de FL » restent disponibles sans le script.
                      """), style: .warning)
            return false
        }

        guard let hardware = chooseFolder ? pickHardwareFolder() : chooseHardwareFolder() else { return false }

        let previousKey = secrets.load()
        do {
            let key = try SecretKeyGenerator.generate()
            let text = try ScriptTemplate.inject(key: key, into: template)
            let data = Data(text.utf8)
            try secrets.save(key)
            let dest: URL
            do {
                dest = try write(script: data, hardware: hardware)
            } catch {
                if let previousKey { try? secrets.save(previousKey) } else { secrets.delete() }
                throw error
            }
            ScriptIntegrity.record(data, at: dest)
            UserDefaults.standard.set(hardware.path, forKey: chosenFolderKey)
            MIDILink.shared.reloadKey()
            AppStatus.shared.refreshScriptState()
            if quiet { return true }
            alert(String(localized: "Script installé"), String(localized: """
            Dernière étape : quitte et rouvre FL Studio. Il trouve « FL Shortcuts Link » en démarrant et le relie tout seul.

            Seulement si ça ne marche pas : Options › MIDI Settings, entrée « FL Shortcuts Link », Controller type « FL Shortcuts » (pas « generic controller »), Enable, et le même numéro de Port pour l'entrée et la sortie « FL Shortcuts Link ».

            « FL Shortcuts » absent des Controller types : FL lit un autre dossier. Le script est dans \(displayFolder(of: dest)) ; compare avec Options › File settings › User data folder dans FL.

            Chaque réinstallation crée une nouvelle clé : redémarre FL après coup.
            """))
            return true
        } catch {
            alert(String(localized: "Installation impossible"), error.localizedDescription, style: .critical)
            return false
        }
    }

    /// Dossier par défaut s'il existe et ne contient aucun lien ; sinon dossier mémorisé ; sinon sélecteur vérifié.
    private static func chooseHardwareFolder() -> URL? {
        let isDir: (URL) -> Bool = { SecureFile.kind(at: $0.path) == .directory }
        let fallback = defaultHardwareFolder
        if isDir(fallback), !SecureFile.pathContainsSymlink(fallback) { return fallback }
        if let saved = UserDefaults.standard.string(forKey: chosenFolderKey) {
            let url = URL(fileURLWithPath: saved, isDirectory: true)
            if isDir(url), !SecureFile.pathContainsSymlink(url) { return url }
        }
        return pickHardwareFolder()
    }

    /// Sélecteur vérifié : le dossier de données de FL (Options › File settings › User data folder), ou son
    /// « Settings/Hardware ».
    private static func pickHardwareFolder() -> URL? {
        let isDir: (URL) -> Bool = { SecureFile.kind(at: $0.path) == .directory }
        let panel = NSOpenPanel()
        panel.message = String(localized: """
            Choisis le dossier de données de FL Studio (Options › File settings › User data folder dans FL), \
            ou son dossier « Settings/Hardware ».
            """)
        panel.directoryURL = defaultHardwareFolder.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let picked = panel.url else { return nil }
        let real = picked.resolvingSymlinksInPath()
        guard let hardware = HardwareFolder.resolve(real, isDirectory: isDir), !SecureFile.pathContainsSymlink(hardware) else {
            alert(String(localized: "Dossier incorrect"),
                  String(localized: "Ce n'est ni le dossier de données de FL Studio ni son « Settings/Hardware ». FL ne verrait pas le script."),
                  style: .warning)
            return nil
        }
        return hardware
    }

    private static func alert(_ title: String, _ text: String, style: NSAlert.Style = .informational) {
        let a = NSAlert()
        a.messageText = title
        a.informativeText = text
        a.alertStyle = style
        a.runModal()
    }
}
