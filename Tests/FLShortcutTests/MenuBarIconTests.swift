import AppKit
import XCTest
@testable import FLShortcut

/// Logo de la barre des menus : une image modèle de 18 points par état, en 1x et 2x, avec sa pastille d'état.
final class MenuBarIconTests: XCTestCase {
    private func pixels(_ image: NSImage, scale: Int) throws -> NSBitmapImageRep {
        try XCTUnwrap(image.representations.compactMap { $0 as? NSBitmapImageRep }.first { $0.pixelsWide == 18 * scale })
    }

    /// Part des pixels non transparents dans la moitié droite du haut (là où est la pastille ou la touche de derrière).
    private func ink(_ rep: NSBitmapImageRep, in box: (x: Range<Int>, y: Range<Int>)) -> Int {
        var n = 0
        for x in box.x { for y in box.y where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 { n += 1 } }
        return n
    }

    func testEveryStateIsATemplateLogo() throws {
        var drawings: [Data] = []
        for state in MenuBarIcon.State.allCases {
            let image = MenuBarIcon.image(state)
            XCTAssertTrue(image.isTemplate, "\(state)")
            XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
            XCTAssertNotNil(image.accessibilityDescription)
            let rep = try pixels(image, scale: 2)
            // Touche de devant (en bas à gauche) toujours dessinée.
            XCTAssertGreaterThan(ink(rep, in: (4..<20, 14..<32)), 100, "\(state)")
            drawings.append(try XCTUnwrap(rep.tiffRepresentation))
            XCTAssertNotNil(try? pixels(image, scale: 1))
        }
        XCTAssertEqual(Set(drawings).count, MenuBarIcon.State.allCases.count, "chaque état se voit")
        XCTAssertTrue(MenuBarIcon.image(.normal) === MenuBarIcon.image(.normal), "dessinée une seule fois")
    }

    func testStateFromTheStatusSymbol() {
        XCTAssertEqual(MenuBarIcon.state(forSymbol: "keyboard.fill"), .normal)
        XCTAssertEqual(MenuBarIcon.state(forSymbol: "exclamationmark.triangle.fill"), .warning)
        XCTAssertEqual(MenuBarIcon.state(forSymbol: "pause.circle.fill"), .paused)
    }
}
