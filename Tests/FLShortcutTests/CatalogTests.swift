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

    /// « Mes raccourcis » : vide au départ ; un raccourci changé y arrive, un raccourci créé aussi, jamais une macro.
    func testMyShortcutsListsOnlyWhatYouChangedOrCreated() throws {
        let store = makeStore()
        var data = store.catalogRows()
        XCTAssertEqual(MyShortcuts.count(rows: data.rows, others: data.others, starters: store.freshRemaps()), 0,
                       "rien de changé au départ, même les raccourcis de départ sans ligne (sans le lien avec FL)")
        let row = try XCTUnwrap(data.rows.first { $0.entry.id == "fl.pianoRoll.p" })
        store.setTrigger(KeyCombo(keyCode: 35, control: true), for: row)                 // ⌃P
        let created = Remap(trigger: KeyCombo(keyCode: 5, control: true),                  // ⌃G : créé à la main
                            sends: KeyCombo(keyCode: 111, option: true, shift: true))    // ⌥⇧F12, hors catalogue
        store.upsert(created)
        store.upsert(Remap(trigger: KeyCombo(keyCode: 9, control: true), macroRef: UUID()))   // ⌃V : une macro
        data = store.catalogRows()
        XCTAssertEqual(MyShortcuts.changed(data.rows).map(\.id), ["fl.pianoRoll.p"])
        XCTAssertEqual(MyShortcuts.created(data.others, starters: store.freshRemaps()).map(\.id), [created.id])
        XCTAssertEqual(MyShortcuts.count(rows: data.rows, others: data.others, starters: store.freshRemaps()), 2)
        store.reset(try XCTUnwrap(data.rows.first { $0.entry.id == "fl.pianoRoll.p" }))
        data = store.catalogRows()
        XCTAssertTrue(MyShortcuts.changed(data.rows).isEmpty, "revenu à la touche d'origine : il repart")
    }

    func testSearchWithAShortcutFindsWhatItDoesNowAndInFL() throws {
        let store = makeStore()
        let row = try XCTUnwrap(store.catalogRows().rows.first { $0.entry.id == "fl.pianoRoll.p" })
        let original = try XCTUnwrap(row.entry.defaultTrigger)
        XCTAssertTrue(KeySearch.matches(row, original))
        let custom = KeyCombo(keyCode: 35, control: true)          // ⌃P
        store.setTrigger(custom, for: row)
        let changed = try XCTUnwrap(store.catalogRows().rows.first { $0.entry.id == "fl.pianoRoll.p" })
        XCTAssertTrue(KeySearch.matches(changed, custom), "sa touche actuelle")
        XCTAssertTrue(KeySearch.matches(changed, original), "celle qu'on connaît de FL")
        XCTAssertFalse(KeySearch.matches(changed, KeyCombo(keyCode: 35, command: true, control: true)))
    }

    /// 07/11 : plus d'« Actions en plus » qui doublent une touche de FL (Ouvrir le Mixer = F9) ; le ⌃4 du profil
    /// Recommandé reste un de tes raccourcis, hors des lignes de FL.
    func testActionsThatDoubleAnFLKeyAreNotListed() throws {
        let store = makeStore()
        let (rows, others) = store.catalogRows()
        XCTAssertFalse(rows.contains { if case .action = $0.entry.kind { return true } else { return false } })
        XCTAssertNotNil(rows.first { $0.entry.id == "fl.general.f9" }, "la ligne de FL reste")
        XCTAssertEqual(others.first { $0.actionID == 33 }?.trigger, KeyCombo(keyCode: 21, control: true))
    }

    // Une touche ne sert qu'une fois : annonce, reprise, et proposition de rechoisir pour l'autre raccourci.
    func testAKeyCanOnlyBeUsedOnce() throws {
        let store = makeStore()
        let rows = store.catalogRows().rows
        let pianoP = try XCTUnwrap(rows.first { $0.entry.id == "fl.pianoRoll.p" })
        let taken = KeyCombo(keyCode: 21, control: true)            // ⌃4 du profil Recommandé (Ouvrir le Mixer)
        let found = store.clashes(for: taken, editing: pianoP)
        XCTAssertEqual(found.count, 1)
        XCTAssertNil(found[0].row)
        XCTAssertFalse(found[0].isFLKey)
        let follow = store.release(found)
        store.setTrigger(taken, for: pianoP)
        XCTAssertNil(follow)
        let after = store.catalogRows()
        XCTAssertNil(after.others.first { $0.actionID == 33 }?.trigger)
        XCTAssertEqual(after.rows.first { $0.entry.id == "fl.pianoRoll.p" }?.current, taken)
        // Revenir à sa propre touche d'origine n'est jamais un conflit (doublons propres à FL).
        XCTAssertTrue(store.clashes(for: try XCTUnwrap(pianoP.entry.defaultTrigger), editing: pianoP).isEmpty)
    }

    /// Essai 2.1 du 13/11 (« ça fait 1>2>1 ») : deux raccourcis de FL échangent leurs touches sans boucle. Le premier
    /// prend la touche du second (on propose de rechoisir pour le second), puis le second prend l'ancienne touche du
    /// premier : plus aucun conflit, aucune touche signalée prise.
    func testTwoFLKeysCanBeSwapped() throws {
        let store = makeStore()
        var rows = store.catalogRows().rows
        func key(_ row: CatalogRow) -> KeyCombo? {
            if case .native(let k) = row.entry.kind { return k }
            return nil
        }
        let used = Set(store.remaps.filter(\.enabled).compactMap(\.trigger))
        let natives = rows.filter { key($0) != nil }
        let unique = natives.filter { row in
            natives.filter { key($0) == key(row) }.count == 1 && !used.contains(key(row)!) && row.current == key(row)
        }
        XCTAssertGreaterThanOrEqual(unique.count, 2)
        let first = unique[0], second = unique[1]
        let a = try XCTUnwrap(key(first)), b = try XCTUnwrap(key(second))

        let found = store.clashes(for: b, editing: first)
        XCTAssertTrue(found.contains { $0.id == second.id && $0.isFLKey })
        XCTAssertEqual(store.release(found), second.id, "on propose de rechoisir pour le second")
        store.setTrigger(b, for: first)
        rows = store.catalogRows().rows
        let secondNow = try XCTUnwrap(rows.first { $0.id == second.id })
        XCTAssertTrue(store.clashes(for: a, editing: secondNow).isEmpty, "le premier a quitté sa touche : elle est libre")
        store.setTrigger(a, for: secondNow)
        rows = store.catalogRows().rows
        XCTAssertEqual(rows.first { $0.id == first.id }?.current, b)
        XCTAssertEqual(rows.first { $0.id == second.id }?.current, a)
        XCTAssertNil(rows.first { $0.id == first.id }?.takenBy)
        XCTAssertNil(rows.first { $0.id == second.id }?.takenBy)
    }

    func testTakingAnFLKeyIsAnnouncedAndFlagged() throws {
        let store = makeStore()
        let rows = store.catalogRows().rows
        let metro = try XCTUnwrap(rows.first { $0.entry.id == "fl.transport.cmd-m" })
        let pianoP = try XCTUnwrap(rows.first { $0.entry.id == "fl.pianoRoll.p" })
        let cmdM = try XCTUnwrap(metro.entry.defaultTrigger)
        XCTAssertTrue(store.clashes(for: cmdM, editing: pianoP).contains { $0.id == metro.id && $0.isFLKey })
        store.setTrigger(cmdM, for: pianoP)
        XCTAssertEqual(store.catalogRows().rows.first { $0.id == metro.id }?.takenBy, pianoP.entry.title)
        XCTAssertNil(store.catalogRows().rows.first { $0.id == pianoP.id }?.takenBy)
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
