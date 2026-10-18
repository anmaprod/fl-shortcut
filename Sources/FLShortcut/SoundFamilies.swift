// Organiser : les familles de sons (et la sorte des drums, pour nommer les pistes de la Playlist) et les règles qui
// fusionnent les mesures du son (SoundFeatures) et l'avis de l'IA de macOS (SoundAnalysis, sur le Mac). Règles
// réglées sur des sons de synthèse (prototype, puis test de la CI) ; elles tiennent même si l'IA se trompe (une montée
// de bruit reste FX, une nappe reste une mélodie).
import Foundation

enum SoundFamily: String, CaseIterable, Codable {
    case drums, bass, melody, vocals, fx, unsure

    var label: String {
        switch self {
        case .drums: return "Drums"
        case .bass: return "Basse"
        case .melody: return "Mélodies"
        case .vocals: return "Voix"
        case .fx: return "FX"
        case .unsure: return "À vérifier"
        }
    }

    var symbol: String {
        switch self {
        case .drums: return "circle.circle"
        case .bass: return "waveform.path"
        case .melody: return "pianokeys"
        case .vocals: return "mic"
        case .fx: return "sparkles"
        case .unsure: return "questionmark.circle"
        }
    }

    /// Nom d'une piste de la Playlist renommée (drums : leur sorte, voir `DrumKind`).
    var trackName: String? {
        switch self {
        case .drums: return "Drums"
        case .bass: return "Basse"
        case .melody: return "Mélodie"
        case .vocals: return "Voix"
        case .fx: return "FX"
        case .unsure: return nil
        }
    }

    /// Ordre des familles (choisi par l'utilisateur) : dans le Channel rack une fois organisé, et dans l'aperçu.
    static let order: [SoundFamily] = [.vocals, .melody, .bass, .drums, .fx, .unsure]
    var rank: Int { Self.order.firstIndex(of: self) ?? Self.order.count }
}

/// Sorte d'un son de drums : le nom d'une piste de la Playlist renommée.
enum DrumKind: String, CaseIterable, Codable {
    case kick, snare, hiHat, clap, cymbal, perc, kit

    var name: String {
        switch self {
        case .kick: return "Kick"
        case .snare: return "Snare"
        case .hiHat: return "Hi-hat"
        case .clap: return "Clap"
        case .cymbal: return "Cymbal"
        case .perc: return "Perc"
        case .kit: return "Drums"
        }
    }
}

enum DrumNaming {
    /// Étiquettes de l'IA de macOS → sorte de drums (toutes dans `FamilyFusion.labelTable`).
    static let labels: [String: DrumKind] = [
        "bass_drum": .kick, "snare_drum": .snare, "hi_hat": .hiHat, "clapping": .clap, "finger_snapping": .clap,
        "cymbal": .cymbal, "gong": .cymbal, "tambourine": .perc, "cowbell": .perc, "tabla": .perc, "timpani": .perc,
        "percussion": .perc, "drum_kit": .kit, "drum": .kit,
    ]
    /// Confiance de l'IA à partir de laquelle son étiquette l'emporte sur les mesures.
    static let minConfidence = 0.3

    /// L'étiquette de l'IA la plus sûre (égalité : l'ordre de `DrumKind`), sinon les mesures : grave → kick ; bruit
    /// aigu → hi-hat (long : cymbale) ; bruit médium → snare ; le reste → perc.
    static func kind(_ f: SoundFeatures, scores: [String: Double]) -> DrumKind {
        var best: (kind: DrumKind, confidence: Double)?
        for (label, confidence) in scores {
            guard let kind = labels[label], confidence >= minConfidence else { continue }
            let rank = DrumKind.allCases.firstIndex(of: kind) ?? 0
            if let b = best, b.confidence > confidence
                || (b.confidence == confidence && (DrumKind.allCases.firstIndex(of: b.kind) ?? 0) <= rank) { continue }
            best = (kind, confidence)
        }
        if let best { return best.kind }
        if f.lowRatio >= 0.5 || (f.medianF0 > 0 && f.medianF0 < FamilyFusion.lowF0 && f.pitchedFraction >= 0.3) {
            return .kick
        }
        if f.flatness >= 0.4 && f.lowRatio < 0.1 { return f.noteLength >= 0.6 ? .cymbal : .hiHat }
        if f.flatness >= 0.2 { return .snare }
        return .perc
    }
}

