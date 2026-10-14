import AppKit
import XCTest
@testable import FLShortcut

/// Créateur de macros : nom vide enregistré « Macro sans nom », essai refusé affiché « non lancé », titre d'un
/// raccourci relié à la bibliothèque. Store et bibliothèque en mémoire.
final class MacroEditorModelTests: XCTestCase {
    private func makeStore() -> Store {
        Store(storage: MemoryProfileStorage(data: try? ProfileCodec.encode([])), layout: FakeLayout.qwerty,
              defaults: UserDefaults(suiteName: "FLShortcutTests-\(UUID())")!, systemHotKeys: { [:] },
              pushToTap: false, saveDelay: 0,
              library: MacroLibraryStore(storage: MemoryMacroLibraryStorage(), saveDelay: 0))
    }

    func testEmptyNameSavedAsUntitled() {
        let store = makeStore()
        let doc = store.library.add(MacroDoc(name: "Voix", blocks: [Block(.delay(ms: 100))]))
        let model = MacroEditorModel(store: store)
        model.load(doc.id)
        model.rename("   ")
        model.saveNow()
        XCTAssertEqual(store.library.doc(doc.id)?.name, MacroEditorModel.untitled)
        model.close()
    }

    func testRefuseIsNotAnOutcome() {
        let monitor = MacroRunMonitor()
        monitor.refuse("Ouvre FL Studio, puis recommence.")
        XCTAssertEqual(monitor.refusal, "Ouvre FL Studio, puis recommence.")
        XCTAssertNil(monitor.outcome)
        monitor.clear()
        XCTAssertNil(monitor.refusal)
    }

    func testRemapTitleForMacroRef() {
        let store = makeStore()
        let doc = store.library.add(MacroDoc(name: "Prise de voix", blocks: [Block(.delay(ms: 100))]))
        XCTAssertEqual(store.remapTitle(Remap(trigger: KeyCombo(keyCode: 1, command: true), macroRef: doc.id)),
                       "Macro : Prise de voix")
        XCTAssertEqual(store.remapTitle(Remap(trigger: KeyCombo(keyCode: 1, command: true), macroRef: UUID())),
                       "Macro : introuvable (supprimée ?)")
    }
}
