import XCTest
@testable import FLShortcut

/// Sons de synthèse (mêmes recettes que le prototype qui a réglé les règles), bruit pseudo-aléatoire fixe.
enum SynthSounds {
    static let rate = 48_000.0

    struct Noise {
        var state: UInt64 = 0x9E37_79B9_7F4A_7C15
        mutating func uniform() -> Double {
            state ^= state >> 12; state ^= state << 25; state ^= state >> 27
            return Double((state &* 2_685_821_657_736_338_717) >> 11) / Double(1 << 53)
        }
        mutating func gaussian() -> Double {
            let u = max(uniform(), 1e-12), v = uniform()
            return (-2 * log(u)).squareRoot() * cos(2 * Double.pi * v)
        }
    }

    static func count(_ d: Double) -> Int { Int(rate * d) }

    static func place(_ total: Double, _ events: [(Double, [Double])]) -> [Double] {
        var out = [Double](repeating: 0, count: count(total))
        for (start, sig) in events {
            let i = count(start)
            for k in 0..<min(sig.count, out.count - i) { out[i + k] += sig[k] }
        }
        return out
    }

    static func onePole(_ x: [Double], _ fc: Double) -> [Double] {
        let a = exp(-2 * Double.pi * fc / rate)
        var acc = 0.0
        return x.map { acc = (1 - a) * $0 + a * acc; return acc }
    }

    static func saw(_ f: Double, _ d: Double, maxHz: Double = 4000) -> [Double] {
        (0..<count(d)).map { i in
            let t = Double(i) / rate
            var v = 0.0, k = 1.0
            while k * f < maxHz { v += sin(2 * Double.pi * k * f * t) / k; k += 1 }
            return v * 0.5
        }
    }

    static func env(_ d: Double, attack: Double = 0.005, release: Double = 0.05) -> [Double] {
        let n = count(d), a = max(1, count(attack)), r = max(1, count(release))
        return (0..<n).map { i in
            var e = 1.0
            if i < a { e = Double(i) / Double(max(a - 1, 1)) }
            if i >= n - r { e *= Double(n - 1 - i) / Double(max(r - 1, 1)) }
            return e
        }
    }

    static func mul(_ a: [Double], _ b: [Double]) -> [Double] { zip(a, b).map(*) }

    static func kick() -> [Double] {
        var phase = 0.0
        let hit: [Double] = (0..<count(0.4)).map { i in
            let t = Double(i) / rate
            phase += 2 * Double.pi * (50 + 100 * exp(-t / 0.03)) / rate
            return sin(phase) * exp(-t / 0.12)
        }
        return place(2, [0, 0.5, 1, 1.5].map { ($0, hit) })
    }

    static func snare(_ noise: inout Noise) -> [Double] {
        let hit: [Double] = (0..<count(0.3)).map { i in
            let t = Double(i) / rate
            let rattle: Double = noise.gaussian() * exp(-t / 0.08) * 0.5
            let body: Double = 0.4 * sin(2 * Double.pi * 180 * t) * exp(-t / 0.05)
            return rattle + body
        }
        return place(2, [(0.5, hit), (1.5, hit)])
    }

    static func hat(_ noise: inout Noise) -> [Double] {
        var previous = noise.gaussian()
        let hit: [Double] = (0..<count(0.12)).map { i in
            let t = Double(i) / rate
            let next = noise.gaussian()
            defer { previous = next }
            return (next - previous) * exp(-t / 0.02) * 0.3
        }
        return place(2, (0..<8).map { (Double($0) * 0.25, hit) })
    }

    static func b808() -> [Double] {
        func note(_ f: Double) -> [Double] {
            (0..<count(0.95)).map { i in
                let t = Double(i) / rate
                return tanh(1.5 * sin(2 * Double.pi * f * t) * exp(-t / 0.6)) * 0.8
            }
        }
        return place(2, [(0, note(49)), (1, note(55))])
    }

    static func bass() -> [Double] {
        let notes: [Double] = [55, 65.4, 73.4, 49]
        return place(2, notes.enumerated().map { i, f -> (Double, [Double]) in
            (Double(i) * 0.5, mul(onePole(saw(f, 0.45), 400), env(0.45)).map { $0 * 1.5 })
        })
    }

    static func lead() -> [Double] {
        let notes: [Double] = [440, 523.3, 587.3, 659.3]
        return place(2, notes.enumerated().map { i, f -> (Double, [Double]) in
            (Double(i) * 0.5, mul(saw(f, 0.45), env(0.45)).map { $0 * 0.6 })
        })
    }

    static func pad() -> [Double] {
        let a = saw(220, 2, maxHz: 3000), b = saw(277.2, 2, maxHz: 3000), c = saw(329.6, 2, maxHz: 3000)
        let sum = (0..<a.count).map { (a[$0] + b[$0] + c[$0]) * 0.3 }
        return mul(onePole(sum, 2000), env(2, attack: 0.3, release: 0.3))
    }

