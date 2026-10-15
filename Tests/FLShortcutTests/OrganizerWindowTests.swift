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
        OrganizerEnvironment(link: { link }, audio: { .success(audio) },
                             classify: { OrganizerWindowTests.classify },
                             moveUp: { _ in { count in link.moveSelectedUp(count) } },
                             timing: OrganizerSession.Timing(listen: 0.01, testNote: 0.01, tail: 0.01, slice: 0.01),
                             sleep: { _ in }, escapePressed: { false },
                             loadStyles: { FamilyStyles.initial }, saveStyles: saved)
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
            XCTAssertEqual(controller.presentFamilies, [.drums, .bass])
            controller.updateStyle(.drums) { $0.fade = black }
            controller.apply()
            waitFor(controller, OrganizerWindowTests.isApplied)
            XCTAssertEqual(controller.phase, .applied(nil))
            XCTAssertEqual(saved?[.drums]?.fade, black)
            XCTAssertEqual(link.channels.map(\.color), [drums, bass])

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

    func testCaptureUnavailableIsExplained() {
        let link = FakeOrganizerLink()
        var e = env(link, FakeAudio(link: link), saved: { _ in })
        e.audio = { .failure(.failed("FL Studio n'est pas ouvert.")) }
        let controller = OrganizerController(env: e)
        controller.start()
        XCTAssertEqual(controller.phase, .failed("FL Studio n'est pas ouvert."))
        XCTAssertEqual(link.log, [], "rien n'est envoyé à FL")
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
