// Sauvegarde en ligne du compte (supabase/sauvegarde.sql). Connecté, les raccourcis (profile.json) et les macros
// (macros.json) partent en ligne quelques secondes après chaque changement ; à la connexion, sur ce Mac ou un autre,
// la sauvegarde du compte revient ; à la déconnexion, ils quittent ce Mac (qui revient au premier lancement : profil
// recommandé, aucune macro) et restent dans le compte. Jamais rien sans compte. Rien d'autre ne part : ni réglages
// du Mac, ni endroits appris hors des macros, ni journal. Un Mac n'écrase jamais une sauvegarde plus récente faite
// ailleurs sans le demander (révision du serveur), et rien n'est remplacé sur ce Mac sans copie datée
// (Application Support › FL Shortcuts), sauf à la déconnexion, où tout vient d'être mis en ligne.
import Combine
import Foundation

/// Ce qui est sauvegardé : les deux fichiers de l'app, en texte, toujours encodés de la même façon.
struct BackupContent: Equatable {
    var profile: String
    var macros: String

    static func of(remaps: [Remap], macros: [MacroDoc]) throws -> BackupContent {
        BackupContent(profile: String(decoding: try ProfileCodec.encode(remaps), as: UTF8.self),
                      macros: String(decoding: try MacroLibraryCodec.encode(macros, pretty: false), as: UTF8.self))
    }

    /// Raccourcis et macros relus ; refusé s'ils viennent d'une version plus récente de l'app (rien ne serait perdu
    /// ici, mais les renvoyer depuis cette version en perdrait une partie).
    func decoded() throws -> (remaps: [Remap], macros: [MacroDoc]) {
        let profile: ProfileCodec.Decoded
        let library: MacroLibraryCodec.Decoded
        do {
            profile = try ProfileCodec.decode(Data(self.profile.utf8))
            library = try MacroLibraryCodec.decode(Data(macros.utf8))
        } catch {
            throw BackupFailure.unreadable
        }
        guard profile.sourceVersion <= ProfileCodec.currentVersion, library.version <= MacroLibraryCodec.currentVersion else {
            throw BackupFailure.newerVersion
        }
        return (profile.remaps, library.macros)
    }

    /// Même contenu une fois relu (encodage identique de part et d'autre).
    func sameAs(_ other: BackupContent) -> Bool {
        guard self != other else { return true }
        guard let a = try? decoded(), let b = try? other.decoded() else { return false }
        return (try? BackupContent.of(remaps: a.remaps, macros: a.macros)) == (try? BackupContent.of(remaps: b.remaps, macros: b.macros))
    }

    /// « 12 raccourcis · 3 macros ».
    static func summary(remaps: Int, macros: Int) -> String {
        String(localized: "\(remaps) raccourci\(remaps > 1 ? "s" : "") · \(macros) macro\(macros > 1 ? "s" : "")")
    }

    var summary: String {
        guard let d = try? decoded() else { return String(localized: "illisible") }
        return Self.summary(remaps: d.remaps.count, macros: d.macros.count)
    }
}

/// La sauvegarde du compte telle que lue sur le serveur.
struct RemoteBackup: Equatable {
    var content: BackupContent
    var revision: Int64
    var updatedAt: Date?
}

enum BackupFailure: Error, LocalizedError, Equatable {
    case unreadable
    case newerVersion
    case cannotWrite
    case copyFailed

    var errorDescription: String? {
        switch self {
        case .unreadable: return String(localized: "La sauvegarde de ton compte est illisible : rien n'a été changé sur ce Mac.")
        case .newerVersion:
            return String(localized: "Ta sauvegarde vient d'une version plus récente de FL Shortcuts : mets l'app à jour.")
        case .cannotWrite: return MacroLibraryStore.writesDisabledMessage
        case .copyFailed:
            return String(localized: """
                Impossible de garder une copie de ce Mac avant de reprendre ta sauvegarde : rien n'a été remplacé.
                """)
        }
    }
}

/// Que faire quand ce Mac et la sauvegarde du compte se retrouvent (connexion, lancement, nouvel essai).
enum BackupDecision: Equatable {
    /// Ce Mac envoie ce qu'il a : pas encore de sauvegarde, ou le compte n'a pas bougé depuis.
    case upload
    /// La sauvegarde du compte remplace ce Mac, qui n'a rien à perdre.
    case restore
    case inSync
    /// Chacun a ses changements : l'utilisateur choisit.
    case ask
}

