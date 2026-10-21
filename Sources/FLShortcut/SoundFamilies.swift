// Organiser : les familles de sons, ce qu'est chaque son d'après son nom (Kick, 808, Open Hat…) et les règles qui
// fusionnent les mesures du son (SoundFeatures) et l'avis de l'IA de macOS (SoundAnalysis, sur le Mac). Règles
// réglées sur des sons de synthèse (prototype, puis test de la CI) ; elles tiennent même si l'IA se trompe (une montée
// de bruit reste FX, une nappe reste une mélodie).
import Foundation

enum SoundFamily: String, CaseIterable, Codable {
    case drums, bass, melody, vocals, fx, unsure

    var label: String {
        switch self {
        case .drums: return String(localized: "Drums")
        case .bass: return String(localized: "Basse")
        case .melody: return String(localized: "Mélodies")
        case .vocals: return String(localized: "Voix")
        case .fx: return String(localized: "FX")
        case .unsure: return String(localized: "À vérifier")
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

    /// Nom d'une piste de la Playlist renommée quand ses sons ne disent pas tous la même chose (voir `SoundKind`).
    var trackName: String? {
        switch self {
        case .drums: return String(localized: "Drums")
        case .bass: return String(localized: "Basse")
        case .melody: return String(localized: "Mélodie")
        case .vocals: return String(localized: "Voix")
        case .fx: return String(localized: "FX")
        case .unsure: return nil
        }
    }

    /// Ordre des familles (choisi par l'utilisateur) : dans le Channel rack une fois organisé, et dans l'aperçu.
    static let order: [SoundFamily] = [.vocals, .melody, .bass, .drums, .fx, .unsure]
    var rank: Int { Self.order.firstIndex(of: self) ?? Self.order.count }

    /// Ce qu'un son de la famille peut être, dans l'ordre du Channel rack organisé.
    var kinds: [SoundKind] { SoundKind.allCases.filter { $0.family == self } }
}

/// Ce qu'est un son, d'après le mot de son nom qui le dit (« BEAM KICK » : Kick, « ZEBRA 808 » : 808, « ALTER OPEN
/// HAT » : Open Hat, « @MEH CLAP » : Clap) : montré dans l'aperçu et donné aux pistes de la Playlist renommées. Dans
/// une famille, le Channel rack organisé met ensemble les sons d'une même sorte, dans cet ordre. Chaque famille a
/// un mot général (« Drums », « Basse », « Voix »…) : un son qui n'en dit pas plus.
enum SoundKind: String, CaseIterable, Codable {
    case vocal, adlib, choir
    case lead, pluck, pad, keys, piano, synth, arp, chords, guitar, strings, bell, flute, brass, organ, melody
    case bass808, sub, reese, bass
    case kick, snare, clap, rim, snap, hiHat, openHat, perc, tom, shaker, crash, ride, cymbal, drums
    case riser, downlifter, impact, sweep, fx

    var family: SoundFamily {
        switch self {
        case .vocal, .adlib, .choir: return .vocals
        case .lead, .pluck, .pad, .keys, .piano, .synth, .arp, .chords, .guitar, .strings, .bell, .flute, .brass,
             .organ, .melody: return .melody
        case .bass808, .sub, .reese, .bass: return .bass
        case .kick, .snare, .clap, .rim, .snap, .hiHat, .openHat, .perc, .tom, .shaker, .crash, .ride, .cymbal,
             .drums: return .drums
        case .riser, .downlifter, .impact, .sweep, .fx: return .fx
        }
    }

    var name: String {
        switch self {
        case .vocal: return String(localized: "Voix")
        case .adlib: return String(localized: "Adlib")
        case .choir: return String(localized: "Chœur")
        case .lead: return String(localized: "Lead")
        case .pluck: return String(localized: "Pluck")
        case .pad: return String(localized: "Pad")
        case .keys: return String(localized: "Keys")
        case .piano: return String(localized: "Piano")
        case .synth: return String(localized: "Synth")
        case .arp: return String(localized: "Arp")
        case .chords: return String(localized: "Chords")
        case .guitar: return String(localized: "Guitare")
        case .strings: return String(localized: "Strings")
        case .bell: return String(localized: "Bell")
        case .flute: return String(localized: "Flûte")
        case .brass: return String(localized: "Brass")
        case .organ: return String(localized: "Orgue")
        case .melody: return String(localized: "Mélodie")
        case .bass808: return String(localized: "808")
        case .sub: return String(localized: "Sub")
        case .reese: return String(localized: "Reese")
        case .bass: return String(localized: "Basse")
        case .kick: return String(localized: "Kick")
        case .snare: return String(localized: "Snare")
        case .clap: return String(localized: "Clap")
        case .rim: return String(localized: "Rim")
        case .snap: return String(localized: "Snap")
        case .hiHat: return String(localized: "Hi-hat")
        case .openHat: return String(localized: "Open Hat")
        case .perc: return String(localized: "Perc")
        case .tom: return String(localized: "Tom")
        case .shaker: return String(localized: "Shaker")
        case .crash: return String(localized: "Crash")
        case .ride: return String(localized: "Ride")
        case .cymbal: return String(localized: "Cymbal")
        case .drums: return String(localized: "Drums")
        case .riser: return String(localized: "Riser")
        case .downlifter: return String(localized: "Downlifter")
        case .impact: return String(localized: "Impact")
        case .sweep: return String(localized: "Sweep")
        case .fx: return String(localized: "FX")
        }
    }

    /// Le mot général de sa famille (« Drums », « Basse », « Voix », « FX », « Mélodie ») : un mot précis l'emporte.
    var isGeneral: Bool { self == .vocal || self == .melody || self == .bass || self == .drums || self == .fx }

    var rank: Int { Self.allCases.firstIndex(of: self) ?? Self.allCases.count }

    /// Ordre dans le Channel rack organisé : celui des cas, sauf dans la basse : Basse, Reese, Sub, puis 808, juste
    /// avant les drums (retour de l'utilisateur : « Voix › Mélodie › Basse › 808 › Drums › FX »). `rank` reste
    /// l'ordre de préférence d'un mot dans un nom (« 808 Sub » : 808).
    var rackRank: Int { Self.rackOrder.firstIndex(of: self) ?? Self.rackOrder.count }
    static let rackOrder: [SoundKind] = allCases.filter { $0.family != .bass } + [.bass, .reese, .sub, .bass808]

    /// Le bus du Mixer où va un son de cette sorte : celui de sa famille, sauf les 808 avec les drums (retour de
    /// l'utilisateur : « Drums (avec les 808 dedans, pas les Bass) »).
    var busFamily: SoundFamily { self == .bass808 ? .drums : family }
}

/// Sorte d'un son de drums reconnue à l'écoute (pas de nom qui la dise).
enum DrumKind: String, CaseIterable, Codable {
    case kick, snare, hiHat, clap, cymbal, perc, kit

    var name: String { sound.name }

    var sound: SoundKind {
        switch self {
        case .kick: return .kick
        case .snare: return .snare
        case .hiHat: return .hiHat
        case .clap: return .clap
        case .cymbal: return .cymbal
        case .perc: return .perc
        case .kit: return .drums
        }
    }
}

/// Ce qu'est un son d'après son nom (« BEAM KICK », « ZEBRA 808 », « Vocal Chop ») : la plupart des sons de packs
/// le disent, rien n'est écouté pour eux. Mots entiers, sans casse ni accents (« Kick01 » compte comme « kick ») ;
/// nil si le nom ne dit rien (« Serum 2 », « Sampler »).
enum SoundNames {
    /// Mot → ce qu'est le son.
    static let kindWords: [String: SoundKind] = [
        "vox": .vocal, "vocal": .vocal, "vocals": .vocal, "voice": .vocal, "voix": .vocal, "acapella": .vocal,
        "chant": .vocal, "adlib": .adlib, "adlibs": .adlib, "choir": .choir, "choeur": .choir,
        "lead": .lead, "leads": .lead, "pluck": .pluck, "plucks": .pluck, "pad": .pad, "pads": .pad,
        "keys": .keys, "rhodes": .keys, "piano": .piano, "synth": .synth, "arp": .arp, "arpeggio": .arp,
        "chord": .chords, "chords": .chords, "guitar": .guitar, "guitare": .guitar, "gtr": .guitar,
        "string": .strings, "strings": .strings, "violin": .strings, "cello": .strings, "bell": .bell, "bells": .bell,
        "flute": .flute, "brass": .brass, "horn": .brass, "organ": .organ, "orgue": .organ, "melody": .melody,
        "melodie": .melody, "mel": .melody, "harp": .melody, "sax": .melody, "marimba": .melody, "kalimba": .melody,
        "808": .bass808, "808s": .bass808, "sub": .sub, "subbass": .sub, "reese": .reese, "bass": .bass,
        "basse": .bass,
        "kick": .kick, "kicks": .kick, "kck": .kick, "kik": .kick, "bd": .kick, "bassdrum": .kick,
        "snare": .snare, "snares": .snare, "snr": .snare, "sd": .snare, "clap": .clap, "claps": .clap, "clp": .clap,
        "rim": .rim, "rimshot": .rim, "snap": .snap, "snaps": .snap,
        "hat": .hiHat, "hats": .hiHat, "hihat": .hiHat, "hihats": .hiHat, "hh": .hiHat, "chh": .hiHat,
        "closedhat": .hiHat, "oh": .openHat, "ohh": .openHat, "openhat": .openHat, "openhats": .openHat,
        "perc": .perc, "percs": .perc, "percussion": .perc, "conga": .perc, "bongo": .perc, "cowbell": .perc,
        "clave": .perc, "tom": .tom, "toms": .tom, "shaker": .shaker, "tamb": .shaker, "tambourine": .shaker,
        "crash": .crash, "ride": .ride, "cymbal": .cymbal, "cym": .cymbal, "splash": .cymbal, "china": .cymbal,
        "drum": .drums, "drums": .drums, "drumloop": .drums, "breakbeat": .drums, "kit": .drums,
        "riser": .riser, "risers": .riser, "uplifter": .riser, "downlifter": .downlifter, "impact": .impact,
        "sweep": .sweep, "fx": .fx, "sfx": .fx, "whoosh": .fx, "noise": .fx, "transition": .fx, "reverse": .fx,
        "zap": .fx, "laser": .fx,
    ]
    /// Mots de charleston : précédés de « open » (« OPEN HAT »), c'est un Open Hat.
    static let hatWords: Set<String> = ["hat", "hats", "hihat", "hihats", "hh"]

    /// Mots du nom, sans casse ni accents ; un nombre collé à la fin d'un mot est retiré (« kick01 » → « kick »),
    /// sauf pour un mot qui n'est fait que de chiffres (« 808 »).
    static func words(_ name: String) -> [String] {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "fr_FR"))
        return folded.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map { part in
            var w = String(part)
            if w.contains(where: \.isLetter) {
                while let last = w.last, last.isNumber { w.removeLast() }
            }
            return w
        }
    }

