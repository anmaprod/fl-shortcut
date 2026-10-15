// Organiser : les familles de sons et les règles qui fusionnent les mesures du son (SoundFeatures) et l'avis de l'IA
// de macOS (SoundAnalysis, sur le Mac). Règles réglées sur des sons de synthèse (prototype, puis test de la CI) ; elles
// tiennent même si l'IA se trompe (une montée de bruit reste FX, une nappe reste une mélodie).
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

    /// Ordre des familles dans le Channel rack une fois organisé, et dans l'aperçu.
    static let order: [SoundFamily] = [.drums, .bass, .melody, .vocals, .fx, .unsure]
    var rank: Int { Self.order.firstIndex(of: self) ?? Self.order.count }
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

    /// Étiquettes de l'IA de macOS (`SNClassifierIdentifier.version1`) → genre. Le test de la CI vérifie celles que
    /// macOS connaît ; une étiquette inconnue ne sert simplement jamais.
    static let labelTable: [String: LabelKind] = {
        var t: [String: LabelKind] = [:]
        for l in ["speech", "singing", "choir", "chant", "rapping", "humming", "yodeling", "whispering",
                  "male_singing", "female_singing", "child_singing", "synthetic_singing", "shout", "yell"] { t[l] = .voice }
        for l in ["drum", "drum_kit", "bass_drum", "snare_drum", "tabla", "timpani", "cymbal", "hi_hat",
                  "tambourine", "cowbell", "gong", "rimshot", "drum_roll", "percussion", "wood_block", "castanets",
                  "maraca", "bongo_drum", "conga_drum", "drum_machine", "clapping", "finger_snapping"] { t[l] = .drums }
        for l in ["music", "musical_instrument", "plucked_string_instrument", "guitar", "electric_guitar",
                  "acoustic_guitar", "bass_guitar", "steel_guitar_slide_guitar", "banjo", "sitar", "mandolin",
                  "ukulele", "zither", "keyboard_musical", "piano", "electric_piano", "organ", "electronic_organ",
                  "hammond_organ", "synthesizer", "harpsichord", "bowed_string_instrument", "string_section",
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
