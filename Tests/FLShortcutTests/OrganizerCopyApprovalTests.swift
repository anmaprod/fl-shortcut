// Validation de la copie rangée (demande du propriétaire, 24/10) : la copie retenue avec son original, la réponse
// sur de vrais fichiers (dossier temporaire, Corbeille imitée par un dossier), rien de perdu si quelque chose rate.
import XCTest
@testable import FLShortcut

final class OrganizerCopyApprovalTests: XCTestCase {
    private var folder: URL!
    private var trashFolder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("approbation-\(UUID().uuidString)")
        trashFolder = folder.appendingPathComponent("Corbeille")
        try FileManager.default.createDirectory(at: trashFolder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    /// Les vrais fichiers ; la Corbeille est un dossier du test (rien ne part dans la vraie Corbeille).
    private func files(renameFails: Bool = false) -> CopyFiles {
        let trash = trashFolder!
        var f = CopyFiles()
        f.trash = { url in
            let place = trash.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: place)
            return place
        }
        if renameFails {
            f.move = { from, to in
                if from.deletingLastPathComponent().standardizedFileURL.path == trash.standardizedFileURL.path {
                    try FileManager.default.moveItem(at: from, to: to)       // l'original qui revient de la Corbeille
                    return
                }
                throw CocoaError(.fileWriteNoPermission)
            }
        }
        return f
    }

