import XCTest
@testable import DeckCore

final class OverlayRefreshTests: XCTestCase {
    func testIdleOverlayFollowsContextHeldOrPinned() {
        XCTAssertTrue(OverlayRefreshPolicy.allows(hasSelection: false, hasPendingAction: false, mouseDown: false))
    }
    func testSelectionAndMouseGesturesDeferReordering() {
        for (selected, pending, mouse) in [(true, false, false), (false, true, false), (false, false, true)] {
            XCTAssertFalse(OverlayRefreshPolicy.allows(hasSelection: selected, hasPendingAction: pending, mouseDown: mouse))
        }
    }
}
