// « Menu de FL » par les menus dans la fenêtre de FL (04/11, « Export Stems » : FL ne met à jour ses éléments grisés
// qu'à l'ouverture de SES menus) : titre et éléments retrouvés à leur nom, élément grisé reconnu à sa couleur.
import CoreGraphics
import XCTest
@testable import FLShortcut

final class MacroWindowMenuTests: XCTestCase {
    private func item(_ text: String, x: CGFloat = 10, y: CGFloat) -> TextLook.Item {
        TextLook.Item(text: text, box: CGRect(x: x, y: y, width: 120, height: 14))
    }

    func testTitleIsFoundInFLCapitals() {
        let strip = [item("FILE", x: 20, y: 6), item("EDIT", x: 60, y: 6), item("ADD", x: 100, y: 6), item("OPTIONS", x: 180, y: 6)]
        XCTAssertEqual(MacroEffectsMac.menuTitle("File", in: strip)?.text, "FILE")
        XCTAssertEqual(MacroEffectsMac.menuTitle("Options", in: strip)?.text, "OPTIONS")
        XCTAssertNil(MacroEffectsMac.menuTitle("Tools", in: strip))
    }

    func testEntriesMatchWithoutEllipsisOrShortcut() {
        let menu = [
            item("Export", y: 10), item("Export project data files…", y: 30),
            item("Time selection...", y: 50), item("Save as   ⇧⌘S", y: 70), item("Playlist F5", y: 90),
        ]
        XCTAssertEqual(MacroEffectsMac.menuEntry("Export", in: menu)?.box.minY, 10, "le nom exact, pas « Export project… »")
        XCTAssertEqual(MacroEffectsMac.menuEntry("Time selection…", in: menu)?.box.minY, 50)
        XCTAssertEqual(MacroEffectsMac.menuEntry("Save as...", in: menu)?.box.minY, 70)
        XCTAssertEqual(MacroEffectsMac.menuEntry("Playlist", in: menu)?.box.minY, 90)
        XCTAssertNil(MacroEffectsMac.menuEntry("Export project", in: menu), "un début de nom n'est jamais pris")
        XCTAssertNil(MacroEffectsMac.menuEntry("", in: menu))
    }

    func testShortcutTextsAreRecognized() {
        for s in ["", "Ctrl+S", "⇧⌘S", "F5", "F10"] { XCTAssertTrue(MacroEffectsMac.isShortcutText(s), s) }
        for s in ["project data files", "data", "F100"] { XCTAssertFalse(MacroEffectsMac.isShortcutText(s), s) }
    }

    /// Texte blanc : actif ; gris moyen (comme les éléments grisés de FL, et du faux FL) : grisé.
    func testGreyedItemsAreDarker() throws {
        func image(text gray: UInt8) -> CGImage? {
            let w = 80, h = 20
            var px = [UInt8](repeating: 46, count: w * h)                     // fond du menu
            for y in 6..<14 { for x in 10..<60 where x % 3 != 0 { px[y * w + x] = gray } }   // lettres
            return px.withUnsafeMutableBytes { raw -> CGImage? in
                CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                          space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)?.makeImage()
            }
        }
        let box = CGRect(x: 8, y: 4, width: 56, height: 12)
        let enabled = try XCTUnwrap(MacroEffectsMac.brightest(in: try XCTUnwrap(image(text: 245)), size: CGSize(width: 80, height: 20), box: box))
        let greyed = try XCTUnwrap(MacroEffectsMac.brightest(in: try XCTUnwrap(image(text: 128)), size: CGSize(width: 80, height: 20), box: box))
        XCTAssertFalse(MacroEffectsMac.looksGreyed(brightest: enabled))
        XCTAssertTrue(MacroEffectsMac.looksGreyed(brightest: greyed))
    }
}
