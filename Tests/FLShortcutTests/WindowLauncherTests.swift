// Fenêtres qui sortent du clic : états d'une ouverture (double clic, fenêtre absente, fermeture), cas sans vol
// (autre écran, fenêtre déjà là, réduite, plein écran, autre espace, mouvement réduit), cadre mémorisé.
import AppKit
import XCTest
@testable import FLShortcut

final class WindowLauncherTests: XCTestCase {
    func testDoubleOpenWhileFlying() {
        XCTAssertEqual(LaunchState.idle.next(.open), .flying)
        XCTAssertEqual(LaunchState.flying.next(.open), .flying, "deuxième clic ignoré")
        XCTAssertEqual(LaunchState.waiting.next(.open), .waiting)
    }

    func testLaunchPath() {
        XCTAssertEqual(LaunchState.flying.next(.landed), .waiting)
        XCTAssertEqual(LaunchState.waiting.next(.windowVisible), .revealing)
        XCTAssertEqual(LaunchState.waiting.next(.timeout), .idle, "fenêtre absente : bulle retirée, rien d'invisible")
        XCTAssertEqual(LaunchState.revealing.next(.finished), .idle)
        XCTAssertEqual(LaunchState.flying.next(.close), .closing)
        XCTAssertEqual(LaunchState.closing.next(.finished), .idle)
        XCTAssertEqual(LaunchState.idle.next(.close), .closing, "fermeture d'une fenêtre ouverte : bulle vers l'icône")
    }

    func testNoFlightAcrossScreens() {
        let a = CGRect(x: 0, y: 0, width: 1440, height: 900), b = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        XCTAssertFalse(LaunchDecision.flies(sourceScreen: a, targetScreen: b, alreadyVisible: false, miniaturized: false,
                                            fullScreen: false, onActiveSpace: true, reduced: false))
        XCTAssertTrue(LaunchDecision.flies(sourceScreen: a, targetScreen: a, alreadyVisible: false, miniaturized: false,
                                           fullScreen: false, onActiveSpace: true, reduced: false))
    }

    func testNoFlightForVisibleHiddenOrReduced() {
        let a = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let cases: [(Bool, Bool, Bool, Bool, Bool)] = [(true, false, false, true, false),
                                                        (false, true, false, true, false),
                                                        (false, false, true, true, false),
                                                        (false, false, false, false, false),
                                                        (false, false, false, true, true)]
        for (visible, mini, full, space, reduced) in cases {
            XCTAssertFalse(LaunchDecision.flies(sourceScreen: a, targetScreen: a, alreadyVisible: visible,
                                                miniaturized: mini, fullScreen: full, onActiveSpace: space,
                                                reduced: reduced))
        }
        XCTAssertFalse(LaunchDecision.flies(sourceScreen: nil, targetScreen: a, alreadyVisible: false,
                                            miniaturized: false, fullScreen: false, onActiveSpace: true,
                                            reduced: false))
    }

    func testFrameMemory() {
        let d = UserDefaults(suiteName: "test.\(UUID())")!
        XCTAssertNil(WindowFrameMemory.load(key: "editorFrame", defaults: d))
        WindowFrameMemory.save(CGRect(x: 10, y: 20, width: 900, height: 600), key: "editorFrame", defaults: d)
        XCTAssertEqual(WindowFrameMemory.load(key: "editorFrame", defaults: d), CGRect(x: 10, y: 20, width: 900, height: 600))
        XCTAssertEqual(WindowFrameMemory.centered(size: CGSize(width: 900, height: 600),
                                                  in: CGRect(x: 0, y: 0, width: 1500, height: 1000)),
                       CGRect(x: 300, y: 200, width: 900, height: 600))
    }

    /// Une fenêtre qu'on ne peut pas faire voler (aucune icône dans la barre des menus pendant les tests) s'ouvre
    /// normalement : jamais invisible.
    func testWindowStaysVisibleWithoutFlight() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.titled],
                              backing: .buffered, defer: true)
        WindowLauncher.shared.open(source: nil, icon: nil, title: nil, window: window)
        XCTAssertEqual(window.alphaValue, 1)
        XCTAssertEqual(WindowLauncher.shared.state, .idle)
    }

    func testFlightWindowNeverTakesTheMouse() {
        let window = FlightWindow.make(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        XCTAssertTrue(window.ignoresMouseEvents)
        XCTAssertFalse(window.canBecomeKey)
        XCTAssertFalse(window.isOpaque)
        window.close()
    }
}
