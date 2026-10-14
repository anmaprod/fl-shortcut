import XCTest
@testable import FLShortcut

/// SEC-05 (liste noire), REL-11 / audit 05 (conflits), REL-20 (analyse unique), SEC-04 (détection de FL),
/// audit 04 (disponibilité des actions).
final class SafetyTests: XCTestCase {
    func testPhysicalBlacklist() {
        let f = ForbiddenTargets.physical
        XCTAssertTrue(f.isForbidden(KeyCombo(keyCode: 12, command: true)))                         // ⌘Q
        XCTAssertTrue(f.isForbidden(KeyCombo(keyCode: 12, command: true, shift: true)))            // ⌘⇧Q
        XCTAssertTrue(f.isForbidden(KeyCombo(keyCode: 12, command: true, control: true)))          // ⌃⌘Q
        XCTAssertTrue(f.isForbidden(KeyCombo(keyCode: 13, command: true)))                         // ⌘W
        XCTAssertTrue(f.isForbidden(KeyCombo(keyCode: 51, command: true)))                         // ⌘⌫
        XCTAssertTrue(f.isForbidden(KeyCombo(keyCode: 51, command: true, shift: true)))            // ⌘⇧⌫
        XCTAssertTrue(f.isForbidden(KeyCombo(keyCode: 117, command: true)))                        // ⌘⌦
        XCTAssertTrue(f.isForbidden(KeyCombo(keyCode: 53, command: true, option: true)))           // ⌘⌥Échap
        XCTAssertTrue(f.isForbidden(KeyCombo(keyCode: 48, command: true)))                         // ⌘⇥
        XCTAssertFalse(f.isForbidden(KeyCombo(keyCode: 1, command: true)))                         // ⌘S
        XCTAssertFalse(f.isForbidden(KeyCombo(keyCode: 12)))                                       // Q seul
        XCTAssertFalse(f.isForbidden(KeyCombo(keyCode: 53, option: true)))                         // ⌥Échap
    }

    /// La touche qui quitte (ou ferme) dans la disposition active ; jamais la lettre qui est à sa place en QWERTY.
    func testBlacklistFollowsLayout() {
        let azerty = ForbiddenTargets.make(layout: FakeLayout.azerty)
        XCTAssertTrue(azerty.isForbidden(KeyCombo(keyCode: 0, command: true)))     // ⌘Q en AZERTY
        XCTAssertTrue(azerty.isForbidden(KeyCombo(keyCode: 6, command: true)))     // ⌘W en AZERTY
        XCTAssertFalse(azerty.isForbidden(KeyCombo(keyCode: 12, command: true)))   // ⌘A en AZERTY (signalé)
        XCTAssertFalse(azerty.isForbidden(KeyCombo(keyCode: 13, command: true)))   // ⌘Z en AZERTY
        let qwerty = ForbiddenTargets.make(layout: FakeLayout.qwerty)
        XCTAssertTrue(qwerty.isForbidden(KeyCombo(keyCode: 12, command: true)))    // ⌘Q
        XCTAssertTrue(qwerty.isForbidden(KeyCombo(keyCode: 13, command: true)))    // ⌘W
        XCTAssertFalse(qwerty.isForbidden(KeyCombo(keyCode: 0, command: true)))    // ⌘A
        // Aucune lettre latine : positions physiques Q et W.
        let russian = ForbiddenTargets.make(layout: FakeLayout.russian)
        XCTAssertTrue(russian.isForbidden(KeyCombo(keyCode: 12, command: true)))
        XCTAssertTrue(russian.isForbidden(KeyCombo(keyCode: 13, command: true)))
    }

    func testImportDropsForbiddenTargets() throws {
        let data = try ProfileCodec.encode([
            Remap(trigger: KeyCombo(keyCode: 49), sends: KeyCombo(keyCode: 12, command: true)),
            Remap(trigger: KeyCombo(keyCode: 18, control: true), action: 30),
            Remap(trigger: KeyCombo(keyCode: 58), action: 1),                      // ⌥ seul : refusé
        ])
        let preview = try ProfileImporter.prepare(data, forbidden: .physical, layout: FakeLayout.qwerty)
        XCTAssertEqual(preview.remaps.count, 1)
        XCTAssertEqual(preview.remaps.first?.actionID, 30)
        XCTAssertEqual(preview.rejected.count, 2)
        XCTAssertEqual(preview.summary.count, 1)
    }

