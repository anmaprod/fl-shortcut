import AppKit
import Combine
import SwiftUI
import XCTest
@testable import FLShortcut

/// Organiser : contrôleur de la fenêtre (sans fenêtre), bloc « Organiser » et son modèle.
final class OrganizerWindowTests: XCTestCase {
    private static func classify(_ samples: [Float], _ rate: Double)
        -> (family: SoundFamily, confidence: Double, rule: String) {
        samples.isEmpty ? (.unsure, 0, "silence") : (.drums, 0.9, "faux")
    }

    private func env(_ link: FakeOrganizerLink, _ audio: FakeAudio,
                     saved: @escaping ([SoundFamily: FamilyStyle]) -> Void) -> OrganizerEnvironment {
        var e = OrganizerEnvironment(link: { link }, audio: { .success(audio) },
                                     classify: { OrganizerWindowTests.classify },
                                     moveUp: { _ in { count in link.moveSelectedUp(count) } },
                                     moveLeft: { _ in { count in link.moveSelectedLeft(count) } },
                                     timing: OrganizerSession.Timing(listen: 0.01, testNote: 0.01, tail: 0.01, slice: 0.01),
                                     sleep: { _ in }, escapePressed: { false },
                                     loadStyles: { FamilyStyles.initial }, saveStyles: saved)
        e.waitInterval = 0.05
        e.deleteSelected = { _ in link.deleteSelected }
        e.moveTrack = { _ in { place, count in link.moveTrackUp(place, count) } }
        return e
    }

    private func waitFor(_ controller: OrganizerController, _ reached: @escaping (OrganizerController.Phase) -> Bool) {
        let done = expectation(description: "phase atteinte")
        done.assertForOverFulfill = false
        let watch = controller.$phase.sink { if reached($0) { done.fulfill() } }
        wait(for: [done], timeout: 5)
        watch.cancel()
    }

    private static func isApplied(_ phase: OrganizerController.Phase) -> Bool {
        if case .applied = phase { return true }
        return false
    }

    private static func isUndone(_ phase: OrganizerController.Phase) -> Bool {
        if case .undone = phase { return true }
        return false
    }

    func testControllerReleasedOnClose() throws {
        let first = RGBColor(r: 1, g: 2, b: 3), second = RGBColor(r: 4, g: 5, b: 6), black = RGBColor(r: 0, g: 0, b: 0)
        let drums = try XCTUnwrap(FamilyStyles.initial[.drums]).color
        let bass = try XCTUnwrap(FamilyStyles.initial[.bass]).color
        let link = FakeOrganizerLink()
        link.channels = [ChannelInfo(index: 0, type: 2, mixerTrack: 0, color: first, name: "Son 0"),
                         ChannelInfo(index: 1, type: 2, mixerTrack: 0, color: second, name: "Son 1")]
        let audio = FakeAudio(link: link)
        audio.parts = [0: [Float](repeating: 0.3, count: 64), 1: [Float](repeating: 0.3, count: 64)]
        var saved: [SoundFamily: FamilyStyle]?
        var closings = 0
        weak var released: OrganizerController?
        do {
            let controller = OrganizerController(env: env(link, audio, saved: { saved = $0 }))
            released = controller
            controller.onClose = { closings += 1 }
            controller.start()
            waitFor(controller) { $0 == .preview }
            XCTAssertEqual(controller.title, "Organiser le projet")
            XCTAssertEqual(controller.presentFamilies, [.drums])
            XCTAssertEqual(controller.members(of: .drums).map(\.name), ["Son 0", "Son 1"])

            // Une famille changée dans l'aperçu, un dégradé choisi : gardés dans les préférences à l'application.
            controller.families[1] = .bass
            XCTAssertEqual(controller.presentFamilies, [.bass, .drums], "ordre : voix, mélodies, basse, drums, FX")
            controller.updateStyle(.drums) { $0.fade = black }
            controller.apply()
            waitFor(controller, OrganizerWindowTests.isApplied)
            XCTAssertEqual(controller.phase, .applied(nil))
            XCTAssertEqual(saved?[.drums]?.fade, black)
            XCTAssertEqual(link.channels.map(\.color), [bass, drums], "la basse remonte avant les drums")
            XCTAssertEqual(link.channels.map(\.name), ["Basse", "Perc"], "renommés simplement")

            XCTAssertTrue(controller.canUndo)
            controller.undo()
            waitFor(controller, OrganizerWindowTests.isUndone)
            XCTAssertEqual(controller.phase, .undone(nil))
            XCTAssertFalse(controller.canUndo)
            XCTAssertEqual(link.channels.map(\.color), [first, second])
            XCTAssertEqual(link.channels.map(\.name), ["Son 0", "Son 1"])

            controller.close()
            controller.close()
            XCTAssertEqual(closings, 1)
        }
        let drained = expectation(description: "file principale vidée")
        DispatchQueue.main.async { drained.fulfill() }
        wait(for: [drained], timeout: 2)
        XCTAssertNil(released, "contrôleur libéré à la fermeture")
        XCTAssertNil(OrganizerWindow.controller)
    }

