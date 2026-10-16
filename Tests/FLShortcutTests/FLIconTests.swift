import XCTest
@testable import FLShortcut

/// Icônes de FL : géométrie de la grille (clic au centre de la case, sans lire l'écran) et ligne du bloc.
final class FLIconTests: XCTestCase {
    /// Grille de FL de 617 × 677 : cases de 617 / 14 de côté sous une barre de titres de 677 − 15 × 617 / 14.
    func testCellCenters() throws {
        let window = CGRect(x: 100, y: 200, width: 617, height: 677)
        let first = FLIconGrid.center(of: try XCTUnwrap(FLIcon(column: 1, row: 0)), in: window)
        XCTAssertEqual(first.x - window.minX, 66.1, accuracy: 0.05)
        XCTAssertEqual(first.y - window.minY, 38.0, accuracy: 0.05)
        let last = FLIconGrid.center(of: try XCTUnwrap(FLIcon(column: 13, row: 14)), in: window)
        XCTAssertEqual(last.x, window.maxX - 617.0 / 28, accuracy: 0.05)
        XCTAssertEqual(last.y, window.maxY - 617.0 / 28, accuracy: 0.05)
        for column in 0..<FLIconGrid.columns {
            for row in 0..<FLIconGrid.rows {
                let icon = try XCTUnwrap(FLIcon(column: column, row: row))
                XCTAssertTrue(window.contains(FLIconGrid.center(of: icon, in: window)), icon.code)
            }
        }
    }

    func testPickerSkipsChannelColumn() throws {
        XCTAssertFalse(FLIconGrid.isPickable(try XCTUnwrap(FLIcon(column: 13, row: 2))))
        XCTAssertTrue(FLIconGrid.isPickable(try XCTUnwrap(FLIcon(column: 12, row: 2))))
        XCTAssertTrue(FLIconGrid.isPickable(try XCTUnwrap(FLIcon(code: "0-0"))))
    }

    func testSummaryShowsIcon() throws {
        let red = NameColorPayload.defaultColor
        let icon = try XCTUnwrap(FLIcon(code: "3-7"))
        let name = FLIconGrid.cell(icon)?.name ?? "3-7"
        XCTAssertEqual(NameColorPayload.summary(name: "Kick", color: red, icon: icon), "Kick · #E0453A · icône \(name)")
        XCTAssertEqual(NameColorPayload.summary(name: nil, color: nil, icon: icon), "icône \(name)")
        XCTAssertEqual(NameColorPayload.summary(name: nil, color: nil), "nom et couleur à choisir")
        let body = BlockBody.nameColor(name: nil, color: red, icon: icon)
        XCTAssertEqual(BlockRegistry.spec(.nameColor).resume(body, FakeLayout.qwerty), "couleur #E0453A · icône \(name)")
    }
}