/// Avis de l'IA de macOS, ramené à trois familles d'étiquettes (confiance 0…1, la plus forte de chaque famille).
struct AILabels: Equatable {
    var voice = 0.0
    var drums = 0.0
    var instrument = 0.0

    static let none = AILabels()

    init(voice: Double = 0, drums: Double = 0, instrument: Double = 0) {
        self.voice = voice
        self.drums = drums
        self.instrument = instrument
    }

    /// Depuis les scores de SoundAnalysis (étiquette → confiance) ; les étiquettes hors table sont ignorées.
    init(scores: [String: Double]) {
        for (label, confidence) in scores {
            switch FamilyFusion.labelTable[label] {
            case .voice?: voice = max(voice, confidence)
            case .drums?: drums = max(drums, confidence)
            case .instrument?: instrument = max(instrument, confidence)
            case nil: break
            }
        }
    }
}

enum FamilyFusion {
    enum LabelKind { case voice, drums, instrument }

    /// Étiquettes de l'IA de macOS (`SNClassifierIdentifier.version1`) → genre, toutes connues de macOS (vérifié par
    /// la CI : 303 étiquettes sur macOS 26).
    static let labelTable: [String: LabelKind] = {
        var t: [String: LabelKind] = [:]
        for l in ["speech", "singing", "rapping", "humming", "yodeling", "whispering", "shout", "yell"] { t[l] = .voice }
        for l in ["drum", "drum_kit", "bass_drum", "snare_drum", "tabla", "timpani", "cymbal", "hi_hat",
                  "tambourine", "cowbell", "gong", "percussion", "clapping", "finger_snapping"] { t[l] = .drums }
        for l in ["music", "plucked_string_instrument", "guitar", "electric_guitar",
                  "acoustic_guitar", "bass_guitar", "steel_guitar_slide_guitar", "banjo", "sitar", "mandolin",
                  "ukulele", "zither", "keyboard_musical", "piano", "electric_piano", "organ", "electronic_organ",
                  "hammond_organ", "synthesizer", "harpsichord", "bowed_string_instrument",
                  "violin_fiddle", "cello", "double_bass", "harp", "wind_instrument", "brass_instrument",
                  "french_horn", "trumpet", "trombone", "flute", "saxophone", "clarinet", "oboe", "bassoon",
                  "harmonica", "accordion", "bagpipes", "marimba_xylophone", "glockenspiel", "vibraphone",
                  "steelpan", "bell", "church_bell", "chime", "wind_chime", "orchestra", "theremin"] { t[l] = .instrument }
        return t
    }()

    /// Seuils (secondes, Hz, 0…1) : les mêmes que le prototype.
    static let silenceDB = -50.0
    static let lowF0 = 130.0
    static let shortNote = 0.4

    /// Famille et confiance (0…1). Dans l'ordre : silence → voix reconnue → basse (grave, tonale, longue ou qui
    /// change de note) → drums (court sans hauteur, ou grave court sur une seule note : kick) → FX (long et bruité)
    /// → voix au vibrato (sans instrument reconnu) → mélodie (tonale) → FX (long) → à vérifier.
    static func decide(_ f: SoundFeatures, _ ai: AILabels) -> (family: SoundFamily, confidence: Double) {
        guard f.peakDB >= silenceDB else { return (.unsure, 0) }
        if ai.voice >= 0.5 { return (.vocals, ai.voice) }
        let low = f.pitchedFraction >= 0.4 && f.medianF0 > 0 && f.medianF0 < lowF0 && f.lowRatio >= 0.5
        if low && (f.noteLength >= 0.35 || f.distinctPitches >= 2) { return (.bass, 0.8) }
        let short = f.noteLength < shortNote
        if (short && (f.pitchedFraction < 0.3 || ai.drums >= 0.6)) || (low && f.noteLength < 0.35) {
            return (.drums, max(ai.drums, 0.75))
        }
        if !short && f.pitchedFraction < 0.3 && f.flatness >= 0.25 { return (.fx, 0.7) }
        if (0.12...0.8).contains(f.vibrato) && (80...500).contains(f.medianF0) && f.pitchedFraction >= 0.6
            && f.noteLength >= 0.5 && ai.instrument < 0.5 {
            return (.vocals, 0.55)
        }
        if f.pitchedFraction >= 0.5 || ai.instrument >= 0.5 || (f.flatness < 0.15 && f.noteLength >= 0.3) {
            return (.melody, max(ai.instrument, 0.7))
        }
        if !short { return (.fx, 0.5) }
        return (.unsure, 0.3)
    }
}
