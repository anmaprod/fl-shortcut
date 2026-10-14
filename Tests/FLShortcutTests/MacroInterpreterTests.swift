import XCTest
@testable import FLShortcut

/// Faux effets : trace de chaque appel, résultats choisis, horloge contrôlée. Aucun événement envoyé.
final class FakeEffects: MacroEffects {
    var trace: [String] = []
    /// Lignes « STEP » du journal.
    var stepLines: [String] = []
    /// Résultats successifs par nom de bloc (journal) ; .ok ensuite.
    var results: [String: [StepResult]] = [:]
    var flResult: StepResult = .ok
    var beginFailure: String?
    var trackInFL = true
    var keyboardIdle = true
    /// Échap après ce nombre de vérifications.
    var escapeAfter: Int?
    private(set) var stopChecks = 0
    /// Réponses successives de « une fenêtre est ouverte » (faux ensuite).
    var windowAnswers: [Bool] = []
    var now = Date(timeIntervalSince1970: 1_000)
    /// Durée simulée de chaque bloc simple.
    var blockSeconds: TimeInterval = 0
    private(set) var larsenEarly: Bool?

    func log(_ tag: String, _ text: String) { if tag == "STEP" { stepLines.append(text) } }

    func begin(startFeedbackEarly: Bool) -> String? {
        trace.append("begin")
        larsenEarly = startFeedbackEarly
        return beginFailure
    }

    func targetTrackIsInFL() -> Bool {
        trace.append("track?")
        return trackInFL
    }

    func waitForKeyboardIdle(timeout: TimeInterval) -> Bool {
        trace.append("idle")
        return keyboardIdle
    }

    func stopReason() -> String? {
        stopChecks += 1
        if let n = escapeAfter, stopChecks > n { return "Échap" }
        return nil
    }

    func perform(_ body: BlockBody, state: inout RunState) -> StepResult {
        let name = BlockRegistry.journal(of: body)
        trace.append(name)
        now = now.addingTimeInterval(blockSeconds)
        if var list = results[name], !list.isEmpty {
            let r = list.removeFirst()
            results[name] = list
            return r
        }
        return .ok
    }

    func flActions(_ group: [FLActionCall], state: inout RunState) -> StepResult {
        trace.append("fl[" + group.map(\.key).joined(separator: ",") + "]")
        return flResult
    }

    func evaluate(_ c: Condition, state: inout RunState) -> Result<Bool, StepFailure> {
        trace.append("evaluate")
        if case .flState = c { return .failure(.fail("lien absent")) }
        return .success(windowAnswers.isEmpty ? false : windowAnswers.removeFirst())
    }

    func pause(ms: Int) -> StepResult {
        trace.append("pause \(ms)")
        now = now.addingTimeInterval(Double(ms) / 1000)
        return .ok
    }

    func cleanup(state: inout RunState) { trace.append("cleanup") }
}

/// Interpréteur : ordre, regroupement des actions de FL, préconditions du premier bloc, arrêt, Échap, échecs,
/// contrôle (si, répéter, tant que, attendre que, variables), garde-fou d'exécution.
final class MacroInterpreterTests: XCTestCase {
    private func run(_ blocks: [Block], _ fx: FakeEffects, variables: [VariableDecl] = [],
                     limits: RuntimeLimits = .standard) -> MacroOutcome {
        let p = MacroProgram(blocks: blocks, name: "essai", source: .blocks(id: UUID(), revision: 0), variables: variables,
                             context: ValidationContext(forbidden: .physical))
        XCTAssertNil(p.problem)
        return MacroInterpreter(effects: fx, limits: limits, clock: { fx.now }).run(p)
    }

    private func b(_ body: BlockBody, onFailure: FailurePolicy = .stop, enabled: Bool = true) -> Block {
        Block(body, enabled: enabled, onFailure: onFailure)
    }

    private let key = BlockBody.key(KeyRef(KeyCombo(keyCode: 49)), times: 1)

    // MARK: Modèle « Enregistrement rapide »

    /// Même ordre que l'ancien moteur, armement + REC en un seul réveil, journal au même format.
    func testTemplateRunsInTheOldOrder() {
        var m = Macro()
        m.recKey = KeyCombo(keyCode: 15)
        let fx = FakeEffects()
        let outcome = MacroInterpreter(effects: fx, clock: { fx.now }).run(MacroProgram.compile(m, forbidden: .physical))
        XCTAssertEqual(outcome, .done)
        XCTAssertEqual(fx.trace, ["begin", "track?", "trackMenu", "waitDialog", "waitDialogClose", "delay",
                                  "fl[armon,recon]", "selectInput", "feedbackCheck", "cleanup"])
        XCTAssertEqual(fx.larsenEarly, true)
        XCTAssertEqual(fx.stepLines, [
            "1/8 trackMenu …", "1 trackMenu → ok in 0 ms",
            "2/8 waitDialog …", "2 waitDialog → ok in 0 ms",
            "3/8 waitDialogClose …", "3 waitDialogClose → ok in 0 ms",
            "4/8 delay …", "4 delay → ok in 0 ms",
            "5/8 armTrack …", "5 armTrack → ok in 0 ms",
            "7/8 selectInput …", "7 selectInput → ok in 0 ms",
            "8/8 feedbackCheck …", "8 feedbackCheck → ok in 0 ms",
        ])
        // Une vérification « Échap / FL devant » par bloc (le groupe armement + REC compte pour un).
        XCTAssertEqual(fx.stopChecks, 7)
    }

