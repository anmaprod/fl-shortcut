// Compte, Communauté et sauvegarde en ligne : client du serveur Supabase, par son API REST, sans bibliothèque ajoutée.
// Le réseau ne sert qu'avec un compte connecté (Communauté, sauvegarde de ses raccourcis et macros : AccountBackup)
// ou pour « Écrire à l'équipe » : jamais sans compte en dehors de ces pages, jamais pour lancer un raccourci ou une
// macro. Sans compte connecté, le serveur ne renvoie rien (règles « authenticated » seulement : supabase/schema.sql,
// supabase/sauvegarde.sql). Le mot de passe n'est jamais gardé : seul le jeton de rafraîchissement l'est, au Trousseau.
import Foundation

/// Adresse du projet Supabase et sa clé publique (« anon », publique par conception : les règles du serveur
/// protègent les données). Lues dans l'Info.plist (build.sh : FLS_SUPABASE_URL, FLS_SUPABASE_ANON_KEY), scellée
/// dans l'app signée. Les réglages (`defaults write app.flshortcut.FLShortcut communityURL …`) ne servent qu'à une
/// app compilée sans serveur, pour un essai : sinon n'importe quel programme du Mac pouvait les écrire et envoyer le
/// mot de passe, la session et la sauvegarde de l'utilisateur à son propre serveur (audit du 25/10).
struct CommunityConfig: Equatable {
    let url: URL
    let anonKey: String

    static var current: CommunityConfig? {
        resolve(info: Bundle.main.infoDictionary, defaults: .standard)
    }

    /// Pur (testé) : l'adresse de l'app d'abord ; celle des réglages seulement si l'app n'en a pas. HTTPS seulement.
    static func resolve(info: [String: Any]?, defaults: UserDefaults) -> CommunityConfig? {
        let builtURL = info?["FLSCommunityURL"] as? String ?? ""
        let builtKey = info?["FLSCommunityAnonKey"] as? String ?? ""
        let built = !builtURL.isEmpty && !builtKey.isEmpty
        let rawURL = built ? builtURL : defaults.string(forKey: "communityURL") ?? ""
        let key = built ? builtKey : defaults.string(forKey: "communityAnonKey") ?? ""
        guard let url = URL(string: rawURL), url.scheme == "https", url.host != nil, url.user == nil,
              !key.isEmpty else { return nil }
        return CommunityConfig(url: url, anonKey: key)
    }
}

enum ShareKind: String, Codable, CaseIterable, Identifiable {
    case macro, profile

    var id: String { rawValue }
    var label: String { self == .macro ? String(localized: "Macro") : String(localized: "Raccourcis") }
    var symbol: String { self == .macro ? "wand.and.stars" : "keyboard" }
}

/// Un partage tel que listé (sans le fichier, chargé seulement pour l'import).
struct Share: Codable, Identifiable, Equatable {
    struct Author: Codable, Equatable { let username: String }

    let id: UUID
    let authorID: UUID
    let kind: ShareKind
    let title: String
    let notes: String
    let appVersion: String
    let createdAt: String
    let author: Author?

    enum CodingKeys: String, CodingKey {
        case id, kind, title, notes, author
        case authorID = "author_id"
        case appVersion = "app_version"
        case createdAt = "created_at"
    }

    var authorName: String { author?.username ?? "?" }
}

/// Un membre qui a publié (trouvé par son nom dans la recherche de la Communauté) : son nom et ses partages.
struct CommunityMember: Identifiable, Equatable {
    let id: UUID
    let username: String
    /// Partages comptés à la recherche (0 : pas encore comptés, membre ouvert depuis un partage).
    let shareCount: Int
}

/// Compte connecté. `accessToken` vit en mémoire ; le reste est gardé au Trousseau.
struct CommunitySession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: UUID
    var email: String
    var username: String
}

enum CommunityError: Error, LocalizedError, Equatable {
    case notConfigured
    case invalid(String)
    case emailToConfirm
    case server(Int, String)
    case network(String)
    case badResponse
    /// La sauvegarde du compte a été changée ailleurs depuis la dernière lue par ce Mac (supabase/sauvegarde.sql).
    case backupConflict
    /// Le serveur n'a pas encore supabase/profil.sql : ni photo, ni changement de pseudo.
    case profileNotReady

