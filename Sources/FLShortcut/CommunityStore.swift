// Communauté : état de la page (session, liste, recherche) et actions, sur le thread principal. Une session est
// gardée au Trousseau ; rien n'est demandé au serveur tant que la page Communauté n'est pas ouverte.
import Foundation
import Security

/// Session au Trousseau (élément générique de FL Shortcut, compte « community-session »).
final class CommunitySessionKeychain {
    private let service: String
    private let account: String

    init(service: String = "app.flshortcut.FLShortcut", account: String = "community-session") {
        self.service = service
        self.account = account
    }

    private var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    func load() -> CommunitySession? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return try? JSONDecoder().decode(CommunitySession.self, from: data)
    }

    func save(_ session: CommunitySession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        if SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary) == errSecItemNotFound {
            var add = query
            add[kSecValueData as String] = data
            add[kSecAttrLabel as String] = "FL Shortcut – session de la Communauté"
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    func delete() { SecItemDelete(query as CFDictionary) }
}

@MainActor
final class CommunityStore: ObservableObject {
    static let shared = CommunityStore()

    @Published private(set) var session: CommunitySession?
    @Published private(set) var shares: [Share] = []
    @Published private(set) var busy = false
    @Published private(set) var isAdmin = false
    @Published var error: String?
    @Published var notice: String?
    @Published var kind: ShareKind?
    @Published var search = ""
    /// Feuille « Partager » ouverte (bouton de la page ou « + » de la barre d'outils).
    @Published var composing = false
    /// Écran de connexion : « Créer un compte » plutôt que « J'ai déjà un compte ».
    @Published var creatingAccount = false
    /// Mode capture seulement (mesure de la CI) : exemples affichés tels quels, sans serveur ni Trousseau.
    @Published private(set) var demo = false

    let client: CommunityClient?
    private let keychain: CommunitySessionKeychain
    private var restored = false

    init(config: CommunityConfig? = .current, keychain: CommunitySessionKeychain = CommunitySessionKeychain(),
         transport: CommunityTransport = URLSessionTransport()) {
        client = config.map { CommunityClient(config: $0, transport: transport) }
        self.keychain = keychain
    }

    var isConfigured: Bool { client != nil || demo }

    /// Ouverture de la page : session du Trousseau reprise (rafraîchie), puis la liste.
    func open() async {
        guard !demo, let client else { return }
        if !restored {
            restored = true
            if let saved = keychain.load() {
                do { set(try await client.refresh(saved)) } catch { set(nil) }
            }
        }
        if session != nil { await reload() }
    }

    func signIn(email: String, password: String) async {
        await run { client in self.set(try await client.signIn(email: email, password: password)) }
        if session != nil { await reload() }
    }

    func signUp(email: String, password: String, username: String) async {
        await run { client in
            do {
                self.set(try await client.signUp(email: email, password: password, username: username))
            } catch CommunityError.emailToConfirm {
                self.notice = CommunityError.emailToConfirm.errorDescription
            }
        }
        if session != nil { await reload() }
    }

    func resetPassword(email: String) async {
        await run { client in
            try await client.resetPassword(email: email)
            self.notice = "Si un compte existe avec ce mail, un lien pour changer le mot de passe vient d'y être envoyé."
        }
    }

    func signOut() async {
        guard !demo else {
            session = nil
            shares = []
            return
        }
        if let client, let session { await client.signOut(session) }
        set(nil)
        shares = []
    }

    func reload() async {
        guard !demo else { return }
        await authed { client, session in
            self.shares = try await client.shares(kind: self.kind, search: self.search, session: session)
        }
    }

    func publish(kind: ShareKind, title: String, notes: String, payload: Data) async -> Bool {
        var ok = false
        await authed { client, session in
            try await client.publish(kind: kind, title: title, notes: notes, payload: payload,
                                     appVersion: MacroFileActions.appVersion, session: session)
            ok = true
        }
        if ok {
            notice = "Partage publié."
            await reload()
        }
        return ok
    }

    func payload(of share: Share) async -> Data? {
        if demo { return Self.demoPayload(share.kind) }
        var data: Data?
        await authed { client, session in data = try await client.payload(of: share.id, session: session) }
        return data
    }

    func delete(_ share: Share) async {
        await authed { client, session in try await client.delete(share.id, session: session) }
        await reload()
    }

    func report(_ share: Share, reason: String) async {
        await authed { client, session in
            try await client.report(share.id, reason: reason, session: session)
            self.notice = "Merci, le signalement est envoyé."
        }
    }

