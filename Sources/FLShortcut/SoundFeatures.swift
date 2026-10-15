// Organiser : mesures d'un son capté (mono, Float), même calcul que le prototype qui a réglé les règles :
// enveloppe sur 40 ms (pas de 10 ms), attaques, longueur des notes, hauteur par autocorrélation normalisée (signal
// ramené au quart, 40 à 1 000 Hz), hauteur de chaque note, vibrato, part d'énergie sous 200 Hz et platitude du spectre
// (FFT de 4 096 points). Quelques millisecondes par son ; rien n'est gardé.
import Accelerate
import Foundation

struct SoundFeatures: Equatable {
    var peakDB: Double
    /// Longueur moyenne d'une note (s) : de son attaque à −20 dB de son sommet (ou à la note suivante).
    var noteLength: Double
    /// Part des trames où une hauteur nette est trouvée (0…1).
    var pitchedFraction: Double
    var medianF0: Double
    /// Part d'énergie sous 200 Hz (0…1).
    var lowRatio: Double
    /// Platitude du spectre de 100 Hz à 8 kHz : 0 tonal, 1 bruit blanc.
    var flatness: Double
    var onsetsPerSecond: Double
    /// Nombre de hauteurs différentes d'une note à l'autre (demi-tons).
    var distinctPitches: Int
    /// Écart type des demi-tons autour de leur médiane glissante, dans les passages tenus.
    var vibrato: Double

    static let silent = SoundFeatures(peakDB: -120, noteLength: 0, pitchedFraction: 0, medianF0: 0, lowRatio: 0,
                                      flatness: 1, onsetsPerSecond: 0, distinctPitches: 0, vibrato: 0)