    var errorDescription: String? {
        switch self {
        case .notConfigured: return String(localized: "La Communauté n'est pas encore ouverte dans cette version.")
        case .invalid(let why): return why
        case .emailToConfirm: return String(localized: "Compte créé : entre le code reçu par mail pour le confirmer.")
        case .server(_, let message): return message
        case .network(let why): return String(localized: "Connexion impossible : \(why)")
        case .badResponse: return String(localized: "Réponse inattendue du serveur.")
        case .backupConflict: return String(localized: "La sauvegarde de ton compte a changé depuis un autre Mac.")
        case .profileNotReady:
            return String(localized: "Les photos et le changement de pseudo ne sont pas encore ouverts : réessaie plus tard.")
        }
    }
}

/// Règles des champs, vérifiées avant tout envoi (le serveur les revérifie).
enum CommunityRules {
    static let minPassword = 8
    static let titleRange = 3...80
    static let maxNotes = 4000
    static let maxPayload = 262_144

    static func usernameProblem(_ s: String) -> String? {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-")
        guard (3...24).contains(s.count), s.unicodeScalars.allSatisfy(allowed.contains) else {
            return String(localized: """
                Pseudo : 3 à 24 caractères, lettres sans accent, chiffres, « _ », « . » ou « - ».
                """)
        }
        return nil
    }

    static func emailProblem(_ s: String) -> String? {
        let parts = s.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."), !s.contains(" "), s.count <= 254 else {
            return String(localized: "Adresse mail invalide.")
        }
        return nil
    }

    /// Mêmes exigences que celles réglées dans Supabase (Authentication › Email › Password requirements :
    /// minuscules, majuscules, chiffres et symboles), avec les mêmes caractères : lettres sans accent.
    static let passwordRule = String(localized: """
        8 caractères au moins, avec une minuscule, une majuscule, un chiffre et un symbole
        """)
    static let passwordSets: [(name: String, chars: String)] = [
        (String(localized: "une minuscule"), "abcdefghijklmnopqrstuvwxyz"),
        (String(localized: "une majuscule"), "ABCDEFGHIJKLMNOPQRSTUVWXYZ"),
        (String(localized: "un chiffre"), "0123456789"),
        (String(localized: "un symbole"), "!@#$%^&*()_+-=[]{};'\\:\"|<>?,./`~"),
    ]

    /// Ce qui manque encore au mot de passe, dans l'ordre (« 3 caractères », « une majuscule »…) ; vide : accepté.
    static func passwordMissing(_ s: String) -> [String] {
        let short = minPassword - s.count
        let length: [String] = short <= 0 ? []
            : [short == 1 ? String(localized: "1 caractère") : String(localized: "\(short) caractères")]
        return length + passwordSets.filter { group in !s.contains { group.chars.contains($0) } }.map(\.name)
    }

    /// Code reçu par mail (confirmation de l'inscription, mot de passe oublié) : 6 à 10 chiffres, espaces ignorés.
    static func code(_ s: String) -> String? {
        let digits = s.filter { !$0.isWhitespace }
        return (6...10).contains(digits.count) && digits.allSatisfy(\.isASCII) && digits.allSatisfy(\.isNumber) ? digits : nil
    }

    static func passwordProblem(_ s: String) -> String? {
        passwordMissing(s).isEmpty ? nil : String(localized: "Mot de passe : \(passwordRule).")
    }

    static func shareProblem(title: String, notes: String, payload: Data) -> String? {
        if !titleRange.contains(title.trimmingCharacters(in: .whitespacesAndNewlines).count) {
            return String(localized: "Titre : \(titleRange.lowerBound) à \(titleRange.upperBound) caractères.")
        }
        if notes.count > maxNotes { return String(localized: "Notes : \(maxNotes) caractères au plus.") }
        if payload.count > maxPayload { return String(localized: "Fichier trop volumineux pour être partagé.") }
        return nil
    }
}

