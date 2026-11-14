// Playlist : chaque son sur sa piste, ses clips réunis (retour du propriétaire, vidéo du 21/10 : les mêmes patterns
// posés deux fois, sur deux pistes, et une piste qui mêlait deux sons).
import XCTest
@testable import FLShortcut

final class OrganizerClipMoverTests: XCTestCase {
    private func item(_ text: String, x: CGFloat, y: CGFloat, width: CGFloat = 50) -> TextLook.Item {
        TextLook.Item(text: text, box: CGRect(x: x, y: y - 7, width: width, height: 14))
    }

    private func spot(_ pattern: Int, _ track: Int, _ x: CGFloat) -> ClipSpot {
        ClipSpot(pattern: pattern, track: track, x: x, point: CGPoint(x: x + 8, y: CGFloat(track) * 48 + 30))
    }

    func testClipNamesAreRecognized() {
        let names = [0: "Mélodie", 1: "Mélodie 3", 2: "Snare"]
        XCTAssertEqual(ClipLayout.pattern(for: "Mélodie", names: names), 0)
        XCTAssertEqual(ClipLayout.pattern(for: "E Mélodie 3", names: names), 1, "l'icône du clip lue comme une lettre")
        XCTAssertEqual(ClipLayout.pattern(for: "M..3", names: names), 1, "nom abrégé par FL dans un clip court")
        XCTAssertEqual(ClipLayout.pattern(for: "M…3", names: names), 1)
        XCTAssertEqual(ClipLayout.pattern(for: "Snare", names: names), 2)
        XCTAssertNil(ClipLayout.pattern(for: "Playlist", names: names))
        XCTAssertNil(ClipLayout.pattern(for: "H..2", names: [0: "Hat 2", 1: "Hit 2"]), "deux patterns possibles : aucun")
    }

    func testClipsAreReadOnTheirTrack() {
        let rows: [Int: CGPoint] = [0: CGPoint(x: 108, y: 194), 1: CGPoint(x: 108, y: 242), 2: CGPoint(x: 108, y: 290)]
        let items = [item("Snare", x: 100, y: 194),                       // nom de piste : colonne des pistes
                     item("Snare", x: 580, y: 193), item("Mélodie", x: 580, y: 241),
                     item("Mélodie", x: 581, y: 242),                     // la ligne et son mot : un seul clip
                     item("M..3", x: 740, y: 289), item("Playlist", x: 600, y: 120)]
        let clips = ClipLayout.clips(items: items, names: [0: "Mélodie", 1: "Mélodie 3", 2: "Snare"], rows: rows,
                                     pitch: 48)
        XCTAssertEqual(clips.map(\.pattern), [2, 0, 1])
        XCTAssertEqual(clips.map(\.track), [0, 1, 2])
        XCTAssertEqual(clips[0].point, CGPoint(x: 588, y: 193 + 48 * 0.3), "dans le clip, sous son nom, pas sur l'icône")
        // La ligne « Mélodie 3 » et son mot « Mélodie » (lus tous les deux) : un seul clip, du pattern « Mélodie 3 ».
        let line = ClipLayout.clips(items: [item("Mélodie", x: 580, y: 241, width: 40),
                                            item("Mélodie 3", x: 580, y: 241, width: 80)],
                                    names: [0: "Mélodie", 1: "Mélodie 3"], rows: rows, pitch: 48)
        XCTAssertEqual(line.map(\.pattern), [1])
    }

