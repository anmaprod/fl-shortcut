import CoreGraphics
import XCTest
@testable import FLShortcut

/// « Enregistrer des clics » : chaque clic devient un bloc, d'après les fenêtres de FL juste avant lui (relevés figés).
final class MacroClickSequenceTests: XCTestCase {
    private func win(_ n: Int, _ layer: Int, _ r: CGRect) -> WinInfo {
        WinInfo(number: n, layer: layer, bounds: r, pid: 42, alpha: 1)
    }

    /// OPTIONS dans la fenêtre de FL, « Audio settings » dans son menu, boutons de la fenêtre des réglages (niveau 8),
    /// puis le même menu par la barre des menus de macOS ; un clic hors de FL est ignoré.
    func testRecordedClicksBecomeBlocks() {
        let main = CGRect(x: 0, y: 25, width: 1440, height: 875)
        let menu = CGRect(x: 120, y: 60, width: 200, height: 120)
        let settings = CGRect(x: 400, y: 200, width: 520, height: 428)
        let history = [
            WinSnapshot(time: 1, fl: [win(1, 0, main)], panelService: []),
            WinSnapshot(time: 2, fl: [win(7, 101, menu), win(1, 0, main)], panelService: []),
            WinSnapshot(time: 3, fl: [win(9, 8, settings), win(1, 0, main)], panelService: []),
            WinSnapshot(time: 5, fl: [win(1, 0, main)], panelService: []),
        ]
        let clicks = [
            RecordedClick(point: CGPoint(x: 150, y: 40), time: 1.5, right: false, menu: nil),
            RecordedClick(point: CGPoint(x: 140, y: 100), time: 2.5, right: false, menu: nil),
            RecordedClick(point: CGPoint(x: 430, y: 260), time: 3.5, right: false, menu: nil),
            RecordedClick(point: CGPoint(x: 900, y: 600), time: 3.6, right: true, menu: nil),
            RecordedClick(point: CGPoint(x: 60, y: 10), time: 5.5, right: false, menu: .bar("Options")),
            RecordedClick(point: CGPoint(x: 80, y: 60), time: 6, right: false, menu: .item(["Options", "Audio settings"])),
            RecordedClick(point: CGPoint(x: 2000, y: 10), time: 6.5, right: false, menu: nil),
        ]
        let r = ClickSequenceCompiler.compile(clicks, history: history)
        XCTAssertEqual(r.blocks, [
            .click(.flWindow(corner: .topLeft, dx: 150, dy: 15, size: main.size), button: .left),
            .click(.openMenu(MacroSpots.PopupHop(offset: CGVector(dx: 20, dy: 40), size: menu.size)), button: .left),
            .click(.flWindow(corner: .topLeft, dx: 30, dy: 60, size: settings.size), button: .left),
            .click(.flWindow(corner: .bottomRight, dx: -20, dy: -28, size: settings.size), button: .right),
            .menuBar(titles: ["Options", "Audio settings"]),
        ])
        XCTAssertEqual(r.ignored, 1)
    }

    /// Menu de la barre ouvert puis refermé par un clic ailleurs : macOS avale ce clic, FL ne le reçoit pas.
    func testMenuBarOpenedThenClosedIsIgnored() {
        let main = CGRect(x: 0, y: 25, width: 800, height: 600)
        let history = [WinSnapshot(time: 0, fl: [win(1, 0, main)], panelService: [])]
        let clicks = [
            RecordedClick(point: CGPoint(x: 60, y: 10), time: 1, right: false, menu: .bar("Options")),
            RecordedClick(point: CGPoint(x: 300, y: 300), time: 2, right: false, menu: nil),
            RecordedClick(point: CGPoint(x: 310, y: 300), time: 3, right: false, menu: nil),
            RecordedClick(point: CGPoint(x: 60, y: 10), time: 4, right: false, menu: .bar("Tools")),
        ]
        let r = ClickSequenceCompiler.compile(clicks, history: history)
        XCTAssertEqual(r.blocks, [.click(.flWindow(corner: .topLeft, dx: 310, dy: 275, size: main.size), button: .left)])
        XCTAssertEqual(r.ignored, 3)
    }

    func testMenuBarPathIsValidatedAndNeverLogged() {
        let ctx = ValidationContext(forbidden: .physical)
        let spec = BlockRegistry.spec(.menuBar)
        XCTAssertNil(spec.valider(.menuBar(titles: ["Options", "Audio settings"]), ctx))
        XCTAssertNotNil(spec.valider(.menuBar(titles: ["Options"]), ctx))
        XCTAssertNotNil(spec.valider(.menuBar(titles: ["Options", " "]), ctx))
        XCTAssertNotNil(spec.valider(.menuBar(titles: Array(repeating: "Niveau", count: MenuBarAX.maxDepth + 1)), ctx))
        XCTAssertEqual(BlockRegistry.journal(of: .menuBar(titles: ["Secret", "Voix"])), "menuBar")
        XCTAssertFalse(spec.dansLaPalette)
    }
}
