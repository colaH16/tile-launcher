import XCTest
@testable import DeckCore

final class MenuObservationLifecycleTests: XCTestCase {
    let original = ProcessIdentity(pid: 11, startedSeconds: 100, startedMicroseconds: 0)
    func testAlreadyRunningAppCanConnectImmediatelyAndDoesNotRetryWhenReady() {
        var state = MenuObservationLifecycle()
        let generation = state.begin(original)
        XCTAssertTrue(state.accepts(generation))
        state.connected(generation: generation)
        XCTAssertNil(state.retryDelay(generation: generation))
    }
    func testUnavailableMenuRetriesWithBackoffThenStopsUntilNextActivation() {
        var state = MenuObservationLifecycle()
        let generation = state.begin(original)
        XCTAssertEqual((0..<5).compactMap { _ in state.retryDelay(generation: generation) }, [0.25, 0.75, 2, 5, 15])
        XCTAssertNil(state.retryDelay(generation: generation))
        let retry = state.begin(original)
        XCTAssertFalse(state.accepts(generation))
        XCTAssertEqual(state.retryDelay(generation: retry), 0.25)
        state.connected(generation: retry)
        XCTAssertNil(state.retryDelay(generation: retry))
    }
    func testSwitchTerminationPauseAndPermissionLossInvalidateQueuedRetries() {
        var state = MenuObservationLifecycle()
        let generation = state.begin(original)
        _ = state.retryDelay(generation: generation)
        state.begin(nil)
        state.connected(generation: generation)
        XCTAssertFalse(state.isReady)
        XCTAssertNil(state.retryDelay(generation: generation))
        XCTAssertFalse(state.accepts(generation))
    }
    func testRestartIncludingReusedPIDCannotInheritOldConnection() {
        var state = MenuObservationLifecycle()
        let old = state.begin(original)
        state.connected(generation: old)
        let newProcess = ProcessIdentity(pid: original.pid, startedSeconds: 200, startedMicroseconds: 0)
        let new = state.begin(newProcess)
        XCTAssertFalse(state.isReady)
        XCTAssertFalse(state.accepts(old))
        XCTAssertTrue(state.accepts(new))
        XCTAssertEqual(state.process, newProcess)
    }
}
