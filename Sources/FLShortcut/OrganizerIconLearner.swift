import Foundation

/// Apprentissage des numéros d'icônes de FL, une fois pour toutes (12/11, « oui stp ») : FL ne publie aucune table
/// (forum d'Image-Line) et ses numéros ne suivent pas la grille (crash out 3 : la même icône vaut 75 au Channel rack et
/// 105 au Mixer). Sur un projet VIDE seulement (aucun clip ni aucune note : jamais un vrai projet), chaque case de la
/// grille est posée sur un son du Channel rack (quelques sons à la fois), FL enregistre, le numéro est relu dans le
/// fichier ; puis de même dans le Mixer, qui a ses propres numéros. Un numéro qui n'a pas changé, ou déjà pris par
/// une autre case : l'icône a raté, elle est refaite plus tard (`maxTries` fois au plus). Échap arrête tout ; ce qui
/// est appris reste. Journal et diagnostic : des nombres seulement.
final class OrganizerIconLearner {
    struct Outcome: Equatable {
        /// Case de la grille (« 7-4 ») → numéro de FL.
        var rack: [String: UInt32] = [:]
        var mixer: [String: UInt32] = [:]
        /// Cases pas apprises (ratées `maxTries` fois).
        var missedRack = 0
        var missedMixer = 0
        var error: OrganizerError?
        var trace: [String] = []
    }

    static let maxTries = 3
    /// Sons du Channel rack et pistes du Mixer utilisés à la fois.
    static let batch = 8
    /// Ratés de suite après lesquels tout s'arrête (FL ne laisse plus faire : inutile d'insister).
    static let failuresInARow = 6
    /// Pause avant le second essai d'une case ratée (comme l'Organiser).
    static let retryPause: TimeInterval = 0.8

    private let link: OrganizerLink
    private let placeIcon: (FLIcon, IconTarget) -> OrganizerError?
    private let files: ProjectFileAccess
    private let wait: (TimeInterval) -> Void
    private let cells: [FLIcon]
    private let progress: (_ done: Int, _ total: Int) -> Void
    /// Vrai : arrêt demandé (fenêtre fermée, Échap) ; vérifié avant chaque case.
    private let stop: () -> Bool
    private var done = 0
    private var total = 0

    init(link: OrganizerLink, placeIcon: @escaping (FLIcon, IconTarget) -> OrganizerError?, files: ProjectFileAccess,
         wait: @escaping (TimeInterval) -> Void, cells: [FLIcon] = FLIconGrid.pickable,
         stop: @escaping () -> Bool = { false },
         progress: @escaping (_ done: Int, _ total: Int) -> Void = { _, _ in }) {
        self.stop = stop
        self.link = link
        self.placeIcon = placeIcon
        self.files = files
        self.wait = wait
        self.cells = cells
        self.progress = progress
    }

    func run() -> Outcome {
        var out = Outcome()
        done = 0
        total = cells.count * 2
        do {
            let url = try files.save(nil).get()
            let file = try files.read(url)
            let project = try FLPProject(file)
            guard project.clips.isEmpty, project.notes.values.allSatisfy({ $0.isEmpty }) else {
                throw OrganizerError.failed(String(localized: "Ouvre un projet vide dans FL (File › New), enregistre-le, puis recommence : l'apprentissage pose des icônes sur ses sons."))
            }
            // Channel rack : les sons où FL écrit l'icône (le 155 de chaque son), renommés pour être retrouvés.
            let channels = Array(project.channels.indices.filter { project.channels[$0].icon != nil }.prefix(Self.batch))
            guard !channels.isEmpty else {
                throw OrganizerError.failed(String(localized: "Ce projet n'a aucun son où poser les icônes : ouvre un nouveau projet dans FL (File › New)."))
            }
            // Noms différents de ceux du Mixer : jamais deux fois le même texte dans la fenêtre de FL.
            try link.setNames(.channels, channels.map { (index: $0, name: "Rack \($0 + 1)") })
            // Une page qui échoue n'empêche pas l'autre (13/11 : le Channel rack ratait, le Mixer n'était pas essayé) ;
            // seul Échap arrête tout.
            do {
                let missedRack = try learn(.channels, places: channels, url: url, table: &out.rack) { file in
                    let project = try? FLPProject(file)
                    var icons: [Int: UInt32] = [:]
                    for (place, channel) in (project?.channels ?? []).enumerated() { icons[place] = channel.icon ?? 0 }
                    return icons
                }
                out.missedRack = missedRack
            } catch let error as OrganizerError where error != .interrupted {
                out.error = error
                out.missedRack = cells.count - out.rack.count
                out.trace.append("rack arrêté")
            }
            out.trace.append("rack \(out.rack.count)/\(cells.count) sons \(channels.count)")
            // Mixer : ses pistes 1 à 8 (le Master ne bouge pas), seulement si FL les écrit à la forme connue.
            let saved = try files.read(url)
            if let prefixes = FLPProject.insertPrefixes(saved.events) {
                let inserts = Array(prefixes.keys.sorted().prefix(Self.batch))
                if !inserts.isEmpty {
                    try link.setNames(.mixer, inserts.map { (index: $0, name: "Mix \($0)") })
                    do {
                        let missedMixer = try learn(.mixer, places: inserts, url: url, table: &out.mixer) { file in
                            FLPProject.insertIcons(file)
                        }
                        out.missedMixer = missedMixer
                    } catch let error as OrganizerError where error != .interrupted {
                        if out.error == nil { out.error = error }
                        out.missedMixer = cells.count - out.mixer.count
                        out.trace.append("mixer arrêté")
                    }
                }
                out.trace.append("mixer \(out.mixer.count)/\(cells.count) pistes \(inserts.count)")
            } else {
                out.missedMixer = cells.count
                out.trace.append("mixer forme inattendue")
            }
        } catch {
            out.error = (error as? OrganizerError)
                ?? .failed(String(localized: "Organiser : étape impossible (\(String(describing: type(of: error))))."))
        }
        MacroLog.shared.write("ICON", "learning: rack \(out.rack.count) mixer \(out.mixer.count) of \(cells.count)"
                              + (out.error.map { " · stopped (\($0))" } ?? ""))
        return out
    }

