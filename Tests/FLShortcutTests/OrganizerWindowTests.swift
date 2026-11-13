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
        e.loadFamilyOrder = { SoundFamily.order }               // jamais les réglages du Mac qui lance les essais
        e.saveFamilyOrder = { _ in }
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
            XCTAssertEqual(controller.title, "Organiser")
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
        var fl: Int32? = 100
        var e = env(link, audio, saved: { _ in })
        e.prepareLink = { installed ? .ready(warmUp: 0.5) : .notInstalled }
        e.installLink = { installed = true; return true }
        e.runningFL = { fl }
        // Lien perdu après l'ouverture (« Démarrer » montré) : l'installation est demandée au clic.
        let controller = OrganizerController(env: e)
        controller.start()
        XCTAssertEqual(controller.phase, .setup)
        XCTAssertTrue(controller.canRetry)
        XCTAssertEqual(link.log, [], "rien n'est envoyé à FL")
        // Un clic : installé, puis Organiser attend que FL redémarre, et « Démarrer » continue (sans « Réessayer »).
        controller.installLink()
        XCTAssertEqual(controller.phase, .waiting(.restartFL))
        fl = 200
        waitFor(controller) { $0 == .ready }
        XCTAssertEqual(link.log, [], "rien n'est envoyé à FL avant « Démarrer »")
        controller.start()
        waitFor(controller) { $0 == .preview }
        XCTAssertEqual(controller.members(of: .drums).map(\.name), ["Son 0"])
        XCTAssertFalse(controller.canRetry)
        controller.close()
    }

    /// Retour du 31/10 (la fenêtre se fermait) : après « Installer le lien », Organiser reste ouvert, FL devant (⌘Q le
    /// quitte lui), attend qu'il soit quitté puis rouvert sans rien lui envoyer, montre MIDI Settings tant qu'il ne
    /// répond pas, puis continue tout seul.
    func testInstallWaitsForFLRestartThenShowsMIDISettings() {
        let link = FakeOrganizerLink()
        link.channels = [ChannelInfo(index: 0, type: 2, mixerTrack: 0, color: RGBColor(r: 1, g: 2, b: 3), name: "Son 0")]
        let audio = FakeAudio(link: link)
        audio.parts = [0: [Float](repeating: 0.3, count: 64)]
        var installed = false
        var fl: Int32? = 100
        var answering = false
        var focused = 0
        var opened = 0
        var listenTries = 0
        var prepared = 0
        var e = env(link, audio, saved: { _ in })
        e.linkInstalled = { installed }
        e.prepareLink = {
            prepared += 1
            return installed ? .ready(warmUp: 0) : .notInstalled
        }
        e.installLink = { installed = true; return true }
        e.runningFL = { fl }
        e.openFL = { opened += 1 }
        e.focusFL = { focused += 1 }
        e.audio = {
            listenTries += 1
            return answering ? .success(audio) : .failure(.noResponse)
        }
        // 2e retour du 01/11 : lien absent → « Installer le lien » d'abord, avant « Démarrer ».
        let controller = OrganizerController(env: e)
        XCTAssertEqual(controller.phase, .setup)
        controller.start()
        XCTAssertEqual(controller.phase, .setup, "« Démarrer » n'existe pas avant l'installation")
        controller.installLink()
        XCTAssertEqual(controller.phase, .waiting(.restartFL))
        XCTAssertTrue(controller.guidingLink)
        XCTAssertEqual(focused, 1, "FL devant : ⌘Q quitte FL, jamais FL Shortcuts")
        // FL tourne encore : il attend, sans rien essayer.
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(controller.phase, .waiting(.restartFL))
        XCTAssertFalse(controller.flClosedForRestart)
        XCTAssertEqual(listenTries, 0)
        // Quitté : « Ouvrir FL Studio ».
        fl = nil
        wait(for: [expectation(for: NSPredicate { _, _ in controller.flClosedForRestart }, evaluatedWith: nil)],
             timeout: 5)
        controller.openFL()
        XCTAssertEqual(opened, 1)
        XCTAssertEqual(listenTries, 0)
        // Un nouveau FL : « Démarrer », toujours sans lien (aucun port avant ce clic).
        fl = 200
        waitFor(controller) { $0 == .ready }
        XCTAssertFalse(controller.flClosedForRestart)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(controller.phase, .ready)
        XCTAssertEqual(prepared, 0, "rien demandé à FL avant « Démarrer »")
        XCTAssertEqual(listenTries, 0)
        // « Démarrer » : MIDI Settings, gardé tant que FL ne répond pas.
        controller.start()
        waitFor(controller) { $0 == .waiting(.midiSettings) }
        XCTAssertGreaterThan(prepared, 0)
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertEqual(controller.phase, .waiting(.midiSettings))
        XCTAssertGreaterThan(listenTries, 0)
        // Les 4 cases réglées : Organiser continue tout seul.
        answering = true
        waitFor(controller) { $0 == .preview }
        XCTAssertFalse(controller.guidingLink)
        XCTAssertEqual(OrganizerController.phaseCode(.waiting(.midiSettings)), "attente-midiSettings")
        controller.close()
    }

    /// FL fermé pendant l'installation du lien : « Ouvrir FL Studio », puis « Démarrer » dès qu'il tourne.
    func testInstallWithFLClosedThenStart() {
        let link = FakeOrganizerLink()
        var installed = false
        var fl: Int32?
        var e = env(link, FakeAudio(link: link), saved: { _ in })
        e.linkInstalled = { installed }
        e.prepareLink = { installed ? .ready(warmUp: 0) : .notInstalled }
        e.installLink = { installed = true; return true }
        e.runningFL = { fl }
        let controller = OrganizerController(env: e)
        controller.installLink()
        XCTAssertEqual(controller.phase, .waiting(.restartFL))
        XCTAssertTrue(controller.flClosedForRestart)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(controller.phase, .waiting(.restartFL))
        fl = 300
        waitFor(controller) { $0 == .ready }
        XCTAssertFalse(controller.flClosedForRestart)
        controller.close()
    }

    /// 13/11 : chaque case de la grille a son numéro de FL (`FLIconNumbers`), écrit dans la copie : une icône choisie
    /// ne demande plus « Enregistrement de l'écran » (avant, capture du 31/10 : « Autoriser » dans l'aperçu).
    func testKnownIconsNeverAskForScreenRecording() throws {
        let link = FakeOrganizerLink()
        var e = env(link, FakeAudio(link: link), saved: { _ in })
        var asked = 0
        e.screenAllowed = { false }
        e.askScreen = { asked += 1 }
        let controller = OrganizerController(env: e)
        controller.showDemo("apercu")
        XCTAssertFalse(controller.iconsNeedScreen, "aucune icône choisie")
        let family = try XCTUnwrap(controller.presentFamilies.first)
        controller.updateStyle(family) { $0.icon = FLIcon(code: "0-0") }
        XCTAssertFalse(controller.iconsNeedScreen, "Reset n'est pas une icône")
        for code in ["7-4", "1-5", "12-6"] {
            controller.updateStyle(family) { $0.icon = FLIcon(code: code) }
            XCTAssertFalse(controller.iconsNeedScreen, "\(code) : numéro connu, écrite dans la copie")
        }
        XCTAssertEqual(asked, 0)
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
        var fl: Int32? = 100
        var e = env(link, audio, saved: { _ in })
        e.runningFL = { fl }
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
        // FL relancé : « Démarrer », puis l'analyse.
        fl = 200
        waitFor(controller) { $0 == .ready }
        controller.start()
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

    /// Demande du propriétaire (25/10) : chaque son montre sa piste du Mixer (sa case) et peut en changer, chaque
    /// famille a son départ, « Rangement automatique » oublie tout ; « Écrire… » donne un nom ; l'ordre des familles
    /// glissées est gardé.
    func testPlacesNamesAndFamilyOrderInThePreview() {
        let link = FakeOrganizerLink()
        let gray = RGBColor(r: 9, g: 9, b: 9)
        link.channels = ["Serum Lead", "BEAM KICK", "ZEBRA 808"].enumerated().map {
            ChannelInfo(index: $0.offset, type: 2, mixerTrack: $0.offset + 1, color: gray, name: $0.element)
        }
        link.mixer = (0...40).map { MixerTrackInfo(index: $0, color: gray, name: $0 == 0 ? "Master" : "Insert \($0)") }
        var savedOrder: [SoundFamily] = []
        var e = env(link, FakeAudio(link: link), saved: { _ in })
        e.loadFamilyOrder = { [.drums] }
        e.saveFamilyOrder = { savedOrder = $0 }
        let controller = OrganizerController(env: e)
        XCTAssertEqual(controller.options.familyOrder, [.drums, .vocals, .melody, .bass, .fx, .unsure])
        controller.start()
        waitFor(controller) { $0 == .preview }
        XCTAssertEqual(controller.presentFamilies, [.drums, .melody, .bass])
        XCTAssertNotNil(controller.mixerSlot(of: 1))
        controller.setSlot(1, 20)
        XCTAssertEqual(controller.members(of: .drums).first?.slot, 20)
        XCTAssertEqual(controller.members(of: .drums).first?.pinned, true)
        controller.setMixerStart(.melody, 30)
        XCTAssertEqual(controller.mixerRange(of: .melody)?.lowerBound, 30)
        XCTAssertTrue(controller.placesChosen)
        controller.autoArrange()
        XCTAssertFalse(controller.placesChosen)
        XCTAssertNil(controller.style(of: .melody).mixerStart)
        controller.setName(1, "  Boom  ")
        XCTAssertEqual(controller.members(of: .drums).first?.newName, "Boom")
        XCTAssertEqual(controller.members(of: .drums).first?.written, true)
        controller.setName(1, "")
        XCTAssertNil(controller.names[1])
        controller.moveFamily(.bass, onto: .drums)
        XCTAssertEqual(controller.presentFamilies, [.bass, .drums, .melody])
        controller.shiftFamily(.melody, by: -1)
        XCTAssertEqual(controller.presentFamilies, [.bass, .melody, .drums])
        controller.setName(0, "Ma mélodie")
        controller.apply()
        waitFor(controller, OrganizerWindowTests.isApplied)
        XCTAssertEqual(savedOrder.prefix(3), [.bass, .melody, .drums])
        XCTAssertEqual(link.channels.map(\.name), ["808", "Ma mélodie", "Kick"])
        controller.close()
    }

    /// Demande du 01/11 : un son glissé dans une autre famille y passe et va dans le bus de cette famille, plus dans
    /// l'ancien ; sa case et ses sorties choisies à la main sont oubliées. La 808 posée sur Basse va dans le bus de la
    /// Basse et garde son nom.
    func testSoundMovedToAnotherFamilyGoesToItsBus() {
        let link = FakeOrganizerLink()
        let gray = RGBColor(r: 9, g: 9, b: 9)
        link.channels = ["Serum Lead", "BEAM KICK", "ZEBRA 808", "BIG CLAP"].enumerated().map {
            ChannelInfo(index: $0.offset, type: 2, mixerTrack: $0.offset + 1, color: gray, name: $0.element)
        }
        link.mixer = (0...40).map { MixerTrackInfo(index: $0, color: gray, name: $0 == 0 ? "Master" : "Insert \($0)") }
        let controller = OrganizerController(env: env(link, FakeAudio(link: link), saved: { _ in }))
        controller.start()
        waitFor(controller) { $0 == .preview }
        func bus(of index: Int) -> SoundFamily? {
            let plan = controller.plan
            guard let track = controller.soundTrack(of: index, in: plan) else { return nil }
            return plan.mixer.routes[track]?.compactMap { plan.mixer.buses[$0] }.first
        }
        XCTAssertEqual(bus(of: 1), .drums)
        XCTAssertEqual(bus(of: 2), .drums, "la 808 dans le bus des Drums")

        controller.setSlot(1, 30)
        controller.options.mixerEdits.routes[2] = [0]
        controller.moveSound(1, to: .melody)
        XCTAssertEqual(controller.families[1], .melody)
        XCTAssertEqual(Set(controller.members(of: .melody).map(\.name)), ["Serum Lead", "BEAM KICK"])
        XCTAssertNil(controller.slots[1], "sa case choisie chez les Drums est oubliée")
        XCTAssertNil(controller.options.mixerEdits.routes[2], "ses sorties changées à la main aussi")
        XCTAssertEqual(bus(of: 1), .melody, "relié au bus des Mélodies, plus à celui des Drums")

        controller.moveSound(2, to: .bass)
        XCTAssertEqual(controller.families[2], .bass)
        XCTAssertEqual(bus(of: 2), .bass, "la 808 dans le bus de la Basse")
        XCTAssertEqual(controller.members(of: .bass).first?.newName, "808", "elle garde son nom")
        let before = controller.families
        controller.moveSound(3, to: .drums)
        XCTAssertEqual(controller.families, before, "déjà dans sa famille : rien ne change")
        controller.close()
    }

    /// Tuto en images (29/10) : à la première ouverture, avant « Démarrer » (rien n'est envoyé à FL) ; vu une fois,
    /// il n'est plus montré tout seul ; revu depuis Options, il ne relance rien.
    func testTutorialFirstThenStart() throws {
        let suite = "fl.essai.tuto.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertTrue(OrganizerTutorial.shouldShow(defaults: defaults))
        let link = FakeOrganizerLink()
        link.v14 = false
        let controller = OrganizerController(env: env(link, FakeAudio(link: link), saved: { _ in }))
        controller.showTutorial()
        XCTAssertTrue(controller.tutorial)
        XCTAssertEqual(controller.phase, .ready)
        controller.finishTutorial(defaults: defaults)
        XCTAssertFalse(controller.tutorial)
        XCTAssertFalse(OrganizerTutorial.shouldShow(defaults: defaults))
        XCTAssertEqual(controller.phase, .ready, "tuto fini : « Démarrer », rien de lancé")
        controller.start()
        waitFor(controller) { $0 == .waiting(.restartFL) }
        controller.showTutorial()
        controller.finishTutorial(defaults: defaults)
        XCTAssertFalse(controller.tutorial)
        XCTAssertEqual(controller.phase, .waiting(.restartFL), "revu : rien n'est relancé")
        controller.close()
    }

    /// Retour du 01/11 (FL saccadait tant qu'il voyait « FL Shortcuts Link ») : le lien avec FL seulement entre
    /// « Démarrer » et la fermeture de l'Organiser, rendu une fois FL remis comme avant.
    func testLinkOnlyBetweenStartAndClose() {
        let link = FakeOrganizerLink()
        link.v14 = false
        var e = env(link, FakeAudio(link: link), saved: { _ in })
        var prepared = 0, released = 0
        e.prepareLink = {
            prepared += 1
            return .ready(warmUp: 0)
        }
        e.releaseLink = { released += 1 }
        let controller = OrganizerController(env: e)
        XCTAssertEqual(controller.phase, .ready)
        XCTAssertEqual(prepared, 0, "ouvert : rien demandé à FL avant « Démarrer »")
        controller.start()
        waitFor(controller) { $0 == .waiting(.restartFL) }
        XCTAssertGreaterThan(prepared, 0)
        XCTAssertEqual(released, 0)
        controller.close()
        let deadline = Date().addingTimeInterval(3)
        while released == 0, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertEqual(released, 1, "fermé : le lien est rendu")
        controller.start()
        XCTAssertEqual(controller.phase, .waiting(.restartFL), "fermé : « Démarrer » ne relance rien")
    }

    /// Retour du 01/11 au soir (« quand on valide Organiser ça rame toujours ») : le lien est rendu dès que tout est
    /// rangé, sans attendre la fermeture de la fenêtre ; « Revenir comme avant » le reprend le temps de remettre FL
    /// comme avant, puis le rend.
    func testLinkReleasedAsSoonAsOrganized() {
        let link = FakeOrganizerLink()
        link.channels = [ChannelInfo(index: 0, type: 2, mixerTrack: 0, color: RGBColor(r: 1, g: 2, b: 3), name: "Son 0"),
                         ChannelInfo(index: 1, type: 2, mixerTrack: 0, color: RGBColor(r: 4, g: 5, b: 6), name: "Son 1")]
        let audio = FakeAudio(link: link)
        audio.parts = [0: [Float](repeating: 0.3, count: 64), 1: [Float](repeating: 0.3, count: 64)]
        var e = env(link, audio, saved: { _ in })
        var released = 0, retaken = 0
        e.releaseLink = { released += 1 }
        e.useLinkAgain = {
            retaken += 1
            return true
        }
        let controller = OrganizerController(env: e)
        controller.start()
        waitFor(controller) { $0 == .preview }
        // 13/11 (« quand j'ouvre organiser et que je ferme ça re rame… si non utilisé il faut le fermer directement ») :
        // l'aperçu n'envoie rien à FL, le lien est rendu dès la fin de l'écoute et repris pour « Organiser ».
        XCTAssertEqual(released, 1, "aperçu : le lien est rendu tout de suite")
        XCTAssertFalse(controller.holdsLink)
        controller.apply()
        waitFor(controller, OrganizerWindowTests.isApplied)
        XCTAssertEqual(retaken, 1, "« Organiser » : le lien de nouveau")
        XCTAssertEqual(released, 2, "rangé : le lien est rendu tout de suite")
        XCTAssertTrue(controller.canUndo)
        controller.undo()
        waitFor(controller, OrganizerWindowTests.isUndone)
        XCTAssertEqual(controller.phase, .undone(nil))
        XCTAssertEqual(retaken, 2, "revenir comme avant : le lien de nouveau")
        XCTAssertEqual(released, 3, "puis rendu")
        controller.close()
    }

    /// 13/11 (« Pas content ? » en pages, maquette validée) : les choix gardés reviennent à l'ouverture ; « Annuler »
    /// remet tout comme avant ; « C'est noté » garde l'ordre des familles, le bus par famille et le pré-master.
    func testFeedbackPagesKeepOrRestoreChoices() {
        let link = FakeOrganizerLink()
        var e = env(link, FakeAudio(link: link), saved: { _ in })
        var savedChoices: (buses: Bool, premaster: Bool)?
        var savedOrder: [SoundFamily]?
        e.loadMixerChoices = { (buses: false, premaster: false) }
        e.saveMixerChoices = { savedChoices = (buses: $0, premaster: $1) }
        e.saveFamilyOrder = { savedOrder = $0 }
        let controller = OrganizerController(env: e)
        XCTAssertFalse(controller.options.buses, "le choix gardé revient")
        XCTAssertFalse(controller.options.premaster)
        let styles = controller.styles, options = controller.options
        controller.options.buses = true
        controller.setFamilyOrder([.drums, .bass, .melody, .vocals, .fx])
        XCTAssertEqual(controller.options.familyOrder.first, .drums)
        controller.restore(styles: styles, options: options)
        XCTAssertFalse(controller.options.buses, "Annuler : comme à l'ouverture")
        XCTAssertNotEqual(controller.options.familyOrder.first, .drums)
        controller.setFamilyOrder([.drums, .bass, .melody, .vocals, .fx])
        controller.options.buses = true
        controller.options.premaster = true
        controller.submitFeedback(OrganizerFeedback())
        XCTAssertEqual(savedOrder?.first, .drums, "C'est noté : l'ordre gardé")
        XCTAssertEqual(savedChoices?.buses, true)
        XCTAssertEqual(savedChoices?.premaster, true)
    }

    /// Fermé sans avoir démarré : rien n'a été demandé à FL, le lien est rendu quand même (aucun port).
    func testCloseBeforeStartReleasesLink() {
        let link = FakeOrganizerLink()
        var e = env(link, FakeAudio(link: link), saved: { _ in })
        var prepared = 0, released = 0
        e.prepareLink = {
            prepared += 1
            return .ready(warmUp: 0)
        }
        e.releaseLink = { released += 1 }
        let controller = OrganizerController(env: e)
        controller.close()
        let deadline = Date().addingTimeInterval(3)
        while released == 0, Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
        XCTAssertEqual(prepared, 0)
        XCTAssertEqual(released, 1)
    }

    /// Les quatre pages du tuto ont leur image, en français et en anglais (Resources/*.lproj, copiés par build.sh).
    func testTutorialPagesHaveTheirImages() {
        let pages = OrganizerTutorial.pages
        XCTAssertEqual(pages.map(\.id), [1, 2, 3, 4])
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
        for language in ["fr", "en"] {
            for page in pages {
                let url = root.appendingPathComponent("Resources/\(language).lproj/\(page.imageName).png")
                let image = NSImage(contentsOf: url)
                XCTAssertNotNil(image, "\(language) \(page.imageName)")
                XCTAssertEqual(image.map { $0.size.width / $0.size.height } ?? 0, 16 / 9, accuracy: 0.01)
            }
        }
    }

    /// Écrans de démonstration (captures de la CI), avec les sons d'exemple : chacun se construit et se dessine.
    /// Sur la CI, « apercu » et « fini » restaient sur l'écran de l'écoute ; ce test dit si leur vue plante.
    func testDemoScreensRender() {
        let link = FakeOrganizerLink()
        let controller = OrganizerController(env: env(link, FakeAudio(link: link), saved: { _ in }))
        for screen in ["demarrer", "tuto", "installer", "attente", "aide", "ecoute", "apercu", "fini"] {
            controller.showDemo(screen)
            XCTAssertEqual(controller.tutorial, screen == "tuto", screen)
            if screen == "demarrer" { XCTAssertEqual(controller.phase, .ready) }
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
        XCTAssertFalse(controller.playlistTooBig, "aucun avertissement : la Playlist tient dans FL")
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
        XCTAssertTrue(OrganizerError.noSound.message.contains("Enregistrement de l'écran et audio du système"))
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

    /// « Pas content ? » montre tous les sons (vidéo du 30/10), même ceux rangés d'après leur nom ; corrigé, un tel son
    /// est retenu d'après son nom et rangé pareil la fois suivante (règle « corrige-nom », un numéro dans le diagnostic).
    func testNamedSoundCorrectedByName() throws {
        let link = FakeOrganizerLink()
        link.channels = [ChannelInfo(index: 0, type: 2, mixerTrack: 0, color: RGBColor(r: 1, g: 2, b: 3), name: "Kick Boom"),
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
        var e = env(link, audio, saved: { _ in })
        e.corrections = { store }
        let controller = OrganizerController(env: e)
        controller.start()
        waitFor(controller) { $0 == .preview }
        XCTAssertEqual(controller.correctable.map(\.index), [0, 1], "tous les sons")
        XCTAssertEqual(controller.result?.items.first { $0.index == 0 }?.byName, true)
        controller.apply()
        waitFor(controller, OrganizerWindowTests.isApplied)
        var feedback = OrganizerFeedback()
        feedback.reasons = [.family]
        feedback.fixes = [0: .init(family: .fx, kind: nil)]
        controller.submitFeedback(feedback)
        XCTAssertEqual(store.cherche(nom: "Kick Boom")?.famille, .fx)
        controller.close()

        // Le même projet, rouvert tel quel (l'Organiser a renommé les sons de la copie, pas ceux de l'original).
        let link2 = FakeOrganizerLink()
        link2.channels = link.channels.map { ChannelInfo(index: $0.index, type: $0.type, mixerTrack: 0, color: $0.color,
                                                         name: $0.index == 0 ? "Kick Boom" : "Son 1") }
        let audio2 = FakeAudio(link: link2)
        audio2.parts = audio.parts
        var e2 = env(link2, audio2, saved: { _ in })
        e2.corrections = { store }
        let again = OrganizerController(env: e2)
        again.start()
        waitFor(again) { $0 == .preview }
        XCTAssertEqual(again.result?.items.first { $0.index == 0 }?.family, .fx, "rangé comme corrigé")
        XCTAssertTrue(again.diagnosticText.contains("c0:corrige-nom"), again.diagnosticText)
        XCTAssertFalse(again.diagnosticText.contains("Kick Boom"), "jamais un nom de son")
        again.close()
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

    /// 01/11 : les 4 cases de MIDI Settings découpées dans l'image, à la même place quelle que soit sa taille.
    func testMIDISettingsCropsFollowTheImageSize() {
        XCTAssertEqual(MIDISettingsCrops.crops.map(\.id), [1, 2, 3, 4])
        let r = CGRect(x: 1090, y: 478, width: 250, height: 112)
        XCTAssertEqual(MIDISettingsCrops.pixelRect(r, imageWidth: 1428), r)
        XCTAssertEqual(MIDISettingsCrops.pixelRect(r, imageWidth: 714), CGRect(x: 545, y: 239, width: 125, height: 56))
        for crop in MIDISettingsCrops.crops {
            XCTAssertLessThanOrEqual(crop.rect.maxX, 1428, "case \(crop.id) dans l'image")
            XCTAssertLessThanOrEqual(crop.rect.maxY, 1684, "case \(crop.id) dans l'image")
        }
    }
}
