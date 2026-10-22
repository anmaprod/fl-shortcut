// Couche de vol : rectangle interpolé, conversion vers la couche par AppKit (vues retournées ou non), sûreté qui
// finit un vol quoi qu'il arrive, fermeture de la fenêtre qui ne laisse rien de caché, remplacement d'un vol.
import AppKit
import XCTest
@testable import FLShortcut

/// Vue à l'origine en haut à gauche, comme la couche SwiftUI.
private final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

final class FlightLayerTests: XCTestCase {
    func testRectInterpolation() {
        let a = CGRect(x: 0, y: 0, width: 20, height: 20), b = CGRect(x: 100, y: 50, width: 60, height: 40)
        XCTAssertEqual(FlightGeometry.rect(at: 0, from: a, to: b), a)
        XCTAssertEqual(FlightGeometry.rect(at: 1, from: a, to: b), b)
        XCTAssertEqual(FlightGeometry.rect(at: 0.5, from: a, to: b), CGRect(x: 50, y: 25, width: 40, height: 30))
    }

    func testLocalConversionUsesTheLayerView() {
        let root = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
        let layer = FlippedView(frame: root.bounds)
        root.addSubview(layer)
        let probe = NSView(frame: NSRect(x: 10, y: 250, width: 30, height: 20))
        root.addSubview(probe)
        XCTAssertEqual(FlightGeometry.local(probe.bounds, of: probe, in: layer),
                       CGRect(x: 10, y: 30, width: 30, height: 20))
    }

    func testSafetyDeadlineFollowsSlowMotion() {
        XCTAssertEqual(FlightGeometry.safetyDeadline(slowMotion: 1), 2)
        XCTAssertEqual(FlightGeometry.safetyDeadline(slowMotion: 10), 20)
    }

    func testSafetyEndsFlightWithoutCompletion() {
        let center = FlightCenter(now: { Date(timeIntervalSince1970: 0) }, schedule: { _, _ in })
        center.testFly(target: "t")
        XCTAssertEqual(center.hidden, ["t"])
        center.expire(at: Date(timeIntervalSince1970: 1.9))
        XCTAssertEqual(center.hidden, ["t"], "pas encore l'heure")
        center.expire(at: Date(timeIntervalSince1970: 2.1))
        XCTAssertTrue(center.hidden.isEmpty)
        XCTAssertTrue(center.flights.isEmpty)
    }

    func testCancelAllForgetsHiddenTargets() {
        let center = FlightCenter(now: Date.init, schedule: { _, _ in })
        center.testFly(target: "a")
        center.testFly(target: "b")
        center.cancelAll()
        XCTAssertTrue(center.hidden.isEmpty)
        XCTAssertTrue(center.flights.isEmpty)
    }

    func testSecondFlightToTheSameTargetReplacesTheFirst() {
        let center = FlightCenter(now: Date.init, schedule: { _, _ in })
        center.testFly(target: "t")
        center.testFly(target: "t")
        XCTAssertEqual(center.flights.count, 1)
        XCTAssertEqual(center.hidden, ["t"])
    }

    func testNoFlightWithoutFramesCallsCompletionAtOnce() {
        let center = FlightCenter(now: Date.init, schedule: { _, _ in })
        var done = 0
        center.fly(.key("A"), from: "absent", to: "absent aussi") { done += 1 }
        XCTAssertEqual(done, 1)
        XCTAssertTrue(center.hidden.isEmpty)
    }

    func testReducedModeNeverFlies() {
        let center = FlightCenter(now: Date.init, schedule: { _, _ in })
        center.mode = .reduced
        var done = 0
        center.fly(.card(cornerRadius: 10), fromRect: CGRect(x: 0, y: 0, width: 10, height: 10), to: "t") { done += 1 }
        XCTAssertEqual(done, 1)
        XCTAssertTrue(center.flights.isEmpty)
    }
}
