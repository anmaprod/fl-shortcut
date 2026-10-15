import XCTest
@testable import FLShortcut

/// Organiser : plan de regroupement, couleurs ou dégradés par famille, application et « Revenir comme avant ».
final class OrganizerApplyTests: XCTestCase {
    private let gray = RGBColor(r: 10, g: 10, b: 10)

    private func style(_ family: SoundFamily) -> RGBColor {
        FamilyStyles.initial[family]?.color ?? RGBColor(r: 0, g: 0, b: 0)
    }

    /// Un Channel rack simulé : canal i de couleur (i, 0, 0) ; nil = automation (non écoutée).
    private func rack(_ families: [SoundFamily?]) -> (link: FakeOrganizerLink, result: OrganizerResult) {
        let link = FakeOrganizerLink()
        link.channels = families.indices.map { i in
            ChannelInfo(index: i, type: families[i] == nil ? ChannelInfo.automationType : 2, mixerTrack: 0,
                        color: RGBColor(r: UInt8(i), g: 0, b: 0), name: "Son \(i)")
        }
        var items: [OrganizerItem] = []
        for (i, family) in families.enumerated() {
            guard let family else { continue }
            items.append(OrganizerItem(index: i, name: "Son \(i)", family: family, confidence: 0.9, testNotes: false,
                                       mixerTrack: 0, color: RGBColor(r: UInt8(i), g: 0, b: 0)))
        }
        return (link, OrganizerResult(page: .channelRack, channels: link.channels, items: items, mixer: [],
                                      mixerFamilies: [:]))
    }

    private func apply(_ link: FakeOrganizerLink, _ result: OrganizerResult,
                       styles: [SoundFamily: FamilyStyle] = FamilyStyles.initial) -> ApplyOutcome {
        OrganizerApplier(link: link, moveUp: link.moveSelectedUp)
            .apply(result: result, families: OrganizerApplier.families(of: result), styles: styles)
    }

    func testPlanStableAndBounded() {
        let small = RegroupPlan.make(order: [.melody, .drums, nil, .drums, .bass])
        XCTAssertEqual(small.final, [1, 3, 4, 0, 2])
        XCTAssertEqual(small.moves, [Move(from: 1, up: 1), Move(from: 3, up: 2), Move(from: 4, up: 2)])

        var seed: UInt64 = 7
        func next() -> Int {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(seed >> 33)
        }
        var orders: [[SoundFamily?]] = [[], [.fx]]
        for n in [2, 5, 17, 40] {
            orders.append((0..<n).map { _ -> SoundFamily? in
                let r = next() % 7
                return r == 6 ? nil : SoundFamily.order[r]
            })
        }
        // Pire cas : 40 canaux dans l'ordre inverse des familles.
        orders.append((0..<40).map { i -> SoundFamily? in SoundFamily.order[5 - i * 6 / 40] })
        for order in orders {
            let n = order.count
            let plan = RegroupPlan.make(order: order)
            let ranks = plan.final.map { order[$0]?.rank ?? SoundFamily.order.count }
            XCTAssertEqual(ranks, ranks.sorted())
            for p in plan.final.indices.dropFirst() where ranks[p] == ranks[p - 1] {
                XCTAssertLessThan(plan.final[p - 1], plan.final[p], "ordre d'origine gardé dans chaque famille")
            }
            let simulated = plan.moves.reduce(Array(0..<n)) { RegroupPlan.applying($1, to: $0) }
            XCTAssertEqual(simulated, plan.final)
            XCTAssertLessThanOrEqual(plan.moves.reduce(0) { $0 + $1.up }, n * (n - 1) / 2)
            XCTAssertTrue(plan.moves.allSatisfy { $0.up >= 1 })
        }
    }

