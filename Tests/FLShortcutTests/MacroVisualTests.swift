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

/// Bouton mute d'une piste du Mixer montré une fois (MacroMuteSolo.swift), retrouvé sur la piste cliquée.
final class MuteSwitchTests: XCTestCase {
    /// Mixer de 7 pistes de 55 points ; bouton mute de chaque piste au centre de sa colonne, à 40 points du haut.
    /// `muted` : pistes dont le bouton est éteint ; `without` : pistes sans bouton visible.
    private func mixer(muted: Set<Int> = [], without: Set<Int> = []) -> GrayImage {
        let w = 400, h = 300
        var px = [UInt8](repeating: 45, count: w * h)
        for i in 0..<7 {
            for y in 0..<h { px[y * w + i * 55] = 70 }                       // séparation des pistes
            guard !without.contains(i) else { continue }
            let cx = i * 55 + 27, cy = 40
            for y in (cy - 7)...(cy + 7) {
                for x in (cx - 7)...(cx + 7) {
                    let d = ((x - cx) * (x - cx) + (y - cy) * (y - cy))
                    if d <= 25 { px[y * w + x] = muted.contains(i) ? 75 : 210 }
                    else if d <= 42 { px[y * w + x] = 120 }                   // contour
                }
            }
        }
        return GrayImage(width: w, height: h, pixels: px)
    }

    private func learned() throws -> MuteSwitch {
        let on = try XCTUnwrap(MuteSwitch.patch(of: mixer(), at: CGPoint(x: 27, y: 40)))
        let off = try XCTUnwrap(MuteSwitch.patch(of: mixer(muted: [0]), at: CGPoint(x: 27, y: 40)))
        return MuteSwitch(dy: 40, side: MuteSwitch.defaultSide, patches: [on, off])
    }

    func testTheClickedTracksSwitchIsFoundInBothStates() throws {
        let spot = try learned()
        XCTAssertTrue(spot.isValid)
        let image = mixer(muted: [3])
        // Piste 4 (éteinte) cliquée à droite de son centre ; piste 6 (allumée) cliquée à gauche.
        let muted = try XCTUnwrap(spot.locate(in: image, expected: CGPoint(x: 3 * 55 + 27 + 12, y: 40)))
        XCTAssertEqual(Double(muted.x), 192, accuracy: 1)
        XCTAssertEqual(Double(muted.y), 40, accuracy: 1)
        let lit = try XCTUnwrap(spot.locate(in: image, expected: CGPoint(x: 5 * 55 + 27 - 15, y: 40)))
        XCTAssertEqual(Double(lit.x), 302, accuracy: 1)
    }

    func testNeverAnotherTracksSwitch() throws {
        let spot = try learned()
        // Seule la première piste a un bouton : rien n'est pris dans une autre colonne.
        XCTAssertNil(spot.locate(in: mixer(without: [1, 2, 3, 4, 5, 6]), expected: CGPoint(x: 300, y: 40)))
        XCTAssertNil(spot.locate(in: GrayImage(width: 400, height: 300, pixels: [UInt8](repeating: 45, count: 400 * 300)),
                                 expected: CGPoint(x: 100, y: 40)))
        XCTAssertNil(MuteSwitch.patch(of: mixer(), at: CGPoint(x: 2, y: 2)), "bord de l'image")
    }

    func testKeptOnThisMacOnly() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "app.flshortcut.tests.\(UUID().uuidString)"))
        XCTAssertNil(MuteSwitch.load(defaults))
        let spot = try learned()
        spot.save(defaults)
        XCTAssertEqual(MuteSwitch.load(defaults), spot)
        MuteSwitch(dy: 40, side: 16, patches: [Data([1, 2, 3])]).save(defaults)
        XCTAssertNil(MuteSwitch.load(defaults), "image abîmée : pas retenu")
        MuteSwitch(dy: 40, side: 16, patches: []).save(defaults)
        XCTAssertNotNil(MuteSwitch.load(defaults), "sans lecture de l'écran : la hauteur seule")
        MuteSwitch.forget(defaults)
        XCTAssertNil(MuteSwitch.load(defaults))
    }

    func testMuteAndSoloWorkWithoutTheScript() {
        for key in ["mute", "solo"] {
            let needs = BlockRegistry.needs(of: .flAction(key: key, fallback: .none))
            XCTAssertTrue(needs.contains(.pisteVisee), "\(key) : la piste cliquée est retenue")
            XCTAssertTrue(MuteSolo.handlesWithoutLink(key))
        }
        XCTAssertFalse(MuteSolo.handlesWithoutLink("bypass"))
        let items = PaletteCatalog.items(layout: FakeLayout.qwerty)
        XCTAssertTrue(items.contains { $0.id == "mute" && $0.make() == .flAction(key: "mute", fallback: .none) })
        XCTAssertTrue(items.contains { $0.id == "solo" && $0.make() == .flAction(key: "solo", fallback: .none) })
    }
}
