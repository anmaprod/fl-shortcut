// Aide › Mes messages (20/11, maquette « Minimal ») : les messages envoyés à l'équipe avec son compte, la réponse de
// l'équipe et « Répondre » (serveur : supabase/mes-messages.sql). Une capture facultative part avec un message
// (préparée ici : JPEG, 1600 points de large au plus). Ce qui a été lu (réponses de l'équipe vues) reste sur ce Mac :
// rien de sensible.
import AppKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct SupportReply: Identifiable, Decodable, Equatable {
    let id: UUID
    let team: Bool
    let message: String
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, team, message
        case createdAt = "created_at"
    }
}

/// Un message envoyé à l'équipe et ses réponses.
struct SupportThread: Identifiable, Decodable, Equatable {
    let id: UUID
    let kind: String
    let reference: String
    let message: String
    let createdAt: String
    var replies: [SupportReply]

    enum CodingKeys: String, CodingKey {
        case id, kind, reference, message, replies = "support_replies"
        case createdAt = "created_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decodeIfPresent(String.self, forKey: .kind) ?? "question"
        reference = try c.decodeIfPresent(String.self, forKey: .reference) ?? ""
        message = try c.decodeIfPresent(String.self, forKey: .message) ?? ""
        createdAt = try c.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        replies = (try c.decodeIfPresent([SupportReply].self, forKey: .replies) ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    init(id: UUID, kind: String, reference: String, message: String, createdAt: String, replies: [SupportReply]) {
        self.id = id
        self.kind = kind
        self.reference = reference
        self.message = message
        self.createdAt = createdAt
        self.replies = replies
    }

    var kindLabel: String { (SupportKind(rawValue: kind) ?? .question).label }
    /// La première ligne du message (titre de la ligne dans « Mes messages »).
    var firstLine: String {
        message.split(whereSeparator: \.isNewline).first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? ""
    }
}

/// Règles pures (testées) de « Mes messages ».
enum SupportInboxRules {
    enum State: Equatable { case sent, answered, newAnswer }

    /// État d'un message : envoyé (pas de réponse de l'équipe), réponse vue, nouvelle réponse.
    static func state(_ thread: SupportThread, seen: Set<UUID>) -> State {
        guard let last = thread.replies.last(where: \.team) else { return .sent }
        return seen.contains(last.id) ? .answered : .newAnswer
    }

    static func unread(_ threads: [SupportThread], seen: Set<UUID>) -> Int {
        threads.filter { state($0, seen: seen) == .newAnswer }.count
    }

    /// Serveur sans mes-messages.sql : table des réponses absente (404 / 400) ou genre « autre », capture refusés.
    static func isMissing(status: Int, message: String) -> Bool {
        let m = message.lowercased()
        if status == 404 { return true }
        return status == 400 && (m.contains("support_replies") || m.contains("relationship")
            || (m.contains("capture") && (m.contains("does not exist") || m.contains("could not find"))))
    }

    /// Envoi refusé par un serveur d'avant (genre « autre » ou capture inconnus) : à renvoyer sans eux.
    static func needsOldForm(status: Int, message: String) -> Bool {
        let m = message.lowercased()
        return status == 400 && (m.contains("capture") || m.contains("support_requests_kind_check"))
    }

    /// « il y a 3 j » (comme la maquette), d'après la date du serveur.
    static func dateLabel(_ iso: String, now: Date = Date()) -> String {
        guard let date = CommunityText.date(iso) else { return "" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: date, relativeTo: now)
    }

    /// Mots d'au moins 4 lettres du message : les questions de l'Aide qui en parlent (« Ça t'aide peut-être »), 3 au
    /// plus ; rien pour une idée.
    static func tips(for text: String, kind: SupportKind?, in faq: [HelpEntry]) -> [HelpEntry] {
        guard kind != .idee else { return [] }
        let words = HelpEntry.fold(text).split { !$0.isLetter && !$0.isNumber }.map(String.init).filter { $0.count >= 4 }
        guard !words.isEmpty else { return [] }
        return Array(faq.filter { entry in
            let hay = HelpEntry.fold(entry.question + " " + entry.keywords)
            return words.contains { hay.contains($0) }
        }.prefix(3))
    }
}

/// Capture jointe : l'image d'un fichier réduite à 1600 points de large au plus, en JPEG d'1 Mo au plus une fois en
/// base64 (la règle du serveur).
enum SupportCapture {
    static let maxWidth = 1600
    static let maxBase64 = 1_048_576

    static func base64(fromFile url: URL) -> String? {
        guard let image = ProfilePhoto.load(url) else { return nil }
        return base64(from: image)
    }

    static func base64(from image: CGImage) -> String? {
        var current = image
        if image.width > maxWidth {
            let h = Int((Double(image.height) * Double(maxWidth) / Double(image.width)).rounded())
            guard let context = CGContext(data: nil, width: maxWidth, height: max(h, 1), bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
            context.interpolationQuality = .high
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: maxWidth, height: h))
            context.draw(image, in: CGRect(x: 0, y: 0, width: maxWidth, height: h))
            guard let small = context.makeImage() else { return nil }
            current = small
        }
        for quality in [0.75, 0.6, 0.45, 0.3] {
            let data = NSMutableData()
            guard let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
            CGImageDestinationAddImage(dest, current, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { return nil }
            let text = (data as Data).base64EncodedString()
            if text.count <= maxBase64 { return text }
        }
        return nil
    }

