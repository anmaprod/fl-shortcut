// Organiser : l'IA intégrée qui classe les sons (YAMNet de Google, licence Apache 2.0, plus des têtes apprises sur
// des sons libres de droits ; sur le Mac, sans internet ; même modèle que l'ONNX de Windows, voir ia/README.md). Le
// son est ramené en mono 16 kHz, crête à 0,7, coupé en tranches de 0,975 s (pas 0,48 s ; 16 au plus, les plus
// fortes) ; le modèle rend pour chaque tranche la famille (voix, mélodie, basse, drums, FX), la sorte parmi les
// choix de l'aperçu de l'Organiser (Voix lead, Chœur, Pad, Piano, 808, Sub, Kick, Open Hat, Riser…) et ses 1216
// mesures (gardées quand on corrige le son : CorrectionsIA). C'est une voix dès que la tranche la plus « voix » passe
// le seuil ; sinon la famille est la moyenne des tranches. Le modèle (`ClasseurSons`) est compilé par build.sh dans
// l'app ; à défaut (tests, build sans Xcode), le paquet du dépôt est compilé à la première écoute. Partagé par les
// écoutes d'un Organiser et libéré avec elles : rien ne reste en mémoire au repos.
import AVFoundation
import CoreML
import Foundation

final class ClasseurSons {
    enum Famille: Int, CaseIterable { case voix, melodie, basse, drums, fx }

    /// Sortes du modèle, dans l'ordre de sa sortie « sorte » (ia/commun.py, vérifié par les tests) : les choix de
    /// l'aperçu, sauf Back et Synth, qui se décident au nom du son.
    static let sortes: [SoundKind] = [
        .vocal, .vocalLead, .choir, .adlib, .ambiance,
        .lead, .pluck, .pad, .keys, .piano, .arp, .chords, .guitar, .strings, .bell, .flute, .brass, .organ, .melody,
        .bass808, .sub, .reese, .bass,
        .kick, .snare, .clap, .rim, .snap, .hiHat, .openHat, .perc, .tom, .shaker, .crash, .ride, .cymbal, .drums,
        .riser, .downlifter, .impact, .sweep, .fx,
    ]

    /// Ce que l'IA intégrée entend dans un son.
    struct Avis: Equatable {
        /// Probabilité moyenne de chaque famille sur les tranches (ordre de `Famille`).
        var familles: [Double]
        /// Probabilité de voix de la tranche la plus « voix ».
        var voixMax: Double
        var famille: Famille
        /// Probabilité moyenne de chaque sorte sur les tranches (ordre de `sortes`).
        var sortes: [Double]
        /// Les 1216 nombres de chaque tranche (empreinte YAMNet + spectre) : gardés quand on corrige le son, jamais le
        /// son lui-même. Vide avec un modèle qui ne les rend pas.
        var mesures: [[Float]] = []

        /// Pour retrouver un son déjà corrigé (CorrectionsIA) : moyenne des empreintes YAMNet des tranches, de
        /// longueur 1 ; nil sans mesures.
        var empreinte: [Float]? { ClasseurSons.empreinte(mesures) }

        /// La sorte la plus probable parmi celles d'une famille de l'Organiser, et sa part parmi elles (0…1) ; nil
        /// pour « À vérifier ».
        func sorte(dans famille: SoundFamily) -> (kind: SoundKind, part: Double)? {
            let permises = ClasseurSons.sortes.indices.filter { ClasseurSons.sortes[$0].family == famille }
            let total = permises.reduce(0.0) { $0 + sortes[$1] }
            guard total > 0, let meilleure = permises.max(by: { sortes[$0] < sortes[$1] }) else { return nil }
            return (ClasseurSons.sortes[meilleure], sortes[meilleure] / total)
        }

        /// La sorte, seulement si elle l'emporte nettement parmi celles de la famille (`partMin`).
        func sorteNette(dans famille: SoundFamily) -> SoundKind? {
            guard let s = sorte(dans: famille), s.part >= ClasseurSons.partMin else { return nil }
            return s.kind
        }
    }

