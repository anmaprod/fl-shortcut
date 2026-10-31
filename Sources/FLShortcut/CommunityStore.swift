// Compte et Communauté : session, liste, recherche et actions, sur le thread principal. Une session est gardée au
// Trousseau ; reprise au lancement seulement s'il y en a une (sauvegarde en ligne : AccountBackup), sinon rien n'est
// demandé au serveur.
import AppKit
import Foundation
import Security

/// Session au Trousseau, dans l'élément commun de FL Shortcuts (avec la clé du script : une seule demande d'accès).
final class CommunitySessionKeychain {
    private let vault: KeychainVault

    init(service: String = "app.flshortcut.FLShortcut") {
        vault = .shared(service: service)
    }

    func load() -> CommunitySession? { vault.read().session }

    func save(_ session: CommunitySession) {
        try? vault.update { $0.session = session }
    }

    func delete() {
        try? vault.update { $0.session = nil }
    }
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
    /// Membres dont le nom correspond à la recherche (parmi ceux qui ont publié).
    @Published private(set) var members: [CommunityMember] = []
    /// Membre dont on regarde les partages (choisi dans la recherche ou depuis un partage) ; nil : tout le monde.
    @Published private(set) var author: CommunityMember?
    /// Feuille « Partager » ouverte (bouton de la page ou « + » de la barre d'outils).
    @Published var composing = false
    /// Écran de connexion : « Créer un compte » plutôt que « J'ai déjà un compte ».
    @Published var creatingAccount = false
    /// Un code est attendu (reçu par mail) : confirmation de l'inscription ou mot de passe oublié.
    @Published var pendingCode: PendingCode? {
        didSet { if pendingCode != oldValue { recoverySession = nil } }
    }
    /// Mot de passe oublié : session obtenue avec le code (utilisable une seule fois), gardée si le nouveau mot de
    /// passe est refusé (le même que l'ancien, réseau) pour réessayer sans redemander de code.
    private var recoverySession: CommunitySession?

    struct PendingCode: Equatable {
        let kind: CommunityClient.CodeKind
        let email: String
    }
    /// Mode capture seulement (mesure de la CI) : exemples affichés tels quels, sans serveur ni Trousseau.
    @Published private(set) var demo = false
    /// Photos des membres déjà chargées (Mon compte, Communauté) ; membre absent : pas de photo, son initiale.
    @Published private(set) var photos: [UUID: NSImage] = [:]
    private var photoVersions: [UUID: String] = [:]
    /// Feuille « Modifier le profil » ouverte (page Mon compte, photo de la barre d'outils).
    @Published var editingProfile = false

    /// Un pseudo vérifié au fil de la frappe (inscription, « Modifier le profil »).
    enum NameCheck: Equatable {
        case empty
        case invalid(String)
        case checking
        case free
        case taken
        /// Le pseudo actuel du compte (majuscules près) : rien à vérifier.
        case mine
        /// Pas de réponse du serveur : il vérifiera à l'envoi.
        case unknown
    }

