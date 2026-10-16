// Communauté : client du serveur Supabase (comptes et partages), par son API REST, sans bibliothèque ajoutée.
// Le réseau n'est utilisé que sur la page Communauté, à la demande de l'utilisateur : jamais au repos, jamais pour les
// raccourcis ni les macros. Sans compte connecté, le serveur ne renvoie rien (règles « authenticated » seulement :
// supabase/schema.sql). Le mot de passe n'est jamais gardé : seul le jeton de rafraîchissement l'est, au Trousseau.
import Foundation

/// Adresse du projet Supabase et sa clé publique (« anon », publique par conception : les règles du serveur
/// protègent les données). Lues dans l'Info.plist (build.sh : FLS_SUPABASE_URL, FLS_SUPABASE_ANON_KEY), ou dans les
/// réglages pour un essai (`defaults write app.flshortcut.FLShortcut communityURL …`).
struct CommunityConfig: Equatable {
    let url: URL
    let anonKey: String

    static var current: CommunityConfig? {
        let info = Bundle.main.infoDictionary
        let defaults = UserDefaults.standard
        let rawURL = defaults.string(forKey: "communityURL") ?? info?["FLSCommunityURL"] as? String ?? ""
        let key = defaults.string(forKey: "communityAnonKey") ?? info?["FLSCommunityAnonKey"] as? String ?? ""
        guard let url = URL(string: rawURL), url.scheme == "https", url.host != nil, !key.isEmpty else { return nil }
        return CommunityConfig(url: url, anonKey: key)
    }
}

enum ShareKind: String, Codable, CaseIterable, Identifiable {
    case macro, profile

