// Gouttes du créateur : elles partent du bouton Ajouter, se posent côte à côte, tiennent dans une barre étroite ; le
// verre natif seulement sur macOS 26 avec le verre activé et la transparence non réduite.
import XCTest
@testable import FLShortcut

final class LiquidDropsTests: XCTestCase {
    func testDropsStartInsideTheAddButton() {
        XCTAssertEqual(DropLayout.positions(count: 3, progress: 0, width: 400, size: 30, spacing: 10), [15, 15, 15])
    }

    func testDropsEndSpaced() {
        XCTAssertEqual(DropLayout.positions(count: 3, progress: 1, width: 400, size: 30, spacing: 10), [15, 55, 95])
    }

    func testDropsStayInsideNarrowBar() {
        let p = DropLayout.positions(count: 3, progress: 1, width: 80, size: 30, spacing: 10)
        XCTAssertLessThanOrEqual(p.last! + 15, 80)
        XCTAssertEqual(p.first, 15)
    }

    func testNoDropsNoPositions() {
        XCTAssertTrue(DropLayout.positions(count: 0, progress: 1, width: 400, size: 30, spacing: 10).isEmpty)
    }

    func testDropsPathChoice() {
        XCTAssertTrue(LiquidDrops.useNativeGlass(available: true, glassEnabled: true, reduceTransparency: false))
        XCTAssertFalse(LiquidDrops.useNativeGlass(available: true, glassEnabled: false, reduceTransparency: false))
        XCTAssertFalse(LiquidDrops.useNativeGlass(available: false, glassEnabled: true, reduceTransparency: false))
        XCTAssertFalse(LiquidDrops.useNativeGlass(available: true, glassEnabled: true, reduceTransparency: true))
    }
}
