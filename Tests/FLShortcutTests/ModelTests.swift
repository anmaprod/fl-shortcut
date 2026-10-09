import CoreGraphics
import XCTest
@testable import FLShortcut

/// REL-01 : décodage tolérant, migration v1, actions inconnues conservées ; profils ; Store.
final class ModelTests: XCTestCase {
    private func json(_ s: String) -> Data { Data(s.utf8) }

    func testV1ArrayMigratesWithoutLosingRows() throws {
        let v1 = json("""
        [
          {"trigger": {"keyCode": 48}, "kind": "flAction", "action": "togglePlaylistMixer"},
          {"id": "3F2504E0-4F89-11D3-9A0C-0305E82C3301", "enabled": true, "kind": "flAction",
           "action": "loopMode", "trigger": {"keyCode": 37, "control": true}},
          {"kind": "keystroke", "trigger": {"keyCode": 0, "control": true}, "target": {"keyCode": 1, "command": true},
           "action": "playPause"}
        ]
        """)
        let decoded = try ProfileCodec.decode(v1)
        XCTAssertEqual(decoded.sourceVersion, 1)
        XCTAssertEqual(decoded.dropped, 0)
        XCTAssertEqual(decoded.remaps.count, 3)

        let first = decoded.remaps[0]
        XCTAssertTrue(first.enabled)                                // champ absent : défaut
        XCTAssertEqual(first.actionID, 35)                          // togglePlaylistMixer → plmx
        XCTAssertEqual(first.trigger, KeyCombo(keyCode: 48))

        let second = decoded.remaps[1]
        XCTAssertNil(second.actionID)                               // loopMode n'existe plus
        XCTAssertEqual(second.unknownAction, "loopMode")
        XCTAssertFalse(second.enabled)                              // jamais exécuter une action devinée

        let third = decoded.remaps[2]
        XCTAssertEqual(third.kind, .keystroke)
        XCTAssertNil(third.actionID)
        XCTAssertEqual(third.target, KeyCombo(keyCode: 1, command: true))
    }

    func testAllV1ActionNamesMap() {
        for (name, id) in FLActions.v1Names {
            XCTAssertTrue(FLActions.isKnown(id), name)
        }
        XCTAssertEqual(FLActions.all.count, 38)
        XCTAssertEqual(Set(FLActions.all.map(\.id)), Set(1...38))
    }

    func testV2RoundTrip() throws {
        var a = Remap(trigger: KeyCombo(keyCode: 18, control: true), action: 30, context: .pianoRoll)
        a.enabled = false
        let b = Remap(trigger: KeyCombo(keyCode: 1, option: true), sends: KeyCombo(keyCode: 1, command: true))
        let data = try ProfileCodec.encode([a, b])
        let decoded = try ProfileCodec.decode(data)
        XCTAssertEqual(decoded.sourceVersion, 2)
        XCTAssertEqual(decoded.remaps, [a, b])
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(text.contains("\"action\" : \"pl\""))
        XCTAssertTrue(text.contains("\"version\" : 2"))
    }

    func testUnknownFutureActionKeptAndPreserved() throws {
        let data = json("""
        {"version": 3, "remaps": [
          {"trigger": {"keyCode": 2, "control": true}, "kind": "flAction", "action": "teleport", "actionID": 77},
          {"trigger": {"keyCode": 3, "control": true}, "kind": "flAction", "action": "pnext", "context": "arranger"},
          {"trigger": {"keyCode": 4, "control": true}, "kind": "macro"},
          {"trigger": {"keyCode": 5, "control": true}, "kind": "flAction", "action": "save"}
        ]}
        """)
        let decoded = try ProfileCodec.decode(data)
        XCTAssertEqual(decoded.remaps.count, 4)
        XCTAssertEqual(decoded.remaps[0].unknownAction, "teleport")
        XCTAssertFalse(decoded.remaps[0].enabled)
        XCTAssertEqual(decoded.remaps[1].actionID, 13)
        XCTAssertFalse(decoded.remaps[1].enabled)                  // contexte inconnu : désactivé
        XCTAssertEqual(decoded.remaps[2].unknownAction, "type:macro")
        XCTAssertEqual(decoded.remaps[3].actionID, 38)
        XCTAssertTrue(decoded.remaps[3].enabled)

        let again = try ProfileCodec.decode(ProfileCodec.encode(decoded.remaps))
        XCTAssertEqual(again.remaps[0].unknownAction, "teleport")  // rien n'est perdu à la réécriture
    }

    func testBrokenElementsDoNotLoseTheRest() throws {
        let data = json("""
        {"version": 2, "remaps": [
          5,
          {"trigger": {"keyCode": "abc"}, "kind": "flAction", "action": "play"},
          {"trigger": {"keyCode": 12, "command": "oui"}, "kind": "flAction", "action": "stop"}
        ]}
        """)
        let decoded = try ProfileCodec.decode(data)
        XCTAssertEqual(decoded.dropped, 1)
        XCTAssertEqual(decoded.remaps.count, 2)
        XCTAssertNil(decoded.remaps[0].trigger)                    // trigger illisible, ligne gardée
        XCTAssertEqual(decoded.remaps[1].trigger, KeyCombo(keyCode: 12))   // modificateur illisible : faux
    }