    /// La vidéo : pistes 1 à 4 : patterns 1 à 4 (mesures 1 à 8) ; pistes 4 à 7 : patterns 1 à 4 de nouveau (mesures
    /// 9 à 16) ; la piste 4 mêlait le pattern 4 et le pattern 1. Chaque son retrouve sa première piste.
    func testIdenticalSoundsShareOneTrack() {
        var clips: [ClipSpot] = []
        for p in 0..<4 { clips += [spot(p, p, 100), spot(p, p, 200)] }
        for p in 0..<4 { clips += [spot(p, p + 3, 300), spot(p, p + 3, 400)] }
        clips += [spot(4, 7, 300), spot(4, 7, 400)]
        let sounds: [Int: Set<Int>] = [0: [0], 1: [1], 2: [2], 3: [3], 4: [4]]
        let moves = ClipLayout.moves(clips, sounds: sounds, free: [8, 9])
        XCTAssertEqual(moves, [ClipMove(pattern: 0, from: 3, to: 0, x: 300), ClipMove(pattern: 0, from: 3, to: 0, x: 400),
                               ClipMove(pattern: 1, from: 4, to: 1, x: 300), ClipMove(pattern: 1, from: 4, to: 1, x: 400),
                               ClipMove(pattern: 2, from: 5, to: 2, x: 300), ClipMove(pattern: 2, from: 5, to: 2, x: 400),
                               ClipMove(pattern: 3, from: 6, to: 3, x: 300), ClipMove(pattern: 3, from: 6, to: 3, x: 400)])
        let after = ClipLayout.applying(moves, to: clips)
        var byTrack: [Int: Set<Int>] = [:]
        for clip in after { byTrack[clip.track, default: []].insert(clip.pattern) }
        XCTAssertEqual(byTrack, [0: [0], 1: [1], 2: [2], 3: [3], 7: [4]], "un son par piste, ses clips réunis")
    }

    /// Deux patterns qui jouent exactement les mêmes sons (un pattern et sa copie) : le même son, la même piste ; un son
    /// qui n'a aucune piste à lui va sur une piste vide.
    func testSameSoundsAndFreeTracks() {
        let clips = [spot(0, 0, 100), spot(1, 1, 200), spot(2, 1, 300)]
        XCTAssertEqual(ClipLayout.moves(clips, sounds: [0: [5], 1: [5], 2: [6]], free: [1, 2, 3]),
                       [ClipMove(pattern: 1, from: 1, to: 0, x: 200), ClipMove(pattern: 2, from: 1, to: 2, x: 300)])
        XCTAssertEqual(ClipLayout.moves([spot(0, 0, 100), spot(1, 1, 100)], sounds: [0: [5], 1: [5]], free: []), [],
                       "le même son au même moment sur deux pistes : jamais l'un sur l'autre (FL l'écraserait)")
        XCTAssertEqual(ClipLayout.moves([spot(0, 0, 100), spot(1, 0, 300)], sounds: [0: [1], 1: [2]], free: [0, 4]),
                       [ClipMove(pattern: 1, from: 0, to: 4, x: 300)], "une piste vide de `free`, jamais une piste occupée")
    }

    func testMoveIsConfirmedOnlyIfThatClipAloneMoved() {
        let before = [spot(0, 1, 100), spot(1, 2, 100)]
        let move = ClipMove(pattern: 0, from: 1, to: 3, x: 100)
        XCTAssertTrue(ClipLayout.confirms(move, before: before, after: [spot(0, 3, 101), spot(1, 2, 100)]))
        XCTAssertTrue(ClipLayout.confirms(move, before: before, after: [spot(0, 3, 100)]), "un nom pas relu : sans avis")
        XCTAssertFalse(ClipLayout.confirms(move, before: before, after: [spot(0, 3, 100), spot(1, 4, 100)]),
                       "un autre clip a bougé : rien n'était sélectionné")
        XCTAssertFalse(ClipLayout.confirms(move, before: before, after: [spot(0, 1, 100), spot(1, 2, 100)]))
        XCTAssertEqual(move.reversed, ClipMove(pattern: 0, from: 3, to: 1, x: 100))
    }

    func testTrackSoundsFollowTheClips() {
        let before = [spot(0, 1, 100), spot(1, 1, 300)]
        let after = ClipLayout.applying([ClipMove(pattern: 1, from: 1, to: 2, x: 300)], to: before)
        XCTAssertEqual(ClipLayout.trackSounds([0: [9], 1: [0, 1], 5: [7]], before: before, after: after,
                                              sounds: [0: [0], 1: [1]]),
                       [0: [9], 1: [0], 2: [1], 5: [7]], "pistes sans clip lu (clips audio) : comme à l'analyse")
    }
}
