import AVFoundation
import XCTest
@testable import FLShortcut

/// IA intégrée de l'Organiser : tranches comme YAMNet, son ramené à 16 kHz, même seuil que le modèle exporté, modèle
/// Core ML présent et qui répond comme le modèle ONNX de l'apprentissage sur des sons jamais entendus
/// (Fixtures/CREDITS.md), règles de l'Organiser.
final class ClasseurSonsTests: XCTestCase {
    private static let fixtures = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures")
    private static let racine = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()

    private func lire(_ nom: String) throws -> (samples: [Float], rate: Double) {
        let fichier = try AVAudioFile(forReading: Self.fixtures.appendingPathComponent(nom))
        let format = fichier.processingFormat
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(fichier.length)))
        try fichier.read(into: buffer)
        let canal = try XCTUnwrap(buffer.floatChannelData?[0])
        return (Array(UnsafeBufferPointer(start: canal, count: Int(buffer.frameLength))), format.sampleRate)
    }

    func testTranchesCommeYAMNet() {
        let t = ClasseurSons.tranche, p = ClasseurSons.pas
        XCTAssertEqual(ClasseurSons.tranches([]).count, 0)
        XCTAssertEqual(ClasseurSons.tranches([Float](repeating: 0.1, count: 100)).count, 1)
        XCTAssertEqual(ClasseurSons.tranches([Float](repeating: 0.1, count: t)).count, 1)
        XCTAssertEqual(ClasseurSons.tranches([Float](repeating: 0.1, count: t + 1)).count, 2)
        XCTAssertEqual(ClasseurSons.tranches([Float](repeating: 0.1, count: t + p)).count, 2)
        XCTAssertEqual(ClasseurSons.tranches([Float](repeating: 0.1, count: t + p + 1)).count, 3)
        XCTAssertTrue(ClasseurSons.tranches([Float](repeating: 0.1, count: 100)).allSatisfy { $0.count == t })
    }

    func testSonLongGardeLesTranchesLesPlusFortes() {
        var son = [Float](repeating: 0.001, count: ClasseurSons.tranche + ClasseurSons.pas * 40)
        let fort = ClasseurSons.pas * 20
        for i in fort..<(fort + ClasseurSons.tranche) { son[i] = 0.8 }
        let lot = ClasseurSons.tranches(son)
        XCTAssertEqual(lot.count, ClasseurSons.maxTranches)
        XCTAssertTrue(lot.contains { $0.allSatisfy { $0 == 0.8 } }, "la tranche la plus forte doit rester")
    }

    func testReechantillonnageEtCrete() {
        let la = (0..<44_100).map { Float(0.2 * sin(2 * Double.pi * 440 * Double($0) / 44_100)) }
        XCTAssertEqual(Double(ClasseurSons.resample(la, from: 44_100).count), 16_000, accuracy: 160)
        XCTAssertEqual(ClasseurSons.resample(la, from: 16_000).count, la.count)
        XCTAssertTrue(ClasseurSons.resample([], from: 44_100).isEmpty)
        XCTAssertEqual(ClasseurSons.normaliser(la).map { abs($0) }.max() ?? 0, 0.7, accuracy: 1e-4)
    }

    /// Même seuil, mêmes tranches et mêmes classes que le modèle exporté (ia/modele/classeur_sons.json).
    func testReglagesCommeLeModeleExporte() throws {
        let data = try Data(contentsOf: Self.racine.appendingPathComponent("ia/modele/classeur_sons.json"))
        let meta = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(meta["seuil_voix"] as? Double, ClasseurSons.seuilVoix)
        XCTAssertEqual(meta["tranche"] as? Int, ClasseurSons.tranche)
        XCTAssertEqual(meta["pas"] as? Int, ClasseurSons.pas)
        XCTAssertEqual(meta["max_tranches"] as? Int, ClasseurSons.maxTranches)
        XCTAssertEqual((meta["familles"] as? [String])?.count, ClasseurSons.Famille.allCases.count)
        XCTAssertEqual(meta["sortes"] as? [String], ClasseurSons.sortes.map(\.rawValue),
                       "sortes du modèle : celles de l'aperçu, dans l'ordre du modèle")
    }

    /// Le modèle propose les choix de l'aperçu de l'Organiser, chacun une fois ; seuls Back et Synth (au nom) manquent.
    func testSortesCommeLAppercu() {
        XCTAssertEqual(Set(ClasseurSons.sortes).count, ClasseurSons.sortes.count)
        XCTAssertEqual(Set(SoundKind.allCases).subtracting(ClasseurSons.sortes), [.backing, .synth])
    }

    func testDecision() {
        var sortes = [Double](repeating: 0, count: ClasseurSons.sortes.count)
        let rang = { (k: SoundKind) in ClasseurSons.sortes.firstIndex(of: k)! }
        sortes[rang(.choir)] = 0.3
        sortes[rang(.snare)] = 0.2
        sortes[rang(.clap)] = 0.1
        sortes[rang(.bass808)] = 0.05
        sortes[rang(.reese)] = 0.15
        var a = ClasseurSons.decider(familles: [0.3, 0.1, 0.0, 0.5, 0.1], voixMax: 0.9, sortes: sortes)
        XCTAssertEqual(a.famille, .voix)
        XCTAssertEqual(a.sorte(dans: .vocals)?.kind, .choir)
        XCTAssertEqual(a.sorte(dans: .vocals)?.part ?? 0, 1, accuracy: 1e-9)
        a = ClasseurSons.decider(familles: [0.3, 0.1, 0.0, 0.5, 0.1], voixMax: 0.1, sortes: sortes)
        XCTAssertEqual(a.famille, .drums)
        XCTAssertEqual(a.sorte(dans: .drums)?.kind, .snare, "la sorte parmi celles de la famille")
        XCTAssertEqual(a.sorte(dans: .drums)?.part ?? 0, 2.0 / 3, accuracy: 1e-9)
        XCTAssertEqual(a.sorte(dans: .bass)?.kind, .reese)
        XCTAssertNil(a.sorte(dans: .melody), "aucune sorte de mélodie entendue")
        XCTAssertNil(a.sorte(dans: .unsure))
    }

    /// La sorte vient du même classeur que le classement : le son n'est écouté qu'une fois, la sorte n'est donnée que
    /// si elle l'emporte nettement.
    func testSorteParLIAIntegree() throws {
        let classeur = try XCTUnwrap(ClasseurSons.partage())
        XCTAssertTrue(ClasseurSons.partage() === classeur, "un seul classeur pour les écoutes en cours")
        let son = try lire("voix-parole.wav")
        let avis = try XCTUnwrap(classeur.avis(son.samples, rate: son.rate))
        XCTAssertEqual(classeur.avis(son.samples, rate: son.rate), avis)
        let nommer = OrganizerSession.liveKindNamer(classeur: classeur)
        let attendue = try XCTUnwrap(avis.sorte(dans: .vocals))
        XCTAssertEqual(nommer(son.samples, son.rate, .vocals), attendue.part >= ClasseurSons.partMin ? attendue.kind : nil)
        XCTAssertNil(nommer(son.samples, son.rate, .unsure))
        XCTAssertEqual(nommer(son.samples, son.rate, .drums).map(\.family) ?? .drums, .drums)
    }

    /// Sons jamais entendus à l'apprentissage : la bonne famille, la même sorte et les mêmes probabilités que le
    /// modèle ONNX.
    func testSonsJamaisEntendus() throws {
        let classeur = try XCTUnwrap(ClasseurSons(), "modèle de l'IA intégrée introuvable ou illisible")
        let data = try Data(contentsOf: Self.fixtures.appendingPathComponent("attendus.json"))
        let attendus = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: [String: Any]])
        XCTAssertFalse(attendus.isEmpty)
        let noms = ["voix", "melodie", "basse", "drums", "fx"]
        for (fichier, a) in attendus.sorted(by: { $0.key < $1.key }) {
            let son = try lire(fichier)
            let avis = try XCTUnwrap(classeur.avis(son.samples, rate: son.rate), fichier)
            XCTAssertEqual(noms[avis.famille.rawValue], a["famille_voulue"] as? String, "\(fichier) : mauvaise famille")
            XCTAssertEqual(avis.voixMax, try XCTUnwrap(a["voix_max"] as? Double), accuracy: 0.08,
                           "\(fichier) : le modèle Core ML s'écarte du modèle ONNX")
            let famille = ClasseurSons.famille(avis.famille)
            if let sorte = a["sorte"] as? String {                // nette pour le modèle ONNX (essais_app.py)
                XCTAssertEqual(avis.sorte(dans: famille)?.kind.rawValue, sorte, "\(fichier) : autre sorte")
            }
        }
    }

    func testRegleVoixDeLIAIntegree() {
        let ton = (0..<44_100).map { Float(0.5 * sin(2 * Double.pi * 220 * Double($0) / 44_100)) }
        let mesures = SoundFeatures.measure(ton, rate: 44_100)
        var ia = AILabels(voice: 0.2)
        ia.embeddedVoice = 0.95
        let voix = FamilyFusion.decideWithRule(mesures, ia)
        XCTAssertEqual(voix.family, .vocals)
        XCTAssertEqual(voix.rule, "voix-iv")
        ia.embeddedVoice = 0.05
        XCTAssertNotEqual(FamilyFusion.decideWithRule(mesures, ia).family, .vocals)
        ia.embeddedVoice = nil
        XCTAssertNotEqual(FamilyFusion.decideWithRule(mesures, ia).family, .vocals)
    }

    /// Les règles d'avant restent (retour du propriétaire : l'organisation ne change pas avec l'IA) : ce que les
    /// mesures disent sûrement passe avant l'IA intégrée, qui prend ensuite la place de l'IA de macOS.
    func testLIAIntegreeDansLesReglesDAvant() {
        func f(len: Double, low: Double, flat: Double, high: Double = 0, f0: Double = 0) -> SoundFeatures {
            SoundFeatures(peakDB: -6, noteLength: len, pitchedFraction: f0 > 0 ? 0.6 : 0, medianF0: f0, lowRatio: low,
                          flatness: flat, onsetsPerSecond: 4, distinctPitches: 1, vibrato: 0, highRatio: high)
        }
        let boucle = f(len: 0.17, low: 0.5, flat: 0.26, high: 0.41)
        XCTAssertEqual(DrumNaming.kind(boucle, scores: [:], embedded: .kick), .drums, "boucle : les mesures d'abord")
        let hat = f(len: 0.1, low: 0, flat: 0.6, high: 0.9)
        XCTAssertEqual(DrumNaming.kind(hat, scores: [:], embedded: .snare), .hiHat, "hi-hat à ses aigus, même si l'IA dit snare")
        XCTAssertEqual(DrumNaming.kind(hat, scores: [:], embedded: .openHat), .openHat, "l'IA précise un métal")
        let neutre = f(len: 0.2, low: 0.2, flat: 0.1)
        XCTAssertEqual(DrumNaming.kind(neutre, scores: ["bass_drum": 0.8], embedded: .rim), .rim, "à la place de l'IA de macOS")
        XCTAssertEqual(DrumNaming.kind(neutre, scores: ["bass_drum": 0.8], embedded: nil), .kick, "sans avis net : comme avant")
        XCTAssertEqual(MelodyNaming.kind(neutre, scores: ["piano": 0.7], embedded: .pad), .pad)
        XCTAssertEqual(MelodyNaming.kind(neutre, scores: ["piano": 0.7], embedded: nil), .piano)

        var ia = AILabels(voice: 0.3)
        var avis = ClasseurSons.decider(familles: [0.05, 0.1, 0.05, 0.75, 0.05], voixMax: 0.2,
                                        sortes: [Double](repeating: 0, count: ClasseurSons.sortes.count))
        ia.merge(embedded: avis)
        XCTAssertEqual(ia.voice, 0.3, "la voix de l'IA de macOS ne change pas")
        XCTAssertEqual(ia.embeddedVoice, 0.2)
        XCTAssertEqual(ia.drums, 0.75, accuracy: 1e-9)
        XCTAssertEqual(ia.instrument, 0.15, accuracy: 1e-9)
        avis.familles = [0, 0, 0, 0.1, 0]
        var macos = AILabels(drums: 0.8, instrument: 0.6)
        macos.merge(embedded: avis)
        XCTAssertEqual(macos.drums, 0.8, "le plus sûr des deux")
        XCTAssertEqual(macos.instrument, 0.6)
        // Trois notes nettes : une mélodie, même si l'IA intégrée entend des drums (la règle d'avant passe avant).
        let notes = SoundFeatures(peakDB: -6, noteLength: 0.16, pitchedFraction: 0.9, medianF0: 391, lowRatio: 0.01,
                                  flatness: 0.01, onsetsPerSecond: 6, distinctPitches: 4, vibrato: 0, highRatio: 0)
        XCTAssertEqual(FamilyFusion.decide(notes, AILabels(drums: 0.95)).family, .melody)
    }

    /// Le modèle rend aussi les 1216 nombres de chaque tranche, et l'empreinte du son (longueur 1).
    func testMesuresEtEmpreinte() throws {
        let classeur = try XCTUnwrap(ClasseurSons())
        let son = try lire("voix-chant-44k.wav")
        let avis = try XCTUnwrap(classeur.avis(son.samples, rate: son.rate))
        XCTAssertEqual(avis.mesures.count, ClasseurSons.tranches(ClasseurSons.resample(son.samples, from: son.rate)).count)
        XCTAssertTrue(avis.mesures.allSatisfy { $0.count == ClasseurSons.tailleMesures })
        let empreinte = try XCTUnwrap(avis.empreinte)
        XCTAssertEqual(empreinte.count, ClasseurSons.tailleEmpreinte)
        XCTAssertEqual(CorrectionsIA.ressemblance(empreinte, empreinte), 1, accuracy: 1e-4)
        XCTAssertNil(ClasseurSons.empreinte([]))
    }

    /// Corrections dans un dossier et des réglages jetables : (magasin, son fichier, ménage).
    private func magasin() throws -> (CorrectionsIA, URL, () -> Void) {
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let fichier = dossier.appendingPathComponent("corrections-ia.json")
        let suite = "essai.corrections." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        return (CorrectionsIA(url: fichier, defaults: defaults), fichier, {
            try? FileManager.default.removeItem(at: dossier)
            defaults.removePersistentDomain(forName: suite)
        })
    }

    private func unite(_ i: Int, _ j: Int? = nil) -> [Float] {
        var v = [Float](repeating: 0, count: ClasseurSons.tailleEmpreinte)
        v[i] = 1
        if let j {
            v[j] = 1
            return v.map { $0 / sqrt(2) }
        }
        return v
    }

    /// Les corrections restent sur le Mac (relues au lancement suivant) ; seul un son presque identique est
    /// retrouvé ; un même son corrigé deux fois garde la dernière réponse ; 500 au plus.
    func testCorrectionsGardeesSurLeMac() throws {
        let (store, fichier, fin) = try magasin()
        defer { fin() }
        XCTAssertNil(store.cherche(unite(3)))
        store.ajoute(CorrectionIA(empreinte: unite(3), famille: .vocals, sorte: .choir, date: Date()))
        XCTAssertEqual(store.cherche(unite(3))?.sorte, .choir)
        XCTAssertNil(store.cherche(unite(3, 4)), "ressemblance 0,71 : un autre son")
        XCTAssertNil(store.cherche(nil))
        store.ajoute(CorrectionIA(empreinte: unite(3), famille: .vocals, sorte: .adlib, date: Date()))
        XCTAssertEqual(store.nombre, 1)
        XCTAssertEqual(CorrectionsIA(url: fichier).cherche(unite(3))?.sorte, .adlib, "gardée dans le fichier")
        for i in 0..<(CorrectionsIA.maximum + 5) {
            store.ajoute(CorrectionIA(empreinte: unite(i % 1000, (i / 1000) + 1000), famille: .drums, sorte: nil,
                                      date: Date()))
        }
        XCTAssertEqual(store.nombre, CorrectionsIA.maximum)
    }

    /// Ce qui part au serveur (accord donné) : des nombres en 16 bits et des noms de familles et de sortes de l'IA,
    /// jamais un nom de son ; rien pour « À vérifier » ; une sorte que l'IA n'apprend pas (Back) n'est pas envoyée.
    func testEnvoiDesCorrections() throws {
        let mesures = [[Float]](repeating: (0..<ClasseurSons.tailleMesures).map { Float($0) / 2 }, count: 10)
        let ecoute = SoundPrint(mesures: mesures, empreinte: unite(1), familleIA: .melody, sorteIA: .lead)
        let corps = try XCTUnwrap(CorrectionsIA.envoi(ecoute, avant: (.melody, .lead), apres: (.vocals, .backing),
                                                      raisons: ["voice"], appVersion: "0.1.0"))
        XCTAssertEqual(corps["famille_ia"] as? String, "melodie")
        XCTAssertEqual(corps["sorte_ia"] as? String, "lead")
        XCTAssertEqual(corps["famille"] as? String, "voix")
        XCTAssertNil(corps["sorte"], "Back se décide au nom : pas appris")
        XCTAssertEqual(corps["tranches"] as? Int, CorrectionsIA.tranchesEnvoyees, "8 tranches au plus")
        let brut = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(corps["mesures"] as? String)))
        XCTAssertEqual(brut.count, CorrectionsIA.tranchesEnvoyees * ClasseurSons.tailleMesures * 2)
        let premiers = brut.withUnsafeBytes { Array($0.bindMemory(to: UInt16.self).prefix(3)) }
        XCTAssertEqual(premiers, [0x0000, 0x3800, 0x3C00], "0 ; 0,5 ; 1 en 16 bits")
        XCTAssertEqual(Set(corps.keys), ["famille_ia", "sorte_ia", "famille_avant", "sorte_avant", "famille",
                                         "mesures", "tranches", "raisons", "modele", "app_version"])
        XCTAssertNil(CorrectionsIA.envoi(ecoute, avant: (.melody, nil), apres: (.unsure, nil), raisons: [],
                                         appVersion: "0.1.0"))
    }

    /// Un son corrigé par l'utilisateur est rangé comme il l'a dit, avant toute règle ; sa sorte aussi.
    func testRegleCorrige() throws {
        let classeur = try XCTUnwrap(ClasseurSons())
        let (store, _, fin) = try magasin()
        defer { fin() }
        let son = try lire("voix-parole.wav")
        let empreinte = try XCTUnwrap(classeur.avis(son.samples, rate: son.rate)?.empreinte)
        let classer = OrganizerSession.liveClassifier(ai: nil, classeur: classeur, corrections: store)
        XCTAssertEqual(classer(son.samples, son.rate).family, .vocals, "sans correction : une voix")
        store.ajoute(CorrectionIA(empreinte: empreinte, famille: .drums, sorte: .rim, date: Date()))
        let verdict = classer(son.samples, son.rate)
        XCTAssertEqual(verdict.family, .drums)
        XCTAssertTrue(verdict.rule.hasPrefix("corrige"), verdict.rule)
        let drums = OrganizerSession.liveDrumNamer(ai: nil, classeur: classeur, corrections: store)
        XCTAssertEqual(drums(son.samples, son.rate), .rim)
        let sorte = OrganizerSession.liveKindNamer(classeur: classeur, corrections: store)
        XCTAssertNotEqual(sorte(son.samples, son.rate, .fx), .rim, "une sorte d'une autre famille n'est pas reprise")
    }

    /// Le classement réel écrit ce que l'IA intégrée a entendu (« +iv » et un nombre), jamais un nom.
    func testDiagnosticDeLIAIntegree() throws {
        let classeur = try XCTUnwrap(ClasseurSons())
        let son = try lire("voix-parole.wav")
        let verdict = OrganizerSession.liveClassifier(ai: nil, classeur: classeur)(son.samples, son.rate)
        XCTAssertEqual(verdict.family, .vocals)
        XCTAssertNotNil(verdict.rule.range(of: #"\+iv\d+$"#, options: .regularExpression), verdict.rule)
    }
}
