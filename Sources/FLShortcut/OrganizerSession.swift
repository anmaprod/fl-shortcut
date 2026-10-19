// Organiser : famille de chaque son de FL. D'abord son nom (« BEAM KICK », « ZEBRA 808 » : rien n'est écouté) ; sinon
// il est écouté seul, dans un pattern où il joue (repéré par FL lui-même : ce qui joue dans chaque pattern), avec deux
// notes d'essai en secours. Mixer : la famille des sons reliés à chaque piste. Playlist : la chanson est parcourue et
// FL dit quelles pistes et quels sons (patterns, clips audio) jouent ensemble ; chaque piste prend la famille de ses
// sons. Tourne hors du fil principal ; FL est toujours remis comme avant (opération 7) avant que le son de FL revienne,
// même après une erreur ou Échap. Les noms ne sont jamais journalisés (le diagnostic n'a que des nombres).
import Accelerate
import Foundation

enum OrganizerPage: Equatable {
    case channelRack, mixer, playlist
}

/// Un canal écouté et classé.
struct OrganizerItem: Equatable {
    let index: Int
    let name: String
    var family: SoundFamily
    var confidence: Double
    /// Le canal se taisait dans le pattern : classé avec les notes d'essai (confiance plus basse).
    var testNotes: Bool
    let mixerTrack: Int
    let color: RGBColor
    /// Ce qu'est le son (Kick, 808, Open Hat…) : d'après son nom, ou pour des drums écoutés, leur sorte. Piste de
    /// la Playlist : ce que tous ses sons disent (son nouveau nom).
    var kind: SoundKind? = nil
    /// Classé d'après son nom, sans écoute.
    var byName = false
}

/// Ce que la dernière écoute a fait, en nombres seulement (« Copier le diagnostic ») : jamais un nom.
struct OrganizerDiagnostics: Equatable {
    var page = "?"
    var reported = "?"
    var listed = 0
    var targets = 0
    var byName = 0
    var listened = 0
    var heard = 0
    var testNotes = 0
    var patterns = 0
    var scanned = 0
    var homes = 0
    var activity = "?"
    var positions = 0
    var activeSamples = 0
    var tracks = 0
    var capture = CaptureStats()
    var error = ""

