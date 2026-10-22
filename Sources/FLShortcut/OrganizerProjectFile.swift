// Organiser sur le fichier du projet (retour du propriétaire, vidéo du 21/10 : des mélodies classées « FX », des
// patterns ni renommés ni colorés, des clips mal posés ; « je veux quelque chose de solide qui fasse qu'à 100 % il
// rende le travail sûr »). FL enregistre le projet ouvert et l'Organiser lit son fichier : les sons de chaque pattern
// et de chaque piste sont ceux de ses notes et de ses clips, rien n'est deviné. La Playlist est rangée dans une copie,
// « <nom>_2.flp » (comme « Save new version » de FL), à côté de l'original, qui ne bouge pas ; FL ouvre la copie, puis Channel rack, patterns,
// Mixer et noms se font par le script, comme avant. « Revenir comme avant » rouvre l'original. Pur (testé).
import Foundation

/// Le fichier du projet ouvert dans FL (des faux dans les tests).
struct ProjectFileAccess {
    /// FL enregistre le projet ouvert ; renvoie son fichier, celui que FL vient d'écrire (`known` : celui qu'on
    /// attend, s'il est connu).
    var save: (_ known: URL?) -> Result<URL, OrganizerError>
    /// FL ouvre ce fichier à la place du projet ouvert ; faux si rien n'a pu être demandé.
    var open: (URL) -> Bool
    var read: (URL) throws -> FLPFile = { try FLPFile(contentsOf: $0) }
    /// Jamais par-dessus un fichier qui existe.
    var write: (FLPFile, URL) throws -> Void = { file, url in
        try Data(file.encoded()).write(to: url, options: .withoutOverwriting)
    }
    var exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    /// La fenêtre de FL porte le nom de ce fichier (FL l'a ouvert).
    var isOpen: (URL) -> Bool = { _ in false }
}

/// Le fichier lu à l'analyse : où il est, chaque clip de la Playlist et ce qu'il joue.
struct ProjectSnapshot: Equatable {
    let url: URL
    let clips: [FLPProject.Clip]
    /// Ce que joue chaque clip (rang du clip → groupe).
    var groups: [Int: PlaylistLayout.Group]
    let trackCount: Int

    /// Patterns posés dans la Playlist où rien ne joue (aucune note) : chacun sur sa piste, après les sons.
    var silentPatterns: Int {
        Set(groups.values.compactMap { group -> Int? in
            if case .silent(let n) = group { return n }
            return nil
        }).count
    }

    /// Les mêmes clips une fois des canaux supprimés de FL (`map` : index d'avant → maintenant).
    func moving(_ map: [Int: Int]) -> ProjectSnapshot {
        var out = self
        out.groups = groups.mapValues { group in
            switch group {
            case .sounds(let s): return .sounds(Set(s.compactMap { map[$0] }))
            case .other(let c): return .other(map[c] ?? c)
            case .silent: return group
            }
        }
        return out
    }
}

enum ProjectFile {
    struct Sounds: Equatable {
        /// Sons de chaque pattern qui en a (0 = pattern 1, comme `PatternInfo.index`).
        var patterns: [Int: Set<Int>] = [:]
        /// Sons de chaque piste de la Playlist qui en a (0 = piste 1).
        var tracks: [Int: Set<Int>] = [:]
        /// Sons qui ont des notes dans un pattern ou un clip dans la Playlist.
        var used: Set<Int> = []
    }

    /// Ce que joue chaque pattern et chaque piste, d'après les notes et les clips. `notSounds` : canaux qui ne sont
    /// pas des sons (automations).
    static func sounds(_ project: FLPProject, notSounds: Set<Int>) -> Sounds {
        var out = Sounds()
        for pattern in project.notes.keys {
            let sounds = project.sounds(of: pattern).subtracting(notSounds)
            if !sounds.isEmpty { out.patterns[pattern - 1] = sounds }
            out.used.formUnion(sounds)
        }
        for clip in project.clips {
            let sounds = played(clip, project, notSounds)
            if !sounds.isEmpty { out.tracks[clip.track, default: []].formUnion(sounds) }
            out.used.formUnion(sounds)
        }
        return out
    }

    private static func played(_ clip: FLPProject.Clip, _ project: FLPProject, _ notSounds: Set<Int>) -> Set<Int> {
        switch clip.source {
        case .pattern(let n): return project.sounds(of: n).subtracting(notSounds)
        case .channel(let c): return project.played([c]).subtracting(notSounds)
        }
    }

    /// Ce que joue un clip, pour ranger la Playlist.
    static func group(_ clip: FLPProject.Clip, project: FLPProject, notSounds: Set<Int>) -> PlaylistLayout.Group {
        let sounds = played(clip, project, notSounds)
        if !sounds.isEmpty { return .sounds(sounds) }
        switch clip.source {
        case .pattern(let n): return .silent(n)
        case .channel(let c): return .other(c)
        }
    }

