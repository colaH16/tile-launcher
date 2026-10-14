import XCTest
import CoreGraphics
@testable import DeckCore

final class DesktopLayoutTests: XCTestCase {
    func testBottomShelfFitsActualRowsAndCapsOnlyItsViewport() {
        let one = DeckContentLayout(width: 1040, availableHeight: 570, registeredCount: 14, compact: false)
        let three = DeckContentLayout(width: 1040, availableHeight: 570, registeredCount: 36, compact: false)
        let many = DeckContentLayout(width: 1040, availableHeight: 570, registeredCount: 200, compact: false)
        let tighter = DeckContentLayout(width: 1040, availableHeight: 560, registeredCount: 36, compact: false)
        XCTAssertEqual(one.registeredHeight, 105.42857, accuracy: 0.001)
        XCTAssertEqual(three.registeredHeight, 248.28571, accuracy: 0.001)
        XCTAssertEqual(many.registeredHeight, three.registeredHeight)
        XCTAssertEqual(tighter.registeredHeight, 176.85714, accuracy: 0.001)
        XCTAssertLessThanOrEqual(three.workHeight + three.gap + three.registeredHeight, 570)
        XCTAssertEqual(one.workTopInset, 0)
        XCTAssertEqual(three.workTopInset, 0)
    }
    func testRegisteredSquaresKeepDenseRowsWithinPanelAndReserveExactHeight() {
        for width: CGFloat in [512, 640, 760, 900, 1040] {
            let grid = RegisteredGridGeometry(width: width)
            XCTAssertGreaterThanOrEqual(grid.side, 60)
            XCTAssertLessThan(grid.side, 72)
            XCTAssertEqual(CGFloat(grid.columns) * grid.side + CGFloat(grid.columns - 1) * grid.gap, width - 48, accuracy: 0.01)
            XCTAssertEqual(grid.shelfHeight(count: grid.columns + 1, maximumRows: 3), grid.side * 2 + grid.gap + 42)
        }
    }
    func testWorkAreaShowsThreeRowsAndThirtyPercentOfFourth() {
        let content = DeckContentLayout(width: 900, availableHeight: 520, registeredCount: 36, compact: false)
        let geometry = DeckGeometry(width: 900, compact: false)
        XCTAssertEqual(content.workTopInset, 0)
        XCTAssertEqual(content.workHeight, geometry.unit * 3.3 + geometry.gap * 3 + 32, accuracy: 0.001)
        XCTAssertEqual(content.registeredHeight, RegisteredGridGeometry(width: 900).shelfHeight(count: 24, maximumRows: 2))
        XCTAssertLessThan(content.workTopInset + content.workHeight + content.gap + content.registeredHeight, 520)
    }
    func testSupportedSmallPanelKeepsTwoWindowRowsAndOneRegisteredRow() {
        for (width, bodyHeight, compact): (CGFloat, CGFloat, Bool) in [(512, 298, true), (760, 470, false), (1040, 560, false)] {
            let content = DeckContentLayout(width: width, availableHeight: bodyHeight, registeredCount: 100, compact: compact)
            XCTAssertGreaterThanOrEqual(content.registeredHeight, 94)
            XCTAssertGreaterThanOrEqual(content.workHeight, DeckGeometry(width: width, compact: compact).twoRows + 32 - 0.001)
            XCTAssertGreaterThanOrEqual(content.workTopInset, 0)
            XCTAssertLessThanOrEqual(content.workTopInset + content.workHeight + content.gap + content.registeredHeight, bodyHeight)
        }
    }
    func testContentFittingShrinksWithinScreenAndAspectBounds() {
        let screen = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let original = PanelLayout.calculate(visibleFrame: screen, cursor: CGPoint(x: -100, y: 100))
        for count in [0, 14, 35, 200] {
            let fitted = original.fittingContent(registeredCount: count)
            XCTAssertLessThanOrEqual(fitted.frame.height, original.frame.height)
            XCTAssertTrue(original.frame.contains(fitted.frame))
            XCTAssertLessThanOrEqual(fitted.frame.width / fitted.frame.height, 1.5)
            XCTAssertGreaterThanOrEqual(fitted.frame.height, 620)
        }
        XCTAssertLessThan(original.fittingContent(registeredCount: 35).frame.height, original.frame.height)
        let fitted = original.fittingContent(registeredCount: 35)
        let body = DeckContentLayout(width: fitted.frame.width, availableHeight: fitted.frame.height - 154,
                                     registeredCount: 35, compact: false)
        XCTAssertEqual(body.registeredHeight, RegisteredGridGeometry(width: fitted.frame.width).shelfHeight(count: 35, maximumRows: 3))
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
