// « Retrouver ce bouton s'il bouge » : recherche d'un bouton à son image (MacroVisual.swift).
import XCTest
@testable import FLShortcut

final class MacroVisualTests: XCTestCase {
    /// Fenêtre de 400 × 300 : fond en damier doux, et un « + » clair à chaque place donnée.
    private func window(plusAt places: [(x: Int, y: Int)]) -> GrayImage {
        let w = 400, h = 300
        var px = [UInt8](repeating: 0, count: w * h)
        for y in 0..<h {
            for x in 0..<w { px[y * w + x] = UInt8(40 + ((x / 20 + y / 20) % 2) * 10) }
        }
        for c in places {
            for d in -8...8 {
                for t in -2...2 {
                    px[(c.y + t) * w + c.x + d] = 230
                    px[(c.y + d) * w + c.x + t] = 230
                }
            }
        }
        return GrayImage(width: w, height: h, pixels: px)
    }

    private func plusImage() throws -> GrayImage {
        try XCTUnwrap(window(plusAt: [(100, 60)]).crop(centerX: 100, centerY: 60, side: VisualSpot.defaultSide))
    }

    func testButtonIsFoundWhereItMoved() throws {
        let hit = try XCTUnwrap(VisualMatch.find(try plusImage(), in: window(plusAt: [(100, 180)]), hint: (100, 60)))
        XCTAssertEqual(Double(hit.x), 100, accuracy: 1)
        XCTAssertEqual(Double(hit.y), 180, accuracy: 1, "le « + » est descendu de 120 points")
        XCTAssertGreaterThan(hit.score, 0.95)
    }

    func testMissingButtonIsNeverClickedBlindly() throws {
        XCTAssertNil(VisualMatch.find(try plusImage(), in: window(plusAt: []), hint: (100, 60)))
    }

    func testTwoIdenticalButtonsTheNearestWins() throws {
        let hit = try XCTUnwrap(VisualMatch.find(try plusImage(), in: window(plusAt: [(300, 240), (120, 100)]),
                                                 hint: (100, 60)))
        XCTAssertEqual(Double(hit.x), 120, accuracy: 1)
        XCTAssertEqual(Double(hit.y), 100, accuracy: 1)
    }

    func testFlatAreaIsNotAButton() {
        let flat = GrayImage(width: 26, height: 26, pixels: [UInt8](repeating: 90, count: 26 * 26))
        XCTAssertLessThan(flat.contrast, VisualMatch.minContrast)
        XCTAssertNil(VisualMatch.find(flat, in: window(plusAt: [(100, 60)]), hint: (100, 60)))
    }

    func testCropAndReduce() {
        let image = window(plusAt: [(100, 60)])
        XCTAssertNil(image.crop(centerX: 5, centerY: 5, side: 26), "le carré doit tenir dans la fenêtre")
        let small = image.reduced(by: 3)
        XCTAssertEqual(small.width, 133)
        XCTAssertEqual(small.height, 100)
    }

    func testSpotIsSavedInTheMacroAndRemovedFromShares() throws {
        let patch = try plusImage()
        let spot = VisualSpot(corner: .topLeft, dx: 100, dy: 60, size: CGSize(width: 400, height: 300), title: nil,
                              side: patch.width, pixels: patch.pixels)
        let target = ClickTarget.button(spot)
        XCTAssertTrue(target.isFinite)
        XCTAssertEqual(ClickTarget(json: target.json), target)
        XCTAssertTrue(target.isLearnedPosition, "image et place retirées à l'export")
        XCTAssertEqual(spot.place, .flWindow(corner: .topLeft, dx: 100, dy: 60, size: CGSize(width: 400, height: 300)))
        let broken = VisualSpot(corner: .topLeft, dx: 1, dy: 1, size: CGSize(width: 400, height: 300), side: 26,
                                pixels: [1, 2, 3])
        XCTAssertFalse(ClickTarget.button(broken).isFinite)
    }
}

/// Boutons retrouvés par leur nom (textes lus dans la fenêtre de FL).
final class NamedButtonTests: XCTestCase {
    private func item(_ text: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat = 14) -> TextLook.Item {
        TextLook.Item(text: text, box: CGRect(x: x, y: y, width: w, height: h))
    }