    /// Ce que dit chaque mot du nom, dans l'ordre (« ALTER OPEN HAT » : Open Hat).
    static func kinds(in words: [String]) -> [SoundKind] {
        words.indices.compactMap { i -> SoundKind? in
            if hatWords.contains(words[i]), i > 0, words[i - 1] == "open" { return SoundKind.openHat }
            return kindWords[words[i]]
        }
    }

    /// La famille : un mot de drums précis (kick, hat…) l'emporte, sinon la première nommée dans l'ordre Voix,
    /// Basse, FX, Mélodies, Drums (« Synth Bass » : Basse ; « Vocal Chop » : Voix ; « 808 Kick » : Kick). Dans la
    /// famille, un mot précis passe avant le mot général, et le premier dans l'ordre de `SoundKind` l'emporte
    /// (« Sub 808 » : 808 ; « Adlib Vox » : Adlib).
    static func kind(of name: String) -> SoundKind? {
        let found = kinds(in: words(name))
        let named = Set(found.map { $0.family })
        let family: SoundFamily
        if found.contains(where: { $0.family == .drums && !$0.isGeneral }) {
            family = .drums
        } else if let first = [SoundFamily.vocals, .bass, .fx, .melody, .drums].first(where: { named.contains($0) }) {
            family = first
        } else {
            return nil
        }
        let mine = found.filter { $0.family == family }
        return mine.min { a, b in a.isGeneral != b.isGeneral ? !a.isGeneral : a.rank < b.rank }
    }

