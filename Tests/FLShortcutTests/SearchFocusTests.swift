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

    /// Retour de l'utilisateur (vidéo) : recherche cliquée, puis une option choisie dans la seconde ; la page changée,
    /// AppKit lui redonnait la main et elle la gardait. Choisie, elle la garde ; un clic ailleurs la lui reprend, même
    /// redonnée après coup ; un autre champ n'est jamais touché.
    func testSearchKeepsFocusOnlyUntilAClickElsewhere() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let search = NSSearchField(frame: NSRect(x: 10, y: 150, width: 200, height: 24))
        let other = NSTextField(frame: NSRect(x: 10, y: 100, width: 200, height: 24))
        let guardView = SearchFocusGuard.GuardView(frame: .zero)
        window.contentView?.addSubview(search)
        window.contentView?.addSubview(other)
        window.contentView?.addSubview(guardView)
        window.orderFrontRegardless()
        func spin() { RunLoop.current.run(until: Date().addingTimeInterval(0.5)) }
        func searchHasFocus() -> Bool { SearchFocusGuard.GuardView.isSearchEditor(window.firstResponder) }

        window.makeFirstResponder(search)                      // AppKit, sans clic : reprise
        spin()
        XCTAssertFalse(searchHasFocus(), "pas choisie : la fenêtre la reprend")

        guardView.clicked(inSearch: true, window: window)      // clic dedans
        window.makeFirstResponder(search)
        spin()
        XCTAssertTrue(searchHasFocus(), "choisie : elle garde la main")

        guardView.clicked(inSearch: false, window: window)     // une option de la barre latérale
        spin()
        XCTAssertFalse(searchHasFocus(), "clic ailleurs : elle lâche la main")
        window.makeFirstResponder(search)                      // la page changée, AppKit la lui redonne
        spin()
        XCTAssertFalse(searchHasFocus(), "redonnée après coup : reprise encore")

        window.makeFirstResponder(other)
        spin()
        XCTAssertFalse(searchHasFocus())
        XCTAssertFalse(window.firstResponder === window, "un autre champ garde la main")
    }
}
