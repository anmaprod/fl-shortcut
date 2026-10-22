// Gouttes du créateur : le verre natif seulement sur macOS 26 avec le verre activé et la transparence non réduite.
import XCTest
@testable import FLShortcut

final class LiquidDropsTests: XCTestCase {
    func testDropsPathChoice() {
        XCTAssertTrue(LiquidDrops.useNativeGlass(available: true, glassEnabled: true, reduceTransparency: false))
        XCTAssertFalse(LiquidDrops.useNativeGlass(available: true, glassEnabled: false, reduceTransparency: false))
        XCTAssertFalse(LiquidDrops.useNativeGlass(available: false, glassEnabled: true, reduceTransparency: false))
        XCTAssertFalse(LiquidDrops.useNativeGlass(available: true, glassEnabled: true, reduceTransparency: true))
    }
}
