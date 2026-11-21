import XCTest
@testable import FLShortcut

/// 13/11 : le Channel rack rangé dans la copie (`FLPProject.reorderingChannels`) et le projet suivi
/// (`OrganizerResult.reordering`).
final class FLPChannelOrderTests: XCTestCase {
    private let names = ["Pad", "Kick", "ZENOLOGY", "Snare", "808"]

    /// Chaque canal à sa nouvelle place, renuméroté ; ses notes et ses clips le suivent ; les noms des patterns (écrits
    /// par FL après le premier canal) restent où ils sont.
    func testChannelsMoveWithTheirNotesAndClips() throws {
        let file = FLPSample.sample(flOrder: true)
        let before = try FLPProject(file)
        let order = [3, 4, 1, 0, 2]
        let moved = try XCTUnwrap(FLPProject.reorderingChannels(file, order: order))
        XCTAssertEqual(moved.events.count, file.events.count)
        let after = try FLPProject(moved)
        XCTAssertEqual(after.channels.map(\.iid), Array(0..<5))
        XCTAssertEqual(after.channels.map { $0.name ?? "" }, order.map { names[$0] })
        XCTAssertEqual(after.channels.map(\.type), order.map { before.channels[$0].type })
        XCTAssertEqual(after.patternNames, before.patternNames)
        // Notes : Snare (3) → place 0, 808 (4) → 1, Kick (1) → 2, ZENOLOGY (2) → 4.
        XCTAssertEqual(after.notes[1], [4: 3])
        XCTAssertEqual(after.notes[2], [0: 1, 1: 1])
        XCTAssertEqual(after.notes[3], [2: 1])
        // Le clip du canal 1 (Kick) suit le Kick (place 2) ; les clips des patterns ne bougent pas.
        XCTAssertEqual(before.clips.filter { $0.source == .channel(1) }.count, 1)
        XCTAssertEqual(after.clips.map(\.source), before.clips.map { $0.source == .channel(1) ? FLPProject.Clip.Source.channel(2) : $0.source })
        XCTAssertEqual(after.clips.map(\.track), before.clips.map(\.track))
    }

    /// L'ordre d'origine redonne exactement le même fichier ; le même échange deux fois aussi.
    func testSameOrderGivesTheSameFile() throws {
        let file = FLPSample.sample(flOrder: true)
        XCTAssertEqual(FLPProject.reorderingChannels(file, order: [0, 1, 2, 3, 4]), file)
        let once = try XCTUnwrap(FLPProject.reorderingChannels(file, order: [1, 0, 2, 3, 4]))
        XCTAssertNotEqual(once, file)
        XCTAssertEqual(FLPProject.reorderingChannels(once, order: [1, 0, 2, 3, 4]), file)
    }

    /// Tout ce qui pourrait désigner un canal autrement, ou une forme inattendue : rien n'est touché.
    func testRefusedWhenAChannelCouldBePointedAtOtherwise() {
        let order = [1, 0, 2, 3, 4]
        XCTAssertNil(FLPProject.reorderingChannels(FLPSample.sample(types: [2: 3], flOrder: true), order: order), "layer")
        XCTAssertNil(FLPProject.reorderingChannels(FLPSample.sample(types: [4: 5], flOrder: true), order: order), "automation")
        for id: UInt8 in [223, 227, 234] {
            var file = FLPSample.sample(flOrder: true)
            file.events.insert(FLPEvent(id: id, bytes: [0, 0, 0, 0]), at: 3)
            XCTAssertNil(FLPProject.reorderingChannels(file, order: order), "événement \(id)")
        }
        XCTAssertNil(FLPProject.reorderingChannels(FLPSample.sample(), order: order), "canaux qui ne finissent pas pareil")
        let file = FLPSample.sample(flOrder: true)
        XCTAssertNil(FLPProject.reorderingChannels(file, order: [0, 0, 2, 3, 4]), "un canal deux fois")
        XCTAssertNil(FLPProject.reorderingChannels(file, order: [1, 0, 2, 3]), "un canal oublié")
        var renumbered = file
        let at = renumbered.events.indices.first { renumbered.events[$0].id == 64 && renumbered.events[$0 + 1].id == 21
            && renumbered.events[$0].value == 1 }!
        renumbered.events[at].bytes = FLPBytes.le(7, size: 2)
        XCTAssertNil(FLPProject.reorderingChannels(renumbered, order: order), "numéros pas dans l'ordre")
    }

    /// Le projet suivi : chaque son sous sa nouvelle place, ses patterns, ses pistes, ses clips.
    func testResultFollowsTheNewPlaces() throws {
        let gray = RGBColor(r: 0x40, g: 0x40, b: 0x40)
        let channels = names.enumerated().map {
            ChannelInfo(index: $0.offset, type: 2, mixerTrack: $0.offset + 1, color: gray, name: $0.element)
        }
        let items = [OrganizerItem(index: 2, name: "ZENOLOGY", family: .melody, confidence: 1, testNotes: false,
                                   mixerTrack: 3, color: gray)]
        var result = OrganizerResult(channels: channels, items: items, patternSounds: [0: [2], 1: [3, 4]], unused: [0])
        result.trackSounds = [5: [1]]
        result.soundAt = [2: 1.5]
        result.freed = [9]
        let moved = try XCTUnwrap(result.reordering([3, 1, 4, 0, 2]))
        XCTAssertEqual(moved.map, [3: 0, 1: 1, 4: 2, 0: 3, 2: 4])
        XCTAssertEqual(moved.result.channels.map(\.name), ["Snare", "Kick", "808", "Pad", "ZENOLOGY"])
        XCTAssertEqual(moved.result.channels.map(\.index), Array(0..<5))
        XCTAssertEqual(moved.result.channels.map(\.mixerTrack), [4, 2, 5, 1, 3])
        XCTAssertEqual(moved.result.items.map(\.index), [4])
        XCTAssertEqual(moved.result.patternSounds, [0: [4], 1: [0, 2]])
        XCTAssertEqual(moved.result.trackSounds, [5: [1]])
        XCTAssertEqual(moved.result.unused, [3])
        XCTAssertEqual(moved.result.soundAt, [4: 1.5])
        XCTAssertEqual(moved.result.freed, [9])
        XCTAssertNil(result.reordering([0, 1, 2]), "pas tous les sons")
    }
}