    static func family(of name: String) -> SoundFamily? {
        kind(of: name)?.family
    }

    /// Un nom que l'Organiser a pu donner : une sorte ou une famille (« Mélodie », « Snare », « Hi-hat »), suivie ou
    /// non d'un numéro (« Mélodie 3 »). Il ne dit rien de sûr : une analyse d'avant a pu se tromper (retour de
    /// l'utilisateur : une boucle de batterie restait « Mélodie 3 », un hi-hat « Snare 3 »).
    static func isGenerated(_ name: String) -> Bool {
        var base = name.trimmingCharacters(in: .whitespaces)
        if let space = base.lastIndex(of: " "), Int(base[base.index(after: space)...]) != nil {
            base = String(base[..<space])
        }
        return generatedNames.contains(base)
    }

    /// Noms que l'Organiser donne, dans la langue de l'appli.
    static var generatedNames: Set<String> {
        Set(SoundKind.allCases.map(\.name) + SoundFamily.allCases.compactMap(\.trackName))
    }

    /// Un nom que l'Organiser a pu donner (`kind`) reste après l'écoute s'il ne la contredit pas : même famille, et
    /// pas une autre sorte (« Lead » entendu comme une mélodie reste « Lead » ; « Snare 3 » entendu comme un hi-hat
    /// devient « Hi-hat »). L'écoute qui ne dit rien laisse le nom.
    static func keeps(_ kind: SoundKind, heard: Verdict) -> Bool {
        heard.family == .unsure || (heard.family == kind.family && (heard.kind == nil || heard.kind == kind))
    }