    static func riser(_ noise: inout Noise) -> [Double] {
        let n = count(2)
        var acc = 0.0
        return (0..<n).map { i in
            let fc = 500 + 7500 * Double(i) / Double(n)
            let a = exp(-2 * Double.pi * fc / rate)
            acc = (1 - a) * noise.gaussian() + a * acc
            return acc * Double(i) / Double(n - 1) * 0.8
        }
    }

    static func voice() -> [Double] {
        let n = count(1.6)
        var phase = 0.0, last = 0.0
        var pulses = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let t = Double(i) / rate
            phase += 150 * pow(2, 0.4 * sin(2 * Double.pi * 5.5 * t) / 12) / rate
            pulses[i] = floor(phase) > floor(last) ? 1 : 0
            last = phase
        }
        func resonator(_ f: Double, _ bw: Double) -> [Double] {
            let r = exp(-Double.pi * bw / rate), c1 = 2 * r * cos(2 * Double.pi * f / rate), c2 = -r * r
            var y1 = 0.0, y2 = 0.0
            return pulses.map { x in
                let v = x + c1 * y1 + c2 * y2
                y2 = y1
                y1 = v
                return v
            }
        }
        let a = resonator(700, 110), b = resonator(1220, 120), c = resonator(2600, 160)
        let mix = (0..<n).map { a[$0] + 0.6 * b[$0] + 0.25 * c[$0] }
        let peak = mix.map { abs($0) }.max() ?? 1
        return mul(mix.map { $0 / peak * 0.7 }, env(1.6, attack: 0.05, release: 0.15))
    }

    /// Les 9 sons et leur famille attendue.
    static func all() -> [(name: String, samples: [Float], expected: SoundFamily)] {
        var noise = Noise()
        let snareSound = snare(&noise)
        let hatSound = hat(&noise)
        let riserSound = riser(&noise)
        let list: [(String, [Double], SoundFamily)] = [
            ("kick", kick(), .drums), ("snare", snareSound, .drums), ("hat", hatSound, .drums),
            ("808", b808(), .bass), ("bass", bass(), .bass), ("lead", lead(), .melody), ("pad", pad(), .melody),
            ("riser", riserSound, .fx), ("voice", voice(), .vocals),
        ]
        return list.map { ($0.0, $0.1.map(Float.init), $0.2) }
    }
}

final class SoundClassificationTests: XCTestCase {
    private func sine(_ f: Double, _ d: Double) -> [Float] {
        let step: Double = 2 * Double.pi * f / 48_000
        return (0..<Int(48_000 * d)).map { i -> Float in
            let v: Double = 0.5 * sin(step * Double(i))
            return Float(v)
        }
    }

    func testFeaturesOfSine() {
        let f = SoundFeatures.measure(sine(220, 1), rate: 48_000)
        XCTAssertEqual(f.medianF0, 220, accuracy: 220 * 0.02)
        XCTAssertGreaterThanOrEqual(f.pitchedFraction, 0.9)
        XCTAssertLessThan(f.flatness, 0.05)
        let low = SoundFeatures.measure(sine(55, 1), rate: 48_000)
        XCTAssertEqual(low.medianF0, 55, accuracy: 55 * 0.02)
        XCTAssertGreaterThan(low.lowRatio, 0.9)
    }

    func testFeaturesOfNoise() {
        var noise = SynthSounds.Noise()
        let x = (0..<48_000).map { _ in Float(noise.gaussian() * 0.3) }
        let f = SoundFeatures.measure(x, rate: 48_000)
        XCTAssertGreaterThan(f.flatness, 0.3)
        XCTAssertLessThan(f.pitchedFraction, 0.2)
    }

    func testSilenceIsUnsure() {
        let quiet = [Float](repeating: 0.000_1, count: 48_000)
        let f = SoundFeatures.measure(quiet, rate: 48_000)
        XCTAssertLessThan(f.peakDB, FamilyFusion.silenceDB)
        XCTAssertEqual(FamilyFusion.decide(f, .none).family, .unsure)
        XCTAssertEqual(FamilyFusion.decide(SoundFeatures.measure([], rate: 48_000), .none).family, .unsure)
    }

