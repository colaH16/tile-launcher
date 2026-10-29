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

    /// R351: the ceiling frame was clamped before trimming, so an edge cursor left
    /// up to half the trimmed height between it and a short panel.
    func testEdgeCursorPlacementUsesFinalHeightInsteadOfClampedCeiling() {
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1415)
        func fitted(_ y: CGFloat) -> PanelLayout {
            PanelLayout.calculate(visibleFrame: screen, cursor: CGPoint(x: 1280, y: y), scale: 1.4)
                .fittingContent(registeredCount: 20, workRows: 3)
        }
        XCTAssertEqual(fitted(1350).frame.height, 816, accuracy: 0.001)
        for (cursor, minY, shift) in [(CGFloat(60), CGFloat(24), CGFloat(-180)), (260, 24, -180), (600, 192, -12),
                                      (707.5, 299.5, 0), (1100, 575, 180), (1350, 575, 180)] {
            let base = fitted(cursor)
            let placed = base.centered(on: CGPoint(x: 1280, y: cursor), visibleFrame: screen)
            XCTAssertEqual(placed.frame.minY, minY, accuracy: 0.001, "cursor y \(cursor)")
            XCTAssertEqual(placed.frame.minY - base.frame.minY, shift, accuracy: 0.001, "cursor y \(cursor)")
            XCTAssertEqual(placed.frame.size, base.frame.size)
            XCTAssertEqual(placed.frame.minX, base.frame.minX, accuracy: 0.001)
        }
    }

    func testFreshPlacementCentersFinalSizeOnCursorOrMovesOnlyToTheSafeEdge() {
        let screens = [CGRect(x: 0, y: 0, width: 2560, height: 1415), CGRect(x: 0, y: 0, width: 1512, height: 945),
                       CGRect(x: -2560, y: -200, width: 2560, height: 1440), CGRect(x: -3440, y: -600, width: 1440, height: 900),
                       CGRect(x: 0, y: 0, width: 560, height: 600), CGRect(x: 0, y: 0, width: 400, height: 300)]
        let fractions: [CGFloat] = [0, 0.02, 0.25, 0.5, 0.75, 0.98, 1]
        for screen in screens {
            let safe = screen.insetBy(dx: min(24, screen.width / 8), dy: min(24, screen.height / 8))
            for count in [0, 20, 39] {
                for rows in [CGFloat(1), 3, 3.3] {
                    for fx in fractions {
                        for fy in fractions {
                            let cursor = CGPoint(x: screen.minX + screen.width * fx, y: screen.minY + screen.height * fy)
                            let base = PanelLayout.calculate(visibleFrame: screen, cursor: cursor, scale: 1.4)
                                .fittingContent(registeredCount: count, workRows: rows)
                            let placed = base.centered(on: cursor, visibleFrame: screen)
                            let label = "\(screen) count \(count) rows \(rows) cursor \(cursor)"
                            XCTAssertEqual(placed.frame.size, base.frame.size, label)
                            XCTAssertEqual(placed.scale, base.scale, label)
                            XCTAssertEqual(placed.compact, base.compact, label)
                            XCTAssertEqual(placed.supported, base.supported, label)
                            XCTAssertTrue(safe.insetBy(dx: -0.001, dy: -0.001).contains(placed.frame), label)
                            // Off-center only as far as the safe edge on the cursor's side requires.
                            if cursor.x > placed.frame.midX + 0.001 { XCTAssertEqual(placed.frame.maxX, safe.maxX, accuracy: 0.001, label) }
                            if cursor.x < placed.frame.midX - 0.001 { XCTAssertEqual(placed.frame.minX, safe.minX, accuracy: 0.001, label) }
                            if cursor.y > placed.frame.midY + 0.001 { XCTAssertEqual(placed.frame.maxY, safe.maxY, accuracy: 0.001, label) }
                            if cursor.y < placed.frame.midY - 0.001 { XCTAssertEqual(placed.frame.minY, safe.minY, accuracy: 0.001, label) }
                            XCTAssertLessThanOrEqual(abs(placed.frame.midY - cursor.y), abs(base.frame.midY - cursor.y) + 0.001, label)
                            XCTAssertLessThanOrEqual(abs(placed.frame.midX - cursor.x), abs(base.frame.midX - cursor.x) + 0.001, label)
                        }
                    }
                }
            }
        }
    }

    /// Quick reopen, drag restore and profile/content refits keep their top-edge
    /// rule after a cursor-centered fresh placement; nothing recenters them.
    func testRefitAfterCenteredPlacementKeepsPositionAndTopEdge() {
        let screen = CGRect(x: -2560, y: -200, width: 2560, height: 1440)
        let cursor = CGPoint(x: -300, y: 1180)
        let placed = PanelLayout.calculate(visibleFrame: screen, cursor: cursor, scale: 1.4)
            .fittingContent(registeredCount: 20, workRows: 3).centered(on: cursor, visibleFrame: screen)
        let reopened = placed.refittingContent(registeredCount: 20, visibleFrame: screen, workRows: 3)
        XCTAssertEqual(reopened.frame.origin.x, placed.frame.origin.x, accuracy: 0.001)
        XCTAssertEqual(reopened.frame.origin.y, placed.frame.origin.y, accuracy: 0.001)
        XCTAssertEqual(reopened.frame.size, placed.frame.size)
        let smaller = placed.refittingContent(registeredCount: 0, visibleFrame: screen, workRows: 1)
        XCTAssertEqual(smaller.frame.maxY, placed.frame.maxY, accuracy: 0.001)
        XCTAssertEqual(smaller.frame.minX, placed.frame.minX, accuracy: 0.001)
        XCTAssertLessThan(smaller.frame.height, placed.frame.height)
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
