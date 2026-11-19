import AppKit
import CryptoKit
import Foundation
import Security

// Mises à jour toutes seules (19/11, « que notre logiciel puisse être corrigé sans que les gens soient obligés de
// réinstaller l'appli » ; choix : « toute seule », publiée seulement quand le propriétaire dit « publie »).
//
// Chaque version publiée (tag vX.Y.Z, job « Publication » de la CI) met dans la release GitHub un petit fichier
// `mise-a-jour.json` (version, adresse et empreinte SHA-256 de l'app Mac en .zip et de l'installeur Windows) et sa
// signature `mise-a-jour.json.sig` (ECDSA P-256, clé privée dans le secret UPDATE_SIGNING_KEY ; clé publique ci-dessous,
// la même que Windows). L'app le lit au lancement puis toutes les 6 h, et ne garde que ce qui est signé, plus récent,
// téléchargé depuis les releases du dépôt, à la bonne empreinte et signé du même certificat que l'app (`codesign`).
// Elle la pose seulement quand FL Studio est fermé et qu'aucune fenêtre de l'app n'est ouverte, puis se relance.
// Seules les versions publiées le font (Info.plist `FLSUpdates` = release, écrit par build.sh pour un tag) : une
// version d'essai de la branche ne se remplace jamais toute seule.
enum UpdateRules {
    /// Clé publique des mises à jour (la même dans l'app Windows : essai `SameUpdateKeyAsTheMac`).
    static let publicKeyPEM = """
    -----BEGIN PUBLIC KEY-----
    MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEXPKipXXg5IdHrF853+ZvA8rchhVc
    D/lYlcrmIHxvRARtPignnY4tUj4YCGnQwGcJKcP4UymK7KVj6gt/sr9rIg==
    -----END PUBLIC KEY-----
    """
    static let manifestURL = URL(string: "https://github.com/anmaprod/fl-shortcut/releases/latest/download/mise-a-jour.json")!
    static let signatureURL = URL(string: "https://github.com/anmaprod/fl-shortcut/releases/latest/download/mise-a-jour.json.sig")!
    /// Seules adresses de téléchargement acceptées : les releases du dépôt.
    static let downloadPrefix = "https://github.com/anmaprod/fl-shortcut/releases/download/"

    struct Asset: Decodable, Equatable {
        let url: String
        let sha256: String
    }

    struct Manifest: Decodable, Equatable {
        let version: String
        let mac: Asset?
        let windows: Asset?
    }

    /// Le manifeste, seulement si sa signature (base64 d'une signature DER) est celle de la clé de l'app et qu'il a
    /// une version X.Y.Z ; nil sinon.
    static func verified(_ data: Data, signature: Data, publicKeyPEM: String = publicKeyPEM) -> Manifest? {
        guard let key = try? P256.Signing.PublicKey(pemRepresentation: publicKeyPEM),
              let text = String(data: signature, encoding: .utf8),
              let der = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
              let sig = try? P256.Signing.ECDSASignature(derRepresentation: der),
              key.isValidSignature(sig, for: data),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              components(manifest.version) != nil else { return nil }
        return manifest
    }

    /// « 1.2.3 » → [1, 2, 3] ; nil pour toute autre forme.
    static func components(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let numbers = parts.compactMap { part -> Int? in
            guard !part.isEmpty, part.count <= 6, part.allSatisfy(\.isASCII), part.allSatisfy(\.isNumber) else { return nil }
            return Int(part)
        }
        return numbers.count == 3 ? numbers : nil
    }

    /// `candidate` est-elle plus récente que `current` ? Faux si l'une n'est pas de la forme X.Y.Z.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        guard let a = components(candidate), let b = components(current) else { return false }
        return b.lexicographicallyPrecedes(a)
    }

    /// L'adresse d'un fichier de la mise à jour, seulement dans les releases du dépôt (HTTPS, sans « .. »).
    static func downloadURL(_ text: String) -> URL? {
        guard text.hasPrefix(downloadPrefix), !text.contains(".."), !text.contains("\\"),
              let url = URL(string: text), url.scheme == "https", url.host == "github.com" else { return nil }
        return url
    }

    /// Empreinte SHA-256 en hexadécimal minuscule.
    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Poser la mise à jour maintenant ? Jamais pendant que FL tourne, ni quand une fenêtre de l'app est ouverte.
    static func canInstall(flRunning: Bool, windowOpen: Bool) -> Bool {
        !flRunning && !windowOpen
    }
}

/// Vérifie, télécharge et pose les mises à jour (fil principal ; le réseau et les fichiers en arrière-plan).
final class AutoUpdate {
    static let shared = AutoUpdate()