enum BackupRules {
    /// - `remoteRevision` : révision de la sauvegarde du compte (nil : pas encore de sauvegarde).
    /// - `sameContent` : ce Mac et le compte ont exactement les mêmes raccourcis et macros.
    /// - `untouched` : rien de personnel sur ce Mac (premier lancement, ou juste après une déconnexion).
    /// - `syncedRevision` : la dernière révision de CE compte que ce Mac a lue ou écrite (nil : jamais, ou un autre
    ///   compte) ; `dirty` : changements faits sur ce Mac depuis.
    static func decide(remoteRevision: Int64?, sameContent: Bool, untouched: Bool, syncedRevision: Int64?,
                       dirty: Bool) -> BackupDecision {
        guard let remote = remoteRevision else { return .upload }
        if sameContent { return .inSync }
        if let synced = syncedRevision {
            if synced == remote { return .upload }        // le compte n'a pas bougé : ce Mac a des changements
            if !dirty { return .restore }                 // changé ailleurs, rien à perdre ici
        }
        if untouched { return .restore }
        return .ask
    }
}

@MainActor
final class AccountBackup: ObservableObject {
    static let shared = AccountBackup()

    enum Status: Equatable {
        /// Pas de compte connecté : tout reste sur ce Mac.
        case off
        case checking
        case upToDate(Date?)
        /// Changements à envoyer dans quelques secondes.
        case pending
        case saving
        /// Envoi impossible pour l'instant (pas de connexion…) : nouvel essai automatique.
        case waiting(String)
        /// Ce Mac et le compte ont chacun leurs changements : à choisir (`conflict`).
        case choice
        /// Rien n'est envoyé (version plus récente, sauvegarde illisible, fichier des macros bloqué).
        case blocked(String)
    }

    /// Les deux versions, résumées, pour le choix.
    struct Conflict: Identifiable, Equatable {
        let id = UUID()
        let remote: RemoteBackup
        let here: String
        let account: String
    }

    enum SignOutOutcome: Equatable {
        case done
        /// Les derniers changements ne sont pas en ligne : ce qui s'est passé.
        case notSaved(String)
    }

    enum Keys {
        static let account = "backup.account"
        static let revision = "backup.revision"
        static let dirty = "backup.dirty"
    }

    @Published private(set) var status: Status = .off
    @Published var conflict: Conflict?
    /// Information d'une action (sauvegarde reprise…), affichée par la page Mon compte.
    @Published var notice: String?

    let community: CommunityStore
    private let store: Store
    private let defaults: UserDefaults
    private let delay: TimeInterval
    private let firstRetry: TimeInterval
    private var retryDelay: TimeInterval
    /// Remplacement en cours (sauvegarde reprise, déconnexion) : ce n'est pas un changement à envoyer.
    private var applying = false
    /// Changements faits sur ce Mac depuis le lancement : un changement pendant un envoi reste à envoyer.
    private var changes = 0
    private var syncing = false
    private var pushTask: Task<Void, Never>?
    private var lastCheck = Date.distantPast
    private var watching: AnyCancellable?

    init(community: CommunityStore = .shared, store: Store = .shared, defaults: UserDefaults = .standard,
         delay: TimeInterval = 4, firstRetry: TimeInterval = 30) {
        self.community = community
        self.store = store
        self.defaults = defaults
        self.delay = delay
        self.firstRetry = firstRetry
        retryDelay = firstRetry
    }

    /// Lancement de l'app : suit les changements et la session ; reprend la session du Trousseau s'il y en a une
    /// (aucune requête sinon).
    func start() {
        // Raccourcis et macros ne changent que sur le thread principal (fenêtre, créateur, import).
        store.onDataChange = { [weak self] in MainActor.assumeIsolated { self?.localChanged() } }
        watching = community.$session.map { $0?.userID }.removeDuplicates()
            .sink { [weak self] user in
                Task { @MainActor in await self?.sessionChanged(user) }
            }
        Task { await community.restoreSession() }
    }

    // MARK: État

    private var dirty: Bool {
        get { defaults.bool(forKey: Keys.dirty) }
        set { defaults.set(newValue, forKey: Keys.dirty) }
    }