    func testImportRejectsOversizedFiles() {
        let big = Data(repeating: 0x20, count: ProfileImporter.maxBytes + 1)
        XCTAssertThrowsError(try ProfileImporter.prepare(big, forbidden: .physical, layout: FakeLayout.qwerty))
    }

    // MARK: Analyse

    private func context(conflicts: ConflictTable = .empty,
                         availability: @escaping (Int) -> ActionAvailability = { _ in .available }) -> AnalysisContext {
        AnalysisContext(toggle: KeyCombo(keyCode: 3, command: true, option: true, control: true),
                        forbidden: .physical, conflicts: conflicts, availability: availability)
    }

    func testAnalyzerFlagsBlockingAndWarnings() {
        let toggle = Remap(trigger: KeyCombo(keyCode: 3, command: true, option: true, control: true), action: 1)
        let bare = Remap(trigger: KeyCombo(keyCode: 29), action: 21)
        let fKey = Remap(trigger: KeyCombo(keyCode: 96), action: 30)
        let quit = Remap(trigger: KeyCombo(keyCode: 0, control: true), sends: KeyCombo(keyCode: 12, command: true))
        var empty = Remap(trigger: KeyCombo(keyCode: 1, control: true), sends: KeyCombo(keyCode: 1))
        empty.target = nil
        let none = Remap(trigger: nil, action: 1)
        let issues = ShortcutAnalyzer.analyze([toggle, bare, fKey, quit, empty, none], context: context())
        XCTAssertTrue(issues[toggle.id]!.contains(.reservedToggle))
        XCTAssertEqual(issues[bare.id], [.bareKey])
        XCTAssertEqual(issues[fKey.id], [])                                        // touche F seule : pas d'alerte
        XCTAssertTrue(issues[quit.id]!.contains { if case .forbiddenTarget = $0 { return true }; return false })
        XCTAssertTrue(issues[empty.id]!.contains(.noTarget))
        XCTAssertTrue(issues[none.id]!.contains(.noTrigger))
        XCTAssertEqual(ShortcutAnalyzer.blocked(issues), [toggle.id, quit.id, empty.id, none.id])
    }

    func testDuplicateCountsOnlyIndexedRows() {                                    // REL-20
        let trigger = KeyCombo(keyCode: 0, control: true)
        var broken = Remap(trigger: trigger, sends: KeyCombo(keyCode: 1))
        broken.target = nil                                                       // ignorée par l'index
        let valid = Remap(trigger: trigger, action: 1)
        let piano = Remap(trigger: trigger, action: 2, context: .pianoRoll)       // autre contexte : permis
        let dup = Remap(trigger: trigger, action: 3)
        let issues = ShortcutAnalyzer.analyze([broken, valid, piano, dup], context: context())
        XCTAssertFalse(issues[valid.id]!.contains(.duplicate))
        XCTAssertFalse(issues[piano.id]!.contains(.duplicate))
        XCTAssertTrue(issues[dup.id]!.contains(.duplicate))
        let index = ShortcutIndex(remaps: [broken, valid, piano, dup], blocked: ShortcutAnalyzer.blocked(issues))
        XCTAssertEqual(index.lookup(trigger, window: nil)?.remapID, valid.id)
    }

    func testLoopDetection() {
        let a = KeyCombo(keyCode: 0, control: true)
        let b = KeyCombo(keyCode: 11, control: true)
        let r1 = Remap(trigger: a, sends: b)
        let r2 = Remap(trigger: b, sends: a)
        let r3 = Remap(trigger: KeyCombo(keyCode: 8, control: true), sends: KeyCombo(keyCode: 96))
        let issues = ShortcutAnalyzer.analyze([r1, r2, r3], context: context())
        XCTAssertTrue(issues[r1.id]!.contains(.loop))
        XCTAssertTrue(issues[r2.id]!.contains(.loop))
        XCTAssertFalse(issues[r3.id]!.contains(.loop))
        XCTAssertFalse(ShortcutAnalyzer.blocked(issues).contains(r1.id))            // avertissement seulement
    }

    func testUnavailableActionIsWarning() {
        let r = Remap(trigger: KeyCombo(keyCode: 0, control: true), action: 12)
        let issues = ShortcutAnalyzer.analyze([r], context: context(availability: { _ in
            .unavailable(reason: "Disponible à partir de FL 21.0.3")
        }))
        XCTAssertEqual(issues[r.id], [.unavailable("Disponible à partir de FL 21.0.3")])
    }

