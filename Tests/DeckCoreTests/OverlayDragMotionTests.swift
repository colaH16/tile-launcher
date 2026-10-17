import XCTest
@testable import DeckCore

final class OverlayDragMotionTests: XCTestCase {
    func testSevenPhysicalPixelsPreserveOriginalGrabAtBothScales() {
        for scale: CGFloat in [1, 2] {
            var drag = OverlayDragMotion(start: CGPoint(x: 30, y: 40), origin: CGPoint(x: 100, y: 200), backingScale: scale)
            XCTAssertNil(drag.advance(to: CGPoint(x: 30 + 6.9 / scale, y: 40)))
            XCTAssertFalse(drag.committed)
            XCTAssertEqual(drag.advance(to: CGPoint(x: 30 + 7 / scale, y: 40)), CGPoint(x: 100 + 7 / scale, y: 200))
            XCTAssertTrue(drag.committed)
            XCTAssertEqual(drag.advance(to: CGPoint(x: 31, y: 39)), CGPoint(x: 101, y: 199))
        }
    }
    func testDiagonalOvershootUsesEntireDisplacementAndReleaseCannotBegin() {
        var drag = OverlayDragMotion(start: .zero, origin: CGPoint(x: 100, y: 200), backingScale: 1)
        XCTAssertEqual(drag.advance(to: CGPoint(x: 6, y: 8)), CGPoint(x: 106, y: 208))
        XCTAssertEqual(drag.advance(to: .zero), CGPoint(x: 100, y: 200))
        XCTAssertTrue(drag.committed)
        var released = OverlayDragMotion(start: .zero, origin: .zero, backingScale: 1)
        XCTAssertNil(released.advance(to: CGPoint(x: 50, y: 50), mayBegin: false))
        XCTAssertFalse(released.committed)
    }
}
