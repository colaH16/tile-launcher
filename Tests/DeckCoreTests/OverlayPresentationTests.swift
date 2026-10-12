import XCTest
@testable import DeckCore

final class OverlayPresentationTests: XCTestCase {
    func testPinnedOverlaySurvivesReleaseScreenshotKeysAndOutsideClick() {
        let presentation = OverlayPresentation()
        XCTAssertTrue(presentation.dismisses(for: .release))
        presentation.pin()
        XCTAssertFalse(presentation.dismisses(for: .release))
        XCTAssertFalse(presentation.dismisses(for: .interruption))
        XCTAssertFalse(presentation.dismisses(for: .outsideClick))
        XCTAssertTrue(presentation.dismisses(for: .escape))
    }

    func testClosingAndReopeningRestoresHoldBehavior() {
        let presentation = OverlayPresentation()
        presentation.pin()
        presentation.reset()
        XCTAssertFalse(presentation.isPinned)
        XCTAssertTrue(presentation.dismisses(for: .release))
        XCTAssertTrue(presentation.dismisses(for: .interruption))
        XCTAssertTrue(presentation.dismisses(for: .outsideClick))
    }
}