    /// Dernière révision de ce compte lue ou écrite par ce Mac.
    private func syncedRevision(for account: UUID) -> Int64? {
        guard defaults.string(forKey: Keys.account) == account.uuidString,
              let n = defaults.object(forKey: Keys.revision) as? NSNumber else { return nil }
        return n.int64Value
    }

    /// Connecté, avec des changements de ce Mac pas encore en ligne.
    var hasUnsavedChanges: Bool { community.session != nil && dirty }

    /// « 12 raccourcis · 3 macros » : ce qui est sur ce Mac.
    var hereSummary: String { BackupContent.summary(remaps: store.remaps.count, macros: store.library.macros.count) }

    /// Fichiers de ce Mac pas lus entièrement au lancement : jamais envoyés à la place de la sauvegarde du compte.
    private var localUnreliable: Bool {
        store.loadIncomplete || store.library.loadIncomplete || store.library.writesDisabled
    }

    private func currentContent() throws -> BackupContent {
        try BackupContent.of(remaps: store.remaps, macros: store.library.macros)
    }

    private func markSynced(_ account: UUID, _ revision: Int64, at date: Date?, changesBefore: Int) {
        defaults.set(account.uuidString, forKey: Keys.account)
        defaults.set(NSNumber(value: revision), forKey: Keys.revision)
        retryDelay = firstRetry
        if changes != changesBefore {                     // changé pendant l'envoi : à renvoyer
            dirty = true
            status = .pending
            schedule(after: delay) { await $0.push() }
        } else {
            dirty = false
            status = .upToDate(date ?? Date())
        }
    }

    private func forgetSync() {
        defaults.removeObject(forKey: Keys.account)
        defaults.removeObject(forKey: Keys.revision)
        defaults.removeObject(forKey: Keys.dirty)
        pushTask?.cancel()
        pushTask = nil
        conflict = nil
        retryDelay = firstRetry
        status = .off
    }

    // MARK: Événements

    private func sessionChanged(_ user: UUID?) async {
        guard !community.demo else { return }
        if user == nil {
            pushTask?.cancel()
            pushTask = nil
            conflict = nil
            status = .off                                 // session expirée : tout reste sur ce Mac
        } else {
            await sync()
        }
    }

    private func localChanged() {
        guard !applying else { return }
        changes += 1
        // Données de ce Mac rattachées à un compte : changement à envoyer, même hors connexion.
        guard defaults.string(forKey: Keys.account) != nil else { return }
        dirty = true
        guard community.session != nil, !community.demo, conflict == nil else { return }
        if case .blocked = status { return }
        status = .pending
        schedule(after: delay) { await $0.push() }
    }

