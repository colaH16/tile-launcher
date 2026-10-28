import XCTest
@testable import DeckCore

final class CompletionPollerTests: XCTestCase {
    private final class Clock {
        final class Timer {
            let at: TimeInterval
            let fire: () -> Void
            var cancelled = false
            init(at: TimeInterval, fire: @escaping () -> Void) { self.at = at; self.fire = fire }
        }
        var now: TimeInterval = 0
        var timers: [Timer] = []
        func schedule(_ delay: TimeInterval, _ fire: @escaping () -> Void) -> () -> Void {
            let timer = Timer(at: now + delay, fire: fire)
            timers.append(timer)
            return { timer.cancelled = true }
        }
        func advance(_ duration: TimeInterval) {
            let end = now + duration
            while let next = timers.filter({ !$0.cancelled && $0.at <= end }).min(by: { $0.at < $1.at }) {
                now = next.at
                next.cancelled = true
                next.fire()
            }
            now = end
        }
    }
    private final class Fixture {
        let clock = Clock()
        var starts: [TimeInterval] = []
        var completions: [(Int?) -> Void] = []
        var values: [Int?] = []
        var poller: CompletionPoller<Int?>!
        init() {
            poller = CompletionPoller(interval: 0.4, operation: { [unowned self] done in
                self.starts.append(self.clock.now)
                self.completions.append(done)
            }, schedule: clock.schedule)
            poller.onValue = { [unowned self] in self.values.append($0) }
        }
    }

    func testHalfSecondReadWaitsPointFourFromCompletionRatherThanSkippingToNextTick() {
        let f = Fixture()
        f.poller.start()
        f.clock.advance(0.500000001)
        XCTAssertEqual(f.starts, [0])
        XCTAssertTrue(f.clock.timers.isEmpty, "No timer until the read actually completes")
        f.completions[0](1)
        f.clock.advance(0.399)
        XCTAssertEqual(f.starts.count, 1)
        f.clock.advance(0.0011)
        XCTAssertEqual(f.starts.count, 2)
        XCTAssertEqual(f.starts[1], 0.900000001, accuracy: 0.00000001)
    }

    func testSlowReadAndRepeatedRequestsNeverBuildABacklog() {
        let f = Fixture()
        f.poller.start()
        for _ in 0..<100 {
            f.poller.refresh()
            f.poller.start()
            f.clock.advance(0.5)
        }
        XCTAssertEqual(f.starts.count, 1)
        f.completions[0](1)
        f.clock.advance(0.2)
        f.poller.refresh() // Also cannot bypass the resting interval.
        XCTAssertEqual(f.starts.count, 1)
        f.clock.advance(0.21)
        XCTAssertEqual(f.starts, [0, 50.4])
        f.clock.advance(100)
        XCTAssertEqual(f.starts.count, 2, "No catch-up reads queued by the earlier requests")
    }

    func testStoppingDuringReadDiscardsLateValueAndDoesNotScheduleAgain() {
        let f = Fixture()
        f.poller.start()
        f.poller.stop()
        f.completions[0](1)
        f.clock.advance(100)
        XCTAssertTrue(f.values.isEmpty)
        XCTAssertEqual(f.starts.count, 1)
        XCTAssertTrue(f.clock.timers.isEmpty)
    }

    func testQuickCloseAndReopenRetainsInFlightGateAndRefreshesAfterOldCompletion() {
        let f = Fixture()
        f.poller.start()
        f.poller.stop()
        f.poller.refresh() // A new Option preparation while the old read is pending.
        f.poller.start()
        XCTAssertEqual(f.starts.count, 1)
        f.clock.advance(3)
        f.completions[0](1)
        XCTAssertTrue(f.values.isEmpty, "An old overlay must not publish into the new one")
        f.clock.advance(0.401)
        XCTAssertEqual(f.starts, [0, 3.4])
        f.completions[1](2)
        XCTAssertEqual(f.values, [2])
    }

    func testCancelledTimerCannotStartAReadAfterStopOrIntoNewSession() {
        let f = Fixture()
        f.poller.start()
        f.completions[0](1)
        let staleTimer = f.clock.timers[0]
        f.poller.stop()
        XCTAssertTrue(staleTimer.cancelled)
        f.poller.start()
        f.completions[1](2)
        staleTimer.fire() // Simulate a timer callback already dispatched when cancelled.
        XCTAssertEqual(f.starts.count, 2)
        f.clock.advance(0.401)
        XCTAssertEqual(f.starts.count, 3)
    }

    func testPreparationIsOneShotAndVisibleMonitoringAdoptsAnOngoingRead() {
        let f = Fixture()
        f.poller.refresh()
        f.completions[0](1)
        f.clock.advance(10)
        XCTAssertEqual(f.starts.count, 1)
        XCTAssertEqual(f.values, [1])
        f.poller.refresh()
        f.poller.start()
        XCTAssertEqual(f.starts.count, 2)
        f.completions[1](nil) // No offer/failure still completes the poll and starts the wait.
        XCTAssertEqual(f.values, [1, nil])
        f.clock.advance(0.401)
        XCTAssertEqual(f.starts.count, 3)
    }

    func testStoppingFromResultCallbackPreventsAnotherRead() {
        let f = Fixture()
        f.poller.onValue = { _ in f.poller.stop() }
        f.poller.start()
        f.completions[0](1)
        f.clock.advance(100)
        XCTAssertEqual(f.starts.count, 1)
        XCTAssertTrue(f.clock.timers.isEmpty)
        f.poller.onValue = nil
    }

    func testRealRunLoopTimerWaitsUntilBackgroundReadCompletes() {
        let nextRead = expectation(description: "Second read")
        var starts = 0
        var finished: TimeInterval = 0
        let poller = CompletionPoller<Int>(interval: 0.04) { done in
            starts += 1
            if starts == 1 {
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.06) {
                    DispatchQueue.main.async {
                        finished = ProcessInfo.processInfo.systemUptime
                        done(1)
                    }
                }
            } else {
                XCTAssertGreaterThanOrEqual(ProcessInfo.processInfo.systemUptime - finished, 0.038)
                nextRead.fulfill()
            }
        }
        poller.start()
        wait(for: [nextRead], timeout: 2)
        poller.stop()
        XCTAssertEqual(starts, 2)
    }
}
