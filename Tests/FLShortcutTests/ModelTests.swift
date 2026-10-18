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
        XCTAssertEqual(FLActions.all.count, 40)
        XCTAssertEqual(Set(FLActions.all.map(\.id)), Set(1...40))
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

    /// « + » d'une page : le raccourci garde sa page (listé sur elle) et vise sa fenêtre de FL. Une page inconnue
    /// (version plus récente) est ignorée sans perdre le raccourci.
    func testShortcutPageRoundTripAndListing() throws {
        var a = Remap(trigger: KeyCombo(keyCode: 18, control: true), action: 30, context: .mixer)
        a.page = .mixer
        var b = Remap(trigger: KeyCombo(keyCode: 19, control: true), action: 2)
        b.page = .transport
        let c = Remap(trigger: KeyCombo(keyCode: 20, control: true), action: 3, context: .playlist)   // sans page
        let decoded = try ProfileCodec.decode(try ProfileCodec.encode([a, b, c]))
        XCTAssertEqual(decoded.remaps, [a, b, c])
        XCTAssertTrue(a.belongs(to: .mixer))
        XCTAssertFalse(a.belongs(to: .playlist))
        XCTAssertTrue(b.belongs(to: .transport))
        XCTAssertFalse(b.belongs(to: .general))
        XCTAssertTrue(c.belongs(to: .playlist))                     // ancien raccourci : par sa fenêtre
        XCTAssertFalse(Remap(trigger: nil, action: 1).belongs(to: .general))
        XCTAssertEqual(ShortcutContext(page: .channelRack), .channelRack)
        XCTAssertEqual(ShortcutContext(page: .patterns), .everywhere)
        let future = json("""
        {"version": 2, "remaps": [{"trigger": {"keyCode": 1}, "kind": "flAction", "action": "play", "page": "demain"}]}
        """)
        let read = try ProfileCodec.decode(future)
        XCTAssertEqual(read.remaps.count, 1)
        XCTAssertNil(read.remaps[0].page)
        XCTAssertTrue(read.remaps[0].enabled)
    }

    func testUnknownFutureActionKeptAndPreserved() throws {
        let data = json("""
        {"version": 3, "remaps": [
          {"trigger": {"keyCode": 2, "control": true}, "kind": "flAction", "action": "teleport", "actionID": 77},
          {"trigger": {"keyCode": 3, "control": true}, "kind": "flAction", "action": "pnext", "context": "arranger"},
          {"trigger": {"keyCode": 4, "control": true}, "kind": "teleportKind"},
          {"trigger": {"keyCode": 5, "control": true}, "kind": "flAction", "action": "save"}
        ]}
        """)
        let decoded = try ProfileCodec.decode(data)
        XCTAssertEqual(decoded.remaps.count, 4)
        XCTAssertEqual(decoded.remaps[0].unknownAction, "teleport")
        XCTAssertFalse(decoded.remaps[0].enabled)
        XCTAssertEqual(decoded.remaps[1].actionID, 13)
        XCTAssertFalse(decoded.remaps[1].enabled)                  // contexte inconnu : désactivé
        XCTAssertEqual(decoded.remaps[2].unknownAction, "type:teleportKind")    // « macro » est désormais connu (MacroTests)
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
        XCTAssertEqual(remaps.count, 12)
        XCTAssertTrue(remaps.allSatisfy { $0.trigger?.hasModifiers == true })
        let triggers = Set(remaps.compactMap(\.trigger))
        XCTAssertFalse(triggers.contains(KeyCombo(keyCode: 123, control: true)))
        XCTAssertFalse(triggers.contains(KeyCombo(keyCode: 124, control: true)))
        XCTAssertTrue(triggers.contains(KeyCombo(keyCode: 3, control: true)))      // ⌃F
        XCTAssertTrue(remaps.filter { $0.kind == .flAction }.allSatisfy { $0.actionID.map(FLActions.isKnown) == true })
        XCTAssertEqual(remaps.filter { $0.kind == .macro }.map(\.trigger), [KeyCombo(keyCode: 15, control: true)])   // ⌃R
    }

    func testPresetsWithRussianLayoutFallBackToQWERTYPositions() {
        let remaps = ProfilePreset.recommended.remaps(layout: FakeLayout.russian)
        let triggers = Set(remaps.compactMap(\.trigger))
        XCTAssertTrue(triggers.contains(KeyCombo(keyCode: 46, control: true)))     // ⌃M → 46
        XCTAssertTrue(triggers.contains(KeyCombo(keyCode: 6, command: true, shift: true)))
        XCTAssertTrue(ProfilePreset.empty.remaps(layout: FakeLayout.qwerty).isEmpty)
        XCTAssertTrue(ProfilePreset.ableton.remaps(layout: FakeLayout.qwerty).contains {
            $0.trigger == KeyCombo(keyCode: 101) && $0.target == KeyCombo(keyCode: 15)                  // F9 → R
        })
    }

    /// Ableton et Logic dans FL : chaque touche envoie une touche de FL autorisée (sans le script), une seule fois par
    /// fenêtre, quelle que soit la disposition ; seul « rétablir » demande le script.
    func testAbletonAndLogicPresetsSendFLKeys() {
        for preset in [ProfilePreset.ableton, .logic] {
            for layout in [FakeLayout.qwerty, FakeLayout.azerty, FakeLayout.russian] {
                let remaps = preset.remaps(layout: layout)
                let forbidden = ForbiddenTargets.make(layout: layout)
                XCTAssertGreaterThanOrEqual(remaps.count, 20, preset.label)
                XCTAssertEqual(remaps.filter { $0.kind == .flAction }.map(\.actionID), [37], preset.label)
                var seen = Set<String>()
                for r in remaps {
                    guard let trigger = r.trigger else { return XCTFail("\(preset.label) : raccourci sans touche") }
                    XCTAssertTrue(trigger.isValidKey, preset.label)
                    XCTAssertTrue(seen.insert("\(trigger.display) \(r.context.rawValue)").inserted,
                                  "\(preset.label) : \(trigger.display) deux fois dans \(r.context.label)")
                    guard r.kind == .keystroke else { continue }
                    guard let target = r.target else { return XCTFail("\(preset.label) : touche de FL manquante") }
                    XCTAssertTrue(target.isValidKey, preset.label)
                    XCTAssertNil(forbidden.reason(for: target), "\(preset.label) : \(target.display)")
                    XCTAssertNotEqual(trigger, target, preset.label)
                }
            }
        }
        let logic = ProfilePreset.logic.remaps(layout: FakeLayout.qwerty)
        XCTAssertTrue(logic.contains { $0.trigger == KeyCombo(keyCode: 7) && $0.target == KeyCombo(keyCode: 101) })   // X → F9
        XCTAssertTrue(logic.contains {
            $0.trigger == KeyCombo(keyCode: 36) && $0.target == KeyCombo(keyCode: 115) && $0.context == .playlist  // ↩ → ↖
        })
    }

    /// 5 exemples de macros prêts : touches de FL seulement, raccourcis ⌃⇧ distincts hors du profil Recommandé, donnés
    /// à la copie s'ils sont libres (déjà pris : la copie reste sans raccourci).
    func testMacroExamplesGetTheirShortcutWhenFree() {
        let store = makeStore(MemoryProfileStorage(data: try? ProfileCodec.encode([])))
        let examples = MacroTemplates.examples(layout: FakeLayout.qwerty)
        XCTAssertEqual(examples.count, 5)
        let combos = examples.compactMap(\.shortcut)
        XCTAssertEqual(Set(combos).count, 5)
        XCTAssertTrue(combos.allSatisfy { $0.control && $0.shift && !$0.command && !$0.option })
        let recommended = Set(ProfilePreset.recommended.remaps(layout: FakeLayout.qwerty).compactMap(\.trigger))
        XCTAssertTrue(recommended.isDisjoint(with: combos))
        let gallery = Set(MacroTemplates.gallery(layout: FakeLayout.qwerty).map(\.id))
        XCTAssertTrue(gallery.isSuperset(of: examples.map(\.id)))
        for t in examples {
            let doc = t.make(FakeLayout.qwerty)
            XCTAssertNil(MacroProgram.compile(doc, forbidden: .physical).problem, t.id)
            XCTAssertFalse(doc.blocks.contains { if case .click = $0.body { return true } else { return false } },
                           "\(t.id) : rien à apprendre")
        }

        let doc = store.library.add(examples[0].make(FakeLayout.qwerty))
        XCTAssertTrue(store.giveShortcutIfFree(combos[0], toMacro: doc.id))
        XCTAssertEqual(store.remaps(forMacro: doc.id).map(\.trigger), [combos[0]])
        let again = store.library.add(examples[0].make(FakeLayout.qwerty))
        XCTAssertFalse(store.giveShortcutIfFree(combos[0], toMacro: again.id), "déjà pris : sans raccourci")
        XCTAssertTrue(store.remaps(forMacro: again.id).isEmpty)
    }

    /// Chargé, le profil Ableton se lit sur les lignes de FL : « Dupliquer la sélection à droite » (Playlist) prend ⌘D.
    func testAbletonPresetShownOnFLRows() {
        let store = makeStore(MemoryProfileStorage(data: try? ProfileCodec.encode([])))
        store.apply(preset: .ableton)
        let rows = store.catalogRows().rows
        let duplicate = rows.first { $0.id == "fl.playlist.cmd-b" }
        XCTAssertEqual(duplicate?.current, KeyCombo(keyCode: 2, command: true))
        XCTAssertEqual(rows.first { $0.id == "fl.transport.r" }?.current, KeyCombo(keyCode: 101))      // F9
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
        XCTAssertEqual(store.remaps.count, 12)
        XCTAssertEqual(storage.writes, 1)
        XCTAssertNil(store.loadWarning)
    }

    func testCorruptProfileIsBackedUpAndNotOverwritten() {
        let storage = MemoryProfileStorage(data: json("{ cassé"))
        let store = makeStore(storage)
        XCTAssertEqual(storage.writes, 0)
        XCTAssertEqual(storage.backups.count, 1)
        XCTAssertNotNil(store.loadWarning)
        XCTAssertEqual(store.remaps.count, 12)
    }

    func testV1ProfileIsBackedUpThenMigrated() throws {
        let storage = MemoryProfileStorage(data: json("[{\"trigger\": {\"keyCode\": 48}, \"action\": \"stop\"}]"))
        let store = makeStore(storage)
        XCTAssertEqual(store.remaps.first?.actionID, 2)
        XCTAssertEqual(storage.backups.count, 1)
        XCTAssertEqual(storage.writes, 1)
        let written = try ProfileCodec.decode(XCTUnwrap(storage.data))
        XCTAssertEqual(written.sourceVersion, 2)
        XCTAssertEqual(store.remaps.last?.kind, .macro)            // macro d'exemple ajoutée une fois
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

    /// Relecture 11 : un nom d'action importé ne peut pas maquiller l'interface (bidi, largeur nulle, longueur).
    func testImportedTextIsCleanedForDisplay() {
        XCTAssertEqual("tele\u{202E}port".displaySafe(), "teleport")
        XCTAssertEqual("a\u{0}\n\u{200B}b".displaySafe(), "ab")
        XCTAssertEqual(String(repeating: "x", count: 500).displaySafe(), String(repeating: "x", count: 40) + "…")
    }
}
