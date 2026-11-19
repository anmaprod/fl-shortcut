import CryptoKit
import XCTest
@testable import FLShortcut

/// Mises à jour toutes seules (19/11) : seul un manifeste signé de la clé de l'app, plus récent, venu des releases du
/// dépôt, est pris ; posé seulement quand FL est fermé et qu'aucune fenêtre n'est ouverte.
final class AutoUpdateTests: XCTestCase {
    private let manifest = Data("""
    {"version":"0.4.0","mac":{"url":"https://github.com/anmaprod/fl-shortcut/releases/download/v0.4.0/FLShortcuts-mac.zip","sha256":"ab"},"windows":null}
    """.utf8)

    func testTheAppKeyIsReadable() throws {
        XCTAssertNoThrow(try P256.Signing.PublicKey(pemRepresentation: UpdateRules.publicKeyPEM))
    }

    /// Signé comme la CI (openssl dgst -sha256 -sign, clé UPDATE_SIGNING_KEY) : la clé de l'app le lit. Version 0.0.0,
    /// sans fichier : jamais une mise à jour.
    func testASignatureMadeLikeTheCIIsAccepted() {
        let data = Data(#"{"version":"0.0.0","mac":null,"windows":null}"#.utf8)
        let signature = Data("MEUCIEEHgoA//ukZM3+Osf1UEaxdYGZF41HKnRGiR/pjI7C+AiEAjYq22oU7o1M3LKMCyo2b/KwjYo7JnO6gzvB+Q3POeAA=".utf8)
        XCTAssertEqual(UpdateRules.verified(data, signature: signature)?.version, "0.0.0")
    }

    func testOnlyASignatureOfTheKeyIsAccepted() throws {
        let key = P256.Signing.PrivateKey()
        let signature = Data(try key.signature(for: manifest).derRepresentation.base64EncodedString().utf8)
        let pem = key.publicKey.pemRepresentation
        let read = UpdateRules.verified(manifest, signature: signature, publicKeyPEM: pem)
        XCTAssertEqual(read?.version, "0.4.0")
        XCTAssertEqual(read?.mac?.sha256, "ab")
        var tampered = manifest
        tampered[tampered.startIndex + 15] = UInt8(ascii: "9")
        XCTAssertNil(UpdateRules.verified(tampered, signature: signature, publicKeyPEM: pem), "manifeste changé")
        XCTAssertNil(UpdateRules.verified(manifest, signature: signature, publicKeyPEM: P256.Signing.PrivateKey().publicKey.pemRepresentation),
                     "autre clé")
        XCTAssertNil(UpdateRules.verified(manifest, signature: signature), "pas la clé de l'app")
        XCTAssertNil(UpdateRules.verified(manifest, signature: Data("pas une signature".utf8), publicKeyPEM: pem))
    }

    func testVersionsCompareNumberByNumber() {
        XCTAssertTrue(UpdateRules.isNewer("0.4.0", than: "0.3.9"))
        XCTAssertTrue(UpdateRules.isNewer("0.10.0", than: "0.9.0"))
        XCTAssertTrue(UpdateRules.isNewer("1.0.0", than: "0.99.99"))
        XCTAssertFalse(UpdateRules.isNewer("0.4.0", than: "0.4.0"))
        XCTAssertFalse(UpdateRules.isNewer("0.3.0", than: "0.4.0"))
        XCTAssertFalse(UpdateRules.isNewer("0.4", than: "0.3.0"))
        XCTAssertFalse(UpdateRules.isNewer("0.4.0-beta", than: "0.3.0"))
        XCTAssertFalse(UpdateRules.isNewer("0.4.0", than: "?"))
    }

    func testFilesComeOnlyFromTheReleasesOfTheRepository() {
        XCTAssertNotNil(UpdateRules.downloadURL("https://github.com/anmaprod/fl-shortcut/releases/download/v0.4.0/FLShortcuts-mac.zip"))
        XCTAssertNil(UpdateRules.downloadURL("http://github.com/anmaprod/fl-shortcut/releases/download/v0.4.0/a.zip"))
        XCTAssertNil(UpdateRules.downloadURL("https://example.com/anmaprod/fl-shortcut/releases/download/v0.4.0/a.zip"))
        XCTAssertNil(UpdateRules.downloadURL("https://github.com/autre/depot/releases/download/v0.4.0/a.zip"))
        XCTAssertNil(UpdateRules.downloadURL("https://github.com/anmaprod/fl-shortcut/releases/download/../../x.zip"))
    }

    func testChecksumAndWhenToInstall() {
        XCTAssertEqual(UpdateRules.sha256Hex(Data("abc".utf8)),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertTrue(UpdateRules.canInstall(flRunning: false, windowOpen: false))
        XCTAssertFalse(UpdateRules.canInstall(flRunning: true, windowOpen: false), "jamais pendant une session de FL")
        XCTAssertFalse(UpdateRules.canInstall(flRunning: false, windowOpen: true), "jamais sous les yeux")
    }

    /// Une version d'essai (ni tag ni Info.plist « release ») ne se met jamais à jour toute seule.
    func testTestBuildsNeverUpdate() {
        XCTAssertFalse(AutoUpdate.enabled)
    }
}
