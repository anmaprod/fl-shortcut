import XCTest
@testable import FLShortcut

/// « Enregistrement rapide » développé en blocs : test « golden » des 8 combinaisons d'options (preset fixe ou non ×
/// armer + entrée × REC), contre les valeurs écrites en clair de l'ancien `autoRecordSteps` ; anciennes macros reprises.
final class MacroTemplateTests: XCTestCase {
    private typealias Role = MacroTemplates.Role
    private let preset = "/Users/test/Presets/Voix lead (micro 1).fst"

    /// Bloc attendu pour chaque rôle : paramètres d'aujourd'hui, id déterministe propre au rôle.
    private func expected(_ role: Role, fixedPreset: Bool) -> Block {
        let body: BlockBody
        switch role {
        case .trackMenu:
            body = .trackMenu(letters: ["f", "o"], labels: ["File", "Open mixer track state"], target: .lastClicked,
                              finalEnter: .learned(legacyKey: "macroMenuEnterAfterLetter"))
        case .waitOpen: body = .waitWindow(.dialog, timeoutMs: 4_000)
        case .chooseFile: body = .chooseFile(path: preset)
        case .waitClose: body = .waitWindowClose(.dialog, timeoutMs: fixedPreset ? 8_000 : 120_000)
        case .delay: body = .delay(ms: 100)
        case .arm: body = .flAction(key: "armon", fallback: .trackMenuArm)
        case .rec: body = .flAction(key: "recon", fallback: .key(KeyRef(KeyCombo(keyCode: 15))))
        case .input: body = .selectInput(.legacy(key: "macroSpots.v2.input"))
        case .feedback: body = .feedbackCheck
        }
        let id = UUID(uuidString: String(format: "F15C0000-0000-4000-8000-%012d", role.rawValue))!
        return Block(id: id, body)
    }

    func testGoldenExpansionOfTheEightOptionCombinations() {
        // (preset fixe, armer + entrée, REC) → rôles dans l'ordre, et noms des anciennes étapes (MacroTests d'avant).
        let all: [(Bool, Bool, Bool, [Role], [String])] = [
            (false, true, true, [.trackMenu, .waitOpen, .waitClose, .delay, .arm, .rec, .input, .feedback],
             ["trackMenu", "waitDialog", "waitDialogClose", "delay", "armTrack", "recordOn", "selectInput", "feedbackCheck"]),
            (false, true, false, [.trackMenu, .waitOpen, .waitClose, .delay, .arm, .input, .feedback],
             ["trackMenu", "waitDialog", "waitDialogClose", "delay", "armTrack", "selectInput", "feedbackCheck"]),
            (false, false, true, [.trackMenu, .waitOpen, .waitClose, .delay, .rec, .feedback],
             ["trackMenu", "waitDialog", "waitDialogClose", "delay", "recordOn", "feedbackCheck"]),
            (false, false, false, [.trackMenu, .waitOpen, .waitClose],
             ["trackMenu", "waitDialog", "waitDialogClose"]),
            (true, true, true, [.trackMenu, .waitOpen, .chooseFile, .waitClose, .delay, .arm, .rec, .input, .feedback],
             ["trackMenu", "waitDialog", "chooseFile", "waitDialogClose", "delay", "armTrack", "recordOn", "selectInput", "feedbackCheck"]),
            (true, true, false, [.trackMenu, .waitOpen, .chooseFile, .waitClose, .delay, .arm, .input, .feedback],
             ["trackMenu", "waitDialog", "chooseFile", "waitDialogClose", "delay", "armTrack", "selectInput", "feedbackCheck"]),
            (true, false, true, [.trackMenu, .waitOpen, .chooseFile, .waitClose, .delay, .rec, .feedback],
             ["trackMenu", "waitDialog", "chooseFile", "waitDialogClose", "delay", "recordOn", "feedbackCheck"]),
            (true, false, false, [.trackMenu, .waitOpen, .chooseFile, .waitClose],
             ["trackMenu", "waitDialog", "chooseFile", "waitDialogClose"]),
        ]
        for (fixed, arm, rec, roles, names) in all {
            var m = Macro()
            m.presetPath = fixed ? preset : nil
            m.armAndInput = arm
            m.startRecording = rec
            m.recKey = KeyCombo(keyCode: 15)
            let label = "preset fixe \(fixed), armer \(arm), REC \(rec)"
            let blocks = MacroTemplates.enregistrementRapide(m)
            XCTAssertEqual(blocks, roles.map { expected($0, fixedPreset: fixed) }, label)
            XCTAssertEqual(blocks.map { BlockRegistry.journal(of: $0.body) }, names, label)
            let program = MacroProgram.compile(m, forbidden: .physical)
            XCTAssertNil(program.problem, label)
            XCTAssertEqual(program.blocks, blocks, label)
            XCTAssertEqual(program.title, names.joined(separator: " > "), label)
        }
    }

    func testEmptyPresetPathAsksTheUserAndMissingRecKeyFallsBackToR() {
        var m = Macro()
        m.presetPath = ""
        m.recKey = nil
        let blocks = MacroTemplates.enregistrementRapide(m)
        XCTAssertFalse(blocks.contains { $0.body.type == .chooseFile })
        XCTAssertTrue(blocks.contains { $0.body == .waitWindowClose(.dialog, timeoutMs: 120_000) })
        XCTAssertTrue(blocks.contains { $0.body == .flAction(key: "recon", fallback: .key(KeyRef(KeyCombo(keyCode: 15)))) })
    }

