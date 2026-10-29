// Demande du propriétaire (25/10) : la place de chaque son dans le Mixer (la case de FL dans le Channel rack), le départ
// de chaque famille (« Drums de 27 à 32, la 808 comprise »), « Rangement automatique », l'ordre des familles glissées
// comme des dossiers, et « Écrire… » pour nommer un son soi-même. Mêmes essais que
// windows/FLShortcut.Core.Tests/OrganizerPlacesTests.cs.
import XCTest
@testable import FLShortcut

final class OrganizerPlacesTests: XCTestCase {
    private let gray = RGBColor(r: 9, g: 9, b: 9)

    /// Lead (piste 1), Kick (2), Snare (3), 808 (4) ; un bus par famille pris sur les pistes libres (5, 6…).
    private func project() -> OrganizerResult {
        let kinds: [SoundKind] = [.lead, .kick, .snare, .bass808]
        let channels = kinds.indices.map { ChannelInfo(index: $0, type: 2, mixerTrack: $0 + 1, color: gray, name: "Son \($0)") }
        let items = kinds.enumerated().map {
            OrganizerItem(index: $0.offset, name: "Son \($0.offset)", family: $0.element.family, confidence: 0.9,
                          testNotes: false, mixerTrack: $0.offset + 1, color: gray, kind: $0.element)
        }
        let mixer = (0..<42).map { MixerTrackInfo(index: $0, color: gray, name: $0 == 0 ? "Master" : "Insert \($0)") }
        return OrganizerResult(channels: channels, items: items, mixer: mixer)
    }

    private func plan(_ result: OrganizerResult, styles: [SoundFamily: FamilyStyle] = FamilyStyles.initial,
                      options: OrganizerOptions = OrganizerOptions(), names: [Int: String] = [:],
                      slots: [Int: Int] = [:]) -> OrganizerPlan {
        OrganizerPlan.make(result, families: OrganizerApplier.families(of: result), kinds: OrganizerApplier.kinds(of: result),
                           styles: styles, options: options, names: names, slots: slots)
    }

    private func slot(_ plan: OrganizerPlan, _ track: Int) -> Int { (plan.mixer.final.firstIndex(of: track) ?? -1) + 1 }

    func testPinnedLayout() {
        XCTAssertEqual(OrganizerPlan.pinned(auto: [1, 2, 4, 9, 5, 6, 7, 10, 8], pins: [], last: 20),
                       [1, 2, 4, 9, 5, 6, 7, 10, 8, 3], "sans place choisie : comme avant")
        XCTAssertEqual(OrganizerPlan.pinned(auto: [1, 2, 3, 4, 5], pins: [(5, 3)], last: 20), [1, 2, 5, 3, 4])
        XCTAssertEqual(OrganizerPlan.pinned(auto: [1, 2, 3, 4, 5], pins: [(5, 3), (4, 3)], last: 20), [1, 2, 5, 4, 3],
                       "même place : la première l'emporte, l'autre prend la suivante libre")
        XCTAssertEqual(OrganizerPlan.pinned(auto: [1, 2], pins: [(1, 8)], last: 20), [2, 3, 4, 5, 6, 7, 8, 1])
        XCTAssertEqual(OrganizerPlan.pinned(auto: [1, 2], pins: [(1, 12)], last: 10), [1, 2], "jamais au-delà du Mixer")
        XCTAssertEqual(OrganizerPlan.pinned(auto: [1, 2], pins: [(1, 2), (2, 2)], last: 2), [2, 1])
    }

    /// « Toutes les drums, la 808 comprise, du 27 au 32 » : la famille commence à sa piste, son bus juste après.
    func testFamilyStartsWhereItIsAsked() {
        let result = project()
        XCTAssertEqual(plan(result).mixer.final, [1, 5, 4, 2, 3, 6])
        var styles = FamilyStyles.initial
        styles[.drums]?.mixerStart = 27
        let placed = plan(result, styles: styles)
        XCTAssertEqual([4, 2, 3, 6].map { slot(placed, $0) }, [27, 28, 29, 30], "808, Kick, Snare, bus")
        XCTAssertEqual([1, 5].map { slot(placed, $0) }, [1, 2])
        XCTAssertEqual(placed.mixer.final.sorted(), Array(1...30))

        let byHand = plan(result, styles: styles, slots: [2: 40])
        XCTAssertEqual(slot(byHand, 3), 40, "le son placé à la main l'emporte")
        XCTAssertEqual([4, 2, 6].map { slot(byHand, $0) }, [27, 28, 29])

        let link = FakeOrganizerLink()
        link.channels = result.channels
        link.mixer = result.mixer
        let applier = OrganizerApplier(link: link, moveUp: link.moveSelectedUp, moveLeft: link.moveSelectedLeft)
        let outcome = applier.apply(placed, result: result, styles: styles)
        XCTAssertNil(outcome.error)
        XCTAssertEqual(link.channels.map(\.name), ["Lead", "808", "Kick", "Snare"])
        XCTAssertEqual(link.channels.map(\.mixerTrack), [1, 27, 28, 29])
        XCTAssertEqual(link.mixer[30].name, "Drums Bus")
        XCTAssertNil(applier.undo(outcome.snapshot).error)
        XCTAssertEqual(link.mixer, result.mixer)
    }

