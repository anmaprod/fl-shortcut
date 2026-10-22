// Moteur de mouvement : durées des trois ressorts, position d'un ressort, gel de la seule fenêtre principale,
// mouvement réduit (jamais au ralenti), règle des sons de l'interface.
import AppKit
import XCTest
@testable import FLShortcut

final class MotionEngineTests: XCTestCase {
    func testSettleTimes() {
        XCTAssertEqual(Motion.settle(response: 0.35, damping: 0.78), 0.493, accuracy: 0.01)
        XCTAssertEqual(Motion.settle(response: 0.5, damping: 1), 0.732, accuracy: 0.01)
        XCTAssertEqual(Motion.settle(response: 0.55, damping: 0.62), 0.975, accuracy: 0.01)
    }

    func testSpringValueEnds() {
        XCTAssertEqual(Motion.springValue(at: 0, response: 0.5, damping: 1), 0, accuracy: 0.001)
        XCTAssertEqual(Motion.springValue(at: 0.732, response: 0.5, damping: 1), 1, accuracy: 0.01)
        XCTAssertGreaterThan(Motion.springValue(at: 0.2, response: 0.55, damping: 0.62), 0.5)
    }

    func testSlowMotionScalesDurations() {
        let saved = DebugSnapshot.slowMotion
        defer { DebugSnapshot.slowMotion = saved }
        DebugSnapshot.slowMotion = 1
        XCTAssertEqual(Motion.settleTime(.doux), 0.732, accuracy: 0.01)
        XCTAssertEqual(Motion.appKitDuration, 0.3, accuracy: 0.001)
        DebugSnapshot.slowMotion = 10
        XCTAssertEqual(Motion.settleTime(.doux), 7.32, accuracy: 0.1)
        XCTAssertEqual(Motion.appKitDuration, 3, accuracy: 0.001)
        XCTAssertEqual(Motion.stagger(2, start: 0.1, step: 0.05), 2, accuracy: 0.001)
    }

    func testPolicyFreezesOnlyTheMainWindow() {
        XCTAssertEqual(MotionPolicy.mode(reduceMotion: false, slowMotion: 1, surface: .window, isKey: false,
                                         appActive: false), .frozen)
        XCTAssertEqual(MotionPolicy.mode(reduceMotion: false, slowMotion: 1, surface: .window, isKey: true,
                                         appActive: false), .full)
        for surface in [MotionSurface.menu, .organiser, .guide, .badge, .hint, .recording, .flight] {
            XCTAssertEqual(MotionPolicy.mode(reduceMotion: false, slowMotion: 1, surface: surface, isKey: false,
                                             appActive: false), .full)
        }
    }

    func testPolicyReduced() {
        XCTAssertEqual(MotionPolicy.mode(reduceMotion: true, slowMotion: 1, surface: .menu, isKey: true,
                                         appActive: true), .reduced)
        XCTAssertEqual(MotionPolicy.mode(reduceMotion: true, slowMotion: 10, surface: .menu, isKey: true,
                                         appActive: true), .full)
        XCTAssertEqual(MotionPolicy.mode(reduceMotion: true, slowMotion: 1, surface: .window, isKey: false,
                                         appActive: false), .frozen)
    }

    func testEffectiveModeOutsideAGate() {
        let saved = DebugSnapshot.slowMotion
        defer { DebugSnapshot.slowMotion = saved }
        DebugSnapshot.slowMotion = 1
        XCTAssertEqual(MotionMode.effective(.full, reduceMotion: true), .reduced)
        XCTAssertEqual(MotionMode.effective(.full, reduceMotion: false), .full)
        XCTAssertEqual(MotionMode.effective(.frozen, reduceMotion: true), .frozen)
        DebugSnapshot.slowMotion = 10
        XCTAssertEqual(MotionMode.effective(.full, reduceMotion: true), .full)
    }

    func testSoundRules() {
        XCTAssertTrue(InterfaceSound.allowed(event: .cardOpen, enabled: true, systemSounds: true, appActive: true,
                                             organiserBusy: false))
        XCTAssertFalse(InterfaceSound.allowed(event: .cardOpen, enabled: true, systemSounds: true, appActive: false,
                                              organiserBusy: false))
        XCTAssertTrue(InterfaceSound.allowed(event: .organiserDone, enabled: true, systemSounds: true,
                                             appActive: false, organiserBusy: false))
        XCTAssertFalse(InterfaceSound.allowed(event: .dropDetach, enabled: true, systemSounds: true, appActive: true,
                                              organiserBusy: true))
        XCTAssertFalse(InterfaceSound.allowed(event: .cardOpen, enabled: false, systemSounds: true, appActive: true,
                                              organiserBusy: false))
        XCTAssertFalse(InterfaceSound.allowed(event: .organiserDone, enabled: true, systemSounds: false,
                                              appActive: true, organiserBusy: false))
    }

    func testEachSoundIsAMacSound() {
        let events: [InterfaceSoundEvent] = [.cardOpen, .cardClose, .creatorOpen, .creatorClose, .dropDetach,
                                             .organiserDone]
        for event in events {
            XCTAssertNotNil(NSSound(named: NSSound.Name(event.soundName)), event.soundName)
        }
    }
}
