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
        // Recherche dessinée autrement (SwiftUI) : un champ qui en a la cellule, ou un champ placé dans une recherche.
        let drawn = NSTextField()
        drawn.cell = NSSearchFieldCell(textCell: "")
        XCTAssertTrue(SearchFocusGuard.GuardView.isSearchEditor(drawn))
        let search = NSSearchField()
        let inner = EditedField()
        search.addSubview(inner)
        editor.delegate = inner
        XCTAssertTrue(SearchFocusGuard.GuardView.isSearchEditor(editor), "le champ édité est dans une recherche")
        let plain = EditedField()
        editor.delegate = plain
        XCTAssertFalse(SearchFocusGuard.GuardView.isSearchEditor(editor), "un autre champ n'est jamais repris")
    }

    /// Mesure de la CI (25/10) : sur macOS 26, la recherche de SwiftUI est un `AppKitSearchField`, champ ordinaire
    /// (pas une recherche d'AppKit) : la garde ne la voyait pas. Reconnue à son nom ; un hôte dont seuls les
    /// paramètres parlent de recherche, ou un autre champ, jamais.
    func testSwiftUISearchFieldIsRecognized() {
        let field = AppKitSearchFieldImitation()
        XCTAssertTrue(SearchFocusGuard.GuardView.isSearchEditor(field))
        let editor = NSTextView()
        editor.isFieldEditor = true
        let inner = EditedField()
        field.addSubview(inner)
        editor.delegate = inner
        XCTAssertTrue(SearchFocusGuard.GuardView.isSearchEditor(editor), "son texte en cours d'édition")
        let host = Host<AppKitSearchFieldImitation>()
        XCTAssertFalse(SearchFocusGuard.GuardView.isSearchView(host), "l'hôte de toute la fenêtre n'est pas la recherche")
        let rename = EditedField()
        host.addSubview(rename)
        editor.delegate = rename
        XCTAssertFalse(SearchFocusGuard.GuardView.isSearchEditor(editor), "un autre champ de la fenêtre n'est pas repris")

        // Clic dedans (même sur sa loupe, dessinée dans le champ) : la recherche est choisie ; à côté, non.
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let search = AppKitSearchFieldImitation(frame: NSRect(x: 10, y: 150, width: 200, height: 24))
        let loupe = NSView(frame: NSRect(x: 4, y: 4, width: 16, height: 16))
        search.addSubview(loupe)
        window.contentView?.addSubview(search)
        XCTAssertTrue(SearchFocusGuard.GuardView.searchField(at: NSPoint(x: 100, y: 162), in: window))
        XCTAssertTrue(SearchFocusGuard.GuardView.searchField(at: NSPoint(x: 21, y: 162), in: window), "sur la loupe")
        XCTAssertFalse(SearchFocusGuard.GuardView.searchField(at: NSPoint(x: 300, y: 50), in: window))
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

    /// Retour de l'utilisateur (vidéo) : recherche cliquée, puis un clic hors de l'app ; la fenêtre revenue, elle était
    /// encore active. La fenêtre qui perd la main la lui reprend, et elle ne la reprend pas au retour.
    func testSearchLetsGoWhenTheWindowLosesFocus() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 200), styleMask: [.titled],
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let search = NSSearchField(frame: NSRect(x: 10, y: 150, width: 200, height: 24))
        let guardView = SearchFocusGuard.GuardView(frame: .zero)
        window.contentView?.addSubview(search)
        window.contentView?.addSubview(guardView)
        window.orderFrontRegardless()
        func spin() { RunLoop.current.run(until: Date().addingTimeInterval(0.5)) }
        func searchHasFocus() -> Bool { SearchFocusGuard.GuardView.isSearchEditor(window.firstResponder) }

        var released = 0
        guardView.release = { released += 1 }
        guardView.clicked(inSearch: true, window: window)      // clic dedans
        window.makeFirstResponder(search)
        spin()
        XCTAssertTrue(searchHasFocus(), "choisie : elle garde la main")
        XCTAssertEqual(released, 0, "SwiftUI la laisse aussi")

        NotificationCenter.default.post(name: NSWindow.didResignKeyNotification, object: window)   // clic hors de l'app
        spin()
        XCTAssertFalse(searchHasFocus(), "fenêtre quittée : elle lâche la main")
        XCTAssertGreaterThan(released, 0, "et SwiftUI aussi (searchFocused à faux)")

        window.makeFirstResponder(search)                      // la fenêtre revenue, AppKit la lui redonne
        spin()
        XCTAssertFalse(searchHasFocus(), "au retour : plus active")
    }
}

/// Un champ en cours d'édition (délégué de l'éditeur de la fenêtre), placé où l'on veut.
private final class EditedField: NSView, NSTextViewDelegate {}

/// La recherche de SwiftUI sur macOS 26 : un champ ordinaire au nom de recherche.
private final class AppKitSearchFieldImitation: NSTextField {}

/// Un hôte de SwiftUI, dont le nom porte celui de ce qu'il affiche (`NSHostingView<…>`).
private final class Host<Content>: NSView {}