/// Envoi d'une requête (URLSession dans l'app, faux serveur dans les tests).
protocol CommunityTransport {
    func send(_ request: URLRequest) async throws -> (Data, Int)
}

struct URLSessionTransport: CommunityTransport {
    /// Session éphémère : ni cookie, ni cache, ni identifiant gardé sur le disque.
    static let session: URLSession = {
        let c = URLSessionConfiguration.ephemeral
        c.timeoutIntervalForRequest = 20
        c.waitsForConnectivity = false
        return URLSession(configuration: c)
    }()

    func send(_ request: URLRequest) async throws -> (Data, Int) {
        do {
            let (data, response) = try await Self.session.data(for: request)
            return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
        } catch {
            throw CommunityError.network(error.localizedDescription)
        }
    }
}

struct CommunityClient {
    let config: CommunityConfig
    var transport: CommunityTransport = URLSessionTransport()
    var now: () -> Date = Date.init

    // MARK: Comptes

    func usernameAvailable(_ name: String) async throws -> Bool {
        let data = try await call("POST", "rest/v1/rpc/username_available", body: ["name": name])
        guard let available = try? JSONDecoder().decode(Bool.self, from: data) else { throw CommunityError.badResponse }
        return available
    }

    /// Crée le compte. Renvoie la session si le serveur connecte tout de suite ; `.emailToConfirm` sinon.
    func signUp(email: String, password: String, username: String) async throws -> CommunitySession {
        if let why = CommunityRules.emailProblem(email) ?? CommunityRules.passwordProblem(password)
            ?? CommunityRules.usernameProblem(username) {
            throw CommunityError.invalid(why)
        }
        guard try await usernameAvailable(username) else {
            throw CommunityError.invalid(String(localized: "Ce pseudo est déjà pris."))
        }
        let data = try await call("POST", "auth/v1/signup",
                                  body: ["email": email, "password": password, "data": ["username": username]])
        guard let session = try? decodeSession(data) else { throw CommunityError.emailToConfirm }
        return session
    }

    func signIn(email: String, password: String) async throws -> CommunitySession {
        if let why = CommunityRules.emailProblem(email) { throw CommunityError.invalid(why) }
        do {
            let data = try await call("POST", "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "password")],
                                      body: ["email": email, "password": password])
            return try decodeSession(data)
        } catch CommunityError.server(_, let message) where message == Self.unconfirmedMessage {
            throw CommunityError.emailToConfirm                 // compte créé, code jamais tapé
        }
    }

    func refresh(_ session: CommunitySession) async throws -> CommunitySession {
        let data = try await call("POST", "auth/v1/token",
                                  query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
                                  body: ["refresh_token": session.refreshToken])
        return try decodeSession(data)
    }

    /// Compte administrateur (table admins) : peut supprimer n'importe quel partage.
    func isAdmin(session: CommunitySession) async -> Bool {
        guard let data = try? await call("POST", "rest/v1/rpc/is_admin", token: session.accessToken, body: [:]) else {
            return false
        }
        return (try? JSONDecoder().decode(Bool.self, from: data)) ?? false
    }

    func signOut(_ session: CommunitySession) async {
        _ = try? await call("POST", "auth/v1/logout", token: session.accessToken)
    }

    /// Mot de passe oublié : un code part par mail (modèle « Reset password » de Supabase, avec {{ .Token }}).
    func resetPassword(email: String) async throws {
        if let why = CommunityRules.emailProblem(email) { throw CommunityError.invalid(why) }
        _ = try await call("POST", "auth/v1/recover", body: ["email": email])
    }

    /// Ce que confirme un code reçu par mail.
    enum CodeKind: String {
        case signup, recovery
    }

    /// Vérifie le code reçu par mail ; le serveur connecte le compte.
    func verifyCode(email: String, code: String, kind: CodeKind) async throws -> CommunitySession {
        guard let token = CommunityRules.code(code) else {
            throw CommunityError.invalid(String(localized: "Le code fait 6 chiffres : recopie-le depuis le mail."))
        }
        let data = try await call("POST", "auth/v1/verify",
                                  body: ["type": kind.rawValue, "email": email, "token": token])
        return try decodeSession(data)
    }