    static func measure(_ samples: [Float], rate: Double) -> SoundFeatures {
        guard rate >= 8_000, !samples.isEmpty else { return .silent }
        var peak: Float = 0
        vDSP_maxmgv(samples, 1, &peak, vDSP_Length(samples.count))
        let peakDB = 20 * log10(max(Double(peak), 1e-9))
        guard peakDB >= FamilyFusion.silenceDB, Double(samples.count) >= rate * 0.05 else {
            var f = SoundFeatures.silent
            f.peakDB = peakDB
            return f
        }

        // Enveloppe : énergie par tranche de 10 ms, moyennée sur 40 ms.
        let hop = Int(rate * 0.01)
        let n = samples.count / hop
        var energy = [Double](repeating: 0, count: n)
        samples.withUnsafeBufferPointer { p in
            for k in 0..<n {
                var e: Float = 0
                vDSP_measqv(p.baseAddress! + k * hop, 1, &e, vDSP_Length(hop))
                energy[k] = Double(e)
            }
        }
        var db = [Double](repeating: -180, count: n)
        for k in 0..<n {
            let lo = max(0, k - 2), hi = min(n, k + 2)
            let mean = energy[lo..<hi].reduce(0, +) / Double(hi - lo)
            db[k] = 20 * log10(mean.squareRoot() + 1e-9)
        }
        let top = db.max() ?? -180
        let activeFloor = max(top - 40, -60)
        let active = db.map { $0 > activeFloor }

        // Attaques : +6 dB sur les 30 ms d'avant, assez fortes, 50 ms d'écart au moins.
        var onsets: [Int] = []
        for k in 0..<n {
            let lo = k > 0 ? db[max(0, k - 3)..<k].min()! : -120
            if db[k] - lo > 6, db[k] > top - 30, onsets.last.map({ k - $0 >= 5 }) ?? true { onsets.append(k) }
        }
        var lengths: [Int] = []
        for (j, k) in onsets.enumerated() {
            let end = j + 1 < onsets.count ? onsets[j + 1] : n
            let local = db[k..<min(k + 6, end)].max() ?? db[k]
            var m = k
            while m < end && db[m] > local - 20 { m += 1 }
            lengths.append(m - k)
        }
        let noteLength = lengths.isEmpty ? Double(active.filter { $0 }.count) * 0.01
                                         : Double(lengths.reduce(0, +)) / Double(lengths.count) * 0.01

        // Hauteur : signal ramené au quart (moyenne de 4 échantillons), trames de 1 024 au pas de 512.
        let d = 4
        let rd = rate / Double(d)
        var y = [Float](repeating: 0, count: samples.count / d)
        for i in 0..<y.count {
            y[i] = (samples[i * d] + samples[i * d + 1] + samples[i * d + 2] + samples[i * d + 3]) / 4
        }
        let frameN = 1024, frameH = 512
        let lmin = Int(rd / 1000), lmax = Int(rd / 40)
        var starts: [Int] = []
        if y.count >= frameN { starts = Array(stride(from: 0, through: y.count - frameN, by: frameH)) }
        var frameDB: [Double] = []
        y.withUnsafeBufferPointer { p in
            for s in starts {
                var e: Float = 0
                vDSP_measqv(p.baseAddress! + s, 1, &e, vDSP_Length(frameN))
                frameDB.append(20 * log10(Double(e).squareRoot() + 1e-9))
            }
        }
        let yTop = frameDB.max() ?? -120
        var chosen = zip(starts, frameDB).filter { $0.1 > yTop - 25 }.map { $0.0 }
        if chosen.count > 48 {
            chosen = (0..<48).map { chosen[Int((Double($0) * Double(chosen.count - 1) / 47).rounded())] }
        }
        var f0s: [Double] = []
        var seq: [(f0: Double, pos: Int)] = []
        y.withUnsafeBufferPointer { p in
            var nacf = [Double](repeating: 0, count: lmax + 2)
            var cumulative = [Double](repeating: 0, count: frameN + 1)
            for s in chosen {
                let w = p.baseAddress! + s
                for i in 0..<frameN { cumulative[i + 1] = cumulative[i] + Double(w[i]) * Double(w[i]) }
                for lag in lmin...lmax {
                    var dot: Float = 0
                    vDSP_dotpr(w, 1, w + lag, 1, &dot, vDSP_Length(frameN - lag))
                    let e0 = cumulative[frameN - lag], eL = cumulative[frameN] - cumulative[lag]
                    nacf[lag] = Double(dot) / ((e0 * eL).squareRoot() + 1e-12)
                }
                let pos = Int((Double(s) + Double(frameN) / 2) * Double(d) / Double(hop))
                let best = nacf[lmin...lmax].max() ?? 0
                guard best >= 0.75 else {
                    seq.append((f0: 0, pos: pos))
                    continue
                }
                // Plus petit retard qui atteint 92 % du meilleur et qui est un sommet (évite les sous-octaves).
                let lag = (lmin + 1..<lmax).first {
                    nacf[$0] >= 0.92 * best && nacf[$0] >= nacf[$0 - 1] && nacf[$0] >= nacf[$0 + 1]
                } ?? (lmin...lmax).max { nacf[$0] < nacf[$1] }!
                var exact = Double(lag)
                if lag > lmin && lag < lmax {
                    let a = nacf[lag - 1], b = nacf[lag], c = nacf[lag + 1]
                    let den = a - 2 * b + c
                    let off = abs(den) > 1e-12 ? 0.5 * (a - c) / den : 0
                    exact += max(-0.5, min(0.5, off))
                }
                f0s.append(rd / exact)
                seq.append((f0: rd / exact, pos: pos))
            }
        }
        let pitchedFraction = chosen.isEmpty ? 0 : Double(f0s.count) / Double(chosen.count)
        let medianF0 = median(f0s) ?? 0

        // Hauteur de chaque note (médiane de ses trames tonales) : un kick qui glisse garde une seule hauteur.
        var distinct = 0
        var vibrato = 0.0
        if !f0s.isEmpty {
            let bounds = (onsets.isEmpty ? [0] : onsets) + [n]
            var notes = Set<Int>()
            for j in 0..<(bounds.count - 1) {
                let values = seq.filter { $0.f0 > 0 && bounds[j] <= $0.pos && $0.pos < bounds[j + 1] }.map(\.f0)
                if let m = median(values) { notes.insert(Int((12 * log2(m / 440)).rounded())) }
            }
            distinct = notes.count
            // Vibrato : demi-tons moins leur médiane glissante (5 trames), dans les suites de 5 trames tonales ou plus.
            var residuals: [Double] = []
            var run: [Double] = []
            for item in seq + [(f0: 0, pos: 0)] {
                if item.f0 > 0 {
                    run.append(12 * log2(item.f0 / 440))
                    continue
                }
                if run.count >= 5 {
                    for i in run.indices {
                        let local = median(Array(run[max(0, i - 2)..<min(run.count, i + 3)])) ?? run[i]
                        let r = run[i] - local
                        if abs(r) <= 1.5 { residuals.append(r) }      // changements de note et erreurs d'octave à part
                    }
                }
                run = []
            }
            if residuals.count >= 5 {
                let mean = residuals.reduce(0, +) / Double(residuals.count)
                vibrato = (residuals.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(residuals.count)).squareRoot()
            }
        }

        // Spectre : trames de 4 096 (16 au plus) parmi les passages actifs.
        let (lowRatio, flatness) = spectrum(samples, rate: rate, active: active, hop: hop)

        return SoundFeatures(peakDB: peakDB, noteLength: noteLength, pitchedFraction: pitchedFraction,
                             medianF0: medianF0, lowRatio: lowRatio, flatness: flatness,
                             onsetsPerSecond: Double(onsets.count) / (Double(samples.count) / rate),
                             distinctPitches: distinct, vibrato: vibrato)
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let v = values.sorted()
        return v.count % 2 == 1 ? v[v.count / 2] : (v[v.count / 2 - 1] + v[v.count / 2]) / 2
    }