    func testIdsAreStableAndDistinct() {
        var m = Macro()
        m.presetPath = preset
        let a = MacroTemplates.enregistrementRapide(m).map(\.id)
        let b = MacroTemplates.enregistrementRapide(m).map(\.id)
        XCTAssertEqual(a, b)
        XCTAssertEqual(Set(a).count, a.count)
        XCTAssertEqual(MacroTemplates.id(.trackMenu).uuidString, "F15C0000-0000-4000-8000-000000000001")
        XCTAssertEqual(MacroTemplates.legacyID(0).uuidString, "F15C0001-0000-4000-8000-000000000001")
        XCTAssertEqual(Set(Role.allCases.map { MacroTemplates.id($0) }).count, Role.allCases.count)
    }

    func testExpansionSurvivesJSON() throws {
        var m = Macro()
        m.presetPath = preset
        let blocks = MacroTemplates.enregistrementRapide(m)
        XCTAssertEqual(try JSONDecoder().decode([Block].self, from: JSONEncoder().encode(blocks)), blocks)
    }

    // MARK: Anciennes macros

    func testLegacyStepsBecomeTheBlocksThatRunThemTheSameWay() {
        var rec = MacroStep(kind: .recordOn)
        rec.combo = KeyCombo(keyCode: 17)
        let steps: [MacroStep] = [
            .click(ClickSpot(anchor: .cursor, dx: 0, dy: 0), button: .right),
            .delay(200),
            .menu(["File", "Open mixer track state"], fallback: [ClickSpot(anchor: .cursor, dx: 10, dy: 20),
                                                                  ClickSpot(anchor: .lastClick, dx: 5, dy: 30)]),
            .waitDialog(3_000),
            .chooseFile("/Users/test/Voix.fst"),
            .waitDialogClose(8_000),
            .click(ClickSpot(anchor: .cursorXWindowY, dx: 12, dy: 640)),
            .click(ClickSpot(anchor: .window, dx: 800, dy: 90)),
            .key(KeyCombo(keyCode: 15)),
            .trackMenu(["File|Fichier", "Open mixer track state|Ouvrir"]),
            MacroStep(kind: .armTrack), rec, MacroStep(kind: .selectInput), MacroStep(kind: .feedbackCheck),
        ]
        let expected: [BlockBody] = [
            .click(.startCursor(dx: 0, dy: 0), button: .right),
            .delay(ms: 200),
            .menuAX(titles: ["File", "Open mixer track state"], fallback: [.startCursor(dx: 10, dy: 20), .lastClick(dx: 5, dy: 30)]),
            .waitWindow(.dialog, timeoutMs: 3_000),
            .chooseFile(path: "/Users/test/Voix.fst"),
            .waitWindowClose(.dialog, timeoutMs: 8_000),
            .click(.cursorXWindowY(dx: 12, dy: 640), button: .left),
            .click(.flWindow(corner: .topLeft, dx: 800, dy: 90, size: nil), button: .left),
            .key(KeyRef(KeyCombo(keyCode: 15)), times: 1),
            .trackMenu(letters: ["f", "o"], labels: ["File", "Open mixer track state"], target: .lastClicked,
                       finalEnter: .learned(legacyKey: "macroMenuEnterAfterLetter")),
            .flAction(key: "armon", fallback: .trackMenuArm),
            .flAction(key: "recon", fallback: .key(KeyRef(KeyCombo(keyCode: 17)))),
            .selectInput(.legacy(key: "macroSpots.v2.input")),
            .feedbackCheck,
        ]
        let blocks = MacroTemplates.blocks(fromLegacy: steps)
        XCTAssertEqual(blocks.map(\.body), expected)
        XCTAssertEqual(blocks.map(\.id), steps.indices.map { MacroTemplates.legacyID($0) })
        XCTAssertEqual(blocks.map { BlockRegistry.journal(of: $0.body) },
                       steps.map { $0.kind == .menu ? "menu" : $0.kind.rawValue })
    }

    func testQuickRecordAndCustomMacrosStillRun() {
        var quick = Macro()
        quick.template = .quickRecord
        for name in MacroLibrary.requiredSpots { quick.spots[name] = ClickSpot(anchor: .cursor, dx: 10, dy: 2) }
        let p = MacroProgram.compile(quick, forbidden: .physical)
        XCTAssertNil(p.problem)
        XCTAssertEqual(p.blocks.first?.body, .click(.startCursor(dx: 0, dy: 0), button: .right))
        // Positions manquantes : même message qu'avant.
        quick.spots = [:]
        XCTAssertEqual(MacroProgram.compile(quick, forbidden: .physical).problem,
                       "Position(s) à apprendre : bouton d'armement, sélecteur d'entrée, première entrée.")
        var custom = Macro()
        custom.template = .custom
        custom.steps = [.delay(100), .key(KeyCombo(keyCode: 49))]
        XCTAssertNil(MacroProgram.compile(custom, forbidden: .physical).problem)
        // Les anciennes bornes s'appliquent toujours aux anciennes macros.
        custom.steps = Array(repeating: .delay(10), count: MacroLibrary.maxSteps + 1)
        XCTAssertEqual(MacroLibrary.problem(in: custom, forbidden: .physical), "Macro trop longue (40 étapes au plus).")
    }

    func testProgramCacheReturnsTheSameProgram() {
        var m = Macro()
        m.presetPath = preset
        let a = MacroProgram.compile(m, forbidden: .physical)
        XCTAssertTrue(a === MacroProgram.compile(m, forbidden: .physical))
        m.startRecording = false
        XCTAssertNotEqual(a, MacroProgram.compile(m, forbidden: .physical))
    }
}
