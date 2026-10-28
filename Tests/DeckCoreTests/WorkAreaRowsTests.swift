import XCTest
import CoreGraphics
@testable import DeckCore

final class WorkAreaRowsTests: XCTestCase {
    func testOnlyOverflowShowsFourthRowPeek() {
        for (count, expected): (Int, CGFloat) in [(0, 1), (3, 1), (6, 2), (9, 3), (10, 3.3), (100, 3.3)] {
            XCTAssertEqual(WorkAreaRows.visible(menuSpans: [], windowSizes: Array(repeating: .wide, count: count),
                windowColumns: 6, compact: false), expected)
        }
    }
    func testMenuCanDetermineHeightEvenWhenWindowsAreShorter() {
        XCTAssertEqual(WorkAreaRows.visible(menuSpans: Array(repeating: 1, count: 9),
            windowSizes: [.wide], windowColumns: 6, compact: false), 3)
        XCTAssertEqual(WorkAreaRows.visible(menuSpans: Array(repeating: 2, count: 7),
            windowSizes: [.wide], windowColumns: 6, compact: false), 3.3)
    }
    func testWindowsCanDetermineHeightWhenMenusAreShorter() {
        XCTAssertEqual(WorkAreaRows.visible(menuSpans: [1],
            windowSizes: Array(repeating: .square, count: 13), windowColumns: 6, compact: false), 3)
    }
    func testSmallTilesUseVerticalPairsAndRoundOnlyLastOccupiedBand() {
        for (count, expected): (Int, CGFloat) in [(24, 1), (25, 2), (48, 2), (49, 3), (73, 3.3)] {
            XCTAssertEqual(WorkAreaRows.visible(menuSpans: [], windowSizes: Array(repeating: .application, count: count),
                windowColumns: 6, compact: false), expected)
        }
    }
    func testHiddenMenusDoNotMakeCompactPanelTaller() {
        XCTAssertEqual(WorkAreaRows.visible(menuSpans: Array(repeating: 2, count: 20),
            windowSizes: [.square], windowColumns: 4, compact: true), 1)
    }
    func testPanelShrinksAndRegrowsWithoutLeavingEmptyRowOrMovingTopEdge() {
        let screen = CGRect(x: -2560, y: 0, width: 2560, height: 1056)
        let base = PanelLayout.calculate(visibleFrame: screen, cursor: CGPoint(x: -1200, y: 500), scale: 1.3)
            .fittingContent(registeredCount: 39, workRows: 3.3)
        let short = base.refittingContent(registeredCount: 39, visibleFrame: screen, workRows: 1)
        XCTAssertLessThan(short.frame.height, base.frame.height - 200)
        XCTAssertEqual(short.frame.maxY, base.frame.maxY, accuracy: 0.001)
        let room = short.frame.height - DeckSpacing.chrome(compact: short.compact, scale: short.scale)
        let content = DeckContentLayout(width: short.contentSize.width, availableHeight: room,
            registeredCount: 39, compact: short.compact, scale: short.scale, workRows: 1)
        let geometry = DeckGeometry(width: short.contentSize.width, compact: short.compact, scale: short.scale)
        XCTAssertEqual(content.workHeight, (geometry.viewport(rows: 1) + DeckSpacing.workHeader()).rounded(.up), accuracy: 0.001)
        XCTAssertLessThan(room - content.workHeight - content.registeredHeight - content.gap, 1.01)
        XCTAssertEqual(short.refittingContent(registeredCount: 39, visibleFrame: screen, workRows: 3.3).frame, base.frame)
    }
}
