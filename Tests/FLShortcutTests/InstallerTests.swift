import XCTest
@testable import FLShortcut

/// PROTOCOL.md §2 (remplacement unique du marqueur), SEC-06 (écriture sans lien symbolique), REL-22.
final class InstallerTests: XCTestCase {
    private let key = Array(UInt8(0)..<UInt8(16))
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FLShortcutTests-\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testPlaceholderReplacedExactlyOnce() throws {
        let template = "# x\nKEY_HEX = \"__FLSHORTCUT_KEY__\"\nprint(KEY_HEX)\n"
        let out = try ScriptTemplate.inject(key: key, into: template)
        XCTAssertEqual(out, "# x\nKEY_HEX = \"000102030405060708090a0b0c0d0e0f\"\nprint(KEY_HEX)\n")
        XCTAssertEqual(ScriptTemplate.occurrences(of: ScriptTemplate.placeholder, in: out), 0)
    }

    func testPlaceholderCountMustBeOne() {
        XCTAssertThrowsError(try ScriptTemplate.inject(key: key, into: "KEY_HEX = \"\"\n")) {
            XCTAssertEqual($0 as? ScriptTemplate.Failure, .placeholderCount(0))
        }
        let twice = "KEY_HEX = \"__FLSHORTCUT_KEY__\"\n# __FLSHORTCUT_KEY__\n"
        XCTAssertThrowsError(try ScriptTemplate.inject(key: key, into: twice)) {
            XCTAssertEqual($0 as? ScriptTemplate.Failure, .placeholderCount(2))
        }
        XCTAssertThrowsError(try ScriptTemplate.inject(key: key, into: "OTHER = \"__FLSHORTCUT_KEY__\"\n")) {
            XCTAssertEqual($0 as? ScriptTemplate.Failure, .keyLineMissing)
        }
        XCTAssertThrowsError(try ScriptTemplate.inject(key: [1, 2, 3], into: "KEY_HEX = \"__FLSHORTCUT_KEY__\"\n")) {
            XCTAssertEqual($0 as? ScriptTemplate.Failure, .invalidKey)
        }
    }

    /// Le vrai script livré : une seule occurrence, sur la bonne ligne.
    func testShippedScriptAcceptsKey() throws {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/device_FLShortcut.py")
        let template = try String(contentsOf: script, encoding: .utf8)
        XCTAssertEqual(ScriptTemplate.occurrences(of: ScriptTemplate.placeholder, in: template), 1)
        let out = try ScriptTemplate.inject(key: key, into: template)
        XCTAssertTrue(out.contains("\nKEY_HEX = \"000102030405060708090a0b0c0d0e0f\"\n"))
        XCTAssertEqual(out.count, template.count - ScriptTemplate.placeholder.count + 32)
        XCTAssertTrue(template.contains("MAX_ACTION_ID = 42"))
        XCTAssertTrue(template.contains("CC_CAPS_FIRST = 90"))
    }

