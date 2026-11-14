import AppKit
import XCTest
@testable import FLShortcut

/// Logo de la barre des menus (rond A tout blanc du 05/11) : une image modèle de macOS (blanche sur une barre sombre,
/// noire sur une claire), le rond plein et le cercle décalé en haut à droite ; 18 points par état, en 1x et 2x, avec
/// sa pastille d'état.
final class MenuBarIconTests: XCTestCase {
    private func pixels(_ image: NSImage, scale: Int) throws -> NSBitmapImageRep {
        try XCTUnwrap(image.representations.compactMap { $0 as? NSBitmapImageRep }.first { $0.pixelsWide == 18 * scale })
    }

    /// Pixels non transparents dans une zone de l'icône.
    private func ink(_ rep: NSBitmapImageRep, in box: (x: Range<Int>, y: Range<Int>)) -> Int {
        var n = 0
        for x in box.x { for y in box.y where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 { n += 1 } }
        return n
    }

    /// Pixels non transparents qui ne sont pas noirs (une image modèle n'a qu'une couleur : le noir).
    private func colored(_ rep: NSBitmapImageRep) -> Int {
        var n = 0
        for x in 0..<rep.pixelsWide {
            for y in 0..<rep.pixelsHigh {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.alphaComponent > 0.5 else { continue }
                if c.redComponent + c.greenComponent + c.blueComponent > 0.6 { n += 1 }
            }
        }
        return n
    }

    func testTheLogoIsATemplateThatFollowsTheBar() throws {
        for state in MenuBarIcon.State.allCases {
            let image = MenuBarIcon.image(state)
            XCTAssertTrue(image.isTemplate, "blanc sur une barre sombre, noir sur une claire : \(state)")
            XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
            XCTAssertNotNil(image.accessibilityDescription)
        }
        XCTAssertTrue(MenuBarIcon.image(.normal) === MenuBarIcon.image(.normal), "dessinée une seule fois")

        var drawings: [Data] = []
        for state in MenuBarIcon.State.allCases {
            let drawn = MenuBarIcon.drawn(state)
            let rep = try pixels(drawn, scale: 2)
            // Le rond plein, en bas à gauche (centre 470, 580 sur 1024 : 16,5 ; 20,4 en 2x).
            XCTAssertGreaterThan(ink(rep, in: (13..<20, 17..<24)), 35, "rond : \(state)")
            // Le cercle, en bas à droite de son tour (hors du jour et de la pastille).
            XCTAssertGreaterThan(ink(rep, in: (27..<33, 21..<28)), 8, "cercle : \(state)")
            XCTAssertEqual(colored(rep), 0, "une seule couleur : \(state)")
            drawings.append(try XCTUnwrap(rep.tiffRepresentation))
            // Même dessin en 1x, à la même place.
            let small = try pixels(drawn, scale: 1)
            XCTAssertGreaterThan(ink(small, in: (6..<11, 8..<13)), 15, "\(state)")
            XCTAssertEqual(Double(ink(rep, in: (0..<36, 0..<36))) / 4, Double(ink(small, in: (0..<18, 0..<18))),
                           accuracy: 40, "\(state)")
        }
        XCTAssertEqual(Set(drawings).count, MenuBarIcon.State.allCases.count, "chaque état se voit")
    }

    func testStateFromTheStatusSymbol() {
        XCTAssertEqual(MenuBarIcon.state(forSymbol: "keyboard.fill"), .normal)
        XCTAssertEqual(MenuBarIcon.state(forSymbol: "exclamationmark.triangle.fill"), .warning)
        XCTAssertEqual(MenuBarIcon.state(forSymbol: "pause.circle.fill"), .paused)
    }
}
