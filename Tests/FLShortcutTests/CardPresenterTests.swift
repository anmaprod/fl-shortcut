// Cartes : une seule à la fois, celle demandée pendant une fermeture attend, fermeture sans effet si rien n'est
// ouvert, tout oublié à la fermeture de la fenêtre.
import XCTest
@testable import FLShortcut

final class CardPresenterTests: XCTestCase {
    func testRequestWhileClosingWaits() {
        var q = CardQueue()
        let a = CardRequest(kind: .templates, source: nil), b = CardRequest(kind: .guide(page: 0), source: nil)
        q.request(a)
        XCTAssertEqual(q.current?.id, a.id)
        q.close()
        XCTAssertTrue(q.closing)
        q.request(b)
        XCTAssertEqual(q.current?.id, a.id, "b attend la fin de la fermeture")
        q.closeFinished()
        XCTAssertEqual(q.current?.id, b.id)
        XCTAssertFalse(q.closing)
    }

    func testRequestWhileOpenClosesFirst() {
        var q = CardQueue()
        let a = CardRequest(kind: .templates, source: nil), b = CardRequest(kind: .communityCompose, source: nil)
        q.request(a)
        q.request(b)
        XCTAssertTrue(q.closing)
        XCTAssertEqual(q.waiting.map(\.id), [b.id])
    }

    func testCloseIsIdempotent() {
        var q = CardQueue()
        q.close()
        q.closeFinished()
        XCTAssertNil(q.current)
        XCTAssertFalse(q.closing)
        q.request(CardRequest(kind: .templates, source: nil))
        q.close()
        q.close()
        XCTAssertTrue(q.closing)
        q.closeFinished()
        XCTAssertNil(q.current)
    }

    func testResetDropsQueue() {
        var q = CardQueue()
        q.request(CardRequest(kind: .templates, source: nil))
        q.request(CardRequest(kind: .communityCompose, source: nil))
        q.reset()
        XCTAssertNil(q.current)
        XCTAssertTrue(q.waiting.isEmpty)
        XCTAssertFalse(q.closing)
    }

    func testStrayCloseFinishedKeepsTheOpenCard() {
        var q = CardQueue()
        let a = CardRequest(kind: .templates, source: nil)
        q.request(a)
        q.closeFinished()
        XCTAssertEqual(q.current?.id, a.id, "rien ne se fermait : la carte reste")
    }
}