    private func schedule(after seconds: TimeInterval, _ work: @escaping (AccountBackup) async -> Void) {
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            await work(self)
        }
    }

    /// Fenêtre ou page Mon compte ouverte : relit le compte s'il n'a pas été vu depuis 2 minutes (changé ailleurs ?).
    func refreshIfStale() async {
        guard community.session != nil, Date().timeIntervalSince(lastCheck) > 120 else { return }
        await sync()
    }

    // MARK: Synchronisation

    /// Retrouve ce Mac et le compte : envoie, reprend ou demande (BackupRules), puis met l'état à jour.
    func sync() async {
        guard !community.demo, community.session != nil, !syncing, conflict == nil else { return }
        syncing = true
        defer { syncing = false }
        lastCheck = Date()
        if await syncOnce() == .conflict { _ = await syncOnce() }   // changé ailleurs pendant l'envoi : relu une fois
    }

    private enum SaveResult { case saved, conflict, failed }

    private func syncOnce() async -> SaveResult {
        guard let client = community.client else { return .failed }
        status = .checking
        do {
            let session = try await community.validSession()
            let account = session.userID
            let synced = syncedRevision(for: account)
            // Fichiers de ce Mac illisibles au lancement (leur copie datée est déjà gardée) : la sauvegarde du compte
            // les remplace ; rien n'est envoyé à sa place.
            if localUnreliable, let remote = try await client.backup(session: session) {
                try restore(remote, account: account, keepCopy: false)
                return .saved
            }
            // Vérification rapide : le compte n'a pas bougé depuis ce Mac.
            if let synced, let quick = try await client.backupRevision(session: session), quick.revision == synced {
                if dirty { return await save(base: synced, force: false) }
                status = .upToDate(quick.updatedAt)
                return .saved
            }
            let remote = try await client.backup(session: session)
            let before = changes
            let local = try currentContent()
            let decision = BackupRules.decide(remoteRevision: remote?.revision,
                                              sameContent: remote.map { $0.content.sameAs(local) } ?? false,
                                              untouched: store.isUntouched, syncedRevision: synced, dirty: dirty)
            switch decision {
            case .upload:
                return await save(base: remote?.revision ?? 0, force: false)
            case .inSync:
                if let remote { markSynced(account, remote.revision, at: remote.updatedAt, changesBefore: before) }
            case .restore:
                if let remote { try restore(remote, account: account, keepCopy: !store.isUntouched) }
            case .ask:
                if let remote {
                    conflict = Conflict(remote: remote, here: hereSummary, account: remote.content.summary)
                    status = .choice
                }
            }
            return .saved
        } catch {
            handle(error)
            return .failed
        }
    }

    /// Envoie ce qu'il y a sur ce Mac si le compte est toujours à la révision `base` (ou quoi qu'il y ait : `force`).
    private func save(base: Int64, force: Bool) async -> SaveResult {
        guard let client = community.client else { return .failed }
        status = .saving
        let before = changes
        do {
            let session = try await community.validSession()
            let content = try currentContent()
            let revision = try await client.saveBackup(content, base: base, force: force,
                                                       appVersion: MacroFileActions.appVersion, session: session)
            markSynced(session.userID, revision, at: Date(), changesBefore: before)
            return .saved
        } catch CommunityError.backupConflict {
            return .conflict
        } catch {
            handle(error)
            return .failed
        }
    }

    /// Envoi après un changement (quelques secondes après le dernier).
    private func push() async {
        guard dirty, let user = community.session?.userID, !syncing, conflict == nil else { return }
        guard !localUnreliable else {                     // relu et décidé par sync
            await sync()
            return
        }
        guard let synced = syncedRevision(for: user) else {
            await sync()
            return
        }
        syncing = true
        let result = await save(base: synced, force: false)
        syncing = false
        if result == .conflict { await sync() }
    }

    /// La sauvegarde du compte remplace ce Mac (copie datée de ce qu'il y avait, s'il y avait quelque chose à soi).
    private func restore(_ remote: RemoteBackup, account: UUID, keepCopy: Bool) throws {
        let decoded = try remote.content.decoded()
        guard !store.library.writesDisabled else { throw BackupFailure.cannotWrite }
        if keepCopy {
            guard store.keepCopy(label: "avant-compte") != nil,
                  store.library.keepCurrentCopy(label: "avant-compte") != nil else { throw BackupFailure.copyFailed }
        }
        applying = true
        store.replaceAll(decoded.remaps, macros: decoded.macros)
        applying = false
        markSynced(account, remote.revision, at: remote.updatedAt, changesBefore: changes)
        notice = String(localized: "Tes raccourcis et tes macros sont revenus de ton compte (\(remote.content.summary)).")
    }

    private func handle(_ error: Error) {
        if let failure = error as? BackupFailure {
            status = .blocked(failure.localizedDescription)
            return
        }
        guard community.session != nil else {
            status = .off
            return
        }
        // Refus définitif du serveur (trop grande, compte supprimé ailleurs…) : pas de nouvel essai sans fin.
        if let e = error as? CommunityError, case .server(let code, let message) = e,
           (400..<500).contains(code), ![401, 408, 429].contains(code) {
            status = .blocked(String(localized: "Sauvegarde refusée par le serveur : \(message)"))
            return
        }
        let why: String
        if let e = error as? CommunityError, case .network = e {
            why = String(localized: "Pas de connexion : la sauvegarde partira dès que possible.")
        } else {
            why = String(localized: "Sauvegarde impossible pour l'instant : \(error.localizedDescription)")
        }
        status = .waiting(why)
        let wait = retryDelay
        retryDelay = min(retryDelay * 2, 900)
        schedule(after: wait) { await $0.sync() }
    }

    // MARK: Choix, déconnexion, suppression

    /// Choix de l'utilisateur quand ce Mac et le compte ont chacun leurs changements.
    func resolve(keepAccount: Bool) async {
        guard !community.demo else {                      // mode capture : rien n'est remplacé ni envoyé
            conflict = nil
            return
        }
        guard let choice = conflict, let account = community.session?.userID else { return }
        conflict = nil
        if keepAccount {
            do { try restore(choice.remote, account: account, keepCopy: true) } catch { handle(error) }
        } else {
            syncing = true
            let result = await save(base: choice.remote.revision, force: true)
            syncing = false
            if result == .conflict { await sync() }
        }
    }

    /// Envoi tout de suite (bouton « Sauvegarder maintenant »).
    func saveNow() async {
        pushTask?.cancel()
        await sync()
    }

    /// Déconnexion : d'abord tout en ligne, puis raccourcis et macros retirés de ce Mac (ils restent dans le
    /// compte). `evenIfNotSaved` : l'utilisateur accepte de perdre ce qui n'a pas pu partir.
    func signOut(evenIfNotSaved: Bool = false) async -> SignOutOutcome {
        guard !community.demo else {                      // mode capture : rien n'est touché sur ce Mac
            await community.signOut()
            return .done
        }
        pushTask?.cancel()
        while syncing { try? await Task.sleep(nanoseconds: 50_000_000) }   // un envoi en cours se termine d'abord
        // Session perdue (expirée, refusée) : sans elle rien ne peut partir ; ce Mac n'est vidé que si tout est déjà
        // dans le compte, ou si l'utilisateur l'accepte.
        if !evenIfNotSaved, community.session == nil,
           dirty || defaults.string(forKey: Keys.account) == nil {
            return .notSaved(String(localized: """
                Ta session a expiré : reconnecte-toi pour mettre en ligne tes derniers changements.
                """))
        }
        if !evenIfNotSaved, let user = community.session?.userID {
            if conflict == nil, dirty || syncedRevision(for: user) == nil { await sync() }
            if conflict != nil {
                return .notSaved(String(localized: """
                    Choisis d'abord quelle version garder : celle de ce Mac ou celle de ton compte.
                    """))
            }
            if dirty || syncedRevision(for: user) == nil {
                if case .waiting(let why) = status { return .notSaved(why) }
                if case .blocked(let why) = status { return .notSaved(why) }
                return .notSaved(String(localized: "Tes derniers changements ne sont pas encore en ligne."))
            }
        }
        await community.signOut()
        applying = true
        store.replaceAll(store.freshRemaps(), macros: [])
        applying = false
        forgetSync()
        notice = nil
        return .done
    }

    /// Supprime le compte et tout ce qu'il a en ligne ; les raccourcis et les macros restent sur ce Mac.
    /// nil : supprimé ; sinon, ce qui s'est passé.
    func deleteAccount() async -> String? {
        guard !community.demo else { return nil }
        guard let client = community.client else { return CommunityError.notConfigured.errorDescription }
        do {
            let session = try await community.validSession()
            try await client.deleteAccount(session: session)
        } catch {
            return error.localizedDescription
        }
        community.forgetSession()
        forgetSync()
        notice = String(localized: "Ton compte est supprimé. Tes raccourcis et tes macros restent sur ce Mac.")
        return nil
    }

    // MARK: Mode capture

    /// Écrans de la page Mon compte pour la mesure de la CI, avec des exemples : rien n'est envoyé ni touché.
    func showDemo(_ screen: String) {
        conflict = nil
        notice = nil
        switch screen {
        case "connexion":
            community.showDemo(signedIn: false)
            status = .off
        case "code", "oubli":
            community.showDemo(signedIn: false)
            community.pendingCode = CommunityStore.PendingCode(kind: screen == "code" ? .signup : .recovery,
                                                               email: "malo@exemple.fr")
            status = .off
        case "choix":
            community.showDemo(signedIn: true)
            status = .choice
            let remote = RemoteBackup(content: (try? BackupContent.of(remaps: store.freshRemaps(), macros: [])) ?? BackupContent(profile: "", macros: ""),
                                      revision: 7, updatedAt: Date(timeIntervalSinceNow: -3600 * 5))
            conflict = Conflict(remote: remote, here: BackupContent.summary(remaps: 14, macros: 3),
                                account: BackupContent.summary(remaps: 12, macros: 5))
        case "attente":
            community.showDemo(signedIn: true)
            status = .waiting(String(localized: "Pas de connexion : la sauvegarde partira dès que possible."))
        default:
            community.showDemo(signedIn: true)
            status = .upToDate(Date(timeIntervalSinceNow: -120))
        }
    }
}