    /// Une page : les cases posées quelques-unes à la fois (une par son ou piste de `places`), FL enregistre, chaque
    /// numéro relu ; une case ratée revient plus tard. Renvoie le nombre de cases pas apprises.
    private func learn(_ kind: ItemKind, places: [Int], url: URL, table: inout [String: UInt32],
                       read: (FLPFile) throws -> [Int: UInt32]) throws -> Int {
        let page: FLWindow = kind == .channels ? .channelRack : .mixer
        if link.window != page { try link.show(page) }
        let names = kind == .channels ? IconTarget.channelNames(try link.listChannels())
                                      : IconTarget.mixerNames(try link.listMixer())
        var before = try read(files.read(url))
        var queue = cells.filter { table[$0.code] == nil }
        var tries: [String: Int] = [:]
        var missed = 0
        var inARow = 0
        func again(_ cell: FLIcon) {
            tries[cell.code, default: 0] += 1
            if tries[cell.code, default: 0] < Self.maxTries {
                queue.append(cell)
            } else {
                missed += 1
                step()
            }
        }
        while !queue.isEmpty {
            let batch = Array(queue.prefix(places.count))
            queue.removeFirst(batch.count)
            var placed: [(cell: FLIcon, place: Int)] = []
            for (cell, place) in zip(batch, places) {
                if stop() { throw OrganizerError.interrupted }
                if link.window != page { try link.show(page) }
                try link.selectOne(kind, place)
                var failure = placeIcon(cell, IconTarget(kind: kind, place: place, names: names))
                if let first = failure, first != .interrupted {
                    wait(Self.retryPause)
                    if link.window != page { try link.show(page) }
                    try link.selectOne(kind, place)
                    failure = placeIcon(cell, IconTarget(kind: kind, place: place, names: names))
                }
                if failure == .interrupted { throw OrganizerError.interrupted }
                if let failure {
                    inARow += 1
                    if inARow >= Self.failuresInARow { throw failure }
                    again(cell)
                    continue
                }
                inARow = 0
                placed.append((cell: cell, place: place))
            }
            guard !placed.isEmpty else { continue }
            let saved = try files.save(url).get()
            let now = try read(files.read(saved))
            for (cell, place) in placed {
                let id = now[place] ?? 0
                if id != 0, id != (before[place] ?? 0), !table.values.contains(id) {
                    table[cell.code] = id
                    step()
                } else {
                    again(cell)
                }
            }
            before = now
        }
        return missed
    }

    private func step() {
        done += 1
        progress(done, total)
    }

    /// Pur (testé) : la table à copier et à envoyer (des cases et des nombres seulement), une ligne par page.
    static func tableText(_ outcome: Outcome) -> String {
        func line(_ ids: [String: UInt32]) -> String {
            ids.sorted { $0.key.compare($1.key, options: .numeric) == .orderedAscending }
                .map { "\($0.key)=\($0.value)" }.joined(separator: " ")
        }
        return "FL Shortcuts · icônes de FL\nrack \(line(outcome.rack))\nmixer \(line(outcome.mixer))"
    }
}
