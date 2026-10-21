import XCTest
@testable import FLShortcut

/// Faux serveur Supabase pour la sauvegarde : se comporte comme supabase/sauvegarde.sql (révision, refus d'écraser
/// une sauvegarde plus récente sauf choix forcé), avec une panne de connexion à la demande.
private final class FakeSupabase: CommunityTransport, @unchecked Sendable {
    struct Row: Equatable {
        var profile: String
        var macros: String
        var revision: Int64
    }

    let user = UUID()
    private let lock = NSLock()
    private var _backup: Row?
    private var _saves: [(base: Int64, force: Bool)] = []
    private var _offline = false

    var backup: Row? { lock.lock(); defer { lock.unlock() }; return _backup }
    var saves: [(base: Int64, force: Bool)] { lock.lock(); defer { lock.unlock() }; return _saves }
    var offline: Bool {
        get { lock.lock(); defer { lock.unlock() }; return _offline }
        set { lock.lock(); _offline = newValue; lock.unlock() }
    }

    private func json(_ object: Any) -> Data { (try? JSONSerialization.data(withJSONObject: object)) ?? Data() }

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        lock.lock()
        defer { lock.unlock() }
        if _offline { throw CommunityError.network("hors ligne") }
        let url = request.url!
        let body = (request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
        switch (request.httpMethod ?? "GET", url.path) {
        case ("POST", "/auth/v1/token"):
            return (json(["access_token": "jeton", "refresh_token": "r", "expires_in": 3600,
                          "user": ["id": user.uuidString, "email": "malo@exemple.fr",
                                   "user_metadata": ["username": "malo"]]]), 200)
        case ("POST", "/auth/v1/logout"):
            return (Data(), 204)
        case ("POST", "/rest/v1/rpc/is_admin"):
            return (Data("false".utf8), 200)
        case ("GET", "/rest/v1/shares"):
            return (Data("[]".utf8), 200)
        case ("GET", "/rest/v1/backups"):
            guard let b = _backup else { return (Data("[]".utf8), 200) }
            let date = "2026-10-17T10:00:00.123456+00:00"
            if (url.query ?? "").contains("profile") {
                return (json([["profile": b.profile, "macros": b.macros, "revision": b.revision, "updated_at": date]]), 200)
            }
            return (json([["revision": b.revision, "updated_at": date]]), 200)
        case ("POST", "/rest/v1/rpc/save_backup"):
            let base = (body["p_base"] as? NSNumber)?.int64Value ?? -1
            let force = body["p_force"] as? Bool ?? false
            _saves.append((base, force))
            if let b = _backup, b.revision != base, !force {
                return (json(["message": "Sauvegarde plus récente sur le compte (révision \(b.revision))."]), 400)
            }
            let revision = (_backup?.revision ?? 0) + 1
            _backup = Row(profile: body["p_profile"] as? String ?? "", macros: body["p_macros"] as? String ?? "",
                          revision: revision)
            return (Data("\(revision)".utf8), 200)
        case ("POST", "/rest/v1/rpc/delete_my_account"):
            _backup = nil
            return (Data(), 204)
        default:
            return (Data(), 404)
        }
    }
}

/// Un Mac : raccourcis et macros en mémoire, réglages et Trousseau à part, sa sauvegarde en ligne.
@MainActor
private final class Mac {
    let profile = MemoryProfileStorage()
    let library = MemoryMacroLibraryStorage()
    let defaults: UserDefaults
    let keychain: CommunitySessionKeychain
    let store: Store
    let community: CommunityStore
    let backup: AccountBackup

    init(_ server: FakeSupabase) {
        let suite = "FLShortcutTests-compte-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        keychain = CommunitySessionKeychain(service: "app.flshortcut.tests.\(UUID().uuidString)")
        store = Store(storage: profile, layout: FakeLayout.qwerty, defaults: defaults, systemHotKeys: { [:] },
                      pushToTap: false, saveDelay: 0, library: MacroLibraryStore(storage: library, saveDelay: 0))
        community = CommunityStore(config: CommunityConfig(url: URL(string: "https://exemple.supabase.co")!,
                                                           anonKey: "sb_publishable_essai"),
                                   keychain: keychain, transport: server)
        backup = AccountBackup(community: community, store: store, defaults: defaults, delay: 0.05, firstRetry: 0.2)
        backup.start()
    }

