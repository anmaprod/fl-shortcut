// Menu de l'icône en bulle : pastille de départ sous l'icône (même près d'un bord), fond de macOS masqué sans jamais
// cacher notre contenu, repli sur l'ancien menu (préférence, ou fenêtre d'une forme inattendue).
import AppKit
import SwiftUI
import XCTest
@testable import FLShortcut

final class MenuBubbleTests: XCTestCase {
    private func window() -> NSWindow {
        NSWindow(contentRect: NSRect(x: 0, y: 0, width: 300, height: 200), styleMask: [.borderless],
                 backing: .buffered, defer: true)
    }

    private func assertRect(_ a: CGRect, _ b: CGRect, file: StaticString = #filePath, line: UInt = #line) {
        for (x, y) in [(a.minX, b.minX), (a.minY, b.minY), (a.width, b.width), (a.height, b.height)] {
            XCTAssertEqual(x, y, accuracy: 0.01, file: file, line: line)
        }
    }

    func testPillStartsUnderTheIcon() {
        let window = CGRect(x: 1000, y: 700, width: 340, height: 420)      // écran, origine en bas
        let icon = CGRect(x: 1150, y: 1120, width: 28, height: 24)
        XCTAssertEqual(MenuBubbleGeometry.pill(icon: icon, window: window), CGRect(x: 150, y: 0, width: 28, height: 24))
    }

    func testPillFollowsTheIconNearTheEdge() {
        let window = CGRect(x: 1580, y: 700, width: 340, height: 420)
        let icon = CGRect(x: 1880, y: 1120, width: 28, height: 24)
        XCTAssertEqual(MenuBubbleGeometry.pill(icon: icon, window: window).midX, 314)
    }

    func testPillStaysInsideTheWindow() {
        let window = CGRect(x: 1000, y: 700, width: 340, height: 420)
        let farRight = CGRect(x: 1400, y: 1120, width: 28, height: 24)
        XCTAssertEqual(MenuBubbleGeometry.pill(icon: farRight, window: window).maxX, 340)
        let farLeft = CGRect(x: 900, y: 1120, width: 28, height: 24)
        XCTAssertEqual(MenuBubbleGeometry.pill(icon: farLeft, window: window).minX, 0)
    }

    func testBubbleShapeGoesFromPillToContent() {
        let pill = CGRect(x: 150, y: 0, width: 28, height: 24)
        let whole = CGRect(x: 0, y: 0, width: 340, height: 420)
        assertRect(MenuBubbleShape(progress: 0, pill: pill).path(in: whole).boundingRect, pill)
        assertRect(MenuBubbleShape(progress: 1, pill: pill).path(in: whole).boundingRect,
                   CGRect(x: 20, y: 0, width: 300, height: 392))
    }

    /// Fond de macOS qui contient notre contenu : le cacher cacherait le menu ; seul son verre est masqué.
    func testBackgroundAroundOurContentIsMaskedNotHidden() {
        let window = window()
        let background = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        let host = NSView(frame: background.bounds)
        let inner = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        host.addSubview(inner)
        background.addSubview(host)
        window.contentView = background
        XCTAssertTrue(MenuBubbleSupport.prepare(window, legacy: false, host: host))
        XCTAssertNotNil(background.maskImage)
        XCTAssertFalse(background.isHidden)
        XCTAssertFalse(inner.isHidden)
        XCTAssertNil(inner.maskImage, "le verre de nos propres vues reste")
        XCTAssertFalse(window.isOpaque)
        XCTAssertEqual(window.backgroundColor, .clear)
        XCTAssertFalse(window.hasShadow)
    }

    /// Fond de macOS posé à côté de notre contenu : caché.
    func testBackgroundBesideOurContentIsHidden() {
        let window = window()
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 300, height: 200))
        let background = NSVisualEffectView(frame: root.bounds)
        let host = NSView(frame: root.bounds)
        root.addSubview(background)
        root.addSubview(host)
        window.contentView = root
        XCTAssertTrue(MenuBubbleSupport.prepare(window, legacy: false, host: host))
        XCTAssertTrue(background.isHidden)
        XCTAssertFalse(host.isHidden)
    }

    func testLegacyMenuKeepsSystemBubble() {
        let window = window()
        window.contentView = NSVisualEffectView()
        window.hasShadow = true
        XCTAssertFalse(MenuBubbleSupport.prepare(window, legacy: true))
        XCTAssertTrue(window.hasShadow)
        let bare = self.window()
        bare.hasShadow = true
        XCTAssertFalse(MenuBubbleSupport.prepare(bare, legacy: false), "pas de fond système trouvé : rien ne change")
        XCTAssertTrue(bare.hasShadow)
    }
}
