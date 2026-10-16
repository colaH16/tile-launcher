import XCTest
@testable import DeckCore

final class OverlayDragGeometryTests: XCTestCase {
    func testScrolledTilesCannotBlockHeaderOrFooterDragging() {
        let viewport = CGRect(x: 10, y: 60, width: 300, height: 200)
        let tile = CGRect(x: 20, y: 20, width: 90, height: 100)
        let visible = OverlayDragGeometry.clipped(tile, to: [viewport])!
        let panel = CGRect(x: 0, y: 0, width: 320, height: 300)
        XCTAssertTrue(OverlayDragGeometry.canBegin(at: CGPoint(x: 40, y: 30), bounds: panel, excluding: [visible]))
        XCTAssertFalse(OverlayDragGeometry.canBegin(at: CGPoint(x: 40, y: 80), bounds: panel, excluding: [visible]))
        XCTAssertNil(OverlayDragGeometry.clipped(tile.offsetBy(dx: 0, dy: -200), to: [viewport]))
        XCTAssertNil(OverlayDragGeometry.clipped(tile.offsetBy(dx: 0, dy: 300), to: [viewport]))
    }
    func testNestedViewportsAndOutsidePanel() {
        let clipped = OverlayDragGeometry.clipped(CGRect(x: -20, y: -20, width: 100, height: 100), to: [
            CGRect(x: 0, y: 0, width: 200, height: 200), CGRect(x: 30, y: 30, width: 200, height: 200)])
        XCTAssertEqual(clipped, CGRect(x: 30, y: 30, width: 50, height: 50))
        XCTAssertFalse(OverlayDragGeometry.canBegin(at: CGPoint(x: -1, y: 20),
            bounds: CGRect(x: 0, y: 0, width: 100, height: 100), excluding: []))
    }
}