    // MARK: Conflits

    func testConflictTable() {
        let table = ConflictTable.make(layout: FakeLayout.qwerty, systemHotKeys: [:])
        XCTAssertNotNil(table.macOSConflict(KeyCombo(keyCode: 124, control: true)))     // ⌃→ : Spaces
        XCTAssertNotNil(table.macOSConflict(KeyCombo(keyCode: 49, command: true)))      // ⌘Espace
        XCTAssertNotNil(table.flConflict(KeyCombo(keyCode: 1, command: true)))          // ⌘S
        XCTAssertNotNil(table.flConflict(KeyCombo(keyCode: 49)))                        // Espace
        XCTAssertNil(table.macOSConflict(KeyCombo(keyCode: 3, control: true)))          // ⌃F libre
        XCTAssertNil(table.flConflict(KeyCombo(keyCode: 3, control: true)))

        let azerty = ConflictTable.make(layout: FakeLayout.azerty, systemHotKeys: [:])
        XCTAssertNotNil(azerty.flConflict(KeyCombo(keyCode: 13, command: true)))        // ⌘Z en AZERTY
    }

    func testSystemHotKeysParsing() {
        let dict: [String: Any] = [
            "118": ["enabled": true, "value": ["parameters": [65535, 18, 262144], "type": "standard"]],
            "119": ["enabled": false, "value": ["parameters": [65535, 19, 262144], "type": "standard"]],
            "64": ["enabled": 1, "value": ["parameters": [32, 49, 1048576], "type": "standard"]],
            "999": ["enabled": true, "value": ["parameters": [1, 500, 0]]],
            "bad": "x",
        ]
        let parsed = SystemHotKeys.parse(dict)
        XCTAssertEqual(parsed.count, 2)
        XCTAssertEqual(parsed[KeyCombo(keyCode: 18, control: true)], "macOS : Passer au bureau 1")
        XCTAssertNotNil(parsed[KeyCombo(keyCode: 49, command: true)])
        XCTAssertNil(parsed[KeyCombo(keyCode: 19, control: true)])

        let table = ConflictTable.make(layout: FakeLayout.qwerty, systemHotKeys: parsed)
        let r = Remap(trigger: KeyCombo(keyCode: 18, control: true), action: 30)
        let issues = ShortcutAnalyzer.analyze([r], context: context(conflicts: table))
        XCTAssertEqual(issues[r.id], [.macOSConflict("macOS : Passer au bureau 1")])
    }

    // MARK: FL

    func testFLMatcherIsStrict() {
        XCTAssertTrue(FLMatcher.isFL(bundleID: "com.image-line.flstudio"))
        XCTAssertTrue(FLMatcher.isFL(bundleID: "com.Image-Line.FLStudio"))
        XCTAssertFalse(FLMatcher.isFL(bundleID: "com.image-line.flstudiomobile"))
        XCTAssertFalse(FLMatcher.isFL(bundleID: "com.image-line.flstudio.mobile"))
        XCTAssertFalse(FLMatcher.isFL(bundleID: "com.image-line.evil"))
        XCTAssertFalse(FLMatcher.isFL(bundleID: nil))
    }

    func testAvailabilityBeforeAndAfterHandshake() {
        let v206 = FLVersion("20.6.2")
        let v21 = FLVersion("21.0")
        let v2024 = FLVersion("2024.1.1")
        XCTAssertEqual(AvailabilityResolver.availability(of: 1, caps: nil, flVersion: nil), .unverified)
        XCTAssertFalse(AvailabilityResolver.availability(of: 1, caps: nil, flVersion: v206).isUsable)
        XCTAssertEqual(AvailabilityResolver.availability(of: 12, caps: nil, flVersion: v21),
                       .unavailable(reason: "Disponible à partir de FL 21.0.3"))
        XCTAssertEqual(AvailabilityResolver.availability(of: 12, caps: nil, flVersion: v2024), .available)
        let caps = CapabilityMask(ccValues: [1, 0, 0, 0, 0, 0])
        XCTAssertEqual(AvailabilityResolver.availability(of: 1, caps: caps, flVersion: v206), .available)  // le masque fait foi
        XCTAssertFalse(AvailabilityResolver.availability(of: 2, caps: caps, flVersion: v2024).isUsable)
        XCTAssertFalse(AvailabilityResolver.availability(of: 1, caps: CapabilityMask(bits: 0), flVersion: v2024).isUsable)
    }
}
