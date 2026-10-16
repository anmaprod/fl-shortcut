// Derniers problèmes rencontrés (20 au plus, gardés entre deux lancements, dans les réglages), joints au message
// d'aide avec leur date : de quoi comprendre ce qui s'est passé, même la veille. Uniquement des textes de l'app
// (échec d'une macro et son bloc, enregistrement impossible, autorisation perdue…) : jamais une touche tapée, un nom
// de piste ni un chemin de fichier.
import Foundation

final class ProblemLog: @unchecked Sendable {
    static let shared = ProblemLog()

    struct Entry: Codable, Equatable {
        let date: Date
        let text: String
    }

    static let maxEntries = 20
    static let key = "problemLog"

    private let defaults: UserDefaults
    private let entries: Locked<[Entry]>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let saved = defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
        entries = Locked(Array(saved.suffix(Self.maxEntries)))
    }

    var all: [Entry] { entries.value }

    /// Nouveau problème ; le même texte dans la minute n'est pas répété (une macro relancée en boucle).
    func add(_ text: String, date: Date = Date()) {
        let clean = String(text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300))
        guard !clean.isEmpty else { return }
        let list: [Entry] = entries.withLock { list in
            if let last = list.last, last.text == clean, date.timeIntervalSince(last.date) < 60 { return list }
            list.append(Entry(date: date, text: clean))
            if list.count > Self.maxEntries { list.removeFirst(list.count - Self.maxEntries) }
            return list
        }
        if let data = try? JSONEncoder().encode(list) { defaults.set(data, forKey: Self.key) }
    }

    func clear() {
        entries.withLock { $0 = [] }
        defaults.removeObject(forKey: Self.key)
    }

    /// « 16/10 21:07 · Macro : échec au bloc 3 », du plus ancien au plus récent ; nil s'il n'y en a pas.
    var text: String? {
        let list = entries.value
        guard !list.isEmpty else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "fr_FR")
        f.dateFormat = "dd/MM HH:mm"
        return list.map { "\(f.string(from: $0.date)) · \($0.text)" }.joined(separator: "\n")
    }
}

extension MacroLog {
    /// La dernière exécution de macro du journal (de sa ligne RUN à la fin), pour le message d'aide : au plus
    /// `maxLines` lignes (le début et surtout la fin, là où se dit l'échec) ; nil s'il n'y en a pas.
    static func lastRunExcerpt(maxLines: Int = 60) -> String? {
        shared.flush()
        guard SecureFile.kind(at: current.path) == .regular,
              let text = try? String(contentsOf: current, encoding: .utf8) else { return nil }
        return excerpt(of: text, maxLines: maxLines)
    }

    static func excerpt(of text: String, maxLines: Int) -> String? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        guard let start = lines.lastIndex(where: { $0.contains("] RUN ") }) else { return nil }
        let run = Array(lines[start...])
        guard run.count > maxLines else { return run.joined(separator: "\n") }
        let head = maxLines / 4
        let tail = maxLines - head
        return (run.prefix(head) + ["… \(run.count - maxLines) lignes …"] + run.suffix(tail)).joined(separator: "\n")
    }
}