    /// Seuil des voix appris (ia/modele/classeur_sons.json, vérifié par les tests) : au plus 2 % des autres sons
    /// (FX, mélodies, drums, basses, leads au vibrato) passent au-dessus, sur des sons jamais entendus.
    static let seuilVoix = 0.34
    /// Une sorte n'est donnée que si elle l'emporte nettement sur les autres de sa famille.
    static let partMin = 0.5
    static let frequence = 16_000.0
    static let tranche = 15_600
    static let pas = 7_680
    static let maxTranches = 16
    static let nomModele = "ClasseurSons"
    /// Version du modèle (ia/modele/classeur_sons.json), envoyée avec une correction partagée.
    static let versionModele = 2
    /// Nombres par tranche : empreinte YAMNet (1024) + 192 mesures du spectre.
    static let tailleMesures = 1216
    static let tailleEmpreinte = 1024

    private let modele: MLModel
    /// Dernier son écouté et son avis : le classement puis la sorte d'un même son ne l'écoutent qu'une fois.
    private let verrouDernier = NSLock()
    private var dernier: (samples: [Float], rate: Double, avis: Avis?)?

    init?(modele url: URL? = ClasseurSons.modeleCompile()) {
        guard let url else { return nil }
        let reglages = MLModelConfiguration()
        reglages.computeUnits = .cpuOnly                     // précision de l'apprentissage, résultat stable
        guard let modele = try? MLModel(contentsOf: url, configuration: reglages) else { return nil }
        self.modele = modele
    }

    private static let verrouPartage = NSLock()
    private static weak var enCours: ClasseurSons?

    /// Le classeur des écoutes en cours (classement et sorte d'un même Organiser), créé à la demande et libéré quand
    /// plus personne ne le garde.
    static func partage() -> ClasseurSons? {
        verrouPartage.lock()
        defer { verrouPartage.unlock() }
        if let enCours { return enCours }
        let nouveau = ClasseurSons()
        enCours = nouveau
        return nouveau
    }

    /// Avis sur un son (échantillons à `rate` Hz) ; nil si le son est vide ou si le modèle n'a pas répondu.
    func avis(_ samples: [Float], rate: Double) -> Avis? {
        verrouDernier.lock()
        defer { verrouDernier.unlock() }
        if let dernier, dernier.rate == rate, dernier.samples == samples { return dernier.avis }
        let avis = ecouter(samples, rate: rate)
        dernier = (samples, rate, avis)
        return avis
    }

    private func ecouter(_ samples: [Float], rate: Double) -> Avis? {
        let lot = Self.tranches(Self.normaliser(Self.resample(samples, from: rate)))
        guard !lot.isEmpty,
              let entree = try? MLMultiArray(shape: [NSNumber(value: lot.count), NSNumber(value: Self.tranche)],
                                             dataType: .float32) else { return nil }
        let ligne = entree.strides[0].intValue                 // pas d'une tranche à la suivante (alignement)
        let p = entree.dataPointer.bindMemory(to: Float.self, capacity: lot.count * ligne)
        for (i, t) in lot.enumerated() {
            t.withUnsafeBufferPointer { (p + i * ligne).update(from: $0.baseAddress!, count: Self.tranche) }
        }
        guard let provider = try? MLDictionaryFeatureProvider(dictionary: ["son": MLFeatureValue(multiArray: entree)]),
              let sortie = try? modele.prediction(from: provider),
              let familles = sortie.featureValue(for: "famille")?.multiArrayValue,
              let sortes = sortie.featureValue(for: "sorte")?.multiArrayValue,
              familles.shape.last?.intValue == Famille.allCases.count,
              sortes.shape.last?.intValue == Self.sortes.count else { return nil }
        let valeur = { (a: MLMultiArray, i: Int, k: Int) in a[[NSNumber(value: i), NSNumber(value: k)]].doubleValue }
        let moyenne = { (a: MLMultiArray, k: Int) in (0..<lot.count).reduce(0.0) { $0 + valeur(a, $1, k) } / Double(lot.count) }
        let moyFamilles = Famille.allCases.map { moyenne(familles, $0.rawValue) }
        let moySortes = Self.sortes.indices.map { moyenne(sortes, $0) }
        let voixMax = (0..<lot.count).map { valeur(familles, $0, Famille.voix.rawValue) }.max() ?? 0
        let mesures = sortie.featureValue(for: "mesures")?.multiArrayValue.map { Self.lignes($0, n: lot.count) } ?? []
        return Self.decider(familles: moyFamilles, voixMax: voixMax, sortes: moySortes, mesures: mesures)
    }