    func testSetupWhenLinkMissingThenRetry() {
        let link = FakeOrganizerLink()
        link.channels = [ChannelInfo(index: 0, type: 2, mixerTrack: 0, color: RGBColor(r: 1, g: 2, b: 3), name: "Son 0")]
        let audio = FakeAudio(link: link)
        audio.parts = [0: [Float](repeating: 0.3, count: 64)]
        var installed = false
        var e = env(link, audio, saved: { _ in })
        e.prepareLink = { installed ? .ready(warmUp: 0.5) : .notInstalled }
        e.installLink = { installed = true; return true }
        let controller = OrganizerController(env: e)
        controller.start()
        XCTAssertEqual(controller.phase, .setup)
        XCTAssertTrue(controller.canRetry)
        XCTAssertEqual(link.log, [], "rien n'est envoyé à FL")
        // Un clic : installé, puis Organiser attend FL et continue tout seul (sans « Réessayer »).
        controller.installLink()
        XCTAssertEqual(controller.phase, .waiting(.restartFL))
        waitFor(controller) { $0 == .preview }
        XCTAssertEqual(controller.members(of: .drums).map(\.name), ["Son 0"])
        XCTAssertFalse(controller.canRetry)
        controller.close()
    }

    /// Script disparu de FL : remis, puis FL à redémarrer (rien n'est envoyé) ; Organiser continue tout seul quand
    /// FL répond. Emplacement montré, autre dossier ; attentes et vrais échecs bien triés.
    func testRestoredScriptAsksToRestartFL() {
        let link = FakeOrganizerLink()
        link.channels = [ChannelInfo(index: 0, type: 2, mixerTrack: 0, color: RGBColor(r: 1, g: 2, b: 3), name: "Son 0")]
        let audio = FakeAudio(link: link)
        audio.parts = [0: [Float](repeating: 0.3, count: 64)]
        let script = URL(fileURLWithPath: "/Users/nina/Documents/Image-Line/FL Studio/Settings/Hardware/FL Shortcuts/"
                         + "device_FLShortcut.py")
        var restored = true
        var revealed: [URL] = []
        var elsewhere = 0
        var e = env(link, audio, saved: { _ in })
        e.prepareLink = {
            defer { restored = false }
            return restored ? .restored : .ready(warmUp: 0)
        }
        e.scriptPlace = { (url: script, present: true) }
        e.reveal = { revealed.append($0) }
        e.installLinkElsewhere = { elsewhere += 1; return true }
        let controller = OrganizerController(env: e)
        controller.start()
        XCTAssertEqual(controller.phase, .waiting(.restartFL))
        XCTAssertEqual(link.log, [], "rien n'est envoyé à FL avant son redémarrage")
        XCTAssertEqual(OrganizerController.waitReason(for: .noResponse), .noResponse)
        XCTAssertEqual(OrganizerController.waitReason(for: .outdatedScript), .restartFL)
        XCTAssertEqual(OrganizerController.waitReason(for: .flClosed), .openFL)
        XCTAssertEqual(OrganizerController.waitReason(for: .refused(4)), .stopPlayback)
        XCTAssertNil(OrganizerController.waitReason(for: .cancelled))
        XCTAssertEqual(controller.scriptPlace?.url, script)
        controller.revealScript()
        XCTAssertEqual(revealed, [script])
        controller.installLinkElsewhere()
        XCTAssertEqual(elsewhere, 1)
        XCTAssertEqual(controller.phase, .waiting(.restartFL))
        waitFor(controller) { $0 == .preview }
        controller.close()
    }

