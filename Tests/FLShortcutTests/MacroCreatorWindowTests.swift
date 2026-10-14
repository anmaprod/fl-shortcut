import AppKit
import XCTest
@testable import FLShortcut

/// Créateur de macros : fenêtre AppKit vraiment libérée à la fermeture, fermeture idempotente qui arrête tout,
/// besoins (ports MIDI, dernière piste cliquée) annoncés seulement pendant « Tester ». Store et bibliothèque en
/// mémoire : jamais les fichiers de l'utilisateur, jamais le tap ni les ports MIDI.
final class MacroCreatorWindowTests: XCTestCase {
    private var savedConfig: TapConfig?

    override func setUp() {
        super.setUp()
        _ = NSApplication.shared                         // NSApp existe : fenêtres, activation
        savedConfig = EventTap.shared.currentConfig
    }

    override func tearDown() {
        ClickTeacher.shared.cancel(nil)
        if let savedConfig { EventTap.shared.updateConfig { $0 = savedConfig } }
        super.tearDown()
    }

    private func makeLibrary() -> MacroLibraryStore {
        MacroLibraryStore(storage: MemoryMacroLibraryStorage(), saveDelay: 0)
    }

    private func makeStore(_ library: MacroLibraryStore) -> Store {
        Store(storage: MemoryProfileStorage(data: try? ProfileCodec.encode([])), layout: FakeLayout.qwerty,
              defaults: UserDefaults(suiteName: "FLShortcutTests-\(UUID())")!, systemHotKeys: { [:] },
              pushToTap: false, saveDelay: 0, library: library)
    }

