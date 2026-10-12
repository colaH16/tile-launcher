import XCTest
import CoreGraphics
@testable import DeckCore

final class DesktopLayoutTests: XCTestCase {
    func testBottomShelfFitsActualRowsAndCapsOnlyItsViewport() {
        let one = DeckContentLayout(width: 1040, availableHeight: 560, registeredCount: 16, compact: false)
        let three = DeckContentLayout(width: 1040, availableHeight: 560, registeredCount: 36, compact: false)
        let many = DeckContentLayout(width: 1040, availableHeight: 560, registeredCount: 200, compact: false)
        XCTAssertEqual(one.registeredHeight, 94)
        XCTAssertEqual(three.registeredHeight, 230)
        XCTAssertEqual(many.registeredHeight, three.registeredHeight)
        XCTAssertGreaterThan(one.workTopInset, three.workTopInset)
    }
    func testWorkAreaUsesThirtyPercentOfSlackWithoutStretchingTiles() {
        let content = DeckContentLayout(width: 900, availableHeight: 520, registeredCount: 36, compact: false)
        let slack = 520 - content.workHeight - content.registeredHeight - content.gap
        XCTAssertGreaterThan(slack, 0)
        XCTAssertEqual(content.workTopInset, slack * 0.3, accuracy: 0.01)
        XCTAssertEqual(content.workHeight, DeckGeometry(width: 900, compact: false).twoRows + 30)
        XCTAssertLessThan(content.workTopInset + content.workHeight + content.gap + content.registeredHeight, 520)
    }
    func testSupportedSmallPanelKeepsTwoWindowRowsAndOneRegisteredRow() {
        for (width, bodyHeight, compact): (CGFloat, CGFloat, Bool) in [(512, 290, true), (760, 460, false), (1040, 560, false)] {
            let content = DeckContentLayout(width: width, availableHeight: bodyHeight, registeredCount: 100, compact: compact)
            XCTAssertGreaterThanOrEqual(content.registeredHeight, 94)
            XCTAssertGreaterThanOrEqual(content.workTopInset, 0)
            XCTAssertLessThanOrEqual(content.workTopInset + content.workHeight + content.gap + content.registeredHeight, bodyHeight)
        }
    }
    func testHiddenAndMinimizedWindowsAreStillCurrentWhenMembershipMatches() {
        XCTAssertEqual(WindowDesktop.resolve(windowSpaces: [4], activeSpaces: [4], onScreen: false), .current)
        XCTAssertEqual(WindowDesktop.resolve(windowSpaces: [5], activeSpaces: [4], onScreen: false), .other)
        XCTAssertEqual(WindowDesktop.resolve(windowSpaces: [4, 5], activeSpaces: [4], onScreen: false), .current)
    }
    func testCurrentIncludesActiveDesktopOnEachDisplay() {
        XCTAssertEqual(WindowDesktop.resolve(windowSpaces: [12], activeSpaces: [4, 12], onScreen: true), .current)
        XCTAssertEqual(WindowDesktop.resolve(windowSpaces: [13], activeSpaces: [4, 12], onScreen: false), .other)
    }
    func testUnavailablePrivateAPIOnlyUsesPositiveOnscreenEvidence() {
        XCTAssertEqual(WindowDesktop.resolve(windowSpaces: nil, activeSpaces: [], onScreen: true), .current)
        XCTAssertEqual(WindowDesktop.resolve(windowSpaces: nil, activeSpaces: [], onScreen: false), .unknown)
        XCTAssertEqual(WindowDesktop.resolve(windowSpaces: [], activeSpaces: [4], onScreen: false), .unknown)
        XCTAssertEqual(WindowDesktop.resolve(windowSpaces: [4], activeSpaces: [], onScreen: false), .unknown)
    }
    func testPartialAXAndTimeoutDoNotRemoveAStillOpenWindow() {
        XCTAssertTrue(WindowRetention.keepMissing(serverStillContains: true, axInvalid: false, destroyed: false))
        XCTAssertTrue(WindowRetention.keepMissing(serverStillContains: nil, axInvalid: false, destroyed: false))
    }
    func testPositiveClosureEvidenceRemovesCachedWindows() {
        XCTAssertFalse(WindowRetention.keepMissing(serverStillContains: false, axInvalid: false, destroyed: false))
        XCTAssertFalse(WindowRetention.keepMissing(serverStillContains: true, axInvalid: true, destroyed: false))
        XCTAssertFalse(WindowRetention.keepMissing(serverStillContains: true, axInvalid: false, destroyed: true))
    }
    func testPinnedDesktopTintCanChangeWithoutUnpinningOrChangingSelection() {
        let presentation = OverlayPresentation()
        let window = UUID()
        presentation.pin()
        presentation.selection = "window:test"
        presentation.windowDesktops = [window: .current]
        presentation.windowDesktops = [window: .other]
        XCTAssertTrue(presentation.isPinned)
        XCTAssertEqual(presentation.selection, "window:test")
        presentation.reset()
        XCTAssertTrue(presentation.windowDesktops.isEmpty)
    }
}
