import XCTest
@testable import DeckCore

final class OverlayPresentationTests: XCTestCase {
    func testHeldWindowSelectionAndSpaceChangeKeepOverlayWithoutPinning() {
        let presentation = OverlayPresentation()
        XCTAssertFalse(presentation.dismisses(for: .windowSelection, heldPresentation: true, optionDown: true))
        XCTAssertFalse(presentation.dismisses(for: .spaceChange, heldPresentation: true, optionDown: true))
        XCTAssertFalse(presentation.isPinned)
        XCTAssertTrue(presentation.dismisses(for: .release))
        XCTAssertTrue(presentation.dismisses(for: .escape, heldPresentation: true, optionDown: true))
    }
    /// Manual/held × Option up/down × pinned. Only an Option-held overlay with
    /// Option still down, or a pinned one, survives window/desktop transitions.
    func testWindowAndSpaceTransitionsFollowOnlyTheOptionHoldThatOpenedTheOverlay() {
        for held in [false, true] {
            for optionDown in [false, true] {
                for pinned in [false, true] {
                    let presentation = OverlayPresentation()
                    if pinned { presentation.pin() }
                    let keeps = pinned || (held && optionDown)
                    let context = "held=\(held) optionDown=\(optionDown) pinned=\(pinned)"
                    for reason in [OverlayDismissal.windowSelection, .spaceChange] {
                        XCTAssertEqual(presentation.dismisses(for: reason, heldPresentation: held, optionDown: optionDown),
                                       !keeps, "\(reason) \(context)")
                    }
                    XCTAssertTrue(presentation.dismisses(for: .escape, heldPresentation: held, optionDown: optionDown), context)
                    // Option itself never changes release/outside-click policy.
                    for reason in [OverlayDismissal.release, .interruption, .outsideClick] {
                        XCTAssertEqual(presentation.dismisses(for: reason, heldPresentation: held, optionDown: optionDown),
                                       !pinned, "\(reason) \(context)")
                    }
                    XCTAssertEqual(presentation.isPinned, pinned, context)
                }
            }
        }
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
