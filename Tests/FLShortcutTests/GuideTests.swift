import XCTest
@testable import FLShortcut

/// Guide de l'appli : « Bienvenue » puis une page par partie, chacune en trois étapes et une astuce ; un clic sur
/// une partie de « Bienvenue » ouvre la page de même numéro.
final class GuideTests: XCTestCase {
    func testPagesAreNumberedInOrder() {
        XCTAssertEqual(GuideContent.pages.map(\.id), Array(1...GuideContent.pages.count))
        XCTAssertEqual(GuideContent.count, GuideContent.pages.count + 1)
        for page in GuideContent.pages {
            XCTAssertEqual(page.steps.count, 3, page.title)
            XCTAssertFalse(page.tip.isEmpty, page.title)
        }
    }
}
