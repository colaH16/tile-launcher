import XCTest
@testable import DeckCore

final class RecentWindowPolicyTests: XCTestCase {
    let displays = [CGRect(x: 0, y: 0, width: 1920, height: 1080),
                    CGRect(x: -1440, y: -300, width: 1440, height: 900)]

    func testLocationIsIndependentOfAppAppearance() {
        let current = CGRect(x: 100, y: 100, width: 500, height: 400)
        let other = CGRect(x: -1000, y: -100, width: 700, height: 500)
        XCTAssertEqual(RecentWindowPolicy.location(desktop: .current, bounds: current, displays: displays, activeDisplay: 0), .activeDisplay)
        XCTAssertEqual(RecentWindowPolicy.location(desktop: .current, bounds: other, displays: displays, activeDisplay: 0), .otherVisibleDisplay)
        XCTAssertEqual(RecentWindowPolicy.location(desktop: .other, bounds: current, displays: displays, activeDisplay: 0), .hidden)
        XCTAssertEqual(RecentWindowPolicy.location(desktop: .current, bounds: other, displays: displays, activeDisplay: 1), .activeDisplay)
        XCTAssertEqual(RecentWindowLocation.activeDisplay.size, .wide)
        XCTAssertEqual(RecentWindowLocation.otherVisibleDisplay.size, .square)
        XCTAssertEqual(RecentWindowLocation.hidden.size, .application)
    }

    func testSpanningWindowsUseLargestIntersectionInCGCoordinates() {
        XCTAssertEqual(RecentWindowPolicy.display(containing: CGRect(x: -150, y: 100, width: 700, height: 400), displays: displays), 0)
        XCTAssertEqual(RecentWindowPolicy.display(containing: CGRect(x: -650, y: -100, width: 700, height: 400), displays: displays), 1)
        XCTAssertNil(RecentWindowPolicy.display(containing: CGRect(x: 4000, y: 0, width: 100, height: 100), displays: displays))
        XCTAssertNil(RecentWindowPolicy.display(containing: nil, displays: displays))
        XCTAssertNil(RecentWindowPolicy.display(containing: .infinite, displays: displays))
    }

    func testUnknownLocationIsNotAWindowlessApplicationOrAnActiveMonitor() {
        XCTAssertEqual(RecentWindowPolicy.location(desktop: .current, bounds: nil, displays: displays, activeDisplay: 0), .visibleUnknownDisplay)
        XCTAssertEqual(RecentWindowPolicy.location(desktop: .current, bounds: displays[0], displays: displays, activeDisplay: nil), .visibleUnknownDisplay)
        XCTAssertEqual(RecentWindowPolicy.location(desktop: .unknown, bounds: displays[0], displays: displays, activeDisplay: 0), .unknown)
        XCTAssertEqual(RecentWindowLocation.visibleUnknownDisplay.size, .square)
    }

    func testNonconsecutiveAppRepeatsAndWindowlessException() {
        XCTAssertEqual(RecentWindowPolicy.firstAppearances(apps: ["T", "S", "T", "F", "S", "USB", "USB"],
            applications: [false, false, false, false, false, true, false]),
                       [true, true, false, true, false, false, true])
        XCTAssertEqual(RecentWindowPolicy.firstAppearances(apps: [String](), applications: []), [])
        // A single-window activation changes the first occurrence without grouping.
        XCTAssertEqual(RecentWindowPolicy.firstAppearances(apps: ["T", "T", "S", "F", "S"],
            applications: [false, false, false, false, false]), [true, false, true, true, false])
    }

    func testNativeGeometryScalesTilesInsideUnscaledOuterMargins() {
        for scale in [CGFloat(1.3), CGFloat(1.4)] {
            for compact in [false, true] {
                let base = DeckGeometry(width: 1120, compact: compact, scale: 1.3)
                let scaled = DeckGeometry(width: 1120, compact: compact, scale: scale)
                XCTAssertEqual(scaled.windowColumns, base.windowColumns)
                XCTAssertEqual(scaled.gap, base.gap)
                XCTAssertEqual(scaled.menuWidth + scaled.windowWidth + (compact ? 0 : DeckSpacing.columns),
                               1120 * scale - 2 * DeckSpacing.edge, accuracy: 0.001)
                XCTAssertGreaterThanOrEqual(scaled.unit, base.unit)
            }
            let base = RegisteredGridGeometry(width: 1120, scale: 1.3)
            let scaled = RegisteredGridGeometry(width: 1120, scale: scale)
            XCTAssertEqual(base.columns, scaled.columns)
            XCTAssertEqual(base.gap, scaled.gap)
            XCTAssertEqual(CGFloat(scaled.columns) * scaled.side + CGFloat(scaled.columns - 1) * scaled.gap,
                           1120 * scale - 2 * DeckSpacing.edge, accuracy: 0.001)
        }
    }
}
