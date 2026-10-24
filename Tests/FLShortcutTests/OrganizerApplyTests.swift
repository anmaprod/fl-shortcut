import XCTest
@testable import FLShortcut

/// Organiser : plan de regroupement, couleurs ou dégradés par famille, application et « Revenir comme avant ».
final class OrganizerApplyTests: XCTestCase {
    private let gray = RGBColor(r: 10, g: 10, b: 10)

    private func style(_ family: SoundFamily) -> FLShortcut.RGBColor {
        FamilyStyles.initial[family]?.color ?? RGBColor(r: 0, g: 0, b: 0)
    }

    /// Un Channel rack simulé : canal i de couleur (i, 0, 0) ; nil = automation (non écoutée). `kinds` : ce qu'est
    /// le son i (Kick…).
    private func rack(_ families: [SoundFamily?], kinds: [Int: SoundKind] = [:])
        -> (link: FakeOrganizerLink, result: OrganizerResult) {
        let link = FakeOrganizerLink()
        link.channels = families.indices.map { i in
            ChannelInfo(index: i, type: families[i] == nil ? ChannelInfo.automationType : 2, mixerTrack: 0,
                        color: RGBColor(r: UInt8(i), g: 0, b: 0), name: "Son \(i)")
        }
        var items: [OrganizerItem] = []
        for (i, family) in families.enumerated() {
            guard let family else { continue }
            items.append(OrganizerItem(index: i, name: "Son \(i)", family: family, confidence: 0.9, testNotes: false,
                                       mixerTrack: 0, color: RGBColor(r: UInt8(i), g: 0, b: 0), kind: kinds[i]))
        }
        return (link, OrganizerResult(channels: link.channels, items: items))
    }

    /// Channel rack seul, sans renommer (les autres pages ont leurs propres tests).
    private let rackOnly = OrganizerOptions(patterns: false, mixer: false, playlist: false, rename: false)

    private func plan(_ result: OrganizerResult, styles: [SoundFamily: FamilyStyle] = FamilyStyles.initial,
                      options: OrganizerOptions = OrganizerOptions()) -> OrganizerPlan {
        OrganizerPlan.make(result, families: OrganizerApplier.families(of: result),
                           kinds: OrganizerApplier.kinds(of: result), styles: styles, options: options)
    }

    private func applier(_ link: FakeOrganizerLink, placeIcon: @escaping (FLIcon) -> OrganizerError? = { _ in nil })
        -> OrganizerApplier {
        OrganizerApplier(link: link, moveUp: link.moveSelectedUp, moveLeft: link.moveSelectedLeft, placeIcon: placeIcon,
                         deleteSelected: link.deleteSelected, moveTrack: link.moveTrackUp)
    }

    private func apply(_ link: FakeOrganizerLink, _ result: OrganizerResult,
                       styles: [SoundFamily: FamilyStyle] = FamilyStyles.initial,
                       options: OrganizerOptions? = nil) -> ApplyOutcome {
        applier(link).apply(plan(result, styles: styles, options: options ?? rackOnly), result: result, styles: styles)
    }