    func testSoundPlacedByHand() {
        let result = project()
        let placed = plan(result, slots: [0: 10])
        XCTAssertEqual(slot(placed, 1), 10)
        XCTAssertEqual([5, 4, 2, 3].map { slot(placed, $0) }, [1, 2, 3, 4])
        XCTAssertEqual(plan(result, slots: [7: 3]).mixer.final, plan(result).mixer.final, "un son inconnu ne compte pas")
    }

    /// Les familles glissées dans l'aperçu : Channel rack (puis Mixer et Playlist) dans ce nouvel ordre.
    func testFamilyOrderIsFollowed() {
        let result = project()
        XCTAssertEqual(plan(result).rack.final, [0, 3, 1, 2])
        var options = OrganizerOptions()
        options.familyOrder = [.drums, .melody]
        let drumsFirst = plan(result, options: options)
        XCTAssertEqual(drumsFirst.rack.final, [1, 2, 0, 3])
        XCTAssertEqual(Array(drumsFirst.mixer.final.prefix(6)), [2, 3, 4, 6, 1, 5], "la 808 avec les drums")
        XCTAssertEqual(OrganizerOptions.completeOrder([.drums, .drums]), [.drums, .vocals, .melody, .bass, .fx, .unsure])
        XCTAssertEqual(OrganizerOptions.completeOrder([]), SoundFamily.order)
    }

    /// « Écrire… » : le nom tapé est posé tel quel, sur le son et partout où il a son nom (piste du Mixer…) ; les
    /// autres sons sont numérotés sans le reprendre ; même « Renommer » décoché, il est posé dans le Channel rack.
    func testWrittenNamesArePutEverywhere() {
        let result = project()
        let named = plan(result, names: [1: "  Kick Boom ", 2: "Kick"])
        XCTAssertEqual(named.rack.names[1], "Kick Boom")
        XCTAssertEqual(named.rack.names[2], "Kick")
        XCTAssertEqual(named.mixer.names[2], "Kick Boom")
        XCTAssertEqual(named.mixer.names[3], "Kick")
        var quiet = OrganizerOptions()
        quiet.rename = false
        XCTAssertEqual(plan(result, options: quiet, names: [0: "Mon lead"]).rack.names, [0: "Mon lead"])
        XCTAssertEqual(plan(result, names: [1: "  "]).rack.names[1], "Kick", "vide : le nom automatique")
    }

    func testFamilyStartIsSaved() throws {
        var styles = FamilyStyles.initial
        styles[.drums]?.mixerStart = 27
        let suite = "places-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        FamilyStyles.save(styles, to: defaults)
        XCTAssertEqual(FamilyStyles.load(from: defaults)[.drums]?.mixerStart, 27)
        XCTAssertNil(FamilyStyles.load(from: defaults)[.bass]?.mixerStart)
        let json = Data(#"{"drums":{"color":"E0453A","mixer":900}}"#.utf8)
        XCTAssertNil(try JSONDecoder().decode([String: FamilyStyle].self, from: json)["drums"]?.mixerStart)
    }

    /// Les familles glissées comme des dossiers : vers le bas, juste après la cible ; vers le haut, juste avant.
    func testFamiliesMovedLikeFolders() {
        let order = SoundFamily.order                            // Voix, Mélodies, Basse, Drums, FX, À vérifier
        XCTAssertEqual(OrganizerController.moving(.vocals, onto: .drums, in: order),
                       [.melody, .bass, .drums, .vocals, .fx, .unsure])
        XCTAssertEqual(OrganizerController.moving(.drums, onto: .vocals, in: order),
                       [.drums, .vocals, .melody, .bass, .fx, .unsure])
        XCTAssertEqual(OrganizerController.moving(.drums, onto: .drums, in: order), order)
    }

    /// La case du numéro, comme dans FL : tirée vers le haut, plus grand ; jamais sous 1 ni au-delà du Mixer.
    func testSlotBoxDrag() {
        XCTAssertEqual(MixerSlotBox.dragged(from: 10, dy: -30, last: 125), 15)
        XCTAssertEqual(MixerSlotBox.dragged(from: 10, dy: 30, last: 125), 5)
        XCTAssertEqual(MixerSlotBox.dragged(from: 10, dy: 2, last: 125), 10)
        XCTAssertEqual(MixerSlotBox.dragged(from: 3, dy: 600, last: 125), 1)
        XCTAssertEqual(MixerSlotBox.dragged(from: 120, dy: -600, last: 125), 125)
        // Comme FL : la flèche garée à droite de la case pendant qu'on tire, puis remise où elle était.
        XCTAssertEqual(HiddenDrag.parked(mouse: CGPoint(x: 100, y: 500), localX: 10, width: 40), CGPoint(x: 142, y: 500))
        XCTAssertEqual(HiddenDrag.parked(mouse: CGPoint(x: 100, y: 500), localX: 55, width: 40), CGPoint(x: 112, y: 500))
        XCTAssertEqual(HiddenDrag.displayPoint(CGPoint(x: 100, y: 700), primaryHeight: 900), CGPoint(x: 100, y: 200))
    }
}