    func testAtomicWriteIsPrivateAndReplaces() throws {
        let file = dir.appendingPathComponent("profile.json")
        try SecureFile.writeAtomically(Data("a".utf8), to: file)
        try SecureFile.writeAtomically(Data("bb".utf8), to: file)
        XCTAssertEqual(try SecureFile.read(file, maxBytes: 10), Data("bb".utf8))
        XCTAssertEqual(SecureFile.permissions(at: file.path)?.mode, 0o600)
        let leftovers = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".tmp") }
        XCTAssertTrue(leftovers.isEmpty)
    }

    func testWriteRefusesSymlinkedDestination() throws {
        let victim = dir.appendingPathComponent("victim.txt")
        try Data("original".utf8).write(to: victim)
        let link = dir.appendingPathComponent("device_FLShortcut.py")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: victim)
        XCTAssertThrowsError(try SecureFile.writeAtomically(Data("x".utf8), to: link))
        XCTAssertEqual(try Data(contentsOf: victim), Data("original".utf8))
        XCTAssertThrowsError(try SecureFile.read(link, maxBytes: 100))
    }

    func testInstallerRefusesSymlinkedFolder() throws {
        let hardware = dir.appendingPathComponent("Settings/Hardware", isDirectory: true)
        try FileManager.default.createDirectory(at: hardware, withIntermediateDirectories: true)
        let elsewhere = dir.appendingPathComponent("elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: elsewhere, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: hardware.appendingPathComponent("FL Shortcuts"),
                                                   withDestinationURL: elsewhere)
        XCTAssertThrowsError(try FLScriptInstaller.write(script: Data("x".utf8), hardware: hardware))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: elsewhere.path).isEmpty)
    }

    /// Nouveau nom de l'app : l'ancien dossier prend le nouveau nom avec son contenu, une seule fois, jamais un lien.
    func testOldNameFolderIsTakenOver() throws {
        let fm = FileManager.default
        let old = dir.appendingPathComponent("FL Shortcut", isDirectory: true)
        let new = dir.appendingPathComponent("FL Shortcuts", isDirectory: true)
        XCTAssertEqual(AppPaths.renamed(old, to: new), new, "rien à reprendre")
        XCTAssertFalse(fm.fileExists(atPath: new.path))

        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        try Data("{}".utf8).write(to: old.appendingPathComponent("macros.json"))
        XCTAssertEqual(AppPaths.renamed(old, to: new), new)
        XCTAssertEqual(try Data(contentsOf: new.appendingPathComponent("macros.json")), Data("{}".utf8))
        XCTAssertFalse(fm.fileExists(atPath: old.path))

        try fm.createDirectory(at: old, withIntermediateDirectories: true)
        XCTAssertEqual(AppPaths.renamed(old, to: new), new, "le nouveau existe déjà : l'ancien n'est pas touché")
        XCTAssertTrue(fm.fileExists(atPath: old.path))
        XCTAssertTrue(fm.fileExists(atPath: new.appendingPathComponent("macros.json").path))

        let linkOld = dir.appendingPathComponent("lien", isDirectory: true)
        let linkNew = dir.appendingPathComponent("lien-nouveau", isDirectory: true)
        try fm.createSymbolicLink(at: linkOld, withDestinationURL: old)
        XCTAssertEqual(AppPaths.renamed(linkOld, to: linkNew), linkNew)
        XCTAssertEqual(SecureFile.kind(at: linkOld.path), .symlink, "un lien n'est jamais repris")
    }

    /// Dossier du script retiré (ancien nom) ou désinstallé : seulement s'il ne contient que notre script.
    func testOurScriptFolderUnderBothNames() throws {
        let hardware = dir.appendingPathComponent("Settings/Hardware", isDirectory: true)
        for name in [FLScriptInstaller.folderName, FLScriptInstaller.oldFolderName, "Autre"] {
            let folder = hardware.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("print(1)".utf8).write(to: folder.appendingPathComponent(FLScriptInstaller.fileName))
            try Data().write(to: folder.appendingPathComponent(".DS_Store"))
            XCTAssertEqual(FLScriptInstaller.isOurScriptFolder(folder), name != "Autre", name)
            try Data("x".utf8).write(to: folder.appendingPathComponent("transport.py"))
            XCTAssertFalse(FLScriptInstaller.isOurScriptFolder(folder), "un autre fichier à côté : jamais supprimé")
        }
        XCTAssertEqual(FLScriptInstaller.oldFolderName, "FL Shortcut")
        XCTAssertEqual(Uninstaller.appNames.sorted(), ["Désinstaller FL Shortcut.app", "Désinstaller FL Shortcuts.app",
                                                       "FL Shortcut.app", "FL Shortcuts.app"])
    }

    /// Désinstallation : chaque trace connue, sous le nom actuel et l'ancien nom, dans les deux dossiers Applications.
    func testUninstallerKnowsEveryTrace() {
        let home = URL(fileURLWithPath: "/Users/nina")
        let apps = Uninstaller.appLocations(home: home).map(\.path)
        XCTAssertEqual(apps.count, 8)
        XCTAssertTrue(apps.contains("/Applications/FL Shortcuts.app"))
        XCTAssertTrue(apps.contains("/Users/nina/Applications/Désinstaller FL Shortcut.app"))
        let data = Uninstaller.dataTraces(home: home).map(\.url.path)
        for path in ["/Users/nina/Library/Application Support/FL Shortcuts",
                     "/Users/nina/Library/Application Support/FL Shortcut",
                     "/Users/nina/Library/Logs/FL Shortcuts", "/Users/nina/Library/Logs/FL Shortcut",
                     "/Users/nina/Library/Preferences/app.flshortcut.FLShortcut.plist",
                     "/Users/nina/Library/Preferences/app.flshortcut.Uninstaller.plist",
                     "/Users/nina/Library/Saved Application State/app.flshortcut.FLShortcut.savedState",
                     "/Users/nina/Library/Caches/app.flshortcut.FLShortcut",
                     "/Users/nina/Library/Keychains/flshortcut-dev.keychain-db"] {
            XCTAssertTrue(data.contains(path), path)
        }
        XCTAssertEqual(Uninstaller.exportFolders(home: home).map(\.lastPathComponent), ["FL Shortcuts", "FL Shortcut"])
        let recorded = "/Users/nina/Documents/Image-Line/FL Studio/Settings/Hardware/FL Shortcuts/device_FLShortcut.py"
        XCTAssertEqual(Uninstaller.scriptFolders(home: home, recorded: recorded).map(\.lastPathComponent),
                       ["FL Shortcuts", "FL Shortcut"], "chemin enregistré et emplacements par défaut, sans doublon")
    }

    /// Ce qui demande Touch ID ou le mot de passe : une seule commande, chemins entre apostrophes (même avec une
    /// apostrophe dedans), reçu du .pkg oublié.
    func testPrivilegedScript() {
        XCTAssertEqual(Uninstaller.privilegedScript(Uninstaller.PrivilegedWork()), "")
        XCTAssertTrue(Uninstaller.PrivilegedWork().isEmpty)
        let work = Uninstaller.PrivilegedWork(apps: [URL(fileURLWithPath: "/Applications/FL Shortcuts.app"),
                                                     URL(fileURLWithPath: "/Applications/L'autre.app")], receipt: true)
        XCTAssertEqual(Uninstaller.privilegedScript(work),
                       "/bin/rm -rf '/Applications/FL Shortcuts.app' '/Applications/L'\\''autre.app'; "
                       + "/usr/sbin/pkgutil --forget app.flshortcut.pkg >/dev/null")
        // Autorisations (clavier, écran, son) : retirées de la liste du système, en administrateur.
        let permissions = Uninstaller.PrivilegedWork(permissions: true)
        XCTAssertFalse(permissions.isEmpty)
        XCTAssertEqual(Uninstaller.privilegedScript(permissions),
                       "/usr/bin/tccutil reset All app.flshortcut.FLShortcut >/dev/null 2>&1; "
                       + "/usr/bin/tccutil reset All app.flshortcut.Uninstaller >/dev/null 2>&1")
        XCTAssertTrue(Uninstaller.privilegedWork(home: URL(fileURLWithPath: "/nulle/part")).permissions)
    }

    func testInstallerWritesIntoDedicatedFolder() throws {
        let hardware = dir.appendingPathComponent("Settings/Hardware", isDirectory: true)
        try FileManager.default.createDirectory(at: hardware, withIntermediateDirectories: true)
        let dest = try FLScriptInstaller.write(script: Data("print(1)".utf8), hardware: hardware)
        XCTAssertEqual(dest.lastPathComponent, "device_FLShortcut.py")
        XCTAssertEqual(dest.deletingLastPathComponent().lastPathComponent, "FL Shortcuts")
        XCTAssertEqual(SecureFile.permissions(at: dest.path)?.mode, 0o600)

        let defaults = try XCTUnwrap(UserDefaults(suiteName: "FLShortcutTests-\(UUID())"))
        ScriptIntegrity.record(Data("print(1)".utf8), at: dest, defaults: defaults)
        XCTAssertEqual(ScriptIntegrity.check(defaults: defaults), .ok)
        try Data("print(2)".utf8).write(to: dest)
        XCTAssertEqual(ScriptIntegrity.check(defaults: defaults), .modified)
    }

    /// Clé là mais script disparu de FL : remis avec la même clé (dossier enregistré, sinon celui de FL par défaut) ;
    /// jamais sans clé, jamais par-dessus un script modifié.
    func testRepairPutsMissingScriptBackWithSameKey() throws {
        // Chemin sans aucun lien (sur macOS, /var mène à /private/var) : un dossier de FL qui en contient est refusé.
        let raw = try XCTUnwrap(realpath(dir.path, nil))
        let real = URL(fileURLWithPath: String(cString: raw), isDirectory: true)
        free(raw)
        let hardware = real.appendingPathComponent("Settings/Hardware", isDirectory: true)
        try FileManager.default.createDirectory(at: hardware, withIntermediateDirectories: true)
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "FLShortcutTests-\(UUID())"))
        let secrets = MemorySecrets()
        let template = "# name=FL Shortcuts\nKEY_HEX = \"__FLSHORTCUT_KEY__\"\n"
        let absent = real.appendingPathComponent("absent", isDirectory: true)
        func repair(_ fallback: URL) -> URL? {
            FLScriptInstaller.repairIfNeeded(secrets: secrets, defaults: defaults, template: template,
                                             defaultHardware: fallback)
        }

        XCTAssertNil(repair(hardware), "sans clé : écran d'installation, rien d'écrit")
        secrets.key = key
        let dest = try XCTUnwrap(repair(hardware))
        XCTAssertEqual(dest.path, hardware.appendingPathComponent("FL Shortcuts/device_FLShortcut.py").path)
        XCTAssertEqual(try String(contentsOf: dest, encoding: .utf8),
                       "# name=FL Shortcuts\nKEY_HEX = \"000102030405060708090a0b0c0d0e0f\"\n")
        XCTAssertEqual(ScriptIntegrity.check(defaults: defaults), .ok)
        XCTAssertNil(repair(hardware), "script en place : rien à faire")

        try FileManager.default.removeItem(at: dest.deletingLastPathComponent())
        XCTAssertEqual(ScriptIntegrity.check(defaults: defaults), .missing)
        XCTAssertEqual(repair(absent)?.path, dest.path, "remis au même endroit")
        XCTAssertEqual(FLScriptInstaller.installedScript(defaults: defaults)?.present, true)

        try Data("print(2)".utf8).write(to: dest)
        XCTAssertNil(repair(hardware), "modifié par quelqu'un : jamais réécrit")
        XCTAssertEqual(try String(contentsOf: dest, encoding: .utf8), "print(2)")

        let other = try XCTUnwrap(UserDefaults(suiteName: "FLShortcutTests-\(UUID())"))
        XCTAssertNil(FLScriptInstaller.repairIfNeeded(secrets: secrets, defaults: other, template: template,
                                                      defaultHardware: absent), "aucun dossier de FL : rien")
        XCTAssertNil(FLScriptInstaller.installedScript(defaults: other))
    }

    func testScriptFolderShownFromHome() {
        let home = URL(fileURLWithPath: "/Users/nina")
        XCTAssertEqual(FLScriptInstaller.displayFolder(
            of: URL(fileURLWithPath: "/Users/nina/Documents/Image-Line/FL Studio/Settings/Hardware/FL Shortcuts/"
                    + "device_FLShortcut.py"), home: home),
                       "Documents › Image-Line › FL Studio › Settings › Hardware › FL Shortcuts")
        XCTAssertEqual(FLScriptInstaller.displayFolder(
            of: URL(fileURLWithPath: "/Volumes/Son/FL/Settings/Hardware/FL Shortcuts/device_FLShortcut.py"), home: home),
                       "Volumes › Son › FL › Settings › Hardware › FL Shortcuts")
    }

    func testHardwareFolderResolution() {
        let base = URL(fileURLWithPath: "/Users/x/Documents/Image-Line/FL Studio")
        let hardware = base.appendingPathComponent("Settings/Hardware")
        let exists: (URL) -> Bool = { $0.standardizedFileURL.path == hardware.path }
        XCTAssertEqual(HardwareFolder.resolve(hardware, isDirectory: exists)?.path, hardware.path)
        XCTAssertEqual(HardwareFolder.resolve(base.appendingPathComponent("Settings"), isDirectory: exists)?.path, hardware.path)
        XCTAssertEqual(HardwareFolder.resolve(base, isDirectory: exists)?.path, hardware.path)
        XCTAssertNil(HardwareFolder.resolve(URL(fileURLWithPath: "/tmp"), isDirectory: exists))
    }

    func testFileSecretStoreRoundTripAndHex() throws {
        let store = FileSecretStore(url: dir.appendingPathComponent("script.key"))
        XCTAssertNil(store.load())
        try store.save(key)
        XCTAssertEqual(store.load(), key)
        XCTAssertEqual(SecureFile.permissions(at: store.url.path)?.mode, 0o600)
        XCTAssertNil(FileSecretStore.parseHex("00"))
        XCTAssertNil(FileSecretStore.parseHex(String(repeating: "g", count: 32)))
        XCTAssertEqual(FLProtocol.hex(key), "000102030405060708090a0b0c0d0e0f")
    }
}

private final class MemorySecrets: SecretStore {
    var key: [UInt8]?
    func load() -> [UInt8]? { key }
    func save(_ key: [UInt8]) throws { self.key = key }
    func delete() { key = nil }
}
