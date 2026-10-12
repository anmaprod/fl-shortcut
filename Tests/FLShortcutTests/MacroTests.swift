import XCTest
@testable import FLShortcut

/// Macros (sans MIDI) : construction des étapes, bornes de sécurité, profil JSON, routage du tap, import.
final class MacroTests: XCTestCase {
    private let trigger = KeyCombo(keyCode: 15, control: true)
    private let toggle = KeyCombo(keyCode: 3, command: true, option: true, control: true)

    private func spot(_ x: Double = 10) -> ClickSpot { ClickSpot(anchor: .cursor, dx: x, dy: 2) }

    /// Ancien modèle à positions apprises.
    private func legacy() -> Macro {
        var m = Macro()
        m.template = .quickRecord
        return m
    }

    private func ready() -> Macro {
        var m = legacy()
        for name in MacroLibrary.requiredSpots { m.spots[name] = spot() }
        return m
    }

    private func steps(_ m: Macro) -> [MacroStep] {
        guard case .success(let s) = MacroLibrary.steps(for: m, forbidden: .physical) else {
            XCTFail("macro refusée")
            return []
        }
        return s
    }

    // MARK: Construction

    func testIncompleteMacroListsMissingSpots() {
        guard case .failure(.missing(let names)) = MacroLibrary.steps(for: legacy(), forbidden: .physical) else {
            return XCTFail("devrait demander les positions")
        }
        XCTAssertEqual(Set(names), Set(MacroLibrary.requiredSpots))
    }

    func testWithoutArmNoSpotIsNeeded() {
        var m = legacy()
        m.armAndInput = false
        XCTAssertFalse(steps(m).contains { $0.kind == .click && $0.button == .left })
    }

    func testAskEveryTimeWaitsForTheUser() {
        let s = steps(ready())
        XCTAssertFalse(s.contains { $0.kind == .chooseFile })
        XCTAssertEqual(s.first { $0.kind == .waitDialogClose }?.ms, MacroLibrary.maxWaitMs)
        XCTAssertEqual(s.first?.kind, .click)
        XCTAssertEqual(s.first?.button, .right)
    }

    func testFixedPresetTypesItsPathAndDoesNotWaitForTheUser() {
        var m = ready()
        m.presetPath = "/Users/test/Presets/Voix.fst"
        let s = steps(m)
        XCTAssertEqual(s.first { $0.kind == .chooseFile }?.path, "/Users/test/Presets/Voix.fst")
        XCTAssertLessThan(s.first { $0.kind == .waitDialogClose }?.ms ?? .max, 10_000)
    }

    func testRecKeyEndsTheMacroOnlyWhenWanted() {
        var m = ready()
        m.recKey = KeyCombo(keyCode: 15)
        XCTAssertEqual(steps(m).last, .key(KeyCombo(keyCode: 15)))
        m.startRecording = false
        XCTAssertNotEqual(steps(m).last?.kind, .key)
    }

    func testMenuFallbackNeedsBothPositions() {
        var m = ready()
        m.spots[Macro.Spot.menuFile] = spot(1)
        XCTAssertEqual(steps(m).first { $0.kind == .menu }?.fallback.count, 0)
        m.spots[Macro.Spot.menuOpenState] = spot(2)
        XCTAssertEqual(steps(m).first { $0.kind == .menu }?.fallback.count, 2)
    }

    // MARK: Modèle automatique (rien à apprendre)

    func testAutoRecordNeedsNothingAndFollowsTheOrder() {
        var m = Macro()
        m.recKey = KeyCombo(keyCode: 15)
        XCTAssertEqual(m.template, .autoRecord)
        let kinds = steps(m).map(\.kind)
        XCTAssertEqual(kinds, [.trackMenu, .waitDialog, .waitDialogClose, .delay,
                               .armTrack, .recordOn, .selectInput, .feedbackCheck])
        XCTAssertEqual(steps(m).first { $0.kind == .waitDialogClose }?.ms, MacroLibrary.maxWaitMs)
        // Touche REC portée par l'étape (utilisée seulement sans lien MIDI).
        XCTAssertEqual(steps(m).first { $0.kind == .recordOn }?.combo, KeyCombo(keyCode: 15))
    }

