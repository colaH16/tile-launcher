import XCTest
@testable import DeckCore

final class ApplicationLaunchGateTests: XCTestCase {
    func testVerifiedWindowReleasesGateWithoutClaimingLaunchNotification() {
        var gate = ApplicationLaunchGate(now: 0)
        _ = gate.update(processFound: true, now: 1)
        XCTAssertEqual(gate.update(processFound: true, windowReady: true, now: 2), .windowReady)
        XCTAssertFalse(gate.status.blocksLaunch)
    }
    func testWindowEvidenceNeedsLivingProcessAndCannotOverrideTermination() {
        var waiting = ApplicationLaunchGate(now: 0)
        XCTAssertEqual(waiting.update(processFound: false, windowReady: true, now: 1), .waiting)
        var stopped = ApplicationLaunchGate(now: 0)
        XCTAssertEqual(stopped.update(processFound: true, windowReady: true, terminated: true, now: 1), .stopped)
    }
    func testLaunchCompletionKeepsItsOwnMeaningWhenBothSignalsExist() {
        var gate = ApplicationLaunchGate(now: 0)
        XCTAssertEqual(gate.update(processFound: true, finished: true, windowReady: true, now: 1), .finished)
    }
    func testNoProcessReleasesAfterStartWindow() {
        var gate = ApplicationLaunchGate(now: 10)
        XCTAssertEqual(gate.update(processFound: false, now: 12.99), .waiting)
        XCTAssertEqual(gate.update(processFound: false, now: 13), .notStarted)
        XCTAssertFalse(gate.status.blocksLaunch)
    }
    func testStartedProcessStaysBlockedBeyondInitialWindowUntilFinished() {
        var gate = ApplicationLaunchGate(now: 10)
        XCTAssertEqual(gate.update(processFound: true, now: 12.9), .launching)
        XCTAssertEqual(gate.update(processFound: true, now: 20), .launching)
        XCTAssertEqual(gate.update(processFound: true, finished: true, now: 21), .finished)
        XCTAssertFalse(gate.status.blocksLaunch)
    }
    func testAlreadyRunningReadyAppReleasesImmediately() {
        var gate = ApplicationLaunchGate(now: 10)
        XCTAssertEqual(gate.update(processFound: true, finished: true, now: 10), .finished)
    }
    func testErrorOrProcessExitNeverLeavesTileBlocked() {
        var failed = ApplicationLaunchGate(now: 0)
        XCTAssertEqual(failed.update(processFound: false, failed: true, now: 0.1), .failed)
        var stopped = ApplicationLaunchGate(now: 0)
        _ = stopped.update(processFound: true, now: 1)
        XCTAssertEqual(stopped.update(processFound: true, finished: true, terminated: true, now: 2), .stopped)
    }
    func testMissingCompletionSignalHasBoundedFallback() {
        var gate = ApplicationLaunchGate(now: 10)
        _ = gate.update(processFound: true, now: 12)
        XCTAssertEqual(gate.update(processFound: true, now: 71.99), .launching)
        XCTAssertEqual(gate.update(processFound: true, now: 72), .timedOut)
    }
    func testLateSignalsCannotReblockAReleasedAttempt() {
        var gate = ApplicationLaunchGate(now: 0)
        _ = gate.update(processFound: false, now: 3)
        XCTAssertEqual(gate.update(processFound: true, now: 4), .notStarted)
        var next = ApplicationLaunchGate(now: 4)
        XCTAssertEqual(next.update(processFound: true, now: 4.1), .launching)
    }
    func testTemporaryInventoryGapDoesNotMeanProcessExit() {
        var gate = ApplicationLaunchGate(now: 0)
        _ = gate.update(processFound: true, now: 1)
        XCTAssertEqual(gate.update(processFound: false, now: 4), .launching)
        XCTAssertEqual(gate.update(processFound: true, finished: true, now: 5), .finished)
    }
    func testFinishAtDeadlineWinsOverTimeout() {
        var gate = ApplicationLaunchGate(now: 0)
        _ = gate.update(processFound: true, now: 1)
        XCTAssertEqual(gate.update(processFound: true, finished: true, now: 61), .finished)
    }
}