    /// Une mesure par règle, dans l'ordre.
    func testFusionRules() {
        func f(len: Double, pitched: Double, f0: Double, low: Double, flat: Double, distinct: Int = 1,
               vib: Double = 0) -> SoundFeatures {
            SoundFeatures(peakDB: -6, noteLength: len, pitchedFraction: pitched, medianF0: f0, lowRatio: low,
                          flatness: flat, onsetsPerSecond: 2, distinctPitches: distinct, vibrato: vib)
        }
        XCTAssertEqual(FamilyFusion.decide(f(len: 1, pitched: 1, f0: 150, low: 0, flat: 0), AILabels(voice: 0.8)).family, .vocals)
        XCTAssertEqual(FamilyFusion.decide(f(len: 0.9, pitched: 1, f0: 50, low: 0.9, flat: 0), .none).family, .bass)       // 808
        XCTAssertEqual(FamilyFusion.decide(f(len: 0.2, pitched: 1, f0: 60, low: 0.9, flat: 0, distinct: 4), .none).family, .bass)  // basse pincée
        XCTAssertEqual(FamilyFusion.decide(f(len: 0.3, pitched: 0.9, f0: 50, low: 1, flat: 0), .none).family, .drums)      // kick
        XCTAssertEqual(FamilyFusion.decide(f(len: 0.1, pitched: 0, f0: 0, low: 0, flat: 0.3), .none).family, .drums)       // charleston
        XCTAssertEqual(FamilyFusion.decide(f(len: 2, pitched: 0, f0: 0, low: 0, flat: 0.45), AILabels(instrument: 0.9)).family, .fx)
        XCTAssertEqual(FamilyFusion.decide(f(len: 1.5, pitched: 1, f0: 150, low: 0, flat: 0, vib: 0.3), .none).family, .vocals)
        XCTAssertEqual(FamilyFusion.decide(f(len: 0.45, pitched: 1, f0: 440, low: 0, flat: 0), AILabels(drums: 0.7)).family, .melody)
        XCTAssertEqual(FamilyFusion.decide(f(len: 2, pitched: 0.2, f0: 220, low: 0, flat: 0.1), .none).family, .melody)    // nappe
        XCTAssertEqual(FamilyFusion.decide(f(len: 2, pitched: 0.2, f0: 0, low: 0, flat: 0.2), .none).family, .fx)
        XCTAssertEqual(FamilyFusion.decide(f(len: 0.2, pitched: 0.4, f0: 300, low: 0, flat: 0.2), .none).family, .unsure)
    }

    private func table(_ rows: [(String, SoundFamily, SoundFamily, String)]) -> Int {
        var ok = 0
        for (name, got, expected, detail) in rows {
            if got == expected { ok += 1 }
            print("ORGANISER: \(name.padding(toLength: 6, withPad: " ", startingAt: 0)) \(got == expected ? "ok " : "NON") \(got.label) (attendu \(expected.label)) \(detail)")
        }
        return ok
    }

    /// Mesures seules (sans l'IA) : le réglage du prototype, 9 sur 9.
    func testSynthSoundsByFeatures() {
        var rows: [(String, SoundFamily, SoundFamily, String)] = []
        for s in SynthSounds.all() {
            let f = SoundFeatures.measure(s.samples, rate: SynthSounds.rate)
            let detail = String(format: "len=%.2f pitched=%.2f f0=%.0f low=%.2f flat=%.3f distinct=%d vib=%.2f",
                                f.noteLength, f.pitchedFraction, f.medianF0, f.lowRatio, f.flatness, f.distinctPitches, f.vibrato)
            rows.append((s.name, FamilyFusion.decide(f, .none).family, s.expected, detail))
        }
        XCTAssertGreaterThanOrEqual(table(rows), 8)
    }

    /// Classement complet (mesures + IA de macOS) : au moins 8 sur 9 ; le tableau part dans le journal de la CI.
    func testSynthSoundsClassified() throws {
        guard let ai = SoundClassifier() else { throw XCTSkip("SoundAnalysis indisponible sur cette machine") }
        let sounds = SynthSounds.all()
        var rows: [(String, SoundFamily, SoundFamily, String)] = []
        let start = Date()
        for s in sounds {
            let f = SoundFeatures.measure(s.samples, rate: SynthSounds.rate)
            let scores = ai.scores(s.samples, rate: SynthSounds.rate)
            let top = scores.sorted { $0.value > $1.value }.prefix(3).map { "\($0.key) \(String(format: "%.2f", $0.value))" }
            let detail = "IA : " + top.joined(separator: ", ") + " (" + ai.lastReport + ")"
            rows.append((s.name, FamilyFusion.decide(f, AILabels(scores: scores)).family, s.expected, detail))
        }
        let perSound = Date().timeIntervalSince(start) / Double(sounds.count)
        print("ORGANISER: classement complet \(String(format: "%.0f", perSound * 1000)) ms par son")
        XCTAssertGreaterThanOrEqual(table(rows), 8)
        XCTAssertLessThan(perSound, 0.5)
    }

    /// Étiquettes de la table connues de macOS : les principales doivent y être ; les autres sont listées.
    func testLabelTableIsKnown() throws {
        guard let ai = SoundClassifier() else { throw XCTSkip("SoundAnalysis indisponible sur cette machine") }
        let known = ai.knownLabels
        let unknown = FamilyFusion.labelTable.keys.filter { !known.contains($0) }.sorted()
        print("ORGANISER: \(known.count) étiquettes connues ; absentes de macOS : \(unknown.joined(separator: ", "))")
        for core in ["speech", "singing", "guitar", "piano", "drum"] {
            XCTAssertTrue(known.contains(core), core)
        }
        XCTAssertEqual(unknown, [], "toute la table est connue de macOS")
        XCTAssertGreaterThanOrEqual(FamilyFusion.labelTable.count, 60)
    }
}