    /// Ce que « Enregistrer » fait de la photo.
    enum PhotoChange: Equatable {
        case keep
        case set(Data)
        case remove
    }

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
        await restoreSession()
        if session != nil { await reload() }
    }

    /// Session du Trousseau reprise une fois (lancement, page Communauté). Hors ligne : gardée telle quelle, le jeton
    /// sera rafraîchi à la prochaine demande ; refusée par le serveur : oubliée (reconnexion demandée).
    func restoreSession() async {
        guard !demo, let client, !restored else { return }
        restored = true
        guard let saved = keychain.load() else { return }
        do {
            set(try await client.refresh(saved))
        } catch let error as CommunityError where Self.sessionRefused(error) {
            set(nil)                                      // jeton refusé : reconnexion demandée
        } catch {
            session = saved                               // hors ligne, serveur en panne : gardée, réessayée plus tard
        }
    }

    /// Session prête pour une requête : jeton rafraîchi s'il expire dans la minute. Refus du serveur : session
    /// oubliée et erreur « reconnecte-toi » ; hors ligne : l'erreur de connexion, session gardée.
    func validSession() async throws -> CommunitySession {
        guard let client, var current = session else {
            throw CommunityError.invalid(String(localized: "Connecte-toi d'abord."))
        }
        if current.expiresAt < Date().addingTimeInterval(60) {
            do {
                current = try await client.refresh(current)
                set(current)
            } catch let error as CommunityError where Self.sessionRefused(error) {
                set(nil)
                throw CommunityError.invalid(String(localized: "Session expirée : reconnecte-toi."))
            }
        }
        return current
    }

    /// Le serveur refuse le jeton de rafraîchissement (expiré, révoqué) : seul cas où la session est oubliée ; une
    /// panne (5xx), une limite (429) ou une réponse illisible la gardent.
    static func sessionRefused(_ error: CommunityError) -> Bool {
        if case .server(let code, _) = error { return [400, 401, 403].contains(code) }
        return false
    }

    /// Oublie la session sans rien demander au serveur (compte supprimé).
    func forgetSession() {
        set(nil)
        shares = []
    }

    func signIn(email: String, password: String) async {
        await run { client in
            do {
                self.set(try await client.signIn(email: email, password: password))
            } catch CommunityError.emailToConfirm {
                // Compte jamais confirmé (code pas tapé, app relancée…) : un nouveau code, et l'écran pour le taper.
                try? await client.resendSignupCode(email: email)
                self.pendingCode = PendingCode(kind: .signup, email: email)
                self.notice = String(localized: "Ton compte n'est pas encore confirmé : un code vient de partir à \(email).")
            }
        }
        if session != nil { await reload() }
    }

    func signUp(email: String, password: String, username: String) async {
        await run { client in
            do {
                self.set(try await client.signUp(email: email, password: password, username: username))
            } catch CommunityError.emailToConfirm {
                self.pendingCode = PendingCode(kind: .signup, email: email)
                self.notice = String(localized: "Un code vient de partir à \(email) : entre-le ici pour confirmer ton compte.")
            }
        }
        if session != nil { await reload() }
    }

    func resetPassword(email: String) async {
        let mail = email.trimmingCharacters(in: .whitespaces)
        await run { client in
            try await client.resetPassword(email: mail)
            self.pendingCode = PendingCode(kind: .recovery, email: mail)
            self.notice = String(localized: """
                Si un compte existe avec ce mail, un code vient d'y partir : entre-le ici avec ton nouveau mot de passe.
                """)
        }
    }

    /// Code de confirmation de l'inscription : le compte est confirmé et connecté.
    func confirmSignup(code: String) async {
        guard let pending = pendingCode, pending.kind == .signup else { return }
        await run { client in
            self.set(try await client.verifyCode(email: pending.email, code: code, kind: .signup))
            self.pendingCode = nil
            self.notice = nil
        }
        if session != nil { await reload() }
    }

    /// Mot de passe oublié : le code connecte le compte, puis le nouveau mot de passe est enregistré.
    func finishReset(code: String, newPassword: String) async {
        guard let pending = pendingCode, pending.kind == .recovery else { return }
        if let why = CommunityRules.passwordProblem(newPassword) {
            error = why
            return
        }
        var changed = false
        await run { client in
            let session: CommunitySession
            if let kept = self.recoverySession {
                session = kept
            } else {
                session = try await client.verifyCode(email: pending.email, code: code, kind: .recovery)
                self.recoverySession = session
            }
            try await client.updatePassword(newPassword, session: session)
            self.set(session)
            self.pendingCode = nil
            changed = true
        }
        if session != nil { await reload() }
        if changed { notice = String(localized: "Mot de passe changé : tu es connecté.") }   // après reload, qui efface les messages
    }

    /// Un nouveau code (il n'est pas arrivé, ou il a expiré).
    func resendCode() async {
        guard let pending = pendingCode else { return }
        await run { client in
            switch pending.kind {
            case .signup: try await client.resendSignupCode(email: pending.email)
            case .recovery: try await client.resetPassword(email: pending.email)
            }
            self.notice = String(localized: "Nouveau code envoyé à \(pending.email).")
        }
    }

    /// Retour à l'écran de connexion (mauvaise adresse…).
    func cancelCode() {
        pendingCode = nil
        recoverySession = nil
        error = nil
        notice = nil
    }

    /// Le mail d'inscription contenait un lien au lieu d'un code (modèles de Supabase pas encore changés) : cliquer
    /// dessus confirme l'adresse, même si la page qui s'ouvre ensuite ne s'affiche pas. Retour à la connexion.
    func confirmedByLink() {
        cancelCode()
        creatingAccount = false
        notice = Self.confirmedByLinkNotice
    }

    static let confirmedByLinkNotice = String(localized: """
        Si tu as cliqué sur le lien du mail, ton adresse est confirmée : connecte-toi avec ton mot de passe.
        """)

    func signOut() async {
        guard !demo else {
            session = nil
            shares = []
            return
        }
        if let client, let session { await client.signOut(session) }
        set(nil)
        shares = []
        members = []
        author = nil
        photos = [:]
        photoVersions = [:]
    }

    func reload() async {
        guard !demo else { return }
        await authed { client, session in
            self.shares = try await client.shares(kind: self.kind, search: self.search, authorID: self.author?.id,
                                                  session: session)
            // Membres : seulement pour une recherche sur tout le monde ; s'ils ne se chargent pas, les partages restent.
            if self.author == nil {
                self.members = (try? await client.members(matching: self.search, session: session)) ?? []
            } else {
                self.members = []
            }
        }
        // Photos des auteurs affichés (sans attendre : la liste est déjà là).
        let ids = shares.map(\.authorID) + members.map(\.id) + (author.map { [$0.id] } ?? [])
        if !ids.isEmpty { Task { await loadPhotos(for: ids) } }
    }

    /// Tous les partages d'un membre (la recherche est effacée : elle a servi à le trouver).
    func showAuthor(_ member: CommunityMember) async {
        author = member
        members = []
        search = ""
        if demo {
            shares = Self.demoShares.filter { $0.authorID == member.id }
            return
        }
        await reload()
    }

    func showAuthor(of share: Share) async {
        await showAuthor(CommunityMember(id: share.authorID, username: share.authorName, shareCount: 0))
    }

    /// Retour aux partages de tout le monde.
    func showEveryone() async {
        author = nil
        if demo {
            shares = Self.demoShares
            return
        }
        await reload()
    }

    func publish(kind: ShareKind, title: String, notes: String, payload: Data) async -> Bool {
        var ok = false
        await authed { client, session in
            try await client.publish(kind: kind, title: title, notes: notes, payload: payload,
                                     appVersion: MacroFileActions.appVersion, session: session)
            ok = true
        }
        if ok {
            await reload()
            notice = String(localized: "Partage publié.")     // après reload, qui efface les messages
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
            self.notice = String(localized: "Merci, le signalement est envoyé.")
        }
    }

    /// « Écrire à l'équipe » (page Aide) : avec le compte s'il y en a un (jeton refusé : sans), sinon sans compte.
    /// nil : envoyé ; sinon, ce qui s'est passé.
    func sendSupport(_ message: SupportMessage) async -> String? {
        if demo { return nil }
        guard let client else { return CommunityError.notConfigured.errorDescription }
        do {
            do {
                try await client.sendSupport(message, appVersion: MacroFileActions.appVersion, token: session?.accessToken)
            } catch CommunityError.server(let status, _) where session != nil && (status == 401 || status == 403) {
                try await client.sendSupport(message, appVersion: MacroFileActions.appVersion, token: nil)
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Correction de l'Organiser partagée (accord donné), avec le compte s'il y en a un (jeton refusé : sans). Un
    /// échec (hors ligne, serveur) est sans gravité : elle reste apprise sur ce Mac.
    func shareCorrection(_ json: Data) async {
        guard !demo, let client else { return }
        do {
            try await client.sendCorrection(json, token: session?.accessToken)
        } catch CommunityError.server(let status, _) where session != nil && (status == 401 || status == 403) {
            try? await client.sendCorrection(json, token: nil)
        } catch {}
    }

    func isMine(_ share: Share) -> Bool { share.authorID == session?.userID }

    // MARK: Profil (pseudo et photo)

    /// Photo du compte connecté (nil : son initiale).
    var myPhoto: NSImage? { session.flatMap { photos[$0.userID] } }

    /// Photos de ces membres : leurs dates d'abord, puis seulement les photos nouvelles ou changées. Hors ligne, ou
    /// serveur sans photos : rien ne change (l'initiale reste).
    func loadPhotos(for ids: [UUID]) async {
        guard !demo, let client, session != nil, let session = try? await validSession() else { return }
        var seen = Set<UUID>()
        let wanted = ids.filter { seen.insert($0).inserted }
        guard !wanted.isEmpty, let versions = try? await client.avatarVersions(of: wanted, session: session) else { return }
        for id in wanted where versions[id] == nil {
            photos[id] = nil
            photoVersions[id] = nil
        }
        let changed = versions.filter { photoVersions[$0.key] != $0.value }.map(\.key)
        guard !changed.isEmpty, let fresh = try? await client.avatars(of: changed, session: session) else { return }
        for (id, avatar) in fresh {
            photos[id] = NSImage(data: avatar.jpeg)
            photoVersions[id] = avatar.version
        }
    }

    /// Pseudo vérifié au fil de la frappe : format, puis libre ou pris (le sien compte comme libre).
    func checkUsername(_ name: String) async -> NameCheck {
        let n = name.trimmingCharacters(in: .whitespaces)
        if n.isEmpty { return .empty }
        if let why = CommunityRules.usernameProblem(n) { return .invalid(why) }
        if let current = session?.username, current.lowercased() == n.lowercased() { return .mine }
        if demo { return n.lowercased() == "leo.beats" ? .taken : .free }
        guard let client, let free = try? await client.usernameAvailable(n) else { return .unknown }
        return free ? .free : .taken
    }

    /// « Enregistrer » de « Modifier le profil » : le pseudo (s'il change), puis la photo. Vrai si tout est enregistré ;
    /// sinon l'erreur est affichée et la feuille reste ouverte.
    func saveProfile(username: String, photo: PhotoChange) async -> Bool {
        let name = username.trimmingCharacters(in: .whitespaces)
        if demo {
            if var s = session { s.username = name; session = s }
            return true
        }
        var ok = false
        await authed { client, session in
            var current = session
            if name != session.username {
                current.username = try await client.setUsername(name, session: session)
                self.set(current)
            }
            switch photo {
            case .keep:
                break
            case .set(let jpeg):
                let version = try await client.setAvatar(jpeg, session: current)
                self.photos[current.userID] = NSImage(data: jpeg)
                self.photoVersions[current.userID] = version
            case .remove:
                try await client.removeAvatar(session: current)
                self.photos[current.userID] = nil
                self.photoVersions[current.userID] = nil
            }
            ok = true
        }
        // Partages affichés : ils prennent le nouveau pseudo.
        if ok, !shares.isEmpty { await reload() }
        return ok
    }

    /// « Signaler la photo… » d'un membre.
    func reportPhoto(of member: CommunityMember) async {
        if demo {
            notice = Self.photoReportedNotice
            return
        }
        await authed { client, session in
            try await client.reportAvatar(of: member.id, session: session)
            self.notice = Self.photoReportedNotice
        }
    }

    static let photoReportedNotice = String(localized: "Merci, la photo est signalée : l'équipe va la regarder.")

    /// Administrateur : retire la photo d'un membre.
    func removePhoto(of member: CommunityMember) async {
        await authed { client, session in
            try await client.adminRemoveAvatar(of: member.id, session: session)
            self.photos[member.id] = nil
            self.photoVersions[member.id] = nil
            self.notice = String(localized: "Photo retirée : son initiale la remplace pour tout le monde.")
        }
    }

    /// Peut supprimer ce partage : le sien, ou n'importe lequel pour un administrateur.
    func canDelete(_ share: Share) -> Bool { isMine(share) || isAdmin }

    // MARK: Interne

    private func set(_ new: CommunitySession?) {
        let changedUser = new?.userID != session?.userID
        session = new
        if let new { keychain.save(new) } else { keychain.delete() }
        guard changedUser else { return }
        isAdmin = false
        editingProfile = false
        if let new, let client {
            Task { self.isAdmin = await client.isAdmin(session: new) }
            Task { await self.loadPhotos(for: [new.userID]) }
        }
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
        await run { client in try await body(client, try await self.validSession()) }
    }

    // MARK: Mode capture

    /// Exemples de la mesure de la CI : `signedIn` connecté en « malo » (avec un partage à lui), `empty` sans partage.
    /// Rien n'est envoyé ni gardé : ni serveur, ni Trousseau.
    func showDemo(signedIn: Bool, empty: Bool = false) {
        demo = true
        error = nil
        notice = nil
        pendingCode = nil
        session = signedIn ? CommunitySession(accessToken: "", refreshToken: "", expiresAt: .distantFuture,
                                              userID: Self.demoUser, email: "malo@exemple.fr", username: "malo") : nil
        shares = signedIn && !empty ? Self.demoShares : []
        members = []
        author = nil
        search = ""
        editingProfile = false
        // Photos d'exemple : Malo et prod.nina en ont une, les autres gardent leur initiale.
        photos = signedIn ? [Self.demoUser: ProfilePhoto.sample((.systemOrange, .systemPink)),
                             Self.demoID(204): ProfilePhoto.sample((.systemTeal, .systemBlue))] : [:]
    }

    private static func demoID(_ n: Int) -> UUID { UUID(uuidString: "00000000-0000-0000-0000-000000000\(n)")! }

    /// Exemple d'une recherche qui trouve des membres (« le ») : leurs noms, puis les partages qui en parlent.
    func showDemoMemberSearch(_ text: String) {
        showDemo(signedIn: true)
        search = text
        let rows = Self.demoShares.map { (id: $0.authorID, username: $0.authorName) }
        members = CommunityClient.members(rows.filter { $0.username.localizedCaseInsensitiveContains(text) })
        shares = Self.demoShares.filter { $0.title.localizedCaseInsensitiveContains(text)
            || $0.notes.localizedCaseInsensitiveContains(text) }
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
