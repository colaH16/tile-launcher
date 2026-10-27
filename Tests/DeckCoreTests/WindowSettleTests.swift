import XCTest
@testable import DeckCore

final class WindowSettleTests: XCTestCase {
    /// Manual serial queue: scheduled work runs only when the test fires it.
    private final class Harness {
        var queued: [(delay: TimeInterval, work: () -> Void)] = []
        var reads: [Int32] = []
        var tracked: Set<Int32> = [7, 8]
        var windowsAfterRead: [Int32: [Bool]] = [:]
        lazy var scheduler = WindowSettleScheduler(
            schedule: { [unowned self] delay, work in self.queued.append((delay, work)) },
            tracking: { [unowned self] pid in self.tracked.contains(pid) },
            read: { [unowned self] pid in
                self.reads.append(pid)
                return self.windowsAfterRead[pid]?.isEmpty == false ? self.windowsAfterRead[pid]!.removeFirst() : false
            })
        @discardableResult func fire() -> TimeInterval? {
            guard !queued.isEmpty else { return nil }
            let next = queued.removeFirst()
            next.work()
            return next.delay
        }
    }

    func testBudgetIsFiniteCompletionBasedAndStopsOnEvidence() {
        var budget = WindowSettleBudget()
        let delays = (0..<6).compactMap { _ in budget.next(realWindowAccepted: false, processAlive: true, tracking: true) }
        XCTAssertEqual(delays, [0.3, 0.8, 1.6, 3.2])
        for stop in [(true, true, true), (false, false, true), (false, true, false)] {
            var stopped = WindowSettleBudget()
            XCTAssertNil(stopped.next(realWindowAccepted: stop.0, processAlive: stop.1, tracking: stop.2))
            // A stop is final for this allowance.
            XCTAssertNil(stopped.next(realWindowAccepted: false, processAlive: true, tracking: true))
        }
    }
    func testLateRealWindowAfterSuccessfulEmptyReadStopsWithoutReopening() {
        let harness = Harness()
        harness.windowsAfterRead[7] = [false, true]
        XCTAssertTrue(harness.scheduler.arm(7, hasRealWindow: false, isAlive: { true }))
        XCTAssertEqual(harness.fire(), 0.3)   // successful empty read
        XCTAssertEqual(harness.fire(), 0.8)   // the window is accepted and published by `read`
        XCTAssertNil(harness.fire())
        XCTAssertEqual(harness.reads, [7, 7])
        XCTAssertFalse(harness.scheduler.isRunning(7))
    }
    func testGenuinelyWindowlessAppStopsAtTheCapAndCannotBeExtended() {
        let harness = Harness()
        harness.scheduler.arm(7, hasRealWindow: false, isAlive: { true })
        var delays: [TimeInterval] = []
        while let delay = harness.fire() { delays.append(delay) }
        XCTAssertEqual(delays, WindowSettleBudget.delays)
        XCTAssertEqual(harness.reads.count, 4)
        // Further launch/activation events for this living process add nothing.
        XCTAssertFalse(harness.scheduler.arm(7, hasRealWindow: false, isAlive: { true }))
        XCTAssertTrue(harness.queued.isEmpty)
    }
    func testDuplicateArmWhileRunningDoesNotAddWorkOrResetTheBudget() {
        let harness = Harness()
        harness.scheduler.arm(7, hasRealWindow: false, isAlive: { true })
        harness.fire()
        XCTAssertFalse(harness.scheduler.arm(7, hasRealWindow: false, isAlive: { true }))
        XCTAssertEqual(harness.queued.map(\.delay), [0.8])
        var remaining = 0
        while harness.fire() != nil { remaining += 1 }
        XCTAssertEqual(remaining, 3)
        XCTAssertEqual(harness.reads.count, 4)
    }
    func testOnlyTheArmedProcessIsRead() {
        let harness = Harness()
        harness.scheduler.arm(7, hasRealWindow: false, isAlive: { true })
        while harness.fire() != nil {}
        XCTAssertEqual(Set(harness.reads), [7])
    }
    func testExistingRealWindowDoesNotConsumeTheAllowance() {
        let harness = Harness()
        XCTAssertFalse(harness.scheduler.arm(7, hasRealWindow: true, isAlive: { true }))
        XCTAssertTrue(harness.queued.isEmpty)
        // Later, without a real window, the same process may still settle once.
        XCTAssertTrue(harness.scheduler.arm(7, hasRealWindow: false, isAlive: { true }))
    }
    func testTerminationStopsBeforeTheNextRead() {
        let harness = Harness()
        var alive = true
        harness.scheduler.arm(7, hasRealWindow: false, isAlive: { alive })
        harness.fire()
        alive = false
        harness.fire()
        XCTAssertEqual(harness.reads, [7])
        XCTAssertTrue(harness.queued.isEmpty)
        XCTAssertFalse(harness.scheduler.arm(7, hasRealWindow: false, isAlive: { false }))
    }
    func testReusedPIDStartsFreshAndOldWorkCannotRead() {
        let harness = Harness()
        var oldAlive = true
        harness.scheduler.arm(7, hasRealWindow: false, isAlive: { oldAlive })
        oldAlive = false
        XCTAssertTrue(harness.scheduler.arm(7, hasRealWindow: false, isAlive: { true }))
        XCTAssertEqual(harness.queued.count, 2)
        harness.fire()                       // the old process's work
        XCTAssertTrue(harness.reads.isEmpty)
        harness.fire()                       // the new process's first read
        XCTAssertEqual(harness.reads, [7])
    }
    func testTrustOrTrackingLossAndRemovalCancelPendingWork() {
        let harness = Harness()
        harness.scheduler.arm(7, hasRealWindow: false, isAlive: { true })
        harness.scheduler.arm(8, hasRealWindow: false, isAlive: { true })
        harness.scheduler.cancelAll()
        while harness.fire() != nil {}
        XCTAssertTrue(harness.reads.isEmpty)

        harness.scheduler.arm(7, hasRealWindow: false, isAlive: { true })
        harness.scheduler.cancel(7)
        harness.fire()
        XCTAssertTrue(harness.reads.isEmpty)

        harness.scheduler.arm(8, hasRealWindow: false, isAlive: { true })
        harness.tracked.remove(8)
        harness.fire()
        XCTAssertTrue(harness.reads.isEmpty)
        XCTAssertTrue(harness.queued.isEmpty)
        XCTAssertFalse(harness.scheduler.arm(9, hasRealWindow: false, isAlive: { true }))
    }

    func testRegistrationRetriesOnlyTransientFailures() {
        XCTAssertEqual(AXNotificationRegistration(errorCode: 0), .registered)
        XCTAssertEqual(AXNotificationRegistration(errorCode: -25209), .registered)
        XCTAssertEqual(AXNotificationRegistration(errorCode: -25207), .unsupported)
        XCTAssertEqual(AXNotificationRegistration(errorCode: -25208), .unsupported)
        XCTAssertEqual(AXNotificationRegistration(errorCode: -25204), .transient)
        XCTAssertEqual(AXNotificationRegistration(errorCode: -25200), .transient)
        // A starting app rejects one name transiently and lacks another.
        let first = AXNotificationRegistration.pending([(name: "focus", code: -25204), (name: "created", code: 0),
                                                        (name: "other", code: -25207)])
        XCTAssertEqual(first, ["focus"])
        // The retry covers only that name; success leaves nothing to repeat.
        XCTAssertEqual(AXNotificationRegistration.pending([(name: "focus", code: 0)]), [])
        XCTAssertEqual(AXNotificationRegistration.pending([(name: "focus", code: -25209)]), [])
        XCTAssertEqual(AXNotificationRegistration.pending([(name: "focus", code: -25208)]), [])
    }
}
