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
        OrganizerApplier(link: link, moveUp: link.moveSelectedUp, moveLeft: link.moveSelectedLeft, placeIcon: placeIcon)
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

    func testStopsWhenPageChanges() {
        // La Playlist passe devant après le premier déplacement (deux sont prévus).
        let (link, result) = rack([.drums, .melody, .vocals])
        let original = link.channels
        let leaving = OrganizerApplier(link: link, moveUp: { count in
            let done = link.moveSelectedUp(count)
            link.window = .playlist
            return done
        })
        let outcome = leaving.apply(plan(result, options: rackOnly), result: result, styles: FamilyStyles.initial)
        XCTAssertEqual(outcome.error, .interrupted)
        XCTAssertEqual(outcome.snapshot.rack?.arrangement, [2, 0, 1])
        XCTAssertEqual(link.channels.map(\.name), ["Son 2", "Son 0", "Son 1"])
        let back = applier(link).undo(outcome.snapshot)
        XCTAssertNil(back.error)
        XCTAssertEqual(link.channels, original, "le retour remet le Channel rack devant tout seul")

        // Arrêt au milieu d'une remontée de 2 places : la disposition suit le pas fait.
        let (half, halfResult) = rack([.drums, .drums, .melody])
        let halfOriginal = half.channels
        let partial = OrganizerApplier(link: half, moveUp: { _ in half.moveSelectedUp(1) })
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
        // « Drums 1 » (nom général) : ce qui y joue.
        result.patternSounds = [1: [0], 2: [0, 1], 3: [1, 3], 5: [1, 3], 6: [0]]
        let patterns = plan(result).patterns
        XCTAssertEqual(patterns.names, [0: "Hi-hat", 1: "Kick", 2: "808", 5: "Basse", 6: "Kick 2"],
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
        let mixer = plan(result).mixer
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
        XCTAssertNil(plan(result).mixer.names[5])
        XCTAssertTrue(plan(result, options: OrganizerOptions(mixer: false)).mixer.isEmpty)
        XCTAssertTrue(plan(result, options: OrganizerOptions(rename: false)).mixer.names.isEmpty)
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
        let outcome = apply(link, result, options: OrganizerOptions(rack: false, patterns: false, playlist: false))
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
        // La piste 0 garde son nom (renommée par l'utilisateur) ; « À vérifier » et la piste muette aussi.
        XCTAssertEqual(names, [1: "Kick", 2: "Kick 2", 3: "Open Hat", 6: "Voix", 7: "Drums"])
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
        XCTAssertEqual(link.log, ["colors playlist 3", "names playlist 2", "playlist"])
        XCTAssertEqual(link.playlist.map(\.name), ["Lead", "Snare", "Basse", "Track 4"])
        XCTAssertEqual(link.playlist.map(\.color), [style(.melody), style(.drums), style(.bass), gray])
        XCTAssertEqual(outcome.snapshot.playlist?.names, [1: "Track 2", 2: "Track 3"])

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
}