    /// Fichier du projet introuvable : « Choisir le fichier… » le fait montrer, puis l'analyse repart toute seule.
    func testProjectNotFoundAsksForTheFile() {
        let link = FakeOrganizerLink()
        var e = env(link, FakeAudio(link: link), saved: { _ in })
        var saves = 0
        var asked = 0
        e.projectFiles = { ProjectFileAccess(save: { _ in saves += 1; return .failure(.projectNotFound) },
                                             open: { _ in false }) }
        e.chooseProject = { asked += 1; return true }
        let controller = OrganizerController(env: e)
        controller.start()
        waitFor(controller) { if case .failed = $0 { return true } else { return false } }
        XCTAssertTrue(controller.projectMissing)
        XCTAssertEqual(controller.phase, .failed(OrganizerError.projectNotFound.message))
        controller.chooseProject()
        XCTAssertEqual(asked, 1)
        XCTAssertFalse(controller.projectMissing, "l'analyse repart")
        waitFor(controller) { if case .failed = $0 { return true } else { return false } }
        XCTAssertEqual(saves, 2)
        XCTAssertTrue(controller.projectMissing)
        controller.close()
    }

    /// Un ancien script chargé dans FL : Organiser attend que FL redémarre, puis continue tout seul.
    func testOldScriptWaitsThenGoesOn() {
        let link = FakeOrganizerLink()
        link.v14 = false
        let controller = OrganizerController(env: env(link, FakeAudio(link: link), saved: { _ in }))
        controller.start()
        waitFor(controller) { $0 == .waiting(.restartFL) }
        XCTAssertTrue(controller.canRetry)
        link.v14 = true
        waitFor(controller) { if case .failed = $0 { return true } else { return false } }
        XCTAssertEqual(controller.phase, .failed("Aucun son à organiser dans ce projet."))
        controller.close()
    }