    func signIn() async { await community.signIn(email: "malo@exemple.fr", password: "MotDePasse1!") }

    @discardableResult
    func addMacro(_ name: String) -> MacroDoc { store.library.add(MacroDoc(name: name, blocks: [Block(.delay(ms: 100))])) }

    var macroNames: [String] { store.library.macros.map(\.name) }

    deinit { keychain.delete() }
}

/// Sauvegarde en ligne du compte : connexion, autre Mac, déconnexion, hors ligne, choix, suppression du compte.
@MainActor
final class AccountBackupTests: XCTestCase {
    private func wait(_ what: String, file: StaticString = #filePath, line: UInt = #line,
                      _ condition: () -> Bool) async {
        let end = Date().addingTimeInterval(5)
        while !condition(), Date() < end { try? await Task.sleep(nanoseconds: 20_000_000) }
        XCTAssertTrue(condition(), what, file: file, line: line)
    }

    private func isUpToDate(_ status: AccountBackup.Status) -> Bool {
        if case .upToDate = status { return true }
        return false
    }

    private func isWaiting(_ status: AccountBackup.Status) -> Bool {
        if case .waiting = status { return true }
        return false
    }

    func testDecisions() {
        func d(_ remote: Int64?, same: Bool = false, untouched: Bool = false, synced: Int64? = nil, dirty: Bool = false) -> BackupDecision {
            BackupRules.decide(remoteRevision: remote, sameContent: same, untouched: untouched, syncedRevision: synced, dirty: dirty)
        }
        XCTAssertEqual(d(nil), .upload, "pas encore de sauvegarde : ce Mac l'envoie")
        XCTAssertEqual(d(nil, untouched: true), .upload)
        XCTAssertEqual(d(3, same: true), .inSync)
        XCTAssertEqual(d(3, untouched: true), .restore, "Mac neuf ou déconnecté : tout revient")
        XCTAssertEqual(d(3, synced: 3, dirty: true), .upload, "le compte n'a pas bougé : ce Mac envoie ses changements")
        XCTAssertEqual(d(4, synced: 3), .restore, "changé ailleurs, rien à perdre ici")
        XCTAssertEqual(d(4, synced: 3, dirty: true), .ask, "changé des deux côtés")
        XCTAssertEqual(d(3), .ask, "ce Mac a ses propres raccourcis, le compte les siens")
        XCTAssertEqual(d(3, untouched: true, synced: 3, dirty: true), .upload, "« Tout réinitialiser » connecté : envoyé")
    }

    func testContentRoundTripAndNewerVersion() throws {
        let remaps = [Remap(trigger: KeyCombo(keyCode: 0, control: true), action: 4)]
        let macros = [MacroDoc(name: "Voix", blocks: [Block(.delay(ms: 100))])]
        let content = try BackupContent.of(remaps: remaps, macros: macros)
        let back = try content.decoded()
        XCTAssertEqual(back.remaps, remaps)
        XCTAssertEqual(back.macros.map(\.name), ["Voix"])
        XCTAssertEqual(content.summary, "1 raccourci · 1 macro")
        XCTAssertTrue(content.sameAs(try BackupContent.of(remaps: back.remaps, macros: back.macros)))
        var newer = content
        newer.macros = #"{"version":99,"macros":[]}"#
        XCTAssertThrowsError(try newer.decoded()) { XCTAssertEqual($0 as? BackupFailure, .newerVersion) }
        XCTAssertThrowsError(try BackupContent(profile: "?", macros: "?").decoded()) {
            XCTAssertEqual($0 as? BackupFailure, .unreadable)
        }
    }

