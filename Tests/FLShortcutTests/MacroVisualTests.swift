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