    var text: String {
        ["page=\(page) dite=\(reported) lus=\(listed) sons=\(targets) nom=\(byName) écoutés=\(listened) "
            + "entendus=\(heard) notes=\(testNotes)",
         "patterns=\(patterns) repérés=\(scanned) trouvés=\(homes) activité=\(activity) positions=\(positions) "
            + "relevés=\(activeSamples) pistes=\(tracks)",
         capture.text,
         error.isEmpty ? "" : "erreur=\(error)"].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

struct OrganizerResult: Equatable {
    let page: OrganizerPage
    /// Tous les canaux, dans l'ordre du Channel rack (layers et automations compris, non écoutés).
    let channels: [ChannelInfo]
    /// Canaux écoutés et classés, dans l'ordre du Channel rack.
    let items: [OrganizerItem]
    /// Pistes du Mixer (page Mixer seulement).
    let mixer: [MixerTrackInfo]
    /// Famille des pistes du Mixer reliées à au moins un canal écouté (le Master n'est jamais touché).
    let mixerFamilies: [Int: SoundFamily]
    /// Pistes de la Playlist lues (page Playlist seulement) ; `items` : celles qui sonnent, écoutées et classées.
    var playlist: [PlaylistTrackInfo] = []
}

final class OrganizerSession {
    struct Timing {
        /// Écoute de ta partie (le pattern depuis son début), au plus.
        var listen: TimeInterval = 3
        /// Durée de chaque note d'essai.
        var testNote: TimeInterval = 0.3
        /// Queue du son après les notes d'essai.
        var tail: TimeInterval = 0.4
        /// Échap est vu au plus tard après ce délai.
        var slice: TimeInterval = 0.05
        /// Playlist : écoute à chaque position essayée, jusqu'à ce que la piste sonne.
        var probe: TimeInterval = 0.4
        /// Écoute après le premier son entendu : assez pour le classer (avant : `listen` entier pour chaque son).
        var afterSound: TimeInterval = 1.5
        /// Encore rien entendu au bout de ce délai : les notes d'essai tout de suite.
        var silentGiveUp: TimeInterval = 1.5
        /// Repérage d'un pattern, ou d'une position de la chanson : relevés de ce qui joue, à cet intervalle.
        var scanStep: TimeInterval = 0.2
        var scanReads = 4
        /// Après un saut dans la chanson, avant le premier relevé.
        var settle: TimeInterval = 0.2
    }

    typealias Classify = ([Float], Double) -> (family: SoundFamily, confidence: Double)
    /// Sorte d'un son classé en drums (nom de la piste de la Playlist).
    typealias NameDrum = ([Float], Double) -> DrumKind

    /// Notes d'essai : C3 puis C5 (pour FPC, ses deux premiers pads).
    static let testNotes: [UInt8] = [48, 60]
    static let testVelocity: UInt8 = 100
    /// Un classement fait avec les notes d'essai compte moins.
    static let testNotesFactor = 0.7
    /// Playlist sans piste sélectionnée : pistes écoutées après la dernière piste renommée (des pistes jamais
    /// renommées ont souvent des clips), 64 au plus ; l'écoute s'arrête après 3 pistes muettes de suite au-delà,
    /// mais jamais avant les 12 premières pistes (vidéo de l'utilisateur : pistes 3 à 5 vides, des clips en 6 à 9 ;
    /// l'écoute s'arrêtait à la 5).
    static let extraTracks = 32
    static let maxTracks = 64
    static let silentRunStop = 3
    static let minTracksScanned = 12
    /// Classé d'après son nom : aussi sûr qu'une bonne écoute.
    static let nameConfidence = 0.9
    /// Patterns repérés au plus (une seconde chacun environ).
    static let maxPatternsScanned = 24
    /// Positions de la chanson relevées au plus (Playlist).
    static let maxPositions = 64

    private let link: OrganizerLink
    private let audio: AudioSource
    private let classify: Classify
    private let nameDrum: NameDrum?
    private let timing: Timing
    private let sleep: (TimeInterval) -> Void
    private let progress: (Int, Int) -> Void
    private let escape: () -> Bool
    private let lock = NSLock()
    private var stopped = false
    private var diag = OrganizerDiagnostics()

    /// Ce que l'écoute a fait (lu une fois `run` fini).
    var diagnostics: OrganizerDiagnostics {
        lock.lock()
        defer { lock.unlock() }
        var out = diag
        out.capture = audio.stats
        return out
    }

    private func note(_ change: (inout OrganizerDiagnostics) -> Void) {
        lock.lock()
        change(&diag)
        lock.unlock()
    }

    /// `escape` : Échap pressé, regardé à chaque tranche d'attente (même quand FL est devant).
    init(link: OrganizerLink, audio: AudioSource, classify: @escaping Classify, nameDrum: NameDrum? = nil,
         timing: Timing = Timing(),
         sleep: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
         escape: @escaping () -> Bool = { false },
         progress: @escaping (Int, Int) -> Void = { _, _ in }) {
        self.link = link
        self.audio = audio
        self.classify = classify
        self.nameDrum = nameDrum
        self.timing = timing
        self.sleep = sleep
        self.escape = escape
        self.progress = progress
    }

    /// Échap : l'écoute s'arrête au plus tard après `Timing.slice`, puis FL est remis comme avant.
    func cancel() {
        lock.lock()
        stopped = true
        lock.unlock()
    }

    private var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return stopped
    }

    /// Bloquant (à lancer hors du fil principal) ; `progress(fait, total)` est appelé avant chaque canal et à la fin.
    /// `chosen` : la page choisie dans l'Organiser (ses boutons), prise telle quelle ; sinon la page devant est
    /// demandée à FL (la première commande réveille le script : rien n'est su avant). Vidéo de l'utilisateur : le
    /// Mixer et la Playlist bien devant, FL ne les disait pas « focused » et l'Organiser attendait sans fin.
    func run(on chosen: OrganizerPage? = nil) -> Result<OrganizerResult, OrganizerError> {
        do {
            // Toujours demandée : c'est elle qui reconnaît un ancien script chargé dans FL (à redémarrer).
            let reported: FLWindow
            do {
                reported = try link.page()
            } catch OrganizerError.failed(_) where chosen != nil {
                reported = .unknown
            }
            note { $0.reported = "\(reported)" }
            let page: OrganizerPage
            if let chosen {
                page = chosen
            } else {
                switch reported {
                case .channelRack: page = .channelRack
                case .mixer: page = .mixer
                case .playlist: page = .playlist
                default: return .failure(.refused(1))
                }
            }
            note { $0.page = "\(page)" }
            if page == .playlist { return .success(try runPlaylist()) }
            // Un groupe affiché (« Unsorted »…) : ses canaux seulement, les autres ne sont pas touchés.
            let channels = try link.listChannels()
            let mixer: [MixerTrackInfo] = try page == .mixer ? link.listMixer() : []
            let targets = Self.sounds(channels)
            note { $0.listed = channels.count }
            let items: [OrganizerItem]
            if targets.isEmpty {
                items = []
            } else {
                try audio.start()
                defer {
                    // FL d'abord remis (lecture arrêtée, sourdines), puis la capture détruite : FL redevient audible.
                    link.stopRestore()
                    audio.stop()
                }
                items = try classifyChannels(targets)
            }
            let families = page == .mixer ? Self.mixerFamilies(items, mixer: mixer) : [:]
            return .success(OrganizerResult(page: page, channels: channels, items: items, mixer: mixer,
                                            mixerFamilies: families))
        } catch let error as OrganizerError {
            note { $0.error = "\(error)" }
            return .failure(error)
        } catch let error as CaptureError {
            note { $0.error = "\(error)" }
            return .failure(.failed(error.message))
        } catch {
            note { $0.error = "\(type(of: error))" }
            return .failure(.failed("Écoute de FL impossible (\(type(of: error)))."))
        }
    }

    /// Sons à classer : ni layers ni automations.
    static func sounds(_ channels: [ChannelInfo]) -> [ChannelInfo] {
        channels.filter { $0.type != ChannelInfo.layerType && $0.type != ChannelInfo.automationType }
    }

    /// Famille de chaque son, dans l'ordre de `targets` : son nom s'il la dit, sinon l'écoute (la capture est déjà
    /// lancée). Pas un son entendu et rien d'après les noms : la capture ne reçoit rien (`noSound`).
    private func classifyChannels(_ targets: [ChannelInfo]) throws -> [OrganizerItem] {
        var byIndex: [Int: OrganizerItem] = [:]
        var toListen: [ChannelInfo] = []
        for channel in targets {
            if let kind = SoundNames.kind(of: channel.name) {
                byIndex[channel.index] = OrganizerItem(
                    index: channel.index, name: channel.name, family: kind.family, confidence: Self.nameConfidence,
                    testNotes: false, mixerTrack: channel.mixerTrack, color: channel.color, kind: kind, byName: true)
            } else {
                toListen.append(channel)
            }
        }
        note { $0.targets = targets.count; $0.byName = targets.count - toListen.count }
        if !toListen.isEmpty {
            let heard = try listen(toListen)
            if heard.anyHeard == false && byIndex.isEmpty { throw OrganizerError.noSound }
            for item in heard.items { byIndex[item.index] = item }
        }
        progress(targets.count, targets.count)
        return targets.compactMap { byIndex[$0.index] }
    }

    /// Chaque son écouté seul, dans un pattern où il joue (repéré avant), sinon le pattern ouvert puis deux notes
    /// d'essai. La capture est déjà lancée ; FL est remis par l'appelant.
    private func listen(_ targets: [ChannelInfo]) throws -> (items: [OrganizerItem], anyHeard: Bool) {
        let homes = try findPatterns(for: targets)
        var items: [OrganizerItem] = []
        var heardAny = false
        for (done, channel) in targets.enumerated() {
            progress(done, targets.count)
            if isCancelled { throw OrganizerError.cancelled }
            audio.reset()
            try link.playSolo(channel.index, pattern: homes[channel.index])
            var samples = try listenUntilHeard()
            let tested = Self.peakDB(samples) < FamilyFusion.silenceDB
            if tested { samples = try playTestNotes(channel.index) }
            let heard = Self.peakDB(samples) >= FamilyFusion.silenceDB
            if heard { heardAny = true }
            note { $0.listened += 1; $0.heard += heard ? 1 : 0; $0.testNotes += tested ? 1 : 0 }
            let verdict = classify(samples, audio.rate)
            var kind: SoundKind?
            if verdict.family == .drums && heard, let drum = nameDrum?(samples, audio.rate) { kind = drum.sound }
            items.append(OrganizerItem(index: channel.index, name: channel.name, family: verdict.family,
                                       confidence: tested ? verdict.confidence * Self.testNotesFactor : verdict.confidence,
                                       testNotes: tested, mixerTrack: channel.mixerTrack, color: channel.color,
                                       kind: kind))
        }
        return (items, heardAny)
    }

    /// Pattern où joue chaque son (1 = le premier) : chaque pattern joué avec tous ses sons, FL dit lesquels jouent
    /// (aucune écoute). Rien si FL n'a qu'un pattern, ou si le script ou FL ne savent pas le dire (ancienne version).
    private func findPatterns(for targets: [ChannelInfo]) throws -> [Int: Int] {
        let info: (count: Int, current: Int)
        do {
            info = try link.patterns()
        } catch OrganizerError.cancelled {
            throw OrganizerError.cancelled
        } catch {
            note { $0.activity = "non (\(error))" }
            return [:]
        }
        note { $0.patterns = info.count }
        guard info.count > 1 else { return [:] }
        let wanted = Set(targets.map(\.index))
        var homes: [Int: Int] = [:]
        // Le pattern ouvert d'abord : un son qui y joue n'a pas besoin d'aller ailleurs.
        let order = [info.current] + (1...min(info.count, Self.maxPatternsScanned)).filter { $0 != info.current }
        for pattern in order where (1...info.count).contains(pattern) && homes.count < wanted.count {
            if isCancelled { throw OrganizerError.cancelled }
            let active: Set<Int>
            do {
                try link.playSolo(OrganizerPayload.allChannels, pattern: pattern)
                active = try readActive { try self.link.activeChannels() }
            } catch OrganizerError.cancelled {
                throw OrganizerError.cancelled
            } catch {
                note { $0.activity = "non (\(error))" }
                return homes
            }
            note { $0.scanned += 1; $0.activity = "oui" }
            for channel in active.intersection(wanted) where homes[channel] == nil { homes[channel] = pattern }
        }
        note { $0.homes = homes.count }
        return homes
    }

    /// Ce qui joue, relevé `scanReads` fois (FL éteint une activité peu après la note) ; l'union des relevés.
    private func readActive(_ read: () throws -> Set<Int>) throws -> Set<Int> {
        var out = Set<Int>()
        for _ in 0..<max(1, timing.scanReads) {
            try pause(timing.scanStep)
            out.formUnion(try read())
        }
        return out
    }

    // MARK: Playlist

    /// La chanson parcourue : à chaque position, FL dit quelles pistes et quels sons jouent (patterns, clips audio,
    /// sans écoute) ; les sons de chaque piste sont ceux qui jouent avec elle, et la piste prend leur famille (leur
    /// nom, sinon leur écoute). Script ou FL trop anciens pour le dire : chaque piste écoutée seule, comme avant.
    private func runPlaylist() throws -> OrganizerResult {
        let tracks = try link.listPlaylist(limit: .max)
        note { $0.listed = tracks.count }
        // Script trop ancien (FL pas redémarré) : l'ancienne façon, sans lancer la capture deux fois.
        guard (try? link.patterns()) != nil else {
            note { $0.activity = "non (script)" }
            let targets = Self.playlistTargets(tracks)
            let lastNamed = tracks.contains(where: \.selected) ? nil : Self.lastNamed(tracks)
            let items = try listenPlaylist(targets, stopAfterSilence: lastNamed)
            return OrganizerResult(page: .playlist, channels: [], items: items, mixer: [], mixerFamilies: [:],
                                   playlist: tracks)
        }
        let channels = Self.sounds(try link.listChannels())
        try audio.start()
        var restored = false
        defer {
            if !restored {
                link.stopRestore()
                audio.stop()
            }
        }
        guard let samples = try sampleSong() else {
            // Ancienne façon : chaque piste écoutée seule (elle relance sa propre capture).
            link.stopRestore()
            audio.stop()
            restored = true
            let targets = Self.playlistTargets(tracks)
            let lastNamed = tracks.contains(where: \.selected) ? nil : Self.lastNamed(tracks)
            let items = try listenPlaylist(targets, stopAfterSilence: lastNamed)
            return OrganizerResult(page: .playlist, channels: [], items: items, mixer: [], mixerFamilies: [:],
                                   playlist: tracks)
        }
        let selected = Set(tracks.filter(\.selected).map(\.index))
        var sounds = Self.trackSounds(samples)
        if !selected.isEmpty { sounds = sounds.filter { selected.contains($0.key) } }
        let used = Set(sounds.values.flatMap(\.keys))
        let classified = try classifyChannels(channels.filter { used.contains($0.index) })
        var byChannel: [Int: OrganizerItem] = [:]
        for item in classified { byChannel[item.index] = item }
        var items: [OrganizerItem] = []
        for track in tracks {
            guard let mine = sounds[track.index],
                  let verdict = Self.trackFamily(mine, items: byChannel) else { continue }
            items.append(OrganizerItem(index: track.index, name: track.name, family: verdict.family,
                                       confidence: verdict.confidence, testNotes: false, mixerTrack: 0,
                                       color: track.color, kind: verdict.kind,
                                       byName: mine.keys.allSatisfy { byChannel[$0]?.byName ?? false }))
        }
        note { $0.tracks = items.count }
        return OrganizerResult(page: .playlist, channels: [], items: items, mixer: [], mixerFamilies: [:],
                               playlist: tracks)
    }

    /// Relevés de ce qui joue à chaque position de la chanson (pistes, sons) ; nil si FL ou le script ne savent pas
    /// le dire (l'ancienne façon prend le relais).
    private func sampleSong() throws -> [(tracks: Set<Int>, channels: Set<Int>)]? {
        var out: [(tracks: Set<Int>, channels: Set<Int>)] = []
        do {
            let bars = try link.playSong(at: 0)
            let positions = Self.songPositions(bars: bars)
            note { $0.positions = positions.count; $0.activity = "oui" }
            for (k, position) in positions.enumerated() {
                progress(k, positions.count + 1)
                if isCancelled { throw OrganizerError.cancelled }
                if k > 0 { _ = try link.playSong(at: position) }
                try pause(timing.settle)
                var tracks = Set<Int>(), channels = Set<Int>()
                for _ in 0..<max(1, timing.scanReads) {
                    try pause(timing.scanStep)
                    tracks.formUnion(try link.activeTracks())
                    channels.formUnion(try link.activeChannels())
                }
                if !tracks.isEmpty && !channels.isEmpty { out.append((tracks, channels)) }
            }
        } catch OrganizerError.cancelled {
            throw OrganizerError.cancelled
        } catch OrganizerError.refused(4) {
            throw OrganizerError.refused(4)
        } catch {
            note { $0.activity = "non (\(error))" }
            return nil
        }
        note { $0.activeSamples = out.count }
        return out
    }

    /// Pur (testé) : positions (0…1) relevées dans la chanson : toutes les 2 mesures (`maxPositions` au plus), 16 si
    /// FL ne donne pas sa longueur.
    static func songPositions(bars: Int) -> [Double] {
        let count = bars > 0 ? min(maxPositions, max(1, (bars + 1) / 2)) : 16
        return (0..<count).map { Double($0) / Double(count) }
    }

    /// Pur (testé) : sons de chaque piste, avec leur poids (0…1), d'après les relevés. Un son va sur la piste dont
    /// les moments de jeu ressemblent le plus aux siens (Jaccard) ; à égalité (pistes qui jouent toujours ensemble),
    /// sur chacune. En dessous de 0,3 : rien.
    static func trackSounds(_ samples: [(tracks: Set<Int>, channels: Set<Int>)]) -> [Int: [Int: Double]] {
        var trackCount: [Int: Int] = [:], channelCount: [Int: Int] = [:], both: [Int: [Int: Int]] = [:]
        for sample in samples {
            for t in sample.tracks { trackCount[t, default: 0] += 1 }
            for c in sample.channels { channelCount[c, default: 0] += 1 }
            for t in sample.tracks {
                for c in sample.channels { both[t, default: [:]][c, default: 0] += 1 }
            }
        }
        var out: [Int: [Int: Double]] = [:]
        for (channel, played) in channelCount {
            var scores: [Int: Double] = [:]
            for (track, count) in trackCount {
                let together = both[track]?[channel] ?? 0
                guard together > 0 else { continue }
                scores[track] = Double(together) / Double(count + played - together)
            }
            guard let best = scores.values.max(), best >= 0.3 else { continue }
            for (track, score) in scores where score >= best * 0.8 { out[track, default: [:]][channel] = score }
        }
        return out
    }

    /// Pur (testé) : famille d'une piste d'après ses sons (poids × confiance ; « À vérifier » seulement si rien
    /// d'autre) et ce qu'ils sont quand tous ceux de la famille le disent pareil (Kick, 808…) ; sinon, pour des
    /// drums, « Drums ».
    static func trackFamily(_ sounds: [Int: Double], items: [Int: OrganizerItem])
        -> (family: SoundFamily, confidence: Double, kind: SoundKind?)? {
        var weight: [SoundFamily: Double] = [:]
        var total = 0.0
        for (channel, score) in sounds {
            guard let item = items[channel] else { continue }
            weight[item.family, default: 0] += score * max(item.confidence, 0.1)
            total += score * max(item.confidence, 0.1)
        }
        guard total > 0 else { return nil }
        let known = weight.filter { $0.key != .unsure }
        let pick = (known.isEmpty ? weight : known).max { a, b in
            a.value != b.value ? a.value < b.value : a.key.rank > b.key.rank
        }
        guard let best = pick else { return nil }
        let family = best.key, w = best.value
        let kinds = Set(sounds.keys.compactMap { items[$0].flatMap { $0.family == family ? $0.kind : nil } })
        var kind: SoundKind? = kinds.count == 1 ? kinds.first : nil
        if kind == nil && family == .drums { kind = SoundKind.drums }
        return (family, min(1, w / total), kind)
    }

    /// `stopAfterSilence` : index de la dernière piste renommée ; au-delà, l'écoute s'arrête après
    /// `silentRunStop` pistes muettes de suite (nil : toutes les pistes demandées sont écoutées).
    private func listenPlaylist(_ targets: [PlaylistTrackInfo], stopAfterSilence: Int?) throws -> [OrganizerItem] {
        guard !targets.isEmpty else { return [] }
        try audio.start()
        defer {
            link.stopRestore()
            audio.stop()
        }
        var items: [OrganizerItem] = []
        var silentRun = 0
        for (done, track) in targets.enumerated() {
            progress(done, targets.count)
            if isCancelled { throw OrganizerError.cancelled }
            guard let samples = try hear(track.index) else {
                if let last = stopAfterSilence, track.index > max(last, Self.minTracksScanned - 1) {
                    silentRun += 1
                    if silentRun >= Self.silentRunStop { break }
                }
                continue
            }
            silentRun = 0
            let verdict = classify(samples, audio.rate)
            var kind: SoundKind?
            if verdict.family == .drums, let drum = nameDrum?(samples, audio.rate) { kind = drum.sound }
            items.append(OrganizerItem(index: track.index, name: track.name, family: verdict.family,
                                       confidence: verdict.confidence, testNotes: false, mixerTrack: 0,
                                       color: track.color, kind: kind))
        }
        progress(targets.count, targets.count)
        if items.isEmpty { throw OrganizerError.noSound }
        return items
    }

    /// La piste seule, chanson jouée depuis son début puis aux positions de `probePositions` jusqu'à ce qu'elle
    /// sonne ; ensuite `Timing.listen` de plus. nil si elle reste muette partout.
    private func hear(_ track: Int) throws -> [Float]? {
        audio.reset()
        let bars = try link.playTrack(track)
        for (k, position) in Self.probePositions(bars: bars).enumerated() {
            if k > 0 {
                try link.seek(position)
                audio.reset()
            }
            try pause(timing.probe)
            let heard = audio.take()
            if Self.peakDB(heard) >= FamilyFusion.silenceDB {
                try pause(min(timing.listen, timing.afterSound))
                return heard + audio.take()
            }
        }
        return nil
    }

    /// Écoute jusqu'à `afterSound` après le premier son entendu (`listen` au plus) ; toujours muet au bout de
    /// `silentGiveUp` : on arrête là (les notes d'essai prennent le relais). Le son reçu depuis `reset`.
    private func listenUntilHeard() throws -> [Float] {
        let step = timing.slice
        let steps = max(1, Int((timing.listen / step).rounded(.up)))
        var heardAt: Int?
        for k in 1...steps {
            try pause(step)
            let elapsed = Double(k) * step
            if heardAt == nil, Self.peakDB(audio.take()) >= FamilyFusion.silenceDB { heardAt = k }
            if let at = heardAt, Double(k - at) * step >= timing.afterSound - 1e-9 { break }
            if heardAt == nil, elapsed >= timing.silentGiveUp - 1e-9 { break }
        }
        return audio.take()
    }

    /// Chaque note est toujours coupée (vélocité 0), même après Échap.
    private func playTestNotes(_ channel: Int) throws -> [Float] {
        audio.reset()
        for note in Self.testNotes {
            try link.audition(channel, note: note, velocity: Self.testVelocity)
            let finished = wait(timing.testNote)
            try link.audition(channel, note: note, velocity: 0)
            if !finished { throw OrganizerError.cancelled }
        }
        try pause(timing.tail)
        return audio.take()
    }

    private func pause(_ seconds: TimeInterval) throws {
        if !wait(seconds) { throw OrganizerError.cancelled }
    }

    /// Attend par petites tranches ; false si Échap a été pressé.
    private func wait(_ seconds: TimeInterval) -> Bool {
        let steps = max(1, Int((seconds / timing.slice).rounded(.up)))
        for _ in 0..<steps {
            if escape() { cancel() }
            if isCancelled { return false }
            sleep(seconds / Double(steps))
        }
        return !isCancelled
    }

    // MARK: Pur

    /// Index de la dernière piste renommée (-1 s'il n'y en a pas).
    static func lastNamed(_ tracks: [PlaylistTrackInfo]) -> Int {
        tracks.last(where: { !$0.hasDefaultName })?.index ?? -1
    }

    /// Pistes à écouter : les pistes sélectionnées s'il y en a ; sinon de la première à la dernière renommée, plus
    /// `extraTracks` pistes au nom de FL après elle ; `maxTracks` au plus.
    static func playlistTargets(_ tracks: [PlaylistTrackInfo]) -> [PlaylistTrackInfo] {
        let selected = tracks.filter(\.selected)
        if !selected.isEmpty { return Array(selected.prefix(maxTracks)) }
        let end = min(tracks.count, lastNamed(tracks) + 1 + extraTracks, maxTracks)
        return Array(tracks.prefix(end))
    }

    /// Positions (0…1) essayées pour trouver le son d'une piste : le début, puis toutes les 4 mesures (24 positions
    /// au plus, 16 si FL ne donne pas la longueur).
    static func probePositions(bars: Int) -> [Double] {
        let count = bars > 0 ? min(24, max(1, (bars + 3) / 4)) : 16
        return (0..<count).map { Double($0) / Double(count) }
    }

    /// Crête en dBFS (−180 pour un son vide).
    static func peakDB(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return -180 }
        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))
        return 20 * log10(max(Double(peak), 1e-9))
    }

    /// Famille majoritaire des canaux reliés à chaque piste (sans compter « À vérifier » ; égalité → l'ordre des
    /// familles). Pistes sans canal écouté et Master laissés tels quels.
    static func mixerFamilies(_ items: [OrganizerItem], mixer: [MixerTrackInfo]) -> [Int: SoundFamily] {
        var out: [Int: SoundFamily] = [:]
        for track in mixer where track.index > 0 {
            let linked = items.filter { $0.mixerTrack == track.index }
            guard !linked.isEmpty else { continue }
            var counts: [SoundFamily: Int] = [:]
            for item in linked where item.family != .unsure { counts[item.family, default: 0] += 1 }
            let best = counts.max { a, b in a.value != b.value ? a.value < b.value : a.key.rank > b.key.rank }
            out[track.index] = best?.key ?? .unsure
        }
        return out
    }

    /// Classement réel : mesures du son et, si macOS l'a, son IA (sur le Mac, sans internet).
    static func liveClassifier(ai: SoundClassifier? = SoundClassifier()) -> Classify {
        { samples, rate in
            let features = SoundFeatures.measure(samples, rate: rate)
            let labels = ai.map { AILabels(scores: $0.scores(samples, rate: rate)) } ?? AILabels.none
            return FamilyFusion.decide(features, labels)
        }
    }

    /// Sorte des drums : étiquettes de l'IA de macOS, sinon les mesures du son.
    static func liveDrumNamer(ai: SoundClassifier? = SoundClassifier()) -> NameDrum {
        { samples, rate in
            DrumNaming.kind(SoundFeatures.measure(samples, rate: rate), scores: ai?.scores(samples, rate: rate) ?? [:])
        }
    }
}
