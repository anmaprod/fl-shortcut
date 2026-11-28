import AppKit
import XCTest
@testable import FLShortcut

/// Faux FL du menu de l'en-tête d'une piste : un clic droit ouvre le menu, un clic sur « Consolidate… » le referme,
/// Échap ferme la fenêtre de devant.
private final class FakeTrackMenuFL: IconPlacementDriver {
    static let main = WinInfo(number: 1, layer: 0, bounds: CGRect(x: 0, y: 0, width: 1400, height: 900), pid: 7, alpha: 1)
    static let menu = WinInfo(number: 2, layer: 101, bounds: CGRect(x: 200, y: 300, width: 240, height: 420), pid: 7, alpha: 1)
    static let item = CGPoint(x: 260, y: 640)

    var open: [WinInfo] = [main]
    var events: [String] = []
    var menuOpens = true
    var reading = IconPlacement.MenuRead.found(item)

    func windows() -> [WinInfo] { open }
    func press(_ key: KeyCombo) {
        events.append(key.keyCode == 53 ? "Échap" : "touche \(key.keyCode)")
        if key.keyCode == 53, let front = open.first, front != Self.main { open.removeFirst() }
    }
    func rightClick(_ p: CGPoint) -> Bool {
        events.append("clic droit")
        if menuOpens { open.insert(Self.menu, at: 0) }
        return true
    }
    func readItem(_ label: String, in menu: WinInfo) -> IconPlacement.MenuRead {
        XCTFail("lecture exacte inattendue")
        return .unreadable
    }
    func readItem(startingWith prefix: String, in menu: WinInfo) -> IconPlacement.MenuRead {
        XCTAssertEqual(prefix, "Consolidate")
        return reading
    }
    func click(_ p: CGPoint) -> Bool {
        if open.first == Self.menu, p == Self.item {
            events.append("Consolidate")
            open.removeFirst()
        } else {
            events.append("clic ailleurs")
        }
        return true
    }
    func wait(_ seconds: TimeInterval) -> Bool { true }
    func learnClick(in window: WinInfo, hint: String) -> CGPoint? { nil }
}

final class ConsolidateTests: XCTestCase {
    private func item(_ text: String, y: CGFloat) -> TextLook.Item {
        TextLook.Item(text: text, box: CGRect(x: 10, y: y, width: 150, height: 14))
    }

    /// Le menu de l'en-tête de la Playlist : l'élément qui commence par « Consolidate » (le plus haut), lu sans casse.
    func testItemFoundByTheStartOfItsName() {
        let items = [item("Rename, color and icon...", y: 10), item("Consolidate this track (from first clip)", y: 300),
                     item("CONSOLIDATE THIS TRACK", y: 280), item("Change icon...", y: 40)]
        XCTAssertEqual(TrackMenuPick.item(startingWith: "Consolidate", in: items)?.box.minY, 280)
        XCTAssertNil(TrackMenuPick.item(startingWith: "Consolidate", in: [item("Arm disk recording", y: 10)]))
        XCTAssertNil(TrackMenuPick.item(startingWith: "", in: items))
    }

    func testConsolidateClickedInTheMenu() {
        let fl = FakeTrackMenuFL()
        XCTAssertEqual(TrackMenuPick.pick("Consolidate", at: CGPoint(x: 120, y: 330), driver: fl), .clicked)
        XCTAssertEqual(fl.events, ["clic droit", "Consolidate"])
        XCTAssertEqual(fl.open, [FakeTrackMenuFL.main])
    }

    /// Menu du Mixer ou du Channel rack (sans « Consolidate ») ou illisible : refermé par Échap, rien cliqué.
    func testMenuWithoutConsolidateIsClosed() {
        for (reading, outcome) in [(IconPlacement.MenuRead.absent, TrackMenuPick.Outcome.notInMenu), (.unreadable, .unreadable)] {
            let fl = FakeTrackMenuFL()
            fl.reading = reading
            XCTAssertEqual(TrackMenuPick.pick("Consolidate", at: CGPoint(x: 120, y: 330), driver: fl), outcome)
            XCTAssertEqual(fl.events, ["clic droit", "Échap"])
            XCTAssertEqual(fl.open, [FakeTrackMenuFL.main])
        }
        let fl = FakeTrackMenuFL()
        fl.menuOpens = false
        XCTAssertEqual(TrackMenuPick.pick("Consolidate", at: CGPoint(x: 120, y: 330), driver: fl), .noMenu)
        XCTAssertEqual(fl.events, ["clic droit"])
    }

    /// Une action faite dans la fenêtre de FL : jamais le lien, jamais regroupée, valide seulement sans repli.
    func testConsolidateIsALocalAction() {
        XCTAssertNil(FLActions.id(forKey: "consolidate"))
        XCTAssertFalse(FLActions.offered.contains { $0.key == "consolidate" })
        let block = Block(.flAction(key: "consolidate", fallback: .none))
        XCTAssertTrue(block.flActionRunsAlone)
        let needs = BlockRegistry.spec(.flAction).needs(block.body)
        XCTAssertFalse(needs.contains(.lienMIDI))
        XCTAssertTrue(needs.contains(.pisteVisee))
        XCTAssertEqual(BlockRegistry.spec(.flAction).resume(block.body, SystemKeyboardLayout()), "Consolider la piste dans la Playlist")
    }
}