    private static func spectrum(_ x: [Float], rate: Double, active: [Bool], hop: Int) -> (low: Double, flatness: Double) {
        let m = 4096, log2n = vDSP_Length(12)
        guard x.count >= m, let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else { return (0, 1) }
        defer { vDSP_destroy_fftsetup(setup) }
        var starts = stride(from: 0, through: x.count - m, by: m).filter { s in
            let a = s / hop, b = min(active.count, (s + m) / hop)
            return a < b && active[a..<b].contains(true)
        }
        if starts.count > 16 {
            starts = (0..<16).map { starts[Int((Double($0) * Double(starts.count - 1) / 15).rounded())] }
        }
        guard !starts.isEmpty else { return (0, 1) }
        var window = [Float](repeating: 0, count: m)
        vDSP_hann_window(&window, vDSP_Length(m), Int32(vDSP_HANN_DENORM))
        var frame = [Float](repeating: 0, count: m)
        var real = [Float](repeating: 0, count: m / 2), imag = [Float](repeating: 0, count: m / 2)
        var power = [Double](repeating: 0, count: m / 2 + 1)
        let binHz = rate / Double(m)
        var lows: [Double] = [], flats: [Double] = []
        for s in starts {
            x.withUnsafeBufferPointer { p in vDSP_vmul(p.baseAddress! + s, 1, window, 1, &frame, 1, vDSP_Length(m)) }
            real.withUnsafeMutableBufferPointer { rp in
                imag.withUnsafeMutableBufferPointer { ip in
                    var split = DSPSplitComplex(realp: rp.baseAddress!, imagp: ip.baseAddress!)
                    frame.withUnsafeBytes { raw in
                        vDSP_ctoz(raw.bindMemory(to: DSPComplex.self).baseAddress!, 2, &split, 1, vDSP_Length(m / 2))
                    }
                    vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                }
            }
            power[0] = Double(real[0]) * Double(real[0])
            power[m / 2] = Double(imag[0]) * Double(imag[0])
            for k in 1..<(m / 2) { power[k] = Double(real[k]) * Double(real[k]) + Double(imag[k]) * Double(imag[k]) }
            var total = 1e-12, low = 0.0
            var logSum = 0.0, sum = 0.0, count = 0.0
            for k in 0...(m / 2) {
                let hz = Double(k) * binHz
                if hz >= 20 && hz <= 20_000 {
                    total += power[k]
                    if hz < 200 { low += power[k] }
                }
                if hz >= 100 && hz <= 8_000 {
                    let p = power[k] + 1e-12
                    logSum += log(p)
                    sum += p
                    count += 1
                }
            }
            lows.append(low / total)
            if count > 0 { flats.append(exp(logSum / count) / (sum / count)) }
        }
        let lowRatio = lows.reduce(0, +) / Double(lows.count)
        let flatness = flats.isEmpty ? 1 : flats.reduce(0, +) / Double(flats.count)
        return (lowRatio, flatness)
    }
}