    /// Mise à jour prête à être posée : sa version et l'app décompressée.
    private var ready: (version: String, app: URL)?
    private var checking = false
    private var lastCheck = Date.distantPast
    private var timer: Timer?
    static let checkEvery: TimeInterval = 6 * 3600

    private init() {}

    /// Seulement une version publiée, lancée comme une vraie app (jamais les essais de la CI ni le mode capture).
    static var enabled: Bool {
        Bundle.main.object(forInfoDictionaryKey: "FLSUpdates") as? String == "release"
            && Bundle.main.bundleURL.pathExtension == "app"
            && Bundle.main.bundleIdentifier?.hasPrefix("app.flshortcut") == true
            && !DebugSnapshot.enabled
            && !CommandLine.arguments.dropFirst().contains { $0.hasPrefix("--") }     // modes d'essai de la CI
    }

    static var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static var folder: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("FL Shortcuts/Mise à jour", isDirectory: true)
    }

    private static let updatedFromKey = "updatedFrom"

    func start() {
        guard Self.enabled, timer == nil else { return }
        if let from = UserDefaults.standard.string(forKey: Self.updatedFromKey) {
            MacroLog.shared.write("UPDATE", "updated \(from) → \(Self.currentVersion)")
            UserDefaults.standard.removeObject(forKey: Self.updatedFromKey)
        }
        try? FileManager.default.removeItem(at: Self.folder)        // restes d'une mise à jour déjà posée
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { [weak self] in self?.check() }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in self?.tick() }
    }

    /// Chaque minute : poser la mise à jour prête si c'est le moment, sinon revérifier toutes les 6 h.
    private func tick() {
        if let ready { installIfIdle(ready); return }
        if Date().timeIntervalSince(lastCheck) >= Self.checkEvery { check() }
    }

    private func check() {
        guard !checking, ready == nil else { return }
        checking = true
        lastCheck = Date()
        let current = Self.currentVersion
        Task.detached(priority: .utility) {
            let prepared = await Self.prepare(current: current)
            await MainActor.run {
                self.checking = false
                guard let prepared else { return }
                self.ready = prepared
                self.installIfIdle(prepared)
            }
        }
    }

    // MARK: - Téléchargement et vérifications (arrière-plan)

    private static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 30
        c.timeoutIntervalForResource = 15 * 60
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    private static func fetch(_ url: URL) async -> Data? {
        guard let result = try? await session.data(from: url),
              (result.1 as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return result.0
    }

    /// Une version plus récente, signée, téléchargée et vérifiée, prête à poser ; nil sinon (rien de neuf, hors
    /// ligne, ou quoi que ce soit d'inattendu : rien n'est touché).
    private static func prepare(current: String) async -> (version: String, app: URL)? {
        guard let data = await fetch(UpdateRules.manifestURL), data.count < 64_000,
              let signature = await fetch(UpdateRules.signatureURL), signature.count < 4_000 else { return nil }
        guard let manifest = UpdateRules.verified(data, signature: signature) else {
            MacroLog.shared.write("UPDATE", "manifest refused (signature)")
            return nil
        }
        guard UpdateRules.isNewer(manifest.version, than: current) else { return nil }
        guard let asset = manifest.mac, let url = UpdateRules.downloadURL(asset.url) else {
            MacroLog.shared.write("UPDATE", "\(manifest.version): no Mac file")
            return nil
        }
        MacroLog.shared.write("UPDATE", "\(current) → \(manifest.version): downloading")
        let fm = FileManager.default
        let folder = Self.folder
        try? fm.removeItem(at: folder)
        guard (try? fm.createDirectory(at: folder, withIntermediateDirectories: true,
                                       attributes: [.posixPermissions: 0o700])) != nil,
              let download = try? await session.download(from: url),
              (download.1 as? HTTPURLResponse)?.statusCode == 200 else {
            MacroLog.shared.write("UPDATE", "\(manifest.version): download failed")
            return nil
        }
        let zip = folder.appendingPathComponent("FLShortcuts-mac.zip")
        guard (try? fm.moveItem(at: download.0, to: zip)) != nil,
              let bytes = try? Data(contentsOf: zip, options: .mappedIfSafe),
              UpdateRules.sha256Hex(bytes) == asset.sha256.lowercased() else {
            MacroLog.shared.write("UPDATE", "\(manifest.version): checksum mismatch")
            try? fm.removeItem(at: folder)
            return nil
        }
        let unpacked = folder.appendingPathComponent("app", isDirectory: true)
        guard run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path]) else {
            MacroLog.shared.write("UPDATE", "\(manifest.version): unzip failed")
            try? fm.removeItem(at: folder)
            return nil
        }
        let app = unpacked.appendingPathComponent(Bundle.main.bundleURL.lastPathComponent, isDirectory: true)
        guard let why = refusal(app, version: manifest.version) else {
            try? fm.removeItem(at: zip)
            MacroLog.shared.write("UPDATE", "\(manifest.version): ready")
            return (manifest.version, app)
        }
        MacroLog.shared.write("UPDATE", "\(manifest.version): refused (\(why))")
        try? fm.removeItem(at: folder)
        return nil
    }

    /// Pourquoi l'app téléchargée est refusée (nil : elle est bonne) : même identifiant, la version annoncée, une
    /// signature de code valide et, si l'app actuelle est signée par un certificat, signée du même.
    static func refusal(_ app: URL, version: String) -> String? {
        guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) else { return "Info.plist" }
        guard info["CFBundleIdentifier"] as? String == Bundle.main.bundleIdentifier else { return "identifier" }
        guard info["CFBundleShortVersionString"] as? String == version else { return "version" }
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return "code" }
        var requirement: SecRequirement?
        if let mine = currentRequirement(), mine.contains("certificate") {
            guard SecRequirementCreateWithString(mine as CFString, [], &requirement) == errSecSuccess else { return "requirement" }
        }
        // kSecCSCheckAllArchitectures (1 << 0) | kSecCSStrictValidate (1 << 4), SecStaticCode.h
        let flags = SecCSFlags(rawValue: (1 << 0) | (1 << 4))
        guard SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess else { return "signature" }
        return nil
    }

    /// L'exigence de signature de l'app qui tourne (« identifier … and certificate leaf = H"…" » avec le certificat
    /// de la CI ; le seul cdhash pour une app signée ad hoc).
    private static func currentRequirement() -> String? {
        var me: SecCode?
        guard SecCodeCopySelf([], &me) == errSecSuccess, let me else { return nil }
        var staticMe: SecStaticCode?
        guard SecCodeCopyStaticCode(me, [], &staticMe) == errSecSuccess, let staticMe else { return nil }
        var requirement: SecRequirement?
        guard SecCodeCopyDesignatedRequirement(staticMe, [], &requirement) == errSecSuccess, let requirement else { return nil }
        var text: CFString?
        guard SecRequirementCopyString(requirement, [], &text) == errSecSuccess else { return nil }
        return text as String?
    }

    private static func run(_ tool: String, _ arguments: [String]) -> Bool {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: tool)
        task.arguments = arguments
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        do { try task.run() } catch { return false }
        task.waitUntilExit()
        return task.terminationStatus == 0
    }

    // MARK: - Pose (fil principal)

    /// Une fenêtre de l'app est-elle ouverte (fenêtre principale, Organiser, créateur…) ? Le menu de l'icône et les
    /// petites bulles ne comptent pas.
    private var windowOpen: Bool {
        NSApp.windows.contains { $0.isVisible && $0.canBecomeMain }
    }

    private func installIfIdle(_ update: (version: String, app: URL)) {
        guard UpdateRules.canInstall(flRunning: FLMonitor.shared.running, windowOpen: windowOpen) else { return }
        ready = nil
        let target = Bundle.main.bundleURL
        guard Self.replace(target, with: update.app) else {
            MacroLog.shared.write("UPDATE", "\(update.version): could not replace the app")
            try? FileManager.default.removeItem(at: Self.folder)
            return
        }
        MacroLog.shared.write("UPDATE", "\(Self.currentVersion) → \(update.version): installed, relaunching")
        UserDefaults.standard.set(Self.currentVersion, forKey: Self.updatedFromKey)
        SingleInstance.relaunchAfterQuit()
        NSApp.terminate(nil)
    }

    /// Remplace l'app : d'un coup quand le dossier Applications le permet, sinon son dossier Contents (l'app
    /// appartient à la personne connectée, posé ainsi par le .pkg : pas de mot de passe).
    static func replace(_ target: URL, with new: URL) -> Bool {
        let fm = FileManager.default
        if (try? fm.replaceItemAt(target, withItemAt: new, backupItemName: nil, options: [])) != nil { return true }
        let contents = target.appendingPathComponent("Contents", isDirectory: true)
        let old = target.appendingPathComponent("Contents.ancien", isDirectory: true)
        try? fm.removeItem(at: old)
        guard (try? fm.moveItem(at: contents, to: old)) != nil else { return false }
        guard (try? fm.moveItem(at: new.appendingPathComponent("Contents", isDirectory: true), to: contents)) != nil else {
            try? fm.moveItem(at: old, to: contents)                 // remis comme avant
            return false
        }
        try? fm.removeItem(at: old)
        return true
    }
}
