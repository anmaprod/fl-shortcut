// Organiser : l'IA de macOS qui reconnaît les sons (SoundAnalysis, `SNClassifierIdentifier.version1`, sur le Mac,
// sans internet). Créée pour une écoute et libérée avec elle : rien ne reste en mémoire au repos.
import AVFoundation
import Foundation
import SoundAnalysis

final class SoundClassifier {
    private let request: SNClassifySoundRequest

    init?() {
        guard let r = try? SNClassifySoundRequest(classifierIdentifier: .version1) else { return nil }
        request = r
    }

    /// Étiquettes que macOS connaît (pour le test de la table de FamilyFusion).
    var knownLabels: Set<String> { Set(request.knownClassifications) }

    /// Confiance la plus forte de chaque étiquette sur tout le son (fenêtres d'environ 1 s) ; vide si le son est
    /// trop court ou si l'analyse échoue.
    func scores(_ samples: [Float], rate: Double) -> [String: Double] {
        guard !samples.isEmpty, let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0] else { return [:] }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { src in channel.update(from: src.baseAddress!, count: samples.count) }
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
        return collector.scores
    }

    /// Bilan de la dernière analyse (nombre de résultats, échec, attente) pour le journal de la CI ; aucun nom de son.
    private(set) var lastReport = ""
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