    func testTheClickedWordOrTheShortLabelIsKept() {
        // Barre de FL lue d'un bloc : le mot cliqué.
        let bar = [item("FILE EDIT ADD PATTERNS VIEW", 10, 5, 260), item("FILE", 10, 5, 30), item("EDIT", 46, 5, 30),
                   item("ADD", 82, 5, 26)]
        XCTAssertEqual(TextLook.label(at: CGPoint(x: 20, y: 11), in: bar)?.text, "FILE")
        XCTAssertEqual(TextLook.label(at: CGPoint(x: 90, y: 11), in: bar)?.text, "ADD")
        // Nom court d'une piste : le nom entier, pas « 1 ».
        let mixer = [item("Insert 1", 300, 400, 52), item("Insert", 300, 400, 36), item("1", 344, 400, 8)]
        XCTAssertEqual(TextLook.label(at: CGPoint(x: 346, y: 406), in: mixer)?.text, "Insert 1")
        // Juste à côté du texte (6 points) : encore lui ; plus loin, ou un simple chiffre : rien.
        XCTAssertEqual(TextLook.label(at: CGPoint(x: 297, y: 406), in: mixer)?.text, "Insert 1")
        XCTAssertNil(TextLook.label(at: CGPoint(x: 200, y: 200), in: mixer))
        XCTAssertNil(TextLook.label(at: CGPoint(x: 5, y: 5), in: [item("1", 0, 0, 10)]))
        // Entre deux mots d'une ligne : un des deux mots, jamais la ligne entière.
        XCTAssertNotEqual(TextLook.label(at: CGPoint(x: 43, y: 11), in: bar)?.text, "FILE EDIT ADD PATTERNS VIEW")
        XCTAssertNotNil(TextLook.label(at: CGPoint(x: 43, y: 11), in: bar))
        // Texte coupé au bord de la zone lue : jamais retenu.
        let region = CGRect(x: 0, y: 0, width: 100, height: 40)
        XCTAssertNil(TextLook.label(at: CGPoint(x: 90, y: 11), in: [item("PATTERNS", 80, 5, 40)], region: region))
        // Un affichage qui change avec le clic n'est pas un nom.
        XCTAssertFalse(TextLook.isUsable("Device : Built-in"))
        XCTAssertFalse(TextLook.isUsable("Mixer - Insert 3"))
        XCTAssertFalse(TextLook.isUsable("● REC"))
        XCTAssertTrue(TextLook.isUsable("Insert 1"))
    }

    func testNameIsFoundWhereverItMovedAndOCRSlipsAreForgiven() {
        let now = [item("Insert 2", 300, 400, 52), item("lnsert 1", 520, 400, 52), item("Master", 80, 400, 50)]
        // « Insert 1 » est passé à droite ; lu « lnsert 1 » cette fois : retrouvé quand même.
        let found = TextLook.find("Insert 1", in: now, near: CGPoint(x: 326, y: 407))
        XCTAssertEqual(found?.box.minX, 520)
        XCTAssertNil(TextLook.find("Insert 10", in: now, near: .zero), "jamais un autre nom")
        // Deux fois le même nom : le plus proche de sa place apprise.
        let twice = [item("Piano roll", 20, 40, 60), item("Piano roll", 600, 300, 60)]
        XCTAssertEqual(TextLook.find("PIANO ROLL", in: twice, near: CGPoint(x: 590, y: 290))?.box.minX, 600)
    }

    func testRecordedClickOnANamedButtonIsKeptByItsName() {
        let main = CGRect(x: 0, y: 0, width: 1200, height: 800)
        let window = WinInfo(number: 7, layer: 0, bounds: main, pid: 42, alpha: 1)
        var click = RecordedClick(point: CGPoint(x: 330, y: 300), right: false, windows: [window], menu: nil)
        click.named = NamedHit(label: "Insert 1", dx: 4, dy: 3)
        let result = ClickSequenceCompiler.compile([click])
        guard case .click(.named(let spot), .left)? = result.blocks.first else { return XCTFail("clic par son nom attendu") }
        XCTAssertEqual(spot.label, "Insert 1")
        XCTAssertEqual(spot.place, .flWindow(corner: .topLeft, dx: 330, dy: 300, size: main.size))
        // Gardé dans la macro, retiré des partages, et sans nom utilisable : sa place, comme avant.
        let target = ClickTarget.named(spot)
        XCTAssertEqual(ClickTarget(json: target.json), target)
        XCTAssertTrue(target.isLearnedPosition)
        click.named = NamedHit(label: "1", dx: 0, dy: 0)
        guard case .click(.flWindow, .left)? = ClickSequenceCompiler.compile([click]).blocks.first else {
            return XCTFail("un chiffre seul n'est pas un nom")
        }
    }
}
