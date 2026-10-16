import XCTest
@testable import FLShortcut

/// Faux serveur Supabase : renvoie les réponses prévues dans l'ordre et garde les requêtes reçues.
private final class FakeServer: CommunityTransport {
    var replies: [(Int, String)]
    private(set) var requests: [URLRequest] = []

    init(_ replies: [(Int, String)]) { self.replies = replies }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        requests.append(request)
        guard !replies.isEmpty else { return (Data(), 500) }
        let (status, body) = replies.removeFirst()
        return (Data(body.utf8), status)
    }

    func body(_ i: Int) -> [String: Any] {
        (requests[i].httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
    }

    func query(_ i: Int) -> [String: String] {
        let items = URLComponents(url: requests[i].url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { a, _ in a })
    }
}

final class CommunityTests: XCTestCase {
    private let config = CommunityConfig(url: URL(string: "https://exemple.supabase.co")!, anonKey: "cle-anon")
    private let userID = UUID()

    private var tokenJSON: String {
        """
        {"access_token":"jeton","refresh_token":"rafraichir","expires_in":3600,
         "user":{"id":"\(userID.uuidString)","email":"malo@example.com",
                 "user_metadata":{"username":"malo","email_verified":true}}}
        """
    }

    private func client(_ server: FakeServer) -> CommunityClient {
        CommunityClient(config: config, transport: server, now: { Date(timeIntervalSince1970: 1000) })
    }

    private var session: CommunitySession {
        CommunitySession(accessToken: "jeton", refreshToken: "r", expiresAt: .distantFuture, userID: userID,
                         email: "malo@example.com", username: "malo")
    }

    func testSignInSendsCredentialsAndReadsSession() async throws {
        let server = FakeServer([(200, tokenJSON)])
        let s = try await client(server).signIn(email: "malo@example.com", password: "motdepasse")
        XCTAssertEqual(s.username, "malo", "métadonnées avec un booléen (email_verified) lues quand même")
        XCTAssertEqual(s.userID, userID)
        XCTAssertEqual(s.expiresAt, Date(timeIntervalSince1970: 4600))
        let r = server.requests[0]
        XCTAssertEqual(r.url?.path, "/auth/v1/token")
        XCTAssertEqual(server.query(0)["grant_type"], "password")
        XCTAssertEqual(r.value(forHTTPHeaderField: "apikey"), "cle-anon")
        XCTAssertEqual(server.body(0)["password"] as? String, "motdepasse")
    }

    /// Clés de Supabase : l'ancienne clé « anon » (un JWT) sert aussi de jeton sans compte ; la nouvelle clé publique
    /// (« sb_publishable_… ») n'est envoyée qu'en « apikey » ; un compte connecté envoie toujours son jeton.
    func testKeysAndBearer() throws {
        let legacy = CommunityClient(config: CommunityConfig(url: config.url, anonKey: "eyJhbGciOi.anon"))
        XCTAssertEqual(try legacy.request("POST", "auth/v1/recover").value(forHTTPHeaderField: "Authorization"),
                       "Bearer eyJhbGciOi.anon")
        let publishable = CommunityClient(config: CommunityConfig(url: config.url, anonKey: "sb_publishable_abc"))
        let anonymous = try publishable.request("POST", "auth/v1/recover")
        XCTAssertEqual(anonymous.value(forHTTPHeaderField: "apikey"), "sb_publishable_abc")
        XCTAssertNil(anonymous.value(forHTTPHeaderField: "Authorization"))
        XCTAssertEqual(try publishable.request("GET", "rest/v1/shares", token: "jeton")
            .value(forHTTPHeaderField: "Authorization"), "Bearer jeton")
    }

    func testSignUpChecksUsernameThenSendsIt() async throws {
        let server = FakeServer([(200, "true"), (200, tokenJSON)])
        _ = try await client(server).signUp(email: "malo@example.com", password: "motdepasse", username: "malo")
        XCTAssertEqual(server.requests[0].url?.path, "/rest/v1/rpc/username_available")
        XCTAssertEqual(server.body(0)["name"] as? String, "malo")
        XCTAssertEqual((server.body(1)["data"] as? [String: String])?["username"], "malo")
    }

    func testSignUpRefusals() async throws {
        let taken = FakeServer([(200, "false")])
        do {
            _ = try await client(taken).signUp(email: "malo@example.com", password: "motdepasse", username: "malo")
            XCTFail("nom pris accepté")
        } catch CommunityError.invalid(let why) {
            XCTAssertTrue(why.contains("déjà pris"))
        }
        XCTAssertEqual(taken.requests.count, 1, "aucune inscription envoyée")

        let none = FakeServer([])
        for (mail, pass, name) in [("pas-un-mail", "motdepasse", "malo"), ("malo@example.com", "court", "malo"),
                                   ("malo@example.com", "motdepasse", "é!"), ("malo@example.com", "motdepasse", "ab")] {
            do {
                _ = try await client(none).signUp(email: mail, password: pass, username: name)
                XCTFail("accepté : \(mail) \(name)")
            } catch CommunityError.invalid {}
        }
        XCTAssertTrue(none.requests.isEmpty, "rien n'est envoyé pour des champs invalides")
    }

