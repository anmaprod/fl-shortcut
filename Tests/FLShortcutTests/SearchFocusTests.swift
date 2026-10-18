import AppKit
import XCTest
@testable import FLShortcut

/// Recherche active seulement quand on l'a choisie : seul un champ de recherche est repris à la fenêtre, jamais un
/// autre champ.
final class SearchFocusTests: XCTestCase {
    func testOnlySearchFieldsAreRecognized() {
        XCTAssertTrue(SearchFocusGuard.GuardView.isSearchEditor(NSSearchField()))
        XCTAssertFalse(SearchFocusGuard.GuardView.isSearchEditor(NSTextField()))
        XCTAssertFalse(SearchFocusGuard.GuardView.isSearchEditor(nil))
        XCTAssertFalse(SearchFocusGuard.GuardView.isSearchEditor(NSTextView()), "pas un éditeur de champ")
        let editor = NSTextView()
        editor.isFieldEditor = true
        XCTAssertFalse(SearchFocusGuard.GuardView.isSearchEditor(editor), "éditeur sans recherche")
    }
}
