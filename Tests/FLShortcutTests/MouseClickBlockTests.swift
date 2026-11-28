import XCTest
@testable import FLShortcut

/// Bloc « Clic de souris » (05/11) : là où est la souris, gauche, droit ou milieu, simple ou double ; même JSON que
/// Windows (MacroModel.cs : « button », « double »).
final class MouseClickBlockTests: XCTestCase {
    func testSameJSONAsWindows() throws {
        let block = Block(.mouseClick(button: .middle, double: true))
        XCTAssertEqual(block.body.params, ["button": .string("middle"), "double": .bool(true)])
        let back = try JSONDecoder().decode([Block].self, from: JSONEncoder().encode([block]))
        XCTAssertEqual(back, [block])
        XCTAssertEqual(BlockRegistry.spec(.mouseClick).parDefaut(), .mouseClick(button: .left, double: false))
    }

    func testEveryButtonHasItsName() {
        let buttons = [PointerButton.left, .right, .middle, PointerButton(number: 3), PointerButton(number: 4)]
        XCTAssertEqual(buttons.map(\.rawValue), ["left", "right", "middle", "4", "5"])
        XCTAssertEqual(Set(buttons.map(\.title)).count, 5)
        XCTAssertEqual(PointerButton(rawValue: "5"), PointerButton(number: 4))
        XCTAssertNil(PointerButton(rawValue: "2"), "le 2 s'écrit « right »")
        XCTAssertNil(PointerButton(rawValue: "33"))
        XCTAssertTrue(BlockRegistry.spec(.mouseClick).plateformes.contains(.windows))
    }

    /// 05/11 : n'importe quel bouton (« si la personne a 5 boutons ») ; le JSON reste lisible par Windows.
    func testASideButtonKeepsItsNumber() throws {
        let block = Block(.mouseClick(button: PointerButton(number: 4), double: false))
        XCTAssertEqual(block.body.params, ["button": .string("5"), "double": .bool(false)])
        let back = try JSONDecoder().decode([Block].self, from: JSONEncoder().encode([block]))
        XCTAssertEqual(back, [block])
    }
}
