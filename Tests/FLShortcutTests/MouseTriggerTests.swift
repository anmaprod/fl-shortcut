import CoreGraphics
import XCTest
@testable import FLShortcut

/// Raccourcis et macros lancés par un bouton de souris (05/11) : molette cliquée et boutons du côté codés comme des
/// touches (KeyCombo.mouseBase), seulement comme déclencheur.
final class MouseTriggerTests: XCTestCase {
    private let side = KeyCombo(mouseButton: 3, flags: [])!          // le 4e bouton (côté, « précédent »)

    func testMouseButtonsAreTriggersNeverTargets() {
        XCTAssertEqual(side.keyCode, 203)
        XCTAssertEqual(side.mouseButton, 3)
        XCTAssertTrue(side.isValidTrigger)
        XCTAssertFalse(side.isValidKey, "jamais envoyé à FL")
        XCTAssertFalse(side.isTypingKey)
        XCTAssertNil(KeyCombo(mouseButton: 0, flags: []), "clic gauche : jamais un raccourci")
        XCTAssertNil(KeyCombo(mouseButton: 1, flags: []), "clic droit : jamais un raccourci")
        XCTAssertNil(KeyCombo(mouseButton: 32, flags: []))
        XCTAssertNil(KeyCombo(keyCode: 40).mouseButton, "une touche n'est pas un bouton")
        let withShift = KeyCombo(mouseButton: 2, flags: .maskShift)!
        XCTAssertTrue(withShift.shift)
        XCTAssertTrue(withShift.isMouseButton)
    }

    func testNamesAndJSON() throws {
        let wheel = try XCTUnwrap(KeyNames.mouseName(202))
        let fourth = try XCTUnwrap(KeyNames.mouseName(203))
        XCTAssertNotEqual(wheel, fourth)
        XCTAssertTrue(fourth.contains("4"), fourth)
        XCTAssertEqual(KeyNames.name(for: 203), fourth)
        XCTAssertNil(KeyNames.mouseName(40))
        let back = try JSONDecoder().decode(KeyCombo.self, from: JSONEncoder().encode(side))
        XCTAssertEqual(back, side)
    }

    func testABareMouseButtonIsAValidShortcut() {
        let context = AnalysisContext(toggle: KeyCombo(keyCode: 3, command: true, option: true, control: true),
                                      forbidden: .physical, conflicts: .empty, availability: { _ in .available })
        let remap = Remap(trigger: side, sends: KeyCombo(keyCode: 1, control: true))
        XCTAssertEqual(ShortcutAnalyzer.analyze([remap], context: context)[remap.id], [])
    }

    func testRouterRunsTheShortcutOnPressAndSwallowsTheRelease() {
        var config = TapConfig()
        config.enabled = true
        let target = KeyCombo(keyCode: 1, control: true)
        config.index = ShortcutIndex(remaps: [Remap(trigger: side, sends: target)], blocked: [])
        var router = KeyRouter()
        let down = RouterInput(kind: .down, combo: side, isRepeat: false, isOwn: false, targetIsFL: true)
        XCTAssertEqual(router.route(down, config: config, link: .offline),
                       RouterDecision(swallow: true, effects: [.post(target)]))
        let up = RouterInput(kind: .up, combo: KeyCombo(keyCode: side.keyCode), isRepeat: false, isOwn: false,
                             targetIsFL: true)
        XCTAssertEqual(router.route(up, config: config, link: .offline), .swallowOnly)
        // Un autre bouton, sans raccourci : il reste à FL.
        let other = RouterInput(kind: .down, combo: KeyCombo(mouseButton: 4, flags: [])!, isRepeat: false, isOwn: false,
                                targetIsFL: true)
        XCTAssertEqual(router.route(other, config: config, link: .offline), .pass)
    }
}
