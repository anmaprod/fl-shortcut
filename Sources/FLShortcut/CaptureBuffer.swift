// Organiser : tampon du son capté (mono, les dernières secondes seulement). Rempli depuis la file de Core Audio,
// lu par la session : protégé par un verrou. Jamais écrit sur le disque.
import Foundation

final class CaptureBuffer {
    let rate: Double
    let capacity: Int
    private var samples: [Float] = []
    private let lock = NSLock()

    init(rate: Double, seconds: Double) {
        self.rate = rate
        capacity = max(1, Int(rate * seconds))
        samples.reserveCapacity(capacity)
    }

    /// Canaux entrelacés (L R L R…) : moyenne des canaux.
    func appendInterleaved(_ data: UnsafePointer<Float>, frames: Int, channels: Int) {
        guard frames > 0, channels > 0 else { return }
        let scale = 1 / Float(channels)
        var mono = [Float](repeating: 0, count: frames)
        for f in 0..<frames {
            var sum: Float = 0
            for c in 0..<channels { sum += data[f * channels + c] }
            mono[f] = sum * scale
        }
        append(mono)
    }

    /// Un tampon par canal : moyenne des canaux.
    func appendPlanar(_ channels: [UnsafePointer<Float>], frames: Int) {
        guard frames > 0, !channels.isEmpty else { return }
        let scale = 1 / Float(channels.count)
        var mono = [Float](repeating: 0, count: frames)
        for ch in channels {
            for f in 0..<frames { mono[f] += ch[f] }
        }
        for f in 0..<frames { mono[f] *= scale }
        append(mono)
    }

    private func append(_ mono: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        samples.append(contentsOf: mono)
        if samples.count > capacity { samples.removeFirst(samples.count - capacity) }
        chunks += 1
        for v in mono where abs(v) > peak { peak = abs(v) }
    }

    /// Blocs reçus depuis la création, et la crête de tout ce qui a été reçu (diagnostic : rien n'est gardé).
    private var chunks = 0
    private var peak: Float = 0
    var received: (chunks: Int, peak: Float) {
        lock.lock()
        defer { lock.unlock() }
        return (chunks, peak)
    }

    /// Le son reçu depuis le dernier `reset` (les `capacity` derniers échantillons), puis le tampon est vidé.
    func take() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        let out = samples
        samples.removeAll(keepingCapacity: true)
        return out
    }

    func reset() {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}

/// Source du son à classer (la capture de FL ; un faux dans les tests).
protocol AudioSource: AnyObject {
    var rate: Double { get }
    func start() throws
    /// Oublie le son reçu jusqu'ici.
    func reset()
    /// Le son reçu depuis le dernier `reset`.
    func take() -> [Float]
    func stop()
    /// Ce que la capture a reçu, pour « Copier le diagnostic ».
    var stats: CaptureStats { get }
}

extension AudioSource {
    var stats: CaptureStats { CaptureStats() }
}

/// Diagnostic de la capture (aucun son, aucun nom) : de quoi savoir pourquoi l'Organiser n'entend rien.
struct CaptureStats: Equatable {
    /// « tap seul » (l'agrégat ne contient que le son de FL) ou « carte » (avec l'appareil de sortie).
    var mode = ""
    /// Blocs reçus, et la crête de tout le son reçu (dBFS).
    var chunks = 0
    var peakDB = -180.0
    /// Tampons d'entrée vus par la lecture, et le premier lu.
    var buffers = 0
    var used = 0
    /// Flux d'entrée de l'appareil de sortie de macOS (une carte son en a).
    var outputInputs = 0
    var rate = 0.0
    var tapChannels = 0
    var interleaved = true

    var text: String {
        "capture=\(mode.isEmpty ? "aucune" : mode) blocs=\(chunks) crête=\(Int(peakDB.rounded()))dB "
            + "tampons=\(buffers) lu=\(used) entrées-sortie=\(outputInputs) fréq=\(Int(rate)) "
            + "tap=\(tapChannels)ch\(interleaved ? "" : "-plan")"
    }
}