    func testAutoRecordWithFixedPresetAndWithoutArmOrRec() {
        var m = Macro()
        m.presetPath = "/Users/test/Voix.fst"
        m.armAndInput = false
        m.startRecording = false
        let kinds = steps(m).map(\.kind)
        XCTAssertEqual(kinds, [.trackMenu, .waitDialog, .chooseFile, .waitDialogClose])
    }

    func testAutoRecordMenuTitlesHaveVariants() {
        let menu = steps(Macro()).first { $0.kind == .trackMenu }
        XCTAssertEqual(menu?.titles.count, 2)
        XCTAssertTrue(menu?.titles.first?.split(separator: "|").contains("File") == true)
        XCTAssertTrue(menu?.titles.last?.split(separator: "|").contains("Open mixer track state") == true)
    }

    func testArmAndRecUseTheScriptActionsThatNeverSwitchOff() {
        XCTAssertEqual(FLActions.info(39)?.key, "armon")
        XCTAssertEqual(FLActions.info(40)?.key, "recon")
        XCTAssertEqual(MacroRunner.armOnAction, 39)
        XCTAssertEqual(MacroRunner.recOnAction, 40)
    }

    func testRecOnlyStillChecksFeedbackAtTheEnd() {
        var m = Macro()
        m.armAndInput = false
        let kinds = steps(m).map(\.kind)
        XCTAssertEqual(kinds, [.trackMenu, .waitDialog, .waitDialogClose, .delay, .recordOn, .feedbackCheck])
    }

    func testLearnedSpotsAreRelativeAndChecked() {
        let anchor = CGPoint(x: 100, y: 200)
        let points = [CGPoint(x: 140, y: 230), CGPoint(x: 150, y: 290)]
        let spots = MacroSpots.Learned(anchorSize: CGSize(width: 800, height: 600), offsets: MacroSpots.offsets(points, from: anchor))
        XCTAssertEqual(spots.points(from: anchor), points)
        XCTAssertEqual(spots.points(from: CGPoint(x: 0, y: 0)), [CGPoint(x: 40, y: 30), CGPoint(x: 50, y: 90)])
        XCTAssertTrue(spots.matches(size: CGSize(width: 801, height: 600)))
        XCTAssertFalse(spots.matches(size: CGSize(width: 900, height: 600)))
    }

    func testFeedbackRiskOnlyWithComputerMicAndSpeakers() {
        let mic = FeedbackRisk.Device(name: "Micro MacBook Pro", builtIn: true, headphones: false)
        let speakers = FeedbackRisk.Device(name: "Haut-parleurs MacBook Pro", builtIn: true, headphones: false)
        let jack = FeedbackRisk.Device(name: "Casque externe", builtIn: true, headphones: true)
        let card = FeedbackRisk.Device(name: "Scarlett 2i2", builtIn: false, headphones: false)
        XCTAssertTrue(FeedbackRisk.Report(input: mic, output: speakers).risky)
        XCTAssertFalse(FeedbackRisk.Report(input: mic, output: jack).risky)
        XCTAssertFalse(FeedbackRisk.Report(input: card, output: card).risky)
        XCTAssertFalse(FeedbackRisk.Report(input: mic, output: card).risky)
        XCTAssertFalse(FeedbackRisk.Report(input: nil, output: speakers).risky)
    }

    // MARK: Sécurité

    func testForbiddenKeyIsRefusedInCustomMacro() {
        var m = Macro()
        m.template = .custom
        m.steps = [.key(KeyCombo(keyCode: 12, command: true))]       // ⌘Q
        if case .success = MacroLibrary.steps(for: m, forbidden: .physical) { XCTFail("⌘Q doit être refusé") }
    }

    func testLimits() {
        var m = Macro()
        m.template = .custom
        m.steps = Array(repeating: .delay(10), count: MacroLibrary.maxSteps + 1)
        XCTAssertNotNil(MacroLibrary.problem(in: m, forbidden: .physical))
        m.steps = []
        XCTAssertNotNil(MacroLibrary.problem(in: m, forbidden: .physical))
        m.steps = [.delay(MacroLibrary.maxDelayMs + 1)]
        XCTAssertNotNil(MacroLibrary.problem(in: m, forbidden: .physical))
        m.steps = [.click(ClickSpot(anchor: .cursor, dx: .infinity, dy: 0))]
        XCTAssertNotNil(MacroLibrary.problem(in: m, forbidden: .physical))
        m.steps = [.chooseFile("/tmp/a\nb.fst")]
        XCTAssertNotNil(MacroLibrary.problem(in: m, forbidden: .physical))
        m.steps = [.delay(100), .waitDialog(500)]
        XCTAssertNil(MacroLibrary.problem(in: m, forbidden: .physical))
    }

