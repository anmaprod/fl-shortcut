import AppKit
import XCTest
@testable import FLShortcut

/// Logo de la barre des menus (logo « A » du 04/11) : en couleurs, jamais une image modèle ; le rond rouge, le cercle
/// blanc sur une barre sombre et noir sur une claire ; 18 points par état, en 1x et 2x, avec sa pastille d'état.
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

    /// Pixels du rouge de la marque dans une zone.
    private func red(_ rep: NSBitmapImageRep, in box: (x: Range<Int>, y: Range<Int>)) -> Int {
        var n = 0
        for x in box.x {
            for y in box.y {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.alphaComponent > 0.5 else { continue }
                if c.redComponent > 0.8 && c.greenComponent < 0.45 && c.blueComponent < 0.4 { n += 1 }
            }
        }
        return n
    }

    /// Pixels de la couleur du cercle (blanc ou noir) dans une zone.
    private func ringColored(_ rep: NSBitmapImageRep, white: Bool, in box: (x: Range<Int>, y: Range<Int>)) -> Int {
        var n = 0
        for x in box.x {
            for y in box.y {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB), c.alphaComponent > 0.5 else { continue }
                let level = (c.redComponent + c.greenComponent + c.blueComponent) / 3
                if white ? level > 0.8 : level < 0.2 { n += 1 }
            }
        }
        return n
    }

    func testTheLogoIsInColorsAndFollowsTheBar() throws {
        for state in MenuBarIcon.State.allCases {
            let image = MenuBarIcon.image(state)
            XCTAssertFalse(image.isTemplate, "en couleurs, jamais teinté par macOS : \(state)")
            XCTAssertEqual(image.size, NSSize(width: 18, height: 18))
            XCTAssertNotNil(image.accessibilityDescription)
        }
        XCTAssertTrue(MenuBarIcon.image(.normal) === MenuBarIcon.image(.normal), "dessinée une seule fois")

        for white in [true, false] {
            var drawings: [Data] = []
            for state in MenuBarIcon.State.allCases {
                let drawn = MenuBarIcon.drawn(state, ring: white ? .white : .black)
                let rep = try pixels(drawn, scale: 2)
                // Le rond rouge, en bas à gauche (centre 392, 652 sur 1024 : 13,8 ; 22,9 en 2x), toujours là.
                XCTAssertGreaterThan(red(rep, in: (8..<20, 17..<29)), 80, "rond rouge : \(state)")
                // Le cercle, au centre : son haut, à gauche de la pastille d'état, de la couleur de la barre.
                XCTAssertGreaterThan(ringColored(rep, white: white, in: (10..<20, 2..<9)), 8, "cercle : \(state)")
                drawings.append(try XCTUnwrap(rep.tiffRepresentation))
                // Même dessin en 1x, à la même place.
                let small = try pixels(drawn, scale: 1)
                XCTAssertGreaterThan(red(small, in: (4..<10, 9..<15)), 15, "\(state)")
                XCTAssertEqual(Double(ink(rep, in: (0..<36, 0..<36))) / 4, Double(ink(small, in: (0..<18, 0..<18))),
                               accuracy: 40, "\(state)")
            }
            XCTAssertEqual(Set(drawings).count, MenuBarIcon.State.allCases.count, "chaque état se voit")
        }
        let dark = try pixels(MenuBarIcon.drawn(.normal, ring: .white), scale: 2).tiffRepresentation
        let light = try pixels(MenuBarIcon.drawn(.normal, ring: .black), scale: 2).tiffRepresentation
        XCTAssertNotEqual(dark, light, "cercle blanc sur barre sombre, noir sur barre claire")
    }

    func testStateFromTheStatusSymbol() {
        XCTAssertEqual(MenuBarIcon.state(forSymbol: "keyboard.fill"), .normal)
        XCTAssertEqual(MenuBarIcon.state(forSymbol: "exclamationmark.triangle.fill"), .warning)
        XCTAssertEqual(MenuBarIcon.state(forSymbol: "pause.circle.fill"), .paused)
    }
}
