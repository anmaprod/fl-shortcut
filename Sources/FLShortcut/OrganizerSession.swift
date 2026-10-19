// Organiser : écoute de chaque canal de FL (ta partie d'abord, notes d'essai en secours si le canal se tait), classement
// en familles, et famille de chaque piste du Mixer ; ou écoute de chaque piste de la Playlist seule (la chanson
// parcourue jusqu'à ce que la piste sonne). Tourne hors du fil principal ; FL est toujours remis comme avant
// (opération 7) avant que le son de FL revienne, même après une erreur ou Échap. Les noms ne sont jamais journalisés.
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
    /// Drums d'une piste de la Playlist : leur sorte (le nouveau nom de la piste).
    var drum: DrumKind? = nil
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
    /// renommées ont souvent des clips), 64 au plus ; l'écoute s'arrête après 3 pistes muettes de suite au-delà.
    static let extraTracks = 32
    static let maxTracks = 64
    static let silentRunStop = 3

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
    /// La page devant est demandée à FL (la première commande réveille le script : rien n'est su avant).
    func run() -> Result<OrganizerResult, OrganizerError> {
        do {
            let page: OrganizerPage
            switch try link.page() {
            case .channelRack: page = .channelRack
            case .mixer: page = .mixer
            case .playlist: return .success(try runPlaylist())
            default: return .failure(.refused(1))
            }
            let list = try link.listChannels()
            if list.filtered { return .failure(.filteredGroup) }
            let mixer: [MixerTrackInfo] = try page == .mixer ? link.listMixer() : []
            let targets = list.channels.filter {
                $0.type != ChannelInfo.layerType && $0.type != ChannelInfo.automationType
            }
            let items = try listen(targets)
            let families = page == .mixer ? Self.mixerFamilies(items, mixer: mixer) : [:]
            return .success(OrganizerResult(page: page, channels: list.channels, items: items, mixer: mixer,
                                            mixerFamilies: families))
        } catch let error as OrganizerError {
            return .failure(error)
        } catch let error as CaptureError {
            return .failure(.failed(error.message))
        } catch {
            return .failure(.failed("Écoute de FL impossible (\(type(of: error)))."))
        }
    }

    private func listen(_ targets: [ChannelInfo]) throws -> [OrganizerItem] {
        guard !targets.isEmpty else { return [] }
        try audio.start()
        defer {
            // FL d'abord remis (lecture arrêtée, sourdines), puis la capture détruite : FL redevient audible.
            link.stopRestore()
            audio.stop()
        }
        var items: [OrganizerItem] = []
        for (done, channel) in targets.enumerated() {
            progress(done, targets.count)
            if isCancelled { throw OrganizerError.cancelled }
            audio.reset()
            try link.playSolo(channel.index)
            var samples = try listenUntilHeard()
            let tested = Self.peakDB(samples) < FamilyFusion.silenceDB
            if tested { samples = try playTestNotes(channel.index) }
            let verdict = classify(samples, audio.rate)
            items.append(OrganizerItem(index: channel.index, name: channel.name, family: verdict.family,
                                       confidence: tested ? verdict.confidence * Self.testNotesFactor : verdict.confidence,
                                       testNotes: tested, mixerTrack: channel.mixerTrack, color: channel.color))
        }
        progress(targets.count, targets.count)
        return items
    }

    // MARK: Playlist

    private func runPlaylist() throws -> OrganizerResult {
        let tracks = try link.listPlaylist(limit: .max)
        let targets = Self.playlistTargets(tracks)
        let lastNamed = tracks.contains(where: \.selected) ? nil : Self.lastNamed(tracks)
        let items = try listenPlaylist(targets, stopAfterSilence: lastNamed)
        return OrganizerResult(page: .playlist, channels: [], items: items, mixer: [], mixerFamilies: [:],
                               playlist: tracks)
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
                if let last = stopAfterSilence, track.index > last {
                    silentRun += 1
                    if silentRun >= Self.silentRunStop { break }
                }
                continue
            }
            silentRun = 0
            let verdict = classify(samples, audio.rate)
            let drum = verdict.family == .drums ? nameDrum?(samples, audio.rate) : nil
            items.append(OrganizerItem(index: track.index, name: track.name, family: verdict.family,
                                       confidence: verdict.confidence, testNotes: false, mixerTrack: 0,
                                       color: track.color, drum: drum))
        }
        progress(targets.count, targets.count)
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
