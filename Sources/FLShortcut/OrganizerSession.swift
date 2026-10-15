// Organiser : écoute de chaque canal de FL (ta partie d'abord, notes d'essai en secours si le canal se tait), classement
// en familles, et famille de chaque piste du Mixer. Tourne hors du fil principal ; FL est toujours remis comme avant
// (opération 7) avant que le son de FL revienne, même après une erreur ou Échap. Les noms ne sont jamais journalisés.
import Accelerate
import Foundation

enum OrganizerPage: Equatable {
    case channelRack, mixer
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
}

final class OrganizerSession {
    struct Timing {
        /// Écoute de ta partie (le pattern depuis son début).
        var listen: TimeInterval = 3
        /// Durée de chaque note d'essai.
        var testNote: TimeInterval = 0.3
        /// Queue du son après les notes d'essai.
        var tail: TimeInterval = 0.6
        /// Échap est vu au plus tard après ce délai.
        var slice: TimeInterval = 0.05
    }

    typealias Classify = ([Float], Double) -> (family: SoundFamily, confidence: Double)

    /// Notes d'essai : C3 puis C5 (pour FPC, ses deux premiers pads).
    static let testNotes: [UInt8] = [48, 60]
    static let testVelocity: UInt8 = 100
    /// Un classement fait avec les notes d'essai compte moins.
    static let testNotesFactor = 0.7

    private let link: OrganizerLink
    private let audio: AudioSource
    private let classify: Classify
    private let timing: Timing
    private let sleep: (TimeInterval) -> Void
    private let progress: (Int, Int) -> Void
    private let escape: () -> Bool
    private let lock = NSLock()
    private var stopped = false

    /// `escape` : Échap pressé, regardé à chaque tranche d'attente (même quand FL est devant).
    init(link: OrganizerLink, audio: AudioSource, classify: @escaping Classify, timing: Timing = Timing(),
         sleep: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
         escape: @escaping () -> Bool = { false },
         progress: @escaping (Int, Int) -> Void = { _, _ in }) {
        self.link = link
        self.audio = audio
        self.classify = classify
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
    func run() -> Result<OrganizerResult, OrganizerError> {
        let page: OrganizerPage
        switch link.window {
        case .channelRack: page = .channelRack
        case .mixer: page = .mixer
        default: return .failure(.refused(1))
        }
        do {
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
            try pause(timing.listen)
            var samples = audio.take()
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
}
