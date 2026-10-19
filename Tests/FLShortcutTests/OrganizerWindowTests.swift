import Combine
import XCTest
@testable import FLShortcut

/// Organiser : contrôleur de la fenêtre (sans fenêtre), bloc « Organiser la page ouverte » et son modèle.
final class OrganizerWindowTests: XCTestCase {
    private static func classify(_ samples: [Float], _ rate: Double) -> (family: SoundFamily, confidence: Double) {
        samples.isEmpty ? (.unsure, 0) : (.drums, 0.9)
    }

    private func env(_ link: FakeOrganizerLink, _ audio: FakeAudio,
                     saved: @escaping ([SoundFamily: FamilyStyle]) -> Void) -> OrganizerEnvironment {
        var e = OrganizerEnvironment(link: { link }, audio: { .success(audio) },
                                     classify: { OrganizerWindowTests.classify },
                                     moveUp: { _ in { count in link.moveSelectedUp(count) } },
                                     timing: OrganizerSession.Timing(listen: 0.01, testNote: 0.01, tail: 0.01, slice: 0.01),
                                     sleep: { _ in }, escapePressed: { false },
                                     loadStyles: { FamilyStyles.initial }, saveStyles: saved)
        e.waitInterval = 0.05
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
            XCTAssertEqual(controller.title, "Organiser le Channel rack")
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

            XCTAssertTrue(controller.canUndo)
            controller.undo()
            waitFor(controller, OrganizerWindowTests.isUndone)
            XCTAssertEqual(controller.phase, .undone(nil))
            XCTAssertFalse(controller.canUndo)
            XCTAssertEqual(link.channels.map(\.color), [first, second])

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

    func testFailureCanBeRetried() {
        let link = FakeOrganizerLink()
        link.window = .browser
        let controller = OrganizerController(env: env(link, FakeAudio(link: link), saved: { _ in }))
        controller.start()
        // Aucune page à organiser devant : Organiser attend, puis continue tout seul quand elle s'ouvre.
        waitFor(controller) { $0 == .waiting(.openPage) }
        XCTAssertTrue(OrganizerError.refused(1).message.contains("Playlist"))
        XCTAssertTrue(controller.canRetry)
        link.window = .channelRack
        waitFor(controller) { if case .failed = $0 { return true } else { return false } }
        XCTAssertEqual(controller.phase, .failed("Aucun son à écouter dans le Channel rack."))
        controller.close()
    }

    func testPlaylistPreviewNamesAndApply() {
        let link = FakeOrganizerLink()
        link.window = .playlist
        let gray = RGBColor(r: 9, g: 9, b: 9)
        link.playlist = (0..<3).map { PlaylistTrackInfo(index: $0, selected: false, color: gray, name: "Track \($0 + 1)") }
        let audio = FakeAudio(link: link)
        audio.tracks = [0: (from: 0, samples: [Float](repeating: 0.3, count: 64)),
                        2: (from: 0, samples: [Float](repeating: 0.3, count: 64))]
        var e = env(link, audio, saved: { _ in })
        e.nameDrum = { { _, _ in .snare } }
        let controller = OrganizerController(env: e)
        controller.start()
        waitFor(controller) { $0 == .preview }
        XCTAssertEqual(controller.title, "Organiser la Playlist")
        XCTAssertEqual(controller.members(of: .drums).map(\.newName), ["Snare", "Snare 2"])
        controller.renameTracks = false
        XCTAssertEqual(controller.members(of: .drums).map(\.newName), [nil, nil])
        controller.renameTracks = true
        controller.apply()
        waitFor(controller, OrganizerWindowTests.isApplied)
        XCTAssertEqual(controller.phase, .applied(nil))
        XCTAssertEqual(link.playlist.map(\.name), ["Snare", "Track 2", "Snare 2"])
        controller.undo()
        waitFor(controller, OrganizerWindowTests.isUndone)
        XCTAssertEqual(link.playlist.map(\.name), ["Track 1", "Track 2", "Track 3"])
        XCTAssertEqual(link.playlist.map(\.color), [gray, gray, gray])
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
        XCTAssertEqual(waiting.phase, .failed("Aucun son à écouter dans le Channel rack."))
        waiting.close()
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