    /// Nouveau code de confirmation de l'inscription.
    func resendSignupCode(email: String) async throws {
        if let why = CommunityRules.emailProblem(email) { throw CommunityError.invalid(why) }
        _ = try await call("POST", "auth/v1/resend", body: ["type": "signup", "email": email])
    }

    /// Nouveau mot de passe du compte connecté (après le code du mot de passe oublié).
    func updatePassword(_ password: String, session: CommunitySession) async throws {
        if let why = CommunityRules.passwordProblem(password) { throw CommunityError.invalid(why) }
        _ = try await call("PUT", "auth/v1/user", token: session.accessToken, body: ["password": password])
    }

    // MARK: Profil (pseudo et photo : supabase/profil.sql)

    /// Une photo de profil : le JPEG (256 × 256) et sa date, qui sert de version (rechargée seulement si elle change).
    struct Avatar: Equatable {
        let version: String
        let jpeg: Data
    }

    /// Nouveau pseudo du compte connecté : les partages déjà publiés prennent le nouveau. Renvoie le pseudo enregistré.
    func setUsername(_ name: String, session: CommunitySession) async throws -> String {
        if let why = CommunityRules.usernameProblem(name) { throw CommunityError.invalid(why) }
        let data = try await profileCall("POST", "rest/v1/rpc/set_username", token: session.accessToken, body: ["p_name": name])
        return (try? JSONDecoder().decode(String.self, from: data)) ?? name
    }

    /// Pose ou remplace la photo du compte (JPEG préparé par ProfilePhoto). Renvoie sa version.
    func setAvatar(_ jpeg: Data, session: CommunitySession) async throws -> String {
        guard ProfilePhoto.isAcceptable(jpeg) else {
            throw CommunityError.invalid(String(localized: "Photo trop grande ou illisible : choisis-en une autre."))
        }
        let data = try await profileCall("POST", "rest/v1/rpc/set_avatar", token: session.accessToken,
                                         body: ["p_image": jpeg.base64EncodedString()])
        return (try? JSONDecoder().decode(String.self, from: data)) ?? ""
    }

    /// Retire la photo du compte (l'initiale de couleur revient).
    func removeAvatar(session: CommunitySession) async throws {
        _ = try await profileCall("POST", "rest/v1/rpc/remove_avatar", token: session.accessToken, body: [:])
    }

    /// Administrateur : retire la photo d'un membre (après un signalement).
    func adminRemoveAvatar(of userID: UUID, session: CommunitySession) async throws {
        _ = try await profileCall("POST", "rest/v1/rpc/admin_remove_avatar", token: session.accessToken,
                                  body: ["p_user": userID.uuidString.lowercased()])
    }

    /// « Signaler la photo… » : un signalement par photo et par compte, lu par les administrateurs.
    func reportAvatar(of userID: UUID, session: CommunitySession) async throws {
        _ = try await profileCall("POST", "rest/v1/avatar_reports", token: session.accessToken,
                                  body: ["user_id": userID.uuidString.lowercased()])
    }

    /// Dates des photos de ces membres (sans les images) : seules celles qui ont changé sont rechargées. Membre absent :
    /// pas de photo. Serveur sans photos (profil.sql pas encore collé) : aucune.
    func avatarVersions(of ids: [UUID], session: CommunitySession) async throws -> [UUID: String] {
        guard !ids.isEmpty else { return [:] }
        struct Row: Decodable { let user_id: UUID; let updated_at: String }
        let rows: [Row] = try await avatarRows("user_id,updated_at", ids, session)
        return Dictionary(rows.map { ($0.user_id, $0.updated_at) }, uniquingKeysWith: { a, _ in a })
    }

