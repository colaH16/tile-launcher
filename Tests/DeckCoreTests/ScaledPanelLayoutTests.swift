import XCTest
import CoreGraphics
@testable import DeckCore

final class ScaledPanelLayoutTests: XCTestCase {
    func testOnlyTilesScaleWhileToolbarAndSectionControlsStayAtNativeSize() {
        for compact in [false, true] {
            XCTAssertEqual(DeckSpacing.headerContent(compact: compact, scale: 1.4), 32)
            XCTAssertEqual(DeckSpacing.header(compact: compact, scale: 1.4), 52)
            XCTAssertEqual(DeckSpacing.chrome(compact: compact, scale: 1.4),
                           DeckSpacing.chrome(compact: compact, scale: 1))
        }
        XCTAssertEqual(DeckSpacing.workHeader(scale: 1.4), 32)
        XCTAssertEqual(DeckSpacing.shelfHeader(scale: 1.4), 42)
    }
    func testLargeScreenUsesPreferredScaleButDoesNotEnlargeOuterSpacing() {
        let screen = CGRect(x: -2560, y: -200, width: 2560, height: 1440)
        let original = PanelLayout.calculate(visibleFrame: screen, cursor: .zero).fittingContent(registeredCount: 18)
        let enlarged = PanelLayout.calculate(visibleFrame: screen, cursor: .zero, scale: 1.4).fittingContent(registeredCount: 18)
        XCTAssertEqual(enlarged.scale, 1.4)
        XCTAssertEqual(enlarged.frame.width, original.frame.width * 1.4, accuracy: 0.001)
        XCTAssertLessThan(enlarged.frame.height, original.frame.height * 1.4)
        XCTAssertEqual(enlarged.contentSize.width, original.frame.width, accuracy: 0.001)
        XCTAssertLessThan(enlarged.contentSize.height, original.frame.height)
        XCTAssertEqual(enlarged.columns, original.columns)
        XCTAssertEqual(DeckSpacing.header(compact: false, scale: enlarged.scale),
                       DeckSpacing.header(compact: false, scale: original.scale))
    }

    func testScreenBoundsMarginsAndCompleteRegisteredRowAtEverySupportedSize() {
        for size in [CGSize(width: 3440, height: 1440), CGSize(width: 1920, height: 1080),
                     CGSize(width: 1440, height: 900), CGSize(width: 1280, height: 800),
                     CGSize(width: 1024, height: 768), CGSize(width: 560, height: 600), CGSize(width: 400, height: 300)] {
            for origin in [CGPoint.zero, CGPoint(x: -3440, y: -600)] {
                let screen = CGRect(origin: origin, size: size)
                for count in [0, 18, 36, 39, 200] {
                    let layout = PanelLayout.calculate(visibleFrame: screen, cursor: screen.origin, scale: 1.4)
                        .fittingContent(registeredCount: count)
                    XCTAssertTrue(screen.contains(layout.frame))
                    XCTAssertTrue((1...1.4).contains(layout.scale))
                    XCTAssertLessThanOrEqual(layout.frame.width, 1568.001)
                    XCTAssertLessThanOrEqual(layout.frame.height, 1176.001)
                    guard layout.supported else { continue }
                    let room = layout.frame.height - DeckSpacing.chrome(compact: layout.compact, scale: layout.scale)
                    let body = DeckContentLayout(width: layout.contentSize.width, availableHeight: room,
                                                 registeredCount: count, compact: layout.compact, scale: layout.scale)
                    let minimum = RegisteredGridGeometry(width: layout.contentSize.width, scale: layout.scale).shelfHeight(count: 1, maximumRows: 1)
                    XCTAssertGreaterThanOrEqual(body.registeredHeight, minimum - 0.001)
                    XCTAssertLessThanOrEqual(body.workHeight + body.gap + body.registeredHeight, room + 0.001)
                }
            }
        }
    }