    func testPlanBackRestoresOrder() {
        let plan = RegroupPlan.make(order: [.fx, .vocals, .drums, nil, .bass, .drums, .melody, .unsure])
        let back = RegroupPlan.back(final: plan.final)
        XCTAssertEqual(back.reduce(plan.final) { RegroupPlan.applying($1, to: $0) }, Array(0..<8))
        XCTAssertEqual(RegroupPlan.back(final: [0, 1, 2]), [])
        XCTAssertEqual(RegroupPlan.applying(Move(from: 0, up: 1), to: [0, 1]), [0, 1], "hors limites : sans effet")
        XCTAssertEqual(RegroupPlan.applying(Move(from: 2, up: 0), to: [0, 1, 2]), [0, 1, 2])
    }

    func testFadeColorsPerFamily() {
        let first = RGBColor(r: 0xE0, g: 0x45, b: 0x3A), last = RGBColor(r: 0x3F, g: 0xA7, b: 0xE0)
        let fade = FamilyStyle(color: first, fade: last)
        XCTAssertEqual(fade.colors(count: 3).map(\.hex), ["E0453A", "90768D", "3FA7E0"], "même milieu que le script")
        XCTAssertEqual(fade.colors(count: 1), [first])
        XCTAssertEqual(fade.colors(count: 0), [])
        XCTAssertEqual(FamilyStyle(color: first).colors(count: 2), [first, first])

        // Le dégradé suit l'ordre final : les drums d'origine 1, 3 et 4.
        var styles = FamilyStyles.initial
        styles[.drums] = fade
        let families: [Int: SoundFamily] = [0: .melody, 1: .drums, 3: .drums, 4: .drums]
        let colors = OrganizerApplier.plannedColors(families: families, styles: styles, order: [1, 3, 4, 0, 2])
        XCTAssertEqual(colors[1]?.hex, "E0453A")
        XCTAssertEqual(colors[3]?.hex, "90768D")
        XCTAssertEqual(colors[4]?.hex, "3FA7E0")
        XCTAssertEqual(colors[0], style(.melody))
        XCTAssertNil(colors[2], "canal non écouté : couleur inchangée")
    }

    func testFamilyStylesSavedAsJSON() throws {
        let suite = "app.flshortcut.tests.organizer-styles"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertEqual(FamilyStyles.load(from: defaults), FamilyStyles.initial)
        XCTAssertEqual(style(.drums).hex, "E0453A")
        XCTAssertEqual(style(.unsure).hex, "8A8F98")

        var styles = FamilyStyles.initial
        styles[.melody] = FamilyStyle(color: RGBColor(r: 0x3F, g: 0xA7, b: 0xE0), fade: RGBColor(r: 0x1B, g: 0x4F, b: 0x72),
                                      icon: FLIcon(code: "3-4"))
        FamilyStyles.save(styles, to: defaults)
        XCTAssertEqual(FamilyStyles.load(from: defaults), styles)
        let data = try XCTUnwrap(defaults.data(forKey: FamilyStyles.key))
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertTrue(json.contains("\"melody\":{\"color\":\"3FA7E0\",\"fade\":\"1B4F72\",\"icon\":\"3-4\"}"), json)

        defaults.set(Data("{\"drums\":{\"color\":\"zz\"}}".utf8), forKey: FamilyStyles.key)
        XCTAssertEqual(FamilyStyles.load(from: defaults), FamilyStyles.initial, "illisible → valeurs de départ")
    }

    func testApplyColorsInChunks() {
        let (link, result) = rack([SoundFamily?](repeating: .melody, count: 70))
        let outcome = apply(link, result)
        XCTAssertNil(outcome.error)
        XCTAssertEqual(link.log, ["colors 70", "list"], "aucun déplacement : déjà regroupés")
        XCTAssertTrue(link.channels.allSatisfy { $0.color == style(.melody) })
        let pairs = (0..<70).map { (index: $0, color: gray) }
        XCTAssertEqual(OrganizerPayload.setColors(.channels, pairs).map(\.count), [3 + 64 * 5, 3 + 6 * 5])
    }

    func testApplyDetectsMismatch() {
        let (link, result) = rack([.melody, .drums, .bass])
        link.ignoredColors = [1]
        let outcome = apply(link, result)
        XCTAssertEqual(outcome.error, .mismatch)
        XCTAssertEqual(outcome.snapshot.arrangement, [1, 2, 0])
        XCTAssertEqual(link.channels.map(\.name), ["Son 1", "Son 2", "Son 0"])
        XCTAssertTrue(OrganizerError.mismatch.message.contains("Revenir comme avant"))
    }