    static func snapshot(_ project: FLPProject, url: URL, notSounds: Set<Int>) -> ProjectSnapshot {
        var groups: [Int: PlaylistLayout.Group] = [:]
        for clip in project.clips { groups[clip.item] = group(clip, project: project, notSounds: notSounds) }
        return ProjectSnapshot(url: url, clips: project.clips, groups: groups, trackCount: project.trackCount)
    }

    /// Pur (testé) : le fichier est-il celui du projet ouvert dans FL ? nil si oui ; sinon ce qui diffère, en mots et
    /// nombres pour le diagnostic (jamais un nom). Autant de canaux, chacun du même nom quand le fichier le dit (le
    /// script coupe les noms longs : son nom est le début de celui du fichier), chaque pattern nommé dans le fichier
    /// du même nom dans FL (`patterns` : 0 = pattern 1).
    static func mismatch(_ project: FLPProject, channels: [String], patterns: [Int: String]) -> String? {
        guard project.channels.count == channels.count else {
            return "canaux \(project.channels.count)/\(channels.count)"
        }
        for (c, live) in zip(project.channels, channels) {
            if let name = c.name, !same(live, name) { return "nom c\(c.iid)" }
        }
        for (n, name) in project.patternNames.sorted(by: { $0.key < $1.key }) {
            guard let live = patterns[n - 1], same(live, name) else { return "pattern \(n)" }
        }
        return nil
    }

    /// Nom lu par le script (peut-être coupé) comparé au nom complet du fichier.
    static func same(_ live: String, _ full: String) -> Bool {
        let l = live.trimmingCharacters(in: .whitespaces), f = full.trimmingCharacters(in: .whitespaces)
        return l == f || (l.count >= 8 && f.hasPrefix(l))
    }

    /// Pur (testé) : la copie rangée, à côté de l'original, nommée comme « Save new version » de FL : « Mon son.flp »
    /// donne « Mon son_2.flp », « Mon son_2.flp » donne « Mon son_3.flp »… Jamais un fichier qui existe.
    static func copyURL(for original: URL, exists: (URL) -> Bool) -> URL {
        let folder = original.deletingLastPathComponent()
        var base = original.deletingPathExtension().lastPathComponent
        var version = 1
        if let range = base.range(of: "_[0-9]+$", options: .regularExpression), range.lowerBound > base.startIndex,
           let n = Int(base[range].dropFirst()), n < 1_000_000 {
            version = n
            base.removeSubrange(range)
        }
        for n in (version + 1)...(version + 999) {
            let url = folder.appendingPathComponent("\(base)_\(n).flp")
            if !exists(url) { return url }
        }
        return folder.appendingPathComponent("\(base)_\(UUID().uuidString.prefix(8)).flp")
    }

    /// Ce qui porte la marque de la copie.
    enum Mark: Equatable {
        /// Un pattern (1 = pattern 1).
        case pattern(Int)
        /// Un canal (rang dans le Channel rack, tous les canaux).
        case channel(Int)
    }

    /// Pur (testé) : la copie marquée, pour savoir que FL l'a ouverte : le premier pattern nommé (d'un nom que le
    /// script peut remettre en entier) prend le nom `marker` ; le script le lit une fois la copie chargée, puis il est
    /// remis. Sinon le nom est ajouté au premier pattern décrit qui n'en a pas ; sinon (un seul pattern jamais nommé,
    /// prod « Mechanical » du propriétaire) il va sur le premier canal nommé. nil : rien de possible.
    static func marking(_ file: FLPFile, marker: String) -> (file: FLPFile, mark: Mark)? {
        let text: [UInt8] = marker.utf16.flatMap { FLPBytes.le(Int($0), size: 2) } + [0, 0]
        let name = FLPEvent(id: FLPProject.Event.patternName, bytes: text)
        var out = file
        var pattern: Int?
        var named = Set<Int>()
        var described: [(index: Int, pattern: Int)] = []
        var channel: (iid: Int, named: Int?)?
        var channelMark: (index: Int, iid: Int)?
        for (i, event) in file.events.enumerated() {
            let next = i + 1 < file.events.count ? file.events[i + 1].id : 0
            switch event.id {
            case FLPProject.Event.pattern:
                pattern = Int(event.value)
                channel = nil
                // Le pattern et ses notes (224, contrôles 223) ; ou sa description (nom, couleur…).
                if next != FLPProject.Event.notes, next != 223 { described.append((i, Int(event.value))) }
            case FLPProject.Event.patternName:
                guard let pattern else { break }
                named.insert(pattern)
                if event.text.utf8.count <= OrganizerPayload.nameBytes {
                    out.events[i] = name
                    return (out, .pattern(pattern))
                }
            case FLPProject.Event.channel where next == FLPProject.Event.channelType:
                channel = (Int(event.value), nil)
            case FLPProject.Event.channelName:
                if let c = channel, c.named == nil {
                    channel?.named = i
                    if channelMark == nil, event.text.utf8.count <= OrganizerPayload.nameBytes { channelMark = (i, c.iid) }
                }
            case FLPProject.Event.arrangement, FLPProject.Event.mixerName, FLPProject.Event.mixerParams:
                pattern = nil
                channel = nil
            default:
                break
            }
        }
        if let free = described.first(where: { !named.contains($0.pattern) }) {
            out.events.insert(name, at: free.index + 1)
            return (out, .pattern(free.pattern))
        }
        guard let channelMark else { return nil }
        out.events[channelMark.index] = FLPEvent(id: FLPProject.Event.channelName, bytes: text)
        return (out, .channel(channelMark.iid))
    }