    /// Essai de la CI : sans le larsen, il n'est jamais lancé.
    func testWithoutFeedbackBlockNothingStartsEarly() {
        var m = Macro()
        m.presetPath = "/Users/test/Voix.fst"
        let blocks = MacroProgram.compile(m, forbidden: .physical).blocks.filter { $0.body != .feedbackCheck }
        let fx = FakeEffects()
        XCTAssertEqual(run(blocks, fx), .done)
        XCTAssertEqual(fx.larsenEarly, false)
        // Clavier au repos avant le dépôt (les touches du raccourci relâchées : jamais ⌃ + appui = clic droit).
        XCTAssertEqual(fx.trace, ["begin", "track?", "idle", "dropFile", "delay", "fl[armon,recon]", "selectInput", "cleanup"])
        XCTAssertTrue(fx.stepLines.contains("5/5 selectInput …"))
    }

    func testTrackOutsideFLIsRefusedBeforeAnything() {
        let fx = FakeEffects()
        fx.trackInFL = false
        let outcome = MacroInterpreter(effects: fx, clock: { fx.now }).run(MacroProgram.compile(Macro(), forbidden: .physical))
        XCTAssertEqual(outcome, .failed(step: 1, reason: "clique d'abord sur ta piste dans le Mixer de FL, puis refais le raccourci"))
        XCTAssertEqual(fx.trace, ["begin", "track?", "cleanup"])
    }

    func testBeginFailureStopsAtStep1() {
        let fx = FakeEffects()
        fx.beginFailure = "autorise FL Shortcut"
        XCTAssertEqual(run([b(.delay(ms: 1))], fx), .failed(step: 1, reason: "autorise FL Shortcut"))
        XCTAssertEqual(fx.trace, ["begin", "cleanup"])
    }

    /// Un premier bloc qui ne clique pas sur la piste attend le clavier au repos (touches du raccourci relâchées).
    func testOtherFirstBlocksWaitForTheKeyboard() {
        let fx = FakeEffects()
        XCTAssertEqual(run([b(.comment("note")), b(.delay(ms: 1))], fx), .done)
        XCTAssertEqual(fx.trace, ["begin", "idle", "delay", "cleanup"])
        let held = FakeEffects()
        held.keyboardIdle = false
        XCTAssertEqual(run([b(.delay(ms: 1))], held), .cancelled(reason: "relâche les touches du raccourci"))
        XCTAssertEqual(held.trace, ["begin", "idle", "cleanup"])
    }

    func testUnrunnableProgramNeverStarts() {
        let fx = FakeEffects()
        let p = MacroProgram(blocks: [b(.unknown(type: "futur", raw: .object([:])))], name: "x",
                             source: .blocks(id: UUID(), revision: 0), context: ValidationContext(forbidden: .physical))
        guard case .failed(1, _) = MacroInterpreter(effects: fx).run(p) else { return XCTFail("refus attendu") }
        XCTAssertEqual(fx.trace, ["cleanup"])
    }

    // MARK: Actions de FL

    func testConsecutiveFLActionsShareOneWake() {
        let fx = FakeEffects()
        _ = run([b(.flAction(key: "armon", fallback: .trackMenuArm)),
                 b(.flAction(key: "play", fallback: .none), enabled: false),
                 b(.flAction(key: "recon", fallback: .none)),
                 b(.delay(ms: 1)),
                 b(.flAction(key: "recon", fallback: .none)),
                 b(.flAction(key: "stop", fallback: .none), onFailure: .keepGoing)], fx)
        XCTAssertEqual(fx.trace, ["begin", "idle", "fl[armon,recon]", "delay", "fl[recon]", "fl[stop]", "cleanup"])
    }

    func testFLActionWarningIsKept() {
        let fx = FakeEffects()
        fx.flResult = .warn("armement non fait : le menu de la piste ne s'est pas ouvert")
        XCTAssertEqual(run([b(.flAction(key: "armon", fallback: .trackMenuArm)), b(.delay(ms: 1))], fx),
                       .doneWithWarning("armement non fait : le menu de la piste ne s'est pas ouvert"))
    }