    func testUndoRestoresColorsAndOrder() {
        let (link, result) = rack([.fx, .vocals, .drums, nil, .bass, .drums, .melody, .unsure])
        let original = link.channels
        let applier = OrganizerApplier(link: link, moveUp: link.moveSelectedUp)
        let outcome = applier.apply(result: result, families: OrganizerApplier.families(of: result),
                                    styles: FamilyStyles.initial)
        XCTAssertNil(outcome.error)
        XCTAssertEqual(link.channels.map(\.name), ["Son 2", "Son 5", "Son 4", "Son 6", "Son 1", "Son 0", "Son 7", "Son 3"])
        XCTAssertEqual(link.channels[0].color, style(.drums))
        XCTAssertEqual(link.channels[7].color, RGBColor(r: 3, g: 0, b: 0), "automation : couleur gardée")

        let back = applier.undo(outcome.snapshot)
        XCTAssertNil(back.error)
        XCTAssertEqual(back.snapshot.arrangement, Array(0..<8))
        XCTAssertEqual(link.channels, original)
    }

    func testMixerColorsOnly() {
        let link = FakeOrganizerLink()
        link.window = .mixer
        link.mixer = (0...3).map { MixerTrackInfo(index: $0, color: gray, name: "Piste \($0)") }
        let result = OrganizerResult(page: .mixer, channels: [], items: [], mixer: link.mixer,
                                     mixerFamilies: [1: .drums, 3: .vocals])
        let applier = OrganizerApplier(link: link, moveUp: { _ in
            XCTFail("pas de déplacement sur le Mixer")
            return 0
        })
        let outcome = applier.apply(result: result, families: OrganizerApplier.families(of: result),
                                    styles: FamilyStyles.initial)
        XCTAssertNil(outcome.error)
        XCTAssertEqual(link.mixer.map(\.color), [gray, style(.drums), gray, style(.vocals)])
        XCTAssertEqual(link.log, ["colors 2", "mixer"])
        XCTAssertNil(applier.undo(outcome.snapshot).error)
        XCTAssertEqual(link.mixer.map(\.color), [gray, gray, gray, gray])
    }

    func testStopsWhenPageChanges() {
        // La Playlist passe devant après le premier déplacement.
        let (link, result) = rack([.melody, .drums, .bass])
        let original = link.channels
        let leaving = OrganizerApplier(link: link, moveUp: { count in
            let done = link.moveSelectedUp(count)
            link.window = .playlist
            return done
        })
        let outcome = leaving.apply(result: result, families: OrganizerApplier.families(of: result),
                                    styles: FamilyStyles.initial)
        XCTAssertEqual(outcome.error, .interrupted)
        XCTAssertEqual(outcome.snapshot.arrangement, [1, 0, 2])
        XCTAssertEqual(link.channels.map(\.name), ["Son 1", "Son 0", "Son 2"])
        link.window = .channelRack
        let back = OrganizerApplier(link: link, moveUp: link.moveSelectedUp).undo(outcome.snapshot)
        XCTAssertNil(back.error)
        XCTAssertEqual(link.channels, original)

        // Arrêt au milieu d'une remontée de 2 places : la disposition suit le pas fait.
        let (half, halfResult) = rack([.melody, .melody, .drums])
        let halfOriginal = half.channels
        let partial = OrganizerApplier(link: half, moveUp: { _ in half.moveSelectedUp(1) })
            .apply(result: halfResult, families: OrganizerApplier.families(of: halfResult), styles: FamilyStyles.initial)
        XCTAssertEqual(partial.error, .interrupted)
        XCTAssertEqual(partial.snapshot.arrangement, [0, 2, 1])
        XCTAssertNil(OrganizerApplier(link: half, moveUp: half.moveSelectedUp).undo(partial.snapshot).error)
        XCTAssertEqual(half.channels, halfOriginal)
        XCTAssertTrue(OrganizerError.interrupted.message.contains("Revenir comme avant"))
    }
}
