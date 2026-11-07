// Audit : SEC-01 / PROTOCOL.md §2 (clé de 16 octets par installation, Trousseau de préférence,
//         sinon fichier 0600 dans Application Support), SEC-05 (droits vérifiés à la lecture).
import Foundation
import Security

/// Stockage de la clé partagée avec le script FL. Injectable pour les tests.
protocol SecretStore: AnyObject {
    func load() -> [UInt8]?
    func save(_ key: [UInt8]) throws
    func delete()
}

enum SecretStoreError: Error, LocalizedError {
    case keychain(OSStatus)
    case invalidKey

    var errorDescription: String? {
        switch self {
        case .keychain(let s): return String(localized: "Trousseau indisponible (\(s)).")
        case .invalidKey: return String(localized: "Clé invalide.")
        }
    }
}

enum SecretKeyGenerator {
    /// 16 octets issus du générateur cryptographique du système.
    static func generate() throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: FLProtocol.keyLength)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else { throw SecretStoreError.keychain(status) }
        return bytes
    }
}

/// Un seul élément du Trousseau pour tout FL Shortcuts : la clé du script FL et la session du compte ensemble.
/// macOS ne demande donc l'accès qu'une fois (« Toujours autoriser » : plus jamais pour cette version de l'app), et
/// l'élément n'est lu qu'une fois par lancement, puis gardé en mémoire (retour de l'utilisateur : une demande par
/// lecture, beaucoup trop). Les deux éléments séparés des versions d'avant sont repris puis effacés.
final class KeychainVault {
    struct Content: Codable {
        /// Clé du script FL, en hexadécimal.
        var scriptKey: String?
        var session: CommunitySession?

        var isEmpty: Bool { scriptKey == nil && session == nil }
    }

    static let account = "fl-shortcuts"
    /// Éléments des versions d'avant (un par secret).
    static let legacyKeyAccount = "fl-script-key"
    static let legacySessionAccount = "community-session"

    private static var vaults: [String: KeychainVault] = [:]
    private static let registry = NSLock()

    /// Un coffre par service : tous ceux qui lisent ou écrivent le même élément partagent sa copie en mémoire.
    static func shared(service: String = "app.flshortcut.FLShortcut") -> KeychainVault {
        registry.lock()
        defer { registry.unlock() }
        if let vault = vaults[service] { return vault }
        let vault = KeychainVault(service: service)
        vaults[service] = vault
        return vault
    }

    private let service: String
    private let lock = NSLock()
    /// nil : pas encore lu (ou lecture refusée : elle sera redemandée).
    private var cache: Content?

    private init(service: String) {
        self.service = service
    }

    private func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    private func copy(_ account: String) -> (status: OSStatus, data: Data?) {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(q as CFDictionary, &item)
        return (status, item as? Data)
    }

    /// Le contenu, lu une fois par lancement. Pas encore d'élément commun : les deux éléments d'avant sont repris
    /// (une seule fois), réunis, puis effacés.
    func read() -> Content {
        lock.lock()
        defer { lock.unlock() }
        if let cache { return cache }
        let found = copy(Self.account)
        if found.status == errSecSuccess {
            let content = found.data.flatMap { try? JSONDecoder().decode(Content.self, from: $0) } ?? Content()
            cache = content
            return content
        }
        guard found.status == errSecItemNotFound else { return Content() }      // refusé : redemandé plus tard
        var content = Content()
        let key = copy(Self.legacyKeyAccount)
        if let data = key.data, data.count == FLProtocol.keyLength { content.scriptKey = FLProtocol.hex([UInt8](data)) }
        let session = copy(Self.legacySessionAccount)
        if let data = session.data { content.session = try? JSONDecoder().decode(CommunitySession.self, from: data) }
        if !content.isEmpty, (try? write(content)) != nil {
            SecItemDelete(query(Self.legacyKeyAccount) as CFDictionary)
            SecItemDelete(query(Self.legacySessionAccount) as CFDictionary)
        }
        if [key.status, session.status].allSatisfy({ $0 == errSecSuccess || $0 == errSecItemNotFound }) {
            cache = content
        }
        return content
    }

    /// Change le contenu et l'écrit ; vide, l'élément est effacé.
    func update(_ change: (inout Content) -> Void) throws {
        var content = read()
        change(&content)
        lock.lock()
        defer { lock.unlock() }
        if content.isEmpty {
            SecItemDelete(query(Self.account) as CFDictionary)
        } else {
            try write(content)
        }
        cache = content
    }

