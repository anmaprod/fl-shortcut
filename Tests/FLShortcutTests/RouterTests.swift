import XCTest
@testable import FLShortcut

/// Index des raccourcis (contexte, priorité) et routeur du tap (REL-04/05/06/15, SEC-05, anti-boucle).
final class IndexTests: XCTestCase {
    private let ctrl1 = KeyCombo(keyCode: 18, control: true)

    func testSpecificContextWinsThenEverywhere() {
        let everywhere = Remap(trigger: ctrl1, action: 30)
        let piano = Remap(trigger: ctrl1, action: 32, context: .pianoRoll)
        let index = ShortcutIndex(remaps: [everywhere, piano], blocked: [])
        XCTAssertEqual(index.lookup(ctrl1, window: .pianoRoll)?.action, .flAction(32))
        XCTAssertEqual(index.lookup(ctrl1, window: .mixer)?.action, .flAction(30))
        XCTAssertEqual(index.lookup(ctrl1, window: .browser)?.action, .flAction(30))
        XCTAssertEqual(index.lookup(ctrl1, window: nil)?.action, .flAction(30))
        XCTAssertNil(index.lookup(KeyCombo(keyCode: 19, control: true), window: nil))
    }

    func testContextOnlyShortcutNeedsKnownWindow() {
        let index = ShortcutIndex(remaps: [Remap(trigger: ctrl1, action: 21, context: .mixer)], blocked: [])
        XCTAssertNil(index.lookup(ctrl1, window: nil))
        XCTAssertNil(index.lookup(ctrl1, window: .playlist))
        XCTAssertEqual(index.lookup(ctrl1, window: .mixer)?.action, .flAction(21))
    }

    func testDisabledBlockedAndIncompleteAreExcluded() {
        var off = Remap(trigger: ctrl1, action: 30)
        off.enabled = false
        let blocked = Remap(trigger: KeyCombo(keyCode: 19, control: true), action: 31)
        var noTarget = Remap(trigger: KeyCombo(keyCode: 20, control: true), sends: KeyCombo(keyCode: 1))
        noTarget.target = nil
        let index = ShortcutIndex(remaps: [off, blocked, noTarget], blocked: [blocked.id])
        XCTAssertEqual(index.count, 0)
    }

    func testFirstOfDuplicatesWins() {
        let a = Remap(trigger: ctrl1, action: 30)
        let b = Remap(trigger: ctrl1, action: 33)
        XCTAssertEqual(ShortcutIndex(remaps: [a, b], blocked: []).lookup(ctrl1, window: nil)?.remapID, a.id)
    }
}

final class RouterTests: XCTestCase {
    private let ctrlRight = KeyCombo(keyCode: 124, option: true, control: true)
    private let zero = KeyCombo(keyCode: 29)
    private let toggle = KeyCombo(keyCode: 3, command: true, option: true, control: true)
    private let linked = LinkRoutingView(linked: true, window: .playlist,
                                         capabilities: CapabilityMask(bits: (1 << 38) - 1), canSign: true)

    private func config(_ remaps: [Remap], enabled: Bool = true) -> TapConfig {
        var c = TapConfig()
        c.enabled = enabled
        c.index = ShortcutIndex(remaps: remaps, blocked: [])
        c.toggle = toggle
        return c
    }

    private func down(_ c: KeyCombo, repeat r: Bool = false, fl: Bool = true) -> RouterInput {
        RouterInput(kind: .down, combo: c, isRepeat: r, isOwn: false, targetIsFL: fl)
    }

    private func up(_ c: KeyCombo, fl: Bool = true) -> RouterInput {
        RouterInput(kind: .up, combo: KeyCombo(keyCode: c.keyCode), isRepeat: false, isOwn: false, targetIsFL: fl)
    }

    func testNominalActionSwallowsDownAndUpOnce() {
        var router = KeyRouter()
        let cfg = config([Remap(trigger: ctrlRight, action: 13)])
        XCTAssertEqual(router.route(down(ctrlRight), config: cfg, link: linked),
                       RouterDecision(swallow: true, effects: [.sendAction(13)]))
        XCTAssertEqual(router.route(up(ctrlRight), config: cfg, link: linked), .swallowOnly)
        XCTAssertTrue(router.owned.isEmpty)
    }

    func testInactiveLinkLetsActionKeyThrough() {
        var router = KeyRouter()
        let cfg = config([Remap(trigger: zero, action: 21)])
        XCTAssertEqual(router.route(down(zero), config: cfg, link: .offline), .pass)
        var noKey = linked
        noKey.canSign = false
        XCTAssertEqual(router.route(down(zero), config: cfg, link: noKey), .pass)
        var noCaps = linked
        noCaps.capabilities = CapabilityMask(bits: 0)
        XCTAssertEqual(router.route(down(zero), config: cfg, link: noCaps), .pass)
        XCTAssertEqual(router.route(up(zero), config: cfg, link: .offline), .pass)
    }

    func testNotFLTargetPasses() {                                     // REL-05 : Spotlight par-dessus FL
        var router = KeyRouter()
        let cfg = config([Remap(trigger: zero, action: 21)])
        XCTAssertEqual(router.route(down(zero, fl: false), config: cfg, link: linked), .pass)
    }

