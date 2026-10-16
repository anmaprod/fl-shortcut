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
            // Même dessin en 1x, à la même place (le 2x n'est pas un dessin 1x posé dans un coin).
            let small = try pixels(image, scale: 1)
            XCTAssertGreaterThan(ink(small, in: (2..<10, 7..<16)), 25, "\(state)")
            XCTAssertEqual(Double(ink(rep, in: (0..<36, 0..<36))) / 4, Double(ink(small, in: (0..<18, 0..<18))),
                           accuracy: 40, "\(state)")
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
