// Communauté du 11/11 (« suivre des gens par leur travail de macro… les pages des gens… des notes pour chaque
// macro », docs/superpowers/specs/2026-11-11-communaute-suivre-design.md ; serveur : supabase/communaute-suivre.sql) :
// onglets, abonnements, « Ajoutée N fois », étoiles, page d'une personne et point rouge. Sans le fichier du serveur,
// tout se replie sur la Communauté d'avant (`CommunityError.socialNotReady` → `social` faux), sans erreur affichée.
// Windows : Community.cs et CommunityPage.cs, mêmes règles.
import Foundation

/// Onglets de la Communauté (vitrine validée le 11/11).
enum CommunityTab: String, CaseIterable, Identifiable {
    case forYou, following, mostAdded, mine

    var id: String { rawValue }

    var title: String {
        switch self {
        case .forYou: return String(localized: "Pour toi")
        case .following: return String(localized: "Abonnements")
        case .mostAdded: return String(localized: "Les plus ajoutées")
        case .mine: return String(localized: "Les miens")
        }
    }

    /// Onglets qui demandent le serveur du 11/11 (cachés sans lui).
    var needsSocial: Bool { self == .following || self == .mostAdded }
}

/// Ordre du travail d'une personne (sa page).
enum PersonSort: CaseIterable {
    case mostAdded, recent

    var title: String {
        switch self {
        case .mostAdded: return String(localized: "Les plus ajoutées")
        case .recent: return String(localized: "Les plus récentes")
        }
    }

    /// Ordre demandé au serveur.
    var order: String {
        switch self {
        case .mostAdded: return "add_count.desc,created_at.desc"
        case .recent: return "created_at.desc"
        }
    }
}

/// Un créateur (vitrine, page d'une personne) : son pseudo et son nombre d'abonnés, jamais la liste.
struct CommunityCreator: Identifiable, Equatable, Decodable {
    let id: UUID
    let username: String
    let followerCount: Int

    enum CodingKeys: String, CodingKey {
        case id, username
        case followerCount = "follower_count"
    }
}