    /// Seulement un JPEG (comme le serveur, `left(capture, 4) = '/9j/'`) : aucun autre format n'est décodé (21/11).
    static func image(_ base64: String) -> NSImage? {
        guard let data = Data(base64Encoded: base64), data.starts(with: [0xFF, 0xD8, 0xFF]) else { return nil }
        return NSImage(data: data)
    }
}

// MARK: - Serveur

extension CommunityClient {
    /// Mes messages (les plus récents d'abord) et leurs réponses.
    func myMessages(session: CommunitySession) async throws -> [SupportThread] {
        let query = [URLQueryItem(name: "select", value: "id,kind,reference,message,created_at,support_replies(id,team,message,created_at)"),
                     URLQueryItem(name: "user_id", value: "eq.\(session.userID.uuidString.lowercased())"),
                     URLQueryItem(name: "order", value: "created_at.desc"),
                     URLQueryItem(name: "limit", value: "100")]
        let data: Data
        do {
            data = try await call("GET", "rest/v1/support_requests", query: query, token: session.accessToken)
        } catch CommunityError.server(let status, let message) where SupportInboxRules.isMissing(status: status, message: message) {
            throw CommunityError.socialNotReady
        }
        guard let list = try? JSONDecoder().decode([SupportThread].self, from: data) else { throw CommunityError.badResponse }
        return list
    }

    /// La capture d'un de mes messages (nil : sans capture).
    func messageCapture(_ id: UUID, session: CommunitySession) async throws -> String? {
        struct Row: Decodable { let capture: String? }
        let data = try await call("GET", "rest/v1/support_requests",
                                  query: [URLQueryItem(name: "select", value: "capture"),
                                          URLQueryItem(name: "id", value: "eq.\(id.uuidString.lowercased())")],
                                  token: session.accessToken)
        return (try? JSONDecoder().decode([Row].self, from: data))?.first?.capture
    }

    /// Répondre à l'équipe dans un de mes messages.
    func replySupport(_ id: UUID, text: String, session: CommunitySession) async throws {
        let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw CommunityError.invalid(String(localized: "Ta réponse est vide.")) }
        _ = try await call("POST", "rest/v1/support_replies", token: session.accessToken,
                           body: ["request_id": id.uuidString.lowercased(), "message": String(clean.prefix(4000))])
    }
}

// MARK: - État

/// Mes messages, partagés par la page Aide et la barre de gauche (point rouge d'une nouvelle réponse).
@MainActor
final class SupportInbox: ObservableObject {
    static let shared = SupportInbox()
    static let seenKey = "supportSeenReplies"

    @Published private(set) var threads: [SupportThread] = []
    /// nil : pas encore lu ; false : serveur sans mes-messages.sql.
    @Published private(set) var ready: Bool?
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    @Published private(set) var seen: Set<UUID>
    @Published private(set) var captures: [UUID: NSImage] = [:]

    init() {
        let ids = UserDefaults.standard.stringArray(forKey: Self.seenKey) ?? []
        seen = Set(ids.compactMap(UUID.init(uuidString:)))
    }

    var unread: Int { SupportInboxRules.unread(threads, seen: seen) }

    func load(_ community: CommunityStore) async {
        if community.demo {
            threads = Self.demoThreads
            ready = true
            return
        }
        guard let client = community.client, let session = try? await community.validSession() else { return }
        loading = true
        defer { loading = false }
        do {
            threads = try await client.myMessages(session: session)
            ready = true
            error = nil
        } catch CommunityError.socialNotReady {
            ready = false
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Un message ouvert : ses réponses de l'équipe sont vues ; sa capture lue une fois.
    func open(_ thread: SupportThread, _ community: CommunityStore) async {
        markSeen(thread)
        guard captures[thread.id] == nil, !community.demo, let client = community.client,
              let session = try? await community.validSession(),
              let text = try? await client.messageCapture(thread.id, session: session),
              let image = SupportCapture.image(text) else { return }
        captures[thread.id] = image
    }

    func markSeen(_ thread: SupportThread) {
        let ids = thread.replies.filter(\.team).map(\.id)
        guard !ids.allSatisfy(seen.contains) else { return }
        seen.formUnion(ids)
        UserDefaults.standard.set(Array(seen.map(\.uuidString).suffix(500)), forKey: Self.seenKey)
    }

    /// nil : envoyée (la liste est relue) ; sinon, ce qui s'est passé.
    func reply(_ thread: SupportThread, text: String, _ community: CommunityStore) async -> String? {
        if community.demo {
            if let i = threads.firstIndex(where: { $0.id == thread.id }) {
                threads[i].replies.append(SupportReply(id: UUID(), team: false, message: text, createdAt: ISO8601DateFormatter().string(from: Date())))
            }
            return nil
        }
        guard let client = community.client, let session = try? await community.validSession() else {
            return String(localized: "Session expirée : reconnecte-toi.")
        }
        do {
            try await client.replySupport(thread.id, text: text, session: session)
            await load(community)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    /// Déconnexion : les messages du compte ne restent pas affichés.
    func forget() {
        threads = []
        ready = nil
        captures = [:]
    }

    nonisolated static let demoThreads: [SupportThread] = {
        let id = UUID(uuidString: "6F1D2C1E-0000-4000-8000-0000000000A1")!
        return [
            SupportThread(id: id, kind: "probleme", reference: "FLS-3F9A2C",
                          message: "Export Stems s'arrête au menu Export.", createdAt: "2026-11-17T10:00:00+00:00",
                          replies: [SupportReply(id: UUID(uuidString: "6F1D2C1E-0000-4000-8000-0000000000B1")!, team: true,
                                                 message: "Merci ! C'est corrigé dans la prochaine version.",
                                                 createdAt: "2026-11-18T09:00:00+00:00")]),
            SupportThread(id: UUID(uuidString: "6F1D2C1E-0000-4000-8000-0000000000A2")!, kind: "idee", reference: "FLS-7B21D0",
                          message: "Un bloc pour changer le tempo.", createdAt: "2026-11-15T10:00:00+00:00", replies: []),
        ]
    }()
}
