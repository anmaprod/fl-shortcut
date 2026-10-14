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
        case .keychain(let s): return "Trousseau indisponible (\(s))."
        case .invalidKey: return "Clé invalide."
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

/// Mot de passe générique du Trousseau de session.
final class KeychainSecretStore: SecretStore {
    private let service: String
    private let account: String

    init(service: String = "app.flshortcut.FLShortcut", account: String = "fl-script-key") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func load() -> [UInt8]? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data, data.count == FLProtocol.keyLength else { return nil }
        return [UInt8](data)
    }

    func save(_ key: [UInt8]) throws {
        guard key.count == FLProtocol.keyLength else { throw SecretStoreError.invalidKey }
        let data = Data(key)
        let update = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw SecretStoreError.keychain(update) }
        var add = baseQuery
        add[kSecValueData as String] = data
        add[kSecAttrLabel as String] = "FL Shortcut – clé du script FL Studio"
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess else { throw SecretStoreError.keychain(status) }
    }

    func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}

/// Repli : fichier 0600 dans « Application Support/FL Shortcut », jamais suivi s'il est un lien.
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
    static let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("FL Shortcut", isDirectory: true)
    }()

    static var profileURL: URL { supportDirectory.appendingPathComponent("profile.json") }
    /// Bibliothèque des macros en blocs (MacroLibraryStore.swift).
    static var macrosURL: URL { supportDirectory.appendingPathComponent("macros.json") }
}
