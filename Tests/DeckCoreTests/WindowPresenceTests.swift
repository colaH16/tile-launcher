import XCTest
@testable import DeckCore

final class WindowPresenceTests: XCTestCase {
    func testLargeInventoryRendersOnlyViewportAndOverscanWithoutTruncatingHistory() {
        let placements = RecentTileArrangement.place(sizes: Array(repeating: .wide, count: 1000), columns: 12)
        let start = RecentTileArrangement.visible(placements, module: 45, gap: 8, offset: 0, viewport: 350)
        let middle = RecentTileArrangement.visible(placements, module: 45, gap: 8, offset: 2500, viewport: 350)
        XCTAssertLessThan(start.count, 30)
        XCTAssertLessThan(middle.count, 30)
        XCTAssertEqual(start.first?.index, 0)
        XCTAssertGreaterThan(middle.first!.index, start.last!.index)
        let lastOffset = CGFloat(placements.last!.row) * 53
        let end = RecentTileArrangement.visible(placements, module: 45, gap: 8, offset: lastOffset, viewport: 350)
        XCTAssertEqual(end.last?.index, 999)
        XCTAssertEqual(placements.count, 1000)
    }
    func testWindowlessNeedsSuccessfulAXAndCompleteInventory() {
        XCTAssertTrue(WindowPresence.applicationOnly(axComplete: true, inventoryComplete: true, accessibleWindows: 0, serverCandidates: 0))
        for (ax, inventory, windows, server) in [(false, true, 0, 0), (true, false, 0, 0), (true, true, 1, 0), (true, true, 0, 1)] {
            XCTAssertFalse(WindowPresence.applicationOnly(axComplete: ax, inventoryComplete: inventory, accessibleWindows: windows, serverCandidates: server))
        }
    }
    func testTransparentUtilitySurfaceDoesNotCreateAnOffDesktopWindow() {
        let bounds = CGRect(x: 0, y: 0, width: 600, height: 400)
        XCTAssertFalse(WindowPresence.serverCandidate(alpha: 0, bounds: bounds))
        XCTAssertFalse(WindowPresence.serverCandidate(alpha: .nan, bounds: bounds))
        XCTAssertTrue(WindowPresence.serverCandidate(alpha: 1, bounds: bounds))
        XCTAssertFalse(WindowPresence.serverCandidate(alpha: 1, bounds: CGRect(x: 0, y: 0, width: 20, height: 20)))
    }
    func testMixedSizePackingPreservesOrderAndDoesNotOverlap() {
        let sizes = RecentTileArrangement.sizes(apps: ["T", "T", "USB", "S", "Other"], applications: [false, false, true, false, true])
        XCTAssertEqual(sizes, [.wide, .square, .application, .wide, .application])
        for columns in [8, 12] {
            let placements = RecentTileArrangement.place(sizes: sizes, columns: columns)
            XCTAssertEqual(placements.map(\.index), Array(0..<sizes.count))
            var used = Set<Int>(), previous = -1
            for tile in placements {
                // Small pairs are top/bottom within one column, then move right.
                let position = (tile.row / 2) * columns * 2 + tile.column * 2 + tile.row % 2
                XCTAssertGreaterThan(position, previous)
                previous = position
                XCTAssertLessThanOrEqual(tile.column + tile.width, columns)
                for y in 0..<tile.height {
                    for x in 0..<tile.width { XCTAssertTrue(used.insert((tile.row + y) * columns + tile.column + x).inserted) }
                }
            }
        }
    }
    func testConsecutiveWindowsAreSmallButNewAppStartsWithASquare() {
        let sizes = RecentTileArrangement.sizes(apps: ["T", "T", "T", "S", "T", "USB", "USB"],
                                               applications: [false, false, false, false, false, true, false],
                                               consecutiveSmall: true)
        XCTAssertEqual(sizes, [.square, .application, .application, .square, .square, .application, .square])
    }
    func testTwoSmallWindowsStackVerticallyBeforeNextSquare() {
        let p = RecentTileArrangement.place(sizes: [.square, .application, .application, .square], columns: 8)
        XCTAssertEqual(p.map(\.row), [0, 0, 1, 0])
        XCTAssertEqual(p.map(\.column), [0, 2, 2, 3])
        XCTAssertEqual(p.map(\.index), [0, 1, 2, 3])
    }
    func testNextBandCannotMoveUpIntoOddSmallTileGap() {
        let p = RecentTileArrangement.place(sizes: [.application, .square, .square, .application, .square], columns: 4)
        XCTAssertEqual(p.map(\.row), [0, 0, 2, 2, 4])
        XCTAssertEqual(p.map(\.column), [0, 1, 0, 2, 0])
        // The cell below the first small tile and right edge of band zero stay empty.
        XCTAssertFalse(p.dropFirst().contains { $0.row == 1 })
    }
    func testSmallPairAtRightEdgeStaysTogetherBeforeWrapping() {
        let p = RecentTileArrangement.place(sizes: [.square, .application, .application, .application, .application, .square], columns: 4)
        XCTAssertEqual(p.map(\.row), [0, 0, 1, 0, 1, 2])
        XCTAssertEqual(p.map(\.column), [0, 2, 2, 3, 3, 0])
    }
    func testDenseMixedInventoryNeverOverlapsOrBackfillsPreviousBands() {
        let sizes: [RecentTileSize] = (0..<1000).map { $0 % 7 < 4 ? .application : $0 % 7 == 4 ? .wide : .square }
        for columns in [4, 8, 12] {
            let p = RecentTileArrangement.place(sizes: sizes, columns: columns)
            var cells = Set<Int>(), previous = -1
            for tile in p {
                let position = (tile.row / 2) * columns * 2 + tile.column * 2 + tile.row % 2
                XCTAssertGreaterThan(position, previous)
                previous = position
                XCTAssertLessThanOrEqual(tile.column + tile.width, columns)
                for y in 0..<tile.height {
                    for x in 0..<tile.width { XCTAssertTrue(cells.insert((tile.row + y) * columns + tile.column + x).inserted) }
                }
            }
            XCTAssertEqual(p.map(\.index), Array(sizes.indices))
        }
    }
}
