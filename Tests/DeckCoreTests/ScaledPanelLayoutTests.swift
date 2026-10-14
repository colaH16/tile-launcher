import XCTest
import CoreGraphics
@testable import DeckCore

final class ScaledPanelLayoutTests: XCTestCase {
    func testLargeScreenKeepsLogicalLayoutAndEnlargesEveryDimension() {
        let screen = CGRect(x: -2560, y: -200, width: 2560, height: 1440)
        let original = PanelLayout.calculate(visibleFrame: screen, cursor: .zero).fittingContent(registeredCount: 18)
        let enlarged = PanelLayout.calculate(visibleFrame: screen, cursor: .zero, scale: 1.4).fittingContent(registeredCount: 18)
        XCTAssertEqual(enlarged.scale, 1.4)
        XCTAssertEqual(enlarged.frame.width, original.frame.width * 1.4, accuracy: 0.001)
        XCTAssertEqual(enlarged.frame.height, original.frame.height * 1.4, accuracy: 0.001)
        XCTAssertEqual(enlarged.contentSize.width, original.frame.width, accuracy: 0.001)
        XCTAssertEqual(enlarged.contentSize.height, original.frame.height, accuracy: 0.001)
        XCTAssertEqual(enlarged.columns, original.columns)
    }

    func testScreenBoundsMarginsAndCompleteRegisteredRowAtEverySupportedSize() {
        for size in [CGSize(width: 3440, height: 1440), CGSize(width: 1920, height: 1080),
                     CGSize(width: 1440, height: 900), CGSize(width: 1280, height: 800),
                     CGSize(width: 1024, height: 768), CGSize(width: 560, height: 600), CGSize(width: 400, height: 300)] {
            for origin in [CGPoint.zero, CGPoint(x: -3440, y: -600)] {
                let screen = CGRect(origin: origin, size: size)
                for count in [0, 18, 36, 200] {
                    let layout = PanelLayout.calculate(visibleFrame: screen, cursor: screen.origin, scale: 1.4)
                        .fittingContent(registeredCount: count)
                    XCTAssertTrue(screen.contains(layout.frame))
                    XCTAssertTrue((1...1.4).contains(layout.scale))
                    XCTAssertLessThanOrEqual(layout.frame.width, 1568.001)
                    XCTAssertLessThanOrEqual(layout.frame.height, 1176.001)
                    guard layout.supported else { continue }
                    let room = layout.contentSize.height - DeckSpacing.chrome(compact: layout.compact)
                    let body = DeckContentLayout(width: layout.contentSize.width, availableHeight: room,
                                                 registeredCount: count, compact: layout.compact)
                    let minimum = RegisteredGridGeometry(width: layout.contentSize.width).shelfHeight(count: 1, maximumRows: 1)
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
}