/// Textes des nombres de la Communauté (purs, testés).
enum CommunityStats {
    /// « ★ 4,6 · Ajoutée 312 fois », « Ajoutée une fois », « ★ 5,0 » ; nil : rien à dire (jamais « Ajoutée 0 fois »).
    static func line(_ share: Share, locale: Locale = .current) -> String? {
        var parts: [String] = []
        if let value = share.rating { parts.append("★ " + rating(value, locale: locale)) }
        if let added = added(share.addCount ?? 0) { parts.append(added) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func added(_ count: Int) -> String? {
        switch count {
        case ..<1: return nil
        case 1: return String(localized: "Ajoutée une fois")
        default: return String(localized: "Ajoutée \(count) fois")
        }
    }

    /// Moyenne à une décimale, à la façon de la langue (« 4,6 » en français, « 4.6 » en anglais).
    static func rating(_ value: Double, locale: Locale = .current) -> String {
        formatter(locale, digits: 1).string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }

    /// « 1 abonné », « 1 284 abonnés ».
    static func followers(_ count: Int, locale: Locale = .current) -> String {
        if count == 1 { return String(localized: "1 abonné") }
        let text = number(count, locale: locale)
        return String(localized: "\(text) abonnés")
    }

    /// Un nombre à la façon de la langue (« 1 284 », « 1,284 »).
    static func number(_ count: Int, locale: Locale = .current) -> String {
        formatter(locale, digits: 0).string(from: NSNumber(value: count)) ?? String(count)
    }

    /// Un formateur par langue et nombre de décimales, créé une seule fois (14/11, optimisation : chaque carte de la
    /// Communauté en recréait deux à chaque dessin). NumberFormatter formate sans risque depuis plusieurs fils.
    private static let formatters = Locked<[String: NumberFormatter]>([:])

    private static func formatter(_ locale: Locale, digits: Int) -> NumberFormatter {
        let key = "\(locale.identifier)|\(digits)"
        return formatters.withLock { cache in
            if let f = cache[key] { return f }
            let f = NumberFormatter()
            f.locale = locale
            f.numberStyle = .decimal
            f.minimumFractionDigits = digits
            f.maximumFractionDigits = digits
            cache[key] = f
            return f
        }
    }

    /// Partages arrivés après `since` (point rouge et « N nouvelles »).
    static func newCount(_ shares: [Share], since: Date) -> Int {
        shares.filter { (CommunityText.date($0.createdAt) ?? .distantPast) > since }.count
    }
}

// MARK: - Serveur

extension CommunityClient {
    /// Pure (testée) : réponse d'un serveur sans communaute-suivre.sql (404 : fonction ou table absente ; 400 :
    /// colonne absente).
    static func isMissingSocial(status: Int, message: String) -> Bool {
        let m = message.lowercased()
        if status == 404 { return true }
        return status == 400 && (m.contains("does not exist") || m.contains("could not find"))
            && (m.contains("add_count") || m.contains("rating") || m.contains("follow") || m.contains("adds"))
    }

    /// Requête de la Communauté du 11/11 : fonction, table ou colonne absente du serveur → `socialNotReady`.
    func socialCall(_ method: String, _ path: String, query: [URLQueryItem] = [], session: CommunitySession,
                    body: [String: Any]? = nil) async throws -> Data {
        do {
            return try await call(method, path, query: query, token: session.accessToken, body: body)
        } catch CommunityError.server(let status, let message) where Self.isMissingSocial(status: status, message: message) {
            throw CommunityError.socialNotReady
        }
    }

    private func decodeShares(_ data: Data) throws -> [Share] {
        guard let list = try? JSONDecoder().decode([Share].self, from: data) else { throw CommunityError.badResponse }
        return list
    }

    /// Partages des gens que l'on suit, les plus récents d'abord.
    func followedShares(limit: Int, session: CommunitySession) async throws -> [Share] {
        try decodeShares(try await socialCall("POST", "rest/v1/rpc/followed_shares",
                                              query: [URLQueryItem(name: "select", value: Self.socialColumns)],
                                              session: session, body: ["p_limit": limit]))
    }

    /// Les plus ajoutés (à égalité, la meilleure note du créateur).
    func mostAdded(kind: ShareKind?, limit: Int, session: CommunitySession) async throws -> [Share] {
        let wanted: Any = kind.map { $0.rawValue as Any } ?? NSNull()
        return try decodeShares(try await socialCall("POST", "rest/v1/rpc/most_added",
                                                     query: [URLQueryItem(name: "select", value: Self.socialColumns)],
                                                     session: session, body: ["p_kind": wanted, "p_limit": limit]))
    }

    /// Créateurs à suivre : ni soi ni ceux qu'on suit déjà.
    func creatorsToFollow(limit: Int, session: CommunitySession) async throws -> [CommunityCreator] {
        let data = try await socialCall("POST", "rest/v1/rpc/creators_to_follow", session: session, body: ["p_limit": limit])
        guard let list = try? JSONDecoder().decode([CommunityCreator].self, from: data) else { throw CommunityError.badResponse }
        return list
    }

    /// Une personne : son pseudo et son nombre d'abonnés.
    func person(_ id: UUID, session: CommunitySession) async throws -> CommunityCreator? {
        let data = try await socialCall("GET", "rest/v1/profiles",
                                        query: [URLQueryItem(name: "select", value: "id,username,follower_count"),
                                                URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")],
                                        session: session)
        guard let list = try? JSONDecoder().decode([CommunityCreator].self, from: data) else { throw CommunityError.badResponse }
        return list.first
    }

    /// Les gens que l'on suit (le serveur ne rend que les siens).
    func following(session: CommunitySession) async throws -> Set<UUID> {
        struct Row: Decodable { let followee_id: UUID }
        let data = try await socialCall("GET", "rest/v1/follows",
                                        query: [URLQueryItem(name: "select", value: "followee_id")], session: session)
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else { throw CommunityError.badResponse }
        return Set(rows.map(\.followee_id))
    }

    func follow(_ id: UUID, session: CommunitySession) async throws {
        _ = try await socialCall("POST", "rest/v1/follows", session: session,
                                 body: ["followee_id": id.uuidString.lowercased()])
    }

    func unfollow(_ id: UUID, session: CommunitySession) async throws {
        _ = try await socialCall("DELETE", "rest/v1/follows",
                                 query: [URLQueryItem(name: "followee_id", value: "eq.\(id.uuidString.lowercased())")],
                                 session: session)
    }

    /// « Ajouter » compté sur le serveur (une fois par personne, jamais le sien) : le nombre d'ajouts du partage.
    func recordAdd(_ share: UUID, session: CommunitySession) async throws -> Int {
        let data = try await socialCall("POST", "rest/v1/rpc/record_add", session: session,
                                        body: ["p_share": share.uuidString.lowercased()])
        guard let count = try? JSONDecoder().decode(Int.self, from: data) else { throw CommunityError.badResponse }
        return count
    }

    /// Ce partage a-t-il été ajouté par moi, et ma note (nil : pas noté).
    func myRating(_ share: UUID, session: CommunitySession) async throws -> (added: Bool, stars: Int?) {
        struct Added: Decodable { let share_id: UUID }
        struct Rated: Decodable { let stars: Int }
        let filter = [URLQueryItem(name: "share_id", value: "eq.\(share.uuidString.lowercased())")]
        let adds = try await socialCall("GET", "rest/v1/adds", query: [URLQueryItem(name: "select", value: "share_id")] + filter,
                                        session: session)
        let rates = try await socialCall("GET", "rest/v1/ratings", query: [URLQueryItem(name: "select", value: "stars")] + filter,
                                         session: session)
        guard let added = try? JSONDecoder().decode([Added].self, from: adds),
              let rated = try? JSONDecoder().decode([Rated].self, from: rates) else { throw CommunityError.badResponse }
        return (!added.isEmpty, rated.first?.stars)
    }

    /// Ma note (1 à 5) : la somme et le nombre de notes du partage ensuite.
    func rate(_ share: UUID, stars: Int, session: CommunitySession) async throws -> (sum: Int, count: Int) {
        struct Row: Decodable { let rating_sum: Int; let rating_count: Int }
        let data = try await socialCall("POST", "rest/v1/rpc/rate_share", session: session,
                                        body: ["p_share": share.uuidString.lowercased(), "p_stars": stars])
        guard let row = (try? JSONDecoder().decode([Row].self, from: data))?.first else { throw CommunityError.badResponse }
        return (row.rating_sum, row.rating_count)
    }
}

// MARK: - État

extension CommunityStore {
    /// Dernière ouverture d'« Abonnements » (secondes depuis 1970), sur ce Mac seulement : rien de sensible.
    static let followedSeenKey = "communityFollowedSeen"

    var isPersonPage: Bool { author != nil && author?.id != session?.userID }

    /// 11/11 : sur la page d'une personne, son pseudo prend la place du titre « communauté. » de la fenêtre.
    var personName: String? { isPersonPage ? author?.username : nil }

    /// Retour de la page d'une personne à la liste (← du titre, ou « Communauté » de la barre de gauche).
    func leavePerson() async {
        await choose(tab == .mine ? .forYou : tab)
    }

    /// Partages de l'onglet, d'une recherche ou de la page d'une personne ; avec leurs nombres tant que le serveur
    /// les a (sinon : la Communauté d'avant).
    func loadShares(_ client: CommunityClient, _ session: CommunitySession) async throws -> [Share] {
        let searching = !search.trimmingCharacters(in: .whitespaces).isEmpty
        if social {
            do {
                if author == nil, !searching {
                    switch tab {
                    case .following:
                        let list = try await client.followedShares(limit: 50, session: session)
                        markFollowedSeen()
                        return list
                    case .mostAdded:
                        return try await client.mostAdded(kind: nil, limit: 50, session: session)
                    case .forYou, .mine:
                        break
                    }
                }
                return try await client.shares(kind: kind, search: search, authorID: author?.id, social: true,
                                               order: isPersonPage ? personSort.order : "created_at.desc", session: session)
            } catch CommunityError.socialNotReady {
                social = false
                if tab.needsSocial { tab = .forYou }
            }
        }
        return try await client.shares(kind: kind, search: search, authorID: author?.id, session: session)
    }

    /// Vitrine « Pour toi » : qui on suit, leurs 3 derniers partages, les 3 plus ajoutés, 5 créateurs à suivre. Sans
    /// réponse : la vitrine reste vide, les nouveautés suffisent.
    func loadShowcase() async {
        guard social, !demo, let client, session != nil, let session = try? await validSession() else { return }
        do {
            async let follows = client.following(session: session)
            async let followed = client.followedShares(limit: 3, session: session)
            async let top = client.mostAdded(kind: nil, limit: 3, session: session)
            async let people = client.creatorsToFollow(limit: 5, session: session)
            let (f, fp, tp, cr) = try await (follows, followed, top, people)
            following = f
            followedPreview = fp
            topPreview = tp
            creators = cr
        } catch CommunityError.socialNotReady {
            social = false
            followedPreview = []
            topPreview = []
            creators = []
        } catch {}
    }

    /// Un onglet choisi : la recherche s'efface, la liste suit.
    func choose(_ tab: CommunityTab) async {
        self.tab = tab
        search = ""
        kind = nil
        members = []
        if tab == .mine, let session {
            author = CommunityMember(id: session.userID, username: session.username, shareCount: 0)
        } else {
            author = nil
        }
        if tab == .following { markFollowedSeen() }
        if demo {
            showDemoTab()
            return
        }
        await reload()
    }

    /// La page d'une personne : son travail (les plus ajoutés d'abord), son nombre d'abonnés, et si on la suit.
    func openPerson(_ member: CommunityMember) async {
        guard member.id != session?.userID else {
            await choose(.mine)
            return
        }
        personFollowers = nil
        personSort = .mostAdded
        if demo {
            author = member
            members = []
            search = ""
            personFollowers = Self.demoFollowers
            shares = Self.demoShares.filter { $0.authorID == member.id }
            return
        }
        await showAuthor(member)
        guard social, let client, let session = try? await validSession() else { return }
        if let person = try? await client.person(member.id, session: session) { personFollowers = person.followerCount }
        if let mine = try? await client.following(session: session) { following = mine }
    }

    func openPerson(of share: Share) async {
        await openPerson(CommunityMember(id: share.authorID, username: share.authorName, shareCount: 0))
    }

    /// Autre ordre du travail d'une personne.
    func sortPerson(_ sort: PersonSort) async {
        personSort = sort
        if demo {
            shares.sort { sort == .mostAdded ? ($0.addCount ?? 0) > ($1.addCount ?? 0) : $0.createdAt > $1.createdAt }
            return
        }
        await reload()
    }

    func follow(_ id: UUID) async {
        guard id != session?.userID, !following.contains(id) else { return }
        if demo {
            following.insert(id)
            if author?.id == id { personFollowers = (personFollowers ?? 0) + 1 }
            return
        }
        await authed { client, session in
            try await client.follow(id, session: session)
            self.following.insert(id)
            if self.author?.id == id { self.personFollowers = (self.personFollowers ?? 0) + 1 }
        }
    }

    func unfollow(_ id: UUID) async {
        guard following.contains(id) else { return }
        if demo {
            following.remove(id)
            if author?.id == id { personFollowers = max((personFollowers ?? 1) - 1, 0) }
            return
        }
        await authed { client, session in
            try await client.unfollow(id, session: session)
            self.following.remove(id)
            if self.author?.id == id { self.personFollowers = max((self.personFollowers ?? 1) - 1, 0) }
        }
    }

    /// « Ajouter » compté une fois sur le serveur (jamais le sien) ; le nombre affiché suit. Silencieux : l'ajout
    /// dans l'app est déjà fait.
    func recordAdd(_ share: Share) async {
        guard social, !demo, !isMine(share), let client, let session = try? await validSession() else { return }
        do {
            let count = try await client.recordAdd(share.id, session: session)
            update(share.id) { $0.addCount = count }
        } catch CommunityError.socialNotReady {
            social = false
        } catch {}
    }

    /// Ajouté par moi, et ma note (nil : pas de notes possibles, serveur d'avant ou son propre partage).
    func myRating(of share: Share) async -> (added: Bool, stars: Int?)? {
        guard social, !isMine(share) else { return nil }
        if demo { return (true, nil) }
        guard let client, let session = try? await validSession() else { return nil }
        do {
            return try await client.myRating(share.id, session: session)
        } catch CommunityError.socialNotReady {
            social = false
            return nil
        } catch {
            return nil
        }
    }

    /// Ma note : envoyée, puis la moyenne affichée suit ; faux en cas de refus (message dans `error`).
    func rate(_ share: Share, stars: Int) async -> Bool {
        if demo { return true }
        var ok = false
        await authed { client, session in
            let result = try await client.rate(share.id, stars: stars, session: session)
            self.update(share.id) {
                $0.ratingSum = result.sum
                $0.ratingCount = result.count
            }
            ok = true
        }
        return ok
    }

    /// Le même partage, partout où il est affiché.
    private func update(_ id: UUID, _ change: (inout Share) -> Void) {
        for i in shares.indices where shares[i].id == id { change(&shares[i]) }
        for i in followedPreview.indices where followedPreview[i].id == id { change(&followedPreview[i]) }
        for i in topPreview.indices where topPreview[i].id == id { change(&topPreview[i]) }
    }

    // MARK: Point rouge

    /// Au lancement (compte connecté), puis toutes les 30 min : nouveautés des gens suivis.
    func startFollowedWatch() {
        newCheck?.cancel()
        guard !demo else { return }
        newCheck = Task { [weak self] in
            while !Task.isCancelled {
                await self?.checkFollowed()
                try? await Task.sleep(nanoseconds: 30 * 60 * 1_000_000_000)
            }
        }
    }

    func checkFollowed() async {
        guard social, !demo, let client, session != nil, let session = try? await validSession() else { return }
        do {
            let list = try await client.followedShares(limit: 20, session: session)
            let seen = UserDefaults.standard.object(forKey: Self.followedSeenKey) as? Double
            guard let seen else {
                markFollowedSeen()                    // première fois : seuls les partages d'après comptent
                return
            }
            newFromFollowed = CommunityStats.newCount(list, since: Date(timeIntervalSince1970: seen))
        } catch CommunityError.socialNotReady {
            social = false
        } catch {}
    }

    func markFollowedSeen() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.followedSeenKey)
        newFromFollowed = 0
    }
}
