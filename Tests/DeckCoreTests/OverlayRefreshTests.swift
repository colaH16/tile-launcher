import XCTest
@testable import DeckCore

final class OverlayRefreshTests: XCTestCase {
    func testIdleOverlayFollowsContextHeldOrPinned() {
        XCTAssertTrue(OverlayRefreshPolicy.allows(showsExecution: false, mouseDown: false))
    }
    func testExecutionFeedbackAndMouseGesturesDeferReordering() {
        for (execution, mouse) in [(true, false), (false, true), (true, true)] {
            XCTAssertFalse(OverlayRefreshPolicy.allows(showsExecution: execution, mouseDown: mouse))
        }
    }
}
