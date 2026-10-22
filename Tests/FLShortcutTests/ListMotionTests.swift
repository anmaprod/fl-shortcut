// Listes : au-delà de 60 lignes changées d'un coup, pas d'animation ; compte des lignes changées (parties, arrivées,
// déplacées).
import XCTest
@testable import FLShortcut

final class ListMotionTests: XCTestCase {
    func testListLimit() {
        XCTAssertTrue(ListMotion.animates(changes: 1))
        XCTAssertTrue(ListMotion.animates(changes: 60))
        XCTAssertFalse(ListMotion.animates(changes: 61))
        XCTAssertFalse(ListMotion.animates(changes: 0))
    }

    func testChangesCount() {
        XCTAssertEqual(ListMotion.changes(from: [1, 2, 3], to: [1, 3, 4]), 2)     // 2 parti, 4 arrivé
        XCTAssertEqual(ListMotion.changes(from: [1, 2, 3], to: [3, 2, 1]), 2)     // déplacés : hors de la suite gardée
        XCTAssertEqual(ListMotion.changes(from: [1, 2, 3], to: [1, 2, 3]), 0)
        XCTAssertEqual(ListMotion.changes(from: [Int](), to: [1, 2]), 2)
    }

    func testBigChangeStopsCounting() {
        let many = Array(0..<500)
        XCTAssertGreaterThan(ListMotion.changes(from: many, to: []), ListMotion.limit)
        XCTAssertFalse(ListMotion.animates(changes: ListMotion.changes(from: many, to: Array(500..<900))))
    }
}
