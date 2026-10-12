import XCTest
@testable import FLShortcut

final class MacroGeometryTests: XCTestCase {
    private func win(_ n: Int, _ r: CGRect, layer: Int = 101) -> WinInfo { WinInfo(number: n, layer: layer, bounds: r, pid: 42, alpha: 1) }

    /// Menu que FL a remonté : le saut appris est relatif à la fenêtre du menu, il résiste donc à tout décalage.
    func testHopIsRelativeToThePopupNotTheClick() {
        let hop = MacroSpots.PopupHop(offset: CGVector(dx: 40, dy: 300), size: CGSize(width: 250, height: 690))
        let low = CGRect(x: 500, y: 200, width: 250, height: 690)       // remonté
        let high = CGRect(x: 900, y: 40, width: 262, height: 690)       // autre piste, titre plus large
        XCTAssertTrue(hop.fits(low)); XCTAssertTrue(hop.fits(high))
        XCTAssertEqual(hop.point(in: low), CGPoint(x: 540, y: 500))
        XCTAssertEqual(hop.point(in: high), CGPoint(x: 940, y: 340))
        XCTAssertFalse(hop.fits(CGRect(x: 0, y: 0, width: 250, height: 120)))   // fader / autre menu
    }

    func testResolveAttributesClicksToTheWindowFrontmostJustBefore() {
        let main = win(1, CGRect(x: 0, y: 0, width: 1400, height: 900), layer: 0)
        let menu = win(7, CGRect(x: 500, y: 200, width: 250, height: 690))
        let sub = win(8, CGRect(x: 750, y: 260, width: 220, height: 160))
        let h = [WinSnapshot(time: 1.0, fl: [main], panelService: []),
                 WinSnapshot(time: 1.2, fl: [menu, main], panelService: []),
                 WinSnapshot(time: 1.5, fl: [sub, menu, main], panelService: [])]
        let clicks = [ClickSample(point: CGPoint(x: 560, y: 270), time: 1.3),
                      ClickSample(point: CGPoint(x: 800, y: 300), time: 1.6)]
        let path = MacroSpots.resolve(clicks, history: h, base: [1], anchor: CGPoint(x: 600, y: 820), firstInWindow: false)
        XCTAssertEqual(path.hops.map(\.offset), [CGVector(dx: 60, dy: 70), CGVector(dx: 50, dy: 40)])
        XCTAssertEqual(path.hops.map(\.size), [menu.bounds.size, sub.bounds.size])
        XCTAssertNil(path.inline)
        XCTAssertTrue(path.isValid)
    }

    func testInlineMenusFallBackToExactReplay() {
        let main = win(1, CGRect(x: 0, y: 0, width: 1400, height: 900), layer: 0)
        let h = [WinSnapshot(time: 1.0, fl: [main], panelService: [])]
        let clicks = [ClickSample(point: CGPoint(x: 560, y: 270), time: 1.3)]
        let path = MacroSpots.resolve(clicks, history: h, base: [1], anchor: CGPoint(x: 600, y: 820), firstInWindow: false)
        XCTAssertTrue(path.hops.isEmpty)
        XCTAssertEqual(path.inline?.offsets, [CGVector(dx: -40, dy: -550)])
        XCTAssertTrue(path.isValid)
    }

    func testInputStartsFromWindowTopRight() {
        let main = win(1, CGRect(x: 0, y: 25, width: 1400, height: 875), layer: 0)
        let list = win(9, CGRect(x: 1200, y: 120, width: 160, height: 300))
        let h = [WinSnapshot(time: 1.0, fl: [main], panelService: []),
                 WinSnapshot(time: 1.4, fl: [list, main], panelService: [])]
        let clicks = [ClickSample(point: CGPoint(x: 1250, y: 110), time: 1.1),
                      ClickSample(point: CGPoint(x: 1230, y: 150), time: 1.5)]
        let path = MacroSpots.resolve(clicks, history: h, base: [1], anchor: .zero, firstInWindow: true)
        XCTAssertEqual(path.start?.fromTopRight, CGVector(dx: -150, dy: 85))
        XCTAssertEqual(path.hops.first?.offset, CGVector(dx: 30, dy: 30))
    }

    func testCorruptPathsAreRejected() {
        XCTAssertFalse(MacroSpots.MenuPath().isValid)
        var p = MacroSpots.MenuPath(hops: [.init(offset: CGVector(dx: 10, dy: 9000), size: CGSize(width: 200, height: 600))])
        XCTAssertFalse(p.isValid)
        p.hops = [.init(offset: CGVector(dx: 10, dy: 20), size: CGSize(width: 200, height: 600))]
        XCTAssertTrue(p.isValid)
    }
}