    func testPlanStableAndBounded() {
        // Ordre des familles : voix, mélodies, basse, drums, FX, à vérifier ; non écoutés à la fin.
        let small = RegroupPlan.make(order: [.melody, .drums, nil, .drums, .bass])
        XCTAssertEqual(small.final, [0, 4, 1, 3, 2])
        XCTAssertEqual(small.moves, [Move(from: 4, up: 3), Move(from: 4, up: 1)])

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

    /// Dans une famille, les sons d'une même sorte ensemble (les Kick, puis les Snare, les Hi-hat…), ceux qui ne
    /// disent rien après ; un son changé de famille dans l'aperçu n'est plus rangé selon son ancienne sorte.
    func testRackGroupsSameKinds() {
        let (link, result) = rack([.drums, .drums, .melody, .drums, .drums, .drums],
                                  kinds: [0: .hiHat, 1: .kick, 2: .lead, 3: .snare, 4: .kick])
        XCTAssertNil(apply(link, result).error)
        XCTAssertEqual(link.channels.map(\.name), ["Son 2", "Son 1", "Son 4", "Son 3", "Son 0", "Son 5"])
        var families = OrganizerApplier.families(of: result)
        families[4] = .bass
        let plan = OrganizerApplier.rackPlan(result.channels, families: families,
                                             kinds: OrganizerApplier.kinds(of: result))
        XCTAssertEqual(plan.final, [2, 4, 1, 3, 0, 5])
        XCTAssertNil(OrganizerApplier.kind(4, families: families, kinds: OrganizerApplier.kinds(of: result)))
        XCTAssertEqual(RegroupPlan.make(order: [.drums, .drums], kinds: [.snare]).final, [0, 1], "sorte manquante : après")
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
        XCTAssertEqual(link.log, ["colors channels 70", "list"], "aucun déplacement : déjà regroupés")
        XCTAssertTrue(link.channels.allSatisfy { $0.color == style(.melody) })
        let pairs = (0..<70).map { (index: $0, color: gray) }
        XCTAssertEqual(OrganizerPayload.setColors(.channels, pairs).map(\.count), [3 + 64 * 5, 3 + 6 * 5])
    }

    func testApplyDetectsMismatch() {
        let (link, result) = rack([.melody, .drums, .bass])
        link.ignoredColors = [1]
        let outcome = apply(link, result)
        XCTAssertEqual(outcome.error, .mismatch)
        XCTAssertEqual(outcome.snapshot.rack?.arrangement, [0, 2, 1])
        XCTAssertEqual(link.channels.map(\.name), ["Son 0", "Son 2", "Son 1"])
        XCTAssertTrue(OrganizerError.mismatch.message.contains("Revenir comme avant"))
    }

    func testUndoRestoresColorsNamesAndOrder() {
        let (link, result) = rack([.fx, .vocals, .drums, nil, .bass, .drums, .melody, .unsure])
        let original = link.channels
        let outcome = apply(link, result, options: OrganizerOptions(patterns: false, mixer: false, playlist: false))
        XCTAssertNil(outcome.error)
        XCTAssertEqual(link.channels.map(\.name), ["Voix", "Mélodie", "Basse", "Drums", "Drums 2", "FX", "Son 7", "Son 3"],
                       "« À vérifier » et l'automation gardent leur nom")
        XCTAssertEqual(link.channels[0].color, style(.vocals))
        XCTAssertEqual(link.channels[7].color, RGBColor(r: 3, g: 0, b: 0), "automation : couleur gardée")

        let back = applier(link).undo(outcome.snapshot)
        XCTAssertNil(back.error)
        XCTAssertTrue(back.snapshot.isEmpty)
        XCTAssertEqual(link.channels, original)
    }

    /// Icônes en dernier, sur la place finale de chaque son (après le regroupement), une sélection chacune.
    func testIconsOnFinalPlaces() throws {
        let (link, result) = rack([.melody, .drums, .bass])
        var styles = FamilyStyles.initial
        styles[.drums]?.icon = try XCTUnwrap(FLIcon(code: "7-4"))
        styles[.melody]?.icon = try XCTUnwrap(FLIcon(code: "6-0"))
        var placed: [String] = []
        let outcome = applier(link, placeIcon: { icon in
            placed.append("\(link.selected ?? -1):\(icon.code)")
            return nil
        }).apply(plan(result, styles: styles, options: rackOnly), result: result, styles: styles)
        XCTAssertNil(outcome.error)
        XCTAssertEqual(link.channels.map(\.name), ["Son 0", "Son 2", "Son 1"])
        XCTAssertEqual(placed, ["0:6-0", "2:7-4"], "Son 0 (Mélodies) à la place 0, Son 1 (Drums) à la place 2")

        // Une icône manquée arrête la suite ; les couleurs et le regroupement restent défaisables.
        let (other, otherResult) = rack([.melody, .drums, .bass])
        let missed = applier(other, placeIcon: { _ in .failed("Icône non posée.") })
            .apply(plan(otherResult, styles: styles, options: rackOnly), result: otherResult, styles: styles)
        XCTAssertEqual(missed.error, .failed("Icône non posée."))
        XCTAssertEqual(missed.snapshot.rack?.arrangement, [0, 2, 1])
    }

    /// Capture du propriétaire (Channel rack à moitié rangé, « La page de FL a changé ») : la page qui n'est plus
    /// devant (FL qui finit d'ouvrir la copie) est remise devant et le rangement continue ; arrêt seulement si elle
    /// ne revient pas.
    func testPageThatChangesIsShownAgain() {
        let (link, result) = rack([.drums, .melody, .vocals])
        var left = 1
        let once = OrganizerApplier(link: link, moveUp: { count in
            let done = link.moveSelectedUp(count)
            if left > 0 {
                left -= 1
                link.window = .playlist
            }
            return done
        }, wait: { _ in })
        let outcome = once.apply(plan(result, options: rackOnly), result: result, styles: FamilyStyles.initial)
        XCTAssertNil(outcome.error)
        XCTAssertEqual(link.channels.map(\.name), ["Son 2", "Son 1", "Son 0"], "Voix, Mélodies, Drums")
        XCTAssertEqual(link.log.filter { $0 == "show channelRack" }.count, 2, "remis devant une fois")
        XCTAssertTrue(outcome.trace.contains("page remise 1"), "\(outcome.trace)")
    }

    func testStopsWhenPageChanges() {
        // La Playlist passe devant après le premier déplacement (deux sont prévus) et y reste.
        let (link, result) = rack([.drums, .melody, .vocals])
        let original = link.channels
        let leaving = OrganizerApplier(link: link, moveUp: { count in
            let done = link.moveSelectedUp(count)
            link.window = .playlist
            link.keptWindow = .playlist
            return done
        }, wait: { _ in })
        let outcome = leaving.apply(plan(result, options: rackOnly), result: result, styles: FamilyStyles.initial)
        XCTAssertEqual(outcome.error, .interrupted)
        XCTAssertEqual(outcome.snapshot.rack?.arrangement, [2, 0, 1])
        XCTAssertEqual(link.channels.map(\.name), ["Son 2", "Son 0", "Son 1"])
        link.keptWindow = nil
        let back = applier(link).undo(outcome.snapshot)
        XCTAssertNil(back.error)
        XCTAssertEqual(link.channels, original, "le retour remet le Channel rack devant tout seul")

        // Arrêt au milieu d'une remontée de 2 places (plus aucune touche prise) : la disposition suit le pas fait.
        let (half, halfResult) = rack([.drums, .drums, .melody])
        let halfOriginal = half.channels
        var calls = 0
        let partial = OrganizerApplier(link: half, moveUp: { _ in
            calls += 1
            return calls == 1 ? half.moveSelectedUp(1) : 0
        }, wait: { _ in })
            .apply(plan(halfResult, options: rackOnly), result: halfResult, styles: FamilyStyles.initial)
        XCTAssertEqual(partial.error, .interrupted)
        XCTAssertEqual(partial.snapshot.rack?.arrangement, [0, 2, 1])
        XCTAssertNil(applier(half).undo(partial.snapshot).error)
        XCTAssertEqual(half.channels, halfOriginal)
        XCTAssertTrue(OrganizerError.interrupted.message.contains("Revenir comme avant"))
    }

    /// Touches perdues (FL sans fenêtre active) : l'ordre relu dans FL remplace l'ordre supposé, et « Revenir comme
    /// avant » remet chaque couleur sur son son au lieu de les mélanger.
    func testLostMovesAreReadBackForUndo() {
        let (link, result) = rack([.drums, .melody, .vocals])
        let original = link.channels
        let lost = OrganizerApplier(link: link, moveUp: { count in count })      // touches comptées, rien ne bouge
        let outcome = lost.apply(plan(result, options: rackOnly), result: result, styles: FamilyStyles.initial)
        XCTAssertEqual(outcome.error, .mismatch)
        XCTAssertEqual(outcome.snapshot.rack?.arrangement, [0, 1, 2])
        XCTAssertNil(applier(link).undo(outcome.snapshot).error)
        XCTAssertEqual(link.channels, original)
        XCTAssertEqual(OrganizerApplier.arrangement(names: ["b", "a"], original: ["a", "b"]), [1, 0])
        XCTAssertNil(OrganizerApplier.arrangement(names: ["a", "a"], original: ["a", "a"]), "noms répétés")
        XCTAssertNil(OrganizerApplier.arrangement(names: ["a", "c"], original: ["a", "b"]))
    }

    // MARK: Ce qu'est un groupe de sons, noms

    func testGroupVerdictAndNumbering() {
        let kick = Verdict(family: .drums, kind: .kick), clap = Verdict(family: .drums, kind: .clap)
        XCTAssertEqual(OrganizerPlan.groupVerdict([kick, kick]), kick)
        XCTAssertEqual(OrganizerPlan.groupVerdict([kick, clap]), Verdict(family: .drums), "plusieurs sortes : Drums")
        XCTAssertEqual(OrganizerPlan.groupVerdict([kick, Verdict(family: .drums)]), Verdict(family: .drums))
        XCTAssertEqual(OrganizerPlan.groupVerdict([Verdict(family: .unsure), Verdict(family: .bass, kind: .bass808)]),
                       Verdict(family: .bass, kind: .bass808), "« À vérifier » seulement s'il n'y a rien d'autre")
        XCTAssertEqual(OrganizerPlan.groupVerdict([Verdict(family: .bass), kick]), Verdict(family: .bass),
                       "égalité : l'ordre des familles")
        XCTAssertNil(OrganizerPlan.groupVerdict([]))
        XCTAssertNil(Verdict(family: .unsure).baseName)
        XCTAssertEqual(Verdict(family: .drums).baseName, "Drums")
        XCTAssertEqual(Verdict(family: .drums, kind: .openHat).baseName, "Open Hat")
        XCTAssertEqual(OrganizerPlan.numbered([(3, "Kick"), (1, "Snare"), (0, "Kick"), (2, "Kick")], taken: ["Kick 2"]),
                       [3: "Kick", 1: "Snare", 0: "Kick 3", 2: "Kick 4"])
    }

    // MARK: Patterns

    func testPatternsNamedByTheirNameOrWhatPlays() {
        let (_, rackResult) = rack([.drums, .bass, .melody, .bass], kinds: [0: .kick, 1: .bass808])
        var result = rackResult
        result.patterns = ["hi hat", "Pattern 2", "Pattern 3", "Intro", "Pattern 5", "Pattern 6", "Drums 1"]
            .enumerated().map { PatternInfo(index: $0.offset, color: gray, name: $0.element) }
        // Pattern 3 : un Kick et un 808 (égalité : l'ordre des familles) ; pattern 6 : deux basses différentes ;
        // « Drums 1 » (nom général) : ce qui y joue. Un pattern où ne joue qu'un son prend son nom du Channel rack
        // (retour de l'utilisateur : le même son ne doit pas s'appeler autrement ailleurs).
        result.patternSounds = [1: [0], 2: [0, 1], 3: [1, 3], 5: [1, 3], 6: [0]]
        let patterns = plan(result).patterns
        XCTAssertEqual(patterns.names, [0: "Hi-hat", 1: "Kick", 2: "808", 5: "Basse", 6: "Kick"],
                       "son nom d'abord ; sinon ce qui y joue ; « Intro » et le pattern vide gardent leur nom")
        XCTAssertEqual(patterns.colors[0], style(.drums))
        XCTAssertEqual(patterns.colors[3], style(.bass), "« Intro » coloré quand même")
        XCTAssertNil(patterns.colors[4])
        XCTAssertTrue(PatternInfo(index: 4, color: gray, name: " Pattern 5").hasDefaultName)
        XCTAssertFalse(PatternInfo(index: 4, color: gray, name: "Pattern 4").hasDefaultName)
    }

    // MARK: Mixer

    /// Le Mixer suit l'ordre du Channel rack ; les pistes reliées par un envoi restent côte à côte, la piste de groupe
    /// juste après celles qui lui envoient ; les pistes vides suivent.
    func testMixerFollowsTheRackAndKeepsSendsTogether() {
        var result = OrganizerResult(channels: [
            ChannelInfo(index: 0, type: 2, mixerTrack: 1, color: gray, name: "BEAM KICK"),
            ChannelInfo(index: 1, type: 2, mixerTrack: 2, color: gray, name: "Lead"),
            ChannelInfo(index: 2, type: 2, mixerTrack: 3, color: gray, name: "@MEH CLAP"),
            ChannelInfo(index: 3, type: 2, mixerTrack: 6, color: gray, name: "ZEBRA 808"),
            ChannelInfo(index: 4, type: 2, mixerTrack: 6, color: gray, name: "Sub Bass"),
        ], items: [])
        result = OrganizerResult(channels: result.channels, items: result.channels.compactMap { c in
            SoundNames.kind(of: c.name).map {
                OrganizerItem(index: c.index, name: c.name, family: $0.family, confidence: 0.9, testNotes: false,
                              mixerTrack: c.mixerTrack, color: gray, kind: $0, byName: true)
            }
        })
        result.mixer = (0...8).map { MixerTrackInfo(index: $0, color: gray, name: $0 == 0 ? "Master" : "Insert \($0)") }
        result.routes = [1: [5], 3: [5], 2: [], 6: []]
        let noBus = OrganizerOptions(buses: false)
        let mixer = plan(result, options: noBus).mixer
        // Lead (2), puis 808 et Sub (6), puis Kick (1), Clap (3) et leur piste de groupe (5) ; la piste 4 suit.
        XCTAssertEqual(mixer.final, [2, 6, 1, 3, 5, 4])
        XCTAssertEqual(mixer.names, [2: "Lead", 6: "Basse", 1: "Kick", 3: "Clap", 5: "Drums Bus"])
        XCTAssertEqual(mixer.verdicts[6], Verdict(family: .bass), "808 et Sub : la famille")
        XCTAssertEqual(mixer.colors[5], style(.drums))
        XCTAssertNil(mixer.colors[4])
        let moved = mixer.moves.reduce(Array(1...6)) { RegroupPlan.applying($1, to: $0) }
        XCTAssertEqual(moved, mixer.final)

        // Piste de groupe déjà nommée : gardée ; Mixer ou renommage désactivés : rien.
        result.mixer[5] = MixerTrackInfo(index: 5, color: gray, name: "Drum Bus perso")
        XCTAssertNil(plan(result, options: noBus).mixer.names[5])
        XCTAssertTrue(plan(result, options: OrganizerOptions(mixer: false)).mixer.isEmpty)
        XCTAssertTrue(plan(result, options: OrganizerOptions(rename: false, buses: false)).mixer.names.isEmpty)
    }

    /// Mixer rangé dans FL (⌥← sur chaque piste), les sons suivent leur piste ; « Revenir comme avant » remet tout.
    func testMixerAppliedThenUndone() {
        let link = FakeOrganizerLink()
        link.channels = [ChannelInfo(index: 0, type: 2, mixerTrack: 1, color: gray, name: "BEAM KICK"),
                         ChannelInfo(index: 1, type: 2, mixerTrack: 2, color: gray, name: "Vocal Chop")]
        link.mixer = (0...4).map { MixerTrackInfo(index: $0, color: gray, name: $0 == 0 ? "Master" : "Insert \($0)") }
        let result = OrganizerResult(channels: link.channels, items: [
            OrganizerItem(index: 0, name: "BEAM KICK", family: .drums, confidence: 0.9, testNotes: false, mixerTrack: 1,
                          color: gray, kind: .kick, byName: true),
            OrganizerItem(index: 1, name: "Vocal Chop", family: .vocals, confidence: 0.9, testNotes: false, mixerTrack: 2,
                          color: gray, kind: .vocal, byName: true),
        ], mixer: link.mixer)
        let originalMixer = link.mixer
        let outcome = apply(link, result, options: OrganizerOptions(rack: false, patterns: false, playlist: false,
                                                                     buses: false))
        XCTAssertNil(outcome.error)
        XCTAssertEqual(link.mixer.map(\.name), ["Master", "Voix", "Kick", "Insert 3", "Insert 4"])
        XCTAssertEqual(link.mixer[1].color, style(.vocals))
        XCTAssertEqual(link.channels.map(\.mixerTrack), [2, 1], "chaque son suit sa piste")
        XCTAssertTrue(link.log.contains("show mixer"))
        XCTAssertEqual(outcome.snapshot.mixer?.arrangement, [2, 1])

        XCTAssertNil(applier(link).undo(outcome.snapshot).error)
        XCTAssertEqual(link.mixer, originalMixer)
        XCTAssertEqual(link.channels.map(\.mixerTrack), [1, 2])
    }

    /// Un bus par famille, juste après ses pistes ; les 808 dans le bus Drums ; chaque son envoyé seulement à son
    /// bus, le bus au Master ; un bus déjà là est repris ; un son sans note n'est pas touché. « Revenir comme avant »
    /// remet aussi les envois.
    func testBusPerFamilyAppliedThenUndone() {
        let link = FakeOrganizerLink()
        let kinds: [SoundKind?] = [.lead, .lead, .bass, .bass808, .kick, .clap, nil]
        let tracks = [1, 2, 4, 5, 6, 7, 8]
        link.channels = kinds.indices.map {
            ChannelInfo(index: $0, type: 2, mixerTrack: tracks[$0], color: gray, name: "Son \($0)")
        }
        link.mixer = (0...12).map {
            MixerTrackInfo(index: $0, color: gray, name: $0 == 0 ? "Master" : $0 == 3 ? "Melody Bus" : "Insert \($0)")
        }
        link.routes = [1: [3], 2: [3], 3: [0], 4: [0], 5: [0], 6: [0], 7: [0], 8: [0]]
        let items = kinds.indices.compactMap { i -> OrganizerItem? in
            guard let kind = kinds[i] else { return nil }            // le canal 6 n'a aucune note
            return OrganizerItem(index: i, name: "Son \(i)", family: kind.family, confidence: 0.9, testNotes: false,
                                 mixerTrack: tracks[i], color: gray, kind: kind)
        }
        var result = OrganizerResult(channels: link.channels, items: items, mixer: link.mixer, routes: link.routes)
        result.unused = [6]
        let mixer = plan(result).mixer
        // Mélodies et leur bus (déjà là : la piste 3), Basse et son bus (piste libre 9), puis 808, Kick, Clap et le
        // bus Drums (piste libre 10) ; la piste du son sans note après.
        XCTAssertEqual(mixer.final, [1, 2, 3, 4, 9, 5, 6, 7, 10, 8])
        XCTAssertEqual(mixer.buses, [3: .melody, 9: .bass, 10: .drums])
        XCTAssertEqual(mixer.routes, [3: [0], 4: [9], 9: [0], 5: [10], 6: [10], 7: [10], 10: [0]],
                       "les mélodies envoient déjà à leur bus : rien n'y change")
        XCTAssertEqual(mixer.names, [1: "Lead", 2: "Lead 2", 4: "Basse", 9: "Basse Bus", 5: "808", 6: "Kick",
                                     7: "Clap", 10: "Drums Bus"], "« Melody Bus » garde son nom")
        XCTAssertEqual(mixer.colors[10], style(.drums))
        XCTAssertNil(mixer.colors[8], "son sans note : pas touché")

        let originalMixer = link.mixer, originalRoutes = link.routes
        let outcome = apply(link, result, options: OrganizerOptions(rack: false, patterns: false, playlist: false,
                                                                    deleteUnused: false))
        XCTAssertNil(outcome.error)
        XCTAssertEqual(link.mixer.map(\.name), ["Master", "Lead", "Lead 2", "Melody Bus", "Basse", "Basse Bus", "808",
                                                "Kick", "Clap", "Drums Bus", "Insert 8", "Insert 11", "Insert 12"])
        XCTAssertEqual(link.routes.filter { !$0.value.isEmpty },
                       [1: [3], 2: [3], 3: [0], 4: [5], 5: [0], 6: [9], 7: [9], 8: [9], 9: [0], 10: [0]],
                       "chaque son vers le bus de sa famille, à sa nouvelle place")
        XCTAssertEqual(link.channels.map(\.mixerTrack), [1, 2, 4, 6, 7, 8, 10], "chaque son suit sa piste")

        XCTAssertNil(applier(link).undo(outcome.snapshot).error)
        XCTAssertEqual(link.mixer, originalMixer)
        XCTAssertEqual(link.routes.filter { !$0.value.isEmpty }, originalRoutes)
        XCTAssertEqual(link.channels.map(\.mixerTrack), tracks)
    }

    /// Règle du propriétaire : un son déjà relié à une autre piste que le Master (ici un sidechain, en plus du Master)
    /// garde ses envois et va avec sa famille ; un son relié au seul Master va dans le bus de sa famille. Le sidechain
    /// n'est pas pris pour un bus.
    func testTracksAlreadySentElsewhereKeepTheirSends() {
        let kinds: [SoundKind] = [.lead, .lead, .kick, .snare]
        var result = OrganizerResult(channels: kinds.indices.map {
            ChannelInfo(index: $0, type: 2, mixerTrack: $0 + 1, color: gray, name: "Son \($0)")
        }, items: kinds.indices.map {
            OrganizerItem(index: $0, name: "Son \($0)", family: kinds[$0].family, confidence: 0.9, testNotes: false,
                          mixerTrack: $0 + 1, color: gray, kind: kinds[$0])
        })
        result.mixer = (0...10).map {
            MixerTrackInfo(index: $0, color: gray, name: $0 == 0 ? "Master" : $0 == 5 ? "Sidechain" : "Insert \($0)")
        }
        result.routes = [1: [0], 2: [0, 5], 3: [0], 4: [0], 5: [0]]
        let mixer = plan(result).mixer
        XCTAssertEqual(mixer.buses, [6: .melody, 7: .drums])
        XCTAssertEqual(mixer.routes, [1: [6], 6: [0], 3: [7], 4: [7], 7: [0]], "la piste 2 garde ses envois")
        XCTAssertEqual(mixer.final, [1, 2, 6, 3, 4, 7, 5], "la piste 2 reste avec les mélodies")

        // Toutes les pistes d'une famille envoient déjà ailleurs : pas de bus pris pour elle.
        result.routes = [1: [0, 5], 2: [0, 5], 3: [0], 4: [0], 5: [0]]
        let shared = plan(result).mixer
        XCTAssertEqual(shared.buses, [6: .drums])
        XCTAssertEqual(shared.routes, [3: [6], 4: [6], 6: [0]])
        XCTAssertEqual(shared.final, [1, 2, 3, 4, 6, 5])
    }

    /// Un projet comme celui de la vidéo de l'utilisateur : deux sons sans note (leurs pistes du Mixer en noir), une
    /// boucle de batterie envoyée au Master.
    private func cleanupProject() -> (link: FakeOrganizerLink, result: OrganizerResult) {
        let link = FakeOrganizerLink()
        let black = RGBColor(r: 0, g: 0, b: 0)
        link.channels = [ChannelInfo(index: 0, type: 2, mixerTrack: 1, color: gray, name: "Son 0"),
                         ChannelInfo(index: 1, type: 2, mixerTrack: 2, color: gray, name: "Serum 2"),
                         ChannelInfo(index: 2, type: 2, mixerTrack: 3, color: gray, name: "Son 2"),
                         ChannelInfo(index: 3, type: 0, mixerTrack: 4, color: gray, name: "KiCK - BREW"),
                         ChannelInfo(index: 4, type: ChannelInfo.audioClipType, mixerTrack: 0, color: gray, name: "Son 4")]
        link.mixer = (0...12).map { i in
            switch i {
            case 0: return MixerTrackInfo(index: 0, color: gray, name: "Master")
            case 2: return MixerTrackInfo(index: 2, color: black, name: "Serum 2")
            case 4: return MixerTrackInfo(index: 4, color: black, name: "KiCK - BREW")
            case 9: return MixerTrackInfo(index: 9, color: black, name: "Serum 2")      // aucun son, aucun envoi
            default: return MixerTrackInfo(index: i, color: gray, name: "Insert \(i)")
            }
        }
        link.routes = [1: [0], 3: [0]]
        let kinds: [Int: SoundKind] = [0: .kick, 2: .lead, 4: .drums]
        let items = kinds.keys.sorted().map { i in
            OrganizerItem(index: i, name: link.channels[i].name, family: kinds[i]!.family, confidence: 0.9,
                          testNotes: false, mixerTrack: link.channels[i].mixerTrack, color: gray, kind: kinds[i])
        }
        var result = OrganizerResult(channels: link.channels, items: items, mixer: link.mixer, routes: link.routes)
        result.unused = [1, 3]
        return (link, result)
    }

    /// Retour de l'utilisateur : les sons sans note disparaissent (« bass » et « kick » sans son compris), leurs pistes
    /// du Mixer redeviennent neuves, et la boucle de batterie envoyée au Master prend une piste. Le reste est fait sur
    /// le Channel rack tel qu'il est après la suppression.
    func testUnusedSoundsDeletedAndMasterSoundGetsATrack() {
        let (link, result) = cleanupProject()
        let preview = plan(result)
        XCTAssertEqual(preview.deleted, [1, 3])
        XCTAssertEqual(preview.mixer.links, [4: 5], "la première piste libre")
        XCTAssertEqual(preview.mixer.resets, [2, 4, 9], "aussi la piste nommée sans aucun son ni envoi")

        let outcome = applier(link).apply(preview, result: result, styles: FamilyStyles.initial)
        XCTAssertNil(outcome.error)
        XCTAssertEqual(outcome.deleted, 2)
        XCTAssertEqual(Array(link.log.prefix(3)), ["list", "select 1,3", "show channelRack"])
        XCTAssertTrue(link.log.contains("delete"))
        XCTAssertTrue(link.log.contains("link 2 5"), "après la suppression, la boucle est le canal 2")
        XCTAssertEqual(link.channels.map(\.name), ["Lead", "Kick", "Drums"])
        XCTAssertEqual(link.channels.map(\.mixerTrack), [1, 3, 4])
        XCTAssertEqual(Array(link.mixer.map(\.name).prefix(8)),
                       ["Master", "Lead", "Mélodie Bus", "Kick", "Drums", "Drums Bus", "", ""],
                       "les pistes des sons supprimés : nom de FL")
        XCTAssertEqual(link.mixer[6].color, gray, "couleur des pistes jamais touchées")
        XCTAssertEqual(link.mixer[7].color, gray)
        XCTAssertTrue(link.mixer[6].hasDefaultName)
        XCTAssertEqual([link.mixer[9].name, link.mixer[9].color.hex], ["", gray.hex])

        // « Revenir comme avant » : tout sauf les sons supprimés.
        XCTAssertNil(applier(link).undo(outcome.snapshot).error)
        XCTAssertEqual(link.channels.map(\.name), ["Son 0", "Son 2", "Son 4"])
        XCTAssertEqual(link.channels.map(\.mixerTrack), [1, 3, 0])
        XCTAssertEqual(Array(link.mixer.map(\.name).prefix(5)), ["Master", "Insert 1", "Serum 2", "Insert 3", "KiCK - BREW"])
        XCTAssertEqual(link.mixer[2].color, RGBColor(r: 0, g: 0, b: 0))
        XCTAssertEqual(link.mixer[9].name, "Serum 2")
    }

    /// FL ne supprime rien (raccourci sans effet) : les sons restent sélectionnés, le reste est fait sans les toucher.
    func testDeletionRefusedKeepsTheRest() {
        let (link, result) = cleanupProject()
        let refusing = OrganizerApplier(link: link, moveUp: link.moveSelectedUp, moveLeft: link.moveSelectedLeft,
                                        deleteSelected: { false })
        let outcome = refusing.apply(plan(result), result: result, styles: FamilyStyles.initial)
        XCTAssertNil(outcome.error)
        XCTAssertEqual([outcome.deleted, outcome.notDeleted], [0, 2])
        XCTAssertEqual(link.channels.map(\.name), ["Lead", "Kick", "Drums", "Serum 2", "KiCK - BREW"])
        XCTAssertEqual(link.unusedSelection, [3, 4], "toujours sélectionnés, à leur nouvelle place")
        XCTAssertTrue(link.mixer.contains { $0.name == "Serum 2" }, "leurs pistes ne sont pas touchées")
    }

    /// Le projet après la suppression : les canaux suivants remontent ; les pistes du Mixer que seuls eux utilisaient
    /// sont libérées.
    func testRemovingChannels() {
        let (_, result) = cleanupProject()
        var full = result
        full.patternSounds = [0: [0, 1], 1: [3]]
        full.trackSounds = [2: [2, 3, 4]]
        let (after, map) = full.removing([1, 3])
        XCTAssertEqual(map, [0: 0, 2: 1, 4: 2])
        XCTAssertEqual(after.channels.map(\.index), [0, 1, 2])
        XCTAssertEqual(after.channels.map(\.name), ["Son 0", "Son 2", "Son 4"])
        XCTAssertEqual(after.items.map(\.index), [0, 1, 2])
        XCTAssertEqual(after.patternSounds, [0: [0]])
        XCTAssertEqual(after.trackSounds, [2: [1, 2]])
        XCTAssertEqual(after.unused, [])
        XCTAssertEqual(after.freed, [2, 4])
    }

    /// Un nom de partie du morceau est gardé ; tout autre nom est remplacé par un nom simple.
    func testSectionNamesAreKept() {
        XCTAssertTrue(SoundNames.isSection("Intro"))
        XCTAssertTrue(SoundNames.isSection("Refrain 2"))
        XCTAssertTrue(SoundNames.isSection("HOOK"))
        XCTAssertFalse(SoundNames.isSection("Kick Intro"), "dit ce qu'est le son")
        XCTAssertFalse(SoundNames.isSection("Serum 2 #3"))
        XCTAssertFalse(SoundNames.isSection("Pattern 3"))
        XCTAssertFalse(SoundNames.isSection("Track 8"))
    }

    /// Ordre du Channel rack dans la basse : Basse, puis 808, juste avant les drums.
    func testBassBefore808() {
        let (link, result) = rack([.drums, .bass, .bass, .melody], kinds: [0: .kick, 1: .bass808, 2: .bass])
        XCTAssertNil(apply(link, result).error)
        XCTAssertEqual(link.channels.map(\.name), ["Son 3", "Son 2", "Son 1", "Son 0"])
        XCTAssertEqual(SoundKind.bass808.busFamily, .drums)
        XCTAssertEqual(SoundKind.bass.busFamily, .bass)
    }

    // MARK: Playlist

    /// Une Playlist simulée : la piste 0 renommée par l'utilisateur, les autres au nom de FL ; `sounds[i]` : les sons
    /// du Channel rack qui jouent sur la piste i.
    private func playlistResult(_ channels: [(SoundFamily, SoundKind?)], sounds: [Int: Set<Int>], tracks: Int)
        -> (link: FakeOrganizerLink, result: OrganizerResult) {
        let link = FakeOrganizerLink()
        link.channels = channels.indices.map {
            ChannelInfo(index: $0, type: 2, mixerTrack: 0, color: gray, name: "Son \($0)")
        }
        link.playlist = (0..<tracks).map {
            PlaylistTrackInfo(index: $0, selected: false, color: gray, name: $0 == 0 ? "Lead" : "Track \($0 + 1)")
        }
        let items = channels.enumerated().map {
            OrganizerItem(index: $0.offset, name: "Son \($0.offset)", family: $0.element.0, confidence: 0.9,
                          testNotes: false, mixerTrack: 0, color: gray, kind: $0.element.1)
        }
        return (link, OrganizerResult(channels: link.channels, items: items, playlist: link.playlist, trackSounds: sounds))
    }

    func testPlaylistNames() {
        let (_, result) = playlistResult([(.melody, .lead), (.drums, .kick), (.drums, .openHat), (.vocals, nil),
                                          (.unsure, nil)],
                                         sounds: [0: [0], 1: [1], 2: [1], 3: [2], 4: [4], 6: [3], 7: [1, 2]], tracks: 8)
        let names = plan(result).playlist.names
        // La piste 0 garde son nom (renommée par l'utilisateur) ; « À vérifier » et la piste muette aussi. Une piste
        // où ne joue qu'un son prend son nom du Channel rack, même si une autre piste le joue aussi.
        XCTAssertEqual(names, [1: "Kick", 2: "Kick", 3: "Open Hat", 6: "Voix", 7: "Drums"])
        XCTAssertEqual(SoundFamily.order.compactMap(\.trackName), ["Voix", "Mélodie", "Basse", "Drums", "FX"])
        // Un nom qui dit déjà ce qu'est la piste (« Drums 2 », « kick ») est remis au propre.
        var renamed = result
        renamed.playlist[0] = PlaylistTrackInfo(index: 0, selected: false, color: gray, name: "drums 2")
        XCTAssertEqual(plan(renamed).playlist.names[0], "Lead")
    }

    func testPlaylistColorsNamesAndUndo() {
        let (link, result) = playlistResult([(.melody, nil), (.drums, .snare), (.bass, nil)],
                                            sounds: [0: [0], 1: [1], 2: [2]], tracks: 4)
        let original = link.playlist
        let outcome = apply(link, result, options: OrganizerOptions(rack: false, patterns: false, mixer: false))
        XCTAssertNil(outcome.error)
        XCTAssertFalse(outcome.playlistUnordered)
        XCTAssertEqual(link.log, ["colors playlist 3", "names playlist 2", "playlist", "show playlist"])
        // Rangée comme le Channel rack (retour de l'utilisateur) : Mélodie, Basse, Drums, puis la piste vide.
        XCTAssertEqual(link.playlist.map(\.name), ["Lead", "Basse", "Snare", "Track 4"])
        XCTAssertEqual(link.playlist.map(\.color), [style(.melody), style(.bass), style(.drums), gray])
        XCTAssertEqual(outcome.snapshot.playlist?.names, [1: "Track 2", 2: "Track 3"])
        XCTAssertEqual(outcome.snapshot.playlist?.arrangement, [0, 2, 1, 3])

        let back = applier(link).undo(outcome.snapshot)
        XCTAssertNil(back.error)
        XCTAssertEqual(link.playlist, original)

        // Une couleur que FL n'a pas prise est signalée.
        let (other, otherResult) = playlistResult([(.melody, nil), (.drums, nil)], sounds: [0: [0], 1: [1]], tracks: 2)
        other.ignoredKind = .playlist
        other.ignoredColors = [1]
        let missed = apply(other, otherResult, options: OrganizerOptions(rack: false, patterns: false, mixer: false))
        XCTAssertEqual(missed.error, .mismatch)
    }

    // MARK: Un son par piste

    /// Retour de l'utilisateur (vidéo) : « deux sons différents ne doivent pas être sur la même ligne ». Piste 1 :
    /// la mélodie (pattern 1) et un FX (pattern 2) ; piste 0 : le kick (pattern 3).
    private func mixedPlaylist() -> (link: FakeOrganizerLink, result: OrganizerResult) {
        let made = playlistResult([(.melody, nil), (.fx, nil), (.drums, .kick)], sounds: [0: [2], 1: [0, 1]], tracks: 3)
        let link = made.link
        var result = made.result
        link.playlist[0] = PlaylistTrackInfo(index: 0, selected: false, color: gray, name: "Track 1")
        result.playlist[0] = link.playlist[0]
        link.patternSounds = [1: [0], 2: [1], 3: [2]]
        link.clipTracks = [1: 1, 2: 1, 3: 0]
        result.patternSounds = [0: [0], 1: [1], 2: [2]]
        result.soundAt = [0: 0.25, 1: 0.5, 2: 0.1]
        result.playlist = Array(result.playlist.prefix(2))          // lue jusqu'à la dernière piste qui joue
        return (link, result)
    }

    private func clipApplier(_ link: FakeOrganizerLink) -> OrganizerApplier {
        OrganizerApplier(link: link, moveUp: link.moveSelectedUp, moveTrack: link.moveTrackUp,
                         moveClips: link.moveClips, wait: { _ in }, listen: 0)
    }

    func testSplitsOnlySafePatterns() {
        let (_, result) = mixedPlaylist()
        let key: (Set<Int>) -> (Int, Int, Int) = { sounds in (sounds.contains(1) ? 4 : 1, 0, sounds.min() ?? 0) }
        let splits = OrganizerPlan.playlistSplits(result, key: key)
        // La mélodie (avant le FX dans l'ordre des familles) reste ; le FX va sur la première piste vide.
        XCTAssertEqual(splits, [PlaylistSplit(pattern: 1, from: 1, to: 2, sound: 1, at: 0.5, kept: 0, keptAt: 0.25)])
        XCTAssertEqual(result.splitting(splits).trackSounds, [0: [2], 1: [0], 2: [1]])
        XCTAssertEqual(result.splitting(splits).playlist.map(\.index), [0, 1, 2])
        // Pas sûr : un son aussi sur une autre piste, un son joué par deux patterns, une position inconnue.
        var elsewhere = result
        elsewhere.trackSounds[0] = [1, 2]
        XCTAssertTrue(OrganizerPlan.playlistSplits(elsewhere, key: key).isEmpty)
        var shared = result
        shared.patternSounds[2] = [2, 1]
        XCTAssertTrue(OrganizerPlan.playlistSplits(shared, key: key).isEmpty)
        var unheard = result
        unheard.soundAt[1] = nil
        XCTAssertTrue(OrganizerPlan.playlistSplits(unheard, key: key).isEmpty)
    }

    func testOneSoundPerTrackAndUndo() {
        let (link, result) = mixedPlaylist()
        let options = OrganizerOptions(rack: false, patterns: false, mixer: false)
        let planned = plan(result, options: options)
        XCTAssertEqual(planned.splits.map(\.pattern), [1])
        let outcome = clipApplier(link).apply(planned, result: result, styles: FamilyStyles.initial)
        XCTAssertNil(outcome.error)
        XCTAssertEqual(outcome.split, 1)
        XCTAssertFalse(outcome.playlistMixed)
        XCTAssertEqual(link.clipTracks, [1: 1, 2: 2, 3: 0], "le FX a sa piste")
        // Vérifié à l'écoute, piste seule : le FX sur la nouvelle piste, la mélodie encore sur l'ancienne.
        XCTAssertTrue(link.log.contains("pick 2"))
        XCTAssertEqual(link.log.filter { $0.hasPrefix("track ") }, ["track 2", "track 1"])
        // Puis la Playlist rangée comme le Channel rack : Mélodie, Drums, FX.
        XCTAssertEqual(link.playlist.map(\.name), ["Mélodie", "Kick", "FX"])
        XCTAssertEqual(outcome.snapshot.splits?.count, 1)

        let back = clipApplier(link).undo(outcome.snapshot)
        XCTAssertNil(back.error)
        XCTAssertEqual(link.clipTracks, [1: 1, 2: 1, 3: 0], "le FX revenu sur sa piste d'avant")
        XCTAssertEqual(link.playlist.map(\.name), ["Track 1", "Track 2", "Track 3"])
        XCTAssertNil(back.snapshot.splits)
    }

    /// FL n'a rien sélectionné (⇧C sans effet) : tous les clips sont descendus ; vu à l'écoute (la mélodie n'est plus
    /// sur sa piste), ils remontent tous, et la Playlist est rangée sans séparer cette piste.
    func testNothingSelectedPutsEverythingBack() {
        let (link, result) = mixedPlaylist()
        link.selectBySource = false
        let options = OrganizerOptions(rack: false, patterns: false, mixer: false)
        let outcome = clipApplier(link).apply(plan(result, options: options), result: result, styles: FamilyStyles.initial)
        XCTAssertNil(outcome.error)
        XCTAssertEqual(outcome.split, 0)
        XCTAssertTrue(outcome.playlistMixed)
        XCTAssertEqual(link.clipTracks, [1: 1, 2: 1, 3: 0], "tout remis à sa place")
        XCTAssertNil(outcome.snapshot.splits)
        XCTAssertEqual(link.playlist.prefix(2).map(\.name), ["Mélodie", "Kick"], "rangée quand même")
    }

    /// Fenêtre de FL lue : chaque clip déplacé seul vers la piste de son son (vérifié), au lieu des patterns
    /// descendus en entier ; « Revenir comme avant » les remet.
    func testClipsReunitedFromFLWindowAndUndo() {
        let (link, result) = mixedPlaylist()
        var clips = [ClipSpot(pattern: 2, track: 0, x: 100, point: .zero),
                     ClipSpot(pattern: 0, track: 1, x: 100, point: .zero),
                     ClipSpot(pattern: 1, track: 1, x: 300, point: .zero)]
        var moved: [ClipMove] = []
        let applier = OrganizerApplier(link: link, moveUp: link.moveSelectedUp, moveTrack: link.moveTrackUp,
                                       moveClips: link.moveClips,
                                       readClips: { PlaylistView(clips: clips, visible: Array(0..<6)) },
                                       moveClip: { move in
                                           moved.append(move)
                                           clips = ClipLayout.applying([move], to: clips)
                                           return .done
                                       }, wait: { _ in }, listen: 0)
        let options = OrganizerOptions(rack: false, patterns: false, mixer: false)
        let outcome = applier.apply(plan(result, options: options), result: result, styles: FamilyStyles.initial)
        XCTAssertNil(outcome.error)
        XCTAssertEqual(moved, [ClipMove(pattern: 1, from: 1, to: 2, x: 300)], "le FX sur une piste vide, à lui")
        XCTAssertEqual(outcome.reunited, 1)
        XCTAssertEqual(outcome.split, 0)
        XCTAssertFalse(link.log.contains("pick 2"), "plus de pattern descendu en entier")
        XCTAssertEqual(link.playlist.map(\.name), ["Mélodie", "Kick", "FX"])
        XCTAssertEqual(outcome.snapshot.clipMoves, moved)

        let back = applier.undo(outcome.snapshot)
        XCTAssertNil(back.error)
        XCTAssertEqual(moved.last, ClipMove(pattern: 1, from: 2, to: 1, x: 300), "remis sur sa piste d'avant")
        XCTAssertNil(back.snapshot.clipMoves)
        XCTAssertEqual(link.playlist.map(\.name), ["Track 1", "Track 2", "Track 3"])
    }

    /// Un clip que FL n'a pas laissé déplacer : il reste à sa place (dit à la fin), la Playlist est rangée avec ce
    /// qui a été fait.
    func testClipNotMovedStopsThere() {
        let (link, result) = mixedPlaylist()
        let clips = [ClipSpot(pattern: 0, track: 1, x: 100, point: .zero), ClipSpot(pattern: 1, track: 1, x: 300, point: .zero)]
        let applier = OrganizerApplier(link: link, moveUp: link.moveSelectedUp, moveTrack: link.moveTrackUp,
                                       readClips: { PlaylistView(clips: clips, visible: Array(0..<6)) },
                                       moveClip: { _ in .notDone }, wait: { _ in }, listen: 0)
        let options = OrganizerOptions(rack: false, patterns: false, mixer: false)
        let outcome = applier.apply(plan(result, options: options), result: result, styles: FamilyStyles.initial)
        XCTAssertNil(outcome.error)
        XCTAssertEqual(outcome.reunited, 0)
        XCTAssertEqual(outcome.clipsLeft, 1)
        XCTAssertNil(outcome.snapshot.clipMoves)
    }

    // MARK: Sur le fichier du projet

    /// Le projet de test en petit, analysé sur son fichier : sons, patterns, Playlist (FLPSample) ; Kick, mélodie,
    /// Snare et 808 classés, « Pad » sans note.
    private func fileProject(_ disk: FakeDisk) throws -> (link: FakeOrganizerLink, result: OrganizerResult) {
        let link = FakeOrganizerLink()
        let names = ["Pad", "Kick", "ZENOLOGY", "Snare", "808"]
        link.channels = names.enumerated().map {
            ChannelInfo(index: $0.offset, type: 2, mixerTrack: 0, color: gray, name: $0.element)
        }
        link.patternList = ["Mélodie", "Drums", "Pattern 3", "Vide"].enumerated().map {
            PatternInfo(index: $0.offset, color: gray, name: $0.element)
        }
        link.playlist = (0..<12).map { PlaylistTrackInfo(index: $0, selected: false, color: gray, name: "Track \($0 + 1)") }
        disk.link = link
        let verdicts: [(Int, SoundFamily, SoundKind?)] = [(1, .drums, .kick), (2, .melody, nil), (3, .drums, .snare),
                                                          (4, .bass, .bass808)]
        let items = verdicts.map {
            OrganizerItem(index: $0.0, name: names[$0.0], family: $0.1, confidence: 0.9, testNotes: false, mixerTrack: 0,
                          color: gray, kind: $0.2)
        }
        let file = try XCTUnwrap(disk.files[disk.original])
        let split = try ProjectFile.splitting(try FLPProject(file), file)        // comme l'analyse
        var result = OrganizerResult(channels: link.channels, items: items,
                                     patterns: ProjectFile.patterns(link.patternList, adding: split.project),
                                     patternSounds: ProjectFile.sounds(split.project, notSounds: []).patterns, unused: [0])
        result.project = ProjectFile.snapshot(split.project, url: disk.original, notSounds: [],
                                              splitPatterns: split.added)
        return (link, result)
    }

    private let fileOptions = OrganizerOptions(rack: false, mixer: false, deleteUnused: false)

    /// Retour du propriétaire (vidéo du 21/10) : « quelque chose de solide ». FL enregistre le projet, la copie rangée
    /// est écrite à côté (chaque pattern seul sur sa piste avec toutes ses répétitions, rien d'autre ne change) et FL
    /// l'ouvre ; le reste se fait dans la copie, que FL enregistre ; « Revenir comme avant » rouvre l'original, qui
    /// n'a pas bougé.
    func testPlaylistOrganizedInACopyOfTheProject() throws {
        let disk = FakeDisk()
        let (link, result) = try fileProject(disk)
        let applier = OrganizerApplier(link: link, moveUp: link.moveSelectedUp, wait: { _ in }, listen: 0,
                                       files: disk.access, marker: "FL Shortcuts 1234")
        let plan = self.plan(result, options: fileOptions)
        let layout = try XCTUnwrap(plan.layout)
        XCTAssertTrue(plan.splits.isEmpty)
        XCTAssertTrue(plan.playlist.moves.isEmpty, "les pistes sont déjà dans l'ordre des familles")
        // Le pattern 2 (Snare et 808) séparé son par son : la 808 a son pattern 5. Clips dans l'ordre de leur début :
        // 0 mélodie, 1 Snare, 2 808, 3 pattern vide, 4 mélodie, 5 Snare, 6 808, 7 clip du Kick.
        XCTAssertEqual(layout.count, 5)
        XCTAssertEqual(layout.tracks, [0: 0, 4: 0, 2: 1, 6: 1, 7: 2, 1: 3, 5: 3, 3: 4],
                       "Mélodies, Basse, Kick, Snare, puis le pattern vide en bas")

        let outcome = applier.apply(plan, result: result, styles: FamilyStyles.initial)
        XCTAssertNil(outcome.error)
        let copyURL = URL(fileURLWithPath: "/projets/Mon son_2.flp")
        XCTAssertEqual(outcome.copy, copyURL)
        XCTAssertEqual(disk.opened, [copyURL])
        XCTAssertEqual(disk.saved, [disk.original, copyURL], "le projet enregistré avant, la copie rangée à la fin")
        XCTAssertEqual(disk.files[disk.original], FLPSample.sample(), "l'original n'a pas bougé")
        let sample = FLPSample.sample()
        let before = try ProjectFile.splitting(try FLPProject(sample), sample).project
        let copy = try FLPProject(XCTUnwrap(disk.files[copyURL]))
        XCTAssertEqual(copy.notes[5], [4: 1], "la 808 dans son pattern")
        XCTAssertEqual(copy.clips.map(\.track), before.clips.map { layout.tracks[$0.item]! })
        XCTAssertEqual(copy.clips.map(\.source), before.clips.map(\.source))
        XCTAssertEqual(copy.clips.map(\.position), before.clips.map(\.position))
        XCTAssertFalse(link.patternList.contains { $0.name.hasPrefix("FL Shortcuts") }, "la marque de la copie remise")
        XCTAssertEqual(outcome.snapshot.original, disk.original)

        let back = applier.undo(outcome.snapshot)
        XCTAssertNil(back.error)
        XCTAssertEqual(disk.opened.last, disk.original, "l'original rouvert dans FL")
        XCTAssertTrue(back.snapshot.isEmpty)
    }

    /// Projets de voix enregistrées (retour du propriétaire : « tout sur la même ligne, surtout quand c'est du rec […]
    /// si deux sont en même temps il met l'une en dessous de l'autre ») : les clips d'une même sorte de voix sur une
    /// seule piste, ceux qui se chevauchent juste dessous, les backs sur leur ligne à eux, avant (ordre des sortes) ;
    /// les enregistrements de guitare aussi, sur leur ligne, après les voix.
    func testRecordingsShareOneLinePerKind() throws {
        let clips = [FLPSample.ClipSpec(channel: 0, track: 0, bar: 1), FLPSample.ClipSpec(channel: 1, track: 3, bar: 9),
                     FLPSample.ClipSpec(channel: 0, track: 6, bar: 3), FLPSample.ClipSpec(channel: 3, track: 2, bar: 1),
                     FLPSample.ClipSpec(channel: 2, track: 7, bar: 1), FLPSample.ClipSpec(channel: 4, track: 9, bar: 9)]
        let project = try FLPProject(FLPSample.sample(clips: clips))
        let names = ["Pad", "Kick", "untitled_2026-10-15 23-37-42_Insert 5", "Snare", "untitled_2026-10-15 23-50-12_Insert 5"]
        let channels = names.enumerated().map {
            ChannelInfo(index: $0.offset, type: ChannelInfo.audioClipType, mixerTrack: 0, color: gray, name: $0.element)
        }
        let kinds: [Int: SoundKind] = [0: .vocal, 1: .vocal, 2: .guitar, 3: .backing, 4: .guitar]
        let items = kinds.keys.sorted().map {
            OrganizerItem(index: $0, name: names[$0], family: kinds[$0]!.family, confidence: 0.9, testNotes: false,
                          mixerTrack: 0, color: gray, kind: kinds[$0])
        }
        var result = OrganizerResult(channels: channels, items: items, patterns: [],
                                     patternSounds: ProjectFile.sounds(project, notSounds: []).patterns, unused: [])
        result.project = ProjectFile.snapshot(project, url: URL(fileURLWithPath: "/projets/Voix.flp"), notSounds: [])
        let layout = try XCTUnwrap(plan(result, options: OrganizerOptions(rack: false, patterns: false, mixer: false)).layout)
        XCTAssertEqual(layout.tracks, [3: 0, 0: 1, 1: 1, 2: 2, 4: 3, 5: 3], "le 2e clip du son 0 chevauche le 1er : dessous")
        XCTAssertEqual(layout.count, 4)
        XCTAssertEqual(layout.sounds, [0: [3], 1: [0, 1], 2: [0, 1], 3: [2, 4]])
    }

    /// Le projet a changé depuis l'analyse, ou FL n'ouvre pas la copie : rien n'est touché dans FL, et dans le second
    /// cas « Revenir comme avant » rouvre l'original.
    func testCopyRefusedWhenTheProjectChangedOrDoesNotOpen() throws {
        let disk = FakeDisk()
        let (link, result) = try fileProject(disk)
        let plan = self.plan(result, options: fileOptions)
        disk.files[disk.original] = FLPSample.sample(clips: [FLPSample.ClipSpec(pattern: 1, track: 0, bar: 1)])
        let changed = OrganizerApplier(link: link, moveUp: link.moveSelectedUp, wait: { _ in }, listen: 0,
                                       files: disk.access).apply(plan, result: result, styles: FamilyStyles.initial)
        XCTAssertEqual(changed.error, .failed(String(localized: "Ton projet a changé depuis l'analyse : rien n'a été touché. Ferme l'Organiser, puis relance-le.")))
        XCTAssertNil(changed.copy)
        XCTAssertTrue(changed.snapshot.isEmpty)
        XCTAssertTrue(disk.opened.isEmpty)
        XCTAssertEqual(disk.files.count, 1, "aucune copie écrite")
        XCTAssertFalse(link.log.contains { $0.hasPrefix("colors") || $0.hasPrefix("names") }, "rien de touché dans FL")

        disk.files[disk.original] = FLPSample.sample()
        disk.loads = false
        let stuck = OrganizerApplier(link: link, moveUp: link.moveSelectedUp, wait: { _ in }, listen: 0,
                                     files: disk.access).apply(plan, result: result, styles: FamilyStyles.initial)
        XCTAssertEqual(stuck.error, .failed(String(localized: "FL n'a pas ouvert la copie rangée à temps : elle est à côté de ton projet, ouvre-la dans FL, puis relance l'Organiser. Ton projet n'a pas bougé.")))
        XCTAssertEqual(stuck.snapshot.original, disk.original, "« Revenir comme avant » le rouvre")
        XCTAssertFalse(link.log.contains { $0.hasPrefix("colors") || $0.hasPrefix("names") }, "rien de touché dans FL")
    }
}

/// Disque et FL simulés pour l'Organiser sur le fichier : le projet (« /projets/Mon son.flp »), la copie rangée,
/// FL qui enregistre et qui ouvre un fichier (le Channel rack et les noms de ses patterns deviennent les siens).
final class FakeDisk {
    let original = URL(fileURLWithPath: "/projets/Mon son.flp")
    var files: [URL: FLPFile]
    var opened: [URL] = []
    var saved: [URL] = []
    /// Faux : FL ne charge jamais le fichier demandé.
    var loads = true
    weak var link: FakeOrganizerLink?

    init() { files = [original: FLPSample.sample()] }

    var access: ProjectFileAccess {
        ProjectFileAccess(save: { known in
            let url = known ?? self.original
            self.saved.append(url)
            return .success(url)
        }, open: { url in
            self.opened.append(url)
            guard self.loads, let link = self.link, let file = self.files[url], let project = try? FLPProject(file)
            else { return true }
            for (n, name) in project.patternNames where n - 1 < link.patternList.count {
                link.patternList[n - 1] = PatternInfo(index: n - 1, color: link.patternList[n - 1].color, name: name)
            }
            // Les patterns ajoutés par la séparation, comme FL les montre.
            let last = (project.notes.keys.max() ?? 0)
            while link.patternList.count < last {
                let n = link.patternList.count + 1
                link.patternList.append(PatternInfo(index: n - 1, color: RGBColor(r: 0x48, g: 0x50, b: 0x58),
                                                    name: "Pattern \(n)"))
            }
            return true
        }, read: { url in
            guard let file = self.files[url] else { throw FLPError.damaged }
            return file
        }, write: { file, url in
            guard self.files[url] == nil else { throw FLPError.damaged }
            self.files[url] = file
        }, exists: { self.files[$0] != nil })
    }
}
