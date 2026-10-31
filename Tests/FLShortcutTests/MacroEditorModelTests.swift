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

    /// Clics enregistrés : ajoutés dans l'ordre sous le bloc choisi, en une seule étape d'annulation.
    func testRecordedClicksInsertedInOrderUnderSelection() {
        let store = makeStore()
        let first = Block(.delay(ms: 100)), last = Block(.delay(ms: 200))
        let doc = store.library.add(MacroDoc(name: "Réglages", blocks: [first, last]))
        let model = MacroEditorModel(store: store)
        let undo = UndoManager()
        undo.groupsByEvent = false
        model.undoManager = undo
        model.load(doc.id)
        model.selection = MacroStepRow.blockRowID(first.id)
        let menu = BlockBody.menuBar(titles: ["Options", "Audio settings"])
        let click = BlockBody.click(.flWindow(corner: .topLeft, dx: 30, dy: 60, size: CGSize(width: 520, height: 428)), button: .left)
        undo.beginUndoGrouping()
        model.insertRecorded(ClickSequenceCompiler.Result(blocks: [menu, click], ignored: 1))
        undo.endUndoGrouping()
        XCTAssertEqual(model.draft?.blocks.map(\.body), [.delay(ms: 100), menu, click, .delay(ms: 200)])
        XCTAssertEqual(model.notice, "2 blocs ajoutés d'après tes clics et tes touches. 1 geste hors de FL (ou dans un menu refermé) ignoré.")
        undo.undo()
        XCTAssertEqual(model.draft?.blocks.map(\.body), [.delay(ms: 100), .delay(ms: 200)])
        model.insertRecorded(ClickSequenceCompiler.Result(blocks: [], ignored: 2))
        XCTAssertEqual(model.notice, "Aucun clic ni aucune touche dans FL enregistrés. 2 gestes hors de FL (ou dans un menu refermé) ignorés.")
        model.close()
    }

    /// Bloc glissé de la palette : lâché avant la 2e ligne, il devient le 2e ; avant la ligne de fin d'une boucle,
    /// le dernier de la boucle ; après la dernière ligne, tout en bas.
    func testPaletteDropInsertsAtTheChosenRow() {
        let store = makeStore()
        let loop = Block(.repeatCount(2, [Block(.delay(ms: 1))]))
        let doc = store.library.add(MacroDoc(name: "Ordre", blocks: [Block(.delay(ms: 100)), Block(.delay(ms: 200)), loop]))
        let model = MacroEditorModel(store: store)
        model.load(doc.id)
        let key = PaletteCatalog.items(layout: FakeLayout.qwerty).first { $0.id == "key" }!
        // Lignes : 0 pause 100, 1 pause 200, 2 boucle, 3 pause 1 (dans la boucle), 4 fin de la boucle.
        model.insert(key, beforeRow: 1)
        XCTAssertEqual(model.draft?.blocks.map(\.body.type), [.delay, .key, .delay, .repeatCount])
        let endRow = model.rows.firstIndex { if case .end = $0.kind { return true }; return false }!
        model.insert(key, beforeRow: endRow)
        XCTAssertEqual(model.draft?.blocks.last?.body.children.first?.map(\.body.type), [.delay, .key])
        model.insert(key, beforeRow: model.rows.count)
        XCTAssertEqual(model.draft?.blocks.last?.body.type, .key)
        XCTAssertEqual(model.draft?.blocks.count, 5)
        model.close()
    }

    /// Flèche ← : macro neuve vide supprimée sans question ; neuve avec des blocs → « Enregistrer / Supprimer » ;
    /// existante modifiée → « Enregistrer / Annuler les modifications » (retour à l'état de l'ouverture) ; sinon rien.
    func testLeavingTheCreator() {
        let store = makeStore()
        let model = MacroEditorModel(store: store)
        model.newMacro()
        let empty = try! XCTUnwrap(model.draft)
        XCTAssertEqual(model.leaveCheck(), .discardEmpty)
        model.discardNew()
        XCTAssertNil(store.library.doc(empty.id))

        model.newMacro()
        let fresh = try! XCTUnwrap(model.draft)
        let key = PaletteCatalog.items(layout: FakeLayout.qwerty).first { $0.id == "key" }!
        model.insert(key)
        XCTAssertEqual(model.leaveCheck(), .askNew(name: fresh.name))
        model.discardNew()
        XCTAssertNil(store.library.doc(fresh.id))

        let doc = store.library.add(MacroDoc(name: "Voix", blocks: [Block(.delay(ms: 100))]))
        model.load(doc.id)
        XCTAssertEqual(model.leaveCheck(), .close)
        model.rename("Voix lead")
        model.insert(key)
        model.saveNow()
        XCTAssertEqual(model.leaveCheck(), .askChanges(name: "Voix lead"))
        model.revertChanges()
        XCTAssertEqual(store.library.doc(doc.id)?.name, "Voix")
        XCTAssertEqual(store.library.doc(doc.id)?.blocks, doc.blocks)
        XCTAssertEqual(model.leaveCheck(), .close)
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
