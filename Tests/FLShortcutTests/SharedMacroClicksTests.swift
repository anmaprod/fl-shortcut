// Macro partagée (Communauté, fichier .flsmacro) rejouée dans le FL d'un autre ordinateur (demande du 19/11 : « que
// FL Shortcuts analyse le clic et fasse le même dans FL que dans les autres ordis ») : un bouton est gardé par son nom
// ou son image, un point d'une fenêtre de plugin en proportion, le reste est à montrer une fois. Miroir de
// SharedMacroClicksTests (Windows), même format de fichier.
import XCTest
@testable import FLShortcut

final class SharedMacroClicksTests: XCTestCase {
    /// Bouton dessiné à l'échelle `scale` : damier noir et blanc de 4 cases de 6 × scale pixels, coin en (bx, by).
    private func window(_ width: Int, _ height: Int, buttonAt bx: Int, _ by: Int, scale: Double) -> GrayImage {
        var px = [UInt8](repeating: 40, count: width * height)
        let side = Int((24 * scale).rounded()), cell = 6 * scale
        for y in 0..<side {
            for x in 0..<side {
                px[(by + y) * width + bx + x] = (Int(Double(x) / cell) + Int(Double(y) / cell)) % 2 == 0 ? 250 : 10
            }
        }
        return GrayImage(width: width, height: height, pixels: px)
    }

    private func patch() throws -> GrayImage {
        try XCTUnwrap(window(500, 400, buttonAt: 100, 80, scale: 1).crop(centerX: 112, centerY: 92, side: VisualSpot.defaultSide))
    }

    func testWhatASharedMacroKeepsOfEachClick() throws {
        let size = CGSize(width: 500, height: 400)
        let named = ClickTarget.named(NamedSpot(label: "Insert 1", dx: 0, dy: 0, corner: .topLeft, px: 60, py: 30, size: size))
        guard case .named(let sharedName) = named.portable else { return XCTFail("bouton par son nom attendu") }
        XCTAssertTrue(sharedName.loose && named.portable.isLoose)

        let image = try patch()
        let place = ClickTarget.flWindow(corner: .topLeft, dx: 112, dy: 92, size: size)
        let withLook = ClickSequenceCompiler.withLook(place, ButtonLook(side: image.width, pixels: image.pixels))
        guard case .flWindow(_, _, _, _, _, let look?, false) = withLook else { return XCTFail("image retenue avec la place") }
        XCTAssertEqual(look.side, VisualSpot.defaultSide)
        XCTAssertFalse(withLook.isLoose)                                        // sur ce Mac rien ne change
        guard case .button(let shared) = withLook.portable else { return XCTFail("partagé : cherché à son image") }
        XCTAssertTrue(shared.loose)
        XCTAssertEqual(shared.dx, 112)

        // Sans image : l'endroit est à montrer chez l'autre.
        XCTAssertEqual(place.portable, .toLearn)
        // Fenêtre d'un plugin (titre) : même endroit en proportion.
        let plugin = ClickTarget.flWindow(corner: .topLeft, dx: 200, dy: 150, size: CGSize(width: 800, height: 600), title: "Serum")
        XCTAssertTrue(plugin.portable.isLoose)
        // Décalages depuis la souris, la piste, le dernier clic ; menus : à montrer une fois.
        XCTAssertEqual(ClickTarget.lastClick(dx: 4, dy: 0).portable, .toLearn)
        XCTAssertEqual(ClickTarget.track(dx: 4, dy: 0).portable, .toLearn)
        // Tout se garde dans le fichier (JSON commun à Windows) ; repasser par portable ne change rien.
        for t in [named.portable, withLook, withLook.portable, plugin.portable] {
            XCTAssertEqual(ClickTarget(json: t.json), t)
            if t.isLoose { XCTAssertEqual(t.portable, t) }
        }
    }

    func testExportThenImportKeepsTheClicksThatCanBeFound() throws {
        let size = CGSize(width: 940, height: 652)
        let image = try patch()
        let blocks = [
            Block(.click(.named(NamedSpot(label: "FILE", dx: 0, dy: 0, corner: .topLeft, px: 20, py: 12, size: size)), button: .left)),
            Block(.click(ClickSequenceCompiler.withLook(.flWindow(corner: .topLeft, dx: 112, dy: 92, size: size),
                                                        ButtonLook(side: image.width, pixels: image.pixels)), button: .left)),
            Block(.click(.flWindow(corner: .topLeft, dx: 300, dy: 300, size: size), button: .left)),
        ]
        let doc = MacroDoc(name: "Export", blocks: blocks)
        let data = try MacroExchange.export(doc, appVersion: "1.2", home: "/Users/flshortcuts")
        let preview = try MacroExchange.prepareImport(data, home: "/Users/autre", layout: FakeLayout.qwerty)
        let targets = preview.doc.blocks.compactMap { b -> ClickTarget? in
            if case .click(let t, _) = b.body { return t }
            return nil
        }
        XCTAssertEqual(targets.count, 3)
        XCTAssertTrue(targets[0].isLoose)
        guard case .button = targets[1] else { return XCTFail("bouton par son image attendu") }
        XCTAssertTrue(targets[1].isLoose)
        XCTAssertEqual(targets[2], .toLearn)
        XCTAssertTrue(preview.lines[0].contains("bouton retrouvé par son nom"), preview.lines[0])
        XCTAssertTrue(preview.lines[1].contains("bouton retrouvé à son image"), preview.lines[1])
        XCTAssertTrue(preview.lines[2].contains("position à montrer"), preview.lines[2])
    }

