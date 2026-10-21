// Organiser : l'IA de macOS qui reconnaît les sons (SoundAnalysis, `SNClassifierIdentifier.version1`, sur le Mac,
// sans internet). Créée pour une écoute et libérée avec elle : rien ne reste en mémoire au repos.
import AVFoundation
import Foundation
import SoundAnalysis

final class SoundClassifier {
    private let request: SNClassifySoundRequest

    init?() {
        guard let r = try? SNClassifySoundRequest(classifierIdentifier: .version1) else { return nil }
        if let window = Self.window(allowedBy: r.windowDurationConstraint) {
            r.windowDuration = CMTime(seconds: window, preferredTimescale: 48_000)
        }
        r.overlapFactor = 0.5
        request = r
    }

    /// Fenêtre d'analyse visée : 1 s. Celle de macOS par défaut (3 s sur macOS 26) dépasse les sons écoutés (1,5 à
    /// 3 s) : l'IA ne rendait aucun résultat (journal de la CI : « résultats 0, fenêtre 3.00 s ») et seules les
    /// mesures classaient (retour de l'utilisateur : un FX pris pour une voix).
    static let wantedWindow = 1.0

    /// La fenêtre que macOS permet la plus proche de `wantedWindow` (type 1 : durées permises ; 2 : intervalle).
    private static func window(allowedBy c: SNTimeDurationConstraint) -> Double? {
        if c.type.rawValue == 1 {
            return pickWindow(allowed: c.enumeratedDurations.map { $0.timeValue.seconds }, range: nil)
        }
        let low = c.durationRange.start.seconds, high = c.durationRange.end.seconds
        guard low.isFinite, high.isFinite, low > 0, low <= high else { return nil }
        return pickWindow(allowed: [], range: low...high)
    }

    /// Pur (testé) : dans l'intervalle permis, `wantedWindow` ramenée dedans ; sinon la durée permise la plus proche.
    static func pickWindow(allowed: [Double], range: ClosedRange<Double>?) -> Double? {
        if let range { return min(max(wantedWindow, range.lowerBound), range.upperBound) }
        let usable = allowed.filter { $0.isFinite && $0 > 0 }
        return usable.min { abs($0 - wantedWindow) < abs($1 - wantedWindow) }
    }

    /// Étiquettes que macOS connaît (pour le test de la table de FamilyFusion).
    var knownLabels: Set<String> { Set(request.knownClassifications) }

    /// Confiance la plus forte de chaque étiquette sur tout le son (fenêtres d'environ 1 s) ; vide si l'analyse
    /// échoue. Un son plus court qu'une fenêtre est complété de silence : il a toujours au moins un résultat.
    func scores(_ samples: [Float], rate: Double) -> [String: Double] {
        lastResults = 0
        let window = request.windowDuration.seconds
        let minimum = Int((window.isFinite && window > 0 ? window : Self.wantedWindow) * rate) + 1
        let count = max(samples.count, minimum)
        guard !samples.isEmpty, let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(count)),
              let channel = buffer.floatChannelData?[0] else { return [:] }
        buffer.frameLength = AVAudioFrameCount(count)
        samples.withUnsafeBufferPointer { src in channel.update(from: src.baseAddress!, count: samples.count) }
        if count > samples.count { (channel + samples.count).update(repeating: 0, count: count - samples.count) }
        let analyzer = SNAudioStreamAnalyzer(format: format)
        let collector = Collector()
        do {
            try analyzer.add(request, withObserver: collector)
        } catch {
            lastReport = "ajout refusé (\(type(of: error)))"
            return [:]
        }
        analyzer.analyze(buffer, atAudioFramePosition: 0)
        analyzer.completeAnalysis()
        let waited = collector.done.wait(timeout: .now() + 2)
        analyzer.removeAllRequests()
        lastReport = collector.report(timedOut: waited == .timedOut, window: request.windowDuration.seconds)
        lastResults = collector.results
        return collector.scores
    }

    /// Bilan de la dernière analyse (nombre de résultats, échec, attente) pour le journal de la CI ; aucun nom de son.
    private(set) var lastReport = ""
    /// Résultats rendus par l'IA à la dernière analyse (0 : elle n'a rien dit).
    private(set) var lastResults = 0
}

private final class Collector: NSObject, SNResultsObserving {
    let done = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var collected: [String: Double] = [:]

    var scores: [String: Double] {
        lock.lock()
        defer { lock.unlock() }
        return collected
    }

    private var produced = 0
    private var failure: String?
    private var best = 0.0

    var results: Int {
        lock.lock()
        defer { lock.unlock() }
        return produced
    }

    func report(timedOut: Bool, window: Double) -> String {
        lock.lock()
        defer { lock.unlock() }
        var text = "résultats \(produced), meilleure confiance \(String(format: "%.2f", best)), fenêtre \(String(format: "%.2f", window)) s"
        if let failure { text += ", échec : \(failure)" }
        if timedOut { text += ", attente dépassée" }
        return text
    }

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let r = result as? SNClassificationResult else { return }
        lock.lock()
        produced += 1
        for c in r.classifications {
            best = max(best, c.confidence)
            if c.confidence > 0.05 { collected[c.identifier] = max(collected[c.identifier] ?? 0, c.confidence) }
        }
        lock.unlock()
    }

    func request(_ request: SNRequest, didFailWithError error: Error) {
        lock.lock()
        failure = (error as NSError).localizedDescription
        lock.unlock()
        done.signal()
    }
    func requestDidComplete(_ request: SNRequest) { done.signal() }
}
