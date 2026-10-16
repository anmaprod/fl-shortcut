import XCTest
@testable import FLShortcut

/// Page Aide : règles d'envoi, message en texte (mail, copie, ticket public sans le mail), diagnostic sans rien de
/// personnel, recherche dans les questions fréquentes, requête au serveur avec ou sans compte.
final class SupportTests: XCTestCase {
    private final class Server: CommunityTransport {
        var status = 201
        private(set) var requests: [URLRequest] = []

        func send(_ request: URLRequest) async throws -> (Data, Int) {
            requests.append(request)
            return (Data(), status)
        }

        func body(_ i: Int) -> [String: Any] {
            (requests[i].httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
        }
    }

    private let message = SupportMessage(kind: .probleme, text: "Ma macro s'arrête au 3e bloc dans le Mixer.",
                                         email: "nina@exemple.fr", diagnostic: "FL Shortcut 0.1.0 · macOS 26.6.2")

    func testRules() {
        XCTAssertNil(SupportRules.problem(message))
        var m = message
        m.text = "Bug"
        XCTAssertNotNil(SupportRules.problem(m), "trop court")
        m = message
        m.email = ""
        XCTAssertNil(SupportRules.problem(m), "mail facultatif")
        m.email = "pas-un-mail"
        XCTAssertEqual(SupportRules.problem(m), "Adresse mail invalide.")
    }

    func testPlainTextMailAndIssue() throws {
        let text = SupportRules.plainText(message, appVersion: "0.1.0")
        XCTAssertTrue(text.hasPrefix("Un problème — FL Shortcut 0.1.0"))
        XCTAssertTrue(text.contains("Pour me répondre : nina@exemple.fr"))
        XCTAssertTrue(text.contains("— État de l'app —\nFL Shortcut 0.1.0"))
        var without = message
        without.diagnostic = nil
        XCTAssertFalse(SupportRules.plainText(without, appVersion: "0.1.0").contains("État de l'app"))

        let mail = try XCTUnwrap(SupportRules.mailURL(message, to: "equipe@exemple.fr", appVersion: "0.1.0"))
        XCTAssertEqual(mail.scheme, "mailto")
        XCTAssertTrue(mail.absoluteString.hasPrefix("mailto:equipe@exemple.fr?subject="))

        let issue = try XCTUnwrap(SupportRules.issueURL(message, appVersion: "0.1.0"))
        XCTAssertEqual(issue.host, "github.com")
        XCTAssertFalse(issue.absoluteString.contains("nina"), "ticket public : jamais le mail")
    }

    func testDiagnosticSaysTheStateOnly() {
        let facts = SupportDiagnostic.Facts(appVersion: "0.1.0", macOS: "macOS 26.6.2", flRunning: true, flVersion: "26.1.7",
                                            accessibility: false, staleTCC: true, secureInput: false, paused: false,
                                            light: true, link: "FL fermé", shortcuts: 4, macros: 3, macrosToLearn: 1,
                                            lastMacro: "échec — bloc 3", screens: ["1512×982", "2560×1440"])
        let text = SupportDiagnostic.text(facts)
        XCTAssertEqual(text, """
            FL Shortcut 0.1.0 · macOS 26.6.2
            FL Studio : ouvert (26.1.7)
            Clavier autorisé : non (autorisation périmée) · En pause : non · Saisie sécurisée : non
            Mode : léger (sans lien MIDI)
            Raccourcis modifiés ou ajoutés : 4 · Macros : 3 (1 à apprendre)
            Dernière macro : échec — bloc 3
            Écrans : 1512×982, 2560×1440
            """)
    }

    func testFAQSearch() {
        let ids = { (q: String) in HelpContent.faq.filter { $0.matches(q) }.map(\.id) }
        XCTAssertEqual(ids(""), HelpContent.faq.map(\.id))
        XCTAssertTrue(ids("pause").contains(7))
        XCTAssertTrue(ids("COMMUNAUTE").contains(8), "sans accents ni majuscules")
        XCTAssertTrue(ids("macro apprendre").contains(5), "tous les mots")
        XCTAssertEqual(ids("zzzz"), [])
        XCTAssertEqual(Set(HelpContent.faq.map(\.id)).count, HelpContent.faq.count)
    }

    func testSendWithAndWithoutAccount() async throws {
        let server = Server()
        let config = CommunityConfig(url: URL(string: "https://exemple.supabase.co")!, anonKey: "sb_publishable_abc")
        let client = CommunityClient(config: config, transport: server)
        try await client.sendSupport(message, appVersion: "0.1.0", token: nil)
        XCTAssertEqual(server.requests[0].url?.path, "/rest/v1/support_requests")
        XCTAssertEqual(server.requests[0].httpMethod, "POST")
        XCTAssertNil(server.requests[0].value(forHTTPHeaderField: "Authorization"), "sans compte : la clé publique seule")
        XCTAssertEqual(server.body(0)["kind"] as? String, "probleme")
        XCTAssertEqual(server.body(0)["email"] as? String, "nina@exemple.fr")
        XCTAssertEqual(server.body(0)["diagnostic"] as? String, "FL Shortcut 0.1.0 · macOS 26.6.2")
        try await client.sendSupport(message, appVersion: "0.1.0", token: "jeton")
        XCTAssertEqual(server.requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer jeton")

        var short = message
        short.text = "Bug"
        do {
            try await client.sendSupport(short, appVersion: "0.1.0", token: nil)
            XCTFail("message trop court envoyé")
        } catch {}
        XCTAssertEqual(server.requests.count, 2, "rien envoyé quand le message est refusé")
    }
}
