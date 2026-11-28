import Security
import XCTest
@testable import FLShortcut

/// Un seul élément du Trousseau pour la clé du script et la session du compte (retour de l'utilisateur : trop de
/// demandes d'accès au Trousseau).
final class KeychainVaultTests: XCTestCase {
    private func uniqueService() -> String { "app.flshortcut.tests.\(UUID().uuidString)" }

    /// Comptes des éléments du Trousseau de ce service (attributs seulement : aucun secret lu).
    private func accounts(_ service: String) -> [String] {
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service,
                                    kSecReturnAttributes as String: true,
                                    kSecMatchLimit as String: kSecMatchLimitAll]
        var items: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &items) == errSecSuccess,
              let list = items as? [[String: Any]] else { return [] }
        return list.compactMap { $0[kSecAttrAccount as String] as? String }.sorted()
    }

    private func addLegacy(_ service: String, account: String, data: Data) {
        let add: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                  kSecAttrService as String: service,
                                  kSecAttrAccount as String: account,
                                  kSecValueData as String: data]
        XCTAssertEqual(SecItemAdd(add as CFDictionary, nil), errSecSuccess)
    }

    private let session = CommunitySession(accessToken: "a", refreshToken: "r",
                                           expiresAt: Date(timeIntervalSince1970: 1000), userID: UUID(),
                                           email: "leo@example.com", username: "leo")

    func testKeyAndSessionShareOneItem() throws {
        let service = uniqueService()
        defer { KeychainVault.shared(service: service).deleteAll() }
        let keys = KeychainSecretStore(service: service)
        let sessions = CommunitySessionKeychain(service: service)
        let key = [UInt8](repeating: 7, count: FLProtocol.keyLength)
        try keys.save(key)
        sessions.save(session)
        XCTAssertEqual(keys.load(), key)
        XCTAssertEqual(sessions.load(), session)
        XCTAssertEqual(accounts(service), [KeychainVault.account], "un seul élément")
        XCTAssertEqual(CommunitySessionKeychain(service: service).load(), session, "même copie en mémoire")

        sessions.delete()
        XCTAssertNil(sessions.load())
        XCTAssertEqual(keys.load(), key, "la clé reste")
        keys.delete()
        XCTAssertEqual(accounts(service), [], "vide : l'élément est effacé")
        XCTAssertThrowsError(try keys.save([1, 2, 3]))
    }

    /// Les deux éléments des versions d'avant sont repris dans l'élément commun, puis effacés.
    func testOldItemsAreMerged() throws {
        let service = uniqueService()
        defer { KeychainVault.shared(service: service).deleteAll() }
        let key = [UInt8](repeating: 9, count: FLProtocol.keyLength)
        addLegacy(service, account: KeychainVault.legacyKeyAccount, data: Data(key))
        addLegacy(service, account: KeychainVault.legacySessionAccount, data: try JSONEncoder().encode(session))
        XCTAssertEqual(KeychainSecretStore(service: service).load(), key)
        XCTAssertEqual(CommunitySessionKeychain(service: service).load(), session)
        XCTAssertEqual(accounts(service), [KeychainVault.account])
    }

    /// Désinstallation : tout est effacé sans rien lire.
    func testDeleteAllRemovesOldAndNewItems() {
        let service = uniqueService()
        addLegacy(service, account: KeychainVault.legacyKeyAccount, data: Data(repeating: 1, count: 16))
        addLegacy(service, account: KeychainVault.account, data: Data("{}".utf8))
        KeychainVault.shared(service: service).deleteAll()
        XCTAssertEqual(accounts(service), [])
    }
}