    /// Bouton retenu à son image sur un écran, retrouvé dessiné une fois et demie plus grand (macro faite sur un PC à
    /// 150 %, ou l'inverse), ailleurs dans une fenêtre d'une autre taille.
    func testAButtonImageIsFoundAtAnotherScale() throws {
        let image = try patch()
        let big = window(750, 600, buttonAt: 400, 300, scale: 1.5)
        let found = try XCTUnwrap(VisualMatch.findAnyScale(image, in: big, hint: (168, 138), likely: [1.5]))
        XCTAssertEqual(Double(found.hit.x), 418, accuracy: 2)
        XCTAssertEqual(Double(found.hit.y), 318, accuracy: 2)
        XCTAssertEqual(found.scale, 1.5, accuracy: 0.01)
        XCTAssertNil(VisualMatch.findAnyScale(image, in: GrayImage(width: 750, height: 600,
                                                                   pixels: [UInt8](repeating: 40, count: 750 * 600)),
                                              hint: (168, 138)))
    }

    // MARK: Presets joints (« le preset part avec la macro »)

    func testThePresetTravelsWithTheMacroAndLandsInThePresetsFolder() throws {
        let bytes = Data((0..<3000).map { UInt8(($0 * 7) & 0xFF) })
        let source = "/Users/flshortcuts/Documents/Image-Line/FL Studio/Presets/Bass.fst"
        let doc = MacroDoc(name: "Basse", blocks: [Block(.dropFile(path: source)), Block(.delay(ms: 100))])
        let file = try MacroExchange.export(doc, appVersion: "1.2", home: "/Users/flshortcuts",
                                            read: { $0 == source ? bytes : nil })
        XCTAssertTrue(String(decoding: file, as: UTF8.self).contains("\"attached\""))

        let presets = "/Users/autre/Documents/FL Shortcuts/Presets"
        let preview = try MacroExchange.prepareImport(file, home: "/Users/autre", layout: FakeLayout.qwerty,
                                                      presets: presets, existing: { _ in nil })
        guard case .dropFile(let path) = preview.doc.blocks[0].body else { return XCTFail("preset glissé attendu") }
        XCTAssertEqual(path, presets + "/Bass.fst")
        XCTAssertEqual(preview.files, [MacroExchange.AttachedFile(path: presets + "/Bass.fst", data: bytes)])
        XCTAssertTrue(preview.lines[0].contains("preset joint"), preview.lines[0])
        XCTAssertFalse(preview.warnings.contains { $0.contains("Rechoisis") })

        // Un autre fichier du même nom est déjà là : jamais remplacé, « Bass 2.fst ».
        let taken = try MacroExchange.prepareImport(file, home: "/Users/autre", layout: FakeLayout.qwerty, presets: presets,
                                                    existing: { $0 == presets + "/Bass.fst" ? Data([1]) : nil })
        guard case .dropFile(let other) = taken.doc.blocks[0].body else { return XCTFail("preset glissé attendu") }
        XCTAssertEqual(other, presets + "/Bass 2.fst")
    }

    func testOnlySafeFstNamesAreKept() {
        XCTAssertEqual(MacroExchange.safePresetName("/a/b/Bass.fst"), "Bass.fst")
        XCTAssertEqual(MacroExchange.safePresetName("C:\\x\\Lead.FST"), "Lead.FST")
        XCTAssertNil(MacroExchange.safePresetName("virus.app"))
        XCTAssertNil(MacroExchange.safePresetName("../.fst"))
        XCTAssertNil(MacroExchange.safePresetName(nil))
    }

    func testAnImageCanBeResizedBothWays() {
        let image = window(40, 40, buttonAt: 8, 8, scale: 1)
        XCTAssertEqual(image.resized(1.5).width, 60)
        XCTAssertEqual(image.resized(0.5).height, 20)
        XCTAssertEqual(image.resized(1), image)
    }
}
