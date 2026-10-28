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

    /// « Modifier les raccourcis… » du menu de l'icône : la page de raccourcis déjà ouverte reste, sinon Général
    /// (retour de l'utilisateur : la fenêtre restait sur Macros).
    func testShortcutsLinkLeavesOtherPages() {
        XCTAssertEqual(ShortcutsLink.page(from: .macros), .section(.general))
        XCTAssertEqual(ShortcutsLink.page(from: .community), .section(.general))
        XCTAssertEqual(ShortcutsLink.page(from: nil), .section(.general), "créateur ouvert, ou recherche")
        XCTAssertEqual(ShortcutsLink.page(from: .section(.mixer)), .section(.mixer))
        XCTAssertEqual(ShortcutsLink.page(from: .custom), .custom)
    }

    func testCardRowPositions() {
        XCTAssertEqual(CardRowPosition.position(index: 0, count: 1), .single)
        XCTAssertEqual(CardRowPosition.position(index: 0, count: 3), .first)
        XCTAssertEqual(CardRowPosition.position(index: 1, count: 3), .middle)
        XCTAssertEqual(CardRowPosition.position(index: 2, count: 3), .last)
    }

    /// Verre dessiné sur les cartes seulement avec l'effet Liquid Glass, sans Réduire la transparence ni Contraste
    /// élevé (sinon les cartes grises de toujours).
    func testGlassPlatesOnlyWithGlassAndNormalTransparency() {
        XCTAssertTrue(GlassPlate.on(glass: true, reduceTransparency: false, increasedContrast: false))
        XCTAssertFalse(GlassPlate.on(glass: false, reduceTransparency: false, increasedContrast: false))
        XCTAssertFalse(GlassPlate.on(glass: true, reduceTransparency: true, increasedContrast: false))
        XCTAssertFalse(GlassPlate.on(glass: true, reduceTransparency: false, increasedContrast: true))
    }
}
