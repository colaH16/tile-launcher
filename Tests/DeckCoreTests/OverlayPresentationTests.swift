import XCTest
@testable import DeckCore

final class OverlayPresentationTests: XCTestCase {
    func testHeldWindowSelectionAndSpaceChangeKeepOverlayWithoutPinning() {
        let presentation = OverlayPresentation()
        XCTAssertFalse(presentation.dismisses(for: .windowSelection, optionHeld: true))
        XCTAssertFalse(presentation.dismisses(for: .spaceChange, optionHeld: true))
        XCTAssertFalse(presentation.isPinned)
        XCTAssertTrue(presentation.dismisses(for: .release))
        XCTAssertTrue(presentation.dismisses(for: .escape, optionHeld: true))
    }
    func testUnheldWindowSelectionAndSpaceChangeKeepExistingDismissalPolicy() {
        let presentation = OverlayPresentation()
        XCTAssertTrue(presentation.dismisses(for: .windowSelection))
        XCTAssertTrue(presentation.dismisses(for: .spaceChange))
        presentation.pin()
        XCTAssertFalse(presentation.dismisses(for: .windowSelection))
        XCTAssertFalse(presentation.dismisses(for: .spaceChange))
        XCTAssertTrue(presentation.dismisses(for: .escape))
    }
    func testFeedbackSurvivesSelectionClearButCannotClearANewerRequest() {
        let presentation = OverlayPresentation()
        presentation.selection = "pin:a"
        presentation.selectionTitle = "App A"
        let first = presentation.showExecution(target: "pin:a", title: "App A")
        presentation.selection = nil
        XCTAssertNil(presentation.selectionTitle)
        XCTAssertEqual(presentation.execution?.target, "pin:a")
        let next = presentation.showExecution(target: "pin:b", title: "App B")
        presentation.clearExecution(id: first)
        XCTAssertEqual(presentation.execution?.id, next)
        presentation.clearExecution(id: next)
        XCTAssertNil(presentation.execution)
    }

    func testClosingOverlayClearsKeyboardFeedback() {
        let presentation = OverlayPresentation()
        presentation.showExecution(target: "window:x", title: "Document")
        presentation.reset()
        XCTAssertNil(presentation.execution)
        XCTAssertNil(presentation.selectionTitle)
    }
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