    func testDuplicateIDsAreReplaced() throws {
        let id = UUID().uuidString
        let data = json("""
        {"version": 2, "remaps": [{"id": "\(id)", "action": "play"}, {"id": "\(id)", "action": "stop"}]}
        """)
        let decoded = try ProfileCodec.decode(data)
        XCTAssertEqual(Set(decoded.remaps.map(\.id)).count, 2)
    }

    func testUnreadableProfileThrows() {
        XCTAssertThrowsError(try ProfileCodec.decode(json("{\"remaps\": ")))
        XCTAssertThrowsError(try ProfileCodec.decode(json("\"texte\"")))
    }

    func testRecommendedPresetHasNoBareKeysNorSpacesConflicts() {
        let remaps = ProfilePreset.recommended.remaps(layout: FakeLayout.qwerty)
        XCTAssertEqual(remaps.count, 11)
        XCTAssertTrue(remaps.allSatisfy { $0.trigger?.hasModifiers == true })
        let triggers = Set(remaps.compactMap(\.trigger))
        XCTAssertFalse(triggers.contains(KeyCombo(keyCode: 123, control: true)))
        XCTAssertFalse(triggers.contains(KeyCombo(keyCode: 124, control: true)))
        XCTAssertTrue(triggers.contains(KeyCombo(keyCode: 3, control: true)))      // ⌃F
        XCTAssertTrue(remaps.allSatisfy { $0.actionID.map(FLActions.isKnown) == true })
    }

    func testPresetsWithRussianLayoutFallBackToQWERTYPositions() {
        let remaps = ProfilePreset.recommended.remaps(layout: FakeLayout.russian)
        let triggers = Set(remaps.compactMap(\.trigger))
        XCTAssertTrue(triggers.contains(KeyCombo(keyCode: 46, control: true)))     // ⌃M → 46
        XCTAssertTrue(triggers.contains(KeyCombo(keyCode: 6, command: true, shift: true)))
        XCTAssertTrue(ProfilePreset.empty.remaps(layout: FakeLayout.qwerty).isEmpty)
        XCTAssertTrue(ProfilePreset.ableton.remaps(layout: FakeLayout.qwerty).contains { $0.trigger == KeyCombo(keyCode: 48) })
    }

    func testKeyComboIgnoresFnNumPadCapsLock() {
        let combo = KeyCombo(keyCode: 124, flags: [.maskControl, .maskSecondaryFn, .maskNumericPad, .maskAlphaShift])
        XCTAssertEqual(combo, KeyCombo(keyCode: 124, control: true))
        XCTAssertFalse(KeyCombo(keyCode: 56).isValidKey)            // ⇧ seul
        XCTAssertFalse(KeyCombo(keyCode: 200).isValidKey)
        XCTAssertTrue(KeyCombo(keyCode: 82).isValidKey)             // 0 du pavé
    }

    // MARK: Store

    private func makeStore(_ storage: MemoryProfileStorage) -> Store {
        Store(storage: storage, layout: FakeLayout.qwerty, defaults: UserDefaults(suiteName: "FLShortcutTests-\(UUID())")!,
              systemHotKeys: { [:] }, pushToTap: false, saveDelay: 0)
    }

    func testFirstLaunchFreezesRecommendedProfile() {
        let storage = MemoryProfileStorage()
        let store = makeStore(storage)
        XCTAssertEqual(store.remaps.count, 11)
        XCTAssertEqual(storage.writes, 1)
        XCTAssertNil(store.loadWarning)
    }

    func testCorruptProfileIsBackedUpAndNotOverwritten() {
        let storage = MemoryProfileStorage(data: json("{ cassé"))
        let store = makeStore(storage)
        XCTAssertEqual(storage.writes, 0)
        XCTAssertEqual(storage.backups.count, 1)
        XCTAssertNotNil(store.loadWarning)
        XCTAssertEqual(store.remaps.count, 11)
    }

    func testV1ProfileIsBackedUpThenMigrated() throws {
        let storage = MemoryProfileStorage(data: json("[{\"trigger\": {\"keyCode\": 48}, \"action\": \"stop\"}]"))
        let store = makeStore(storage)
        XCTAssertEqual(store.remaps.first?.actionID, 2)
        XCTAssertEqual(storage.backups.count, 1)
        XCTAssertEqual(storage.writes, 1)
        let written = try ProfileCodec.decode(XCTUnwrap(storage.data))
        XCTAssertEqual(written.sourceVersion, 2)
    }

    func testSaveErrorIsPublished() {
        let storage = MemoryProfileStorage(data: try? ProfileCodec.encode([]))
        let store = makeStore(storage)
        storage.writeError = SecureFile.Failure.symlink("/x")
        store.saveNow()
        XCTAssertNotNil(store.saveError)
    }

    func testPresetReplacementCanBeUndone() {
        let store = makeStore(MemoryProfileStorage(data: try? ProfileCodec.encode([])))
        store.apply(preset: .ableton)
        XCTAssertFalse(store.remaps.isEmpty)
        store.undoReplace()
        XCTAssertTrue(store.remaps.isEmpty)
    }
}