    /// Les photos de ces membres (une requête pour toutes) ; une image illisible est ignorée.
    func avatars(of ids: [UUID], session: CommunitySession) async throws -> [UUID: Avatar] {
        guard !ids.isEmpty else { return [:] }
        struct Row: Decodable { let user_id: UUID; let image: String; let updated_at: String }
        let rows: [Row] = try await avatarRows("user_id,image,updated_at", ids, session)
        var out: [UUID: Avatar] = [:]
        for row in rows {
            guard let jpeg = Data(base64Encoded: row.image), ProfilePhoto.isAcceptable(jpeg) else { continue }
            out[row.user_id] = Avatar(version: row.updated_at, jpeg: jpeg)
        }
        return out
    }

    /// Pure (testée) : membres demandés, sans doublon, 60 au plus (une adresse courte).
    static func avatarFilter(_ ids: [UUID]) -> String {
        var seen = Set<UUID>()
        let unique = ids.filter { seen.insert($0).inserted }.prefix(60)
        return "in.(" + unique.map { $0.uuidString.lowercased() }.joined(separator: ",") + ")"
    }

    private func avatarRows<Row: Decodable>(_ columns: String, _ ids: [UUID], _ session: CommunitySession) async throws -> [Row] {
        let data: Data
        do {
            data = try await call("GET", "rest/v1/avatars",
                                  query: [URLQueryItem(name: "select", value: columns),
                                          URLQueryItem(name: "user_id", value: Self.avatarFilter(ids))],
                                  token: session.accessToken)
        } catch CommunityError.server(404, _) {
            return []                                     // serveur sans photos : l'initiale reste
        }
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else { throw CommunityError.badResponse }
        return rows
    }

    /// Requête du profil : fonction ou table absente du serveur (404 : profil.sql pas encore collé) → pas encore ouvert.
    private func profileCall(_ method: String, _ path: String, token: String, body: [String: Any]) async throws -> Data {
        do {
            return try await call(method, path, token: token, body: body)
        } catch CommunityError.server(404, _) {
            throw CommunityError.profileNotReady
        }
    }

    // MARK: Partages

    static let listColumns = "id,author_id,kind,title,notes,app_version,created_at,author:profiles(username)"

    /// Les 50 partages les plus récents, filtrés par sorte, par texte (titre ou notes) et par auteur.
    func shares(kind: ShareKind?, search: String, authorID: UUID? = nil,
                session: CommunitySession) async throws -> [Share] {
        var query = [URLQueryItem(name: "select", value: Self.listColumns),
                     URLQueryItem(name: "order", value: "created_at.desc"),
                     URLQueryItem(name: "limit", value: "50")]
        if let kind { query.append(URLQueryItem(name: "kind", value: "eq.\(kind.rawValue)")) }
        if let authorID { query.append(URLQueryItem(name: "author_id", value: "eq.\(authorID.uuidString.lowercased())")) }
        let words = Self.searchPattern(search)
        if !words.isEmpty {
            query.append(URLQueryItem(name: "or", value: "(title.ilike.*\(words)*,notes.ilike.*\(words)*)"))
        }
        let data = try await call("GET", "rest/v1/shares", query: query, token: session.accessToken)
        guard let list = try? JSONDecoder().decode([Share].self, from: data) else { throw CommunityError.badResponse }
        return list
    }

    /// Membres dont le nom contient la recherche, parmi ceux qui ont publié (un compte sans partage n'apparaît
    /// jamais) : les plus actifs d'abord, 8 au plus.
    func members(matching search: String, session: CommunitySession) async throws -> [CommunityMember] {
        guard let name = Self.memberPattern(search) else { return [] }
        let query = [URLQueryItem(name: "select", value: "author_id,author:profiles!inner(username)"),
                     URLQueryItem(name: "author.username", value: "ilike.*\(name)*"),
                     URLQueryItem(name: "limit", value: "500")]
        let data = try await call("GET", "rest/v1/shares", query: query, token: session.accessToken)
        struct Row: Decodable {
            let authorID: UUID
            let author: Share.Author
            enum CodingKeys: String, CodingKey {
                case author
                case authorID = "author_id"
            }
        }
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else { throw CommunityError.badResponse }
        return Self.members(rows.map { (id: $0.authorID, username: $0.author.username) })
    }

