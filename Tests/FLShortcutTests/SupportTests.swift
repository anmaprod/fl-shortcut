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
                                         email: "nina@exemple.fr", error: "Macro : échec au bloc 3 (Clic)",
                                         diagnostic: "FL Shortcuts 0.1.0 · macOS 26.6.2", reference: "FLS-3F9A2C")

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
        XCTAssertEqual(text, """
            Référence : FLS-3F9A2C
            Genre : Un problème
            FL Shortcuts 0.1.0
            Pour répondre : nina@exemple.fr

            — Message —
            Ma macro s'arrête au 3e bloc dans le Mixer.

            — Le problème signalé —
            Macro : échec au bloc 3 (Clic)

            — État de l'app —
            FL Shortcuts 0.1.0 · macOS 26.6.2
            """)
        var without = message
        without.diagnostic = nil
        without.error = nil
        XCTAssertFalse(SupportRules.plainText(without, appVersion: "0.1.0").contains("État de l'app"))
        XCTAssertFalse(SupportRules.plainText(without, appVersion: "0.1.0").contains("problème signalé"))
        XCTAssertEqual(SupportRules.subject(message), "[FL Shortcuts] Problème · FLS-3F9A2C · Ma macro s'arrête au 3e bloc dans le Mixer.")
        XCTAssertTrue(SupportMessage.newReference().hasPrefix("FLS-"))
        XCTAssertEqual(SupportMessage.newReference().count, 10)

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
            FL Shortcuts 0.1.0 · macOS 26.6.2
            FL Studio : ouvert (26.1.7)
            Clavier autorisé : non (autorisation périmée) · En pause : non · Saisie sécurisée : non
            Mode : léger (sans lien MIDI)
            Raccourcis modifiés ou ajoutés : 4 · Macros : 3 (1 à apprendre)
            Dernière macro : échec — bloc 3
            Écrans : 1512×982, 2560×1440
            """)
    }

    func testReportSections() {
        let facts = SupportDiagnostic.Facts(appVersion: "0.1.0", macOS: "macOS 26.6.2", flRunning: false, flVersion: nil,
                                            accessibility: true, staleTCC: false, secureInput: false, paused: false,
                                            light: true, link: "FL fermé", shortcuts: 0, macros: 0, macrosToLearn: 0,
                                            lastMacro: nil, screens: [])
        let report = SupportDiagnostic.report(facts, problems: "16/10 21:07 · Macro : échec", journal: "RUN ==== Essai ====")
        XCTAssertTrue(report.hasPrefix("FL Shortcuts 0.1.0 · macOS 26.6.2\nFL Studio : fermé"))
        XCTAssertTrue(report.contains("\n\n— Derniers problèmes —\n16/10 21:07 · Macro : échec"))
        XCTAssertTrue(report.hasSuffix("\n\n— Journal de la dernière macro —\nRUN ==== Essai ===="))
        XCTAssertFalse(SupportDiagnostic.report(facts, problems: nil, journal: nil).contains("—"))
        XCTAssertLessThanOrEqual(SupportDiagnostic.report(facts, problems: nil, journal: String(repeating: "x", count: 50_000)).count,
                                 SupportRules.maxDiagnostic)
    }

    /// Derniers problèmes : gardés entre deux lancements, 20 au plus, le même texte dans la minute pas répété.
    func testProblemLog() {
        let suite = "app.flshortcut.tests.problemes.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let log = ProblemLog(defaults: defaults)
        XCTAssertNil(log.text)
        let t0 = Date(timeIntervalSince1970: 1_800_000_000)
        log.add("Macro : échec au bloc 3", date: t0)
        log.add("Macro : échec au bloc 3", date: t0.addingTimeInterval(20))
        XCTAssertEqual(log.all.count, 1, "même texte dans la minute")
        log.add("Macro : échec au bloc 3", date: t0.addingTimeInterval(120))
        XCTAssertEqual(log.all.count, 2)
        for i in 0..<30 { log.add("Problème \(i)", date: t0.addingTimeInterval(Double(200 + i))) }
        XCTAssertEqual(log.all.count, ProblemLog.maxEntries)
        XCTAssertEqual(log.all.last?.text, "Problème 29")
        XCTAssertEqual(ProblemLog(defaults: defaults).all, log.all, "gardés entre deux lancements")
        log.clear()
        XCTAssertNil(ProblemLog(defaults: defaults).text)
    }

    /// Journal joint : la dernière exécution seulement, début et fin si elle est longue.
    func testLastRunExcerpt() {
        let old = "t [aaaaaa] RUN   ==== Ancienne ====\nt [aaaaaa] END   Macro terminée"
        let lines = (1...100).map { "t [bbbbbb] STEP  \($0)" }
        let text = old + "\nt [bbbbbb] RUN   ==== Dernière ====\n" + lines.joined(separator: "\n")
        let excerpt = MacroLog.excerpt(of: text, maxLines: 20) ?? ""
        XCTAssertTrue(excerpt.hasPrefix("t [bbbbbb] RUN   ==== Dernière ===="))
        XCTAssertFalse(excerpt.contains("Ancienne"))
        XCTAssertTrue(excerpt.contains("… 81 lignes …"))
        XCTAssertTrue(excerpt.hasSuffix("STEP  100"))
        XCTAssertNil(MacroLog.excerpt(of: "rien", maxLines: 20))
        XCTAssertEqual(MacroLog.excerpt(of: old, maxLines: 20), old)
    }

    func testFAQSearch() {
        let ids = { (q: String) in HelpContent.faq.filter { $0.matches(q) }.map(\.id) }
        XCTAssertEqual(ids(""), HelpContent.faq.map(\.id))
        XCTAssertTrue(ids("pause").contains(7))
        XCTAssertTrue(ids("RECU LE CODE").contains(8), "sans accents ni majuscules")
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
        XCTAssertEqual(server.body(0)["diagnostic"] as? String, "FL Shortcuts 0.1.0 · macOS 26.6.2")
        XCTAssertEqual(server.body(0)["reference"] as? String, "FLS-3F9A2C")
        XCTAssertEqual(server.body(0)["error"] as? String, "Macro : échec au bloc 3 (Clic)")
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

    /// Réponse de l'aide en étapes numérotées (maquette du 30/10) : seulement « 1. … 2. … » à la suite.
    func testHelpAnswerSteps() {
        let parsed = HelpEntry.steps("Vérifie trois choses. 1. FL est devant. 2. Pas en pause. 3. Le clavier est autorisé.")
        XCTAssertEqual(parsed?.intro, "Vérifie trois choses.")
        XCTAssertEqual(parsed?.steps, ["FL est devant.", "Pas en pause.", "Le clavier est autorisé."])
        XCTAssertNil(HelpEntry.steps("Attends 1,5 s puis réessaie avec macOS 26. Rien d'autre."))
        XCTAssertNil(HelpEntry.steps("Une seule étape : 1. ouvre FL."))
        XCTAssertNil(HelpEntry.steps("2. avant 1. : pas une suite."))
        // La vraie première réponse de l'aide se découpe en ses trois étapes.
        let first = HelpContent.faq.first { $0.id == 1 }?.answer ?? ""
        XCTAssertEqual(HelpEntry.steps(first)?.steps.count, 3)
    }
}