    // MARK: Arrêts et échecs

    func testEscapeCancelsAndCleansUp() {
        let fx = FakeEffects()
        fx.escapeAfter = 2
        XCTAssertEqual(run([b(.delay(ms: 1)), b(.delay(ms: 2)), b(.delay(ms: 3))], fx), .cancelled(reason: "Échap"))
        XCTAssertEqual(fx.trace, ["begin", "idle", "delay", "delay", "cleanup"])
    }

    func testCancelFromABlockStopsEverything() {
        let fx = FakeEffects()
        fx.results["waitDialog"] = [.cancel("FL n'est plus au premier plan")]
        XCTAssertEqual(run([b(.waitWindow(.dialog, timeoutMs: 500), onFailure: .keepGoing), b(.delay(ms: 1))], fx),
                       .cancelled(reason: "FL n'est plus au premier plan"))
        XCTAssertFalse(fx.trace.contains("delay"))
    }

    func testFailureStopsWithTheOldMessage() {
        let fx = FakeEffects()
        fx.results["delay"] = [.ok, .fail("boîte de dialogue introuvable")]
        let outcome = run([b(.delay(ms: 1)), b(.delay(ms: 2)), b(.delay(ms: 3))], fx)
        XCTAssertEqual(outcome, .failed(step: 2, reason: "boîte de dialogue introuvable"))
        XCTAssertEqual(outcome.text, "Macro arrêtée à l'étape 2 : boîte de dialogue introuvable")
        XCTAssertEqual(fx.trace.filter { $0 == "delay" }.count, 2)
        XCTAssertEqual(fx.stepLines.last, "2 delay → FAIL: boîte de dialogue introuvable in 0 ms")
    }

    /// « Continuer si échec » : le bloc est sauté, « le bloc précédent a échoué » devient vrai.
    func testKeepGoingSetsLastBlockFailed() {
        let fx = FakeEffects()
        fx.results["delay"] = [.fail("boom")]
        let outcome = run([b(.delay(ms: 1), onFailure: .keepGoing),
                           b(.ifElse(.lastBlockFailed, then: [b(key)], otherwise: [])),
                           b(.ifElse(.lastBlockFailed, then: [b(.menuKey(.down, times: 1))], otherwise: []))], fx)
        XCTAssertEqual(outcome, .doneWithWarning("étape 1 non faite (boom)"))
        XCTAssertTrue(fx.trace.contains("key"))
        XCTAssertFalse(fx.trace.contains("menuKey"))          // le « si » précédent a réussi
    }

    func testWarningsAreJoined() {
        let fx = FakeEffects()
        fx.results["delay"] = [.warn("a"), .warn("b")]
        XCTAssertEqual(run([b(.delay(ms: 1)), b(.delay(ms: 2))], fx), .doneWithWarning("a ; b"))
    }

    func testStopBlockEndsTheMacro() {
        let fx = FakeEffects()
        let outcome = run([b(.delay(ms: 1)), b(.stop(message: "fini")), b(.delay(ms: 2))], fx)
        XCTAssertEqual(outcome, .stopped("fini"))
        XCTAssertEqual(fx.trace.filter { $0 == "delay" }.count, 1)
        XCTAssertEqual(fx.trace.last, "cleanup")
    }

    // MARK: Contrôle

    func testIfElseAndNestedFailurePath() {
        let fx = FakeEffects()
        fx.windowAnswers = [true, false]
        _ = run([b(.ifElse(.windowOpen(.dialog), then: [b(key)], otherwise: [b(.delay(ms: 1))])),
                 b(.ifElse(.windowOpen(.dialog), then: [b(key)], otherwise: [b(.delay(ms: 1))]))], fx)
        XCTAssertEqual(fx.trace, ["begin", "idle", "evaluate", "key", "evaluate", "delay", "cleanup"])

        let failing = FakeEffects()
        failing.results["key"] = [.fail("touche interdite")]
        let outcome = run([b(.delay(ms: 1)),
                           b(.ifElse(.lastBlockFailed, then: [], otherwise: [b(.delay(ms: 2)), b(key)]))], failing)
        // Le sinon continue la numérotation du alors (vide) : 2.2.
        XCTAssertEqual(outcome, .failedInBlock(path: "2.2", label: "Touche ou raccourci", reason: "touche interdite"))
        XCTAssertEqual(outcome.text, "Macro arrêtée au bloc 2.2 (Touche) : touche interdite")
        XCTAssertTrue(failing.stepLines.contains("2.2/2 key …"))
    }