    func isMine(_ share: Share) -> Bool { share.authorID == session?.userID }

    /// Peut supprimer ce partage : le sien, ou n'importe lequel pour un administrateur.
    func canDelete(_ share: Share) -> Bool { isMine(share) || isAdmin }

    // MARK: Interne

    private func set(_ new: CommunitySession?) {
        let changedUser = new?.userID != session?.userID
        session = new
        if let new { keychain.save(new) } else { keychain.delete() }
        guard changedUser else { return }
        isAdmin = false
        if let new, let client { Task { self.isAdmin = await client.isAdmin(session: new) } }
    }

    /// Une action, avec l'indicateur d'activité et l'erreur affichée.
    private func run(_ body: (CommunityClient) async throws -> Void) async {
        if demo { return }                                // mode capture : aucune requête
        guard let client else {
            error = CommunityError.notConfigured.errorDescription
            return
        }
        busy = true
        error = nil
        notice = nil
        defer { busy = false }
        do {
            try await body(client)
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Une action qui demande un compte : jeton rafraîchi s'il expire dans la minute ; session expirée, retour
    /// à l'écran de connexion.
    private func authed(_ body: (CommunityClient, CommunitySession) async throws -> Void) async {
        await run { client in
            guard var current = self.session else { throw CommunityError.invalid("Connecte-toi d'abord.") }
            if current.expiresAt < Date().addingTimeInterval(60) {
                do {
                    current = try await client.refresh(current)
                    self.set(current)
                } catch {
                    self.set(nil)
                    throw CommunityError.invalid("Session expirée : reconnecte-toi.")
                }
            }
            try await body(client, current)
        }
    }

    // MARK: Mode capture

    /// Exemples de la mesure de la CI : `signedIn` connecté en « malo » (avec un partage à lui), `empty` sans partage.
    /// Rien n'est envoyé ni gardé : ni serveur, ni Trousseau.
    func showDemo(signedIn: Bool, empty: Bool = false) {
        demo = true
        error = nil
        notice = nil
        session = signedIn ? CommunitySession(accessToken: "", refreshToken: "", expiresAt: .distantFuture,
                                              userID: Self.demoUser, email: "malo@exemple.fr", username: "malo") : nil
        shares = signedIn && !empty ? Self.demoShares : []
    }

    private static let demoUser = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!

    private static func demoShare(_ n: Int, _ author: String, mine: Bool = false, _ kind: ShareKind, _ title: String,
                                  _ notes: String, _ day: String) -> Share {
        Share(id: UUID(uuidString: "00000000-0000-0000-0000-00000000010\(n)")!,
              authorID: mine ? demoUser : UUID(uuidString: "00000000-0000-0000-0000-00000000020\(n)")!,
              kind: kind, title: title, notes: notes, appVersion: "0.1.0", createdAt: day + "T18:02:11Z",
              author: Share.Author(username: author))
    }

    private static let demoShares: [Share] = [
        demoShare(1, "leo.beats", .macro, "Armer la piste et lancer l'enregistrement",
                  "Clique sur ta piste dans le Mixer, puis lance la macro : elle arme la piste et démarre le REC. "
                  + "Parfait pour enregistrer une voix sans chercher dans les menus.", "2026-10-15"),
        demoShare(2, "sarah.mix", .profile, "Raccourcis façon Ableton",
                  "Espace pour lecture, ⌘E pour couper, ⌘D pour dupliquer… Pour ceux qui viennent d'Ableton et "
                  + "ne veulent pas réapprendre.", "2026-10-14"),
        demoShare(3, "malo", mine: true, .macro, "Nommer et colorer la piste en vert",
                  "Renomme la piste choisie en « Lead » et la passe en vert.", "2026-10-13"),
        demoShare(4, "prod.nina", .macro, "Choisir l'interface USB dans les réglages audio",
                  "Ouvre Options › Audio settings et choisit ta carte son USB. À lancer quand FL a perdu ta carte.",
                  "2026-10-11"),
    ]

    private static func demoPayload(_ kind: ShareKind) -> Data? {
        switch kind {
        case .macro:
            let doc = MacroTemplates.sampleForCapture(layout: Store.shared.layout)
            return try? MacroExchange.export(doc, appVersion: MacroFileActions.appVersion)
        case .profile:
            return try? Store.shared.exportData()
        }
    }
}
