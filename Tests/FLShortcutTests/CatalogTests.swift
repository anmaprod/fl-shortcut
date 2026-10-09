// Catalogue par fenêtre (retours utilisateur) et mesure du temps de réponse de FL.
import XCTest
@testable import FLShortcut

final class CatalogTests: XCTestCase {
    private func makeStore() -> Store {
        Store(storage: MemoryProfileStorage(), layout: FakeLayout.qwerty,
              defaults: UserDefaults(suiteName: "FLShortcutTests-\(UUID())")!,
              systemHotKeys: { [:] }, pushToTap: false, saveDelay: 0)
    }

    func testEveryActionAndEverySectionIsInTheCatalog() {
        let entries = Catalog.entries(layout: FakeLayout.qwerty)
        XCTAssertEqual(Set(entries.map(\.id)).count, entries.count, "identifiants uniques")
        let actionIDs = Set(entries.compactMap { e -> Int? in if case .action(let id) = e.kind { return id }; return nil })
        XCTAssertEqual(actionIDs, Set(FLActions.all.map(\.id)), "les 38 actions sont rangées dans une section")
        for section in FLSection.allCases {
            XCTAssertFalse(entries.filter { $0.section == section }.isEmpty, "\(section) vide")
        }
        XCTAssertGreaterThanOrEqual(entries.filter(\.isNative).count, 250, "raccourcis d'origine de FL")
        for e in entries where e.isNative {
            XCTAssertTrue(e.defaultTrigger?.isValidKey ?? false, e.id)
        }
    }

    func testNativeShortcutsDoNotRepeatInsideAWindow() {
        let entries = Catalog.entries(layout: FakeLayout.qwerty).filter(\.isNative)
        for section in FLSection.allCases {
            let combos = entries.filter { $0.section == section }.compactMap(\.defaultTrigger)
            XCTAssertEqual(Set(combos).count, combos.count, "doublon dans \(section)")
        }
    }

    func testChangingAndResettingANativeShortcut() throws {
        let store = makeStore()
        let row = try XCTUnwrap(store.catalogRows().rows.first { $0.entry.id == "fl.pianoRoll.p" })
        XCTAssertTrue(row.isDefault)
        let custom = KeyCombo(keyCode: 35, control: true)          // ⌃P
        store.setTrigger(custom, for: row)
        let changed = try XCTUnwrap(store.catalogRows().rows.first { $0.entry.id == "fl.pianoRoll.p" })
        XCTAssertEqual(changed.current, custom)
        XCTAssertFalse(changed.isDefault)
        XCTAssertEqual(changed.remap?.kind, .keystroke)
        XCTAssertEqual(changed.remap?.context, .pianoRoll)        // seulement dans le Piano Roll
        XCTAssertEqual(changed.remap?.target, row.entry.defaultTrigger)
        store.reset(changed)
        let back = try XCTUnwrap(store.catalogRows().rows.first { $0.entry.id == "fl.pianoRoll.p" })
        XCTAssertTrue(back.isDefault)
        XCTAssertNil(back.remap)
    }

    func testChangingAndResettingAnAction() throws {
        let store = makeStore()
        let row = try XCTUnwrap(store.catalogRows().rows.first { $0.entry.id == "action.mx" })
        let original = row.current
        XCTAssertNotNil(original)                                  // ⌃4 dans le profil Recommandé
        store.setTrigger(nil, for: row)
        XCTAssertNil(store.catalogRows().rows.first { $0.entry.id == "action.mx" }?.current)
        let cleared = try XCTUnwrap(store.catalogRows().rows.first { $0.entry.id == "action.mx" })
        store.reset(cleared)
        XCTAssertEqual(store.catalogRows().rows.first { $0.entry.id == "action.mx" }?.current, original)
    }

    func testResponseTimeIsMeasuredFromFrameToAck() {
        let transport = FakeTransport()
        let core = LinkCore(transport: transport, key: Array(UInt8(0)..<UInt8(16)))
        core.receive(Bytes.hello(nonce: [1, 2, 3, 4], caps: Bytes.allCaps))
        XCTAssertNil(core.snapshot.responseMs)
        XCTAssertEqual(core.sendAction(33), .sent(seq: 1))
        core.receive(Bytes.cc(119, 33))
        let ms = core.snapshot.responseMs
        XCTAssertNotNil(ms)
        XCTAssertLessThan(ms ?? .infinity, 1000)
        XCTAssertEqual(LinkCore.median([5, 1, 3]), 3)
        XCTAssertEqual(LinkCore.median([4, 2]), 3)
    }
}