    var id: String { rawValue }
    var label: String { self == .macro ? "Macro" : "Raccourcis" }
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

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "La Communauté n'est pas encore ouverte dans cette version."
        case .invalid(let why): return why
        case .emailToConfirm: return "Compte créé : ouvre le mail de confirmation, puis connecte-toi."
        case .server(_, let message): return message
        case .network(let why): return "Connexion impossible : \(why)"
        case .badResponse: return "Réponse inattendue du serveur."
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
            return "Nom d'utilisateur : 3 à 24 caractères, lettres sans accent, chiffres, « _ », « . » ou « - »."
        }
        return nil
    }

    static func emailProblem(_ s: String) -> String? {
        let parts = s.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains("."), !s.contains(" "), s.count <= 254 else {
            return "Adresse mail invalide."
        }
        return nil
    }

    /// Mêmes exigences que celles réglées dans Supabase (Authentication › Email › Password requirements :
    /// minuscules, majuscules, chiffres et symboles), avec les mêmes caractères : lettres sans accent.
    static let passwordRule = "8 caractères au moins, avec une minuscule, une majuscule, un chiffre et un symbole"
    static let passwordSets: [(name: String, chars: String)] = [
        ("une minuscule", "abcdefghijklmnopqrstuvwxyz"),
        ("une majuscule", "ABCDEFGHIJKLMNOPQRSTUVWXYZ"),
        ("un chiffre", "0123456789"),
        ("un symbole", "!@#$%^&*()_+-=[]{};'\\:\"|<>?,./`~"),
    ]

    /// Ce qui manque encore au mot de passe, dans l'ordre (« 3 caractères », « une majuscule »…) ; vide : accepté.
    static func passwordMissing(_ s: String) -> [String] {
        let short = minPassword - s.count
        let length: [String] = short <= 0 ? [] : [short == 1 ? "1 caractère" : "\(short) caractères"]
        return length + passwordSets.filter { group in !s.contains { group.chars.contains($0) } }.map(\.name)
    }

    static func passwordProblem(_ s: String) -> String? {
        passwordMissing(s).isEmpty ? nil : "Mot de passe : \(passwordRule)."
    }

    static func shareProblem(title: String, notes: String, payload: Data) -> String? {
        if !titleRange.contains(title.trimmingCharacters(in: .whitespacesAndNewlines).count) {
            return "Titre : \(titleRange.lowerBound) à \(titleRange.upperBound) caractères."
        }
        if notes.count > maxNotes { return "Notes : \(maxNotes) caractères au plus." }
        if payload.count > maxPayload { return "Fichier trop volumineux pour être partagé." }
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
            throw CommunityError.invalid("Ce nom d'utilisateur est déjà pris.")
        }
        let data = try await call("POST", "auth/v1/signup",
                                  body: ["email": email, "password": password, "data": ["username": username]])
        guard let session = try? decodeSession(data) else { throw CommunityError.emailToConfirm }
        return session
    }

    func signIn(email: String, password: String) async throws -> CommunitySession {
        if let why = CommunityRules.emailProblem(email) { throw CommunityError.invalid(why) }
        let data = try await call("POST", "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "password")],
                                  body: ["email": email, "password": password])
        return try decodeSession(data)
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

    /// Mail de remise à zéro du mot de passe.
    func resetPassword(email: String) async throws {
        if let why = CommunityRules.emailProblem(email) { throw CommunityError.invalid(why) }
        _ = try await call("POST", "auth/v1/recover", body: ["email": email])
    }

    // MARK: Partages

    static let listColumns = "id,author_id,kind,title,notes,app_version,created_at,author:profiles(username)"

    /// Les 50 partages les plus récents, filtrés par sorte et par texte (titre ou notes).
    func shares(kind: ShareKind?, search: String, session: CommunitySession) async throws -> [Share] {
        var query = [URLQueryItem(name: "select", value: Self.listColumns),
                     URLQueryItem(name: "order", value: "created_at.desc"),
                     URLQueryItem(name: "limit", value: "50")]
        if let kind { query.append(URLQueryItem(name: "kind", value: "eq.\(kind.rawValue)")) }
        let words = Self.searchPattern(search)
        if !words.isEmpty {
            query.append(URLQueryItem(name: "or", value: "(title.ilike.*\(words)*,notes.ilike.*\(words)*)"))
        }
        let data = try await call("GET", "rest/v1/shares", query: query, token: session.accessToken)
        guard let list = try? JSONDecoder().decode([Share].self, from: data) else { throw CommunityError.badResponse }
        return list
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
        guard let text = String(data: payload, encoding: .utf8) else { throw CommunityError.invalid("Fichier illisible.") }
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
        guard (3...500).contains(reason.count) else { throw CommunityError.invalid("Raison : 3 à 500 caractères.") }
        _ = try await call("POST", "rest/v1/reports", token: session.accessToken,
                           body: ["share_id": id.uuidString.lowercased(), "reason": reason])
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

    /// Message du serveur, traduit pour les cas courants.
    static func message(_ data: Data, status: Int) -> String {
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let raw = (json?["error_description"] ?? json?["msg"] ?? json?["message"] ?? json?["error"]) as? String ?? ""
        let lower = raw.lowercased()
        if lower.contains("invalid login credentials") { return "Mail ou mot de passe incorrect." }
        if lower.contains("email not confirmed") { return "Confirme d'abord ton adresse mail (lien reçu par mail)." }
        if lower.contains("already registered") || lower.contains("already exists") {
            return "Un compte existe déjà avec ce mail."
        }
        if (json?["error_code"] as? String) == "weak_password" || lower.contains("password should") {
            return "Mot de passe trop faible : \(CommunityRules.passwordRule)."
        }
        if lower.contains("error sending") || lower.contains("not authorized") {
            return "Le mail de confirmation n'a pas pu partir. Réessaie plus tard, ou écris à l'équipe depuis la page Aide."
        }
        if lower.contains("trop de partages") || lower.contains("trop de messages") { return raw }
        if status == 401 || status == 403 { return "Session expirée : reconnecte-toi." }
        if status == 429 { return "Trop de tentatives : réessaie dans quelques minutes." }
        return raw.isEmpty ? "Erreur du serveur (\(status))." : "Erreur du serveur : \(raw.prefix(200))"
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
