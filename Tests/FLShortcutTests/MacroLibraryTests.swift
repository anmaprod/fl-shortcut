import Foundation
import XCTest
@testable import FLShortcut

/// Bibliothèque des macros (macros.json) et format d'échange .flsmacro.
final class MacroLibraryTests: XCTestCase {
    private func sample(_ name: String = "Ma macro") -> MacroDoc {
        MacroDoc(name: name, blocks: [
            Block(.key(KeyRef(KeyCombo(keyCode: 1, command: true), char: "s"), times: 1), note: "Enregistrer"),
            Block(.repeatCount(2, [Block(.menuKey(.down, times: 1)), Block(.delay(ms: 100), enabled: false)])),
            Block(.click(.flWindow(corner: .topRight, dx: -40, dy: 12, size: CGSize(width: 900, height: 600)), button: .left)),
            Block(.chooseFile(path: "/Users/moi/Documents/Voix.fst")),
            Block(.unknown(type: "teleport", raw: .object(["where": .string("Mars")]))),
        ])
    }

    // MARK: Fichier

    func testRoundTripKeepsEveryMacroAndUnknownBlocks() throws {
        let docs = [sample(), sample("Deuxième")]
        let decoded = try MacroLibraryCodec.decode(MacroLibraryCodec.encode(docs))
        XCTAssertEqual(decoded.macros, docs)
        XCTAssertEqual(decoded.dropped, 0)
        XCTAssertEqual(decoded.version, MacroLibraryCodec.currentVersion)
        // Le bloc inconnu est gardé tel quel, et bloque sa macro.
        XCTAssertNotNil(MacroProgram.compile(decoded.macros[0], forbidden: .physical).problem)
    }

    func testUnreadableEntryIsDroppedAndDuplicateIDsRegenerated() throws {
        let id = UUID().uuidString
        let json = """
        {"version": 1, "macros": [
          {"id": "\(id)", "name": "A", "blocks": [{"type": "delay", "ms": 100}]},
          42,
          {"id": "\(id)", "name": "B", "blocks": []}
        ]}
        """
        let decoded = try MacroLibraryCodec.decode(Data(json.utf8))
        XCTAssertEqual(decoded.macros.map(\.name), ["A", "B"])
        XCTAssertEqual(decoded.dropped, 1)
        XCTAssertNotEqual(decoded.macros[0].id, decoded.macros[1].id)
    }

    func testStoreSavesAfterAChangeAndKeepsThePreviousFileOnce() throws {
        let storage = MemoryMacroLibraryStorage(data: try MacroLibraryCodec.encode([sample()]))
        let original = storage.data
        let store = MacroLibraryStore(storage: storage, saveDelay: 0)
        XCTAssertEqual(store.macros.count, 1)
        XCTAssertNil(store.loadWarning)
        store.add(sample("Nouvelle"))
        store.saveNow()
        XCTAssertEqual(storage.writes, 1)
        XCTAssertEqual(storage.backups["macros.precedente.json"], original)
        store.add(sample("Encore"))
        store.saveNow()
        XCTAssertEqual(storage.writes, 2)
        XCTAssertEqual(storage.backups.count, 1)                 // une seule copie par lancement
        let reread = MacroLibraryStore(storage: storage, saveDelay: 0)
        XCTAssertEqual(reread.macros.map(\.name), ["Ma macro", "Nouvelle", "Encore"])
    }

    func testCorruptFileIsBackedUpAndLibraryStartsEmpty() {
        let storage = MemoryMacroLibraryStorage(data: Data("{ cassé".utf8))
        let store = MacroLibraryStore(storage: storage, saveDelay: 0)
        XCTAssertTrue(store.macros.isEmpty)
        XCTAssertEqual(storage.backups["macros.illisible.json"], Data("{ cassé".utf8))
        XCTAssertNotNil(store.loadWarning)
        XCTAssertEqual(storage.writes, 0)                        // rien d'écrit tant que rien ne change
    }

