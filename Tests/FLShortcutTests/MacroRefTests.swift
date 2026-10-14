import XCTest
@testable import FLShortcut

/// Raccourci → macro de la bibliothèque (`Remap.macroRef`), lien caché pour les anciennes versions, Store.
final class MacroRefTests: XCTestCase {
    private let trigger = KeyCombo(keyCode: 46, option: true, control: true)

    private func makeStore(_ library: MacroLibraryStore) -> Store {
        Store(storage: MemoryProfileStorage(data: try? ProfileCodec.encode([])), layout: FakeLayout.qwerty,
              defaults: UserDefaults(suiteName: "FLShortcutTests-\(UUID())")!, systemHotKeys: { [:] },
              pushToTap: false, saveDelay: 0, library: library)
    }

    private func object(_ data: Data) throws -> [String: Any] {
        let file = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try XCTUnwrap((file["remaps"] as? [[String: Any]])?.first)
    }

    func testMacroRefRoundTripWritesTheHiddenLink() throws {
        let id = UUID()
        let data = try ProfileCodec.encode([Remap(trigger: trigger, macroRef: id)])
        let raw = try object(data)
        XCTAssertEqual(raw["kind"] as? String, "macro")
        XCTAssertEqual(raw["macroRef"] as? String, id.uuidString)
        XCTAssertEqual(raw["unknownAction"] as? String, "macroRef:" + id.uuidString)
        XCTAssertNil(raw["macro"])
        let back = try ProfileCodec.decode(data).remaps[0]
        XCTAssertEqual(back.macroRef, id)
        XCTAssertNil(back.unknownAction)                         // le lien caché n'est qu'un format d'écriture
        XCTAssertEqual(back.kind, Remap.Kind.macro)
    }

    /// Une ancienne version relit le profil, ignore `macroRef` et le réécrit sans : le lien caché (qu'elle garde)
    /// suffit à retrouver la macro.
    func testOlderVersionRewriteIsRecoveredFromTheHiddenLink() throws {
        let id = UUID()
        var raw = try object(ProfileCodec.encode([Remap(trigger: trigger, macroRef: id)]))
        raw.removeValue(forKey: "macroRef")
        let rewritten = try JSONSerialization.data(withJSONObject: ["version": 2, "remaps": [raw]])
        let back = try ProfileCodec.decode(rewritten).remaps[0]
        XCTAssertEqual(back.macroRef, id)
        XCTAssertNil(back.macro)
        // Réécrit par cette version : la clé revient.
        XCTAssertEqual(try object(ProfileCodec.encode([back]))["macroRef"] as? String, id.uuidString)
    }

    /// Dans l'ancienne version, l'utilisateur a remis le modèle « Enregistrement rapide » sur ce raccourci : le
    /// modèle garde la priorité, le lien caché périmé disparaît.
    func testInlineMacroWinsOverAStaleLink() throws {
        var raw = try object(ProfileCodec.encode([Remap(trigger: trigger, macro: Macro())]))
        raw["unknownAction"] = "macroRef:" + UUID().uuidString
        let data = try JSONSerialization.data(withJSONObject: ["version": 2, "remaps": [raw]])
        let back = try ProfileCodec.decode(data).remaps[0]
        XCTAssertNil(back.macroRef)
        XCTAssertEqual(back.macro?.template, .autoRecord)
        XCTAssertNil(try object(ProfileCodec.encode([back]))["unknownAction"])
    }

    func testProfileImportRefusesLibraryMacros() throws {
        let data = try ProfileCodec.encode([Remap(trigger: trigger, macroRef: UUID())])
        let preview = try ProfileImporter.prepare(data, forbidden: .physical, layout: FakeLayout.qwerty)
        XCTAssertTrue(preview.remaps.isEmpty)
        XCTAssertTrue(preview.rejected.first?.contains(".flsmacro") == true)
    }

    // MARK: Store

    func testLibraryMacroIsIndexedAndItsNeedsAggregated() {
        let library = MacroLibraryStore(storage: MemoryMacroLibraryStorage(), saveDelay: 0)
        let doc = library.add(MacroDoc(name: "Armer", blocks: [Block(.flAction(key: "armon", fallback: .trackMenuArm))]))
        let store = makeStore(library)
        XCTAssertFalse(store.activeNeeds.contains(.pisteVisee))
        store.upsert(Remap(trigger: trigger, macroRef: doc.id))
        XCTAssertFalse(store.issues(for: store.remaps[0].id).contains(where: \.isBlocking))
        guard case .macro(let program)? = store.index.lookup(trigger, window: nil)?.action else {
            return XCTFail("macro attendue dans l'index")
        }
        XCTAssertEqual(program.source, MacroProgram.Source.blocks(id: doc.id, revision: 0))
        XCTAssertTrue(store.activeNeeds.contains(.pisteVisee))
        XCTAssertTrue(store.activeNeeds.contains(.lienMIDI))
        // Modifiée dans la bibliothèque : l'index suit (nouvelle révision), sans toucher au profil.
        var changed = doc
        changed.blocks = [Block(.delay(ms: 100))]
        library.update(changed)
        guard case .macro(let updated)? = store.index.lookup(trigger, window: nil)?.action else { return XCTFail() }
        XCTAssertEqual(updated.source, MacroProgram.Source.blocks(id: doc.id, revision: 1))
        XCTAssertFalse(store.activeNeeds.contains(.pisteVisee))
    }

    func testMissingOrInvalidLibraryMacroBlocksTheShortcut() {
        let library = MacroLibraryStore(storage: MemoryMacroLibraryStorage(), saveDelay: 0)
        let store = makeStore(library)
        let orphan = Remap(trigger: trigger, macroRef: UUID())
        store.upsert(orphan)
        XCTAssertTrue(store.issues(for: orphan.id).contains { $0.isBlocking })
        XCTAssertNil(store.index.lookup(trigger, window: nil))
        let empty = library.add(MacroDoc(name: "Vide", blocks: []))
        let other = Remap(trigger: KeyCombo(keyCode: 17, control: true), macroRef: empty.id)
        store.upsert(other)
        XCTAssertTrue(store.issues(for: other.id).contains { $0.isBlocking })
    }

    /// Le modèle livré garde exactement ses besoins (mémoire de la piste, ports MIDI à la demande).
    func testTemplateNeedsAreUnchanged() {
        let store = makeStore(MacroLibraryStore(storage: MemoryMacroLibraryStorage(), saveDelay: 0))
        var m = Macro()
        m.recKey = KeyCombo(keyCode: 15)
        store.upsert(Remap(trigger: trigger, macro: m))
        XCTAssertTrue(store.activeNeeds.isSuperset(of: [.pisteVisee, .lienMIDI]))
        m.armAndInput = false
        m.startRecording = false
        store.remaps = [Remap(trigger: trigger, macro: m)]
        XCTAssertTrue(store.activeNeeds.contains(.pisteVisee))
        XCTAssertFalse(store.activeNeeds.contains(.lienMIDI))
        // Désactivé : plus rien n'est suivi.
        store.remaps[0].enabled = false
        XCTAssertTrue(store.activeNeeds.isEmpty)
        // Un essai dans le créateur annonce ses besoins.
        store.setEditorNeeds([.pisteVisee])
        XCTAssertEqual(store.activeNeeds, [.pisteVisee])
        store.setEditorNeeds([])
        XCTAssertTrue(store.activeNeeds.isEmpty)
    }
}