    /// Fait tourner la boucle principale (blocs différés, minuteries) jusqu'à `condition`, `timeout` au plus.
    private func spin(until condition: () -> Bool = { false }, timeout: TimeInterval = 3) {
        let end = Date().addingTimeInterval(timeout)
        while !condition(), Date() < end {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    /// Tient lieu de FL : un processus que NSRunningApplication connaît (le test lui-même, sinon le Dock). Rien
    /// n'est lancé ; l'app ne le voit jamais au premier plan (frontmostPID reste 0).
    private func standInFL() throws -> Int32 {
        let me = ProcessInfo.processInfo.processIdentifier
        if NSRunningApplication(processIdentifier: me) != nil { return me }
        return try XCTUnwrap(NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock")
            .first?.processIdentifier)
    }

    /// « Tester » avec FL présent mais jamais devant : l'essai reste en préparation (2 s au plus).
    private func startTest(_ model: MacroEditorModel) throws {
        let pid = try standInFL()
        EventTap.shared.updateConfig {
            $0.flPIDs = [pid]
            $0.frontmostPID = 0
        }
        model.test()
        XCTAssertTrue(model.preparingTest, "l'essai doit attendre FL")
    }

    /// Ouvrir puis fermer, deux fois de suite : fenêtre et modèle libérés à chaque fermeture, rien ne s'accumule.
    func testControllerReleasesModelOnClose() {
        let before = MacroEditorModel.liveCount
        let controller = MacroCreatorWindowController(store: makeStore(makeLibrary()))
        for cycle in 1...2 {
            autoreleasepool { controller.show() }
            XCTAssertTrue(controller.isOpen)
            XCTAssertEqual(MacroEditorModel.liveCount, before + 1, "cycle \(cycle) : un seul modèle ouvert")
            spin(timeout: 0.3)                           // la vue s'affiche (onAppear)
            autoreleasepool { controller.close() }
            XCTAssertFalse(controller.isOpen)
            spin(until: { MacroEditorModel.liveCount == before })
            XCTAssertEqual(MacroEditorModel.liveCount, before, "cycle \(cycle) : modèle encore vivant après fermeture")
        }
    }

    /// Deux fermetures : un seul enregistrement, besoins rendus ; ensuite plus rien n'est enregistré ni lancé.
    func testCloseIsIdempotent() throws {
        let library = makeLibrary()
        let store = makeStore(library)
        let doc = library.add(MacroDoc(name: "Solo", blocks: [Block(.flAction(key: "solo", fallback: .none))]))
        let model = MacroEditorModel(store: store)
        model.load(doc.id)
        try startTest(model)
        XCTAssertFalse(store.activeNeeds.isEmpty)
        model.rename("Solo de la piste")                 // enregistrement différé en attente
        let revision = try XCTUnwrap(library.doc(doc.id)).revision

        model.close()
        model.close()
        XCTAssertEqual(library.doc(doc.id)?.revision, revision + 1)
        XCTAssertEqual(library.doc(doc.id)?.name, "Solo de la piste")
        XCTAssertTrue(store.activeNeeds.isEmpty)
        XCTAssertFalse(model.preparingTest)

        model.rename("Après la fermeture")
        model.test()
        spin(timeout: 0.8)                               // au-delà de l'enregistrement différé (0,5 s)
        XCTAssertEqual(library.doc(doc.id)?.revision, revision + 1)
        XCTAssertEqual(library.doc(doc.id)?.name, "Solo de la piste")
        XCTAssertTrue(store.activeNeeds.isEmpty)
        XCTAssertFalse(model.preparingTest)
        XCTAssertFalse(model.monitor.running)
    }

    /// Fermer pendant « Montrer dans FL… » : l'apprentissage s'arrête, le brouillon est enregistré tel quel, et un
    /// endroit retenu après coup n'écrit plus rien dans la bibliothèque.
    func testCloseCancelsTeachingAndKeepsDraft() throws {
        let library = makeLibrary()
        let store = makeStore(library)
        let click = Block(.click(.toLearn, button: .left))
        let doc = library.add(MacroDoc(name: "Clic", blocks: [click]))
        let model = MacroEditorModel(store: store)
        model.load(doc.id)
        model.rename("Clic à montrer")
        let teacher = ClickTeacher.shared
        let pid = try standInFL()
        var learned: ClickTarget?
        teacher.start(block: click.id, pid: pid, returnTo: nil) { [weak model] target in
            learned = target
            model?.updateBlock(click.id, key: "target") { $0.body = .click(target, button: .left) }
        }
        XCTAssertEqual(teacher.activeBlock, click.id)

        model.close()
        XCTAssertNil(teacher.activeBlock)
        let saved = try XCTUnwrap(library.doc(doc.id))
        XCTAssertEqual(saved.name, "Clic à montrer")
        XCTAssertEqual(saved.blocks, [click])            // endroit toujours « à montrer »
        XCTAssertEqual(saved.revision, doc.revision + 1)

        // Endroit arrivé trop tard (bloc modifié après la fermeture) : rien n'est écrit.
        model.updateBlock(click.id, key: "target") { $0.body = .click(.track(dx: 5, dy: 5), button: .left) }
        spin(timeout: 0.8)
        XCTAssertNil(learned)
        XCTAssertNil(teacher.activeBlock)
        XCTAssertEqual(library.doc(doc.id), saved)
    }

    /// Ouvert et modifié : aucun besoin annoncé (ni ports MIDI ni suivi des clics). « Tester » les annonce ; la fin
    /// de l'essai (ici FL qui ne passe pas devant) les rend.
    func testEditorNeedsEmptyUntilTest() throws {
        let library = makeLibrary()
        let store = makeStore(library)
        let doc = library.add(MacroDoc(name: "Piste et lien", blocks: [
            Block(.click(.track(dx: 0, dy: 0), button: .left)),
            Block(.flAction(key: "solo", fallback: .none)),
        ]))
        let model = MacroEditorModel(store: store)
        model.load(doc.id)
        XCTAssertNil(model.problem)
        XCTAssertTrue(model.needs.isSuperset(of: [.lienMIDI, .pisteVisee]))
        XCTAssertTrue(store.activeNeeds.isEmpty)
        model.rename("Piste et lien modifiée")
        XCTAssertTrue(store.activeNeeds.isEmpty)

        try startTest(model)
        XCTAssertTrue(store.activeNeeds.isSuperset(of: [.lienMIDI, .pisteVisee]))
        spin(until: { !model.preparingTest }, timeout: 5)
        XCTAssertFalse(model.preparingTest)
        XCTAssertNotNil(model.monitor.refusal)           // « FL Studio n'est pas passé au premier plan »
        XCTAssertNil(model.monitor.outcome)              // essai non lancé : ni arrêté ni échoué
        XCTAssertTrue(store.activeNeeds.isEmpty)

        model.close()
        XCTAssertTrue(store.activeNeeds.isEmpty)
    }
}