    /// Pure (testée) : nom d'utilisateur cherché (« @leo.beats » → « leo.beats »), ou nil si la recherche n'en est pas
    /// un (espace, accent, signe : un titre). Deux caractères au moins.
    static func memberPattern(_ s: String) -> String? {
        var name = s.trimmingCharacters(in: .whitespaces)
        if name.hasPrefix("@") { name.removeFirst() }
        guard (2...24).contains(name.count),
              name.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "_.-".contains($0)) }) else { return nil }
        return name
    }

    /// Pure (testée) : un membre par auteur avec son nombre de partages, les plus actifs d'abord, puis par nom.
    static func members(_ rows: [(id: UUID, username: String)], max: Int = 8) -> [CommunityMember] {
        var counts: [UUID: (username: String, count: Int)] = [:]
        for row in rows { counts[row.id, default: (row.username, 0)].count += 1 }
        return counts.map { CommunityMember(id: $0.key, username: $0.value.username, shareCount: $0.value.count) }
            .sorted { ($0.shareCount, $1.username.lowercased()) > ($1.shareCount, $0.username.lowercased()) }
            .prefix(max)
            .map { $0 }
    }

    /// Texte de recherche sans les caractères qui ont un sens dans un filtre du serveur.
    static func searchPattern(_ s: String) -> String {
        let kept = s.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) || $0 == " " || $0 == "-" || $0 == "'" }
        return String(String.UnicodeScalarView(kept)).trimmingCharacters(in: .whitespaces).prefix(60).description
    }

    /// Le fichier partagé, pour l'import.
    func payload(of id: UUID, session: CommunitySession) async throws -> Data {
        let data = try await call("GET", "rest/v1/shares",
                                  query: [URLQueryItem(name: "select", value: "payload"),
                                          URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")],
                                  token: session.accessToken)
        struct Row: Decodable { let payload: String }
        guard let row = (try? JSONDecoder().decode([Row].self, from: data))?.first,
              let file = row.payload.data(using: .utf8), file.count <= CommunityRules.maxPayload else {
            throw CommunityError.badResponse
        }
        return file
    }

    func publish(kind: ShareKind, title: String, notes: String, payload: Data, appVersion: String,
                 session: CommunitySession) async throws {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let why = CommunityRules.shareProblem(title: title, notes: notes, payload: payload) {
            throw CommunityError.invalid(why)
        }
        guard let text = String(data: payload, encoding: .utf8) else {
            throw CommunityError.invalid(String(localized: "Fichier illisible."))
        }
        _ = try await call("POST", "rest/v1/shares", token: session.accessToken,
                           body: ["kind": kind.rawValue, "title": title, "notes": notes, "payload": text,
                                  "app_version": String(appVersion.prefix(20))])
    }

    func delete(_ id: UUID, session: CommunitySession) async throws {
        _ = try await call("DELETE", "rest/v1/shares",
                           query: [URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")],
                           token: session.accessToken)
    }

    func report(_ id: UUID, reason: String, session: CommunitySession) async throws {
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (3...500).contains(reason.count) else {
            throw CommunityError.invalid(String(localized: "Raison : 3 à 500 caractères."))
        }
        _ = try await call("POST", "rest/v1/reports", token: session.accessToken,
                           body: ["share_id": id.uuidString.lowercased(), "reason": reason])
    }

    // MARK: Sauvegarde du compte

    /// Révision et date de la sauvegarde du compte, sans son contenu (vérification rapide) ; nil : pas encore.
    func backupRevision(session: CommunitySession) async throws -> (revision: Int64, updatedAt: Date?)? {
        let data = try await call("GET", "rest/v1/backups", query: [URLQueryItem(name: "select", value: "revision,updated_at")],
                                  token: session.accessToken)
        struct Row: Decodable { let revision: Int64; let updated_at: String? }
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else { throw CommunityError.badResponse }
        return rows.first.map { ($0.revision, $0.updated_at.flatMap(CommunityText.date)) }
    }

    /// La sauvegarde du compte ; nil : pas encore de sauvegarde.
    func backup(session: CommunitySession) async throws -> RemoteBackup? {
        let data = try await call("GET", "rest/v1/backups",
                                  query: [URLQueryItem(name: "select", value: "profile,macros,revision,updated_at")],
                                  token: session.accessToken)
        struct Row: Decodable { let profile: String; let macros: String; let revision: Int64; let updated_at: String? }
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else { throw CommunityError.badResponse }
        return rows.first.map {
            RemoteBackup(content: BackupContent(profile: $0.profile, macros: $0.macros), revision: $0.revision,
                         updatedAt: $0.updated_at.flatMap(CommunityText.date))
        }
    }

    /// Enregistre la sauvegarde si elle est toujours à la révision `base` (sinon `.backupConflict`), ou quoi qu'il y
    /// ait si `force`. Renvoie la nouvelle révision.
    func saveBackup(_ content: BackupContent, base: Int64, force: Bool, appVersion: String,
                    session: CommunitySession) async throws -> Int64 {
        let data: Data
        do {
            data = try await call("POST", "rest/v1/rpc/save_backup", token: session.accessToken,
                                  body: ["p_profile": content.profile, "p_macros": content.macros, "p_base": base,
                                         "p_force": force, "p_app_version": String(appVersion.prefix(20))])
        } catch CommunityError.server(_, let message) where message.hasPrefix("Sauvegarde plus récente") {
            throw CommunityError.backupConflict
        }
        guard let revision = try? JSONDecoder().decode(Int64.self, from: data) else { throw CommunityError.badResponse }
        return revision
    }

    /// Supprime le compte et tout ce qui en dépend sur le serveur (profil, partages, signalements, sauvegarde).
    func deleteAccount(session: CommunitySession) async throws {
        _ = try await call("POST", "rest/v1/rpc/delete_my_account", token: session.accessToken, body: [:])
    }

    // MARK: Aide

    /// « Écrire à l'équipe » (page Aide) : avec le jeton du compte s'il y en a un, sinon la clé publique seule.
    func sendSupport(_ message: SupportMessage, appVersion: String, token: String?) async throws {
        if let why = SupportRules.problem(message) { throw CommunityError.invalid(why) }
        var body: [String: Any] = ["kind": message.kind.rawValue,
                                   "reference": message.reference,
                                   "message": message.text.trimmingCharacters(in: .whitespacesAndNewlines),
                                   "error": String((message.error ?? "").prefix(2000)),
                                   "diagnostic": String((message.diagnostic ?? "").prefix(SupportRules.maxDiagnostic)),
                                   "app_version": String(appVersion.prefix(20))]
        let mail = message.email.trimmingCharacters(in: .whitespaces)
        if !mail.isEmpty { body["email"] = mail }
        _ = try await call("POST", "rest/v1/support_requests", token: token, body: body)
    }

    // MARK: IA intégrée

    /// Une correction de l'Organiser partagée (accord donné) : des nombres et des noms de familles et de sortes,
    /// jamais le son, son nom ni un texte tapé (supabase/corrections-ia.sql ; JSON fait par CorrectionsIA.envoi).
    func sendCorrection(_ json: Data, token: String?) async throws {
        guard let corps = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] else {
            throw CommunityError.badResponse
        }
        _ = try await call("POST", "rest/v1/corrections_ia", token: token, body: corps)
    }

    // MARK: Requêtes

    func request(_ method: String, _ path: String, query: [URLQueryItem] = [], token: String? = nil,
                 body: [String: Any]? = nil) throws -> URLRequest {
        var components = URLComponents(url: config.url.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else { throw CommunityError.badResponse }
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        // Jeton du compte connecté ; sans compte, l'ancienne clé « anon » (un JWT, « eyJ… ») sert aussi de jeton.
        // La nouvelle clé publique de Supabase (« sb_publishable_… ») n'en est pas un : envoyée en Authorization,
        // le serveur refuserait la requête ; « apikey » suffit alors.
        if let bearer = token ?? (config.anonKey.hasPrefix("eyJ") ? config.anonKey : nil) {
            r.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        }
        if let body {
            r.httpBody = try JSONSerialization.data(withJSONObject: body)
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return r
    }

    private func call(_ method: String, _ path: String, query: [URLQueryItem] = [], token: String? = nil,
                      body: [String: Any]? = nil) async throws -> Data {
        let (data, status) = try await transport.send(request(method, path, query: query, token: token, body: body))
        guard (200..<300).contains(status) else { throw CommunityError.server(status, Self.message(data, status: status)) }
        return data
    }

    static let unconfirmedMessage = String(localized: "Confirme d'abord ton adresse mail avec le code reçu par mail.")

    /// Message du serveur, traduit pour les cas courants.
    static func message(_ data: Data, status: Int) -> String {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let raw = (json?["error_description"] ?? json?["msg"] ?? json?["message"] ?? json?["error"]) as? String ?? ""
        let lower = raw.lowercased()
        if lower.contains("invalid login credentials") { return String(localized: "Mail ou mot de passe incorrect.") }
        if lower.contains("email not confirmed") || (json?["error_code"] as? String) == "email_not_confirmed" {
            return unconfirmedMessage
        }
        if lower.contains("already registered") || lower.contains("already exists") {
            return String(localized: "Un compte existe déjà avec ce mail.")
        }
        let code = json?["error_code"] as? String
        if code == "otp_expired" || lower.contains("token has expired") || lower.contains("token is invalid")
            || lower.contains("otp has expired") {
            return String(localized: "Code incorrect ou expiré : vérifie-le, ou demande un nouveau code.")
        }
        if code == "same_password" || lower.contains("should be different") {
            return String(localized: "Choisis un mot de passe différent de l'ancien.")
        }
        if (json?["error_code"] as? String) == "weak_password" || lower.contains("password should") {
            return String(localized: "Mot de passe trop faible : \(CommunityRules.passwordRule).")
        }
        if lower.contains("error sending") || lower.contains("not authorized") {
            return String(localized: """
                Le mail de confirmation n'a pas pu partir. Réessaie plus tard, ou écris à l'équipe depuis la page Aide.
                """)
        }
        if lower.contains("trop de partages") || lower.contains("trop de messages") || lower.hasPrefix("sauvegarde plus récente")
            || lower.hasPrefix("attends ") || lower.hasPrefix("réservé aux administrateurs") {
            return raw
        }
        if lower.contains("pseudo déjà pris") || lower.contains("profiles_username") {
            return String(localized: "Ce pseudo est déjà pris.")
        }
        if lower.contains("pseudo invalide") {
            return CommunityRules.usernameProblem("") ?? raw
        }
        if lower.contains("avatars_image_check") {
            return String(localized: "Photo trop grande ou illisible : choisis-en une autre.")
        }
        if lower.contains("avatar_reports_user_id_reporter_id_key") {
            return String(localized: "Tu as déjà signalé cette photo.")
        }
        if lower.contains("backups_profile_check") || lower.contains("backups_macros_check") {
            return String(localized: """
                Sauvegarde trop grande pour le serveur (2 Mo de raccourcis, 6 Mo de macros au plus).
                """)
        }
        if status == 401 || status == 403 { return String(localized: "Session expirée : reconnecte-toi.") }
        if status == 429 { return String(localized: "Trop de tentatives : réessaie dans quelques minutes.") }
        return raw.isEmpty ? String(localized: "Erreur du serveur (\(status)).")
            : String(localized: "Erreur du serveur : \(String(raw.prefix(200)))")
    }

    func decodeSession(_ data: Data) throws -> CommunitySession {
        struct Token: Decodable {
            struct User: Decodable {
                /// Seul le nom est lu (les métadonnées contiennent aussi des booléens, comme email_verified).
                struct Meta: Decodable { let username: String? }
                let id: UUID
                let email: String?
                let user_metadata: Meta?
            }
            let access_token: String
            let refresh_token: String
            let expires_in: Double
            let user: User
        }
        guard let t = try? JSONDecoder().decode(Token.self, from: data) else { throw CommunityError.badResponse }
        return CommunitySession(accessToken: t.access_token, refreshToken: t.refresh_token,
                                expiresAt: now().addingTimeInterval(t.expires_in), userID: t.user.id,
                                email: t.user.email ?? "", username: t.user.user_metadata?.username ?? "")
    }
}