    func testProfileChangesPreserveScaleTopEdgeAndRestoreHeight() {
        let screen = CGRect(x: -2560, y: 120, width: 2560, height: 1440)
        let original = PanelLayout.calculate(visibleFrame: screen, cursor: CGPoint(x: -1000, y: 700), scale: 1.4)
            .fittingContent(registeredCount: 36)
        let small = original.refittingContent(registeredCount: 18, visibleFrame: screen)
        let restored = small.refittingContent(registeredCount: 36, visibleFrame: screen)
        XCTAssertEqual(small.scale, original.scale)
        XCTAssertEqual(small.frame.minX, original.frame.minX)
        XCTAssertEqual(small.frame.maxY, original.frame.maxY, accuracy: 0.001)
        XCTAssertLessThan(small.frame.height, original.frame.height)
        XCTAssertEqual(restored.frame.minX, original.frame.minX, accuracy: 0.001)
        XCTAssertEqual(restored.frame.minY, original.frame.minY, accuracy: 0.001)
        XCTAssertEqual(restored.frame.width, original.frame.width, accuracy: 0.001)
        XCTAssertEqual(restored.frame.height, original.frame.height, accuracy: 0.001)
    }

    func testReopenOnSmallerScreenClampsAndRetainsEveryWindow() {
        let large = PanelLayout.calculate(visibleFrame: CGRect(x: 0, y: 0, width: 2560, height: 1440), cursor: .zero, scale: 1.4)
            .fittingContent(registeredCount: 36)
        let screen = CGRect(x: -700, y: -200, width: 640, height: 600)
        let fitted = large.refittingContent(registeredCount: 200, visibleFrame: screen)
        XCTAssertTrue(screen.contains(fitted.frame))
        XCTAssertLessThan(fitted.scale, large.scale)
        XCTAssertEqual(fitted.windowLimit(manual: nil, actual: 1000), 1000)
        XCTAssertEqual(fitted.windowLimit(manual: 12, actual: 1000), 12)
    }

    func test39RegisteredAppsKeepThreeRowsOnNormalScreensInsteadOfLeavingAWholeRowBlank() {
        for screen in [CGSize(width: 2560, height: 1440), CGSize(width: 1920, height: 1080),
                       CGSize(width: 1440, height: 900), CGSize(width: 1280, height: 800)] {
            let layout = PanelLayout.calculate(visibleFrame: CGRect(origin: .zero, size: screen),
                cursor: .zero, scale: PanelLayout.preferredScale).fittingContent(registeredCount: 39)
            let room = layout.frame.height - DeckSpacing.chrome(compact: layout.compact, scale: layout.scale)
            let content = DeckContentLayout(width: layout.contentSize.width, availableHeight: room,
                registeredCount: 39, compact: layout.compact, scale: layout.scale)
            let grid = RegisteredGridGeometry(width: layout.contentSize.width, scale: layout.scale)
            XCTAssertEqual(content.registeredHeight, grid.shelfHeight(count: 39, maximumRows: 3))
            XCTAssertLessThan(room - content.workHeight - content.gap - content.registeredHeight, 1.01)
            XCTAssertEqual(content.gap, DeckSpacing.workToShelf(compact: layout.compact))
        }
    }

    func testApprovedThreeRowLayoutIncludesCompactFooterInRealWindowHeight() {
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1056)
        let layout = PanelLayout.calculate(visibleFrame: screen, cursor: .zero, scale: PanelLayout.preferredScale)
            .fittingContent(registeredCount: 39, workRows: 3)
        XCTAssertEqual(layout.frame.size, CGSize(width: 1568, height: 918))
        let room = layout.frame.height - DeckSpacing.chrome(compact: false, scale: layout.scale)
        let body = DeckContentLayout(width: layout.contentSize.width, availableHeight: room,
                                    registeredCount: 39, compact: false, scale: layout.scale, workRows: 3)
        XCTAssertEqual(body.registeredHeight,
                       RegisteredGridGeometry(width: layout.contentSize.width, scale: layout.scale)
                        .shelfHeight(count: 39, maximumRows: 3))
        XCTAssertLessThan(room - body.workHeight - body.gap - body.registeredHeight, 1)
    }

    func testFractionalShelfRemainderIsUsableInsteadOfRoundedDownToWholeRows() {
        let content = DeckContentLayout(width: 1040, availableHeight: 440, registeredCount: 200, compact: false)
        let grid = RegisteredGridGeometry(width: 1040)
        XCTAssertGreaterThan(content.registeredHeight, grid.shelfHeight(count: 14, maximumRows: 1))
        XCTAssertLessThan(content.registeredHeight, grid.shelfHeight(count: 200, maximumRows: 3))
        XCTAssertEqual(content.workHeight + content.gap + content.registeredHeight, 440, accuracy: 0.001)
    }
}