    // MARK: Profil

    func testProfileRoundTrip() throws {
        var m = ready()
        m.presetPath = "/Users/test/Voix.fst"
        m.recKey = KeyCombo(keyCode: 15)
        let r = Remap(trigger: trigger, macro: m)
        let decoded = try ProfileCodec.decode(try ProfileCodec.encode([r]))
        XCTAssertEqual(decoded.dropped, 0)
        XCTAssertEqual(decoded.remaps.first?.kind, .macro)
        XCTAssertEqual(decoded.remaps.first?.macro, m)
    }

    func testUnknownTemplateKeepsTheLineWithoutMacro() throws {
        let json = """
        {"version":2,"remaps":[{"kind":"macro","trigger":{"keyCode":15,"control":true},
          "macro":{"template":"futur"}}]}
        """
        let decoded = try ProfileCodec.decode(Data(json.utf8))
        XCTAssertEqual(decoded.dropped, 0)
        XCTAssertEqual(decoded.remaps.first?.kind, .macro)
        XCTAssertNil(decoded.remaps.first?.macro)
        XCTAssertNil(decoded.remaps.first?.routedAction)
    }

    func testAnalyzerBlocksIncompleteMacro() {
        let incomplete = Remap(trigger: trigger, macro: legacy())
        let ctx = AnalysisContext(toggle: toggle, forbidden: .physical, conflicts: .empty,
                                  availability: { _ in .available })
        let issues = ShortcutAnalyzer.analyze([incomplete], context: ctx)[incomplete.id] ?? []
        XCTAssertTrue(issues.contains { if case .macroInvalid = $0 { return true } else { return false } })
        XCTAssertTrue(ShortcutAnalyzer.blocked([incomplete.id: issues]).contains(incomplete.id))
    }

    func testImportRefusesCustomMacro() throws {
        var custom = Macro()
        custom.template = .custom
        custom.steps = [.delay(100)]
        let data = try ProfileCodec.encode([Remap(trigger: trigger, macro: custom),
                                            Remap(trigger: KeyCombo(keyCode: 17, control: true), macro: ready())])
        let preview = try ProfileImporter.prepare(data, forbidden: .physical, layout: FakeLayout.qwerty)
        XCTAssertEqual(preview.remaps.count, 1)
        XCTAssertEqual(preview.remaps.first?.macro?.template, .quickRecord)
        XCTAssertEqual(preview.rejected.count, 1)
    }

    // MARK: Routeur du tap

    private let linked = LinkRoutingView.offline

    private func config(_ remaps: [Remap]) -> TapConfig {
        var c = TapConfig()
        c.toggle = toggle
        c.index = ShortcutIndex(remaps: remaps, blocked: [])
        return c
    }

    private func down(_ c: KeyCombo, repeat r: Bool = false, fl: Bool = true) -> RouterInput {
        RouterInput(kind: .down, combo: c, isRepeat: r, isOwn: false, targetIsFL: fl)
    }

    func testRouterRunsTheMacroOnceAndSwallowsTheKey() {
        let m = ready()
        let cfg = config([Remap(trigger: trigger, macro: m)])
        var router = KeyRouter()
        let d = router.route(down(trigger), config: cfg, link: linked)
        XCTAssertTrue(d.swallow)
        XCTAssertEqual(d.effects, [.runMacro(m)])
        // Auto-répétition : avalée, jamais relancée.
        let rep = router.route(down(trigger, repeat: true), config: cfg, link: linked)
        XCTAssertEqual(rep, .swallowOnly)
        // Relâchement : avalé.
        let up = router.route(RouterInput(kind: .up, combo: trigger, isRepeat: false, isOwn: false, targetIsFL: true),
                              config: cfg, link: linked)
        XCTAssertEqual(up, .swallowOnly)
    }

    func testRouterIgnoresMacroOutsideFLOrWhenPaused() {
        let cfg = config([Remap(trigger: trigger, macro: ready())])
        var router = KeyRouter()
        XCTAssertEqual(router.route(down(trigger, fl: false), config: cfg, link: linked), .pass)
        var paused = cfg
        paused.enabled = false
        XCTAssertEqual(router.route(down(trigger), config: paused, link: linked), .pass)
    }
}
