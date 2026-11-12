import XCTest
@testable import FLShortcut

/// 12/11 (« le bouton quitter et rouvrir… il ne rouvre pas automatiquement FL Studio ») : mêmes essais que Windows
/// (FlRelaunchPlanTests.cs).
final class FLRelaunchPlanTests: XCTestCase {
    func testFLIsLaunchedOnceItHasQuit() {
        var plan = FLRelaunchPlan(oldPID: 10, now: 0)
        XCTAssertEqual(plan.next(now: 1, running: [10]), .wait)      // « Enregistrer ? » dans FL
        XCTAssertEqual(plan.next(now: 3, running: [10]), .wait)
        XCTAssertEqual(plan.next(now: 3.5, running: []), .wait)      // parti : une seconde de battement
        XCTAssertEqual(plan.next(now: 4.5, running: []), .launch)
        XCTAssertEqual(plan.next(now: 5, running: []), .wait)        // le nouveau FL démarre
        XCTAssertEqual(plan.next(now: 6, running: [22]), .done)
        XCTAssertEqual(plan.launches, 1)
    }

    func testFLReopenedByHandIsNotLaunchedAgain() {
        var plan = FLRelaunchPlan(oldPID: 10, now: 0)
        XCTAssertEqual(plan.next(now: 2, running: []), .wait)
        XCTAssertEqual(plan.next(now: 2.5, running: [30]), .done)
        XCTAssertEqual(plan.launches, 0)
    }

    func testLaunchErrorIsRetriedSoon() {
        var plan = FLRelaunchPlan(oldPID: 10, now: 0)
        XCTAssertEqual(plan.next(now: 1, running: []), .wait)
        XCTAssertEqual(plan.next(now: 2, running: []), .launch)
        plan.launchFailed(now: 2)
        XCTAssertEqual(plan.next(now: 3, running: []), .wait)
        XCTAssertEqual(plan.next(now: 4, running: []), .launch)
        XCTAssertEqual(plan.launches, 2)
    }

    func testFLThatNeverAppearsIsLaunchedThreeTimesThenLeft() {
        var plan = FLRelaunchPlan(oldPID: 10, now: 0)
        XCTAssertEqual(plan.next(now: 1, running: []), .wait)
        XCTAssertEqual(plan.next(now: 2, running: []), .launch)
        XCTAssertEqual(plan.next(now: 21.5, running: []), .wait)
        XCTAssertEqual(plan.next(now: 22, running: []), .launch)
        XCTAssertEqual(plan.next(now: 42, running: []), .launch)
        XCTAssertEqual(plan.next(now: 62, running: []), .giveUp)
        XCTAssertEqual(plan.launches, FLRelaunchPlan.maxLaunches)
    }

    func testFLThatStaysOpenIsLeftAfterFiveMinutes() {
        var plan = FLRelaunchPlan(oldPID: 10, now: 0)
        XCTAssertEqual(plan.next(now: 299, running: [10]), .wait)    // « Annuler » à « Enregistrer ? »
        XCTAssertEqual(plan.next(now: 300, running: [10]), .giveUp)
        XCTAssertEqual(plan.launches, 0)
    }

    func testANewFLNextToTheOldOneCounts() {
        var plan = FLRelaunchPlan(oldPID: 10, now: 0)
        XCTAssertEqual(plan.next(now: 1, running: [10, 31]), .done)
    }
}
