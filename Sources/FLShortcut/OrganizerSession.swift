// Organiser : tout le projet d'un coup. Ce qu'est chaque son du Channel rack (son nom, sinon son écoute dans un
// pattern où il joue, avec deux notes d'essai en secours), les sons de chaque pattern (chaque pattern joué, FL dit ce
// qui joue), ceux de chaque piste de la Playlist (la chanson relevée, puis chaque piste jouée seule : FL dit quels sons
// jouent ; un clip audio sans son reconnu est écouté) et les envois du Mixer. Les sons et pistes coupés par
// l'utilisateur sont audibles le temps de l'analyse (retour de l'utilisateur : trois pistes sautées, leurs sons étaient
// coupés). Tourne hors du fil principal ; FL est toujours remis comme avant (opération 7) avant que le son de FL
// revienne, même après une erreur ou Échap. Les noms ne sont jamais journalisés (le diagnostic n'a que des nombres).
import Accelerate
import Foundation

/// Un son du Channel rack classé, ou une piste de la Playlist classée à l'écoute (clip audio).
struct OrganizerItem: Equatable {
    let index: Int
    let name: String
    var family: SoundFamily
    var confidence: Double
    /// Le canal se taisait dans ses patterns : classé avec les notes d'essai (confiance plus basse).
    var testNotes: Bool
    let mixerTrack: Int
    let color: RGBColor
    /// Ce qu'est le son (Kick, 808, Open Hat…) : d'après son nom, ou pour des drums écoutés, leur sorte.
    var kind: SoundKind? = nil
    /// Classé d'après son nom, sans écoute.
    var byName = false
}

/// Ce que la dernière analyse a fait, en nombres seulement (« Copier le diagnostic ») : jamais un nom.
struct OrganizerDiagnostics: Equatable {
    var listed = 0
    var targets = 0
    var byName = 0
    var listened = 0
    var heard = 0
    var testNotes = 0
    var patterns = 0
    var scanned = 0
    var withSounds = 0
    var activity = "?"
    var positions = 0
    var activeSamples = 0
    var tracks = 0
    var tracksSolo = 0
    var tracksHeard = 0
    var mixerUsed = 0
    var routes = 0
    var capture = CaptureStats()
    var error = ""