    /// Confirmation du mail activée : l'inscription ne renvoie pas de session.
    func testSignUpWithEmailToConfirm() async throws {
        let server = FakeServer([(200, "true"), (200, #"{"id":"\#(userID.uuidString)","email":"malo@example.com"}"#)])
        do {
            _ = try await client(server).signUp(email: "malo@example.com", password: "motdepasse", username: "malo")
            XCTFail("session inventée")
        } catch CommunityError.emailToConfirm {}
    }

    func testListUsesTokenFiltersAndSafeSearch() async throws {
        let row = """
        [{"id":"\(UUID().uuidString)","author_id":"\(userID.uuidString)","kind":"macro","title":"Armer vite",
          "notes":"Clique la piste puis ⌃R","app_version":"0.1.0","created_at":"2026-10-16T18:02:11+00:00",
          "author":{"username":"malo"}}]
        """
        let server = FakeServer([(200, row)])
        let list = try await client(server).shares(kind: .macro, search: "arm*,(x)", session: session)
        XCTAssertEqual(list.first?.authorName, "malo")
        XCTAssertEqual(server.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer jeton")
        let q = server.query(0)
        XCTAssertEqual(q["kind"], "eq.macro")
        XCTAssertEqual(q["or"], "(title.ilike.*armx*,notes.ilike.*armx*)", "* , ( ) retirés de la recherche")
        XCTAssertEqual(q["limit"], "50")
    }

    func testPublishValidatesBeforeSending() async throws {
        let server = FakeServer([(201, "")])
        let file = Data(#"{"format":"flsmacro"}"#.utf8)
        try await client(server).publish(kind: .macro, title: "  Armer vite  ", notes: "Notes", payload: file,
                                         appVersion: "0.1.0", session: session)
        XCTAssertEqual(server.body(0)["title"] as? String, "Armer vite")
        XCTAssertEqual(server.body(0)["kind"] as? String, "macro")
        XCTAssertEqual(server.body(0)["payload"] as? String, #"{"format":"flsmacro"}"#)

        let big = Data(repeating: 65, count: CommunityRules.maxPayload + 1)
        for (title, payload) in [("ab", file), ("Titre correct", big)] {
            do {
                try await client(server).publish(kind: .macro, title: title, notes: "", payload: payload,
                                                 appVersion: "0.1.0", session: session)
                XCTFail("accepté : \(title)")
            } catch CommunityError.invalid {}
        }
        XCTAssertEqual(server.requests.count, 1)
    }

    func testServerMessagesAreReadable() {
        func msg(_ json: String, _ status: Int) -> String { CommunityClient.message(Data(json.utf8), status: status) }
        XCTAssertEqual(msg(#"{"error_description":"Invalid login credentials"}"#, 400), "Mail ou mot de passe incorrect.")
        XCTAssertEqual(msg(#"{"msg":"Email not confirmed"}"#, 400),
                       "Confirme d'abord ton adresse mail (lien reçu par mail).")
        XCTAssertEqual(msg(#"{"msg":"User already registered"}"#, 422), "Un compte existe déjà avec ce mail.")
        XCTAssertEqual(msg("", 401), "Session expirée : reconnecte-toi.")
        XCTAssertEqual(msg("", 429), "Trop de tentatives : réessaie dans quelques minutes.")
    }

    func testConfigNeedsHTTPS() {
        let d = UserDefaults.standard
        defer { d.removeObject(forKey: "communityURL"); d.removeObject(forKey: "communityAnonKey") }
        d.set("http://exemple.supabase.co", forKey: "communityURL")
        d.set("cle", forKey: "communityAnonKey")
        XCTAssertNil(CommunityConfig.current, "jamais en clair")
        d.set("https://exemple.supabase.co", forKey: "communityURL")
        XCTAssertEqual(CommunityConfig.current?.anonKey, "cle")
    }

    func testDayFormat() {
        XCTAssertEqual(CommunityText.day("2026-10-16T18:02:11+00:00"), "16/10/2026")
    }

    /// Mode capture de la mesure : exemples affichés, aucune requête (serveur vide), Trousseau jamais touché.
    @MainActor
    func testDemoNeverUsesServerOrKeychain() async {
        let server = FakeServer([])
        let keychain = CommunitySessionKeychain(service: "app.flshortcut.tests.\(UUID().uuidString)")
        let community = CommunityStore(config: config, keychain: keychain, transport: server)
        community.showDemo(signedIn: false)
        XCTAssertTrue(community.isConfigured)
        XCTAssertNil(community.session)
        community.showDemo(signedIn: true)
        XCTAssertEqual(community.session?.username, "malo")
        XCTAssertEqual(community.shares.count, 4)
        XCTAssertEqual(community.shares.filter(community.isMine).count, 1, "un partage à soi, avec son badge")
        await community.open()
        await community.reload()
        await community.signIn(email: "malo@example.com", password: "motdepasse")
        XCTAssertEqual(community.shares.count, 4)
        XCTAssertTrue(server.requests.isEmpty, "aucune requête en mode capture")
        XCTAssertNil(keychain.load())
        await community.signOut()
        XCTAssertNil(community.session)
        XCTAssertTrue(server.requests.isEmpty)
    }

    func testByline() {
        let share = Share(id: UUID(), authorID: UUID(), kind: .macro, title: "Armer la piste", notes: "",
                          appVersion: "0.1.0", createdAt: "2026-10-15T18:02:11Z", author: Share.Author(username: "leo"))
        XCTAssertEqual(CommunityText.byline(share), "Macro · par @leo · 15/10/2026")
    }
}