    func testUntouchedMac() {
        let mac = Mac(FakeSupabase())
        XCTAssertTrue(mac.store.isUntouched, "premier lancement")
        mac.store.upsert(Remap(trigger: KeyCombo(keyCode: 0, control: true), action: 4))
        XCTAssertFalse(mac.store.isUntouched)
        mac.store.replaceAll(mac.store.freshRemaps(), macros: [])
        XCTAssertTrue(mac.store.isUntouched)
        mac.addMacro("Voix")
        XCTAssertFalse(mac.store.isUntouched)
    }

    /// Nouveau compte : ce qu'il y a sur ce Mac part en ligne, puis chaque changement quelques instants après.
    func testNewAccountUploadsThenEachChange() async {
        let server = FakeSupabase()
        let mac = Mac(server)
        mac.store.upsert(Remap(trigger: KeyCombo(keyCode: 0, control: true), action: 4))
        await mac.signIn()
        await wait("première sauvegarde") { server.backup?.revision == 1 && self.isUpToDate(mac.backup.status) }
        XCTAssertEqual(server.saves.first?.base, 0)
        let doc = mac.addMacro("Voix")
        await wait("changement envoyé") { server.backup?.revision == 2 && self.isUpToDate(mac.backup.status) }
        XCTAssertTrue(server.backup?.macros.contains(doc.id.uuidString) == true)
        XCTAssertEqual(server.saves.last?.base, 1)
        XCTAssertFalse(mac.backup.hasUnsavedChanges)
    }

    /// Autre Mac, neuf : tout revient, sans rien renvoyer ni copier.
    func testOtherMacGetsEverythingBack() async {
        let server = FakeSupabase()
        let a = Mac(server)
        a.store.upsert(Remap(trigger: KeyCombo(keyCode: 0, control: true), action: 4))
        a.addMacro("Voix")
        await a.signIn()
        await wait("sauvegarde du premier Mac") { server.backup?.revision == 1 && self.isUpToDate(a.backup.status) }
        let b = Mac(server)
        XCTAssertTrue(b.store.isUntouched)
        await b.signIn()
        await wait("tout revient") { b.macroNames == ["Voix"] }
        XCTAssertEqual(b.store.remaps, a.store.remaps)
        XCTAssertTrue(b.profile.backups.isEmpty, "Mac neuf : rien à copier")
        XCTAssertEqual(server.saves.count, 1, "le Mac neuf n'a rien renvoyé")
    }

    /// Déconnexion : le Mac revient au premier lancement, le compte garde tout ; reconnexion : tout revient.
    func testSignOutEmptiesThisMacAndSignInBringsBack() async {
        let server = FakeSupabase()
        let mac = Mac(server)
        mac.addMacro("Voix")
        await mac.signIn()
        await wait("sauvegardé") { server.backup?.revision == 1 && self.isUpToDate(mac.backup.status) }
        let outcome = await mac.backup.signOut()
        XCTAssertEqual(outcome, .done)
        XCTAssertNil(mac.community.session)
        XCTAssertTrue(mac.store.isUntouched, "plus rien de personnel sur ce Mac")
        XCTAssertEqual(server.backup?.revision, 1, "le compte garde tout")
        XCTAssertNil(mac.defaults.string(forKey: AccountBackup.Keys.account))
        await mac.signIn()
        await wait("tout revient") { mac.macroNames == ["Voix"] }
        XCTAssertEqual(server.saves.count, 1)
    }

    /// Hors ligne : la déconnexion ne retire rien sans le demander ; « quand même » retire tout.
    func testOfflineSignOutAsksFirst() async {
        let server = FakeSupabase()
        let mac = Mac(server)
        await mac.signIn()
        await wait("sauvegardé") { server.backup?.revision == 1 && self.isUpToDate(mac.backup.status) }
        server.offline = true
        mac.addMacro("Hors ligne")
        await wait("en attente de connexion") { self.isWaiting(mac.backup.status) }
        let refused = await mac.backup.signOut()
        guard case .notSaved = refused else { return XCTFail("déconnecté sans prévenir : \(refused)") }
        XCTAssertEqual(mac.macroNames, ["Hors ligne"], "rien n'est retiré")
        XCTAssertNotNil(mac.community.session)
        server.offline = false
        let done = await mac.backup.signOut()
        XCTAssertEqual(done, .done)
        XCTAssertTrue(server.backup?.macros.contains("Hors ligne") == true, "parti avant la déconnexion")

        await mac.signIn()
        await wait("revenu") { mac.macroNames == ["Hors ligne"] }
        server.offline = true
        mac.addMacro("Perdue")
        await wait("en attente") { self.isWaiting(mac.backup.status) }
        let forced = await mac.backup.signOut(evenIfNotSaved: true)
        XCTAssertEqual(forced, .done)
        XCTAssertTrue(mac.store.isUntouched)
        XCTAssertFalse(server.backup?.macros.contains("Perdue") == true)
    }

