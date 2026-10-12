import XCTest
@testable import DeckCore

final class PinnedRefreshTests: XCTestCase {
    func testPinnedIdlePanelCanFollowContext() {
        XCTAssertTrue(PinnedRefreshPolicy.allows(isPinned: true, optionDown: false,
                                                hasSelection: false, hasPendingAction: false, mouseDown: false))
    }
    func testHeldOverlayKeepsCapturedOrder() {
        XCTAssertFalse(PinnedRefreshPolicy.allows(isPinned: false, optionDown: false,
                                                 hasSelection: false, hasPendingAction: false, mouseDown: false))
        XCTAssertFalse(PinnedRefreshPolicy.allows(isPinned: true, optionDown: true,
                                                 hasSelection: false, hasPendingAction: false, mouseDown: false))
    }
    func testSelectionAndMouseGesturesDeferReordering() {
        for (selected, pending, mouse) in [(true, false, false), (false, true, false), (false, false, true)] {
            XCTAssertFalse(PinnedRefreshPolicy.allows(isPinned: true, optionDown: false,
                                                     hasSelection: selected, hasPendingAction: pending, mouseDown: mouse))
        }
    }
}
