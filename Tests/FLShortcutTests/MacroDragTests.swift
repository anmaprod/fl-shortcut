import CoreGraphics
import Foundation
import XCTest
@testable import FLShortcut

/// Bloc « Glisser-déposer » : modèle, validation, export, geste montré dans FL, points du glissé.
final class MacroDragTests: XCTestCase {
    private let ctx = ValidationContext(forbidden: .physical, strictFiles: true)
    private let size = CGSize(width: 1200, height: 800)

    private var learned: BlockBody {
        .drag(from: .flWindow(corner: .topLeft, dx: 40, dy: 120, size: size),
              to: .flWindow(corner: .topRight, dx: -300, dy: 200, size: size))
    }

    func testJSONRoundTripAndValidation() throws {
        let block = Block(learned)
        let data = try JSONEncoder().encode(block)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "drag")
        XCTAssertEqual(try JSONDecoder().decode(Block.self, from: data), block)

        let spec = BlockRegistry.spec(.drag)
        XCTAssertNil(spec.valider(learned, ctx))
        XCTAssertNotNil(spec.valider(.drag(from: .toLearn, to: .lastClick(dx: 0, dy: 0)), ctx))
        XCTAssertNotNil(spec.valider(.drag(from: .lastClick(dx: 0, dy: 0), to: .toLearn), ctx))
        XCTAssertNotNil(spec.valider(.drag(from: .lastClick(dx: .infinity, dy: 0), to: .startCursor(dx: 0, dy: 0)), ctx))
        let menu = MacroSpots.PopupHop(offset: CGVector(dx: 20, dy: 30), size: CGSize(width: 200, height: 300))
        XCTAssertNotNil(spec.valider(.drag(from: .openMenu(menu), to: .startCursor(dx: 0, dy: 0)), ctx))
        XCTAssertTrue(spec.needs(learned).contains(.cliqueHID))
        XCTAssertFalse(spec.needs(learned).contains(.pisteVisee))
        XCTAssertTrue(spec.needs(.drag(from: .track(dx: 0, dy: 0), to: .lastClick(dx: 0, dy: 0))).contains(.pisteVisee))
        XCTAssertEqual(BlockRegistry.journal(of: learned), "drag")
    }

    func testToLearnShownInEditorAndBlocksTheMacro() {
        let fresh = Block(.drag(from: .toLearn, to: .toLearn))
        let rows = MacroOutline.rows([fresh], layout: FakeLayout.qwerty, context: ctx, learnedInput: true)
        XCTAssertEqual(rows.first?.verb, "Glisser-déposer")
        XCTAssertEqual(rows.first?.value, "à montrer dans FL")
        XCTAssertTrue(rows.first?.badges.contains { if case .aApprendre = $0 { return true } else { return false } } ?? false)
        XCTAssertTrue(MacroOutline.flags([fresh], learnedInput: true).toLearn)
        XCTAssertFalse(MacroOutline.flags([Block(learned)], learnedInput: true).toLearn)
        let program = MacroProgram(blocks: [fresh], name: "x", source: .blocks(id: UUID(), revision: 0), context: ctx)
        XCTAssertNotNil(program.problem)
    }

    func testPositionsRemovedOnExport() {
        let shared = MacroExchange.sharable([Block(learned)], home: "/Users/x")
        XCTAssertEqual(shared.first?.body, .drag(from: .toLearn, to: .toLearn))
        let relative = BlockBody.drag(from: .lastClick(dx: 10, dy: 0), to: .startCursor(dx: 0, dy: 0))
        XCTAssertEqual(MacroExchange.sharable([Block(relative)], home: "/Users/x").first?.body, relative)
    }

    func testDragShownInFL() {
        let main = CGRect(x: 100, y: 100, width: 1200, height: 800)
        let windows: [(layer: Int, bounds: CGRect)] = [(0, main)]
        // Du Browser (en haut à gauche) vers la Playlist (en haut à droite) : chaque bout relatif à son coin.
        let shown = MacroOutline.dragTargets(from: CGPoint(x: 140, y: 220), to: CGPoint(x: 1000, y: 300), windows: windows)
        XCTAssertEqual(shown, .shown(from: .flWindow(corner: .topLeft, dx: 40, dy: 120, size: main.size),
                                     to: .flWindow(corner: .topRight, dx: -300, dy: 200, size: main.size)))
        XCTAssertEqual(MacroOutline.dragTargets(from: CGPoint(x: 140, y: 220), to: CGPoint(x: 142, y: 221), windows: windows),
                       .tooShort)
        XCTAssertEqual(MacroOutline.dragTargets(from: CGPoint(x: 140, y: 220), to: CGPoint(x: 5, y: 5), windows: windows),
                       .outside, "lâché hors de FL")
        let menu = CGRect(x: 300, y: 150, width: 200, height: 300)
        XCTAssertEqual(MacroOutline.dragTargets(from: CGPoint(x: 320, y: 200), to: CGPoint(x: 1000, y: 300),
                                                windows: [(101, menu), (0, main)]), .outside, "jamais depuis un menu")
    }

    func testDragSteps() {
        let a = CGPoint(x: 100, y: 100)
        let near = MacroEffectsMac.dragSteps(from: a, to: CGPoint(x: 110, y: 100))
        XCTAssertEqual(near.count, 8, "8 pas au moins")
        XCTAssertEqual(near.last, CGPoint(x: 110, y: 100))
        let far = MacroEffectsMac.dragSteps(from: a, to: CGPoint(x: 1100, y: 600))
        XCTAssertEqual(far.count, 30, "30 pas au plus")
        XCTAssertEqual(far.last, CGPoint(x: 1100, y: 600))
        let mid = MacroEffectsMac.dragSteps(from: a, to: CGPoint(x: 400, y: 100))
        XCTAssertEqual(mid.count, 15)
        XCTAssertTrue(zip(mid, mid.dropFirst()).allSatisfy { $0.x < $1.x }, "toujours vers l'arrivée")
    }
}