    /// Ce Mac et le compte ont chacun leurs macros : rien n'est envoyé ni remplacé avant le choix.
    func testConflictWaitsForChoice() async {
        let server = FakeSupabase()
        let a = Mac(server)
        a.addMacro("Du compte")
        await a.signIn()
        await wait("sauvegardé") { server.backup?.revision == 1 && self.isUpToDate(a.backup.status) }

        let b = Mac(server)
        b.addMacro("De ce Mac")
        await b.signIn()
        await wait("choix demandé") { b.backup.conflict != nil }
        XCTAssertEqual(b.backup.status, .choice)
        XCTAssertEqual(b.backup.conflict?.here, "11 raccourcis · 1 macro")
        XCTAssertEqual(server.saves.count, 1, "rien envoyé avant le choix")
        XCTAssertEqual(b.macroNames, ["De ce Mac"], "rien remplacé avant le choix")
        await b.backup.resolve(keepAccount: true)
        XCTAssertEqual(b.macroNames, ["Du compte"])
        XCTAssertNotNil(b.library.backups["macros.avant-compte.json"], "copie de ce qu'il y avait")
        XCTAssertNotNil(b.profile.backups["profile.avant-compte.json"])

        let c = Mac(server)
        c.addMacro("Mon Mac")
        await c.signIn()
        await wait("choix demandé") { c.backup.conflict != nil }
        await c.backup.resolve(keepAccount: false)
        XCTAssertEqual(server.saves.last?.force, true)
        XCTAssertTrue(server.backup?.macros.contains("Mon Mac") == true)
        XCTAssertEqual(server.backup?.revision, 2)
    }

    /// Changé sur un autre Mac pendant que celui-ci était à jour : la nouvelle version revient ici.
    func testChangeFromAnotherMacComesBack() async {
        let server = FakeSupabase()
        let a = Mac(server)
        a.addMacro("Voix")
        await a.signIn()
        await wait("sauvegardé") { server.backup?.revision == 1 && self.isUpToDate(a.backup.status) }
        let b = Mac(server)
        await b.signIn()
        await wait("revenu") { b.macroNames == ["Voix"] }
        a.addMacro("Batterie")
        await wait("envoyé") { server.backup?.revision == 2 && self.isUpToDate(a.backup.status) }
        await b.backup.sync()
        XCTAssertEqual(b.macroNames, ["Voix", "Batterie"])
        XCTAssertEqual(server.saves.count, 2, "rien renvoyé par l'autre Mac")
    }

    /// Supprimer le compte : sauvegarde effacée, déconnecté, raccourcis et macros gardés sur ce Mac.
    func testDeleteAccountKeepsThisMac() async {
        let server = FakeSupabase()
        let mac = Mac(server)
        mac.addMacro("Voix")
        await mac.signIn()
        await wait("sauvegardé") { server.backup?.revision == 1 && self.isUpToDate(mac.backup.status) }
        let error = await mac.backup.deleteAccount()
        XCTAssertNil(error)
        XCTAssertNil(server.backup)
        XCTAssertNil(mac.community.session)
        XCTAssertEqual(mac.macroNames, ["Voix"])
        XCTAssertEqual(mac.backup.status, .off)
    }

    func testServerDates() {
        XCTAssertNotNil(CommunityText.date("2026-10-17T10:00:00.123456+00:00"))
        XCTAssertNotNil(CommunityText.date("2026-10-17T10:00:00+00:00"))
        XCTAssertNil(CommunityText.date("hier"))
    }
}