    func testRepeatAndWhile() {
        let fx = FakeEffects()
        fx.windowAnswers = [true, true, false]
        _ = run([b(.repeatCount(3, [b(.menuKey(.down, times: 1))])),
                 b(.repeatWhile(.windowOpen(.menu), maxIterations: 10, [b(key)]))], fx)
        XCTAssertEqual(fx.trace.filter { $0 == "menuKey" }.count, 3)
        XCTAssertEqual(fx.trace.filter { $0 == "key" }.count, 2)

        let endless = FakeEffects()
        endless.windowAnswers = Array(repeating: true, count: 10)
        let outcome = run([b(.repeatWhile(.windowOpen(.menu), maxIterations: 2, [b(key)]))], endless)
        XCTAssertEqual(outcome, .failed(step: 1, reason: "condition toujours vraie après 2 tours"))
        XCTAssertEqual(endless.trace.filter { $0 == "key" }.count, 2)
    }

    func testWaitUntilPollsFourTimesASecond() {
        let fx = FakeEffects()
        fx.windowAnswers = [false, false, true]
        XCTAssertEqual(run([b(.waitUntil(.windowOpen(.dialog), timeoutMs: 1_000))], fx), .done)
        XCTAssertEqual(fx.trace.filter { $0 == "pause 250" }.count, 2)

        let never = FakeEffects()
        let outcome = run([b(.waitUntil(.windowOpen(.dialog), timeoutMs: 1_000))], never)
        XCTAssertEqual(outcome, .failed(step: 1, reason: "condition toujours fausse après 1 s"))
        XCTAssertEqual(never.trace.filter { $0 == "pause 250" }.count, 4)
    }

    func testVariables() {
        let fx = FakeEffects()
        _ = run([b(.setVariable("n", .constant(3))),
                 b(.ifElse(.all([.variable("n", .eq, 3), .not(.variable("m", .gt, 0))]), then: [b(key)], otherwise: []))],
                fx, variables: [VariableDecl(name: "n"), VariableDecl(name: "m", initial: 0)])
        XCTAssertTrue(fx.trace.contains("key"))
    }

    func testFLStateConditionFailsClearly() {
        let fx = FakeEffects()
        let outcome = run([b(.ifElse(.flState(query: "isrec", .eq, 0), then: [b(key)], otherwise: []))], fx)
        XCTAssertEqual(outcome, .failed(step: 1, reason: "lien absent"))
    }

    func testCommentsAndDisabledBlocksAreSkipped() {
        let fx = FakeEffects()
        _ = run([b(.delay(ms: 1)), b(.comment("rien")), b(key, enabled: false), b(.menuKey(.up, times: 1))], fx)
        XCTAssertEqual(fx.trace, ["begin", "idle", "delay", "menuKey", "cleanup"])
        XCTAssertEqual(fx.stepLines.first, "1/4 delay …")
        XCTAssertTrue(fx.stepLines.contains("4/4 menuKey …"))
    }

    // MARK: Garde-fou d'exécution

    func testRuntimeLimits() {
        let fx = FakeEffects()
        let outcome = run([b(.repeatCount(10, [b(.delay(ms: 1))]))], fx, limits: RuntimeLimits(maxBlocks: 4, maxSeconds: 300))
        guard case .failedInBlock(_, _, let reason) = outcome else { return XCTFail("\(outcome)") }
        XCTAssertTrue(reason.contains("trop de blocs"))
        XCTAssertEqual(fx.trace.filter { $0 == "delay" }.count, 3)

        let slow = FakeEffects()
        slow.blockSeconds = 0.6
        let late = run([b(.delay(ms: 1)), b(.delay(ms: 1)), b(.delay(ms: 1))], slow, limits: RuntimeLimits(maxBlocks: 100, maxSeconds: 1))
        XCTAssertEqual(late, .failed(step: 3, reason: "macro trop longue (1 s au plus)"))
    }

    /// Suivi d'un essai : chaque bloc commencé puis fini, avec son chemin et son résultat.
    func testObserverSeesEveryBlock() {
        final class Spy: RunObserver {
            var events: [String] = []
            func blockStarted(_ id: UUID, path: String) { events.append("+\(path)") }
            func blockFinished(_ id: UUID, path: String, result: StepResult, ms: Int) { events.append("-\(path) \(result)") }
        }
        let spy = Spy()
        let fx = FakeEffects()
        let p = MacroProgram(blocks: [b(.delay(ms: 1)), b(.repeatCount(1, [b(key)]))], name: "x",
                             source: .blocks(id: UUID(), revision: 0), context: ValidationContext(forbidden: .physical))
        XCTAssertEqual(MacroInterpreter(effects: fx, observer: spy, clock: { fx.now }).run(p), .done)
        XCTAssertEqual(spy.events, ["+1", "-1 ok", "+2", "+2.1", "-2.1 ok", "-2 ok"])
    }
}
