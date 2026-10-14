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
                let position = tile.row * columns + tile.column
                XCTAssertGreaterThan(position, previous)
                previous = position
                XCTAssertLessThanOrEqual(tile.column + tile.width, columns)
                for y in 0..<tile.height {
                    for x in 0..<tile.width { XCTAssertTrue(used.insert((tile.row + y) * columns + tile.column + x).inserted) }
                }
            }
        }
    }
}