    /// Rangés d'après leur nom (« BEAM KICK » : Kick) : l'aperçu montre ce qu'est chaque son et le nom qu'il prendra,
    /// les met dans l'ordre du Channel rack organisé (les Kick, puis les Clap, puis les Open Hat) ; changé à la main,
    /// il suit.
    func testPreviewShowsWhatEachSoundIs() {
        let link = FakeOrganizerLink()
        let gray = RGBColor(r: 9, g: 9, b: 9)
        link.channels = ["ALTER OPEN HAT", "BEAM KICK", "ZEBRA 808", "@MEH CLAP"].enumerated().map {
            ChannelInfo(index: $0.offset, type: 2, mixerTrack: 0, color: gray, name: $0.element)
        }
        let controller = OrganizerController(env: env(link, FakeAudio(link: link), saved: { _ in }))
        controller.start()
        waitFor(controller) { $0 == .preview }
        XCTAssertEqual(controller.presentFamilies, [.bass, .drums])
        XCTAssertEqual(controller.members(of: .drums).map(\.name), ["BEAM KICK", "@MEH CLAP", "ALTER OPEN HAT"])
        XCTAssertEqual(controller.members(of: .drums).map { $0.kind?.name }, ["Kick", "Clap", "Open Hat"])
        XCTAssertEqual(controller.members(of: .drums).map(\.newName), ["Kick", "Clap", "Open Hat"])
        XCTAssertEqual(controller.members(of: .bass).map { $0.kind?.name }, ["808"])

        controller.setFamily(1, .bass)
        XCTAssertEqual(controller.members(of: .bass).map(\.name), ["ZEBRA 808", "BEAM KICK"])
        XCTAssertEqual(controller.members(of: .bass).map(\.kind), [.bass808, nil], "une famille seule : plus un Kick")
        controller.setKind(1, .kick)
        XCTAssertEqual(controller.families[1], .drums)
        XCTAssertEqual(controller.members(of: .drums).first?.kind, .kick)
        controller.options.rename = false
        XCTAssertEqual(controller.members(of: .drums).map(\.newName), [nil, nil, nil])
        controller.options.rename = true

        controller.apply()
        waitFor(controller, OrganizerWindowTests.isApplied)
        XCTAssertEqual(controller.phase, .applied(nil))
        XCTAssertEqual(link.channels.map(\.name), ["808", "Kick", "Clap", "Open Hat"])
        controller.close()
    }