    var text: String {
        ["canaux=\(listed) sons=\(targets) nom=\(byName) écoutés=\(listened) entendus=\(heard) notes=\(testNotes)",
         "patterns=\(patterns) relevés=\(scanned) avec-sons=\(withSounds) activité=\(activity) positions=\(positions) "
            + "relevés-chanson=\(activeSamples) pistes=\(tracks) seules=\(tracksSolo) écoutées=\(tracksHeard) "
            + "mixer=\(mixerUsed) envois=\(routes)",
         capture.text,
         error.isEmpty ? "" : "erreur=\(error)"].filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

/// Tout ce que l'analyse a lu et compris du projet.
struct OrganizerResult: Equatable {
    /// Tous les canaux, dans l'ordre du Channel rack (layers et automations compris, jamais classés).
    let channels: [ChannelInfo]
    /// Sons classés, dans l'ordre du Channel rack.
    let items: [OrganizerItem]
    var patterns: [PatternInfo] = []
    /// Sons (index des canaux) qui jouent dans chaque pattern (index 0 = pattern 1) ; patterns vides absents.
    var patternSounds: [Int: Set<Int>] = [:]
    /// Toutes les pistes du Mixer (Master compris).
    var mixer: [MixerTrackInfo] = []
    /// Pistes du Mixer vers lesquelles envoie chaque piste reliée à un son, ou qui en reçoit (sans le Master).
    var routes: [Int: [Int]] = [:]
    /// Pistes de la Playlist lues (jusqu'à la dernière qui joue).
    var playlist: [PlaylistTrackInfo] = []
    /// Sons qui jouent sur chaque piste de la Playlist (index 0 = piste 1).
    var trackSounds: [Int: Set<Int>] = [:]
    /// Pistes sans son du Channel rack reconnu (clips audio), classées à l'écoute.
    var trackItems: [OrganizerItem] = []
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
        /// Piste de la Playlist sans son reconnu : écoutée encore ce temps-là (clip audio).
        var probe: TimeInterval = 0.4
        /// Écoute après le premier son entendu : assez pour le classer.
        var afterSound: TimeInterval = 1.5
        /// Encore rien entendu au bout de ce délai : les notes d'essai tout de suite.
        var silentGiveUp: TimeInterval = 1.5
        /// Relevé de ce qui joue (pattern, position de la chanson, piste seule) : à cet intervalle, `scanReads` fois.
        var scanStep: TimeInterval = 0.2
        var scanReads = 4
        /// Après un saut dans la chanson, avant le premier relevé.
        var settle: TimeInterval = 0.2
    }

    typealias Classify = ([Float], Double) -> (family: SoundFamily, confidence: Double)
    /// Sorte d'un son classé en drums.
    typealias NameDrum = ([Float], Double) -> DrumKind

    /// Notes d'essai : C3 puis C5 (pour FPC, ses deux premiers pads).
    static let testNotes: [UInt8] = [48, 60]
    static let testVelocity: UInt8 = 100
    /// Un classement fait avec les notes d'essai compte moins.
    static let testNotesFactor = 0.7
    /// Classé d'après son nom : aussi sûr qu'une bonne écoute.
    static let nameConfidence = 0.9
    /// Patterns relevés au plus (une seconde chacun environ).
    static let maxPatternsScanned = 64
    /// Positions de la chanson relevées au plus.
    static let maxPositions = 64
    /// Pistes de la Playlist jouées seules au plus.
    static let maxTracks = 64
    /// Pistes du Mixer dont les envois sont lus au plus.
    static let maxRouted = 64

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
    /// Avancement : étapes faites et prévues (le total grandit quand une étape en découvre d'autres).
    private var stepsDone = 0
    private var stepsTotal = 0

    /// Ce que l'analyse a fait (lu une fois `run` fini).
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

    /// Échap : l'analyse s'arrête au plus tard après `Timing.slice`, puis FL est remis comme avant.
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

    private func plan(_ more: Int) {
        stepsTotal += more
        progress(stepsDone, stepsTotal)
    }

    private func step() throws {
        if isCancelled { throw OrganizerError.cancelled }
        progress(stepsDone, stepsTotal)
        stepsDone += 1
    }

    /// Bloquant (à lancer hors du fil principal) ; `progress(fait, total)` est appelé à chaque étape et à la fin.
    func run() -> Result<OrganizerResult, OrganizerError> {
        do {
            // La première commande réveille le script ; un script d'avant la v12 la refuse : FL à redémarrer.
            let patterns = try link.listPatterns()
            let channels = try link.listChannels()
            let mixer = try link.listMixer()
            let targets = Self.sounds(channels)
            note { $0.listed = channels.count; $0.patterns = patterns.count }
            plan(min(patterns.count, Self.maxPatternsScanned))
            try audio.start()
            defer {
                // FL d'abord remis (lecture arrêtée, sourdines), puis la capture détruite : FL redevient audible.
                link.stopRestore()
                audio.stop()
            }
            let patternSounds = try scanPatterns(count: patterns.count)
            let items = try classifyChannels(targets, homes: Self.homes(patternSounds))
            let song = try readPlaylist()
            let routes = try readRoutes(targets, mixer: mixer)
            progress(stepsTotal, stepsTotal)
            return .success(OrganizerResult(channels: channels, items: items, patterns: patterns,
                                            patternSounds: patternSounds, mixer: mixer, routes: routes,
                                            playlist: song.tracks, trackSounds: song.sounds, trackItems: song.heard))
        } catch let error as OrganizerError {
            note { $0.error = "\(error)" }
            return .failure(error)
        } catch let error as CaptureError {
            note { $0.error = "\(error)" }
            return .failure(.failed(error.message))
        } catch {
            note { $0.error = String(describing: type(of: error)) }
            return .failure(.failed(String(localized: "Écoute de FL impossible (\(String(describing: type(of: error)))).")))
        }
    }

    /// Sons à classer : ni layers ni automations.
    static func sounds(_ channels: [ChannelInfo]) -> [ChannelInfo] {
        channels.filter { $0.type != ChannelInfo.layerType && $0.type != ChannelInfo.automationType }
    }

    // MARK: Patterns

    /// Sons qui jouent dans chaque pattern (index 0 = pattern 1) : chaque pattern joué avec tous les sons audibles,
    /// FL dit lesquels jouent (aucune écoute). FL trop ancien pour le dire : rien.
    private func scanPatterns(count: Int) throws -> [Int: Set<Int>] {
        let n = min(count, Self.maxPatternsScanned)
        guard n > 0 else { return [:] }
        var out: [Int: Set<Int>] = [:]
        for pattern in 1...n {
            try step()
            let active: Set<Int>
            do {
                try link.playSolo(OrganizerPayload.allChannels, pattern: pattern)
                active = try readActive { try self.link.activeChannels() }
            } catch OrganizerError.cancelled {
                throw OrganizerError.cancelled
            } catch OrganizerError.refused(4) {
                throw OrganizerError.refused(4)
            } catch {
                note { $0.activity = "non (\(error))" }
                return out
            }
            note { $0.scanned += 1; $0.activity = "oui"; $0.withSounds += active.isEmpty ? 0 : 1 }
            if !active.isEmpty { out[pattern - 1] = active }
        }
        return out
    }

    /// Pur (testé) : le premier pattern (1 = le premier de FL) où joue chaque son.
    static func homes(_ patternSounds: [Int: Set<Int>]) -> [Int: Int] {
        var out: [Int: Int] = [:]
        for pattern in patternSounds.keys.sorted() {
            for channel in patternSounds[pattern] ?? [] where out[channel] == nil { out[channel] = pattern + 1 }
        }
        return out
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

    // MARK: Sons du Channel rack

    /// Chaque son : son nom s'il dit ce qu'il est, sinon son écoute (la capture est déjà lancée), dans le pattern où il
    /// joue. Pas un son entendu et rien d'après les noms : la capture ne reçoit rien (`noSound`).
    private func classifyChannels(_ targets: [ChannelInfo], homes: [Int: Int]) throws -> [OrganizerItem] {
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
            plan(toListen.count)
            let heard = try listen(toListen, homes: homes)
            if heard.anyHeard == false && byIndex.isEmpty { throw OrganizerError.noSound }
            for item in heard.items { byIndex[item.index] = item }
        }
        return targets.compactMap { byIndex[$0.index] }
    }

    /// Chaque son écouté seul, dans un pattern où il joue (sinon le pattern ouvert), puis deux notes d'essai s'il se
    /// tait. La capture est déjà lancée ; FL est remis par l'appelant.
    private func listen(_ targets: [ChannelInfo], homes: [Int: Int]) throws -> (items: [OrganizerItem], anyHeard: Bool) {
        var items: [OrganizerItem] = []
        var heardAny = false
        for channel in targets {
            try step()
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

    // MARK: Playlist

    /// Pistes de la Playlist qui jouent et leurs sons : la chanson relevée à plusieurs positions (FL dit quelles pistes
    /// jouent), puis chaque piste jouée seule à une position où elle joue avec le moins d'autres pistes (FL dit quels
    /// sons jouent). Rien de reconnu (clip audio) : la piste est écoutée et classée à l'écoute ; FL ne dit rien du
    /// tout : les sons qui jouent en même temps qu'elle. FL trop ancien pour le dire : aucune piste.
    private func readPlaylist() throws -> (tracks: [PlaylistTrackInfo], sounds: [Int: Set<Int>], heard: [OrganizerItem]) {
        guard let samples = try sampleSong(), !samples.isEmpty else { return ([], [:], []) }
        var activeAt: [Int: [Int]] = [:]          // piste -> relevés où elle joue
        for (k, sample) in samples.enumerated() {
            for t in sample.tracks { activeAt[t, default: []].append(k) }
        }
        let active = Array(activeAt.keys.sorted().prefix(Self.maxTracks))
        guard let last = active.last else { return ([], [:], []) }
        let tracks = try link.listPlaylist(limit: last + 1)
        let together = Self.trackSounds(samples.map { (tracks: $0.tracks, channels: $0.channels) })
        note { $0.tracks = active.count }
        plan(active.count)
        var sounds: [Int: Set<Int>] = [:]
        var heard: [OrganizerItem] = []
        for t in active {
            try step()
            let at = Self.quietestSample(activeAt[t] ?? [], samples: samples.map { $0.tracks })
            let fraction = at.map { samples[$0].position } ?? 0
            _ = try link.playTrack(t)
            if fraction > 0 { try link.seek(fraction) }
            try pause(timing.settle)
            audio.reset()
            let playing = try readActive { try self.link.activeChannels() }
            if !playing.isEmpty {
                sounds[t] = playing
                note { $0.tracksSolo += 1 }
                continue
            }
            try pause(timing.probe)
            let samplesHeard = audio.take()
            if Self.peakDB(samplesHeard) >= FamilyFusion.silenceDB, let track = tracks.first(where: { $0.index == t }) {
                let verdict = classify(samplesHeard, audio.rate)
                var kind: SoundKind?
                if verdict.family == .drums, let drum = nameDrum?(samplesHeard, audio.rate) { kind = drum.sound }
                heard.append(OrganizerItem(index: t, name: track.name, family: verdict.family,
                                           confidence: verdict.confidence, testNotes: false, mixerTrack: 0,
                                           color: track.color, kind: kind))
                note { $0.tracksHeard += 1 }
            } else if let guess = together[t], !guess.isEmpty {
                sounds[t] = Set(guess.keys)
            }
        }
        return (tracks, sounds, heard)
    }

    /// Relevés de ce qui joue à chaque position de la chanson (pistes, sons), tout audible ; nil si FL ou le script ne
    /// savent pas le dire.
    private func sampleSong() throws -> [(position: Double, tracks: Set<Int>, channels: Set<Int>)]? {
        var out: [(position: Double, tracks: Set<Int>, channels: Set<Int>)] = []
        do {
            let bars = try link.playSong(at: 0)
            let positions = Self.songPositions(bars: bars)
            note { $0.positions = positions.count; $0.activity = "oui" }
            plan(positions.count)
            for (k, position) in positions.enumerated() {
                try step()
                if k > 0 { _ = try link.playSong(at: position) }
                try pause(timing.settle)
                var tracks = Set<Int>(), channels = Set<Int>()
                for _ in 0..<max(1, timing.scanReads) {
                    try pause(timing.scanStep)
                    tracks.formUnion(try link.activeTracks())
                    channels.formUnion(try link.activeChannels())
                }
                if !tracks.isEmpty { out.append((position: position, tracks: tracks, channels: channels)) }
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

    /// Pur (testé) : parmi les relevés où une piste joue, celui où le moins d'autres pistes jouent (égalité : le
    /// premier) ; nil s'il n'y en a pas.
    static func quietestSample(_ candidates: [Int], samples: [Set<Int>]) -> Int? {
        candidates.filter { samples.indices.contains($0) }.min { a, b in
            samples[a].count != samples[b].count ? samples[a].count < samples[b].count : a < b
        }
    }

    /// Pur (testé) : positions (0…1) relevées dans la chanson : toutes les 2 mesures (`maxPositions` au plus), 16 si
    /// FL ne donne pas sa longueur.
    static func songPositions(bars: Int) -> [Double] {
        let count = bars > 0 ? min(maxPositions, max(1, (bars + 1) / 2)) : 16
        return (0..<count).map { Double($0) / Double(count) }
    }

    /// Pur (testé) : sons de chaque piste d'après les relevés seulement (repli quand FL ne dit rien de la piste jouée
    /// seule), avec leur poids (0…1). Un son va sur la piste dont les moments de jeu ressemblent le plus aux siens
    /// (Jaccard) ; à égalité (pistes qui jouent toujours ensemble), sur chacune. En dessous de 0,3 : rien.
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

    // MARK: Mixer

    /// Envois des pistes du Mixer reliées à un son, puis de celles qui les reçoivent (pistes de groupe), `maxRouted`
    /// pistes au plus. Le Master et la piste « Current » (la dernière) ne comptent pas.
    private func readRoutes(_ targets: [ChannelInfo], mixer: [MixerTrackInfo]) throws -> [Int: [Int]] {
        let last = mixer.count - 2
        guard last >= 1 else { return [:] }
        var todo = Array(Set(targets.map(\.mixerTrack).filter { (1...last).contains($0) })).sorted()
        var seen = Set(todo)
        var out: [Int: [Int]] = [:]
        note { $0.mixerUsed = todo.count }
        while !todo.isEmpty, out.count < Self.maxRouted {
            if isCancelled { throw OrganizerError.cancelled }
            let track = todo.removeFirst()
            let dests = try link.routes(from: track).filter { (1...last).contains($0) && $0 != track }
            out[track] = dests
            for d in dests where !seen.contains(d) {
                seen.insert(d)
                todo.append(d)
            }
        }
        note { $0.routes = out.values.reduce(0) { $0 + $1.count } }
        return out
    }

    // MARK: Écoute

    /// Écoute jusqu'à `afterSound` après le premier son entendu (`listen` au plus) ; toujours muet au bout de
    /// `silentGiveUp` : on arrête là (les notes d'essai prennent le relais). Le son reçu depuis `reset`.
    private func listenUntilHeard() throws -> [Float] {
        let step = timing.slice
        let steps = max(1, Int((timing.listen / step).rounded(.up)))
        var heardAt: Int?
        var kept: [Float] = []
        for k in 1...steps {
            try pause(step)
            let elapsed = Double(k) * step
            let chunk = audio.take()
            if heardAt != nil {
                kept += chunk
            } else if Self.peakDB(chunk) >= FamilyFusion.silenceDB {
                heardAt = k
                kept = chunk
            }
            if let at = heardAt, Double(k - at) * step >= timing.afterSound - 1e-9 { break }
            if heardAt == nil, elapsed >= timing.silentGiveUp - 1e-9 { break }
        }
        return kept + audio.take()
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

    /// Crête en dBFS (−180 pour un son vide).
    static func peakDB(_ samples: [Float]) -> Double {
        guard !samples.isEmpty else { return -180 }
        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))
        return 20 * log10(max(Double(peak), 1e-9))
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