    /// Lignes d'une sortie [n, 1216] du modèle ; vide si sa forme est autre.
    static func lignes(_ a: MLMultiArray, n: Int) -> [[Float]] {
        guard a.shape.count == 2, a.shape[0].intValue == n, a.shape[1].intValue == tailleMesures else { return [] }
        let pas0 = a.strides[0].intValue, pas1 = a.strides[1].intValue
        if a.dataType == .float32 {
            let p = a.dataPointer.bindMemory(to: Float.self, capacity: (n - 1) * pas0 + (tailleMesures - 1) * pas1 + 1)
            return (0..<n).map { i in (0..<tailleMesures).map { p[i * pas0 + $0 * pas1] } }
        }
        return (0..<n).map { i in (0..<tailleMesures).map { a[[NSNumber(value: i), NSNumber(value: $0)]].floatValue } }
    }

    /// Moyenne des empreintes YAMNet (les 1024 premiers nombres) des tranches, ramenée à une longueur de 1.
    static func empreinte(_ mesures: [[Float]]) -> [Float]? {
        guard !mesures.isEmpty, mesures.allSatisfy({ $0.count >= tailleEmpreinte }) else { return nil }
        var somme = [Float](repeating: 0, count: tailleEmpreinte)
        for tranche in mesures {
            for i in 0..<tailleEmpreinte { somme[i] += tranche[i] }
        }
        let norme = sqrt(somme.reduce(0) { $0 + $1 * $1 })
        guard norme > 0 else { return nil }
        return somme.map { $0 / norme }
    }

    // MARK: Pur

    /// Décision : voix si la tranche la plus « voix » passe le seuil, sinon la meilleure autre famille.
    static func decider(familles: [Double], voixMax: Double, sortes: [Double], mesures: [[Float]] = []) -> Avis {
        let famille: Famille = voixMax >= seuilVoix ? .voix
            : Famille.allCases.filter { $0 != .voix }.max { familles[$0.rawValue] < familles[$1.rawValue] } ?? .fx
        return Avis(familles: familles, voixMax: voixMax, famille: famille, sortes: sortes, mesures: mesures)
    }

    /// Crête ramenée à 0,7 (le niveau d'un sample ne doit pas compter, comme à l'apprentissage).
    static func normaliser(_ samples: [Float]) -> [Float] {
        let crete = samples.reduce(Float(0)) { max($0, abs($1)) }
        guard crete > 1e-4 else { return samples }
        let gain = 0.7 / crete
        return samples.map { $0 * gain }
    }

    /// Tranches de `tranche` échantillons tous les `pas` (la dernière complétée de silence, comme YAMNet) ; au-delà
    /// de `maxTranches`, les plus fortes, dans l'ordre du son. Vide pour un son vide.
    static func tranches(_ samples: [Float]) -> [[Float]] {
        guard !samples.isEmpty else { return [] }
        let n = 1 + max(0, Int((Double(samples.count - tranche) / Double(pas)).rounded(.up)))
        var lot: [[Float]] = []
        for i in 0..<n {
            let debut = i * pas
            var t = Array(samples[debut..<min(debut + tranche, samples.count)])
            if t.count < tranche { t += [Float](repeating: 0, count: tranche - t.count) }
            lot.append(t)
        }
        guard lot.count > maxTranches else { return lot }
        let energie = lot.map { $0.reduce(0) { $0 + $1 * $1 } }
        let fortes = Set(energie.indices.sorted { energie[$0] > energie[$1] }.prefix(maxTranches))
        return lot.indices.filter(fortes.contains).map { lot[$0] }
    }