    /// Écrans de démonstration (captures de la CI), avec les sons d'exemple : chacun se construit et se dessine.
    /// Sur la CI, « apercu » et « fini » restaient sur l'écran de l'écoute ; ce test dit si leur vue plante.
    func testDemoScreensRender() {
        let link = FakeOrganizerLink()
        let controller = OrganizerController(env: env(link, FakeAudio(link: link), saved: { _ in }))
        for screen in ["installer", "attente", "aide", "ecoute", "apercu", "fini"] {
            controller.showDemo(screen)
            if screen == "apercu" {
                XCTAssertEqual(controller.phase, .preview)
                XCTAssertFalse(controller.presentFamilies.isEmpty, "familles des sons d'exemple")
            }
            let host = NSHostingView(rootView: OrganizerView(controller: controller))
            host.frame = NSRect(x: 0, y: 0, width: OrganizerView.width, height: OrganizerView.height)
            host.layoutSubtreeIfNeeded()
            guard let image = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
                XCTFail("écran « \(screen) » : rien à dessiner")
                continue
            }
            host.cacheDisplay(in: host.bounds, to: image)
            XCTAssertGreaterThan(host.fittingSize.height, 0, screen)
        }
        XCTAssertEqual(controller.phase, .applied(nil))
        controller.close()
    }

    /// « Organiser » : Channel rack, patterns, Mixer (même ordre, pistes de groupe après leurs pistes) et
    /// Playlist d'un coup ; « Revenir comme avant » remet tout.
    func testWholeProjectAppliedThenUndone() {
        let link = FakeOrganizerLink()
        let gray = RGBColor(r: 9, g: 9, b: 9)
        link.channels = [ChannelInfo(index: 0, type: 2, mixerTrack: 1, color: gray, name: "BEAM KICK"),
                         ChannelInfo(index: 1, type: 2, mixerTrack: 2, color: gray, name: "Lead Synth"),
                         ChannelInfo(index: 2, type: 2, mixerTrack: 3, color: gray, name: "@MEH CLAP")]
        link.mixer = (0...5).map { MixerTrackInfo(index: $0, color: gray, name: $0 == 0 ? "Master" : "Insert \($0)") }
        link.routes = [1: [4], 3: [4]]
        link.patternList = [PatternInfo(index: 0, color: gray, name: "hi hat"),
                            PatternInfo(index: 1, color: gray, name: "Pattern 2")]
        link.patternSounds = [2: [1]]
        link.bars = 2
        link.songAt = { _ in ([0, 1], [0, 1]) }
        link.trackChannels = [0: [0, 2], 1: [1]]
        link.playlist = (0..<2).map { PlaylistTrackInfo(index: $0, selected: false, color: gray, name: "Track \($0 + 1)") }
        let original = (link.channels, link.mixer, link.patternList, link.playlist)
        let controller = OrganizerController(env: env(link, FakeAudio(link: link), saved: { _ in }))
        controller.start()
        waitFor(controller) { $0 == .preview }
        XCTAssertEqual(controller.summary.count, 4, "une ligne par page de FL")
        controller.apply()
        waitFor(controller, OrganizerWindowTests.isApplied)
        XCTAssertEqual(controller.phase, .applied(nil))
        // Channel rack : la mélodie d'abord, puis les drums (Kick, Clap) ; noms simples.
        XCTAssertEqual(link.channels.map(\.name), ["Lead", "Kick", "Clap"])
        // Patterns : « hi hat » prend son nom simple, le pattern 2 ce qui y joue.
        XCTAssertEqual(link.patternList.map(\.name), ["Hi-hat", "Lead"])
        // Mixer : même ordre que le Channel rack ; la piste de groupe juste après les pistes qui lui envoient.
        XCTAssertEqual(link.mixer.map(\.name), ["Master", "Lead", "Kick", "Clap", "Drums Bus", "Insert 5"])
        XCTAssertEqual(link.channels.map(\.mixerTrack), [1, 2, 3], "chaque son suit sa piste")
        // Playlist : chaque piste prend ce qu'elle joue, rangée comme le Channel rack (la mélodie d'abord).
        XCTAssertEqual(link.playlist.map(\.name), ["Lead", "Drums"])
        XCTAssertEqual(controller.lastApply?.playlistUnordered, false)

        controller.undo()
        waitFor(controller, OrganizerWindowTests.isUndone)
        XCTAssertEqual(controller.phase, .undone(nil))
        XCTAssertEqual(link.channels, original.0)
        XCTAssertEqual(link.mixer, original.1)
        XCTAssertEqual(link.patternList, original.2)
        XCTAssertEqual(link.playlist, original.3)
        controller.close()
    }

    func testCaptureUnavailableIsExplained() {
        let link = FakeOrganizerLink()
        var e = env(link, FakeAudio(link: link), saved: { _ in })
        e.audio = { .failure(.failed("L'Organiser écoute FL avec macOS 14.2 ou plus récent : mets macOS à jour.")) }
        let controller = OrganizerController(env: e)
        controller.start()
        XCTAssertEqual(controller.phase, .failed("L'Organiser écoute FL avec macOS 14.2 ou plus récent : mets macOS à jour."))
        XCTAssertEqual(link.log, [], "rien n'est envoyé à FL")
        // FL fermé : Organiser attend qu'il s'ouvre, et commence tout seul.
        var open = false
        e.audio = { open ? .success(FakeAudio(link: link)) : .failure(.flClosed) }
        let waiting = OrganizerController(env: e)
        waiting.start()
        XCTAssertEqual(waiting.phase, .waiting(.openFL))
        open = true
        waitFor(waiting) { if case .failed = $0 { return true } else { return false } }
        XCTAssertEqual(waiting.phase, .failed("Aucun son à organiser dans ce projet."))
        waiting.close()
    }

    /// « Audio du système » : refusée, Organiser attend (sans rien envoyer à FL) et continue dès qu'elle est donnée ;
    /// jamais demandée, la fenêtre de macOS est montrée une fois avant l'écoute.
    func testAudioPermissionIsAskedBeforeListening() {
        let link = FakeOrganizerLink()
        var e = env(link, FakeAudio(link: link), saved: { _ in })
        var permission = AudioCapturePermission.denied
        e.audioPermission = { permission }
        let denied = OrganizerController(env: e)
        denied.start()
        XCTAssertEqual(denied.phase, .waiting(.audioPermission))
        XCTAssertEqual(link.log, [], "rien n'est envoyé à FL")
        permission = .granted
        waitFor(denied) { if case .failed = $0 { return true } else { return false } }
        XCTAssertEqual(denied.phase, .failed("Aucun son à organiser dans ce projet."))
        denied.close()

        permission = .unknown
        var asked: [(Bool) -> Void] = []
        e.requestAudioPermission = { done in asked.append(done); return true }
        let fresh = OrganizerController(env: e)
        fresh.start()
        XCTAssertEqual(fresh.phase, .waiting(.audioPermission))
        XCTAssertEqual(asked.count, 1)
        permission = .granted
        asked[0](true)
        waitFor(fresh) { if case .failed = $0 { return true } else { return false } }
        XCTAssertEqual(asked.count, 1, "demandée une seule fois")
        fresh.close()
        XCTAssertTrue(OrganizerError.noSound.message.contains("Audio du système"))
    }

    /// « Copier le diagnostic » : versions, étape et ce que l'écoute a fait, jamais un nom de son.
    /// L'IA apprend de ses erreurs (demande du propriétaire) : un son changé dans l'aperçu est retenu sans rien
    /// demander (pas partagé : aucun accord) ; « Pas content ? » retient ses corrections et, la case cochée, les
    /// partage (des nombres, jamais un nom) ; Playlist et texte libre vont à l'équipe.
    func testCorrectionsAreLearnedThenShared() throws {
        let link = FakeOrganizerLink()
        link.channels = [ChannelInfo(index: 0, type: 2, mixerTrack: 0, color: RGBColor(r: 1, g: 2, b: 3), name: "Son 0"),
                         ChannelInfo(index: 1, type: 2, mixerTrack: 0, color: RGBColor(r: 4, g: 5, b: 6), name: "Son 1")]
        let audio = FakeAudio(link: link)
        audio.parts = [0: [Float](repeating: 0.3, count: 64), 1: [Float](repeating: 0.25, count: 64)]
        let dossier = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "essai.corrections." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            try? FileManager.default.removeItem(at: dossier)
            defaults.removePersistentDomain(forName: suite)
        }
        let store = CorrectionsIA(url: dossier.appendingPathComponent("corrections-ia.json"), defaults: defaults)
        var shared: [Data] = []
        var team: [(String, String)] = []
        var e = env(link, audio, saved: { _ in })
        // Une empreinte par son (d'après son niveau), les mesures de l'IA, son avis (Drums).
        e.fingerprint = {
            { samples, _ in
                var empreinte = [Float](repeating: 0, count: ClasseurSons.tailleEmpreinte)
                empreinte[Int((samples[0] * 100).rounded())] = 1
                return SoundPrint(mesures: [[Float](repeating: 0.5, count: ClasseurSons.tailleMesures)],
                                  empreinte: empreinte, familleIA: .drums, sorteIA: nil)
            }
        }
        e.corrections = { store }
        e.shareCorrection = { shared.append($0) }
        e.sendFeedback = { team.append(($0, $1)) }
        let controller = OrganizerController(env: e)
        controller.start()
        waitFor(controller) { $0 == .preview }
        XCTAssertEqual(controller.correctable.map(\.index), [0, 1])
        controller.setKind(1, .bass808)
        controller.apply()
        waitFor(controller, OrganizerWindowTests.isApplied)
        XCTAssertEqual(controller.learned, 1, "le son changé dans l'aperçu")
        XCTAssertEqual(store.nombre, 1)
        XCTAssertNil(store.partage, "jamais demandé")
        XCTAssertTrue(shared.isEmpty, "rien ne part sans accord")
        XCTAssertTrue(controller.doneText.contains("1"), controller.doneText)

        XCTAssertTrue(controller.canGiveFeedback)
        var feedback = OrganizerFeedback()
        feedback.reasons = [.kind, .playlist]
        feedback.other = true
        feedback.otherText = "Les clips de voix sont trop bas."
        feedback.fixes = [0: .init(family: .drums, kind: .snare)]
        feedback.share = true
        controller.submitFeedback(feedback)
        XCTAssertEqual(controller.learned, 2)
        XCTAssertEqual(store.nombre, 2)
        XCTAssertEqual(store.partage, true)
        XCTAssertFalse(controller.canGiveFeedback, "une fois")
        XCTAssertEqual(shared.count, 1)
        let corps = try XCTUnwrap(JSONSerialization.jsonObject(with: shared[0]) as? [String: Any])
        XCTAssertEqual(corps["famille"] as? String, "drums")
        XCTAssertEqual(corps["sorte"] as? String, "snare")
        XCTAssertEqual(corps["raisons"] as? String, "kind,playlist")
        XCTAssertFalse(String(decoding: shared[0], as: UTF8.self).contains("Son 0"), "jamais un nom de son")
        XCTAssertEqual(team.count, 1)
        XCTAssertTrue(team[0].0.contains("Playlist") && team[0].0.contains("trop bas"), team[0].0)
        XCTAssertFalse(team[0].1.contains("Son 0"), "diagnostic sans nom")
        // Le même son, la prochaine fois : rangé comme corrigé (Snare), avant toute règle.
        var empreinte = [Float](repeating: 0, count: ClasseurSons.tailleEmpreinte)
        empreinte[30] = 1
        XCTAssertEqual(store.cherche(empreinte)?.sorte, .snare)
        controller.close()
    }

    func testDiagnosticIsCopiedWithoutNames() {
        let link = FakeOrganizerLink()
        link.channels = [ChannelInfo(index: 0, type: 2, mixerTrack: 0, color: RGBColor(r: 1, g: 2, b: 3),
                                     name: "Secret Serum")]
        var e = env(link, FakeAudio(link: link), saved: { _ in })
        var copied: [String] = []
        e.about = { "app 1.0 · audio=granted" }
        e.copy = { copied.append($0) }
        let controller = OrganizerController(env: e)
        controller.start()
        waitFor(controller) { if case .failed = $0 { return true } else { return false } }
        XCTAssertEqual(controller.phase, .failed(OrganizerError.noSound.message), "nom qui ne dit rien : écouté, muet")
        controller.copyDiagnostic()
        let text = try? XCTUnwrap(copied.first)
        XCTAssertTrue(text?.contains("app 1.0 · audio=granted") ?? false)
        XCTAssertTrue(text?.contains("étape=échec") ?? false)
        XCTAssertTrue(text?.contains("sons=1") ?? false)
        XCTAssertTrue(text?.contains("capture=") ?? false)
        XCTAssertFalse(text?.contains("Secret") ?? true, "jamais un nom")
        XCTAssertTrue(controller.copied)
        controller.close()
    }

    func testOrganizeBlockJSON() throws {
        let block = Block(.organize)
        let data = try JSONEncoder().encode(block)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "organize")
        XCTAssertEqual(try JSONDecoder().decode(Block.self, from: data), block)
        let spec = BlockRegistry.spec(.organize)
        XCTAssertTrue(spec.needs(.organize).contains(.lienMIDI))
        XCTAssertTrue(spec.dansLaPalette)
        XCTAssertEqual(spec.category, .fl)
        XCTAssertTrue(PaletteCatalog.items(layout: FakeLayout.qwerty).contains { $0.type == .organize && !$0.soon })
    }

    func testTemplateHasOrganize() throws {
        let gallery = MacroTemplates.gallery(layout: FakeLayout.qwerty)
        let template = try XCTUnwrap(gallery.first { $0.id == MacroTemplates.organizeID })
        let doc = template.make(FakeLayout.qwerty)
        XCTAssertEqual(doc.blocks.map(\.body), [.organize])
        XCTAssertNil(MacroProgram.compile(doc, forbidden: .physical).problem)
    }
}
