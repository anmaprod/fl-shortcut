// Interface : textes de l'en-tête de page, couleurs des rubriques, règle du verre (coupé = tout opaque).
import SwiftUI
import XCTest
@testable import FLShortcut

final class AppearanceTests: XCTestCase {
    func testPageSummaryCountsInFrench() {
        XCTAssertEqual(PageSummary.count(1, modified: 0), "1 raccourci")
        XCTAssertEqual(PageSummary.count(34, modified: 0), "34 raccourcis")
        XCTAssertEqual(PageSummary.count(34, modified: 1), "34 raccourcis · 1 modifié")
        XCTAssertEqual(PageSummary.count(34, modified: 3), "34 raccourcis · 3 modifiés")
    }

    func testEachSidebarItemHasItsOwnColor() {
        let items = FLSection.allCases.map(SidebarItem.section) + [SidebarItem.custom]
        XCTAssertEqual(Set(items.map(\.tint)).count, items.count, "une couleur par rubrique")
    }

    func testCardRowPositions() {
        XCTAssertEqual(CardRowPosition.position(index: 0, count: 1), .single)
        XCTAssertEqual(CardRowPosition.position(index: 0, count: 3), .first)
        XCTAssertEqual(CardRowPosition.position(index: 1, count: 3), .middle)
        XCTAssertEqual(CardRowPosition.position(index: 2, count: 3), .last)
    }

    func testWindowStaysOpaqueWithoutGlassOrWithReducedTransparency() {
        XCTAssertFalse(Appearance.translucentWindow(glass: false, reduceTransparency: false))
        XCTAssertFalse(Appearance.translucentWindow(glass: true, reduceTransparency: true))
        if #available(macOS 15.0, *) {
            XCTAssertTrue(Appearance.translucentWindow(glass: true, reduceTransparency: false))
        }
    }
}