    /// Mots d'une partie du morceau : un pattern ou une piste ainsi nommés gardent leur nom.
    static let sectionWords: Set<String> = [
        "intro", "outro", "verse", "couplet", "chorus", "refrain", "hook", "drop", "bridge", "pont", "break",
        "breakdown", "build", "buildup", "interlude", "prechorus", "skit", "ending", "part", "partie", "section",
        "theme",
    ]

    /// Un nom choisi pour une partie du morceau (« Intro », « Refrain 2 ») qui ne dit pas ce qu'est le son : gardé.
    /// Tout autre nom (« Pattern 3 », « Serum 2 #3 », « hi hat », « Track 8 ») est remplacé par un nom simple.
    static func isSection(_ name: String) -> Bool {
        kind(of: name) == nil && words(name).contains(where: sectionWords.contains)
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

    /// Ce que les mesures disent sûrement l'emporte sur l'IA : le grave d'un kick avec des aigus (charleston) est une
    /// boucle de batterie ; presque tout au-dessus de 6 kHz, un charleston (retour de l'utilisateur : un hi-hat
    /// renommé « Snare 3 »). Sinon l'étiquette de l'IA la plus sûre (égalité : l'ordre de `DrumKind`), sinon les
    /// mesures : grave → kick ; aigu → hi-hat (long : cymbale) ; tonal → perc ; bruit sans grave ni aigu → clap ;
    /// bruit → snare ; le reste → perc.
    static func kind(_ f: SoundFeatures, scores: [String: Double]) -> DrumKind {
        let low = f.lowRatio >= 0.5 || (f.medianF0 > 0 && f.medianF0 < FamilyFusion.lowF0 && f.pitchedFraction >= 0.3)
        if low && f.highRatio >= FamilyFusion.loopHigh { return .kit }
        if f.highRatio >= sureHatHigh && f.flatness >= FamilyFusion.noisy { return f.noteLength >= cymbalLength ? .cymbal : .hiHat }
        var best: (kind: DrumKind, confidence: Double)?
        for (label, confidence) in scores {
            guard let kind = labels[label], confidence >= minConfidence else { continue }
            let rank = DrumKind.allCases.firstIndex(of: kind) ?? 0
            if let b = best, b.confidence > confidence
                || (b.confidence == confidence && (DrumKind.allCases.firstIndex(of: b.kind) ?? 0) <= rank) { continue }
            best = (kind, confidence)
        }
        if let best { return best.kind }
        if low { return .kick }
        if f.highRatio >= hatHigh { return f.noteLength >= cymbalLength ? .cymbal : .hiHat }
        if f.pitchedFraction >= 0.6 { return .perc }
        if f.flatness >= FamilyFusion.noisy {
            return f.highRatio < 0.05 && f.lowRatio < 0.05 ? .clap : .snare
        }
        return .perc
    }

    /// Part d'énergie au-dessus de 6 kHz : un charleston (une snare n'en a pas autant) ; au-delà de `sureHatHigh`,
    /// plus sûr que l'IA.
    static let hatHigh = 0.7
    static let sureHatHigh = 0.85
    /// Plus long (s) : une cymbale, plus court : un charleston (même ouvert).
    static let cymbalLength = 1.0
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

    /// Seuils (secondes, Hz, 0…1), réglés sur des sons de synthèse et des sons plus proches des vrais (réverbération,
    /// accords, bruits filtrés) avec le même calcul.
    static let silenceDB = -50.0
    static let lowF0 = 130.0
    static let shortNote = 0.4
    /// Platitude (`SoundFeatures.flatness`) : en dessous de `tonal`, un son tonal (même en accord ou réverbéré) ; à
    /// partir de `noisy`, un bruit (charleston, snare, clap, montée).
    static let tonal = 0.15
    static let noisy = 0.2
    /// Part d'énergie au-dessus de 6 kHz qui, avec le grave d'un kick, fait une boucle de batterie (une basse n'en a
    /// pas) ; `ringHigh` : un son long et bruité qui attaque (open hat, cymbale), pas une montée.
    static let loopHigh = 0.08
    static let ringHigh = 0.6

    /// Famille et confiance (0…1). Dans l'ordre : silence → voix reconnue → boucle de batterie (grave de kick et
    /// aigus) → basse (grave, tonale, longue ou qui change de note) → drums (court et bruité, ou grave court sur une
    /// seule note : kick ; court et entendu comme des drums par l'IA, sauf un son tonal qui change de note) → open
    /// hat, cymbale (long, bruité, aigu, qui attaque) → FX (long et bruité) → voix au vibrato (sans instrument
    /// reconnu) → mélodie (tonale) → FX (long) → à vérifier. Un son court et tonal sans hauteur nette (accord, arpège
    /// réverbéré) est une mélodie, plus des drums (retour de l'utilisateur : un arpège renommé « Snare »).
    static func decide(_ f: SoundFeatures, _ ai: AILabels) -> (family: SoundFamily, confidence: Double) {
        guard f.peakDB >= silenceDB else { return (.unsure, 0) }
        if ai.voice >= 0.5 { return (.vocals, ai.voice) }
        let low = f.pitchedFraction >= 0.4 && f.medianF0 > 0 && f.medianF0 < lowF0 && f.lowRatio >= 0.5
        let short = f.noteLength < shortNote
        let isNoisy = f.flatness >= noisy, isTonal = f.flatness < tonal
        if low && short && f.highRatio >= loopHigh { return (.drums, max(ai.drums, 0.75)) }
        if low && (f.noteLength >= 0.35 || f.distinctPitches >= 2) { return (.bass, 0.8) }
        if (short && isNoisy) || (low && f.noteLength < 0.35) { return (.drums, max(ai.drums, 0.75)) }
        if short && ai.drums >= 0.6 && ai.drums > ai.instrument && !(isTonal && f.distinctPitches >= 3) {
            return (.drums, ai.drums)
        }
        if !short && isNoisy && f.highRatio >= ringHigh && f.onsetsPerSecond > 0 { return (.drums, 0.7) }
        if !short && f.pitchedFraction < 0.3 && isNoisy { return (.fx, 0.7) }
        if (0.12...0.8).contains(f.vibrato) && (80...500).contains(f.medianF0) && f.pitchedFraction >= 0.6
            && f.noteLength >= 0.5 && f.distinctPitches <= 2 && ai.instrument < 0.5 {
            return (.vocals, 0.55)
        }
        if f.pitchedFraction >= 0.5 || ai.instrument >= 0.5 || isTonal {
            return (.melody, max(ai.instrument, 0.7))
        }
        if !short { return (.fx, 0.5) }
        return (.unsure, 0.3)
    }
}
