import XCTest
@testable import FLShortcut

/// Pistes de la Playlist remontées par leur menu : où viser le nom de chaque piste dans la fenêtre de FL.
final class OrganizerPlaylistMoverTests: XCTestCase {
    private func item(_ text: String, x: CGFloat, y: CGFloat) -> TextLook.Item {
        TextLook.Item(text: text, box: CGRect(x: x, y: y - 6, width: 60, height: 12))
    }

    /// La colonne des noms (vidéo de l'utilisateur : x 576, une rangée tous les 81 points) ; « Track 4 » pas lu ; à
    /// droite, des clips aux mêmes noms ; ailleurs, le « Kick » du Channel rack posé sur la Playlist.
    func testHeaderColumnAndRows() {
        let names = ["Mélodie", "Mélodie 2", "Kick", "Track 4", "Snare"]
        let items = [item("Mélodie", x: 576, y: 240), item("Melodie 2", x: 577, y: 321), item("Kick", x: 576, y: 402),
                     item("Snare", x: 576, y: 564), item("Kick", x: 710, y: 402), item("Snare", x: 710, y: 564),
                     item("Kick", x: 1060, y: 420)]
        let rows = PlaylistMover.rows(names: names, items: items)
        XCTAssertEqual(rows?[0], CGPoint(x: 584, y: 240))
        XCTAssertEqual(rows?[3], CGPoint(x: 584, y: 483), "d'après le pas entre les rangées")
        XCTAssertEqual(rows?[4], CGPoint(x: 584, y: 564))
        XCTAssertNil(PlaylistMover.rows(names: names, items: [item("Kick", x: 576, y: 402)]), "un seul nom : rien")
    }

    /// Deux pistes au même nom (le même son) : chacune à sa rangée, de haut en bas ; à égalité de noms trouvés, la
    /// colonne la plus à gauche (les noms des pistes, pas ceux des clips).
    func testSameNamesAndLeftmostColumn() {
        let names = ["Kick", "Kick", "Snare"]
        let items = [item("Kick", x: 900, y: 100), item("Kick", x: 900, y: 150), item("Kick", x: 500, y: 100),
                     item("Kick", x: 500, y: 150), item("Snare", x: 500, y: 200), item("Snare", x: 900, y: 200)]
        let rows = PlaylistMover.rows(names: names, items: items)
        XCTAssertEqual(rows?[0], CGPoint(x: 508, y: 100))
        XCTAssertEqual(rows?[1], CGPoint(x: 508, y: 150))
        XCTAssertEqual(rows?[2], CGPoint(x: 508, y: 200))
    }
}
