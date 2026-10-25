import XCTest
@testable import FLShortcut

/// Faux serveur Supabase : renvoie les réponses prévues dans l'ordre et garde les requêtes reçues.
private final class FakeServer: CommunityTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [(Int, String)]
    private var _requests: [URLRequest] = []
    /// Requêtes reçues ; protégées : la vérification d'administrateur part en parallèle de la liste.
    var requests: [URLRequest] { lock.lock(); defer { lock.unlock() }; return _requests }

    init(_ replies: [(Int, String)]) { self.replies = replies }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        lock.lock()
        defer { lock.unlock() }
        _requests.append(request)
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
        _ = try await client(server).signUp(email: "malo@example.com", password: "MotDePasse1!", username: "malo")
        XCTAssertEqual(server.requests[0].url?.path, "/rest/v1/rpc/username_available")
        XCTAssertEqual(server.body(0)["name"] as? String, "malo")
        XCTAssertEqual((server.body(1)["data"] as? [String: String])?["username"], "malo")
    }

    func testSignUpRefusals() async throws {
        let taken = FakeServer([(200, "false")])
        do {
            _ = try await client(taken).signUp(email: "malo@example.com", password: "MotDePasse1!", username: "malo")
            XCTFail("nom pris accepté")
        } catch CommunityError.invalid(let why) {
            XCTAssertTrue(why.contains("déjà pris"))
        }
        XCTAssertEqual(taken.requests.count, 1, "aucune inscription envoyée")

        let none = FakeServer([])
        for (mail, pass, name) in [("pas-un-mail", "MotDePasse1!", "malo"), ("malo@example.com", "court", "malo"),
                                   ("malo@example.com", "motdepasse", "malo"),
                                   ("malo@example.com", "MotDePasse1!", "é!"), ("malo@example.com", "MotDePasse1!", "ab")] {
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
            _ = try await client(server).signUp(email: "malo@example.com", password: "MotDePasse1!", username: "malo")
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

    /// Recherche d'un membre : seulement un nom d'utilisateur possible, parmi ceux qui ont publié, regroupé par auteur.
    func testMemberSearchFindsAuthorsByName() async throws {
        XCTAssertEqual(CommunityClient.memberPattern("@leo.beats"), "leo.beats")
        XCTAssertEqual(CommunityClient.memberPattern(" Nina_2 "), "Nina_2")
        XCTAssertNil(CommunityClient.memberPattern("l"), "un seul caractère")
        XCTAssertNil(CommunityClient.memberPattern("armer la piste"), "une phrase n'est pas un nom")
        XCTAssertNil(CommunityClient.memberPattern("léo"), "accent : pas un nom d'utilisateur")
        XCTAssertNil(CommunityClient.memberPattern("leo*,(x)"))

        let leo = UUID(), nina = UUID(), lea = UUID()
        let rows = """
        [{"author_id":"\(leo.uuidString)","author":{"username":"leo.beats"}},
         {"author_id":"\(nina.uuidString)","author":{"username":"nina.leon"}},
         {"author_id":"\(leo.uuidString)","author":{"username":"leo.beats"}},
         {"author_id":"\(lea.uuidString)","author":{"username":"Lea"}}]
        """
        let server = FakeServer([(200, rows)])
        let members = try await client(server).members(matching: "@le", session: session)
        XCTAssertEqual(members.map(\.username), ["leo.beats", "Lea", "nina.leon"], "les plus actifs, puis par nom")
        XCTAssertEqual(members.first?.shareCount, 2)
        XCTAssertEqual(members.first?.id, leo)
        let q = server.query(0)
        XCTAssertEqual(server.requests[0].url?.path, "/rest/v1/shares", "seuls ceux qui ont publié")
        XCTAssertEqual(q["select"], "author_id,author:profiles!inner(username)")
        XCTAssertEqual(q["author.username"], "ilike.*le*")
        XCTAssertEqual(server.requests[0].value(forHTTPHeaderField: "Authorization"), "Bearer jeton")

        let none = FakeServer([])
        let nothing = try await client(none).members(matching: "armer la piste", session: session)
        XCTAssertTrue(nothing.isEmpty)
        XCTAssertTrue(none.requests.isEmpty, "aucune requête pour une phrase")
        let many = (0..<12).map { (id: UUID(), username: "membre\($0)") }
        XCTAssertEqual(CommunityClient.members(many).count, 8)
    }

    func testListOfOneAuthor() async throws {
        let author = UUID()
        let server = FakeServer([(200, "[]")])
        _ = try await client(server).shares(kind: nil, search: "", authorID: author, session: session)
        XCTAssertEqual(server.query(0)["author_id"], "eq.\(author.uuidString.lowercased())")
        XCTAssertNil(server.query(0)["kind"])
    }

    /// Page : un membre choisi montre ses partages ; « Voir tout le monde » revient à la liste (mode capture).
    @MainActor
    func testAuthorFilterInDemo() async {
        let server = FakeServer([])
        let keychain = CommunitySessionKeychain(service: "app.flshortcut.tests.\(UUID().uuidString)")
        let community = CommunityStore(config: config, keychain: keychain, transport: server)
        community.showDemoMemberSearch("leo")
        XCTAssertEqual(community.members.map(\.username), ["leo.beats"])
        guard let leo = community.members.first else { return XCTFail("membre attendu") }
        await community.showAuthor(leo)
        XCTAssertEqual(community.author, leo)
        XCTAssertEqual(community.search, "", "la recherche a servi à le trouver")
        XCTAssertTrue(community.members.isEmpty)
        XCTAssertFalse(community.shares.isEmpty)
        XCTAssertTrue(community.shares.allSatisfy { $0.authorName == "leo.beats" })
        await community.showEveryone()
        XCTAssertNil(community.author)
        XCTAssertEqual(community.shares.count, 4)
        XCTAssertTrue(server.requests.isEmpty, "aucune requête en mode capture")
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

    /// Mêmes exigences que Supabase : 8 caractères, minuscule, majuscule, chiffre, symbole (lettres sans accent).
    func testPasswordRules() {
        XCTAssertNil(CommunityRules.passwordProblem("MotDePasse1!"))
        XCTAssertNil(CommunityRules.passwordProblem("aB3~xxxx"))
        XCTAssertEqual(CommunityRules.passwordMissing("motdepasse"), ["une majuscule", "un chiffre", "un symbole"])
        XCTAssertEqual(CommunityRules.passwordMissing("Ab1!"), ["4 caractères"])
        XCTAssertEqual(CommunityRules.passwordMissing("Abcdefg1!"), [])
        XCTAssertEqual(CommunityRules.passwordMissing("ÉÉÉÉÉé1!"), ["une minuscule", "une majuscule"],
                       "les lettres accentuées ne comptent pas, comme chez Supabase")
        XCTAssertEqual(CommunityRules.passwordMissing("Abcdefg1 "), ["un symbole"], "l'espace n'est pas un symbole")
        XCTAssertEqual(CommunityRules.passwordMissing("Abcdef1"), ["1 caractère", "un symbole"])
    }

    func testServerMessagesAreReadable() {
        func msg(_ json: String, _ status: Int) -> String { CommunityClient.message(Data(json.utf8), status: status) }
        XCTAssertEqual(msg(#"{"error_description":"Invalid login credentials"}"#, 400), "Mail ou mot de passe incorrect.")
        XCTAssertEqual(msg(#"{"msg":"Email not confirmed"}"#, 400),
                       CommunityClient.unconfirmedMessage)
        XCTAssertEqual(msg(#"{"msg":"User already registered"}"#, 422), "Un compte existe déjà avec ce mail.")
        XCTAssertEqual(msg(#"{"code":422,"error_code":"weak_password","msg":"Password should contain at least one character of each"}"#, 422),
                       "Mot de passe trop faible : \(CommunityRules.passwordRule).")
        XCTAssertTrue(msg(#"{"msg":"Error sending confirmation email"}"#, 500).hasPrefix("Le mail de confirmation n'a pas pu partir"))
        XCTAssertEqual(msg("", 401), "Session expirée : reconnecte-toi.")
        XCTAssertEqual(msg("", 429), "Trop de tentatives : réessaie dans quelques minutes.")
    }

    func testConfigNeedsHTTPS() throws {
        let suite = "config-\(UUID().uuidString)"
        let d = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite) }
        d.set("http://exemple.supabase.co", forKey: "communityURL")
        d.set("cle", forKey: "communityAnonKey")
        XCTAssertNil(CommunityConfig.resolve(info: nil, defaults: d), "jamais en clair")
        d.set("https://exemple.supabase.co", forKey: "communityURL")
        XCTAssertEqual(CommunityConfig.resolve(info: nil, defaults: d)?.anonKey, "cle", "app sans serveur : essai")
    }

    /// Audit du 25/10 : un autre programme du Mac écrit une adresse dans les réglages de l'app ; l'app qui a la sienne
    /// ne l'écoute jamais (sinon mot de passe, session et sauvegarde partaient chez lui).
    func testBuiltInServerCannotBeRedirected() throws {
        let suite = "config-\(UUID().uuidString)"
        let d = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite) }
        d.set("https://pirate.example", forKey: "communityURL")
        d.set("cle-pirate", forKey: "communityAnonKey")
        let info: [String: Any] = ["FLSCommunityURL": "https://vrai.supabase.co", "FLSCommunityAnonKey": "cle"]
        let config = CommunityConfig.resolve(info: info, defaults: d)
        XCTAssertEqual(config?.url.host, "vrai.supabase.co")
        XCTAssertEqual(config?.anonKey, "cle")
        XCTAssertNil(CommunityConfig.resolve(info: ["FLSCommunityURL": "https://moi:secret@vrai.supabase.co",
                                                    "FLSCommunityAnonKey": "cle"], defaults: d),
                     "jamais d'identifiants dans l'adresse")
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

    /// Codes reçus par mail : confirmation de l'inscription, puis mot de passe oublié (code + nouveau mot de passe).
    @MainActor
    func testCodesFromMail() async {
        XCTAssertEqual(CommunityRules.code(" 123 456 "), "123456")
        XCTAssertEqual(CommunityRules.code("12345678"), "12345678")
        XCTAssertNil(CommunityRules.code("12345"))
        XCTAssertNil(CommunityRules.code("abcdef"))
        XCTAssertNil(CommunityRules.code("١٢٣٤٥٦"), "chiffres latins seulement")

        let keychain = CommunitySessionKeychain(service: "app.flshortcut.tests.\(UUID().uuidString)")
        defer { keychain.delete() }
        let signup = FakeServer([(200, "true"), (200, #"{"id":"\#(userID.uuidString)","email":"malo@example.com"}"#),
                                 (200, tokenJSON)])
        let community = CommunityStore(config: config, keychain: keychain, transport: signup)
        await community.signUp(email: "malo@example.com", password: "MotDePasse1!", username: "malo")
        XCTAssertEqual(community.pendingCode, CommunityStore.PendingCode(kind: .signup, email: "malo@example.com"))
        XCTAssertNil(community.session)
        await community.confirmSignup(code: "123 456")
        XCTAssertEqual(signup.requests[2].url?.path, "/auth/v1/verify")
        XCTAssertEqual(signup.body(2)["type"] as? String, "signup")
        XCTAssertEqual(signup.body(2)["token"] as? String, "123456")
        XCTAssertEqual(community.session?.username, "malo")
        XCTAssertNil(community.pendingCode)

        let keychain2 = CommunitySessionKeychain(service: "app.flshortcut.tests.\(UUID().uuidString)")
        defer { keychain2.delete() }
        let reset = FakeServer([(200, "{}"), (200, tokenJSON), (200, "{}")])
        let forgot = CommunityStore(config: config, keychain: keychain2, transport: reset)
        await forgot.resetPassword(email: " malo@example.com ")
        XCTAssertEqual(reset.requests[0].url?.path, "/auth/v1/recover")
        XCTAssertEqual(forgot.pendingCode, CommunityStore.PendingCode(kind: .recovery, email: "malo@example.com"))
        await forgot.finishReset(code: "654321", newPassword: "faible")
        XCTAssertEqual(reset.requests.count, 1, "mot de passe refusé avant tout envoi")
        XCTAssertNotNil(forgot.error)
        await forgot.finishReset(code: "654321", newPassword: "NouveauMdp2!")
        XCTAssertEqual(reset.body(1)["type"] as? String, "recovery")
        XCTAssertEqual(reset.requests[2].httpMethod, "PUT")
        XCTAssertEqual(reset.requests[2].url?.path, "/auth/v1/user")
        XCTAssertEqual(reset.requests[2].value(forHTTPHeaderField: "Authorization"), "Bearer jeton")
        XCTAssertEqual(reset.body(2)["password"] as? String, "NouveauMdp2!")
        XCTAssertNotNil(forgot.session)
        XCTAssertNil(forgot.pendingCode)

        func msg(_ json: String) -> String { CommunityClient.message(Data(json.utf8), status: 403) }
        XCTAssertTrue(msg(#"{"error_code":"otp_expired","msg":"Token has expired or is invalid"}"#).hasPrefix("Code incorrect ou expiré"))

        // Mail avec un lien au lieu d'un code : retour à la connexion, rien d'envoyé.
        let keychain3 = CommunitySessionKeychain(service: "app.flshortcut.tests.\(UUID().uuidString)")
        defer { keychain3.delete() }
        let linked = FakeServer([(200, "true"), (200, #"{"id":"\#(userID.uuidString)","email":"malo@example.com"}"#)])
        let byLink = CommunityStore(config: config, keychain: keychain3, transport: linked)
        byLink.creatingAccount = true
        await byLink.signUp(email: "malo@example.com", password: "MotDePasse1!", username: "malo")
        XCTAssertNotNil(byLink.pendingCode)
        byLink.confirmedByLink()
        XCTAssertNil(byLink.pendingCode)
        XCTAssertFalse(byLink.creatingAccount)
        XCTAssertEqual(byLink.notice, CommunityStore.confirmedByLinkNotice)
        XCTAssertEqual(linked.requests.count, 2)
    }

    func testByline() {
        let share = Share(id: UUID(), authorID: UUID(), kind: .macro, title: "Armer la piste", notes: "",
                          appVersion: "0.1.0", createdAt: "2026-10-15T18:02:11Z", author: Share.Author(username: "leo"))
        XCTAssertEqual(CommunityText.byline(share), "Macro · par @leo · 15/10/2026")
    }
}