    func testNewerOrPartialFileIsBackedUp() throws {
        let newer = Data(#"{"version": 9, "macros": [{"name": "Future", "blocks": [], "format": 3}]}"#.utf8)
        let storage = MemoryMacroLibraryStorage(data: newer)
        let store = MacroLibraryStore(storage: storage, saveDelay: 0)
        XCTAssertEqual(store.macros.count, 1)
        XCTAssertEqual(storage.backups["macros.plus-recente.json"], newer)
        XCTAssertNotNil(MacroProgram.compile(store.macros[0], forbidden: .physical).problem)   // format 3 : bloquée
    }

    func testInaccessibleFileIsNeverOverwritten() {
        let storage = MemoryMacroLibraryStorage()
        storage.readError = SecureFile.Failure.symlink("/x")
        let store = MacroLibraryStore(storage: storage, saveDelay: 0)
        XCTAssertTrue(store.writesDisabled)
        store.add(sample())
        store.saveNow()
        XCTAssertEqual(storage.writes, 0)
    }

    func testBackupFailureDisablesWrites() throws {
        let storage = MemoryMacroLibraryStorage(data: try MacroLibraryCodec.encode([sample()]))
        let original = storage.data
        storage.backupError = CocoaError(.fileWriteOutOfSpace)
        let store = MacroLibraryStore(storage: storage, saveDelay: 0)
        store.add(sample("Nouvelle"))
        store.saveNow()
        XCTAssertEqual(storage.writes, 0)                        // jamais remplacé sans copie
        XCTAssertEqual(storage.data, original)
        XCTAssertTrue(store.writesDisabled)
        store.add(sample("Encore"))
        store.saveNow()
        XCTAssertEqual(storage.writes, 0)
    }

    func testProblemMessageWhenWritesDisabled() throws {
        let storage = MemoryMacroLibraryStorage(data: try MacroLibraryCodec.encode([sample()]))
        storage.backupError = CocoaError(.fileWriteOutOfSpace)
        let store = MacroLibraryStore(storage: storage, saveDelay: 0)
        XCTAssertNil(store.problem)
        store.add(sample("Nouvelle"))
        store.saveNow()
        let problem = try XCTUnwrap(store.problem)
        XCTAssertTrue(problem.hasPrefix("Tes macros ne peuvent pas être enregistrées"), problem)
    }

    func testProblemVisibleWhenLibraryEmpty() {
        let storage = MemoryMacroLibraryStorage(data: Data("{ cassé".utf8))
        storage.backupError = CocoaError(.fileWriteNoPermission)
        let store = MacroLibraryStore(storage: storage, saveDelay: 0)
        XCTAssertTrue(store.macros.isEmpty)
        XCTAssertTrue(store.writesDisabled)                      // illisible et pas copié : jamais écrasé
        let problem = store.problem ?? ""
        XCTAssertTrue(problem.hasPrefix("Le fichier des macros est illisible"), problem)
        store.add(sample())
        store.saveNow()
        XCTAssertEqual(storage.writes, 0)
        XCTAssertEqual(storage.data, Data("{ cassé".utf8))
    }

    func testUpdateBumpsTheRevisionOnlyWhenContentChanges() {
        let store = MacroLibraryStore(storage: MemoryMacroLibraryStorage(), saveDelay: 0)
        let doc = store.add(sample())
        XCTAssertEqual(store.update(doc)?.revision, 0)
        var changed = doc
        changed.name = "Renommée"
        XCTAssertEqual(store.update(changed)?.revision, 1)
        XCTAssertNil(store.update(MacroDoc(name: "Absente", blocks: [])))
    }

    func testProgramsAreCachedByRevision() {
        let store = MacroLibraryStore(storage: MemoryMacroLibraryStorage(), saveDelay: 0)
        let doc = store.add(MacroDoc(name: "A", blocks: [Block(.delay(ms: 100))]))
        let first = store.programs(forbidden: .physical)[doc.id]
        XCTAssertTrue(first === store.programs(forbidden: .physical)[doc.id])
        var changed = doc
        changed.blocks.append(Block(.delay(ms: 200)))
        store.update(changed)
        let second = store.programs(forbidden: .physical)[doc.id]
        XCTAssertFalse(first === second)
        XCTAssertEqual(second?.blocks.count, 2)
        XCTAssertNil(second?.problem)
    }

    func testUniqueNames() {
        let store = MacroLibraryStore(storage: MemoryMacroLibraryStorage(), saveDelay: 0)
        XCTAssertEqual(store.uniqueName("Nouvelle macro"), "Nouvelle macro")
        store.add(MacroDoc(name: "Nouvelle macro", blocks: []))
        store.add(MacroDoc(name: "Nouvelle macro 2", blocks: []))
        XCTAssertEqual(store.uniqueName("Nouvelle macro"), "Nouvelle macro 3")
    }

    func testAtomicPrivateFileWrite() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("fls-lib-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("macros.json")
        let storage = FileMacroLibraryStorage(url: url)
        XCTAssertNil(try storage.read())
        let store = MacroLibraryStore(storage: storage, saveDelay: 0)
        store.add(sample())
        store.saveNow()
        XCTAssertEqual(SecureFile.permissions(at: url.path)?.mode, 0o600)
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        XCTAssertEqual(names, ["macros.json"])                   // aucun fichier temporaire laissé
        XCTAssertEqual(MacroLibraryStore(storage: FileMacroLibraryStorage(url: url), saveDelay: 0).macros, store.macros)
        // Lien symbolique à la place du fichier : refusé, jamais suivi.
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createSymbolicLink(atPath: url.path, withDestinationPath: "/tmp/ailleurs.json")
        XCTAssertThrowsError(try storage.write(Data("{}".utf8)))
    }

    // MARK: .flsmacro

    func testExportFormatRemovesLearnedPositionsAndHomeFolder() throws {
        let data = try MacroExchange.export(sample(), appVersion: "1.2", home: "/Users/moi")
        let json = try JSONDecoder().decode(JSONValue.self, from: data)
        XCTAssertEqual(json["format"]?.string, "flsmacro")
        XCTAssertEqual(json["version"]?.int, 1)
        XCTAssertEqual(json["exportedBy"]?.string, "FL Shortcut 1.2 (macOS)")
        XCTAssertEqual(json["macro"]?["name"]?.string, "Ma macro")
        let blocks = try XCTUnwrap(json["macro"]?["blocks"]?.array)
        XCTAssertEqual(blocks.count, 5)
        XCTAssertEqual(blocks[2]["target"]?["anchor"]?.string, "toLearn")      // position apprise retirée
        XCTAssertEqual(blocks[3]["path"]?.string, "~/Documents/Voix.fst")       // jamais le nom du compte
        XCTAssertEqual(blocks[4]["type"]?.string, "teleport")                   // bloc inconnu gardé tel quel
        XCTAssertNil(blocks[2]["target"]?["size"])                               // taille de la fenêtre retirée
        XCTAssertFalse(String(decoding: data, as: UTF8.self).contains("/Users/moi"))
    }

    func testImportRegeneratesIDsAndNeedsNoShortcut() throws {
        let original = sample()
        let data = try MacroExchange.export(original, appVersion: "1.2", home: "/Users/moi")
        let preview = try MacroExchange.prepareImport(data, home: "/Users/autre", layout: FakeLayout.qwerty)
        XCTAssertEqual(preview.doc.name, "Ma macro")
        XCTAssertEqual(preview.doc.origin, .imported)
        XCTAssertNotEqual(preview.doc.id, original.id)
        XCTAssertTrue(Set(allIDs(preview.doc.blocks)).isDisjoint(with: allIDs(original.blocks)))
        XCTAssertEqual(MacroValidation.count(preview.doc.blocks), MacroValidation.count(original.blocks))
        if case .chooseFile(let path) = preview.doc.blocks[3].body {
            XCTAssertEqual(path, "/Users/autre/Documents/Voix.fst")
        } else {
            XCTFail("preset attendu")
        }
        XCTAssertEqual(preview.lines.count, 7)                                  // 5 blocs + 2 dans la boucle
        XCTAssertTrue(preview.lines[0].contains("touche avec ⌘"))
        XCTAssertTrue(preview.lines.contains { $0.contains("position à montrer") })
        XCTAssertFalse(preview.warnings.isEmpty)
        // Positions à montrer : la macro importée ne peut pas tourner telle quelle.
        XCTAssertNotNil(MacroProgram.compile(preview.doc, forbidden: .physical).problem)
    }

    /// Fichier .flsmacro écrit à la main (sans passer par l'export, qui retire déjà les positions).
    private func handMade(_ blocks: [Block]) throws -> Data {
        let file: JSONValue = .object([
            "format": .string(MacroExchange.format),
            "version": .num(MacroExchange.version),
            "macro": .object(["name": .string("Faite main"), "blocks": .array(blocks.map(\.json))]),
        ])
        return try JSONEncoder().encode(file)
    }

    func testImportForcesClicksToLearn() throws {
        let aimed = ClickTarget.flWindow(corner: .topRight, dx: -40, dy: 12, size: CGSize(width: 900, height: 600))
        let relative: [ClickTarget] = [.track(dx: 4_000, dy: -4_000), .lastClick(dx: 300, dy: 0), .startCursor(dx: 0, dy: 900)]
        let data = try handMade([Block(.click(aimed, button: .left)),
                                 Block(.repeatCount(2, [Block(.click(aimed, button: .right))]))]
                                + relative.map { Block(.click($0, button: .left)) })
        let preview = try MacroExchange.prepareImport(data, layout: FakeLayout.qwerty)
        guard case .click(.toLearn, _) = preview.doc.blocks[0].body else { return XCTFail("clic à apprendre attendu") }
        guard case .repeatCount(_, let inner) = preview.doc.blocks[1].body,
              case .click(.toLearn, _) = inner[0].body else { return XCTFail("clic imbriqué à apprendre attendu") }
        for block in preview.doc.blocks.dropFirst(2) {                           // piste, dernier clic, curseur
            guard case .click(.toLearn, _) = block.body else { return XCTFail("clic relatif à apprendre attendu") }
        }
        XCTAssertEqual(preview.sensitiveCount, 5)
        XCTAssertNotNil(MacroProgram.compile(preview.doc, forbidden: .physical).problem)
    }

    func testImportFlagsHiddenMenuAX() throws {
        let aimed = ClickTarget.flWindow(corner: .topLeft, dx: 10, dy: 10, size: CGSize(width: 900, height: 600))
        let data = try handMade([Block(.menuAX(titles: ["File", "Open"], fallback: [aimed]))])
        let preview = try MacroExchange.prepareImport(data, layout: FakeLayout.qwerty)
        XCTAssertTrue(preview.lines[0].contains("bloc caché"), preview.lines[0])
        XCTAssertTrue(preview.warnings.contains { $0.contains("bloc caché") })
        XCTAssertEqual(preview.sensitiveCount, 1)
        guard case .menuAX(_, let fallback) = preview.doc.blocks[0].body else { return XCTFail("menuAX attendu") }
        XCTAssertTrue(fallback.isEmpty)                                           // clics de secours retirés
    }

    func testImportCountsSensitiveBlocksInWholeTree() throws {
        var blocks = (0..<35).map { _ in Block(.delay(ms: 100)) }
        blocks.append(Block(.repeatCount(2, [Block(.chooseFile(path: "~/Documents/Voix.fst"))])))
        let preview = try MacroExchange.prepareImport(try handMade(blocks), home: "/Users/autre", layout: FakeLayout.qwerty)
        XCTAssertEqual(preview.lines.count, 37)
        XCTAssertEqual(preview.sensitiveCount, 1)                                 // le fichier, à la 37ᵉ ligne
        XCTAssertTrue(preview.lines[36].contains("fichier"), preview.lines[36])
    }

    func testImportLimits() {
        XCTAssertThrowsError(try MacroExchange.prepareImport(Data(repeating: 32, count: MacroExchange.maxBytes + 1),
                                                             layout: FakeLayout.qwerty)) { error in
            XCTAssertEqual(error as? MacroExchange.Failure, .tooLarge)
        }
        XCTAssertThrowsError(try MacroExchange.prepareImport(Data(#"{"version":2,"remaps":[]}"#.utf8), layout: FakeLayout.qwerty))
        let newer = #"{"format":"flsmacro","version":9,"macro":{"name":"x","blocks":[]}}"#
        XCTAssertThrowsError(try MacroExchange.prepareImport(Data(newer.utf8), layout: FakeLayout.qwerty)) { error in
            XCTAssertEqual(error as? MacroExchange.Failure, .newerVersion)
        }
        // Imbrication au-delà de la limite : refusée.
        var nested = Block(.comment("fond"))
        for _ in 0...MacroValidation.maxDepth { nested = Block(.repeatCount(2, [nested])) }
        let deep = MacroDoc(name: "Profonde", blocks: [nested])
        XCTAssertThrowsError(try MacroExchange.prepareImport(MacroExchange.export(deep, appVersion: "1"), layout: FakeLayout.qwerty))
        // Nom piégé (bidi) nettoyé.
        let tricky = #"{"format":"flsmacro","version":1,"macro":{"name":"Vo‮ix","blocks":[{"type":"delay","ms":100}]}}"#
        XCTAssertEqual(try MacroExchange.prepareImport(Data(tricky.utf8), layout: FakeLayout.qwerty).doc.name, "Voix")
    }

    private func allIDs(_ blocks: [Block]) -> [UUID] {
        blocks.flatMap { [$0.id] + $0.body.children.flatMap(allIDs) }
    }

    // MARK: Modèles

    func testGalleryTemplatesAreValidExceptLearning() {
        let gallery = MacroTemplates.gallery(layout: FakeLayout.qwerty)
        XCTAssertGreaterThanOrEqual(gallery.count, 4)
        for t in gallery {
            let doc = t.make(FakeLayout.qwerty)
            XCTAssertFalse(doc.blocks.isEmpty, t.id)
            XCTAssertNil(MacroProgram.compile(doc, forbidden: .physical).problem, t.id)
            XCTAssertFalse(t.summary.isEmpty)
        }
        // Deux copies d'un modèle ne partagent aucun id.
        let a = gallery[0].make(FakeLayout.qwerty), b = gallery[0].make(FakeLayout.qwerty)
        XCTAssertTrue(Set(allIDs(a.blocks)).isDisjoint(with: allIDs(b.blocks)))
        // « Enregistrement rapide » personnalisé : mêmes blocs que le modèle (ids mis à part).
        var m = Macro()
        m.recKey = AppMode.nativeEquivalent(of: 3, layout: FakeLayout.qwerty)
        XCTAssertEqual(a.blocks.map(\.body), MacroTemplates.enregistrementRapide(m).map(\.body))
    }
}