    func testMissedKeyUpDoesNotPoisonKey() {                           // REL-04 (a)
        var router = KeyRouter()
        let cfg = config([Remap(trigger: zero, action: 21)])
        XCTAssertTrue(router.route(down(zero), config: cfg, link: linked).swallow)
        _ = router.route(RouterInput(kind: .tapDisabled, combo: KeyCombo(keyCode: 0)), config: cfg, link: linked)
        let paused = config([Remap(trigger: zero, action: 21)], enabled: false)
        XCTAssertEqual(router.route(down(zero), config: paused, link: linked), .pass)
        XCTAssertEqual(router.route(up(zero), config: paused, link: linked), .pass)
    }

    func testRepeatsFollowInitialDecisionEvenWithoutModifiers() {     // REL-04 (b)
        var router = KeyRouter()
        let cfg = config([Remap(trigger: ctrlRight, action: 13)])
        _ = router.route(down(ctrlRight), config: cfg, link: linked)
        let bareRepeat = down(KeyCombo(keyCode: 124), repeat: true)
        XCTAssertEqual(router.route(bareRepeat, config: cfg, link: linked), .swallowOnly)
        XCTAssertEqual(router.route(bareRepeat, config: cfg, link: linked), .swallowOnly)
        XCTAssertEqual(router.route(up(ctrlRight), config: cfg, link: linked), .swallowOnly)
        let orphanRepeat = down(KeyCombo(keyCode: 124), repeat: true)
        XCTAssertEqual(router.route(orphanRepeat, config: cfg, link: linked), .pass)
    }

    func testToggleOnlyOnceDespiteAutoRepeat() {                       // REL-15
        var router = KeyRouter()
        let cfg = config([])
        var toggles = 0
        for i in 0..<6 {
            let d = router.route(down(toggle, repeat: i > 0, fl: false), config: cfg, link: .offline)
            XCTAssertTrue(d.swallow)
            toggles += d.effects.filter { $0 == .toggleEnabled }.count
        }
        XCTAssertEqual(toggles, 1)
    }

    func testRecordingLetsEverythingThrough() {                        // REL-19
        var router = KeyRouter()
        var cfg = config([Remap(trigger: zero, action: 21)])
        cfg.recording = true
        XCTAssertEqual(router.route(down(toggle), config: cfg, link: linked), .pass)
        XCTAssertEqual(router.route(down(zero), config: cfg, link: linked), .pass)
    }

    func testOwnEventsAreNeverReprocessed() {                          // anti-boucle
        var router = KeyRouter()
        let a = KeyCombo(keyCode: 0, control: true)
        let b = KeyCombo(keyCode: 11, control: true)
        let cfg = config([Remap(trigger: a, sends: b), Remap(trigger: b, sends: KeyCombo(keyCode: 8, control: true))])
        XCTAssertEqual(router.route(down(a), config: cfg, link: linked),
                       RouterDecision(swallow: true, effects: [.post(b)]))
        let own = RouterInput(kind: .down, combo: b, isRepeat: false, isOwn: true, targetIsFL: true)
        XCTAssertEqual(router.route(own, config: cfg, link: linked), .pass)
    }

    func testKeystrokeRepeatsRepost() {
        var router = KeyRouter()
        let a = KeyCombo(keyCode: 0, control: true)
        let target = KeyCombo(keyCode: 96)
        let cfg = config([Remap(trigger: a, sends: target)])
        _ = router.route(down(a), config: cfg, link: .offline)               // touche de FL : pas besoin du lien
        XCTAssertEqual(router.route(down(a, repeat: true), config: cfg, link: .offline),
                       RouterDecision(swallow: true, effects: [.post(target)]))
    }

    func testForbiddenTargetIsNeverPostedEvenIfIndexed() {             // SEC-05 non contournable
        var router = KeyRouter()
        let trigger = KeyCombo(keyCode: 49, control: true)
        let quit = KeyCombo(keyCode: 12, command: true)
        let cfg = config([Remap(trigger: trigger, sends: quit)])           // index construit sans analyse
        XCTAssertEqual(router.route(down(trigger), config: cfg, link: linked), .pass)
    }

    func testReleasedPressLetsRepeatsAndKeyUpThrough() {               // REL-06 : trame non émise
        var router = KeyRouter()
        let cfg = config([Remap(trigger: zero, action: 21)])
        XCTAssertTrue(router.route(down(zero), config: cfg, link: linked).swallow)
        router.release(zero.keyCode)
        XCTAssertEqual(router.route(down(zero, repeat: true), config: cfg, link: linked), .pass)
        XCTAssertEqual(router.route(up(zero), config: cfg, link: linked), .pass)
        XCTAssertTrue(router.owned.isEmpty)
    }

    func testWindowFilteringUsesLinkWindow() {
        var router = KeyRouter()
        let cfg = config([Remap(trigger: zero, action: 21, context: .mixer)])
        XCTAssertEqual(router.route(down(zero), config: cfg, link: linked), .pass)       // Playlist active
        var inMixer = linked
        inMixer.window = .mixer
        XCTAssertEqual(router.route(down(zero), config: cfg, link: inMixer).effects, [.sendAction(21)])
    }
}