    /// Son ramené à 16 kHz (convertisseur de macOS, meilleure qualité).
    static func resample(_ samples: [Float], from rate: Double) -> [Float] {
        guard !samples.isEmpty, rate > 0 else { return [] }
        guard rate != frequence else { return samples }
        guard let formatIn = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1),
              let formatOut = AVAudioFormat(standardFormatWithSampleRate: frequence, channels: 1),
              let convertisseur = AVAudioConverter(from: formatIn, to: formatOut),
              let entree = AVAudioPCMBuffer(pcmFormat: formatIn, frameCapacity: AVAudioFrameCount(samples.count)),
              let sortie = AVAudioPCMBuffer(pcmFormat: formatOut,
                                            frameCapacity: AVAudioFrameCount(Double(samples.count) * frequence / rate) + 1024)
        else { return [] }
        convertisseur.sampleRateConverterQuality = AVAudioQuality.max.rawValue
        entree.frameLength = AVAudioFrameCount(samples.count)
        samples.withUnsafeBufferPointer { entree.floatChannelData![0].update(from: $0.baseAddress!, count: samples.count) }
        var donne = false
        var erreur: NSError?
        let etat = convertisseur.convert(to: sortie, error: &erreur) { _, statut in
            if donne {
                statut.pointee = .endOfStream
                return nil
            }
            donne = true
            statut.pointee = .haveData
            return entree
        }
        guard etat != .error, let canal = sortie.floatChannelData?[0] else { return [] }
        return Array(UnsafeBufferPointer(start: canal, count: Int(sortie.frameLength)))
    }

    // MARK: Modèle

    private static let verrou = NSLock()
    private static var compile: URL?

    /// Modèle compilé : celui de l'app (build.sh), sinon le paquet de l'app ou du dépôt compilé une fois par
    /// lancement. nil si aucun n'est trouvé.
    static func modeleCompile() -> URL? {
        if let url = Bundle.main.url(forResource: nomModele, withExtension: "mlmodelc") { return url }
        verrou.lock()
        defer { verrou.unlock() }
        if let compile { return compile }
        let depot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/\(nomModele).mlpackage")
        let paquet = Bundle.main.url(forResource: nomModele, withExtension: "mlpackage")
            ?? (FileManager.default.fileExists(atPath: depot.path) ? depot : nil)
        guard let paquet, let url = try? MLModel.compileModel(at: paquet) else { return nil }
        compile = url
        return url
    }
}

extension AILabels {
    /// L'IA intégrée à la place de l'IA de macOS dans les règles (retour du propriétaire : l'organisation ne change
    /// pas avec l'IA) : sa voix pour la règle « voix-iv », ses drums et ses instruments (mélodie + basse) quand elle
    /// en entend plus que celle de macOS.
    mutating func merge(embedded avis: ClasseurSons.Avis) {
        embeddedVoice = avis.voixMax
        drums = max(drums, avis.familles[ClasseurSons.Famille.drums.rawValue])
        instrument = max(instrument, avis.familles[ClasseurSons.Famille.melodie.rawValue]
                         + avis.familles[ClasseurSons.Famille.basse.rawValue])
    }
}

extension ClasseurSons {
    /// Famille de l'Organiser pour une famille de l'IA intégrée.
    static func famille(_ f: Famille) -> SoundFamily {
        switch f {
        case .voix: return .vocals
        case .melodie: return .melody
        case .basse: return .bass
        case .drums: return .drums
        case .fx: return .fx
        }
    }
}