    private func write(_ content: Content) throws {
        let data = try JSONEncoder().encode(content)
        let update = SecItemUpdate(query(Self.account) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw SecretStoreError.keychain(update) }
        var add = query(Self.account)
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = "FL Shortcuts"
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw SecretStoreError.keychain(status) }
    }

    /// Désinstallation : l'élément commun et ceux d'avant effacés sans être lus (aucune demande d'accès).
    func deleteAll() {
        lock.lock()
        defer { lock.unlock() }
        for account in [Self.account, Self.legacyKeyAccount, Self.legacySessionAccount] {
            SecItemDelete(query(account) as CFDictionary)
        }
        cache = nil
    }
}

/// La clé du script FL, dans l'élément commun du Trousseau.
final class KeychainSecretStore: SecretStore {
    private let vault: KeychainVault

    init(service: String = "app.flshortcut.FLShortcut") {
        vault = .shared(service: service)
    }

    func load() -> [UInt8]? {
        vault.read().scriptKey.flatMap(FileSecretStore.parseHex)
    }

    func save(_ key: [UInt8]) throws {
        guard key.count == FLProtocol.keyLength else { throw SecretStoreError.invalidKey }
        try vault.update { $0.scriptKey = FLProtocol.hex(key) }
    }

    func delete() {
        try? vault.update { $0.scriptKey = nil }
    }
}

/// Repli : fichier 0600 dans « Application Support/FL Shortcuts », jamais suivi s'il est un lien.
final class FileSecretStore: SecretStore {
    let url: URL

    init(url: URL = AppPaths.supportDirectory.appendingPathComponent("script.key")) {
        self.url = url
    }

    func load() -> [UInt8]? {
        guard let perms = SecureFile.permissions(at: url.path),
              perms.owner == getuid(), perms.mode & 0o077 == 0,
              let data = try? SecureFile.read(url, maxBytes: 256, requirePrivate: true),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return Self.parseHex(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    func save(_ key: [UInt8]) throws {
        guard key.count == FLProtocol.keyLength else { throw SecretStoreError.invalidKey }
        try SecureFile.ensureDirectory(url.deletingLastPathComponent())
        try SecureFile.writeAtomically(Data(FLProtocol.hex(key).utf8), to: url, mode: 0o600)
    }

    func delete() {
        if SecureFile.kind(at: url.path) == .regular { unlink(url.path) }
    }

    static func parseHex(_ s: String) -> [UInt8]? {
        let chars = Array(s.utf8)
        guard chars.count == FLProtocol.keyLength * 2 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(FLProtocol.keyLength)
        var i = 0
        while i < chars.count {
            guard let hi = hexValue(chars[i]), let lo = hexValue(chars[i + 1]) else { return nil }
            out.append(hi << 4 | lo)
            i += 2
        }
        return out
    }

    private static func hexValue(_ c: UInt8) -> UInt8? {
        switch c {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return c - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): return c - UInt8(ascii: "a") + 10
        default: return nil
        }
    }
}

/// Trousseau d'abord, fichier 0600 en repli (PROTOCOL.md §2).
final class PreferredSecretStore: SecretStore {
    private let primary: SecretStore
    private let fallback: SecretStore

    init(primary: SecretStore = KeychainSecretStore(), fallback: SecretStore = FileSecretStore()) {
        self.primary = primary
        self.fallback = fallback
    }

    func load() -> [UInt8]? { primary.load() ?? fallback.load() }

    func save(_ key: [UInt8]) throws {
        do {
            try primary.save(key)
            fallback.delete()
        } catch {
            try fallback.save(key)
        }
    }

    func delete() {
        primary.delete()
        fallback.delete()
    }
}

/// Chemins de l'appli (calculés une fois, REL-21).
enum AppPaths {
    /// Nom de l'app et de ses dossiers avant « FL Shortcuts ».
    static let oldName = "FL Shortcut"

    static let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return renamed(base.appendingPathComponent(oldName, isDirectory: true),
                       to: base.appendingPathComponent("FL Shortcuts", isDirectory: true))
    }()

    /// Dossier à l'ancien nom de l'app : s'il existe (un vrai dossier, jamais un lien) et que le nouveau n'existe pas
    /// encore, il prend le nouveau nom, avec tout son contenu (rename(2) : même volume, rien n'est copié). Si c'est
    /// impossible, l'ancien reste utilisé : rien n'est perdu, le renommage sera retenté au prochain lancement.
    static func renamed(_ old: URL, to new: URL) -> URL {
        guard SecureFile.kind(at: new.path) == .none, SecureFile.kind(at: old.path) == .directory else { return new }
        return rename(old.path, new.path) == 0 ? new : old
    }

    static var profileURL: URL { supportDirectory.appendingPathComponent("profile.json") }
    /// Bibliothèque des macros en blocs (MacroLibraryStore.swift).
    static var macrosURL: URL { supportDirectory.appendingPathComponent("macros.json") }
}