    private func file(_ name: String, _ text: String) throws -> URL {
        let url = folder.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    private func text(_ url: URL) -> String? { (try? Data(contentsOf: url)).map { String(decoding: $0, as: UTF8.self) } }

    func testCopiesAreRememberedWithTheirOriginal() {
        let x = URL(fileURLWithPath: "/p/Nuit.flp"), x2 = URL(fileURLWithPath: "/p/Nuit_2.flp")
        let x3 = URL(fileURLWithPath: "/p/Nuit_3.flp"), y = URL(fileURLWithPath: "/p/Jour.flp")
        let y2 = URL(fileURLWithPath: "/p/Jour_2.flp")
        var list = CopyApprovalRules.recording([], original: x, copy: x2, date: Date())
        XCTAssertEqual(list.map(\.copy), [x2])
        list = CopyApprovalRules.recording(list, original: y, copy: y2, date: Date())
        XCTAssertEqual(list.count, 2, "un autre projet : une autre question")
        // Organiser relancé sur la version organisée, sans avoir répondu : la nouvelle la remplace, même original.
        list = CopyApprovalRules.recording(list, original: x2, copy: x3, date: Date())
        let nuit = list.first { $0.copy == x3 }
        XCTAssertEqual(nuit?.original, x)
        XCTAssertEqual(nuit?.older, [x2], "l'ancienne version organisée partira à la Corbeille")
        XCTAssertEqual(list.count, 2)
        // Relancé depuis l'original : pareil.
        let x4 = URL(fileURLWithPath: "/p/Nuit_4.flp")
        list = CopyApprovalRules.recording(list, original: x, copy: x4, date: Date())
        XCTAssertEqual(list.first { $0.copy == x4 }?.older, [x2, x3])
        XCTAssertEqual(list.filter { $0.original == x }.count, 1)
    }

    /// « Valider » : l'original à la Corbeille, la version organisée prend son nom, les versions d'avant à la Corbeille.
    func testValidateReplacesTheOriginal() throws {
        let original = try file("Nuit.flp", "avant")
        let older = try file("Nuit_2.flp", "rangé 1")
        let copy = try file("Nuit_3.flp", "rangé 2")
        let pending = PendingCopy(original: original, copy: copy, older: [older], date: Date())
        let final = try CopyApprovalRules.validate(pending, files: files())
        XCTAssertEqual(final, original)
        XCTAssertEqual(text(original), "rangé 2", "la version organisée a pris le nom du projet")
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: older.path))
        let trashed = try FileManager.default.contentsOfDirectory(atPath: trashFolder.path)
        XCTAssertEqual(trashed.count, 2, "l'original et l'ancienne version : à la Corbeille, pas supprimés")
        XCTAssertTrue(trashed.contains { $0.hasSuffix("Nuit.flp") })
    }

    /// La version organisée a disparu : rien n'est touché. Le renommage rate : l'original revient à sa place.
    func testNothingIsLostWhenSomethingFails() throws {
        let original = try file("Nuit.flp", "avant")
        let gone = folder.appendingPathComponent("Nuit_2.flp")
        XCTAssertThrowsError(try CopyApprovalRules.validate(PendingCopy(original: original, copy: gone, date: Date()),
                                                            files: files())) {
            XCTAssertEqual($0 as? CopyApprovalError, .copyMissing)
        }
        XCTAssertEqual(text(original), "avant")

        let copy = try file("Nuit_2.flp", "rangé")
        XCTAssertThrowsError(try CopyApprovalRules.validate(PendingCopy(original: original, copy: copy, date: Date()),
                                                            files: files(renameFails: true))) {
            XCTAssertEqual($0 as? CopyApprovalError, .cannotRename)
        }
        XCTAssertEqual(text(original), "avant", "l'original revenu de la Corbeille")
        XCTAssertEqual(text(copy), "rangé")

        var stuck = files()
        stuck.trash = { _ in throw CocoaError(.fileWriteNoPermission) }
        XCTAssertThrowsError(try CopyApprovalRules.validate(PendingCopy(original: original, copy: copy, date: Date()),
                                                            files: stuck)) {
            XCTAssertEqual($0 as? CopyApprovalError, .cannotTrash)
        }
        XCTAssertEqual(text(original), "avant")
        XCTAssertEqual(text(copy), "rangé", "rien n'a bougé")
    }

    /// L'original supprimé à la main entre-temps : la version organisée prend quand même son nom.
    func testValidateWithoutTheOriginal() throws {
        let original = folder.appendingPathComponent("Nuit.flp")
        let copy = try file("Nuit_2.flp", "rangé")
        try CopyApprovalRules.validate(PendingCopy(original: original, copy: copy, date: Date()), files: files())
        XCTAssertEqual(text(original), "rangé")
    }

    /// « Retourner en arrière » : la version organisée (et celles d'avant) à la Corbeille, l'original ne bouge pas.
    func testGoBackTrashesTheCopies() throws {
        let original = try file("Nuit.flp", "avant")
        let older = try file("Nuit_2.flp", "rangé 1")
        let copy = try file("Nuit_3.flp", "rangé 2")
        CopyApprovalRules.goBack(PendingCopy(original: original, copy: copy, older: [older], date: Date()),
                                 files: files())
        XCTAssertEqual(text(original), "avant")
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: older.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: trashFolder.path).count, 2)
    }

    /// Retenu d'un lancement à l'autre ; « Revenir comme avant » l'oublie ; une version organisée disparue aussi.
    func testPendingCopiesSurviveARelaunch() throws {
        let suite = "approbation-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let original = try file("Nuit.flp", "avant")
        let copy = try file("Nuit_2.flp", "rangé")
        let approval = CopyApproval(defaults: defaults)
        approval.record(original: original, copy: copy)
        let relaunched = CopyApproval(defaults: defaults)
        XCTAssertEqual(relaunched.pending.map(\.copy), [copy])
        XCTAssertEqual(relaunched.pending.first?.original, original)
        relaunched.forget(copy: copy)
        XCTAssertTrue(CopyApproval(defaults: defaults).pending.isEmpty, "« Revenir comme avant » : plus de question")

        approval.record(original: original, copy: copy)
        try FileManager.default.removeItem(at: copy)
        approval.prune()
        XCTAssertTrue(approval.pending.isEmpty, "version organisée supprimée à la main : plus de question")
        XCTAssertNil(defaults.data(forKey: CopyApproval.key))
    }

    /// Audit du 25/10 : la liste est dans les réglages de l'app, qu'un autre programme peut écrire. Seuls des projets
    /// .flp et leurs versions « _N » du même dossier sont acceptés : jamais n'importe quel fichier mis à la Corbeille,
    /// renommé ou ouvert.
    func testOnlyProjectVersionsAreAccepted() throws {
        let p = URL(fileURLWithPath: "/Users/moi/Projets")
        func pending(_ original: String, _ copy: String, older: [String] = []) -> PendingCopy {
            PendingCopy(original: p.appendingPathComponent(original), copy: p.appendingPathComponent(copy),
                        older: older.map { p.appendingPathComponent($0) }, date: Date())
        }
        XCTAssertTrue(CopyApprovalRules.isSafe(pending("Nuit.flp", "Nuit_2.flp")))
        XCTAssertTrue(CopyApprovalRules.isSafe(pending("Beat_7.flp", "Beat_8.flp")), "projet déjà numéroté")
        XCTAssertTrue(CopyApprovalRules.isSafe(pending("Nuit.flp", "Nuit_3.flp", older: ["Nuit_2.flp"])))
        XCTAssertFalse(CopyApprovalRules.isSafe(pending("Rapport.docx", "Rapport_2.docx")), "pas un projet")
        XCTAssertFalse(CopyApprovalRules.isSafe(pending("Nuit.flp", "Autre_2.flp")), "pas une version du même projet")
        XCTAssertFalse(CopyApprovalRules.isSafe(pending("Nuit.flp", "Nuit.flp")), "le même fichier")
        XCTAssertFalse(CopyApprovalRules.isSafe(pending("Nuit.flp", "Nuit_2.flp", older: ["Nuit.flp"])))
        XCTAssertFalse(CopyApprovalRules.isSafe(PendingCopy(original: p.appendingPathComponent("Nuit.flp"),
                                                            copy: URL(fileURLWithPath: "/tmp/Nuit_2.flp"), date: Date())),
                       "pas dans le dossier du projet")
        XCTAssertFalse(CopyApprovalRules.isSafe(pending("Script.command", "Script_2.command")), "jamais un programme")

        let suite = "approbation-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let written = [pending("Nuit.flp", "Nuit_2.flp"), pending("Rapport.docx", "Rapport_2.docx")]
        defaults.set(try JSONEncoder().encode(written), forKey: CopyApproval.key)
        XCTAssertEqual(CopyApproval(defaults: defaults).pending.map(\.copy.lastPathComponent), ["Nuit_2.flp"],
                       "une entrée écrite par un autre programme est ignorée")
        XCTAssertThrowsError(try CopyApprovalRules.validate(pending("Rapport.docx", "Rapport_2.docx"), files: files()))
    }

    /// La copie faite et ouverte dans FL est retenue, même si la suite s'est arrêtée en route.
    func testOrganizerReportsTheCopyItMade() {
        let original = URL(fileURLWithPath: "/p/Nuit.flp"), copy = URL(fileURLWithPath: "/p/Nuit_2.flp")
        var outcome = ApplyOutcome(snapshot: OrganizerSnapshot())
        XCTAssertNil(OrganizerController.madeCopy(outcome), "pas de copie : rien à demander")
        outcome.copy = copy
        outcome.snapshot.original = original
        outcome.error = .interrupted
        XCTAssertEqual(OrganizerController.madeCopy(outcome)?.copy, copy)
        XCTAssertEqual(OrganizerController.madeCopy(outcome)?.original, original)
    }
}