    /// Nom de pattern qui marque la copie : jamais celui d'un son.
    static func marker(_ n: Int) -> String { "FL Shortcuts \(n)" }

    /// Pur (testé) : les noms de projet possibles dans le titre de la fenêtre de FL (« Mon son - FL Studio 2025 »,
    /// « Mon son.flp * ») : chaque morceau, sans « FL Studio », sans « .flp » ni la marque des changements.
    static func titleNames(_ title: String) -> [String] {
        var parts = [title]
        for separator in [" - ", " — ", " – "] { parts = parts.flatMap { $0.components(separatedBy: separator) } }
        var out: [String] = []
        for part in parts {
            var name = part.trimmingCharacters(in: .whitespaces)
            while name.hasSuffix("*") { name = String(name.dropLast()).trimmingCharacters(in: .whitespaces) }
            if name.lowercased().hasSuffix(".flp") { name = String(name.dropLast(4)) }
            name = name.trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, !name.localizedCaseInsensitiveContains("FL Studio"), !out.contains(name) else { continue }
            out.append(name)
        }
        return out
    }

    /// Le projet ouvert dans FL, lu dans son fichier : FL l'enregistre, puis le fichier est lu et comparé au projet
    /// ouvert (mêmes canaux, mêmes patterns). Ce qui ne va pas arrête tout, avant que rien ne soit touché ; `why`
    /// reçoit la raison en mots (diagnostic : jamais un nom).
    static func read(_ files: ProjectFileAccess, known: URL?, channels: [ChannelInfo], patterns: [PatternInfo],
                     why: (String) -> Void = { _ in }) throws -> (url: URL, file: FLPFile, project: FLPProject) {
        let url = try files.save(known).get()
        let file: FLPFile
        let project: FLPProject
        do {
            file = try files.read(url)
            project = try FLPProject(file)
        } catch FLPError.unsupported(let what) {
            why(what)
            if what == "arrangements" {
                throw OrganizerError.failed(String(localized: "Ton projet a plusieurs arrangements avec des clips : l'Organiser ne range pour l'instant qu'un seul arrangement. Rien n'a été touché."))
            }
            throw OrganizerError.failed(String(localized: "L'Organiser ne sait pas encore ranger ce projet sans risque (\(what)) : rien n'a été touché."))
        } catch {
            why(denied(error) ? "autorisation" : "lecture")
            throw denied(error) ? Self.deniedError
                : OrganizerError.failed(String(localized: "Le fichier de ton projet n'a pas pu être lu : rien n'a été touché."))
        }
        var names: [Int: String] = [:]
        for pattern in patterns { names[pattern.index] = pattern.name }
        let live = channels.sorted { $0.index < $1.index }.map(\.name)
        if let what = mismatch(project, channels: live, patterns: names) {
            why(what)
            throw OrganizerError.failed(String(localized: "Le fichier enregistré ne correspond pas au projet ouvert dans FL : rien n'a été touché. Si le Channel rack ne montre qu'un groupe de sons, choisis « All » en haut du Channel rack. Puis clique sur « Réessayer »."))
        }
        if project.clips.contains(where: { project.mutedTracks.contains($0.track) }) {
            why("piste coupée")
            throw OrganizerError.failed(String(localized: "Une piste de ta Playlist est coupée (mute) : réactive-la dans FL (ou retire ses clips), puis clique sur « Réessayer ». Rien n'a été touché."))
        }
        return (url, file, project)
    }

    /// macOS n'a pas laissé lire ou écrire le dossier du projet (Documents, Bureau, disque externe…).
    static func denied(_ error: Error) -> Bool {
        let e = error as NSError
        if e.domain == NSCocoaErrorDomain { return [NSFileReadNoPermissionError, NSFileWriteNoPermissionError].contains(e.code) }
        if e.domain == NSPOSIXErrorDomain { return [Int(EPERM), Int(EACCES)].contains(e.code) }
        return false
    }

    static var deniedError: OrganizerError {
        .failed(String(localized: "macOS n'a pas laissé FL Shortcuts ouvrir le dossier de ton projet : autorise-le dans Réglages Système › Confidentialité et sécurité › Fichiers et dossiers, puis clique sur « Réessayer ». Rien n'a été touché."))
    }

    /// Nom posé dans une copie pour la reconnaître (resté si FL l'a ouverte trop tard) : jamais repris comme nom.
    static func isMarker(_ name: String) -> Bool {
        name.range(of: "^FL Shortcuts [0-9]+$", options: .regularExpression) != nil
    }
}
