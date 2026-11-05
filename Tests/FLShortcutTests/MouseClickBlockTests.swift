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
        XCTAssertEqual(PointerButton.allCases.map(\.rawValue), ["left", "right", "middle"])
        XCTAssertEqual(Set(PointerButton.allCases.map(\.title)).count, 3)
        XCTAssertTrue(BlockRegistry.spec(.mouseClick).plateformes.contains(.windows))
    }
}
