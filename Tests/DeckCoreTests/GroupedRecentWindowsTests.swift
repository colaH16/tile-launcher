import XCTest
@testable import DeckCore

final class GroupedRecentWindowsTests: XCTestCase {
    func testSeparatedWindowsStayTogetherInTheirExistingMRUOrder() {
        let apps = ["terminal", "safari", "terminal", "finder", "safari"]
        XCTAssertEqual(GroupedRecentWindows.order(apps: apps, activeApp: "terminal"), [0, 2, 1, 4, 3])
        XCTAssertEqual(GroupedRecentWindows.order(apps: apps, activeApp: "safari"), [1, 4, 0, 2, 3])
        XCTAssertEqual(GroupedRecentWindows.order(apps: apps, activeApp: nil), [0, 2, 1, 4, 3])
    }

    func testMissingActiveAppDoesNotDisturbRecentGroupOrder() {
        XCTAssertEqual(GroupedRecentWindows.order(apps: [1, 2, 1, 3], activeApp: 99), [0, 2, 1, 3])
        XCTAssertEqual(GroupedRecentWindows.order(apps: [Int](), activeApp: 99), [])
    }

    func testAppIdentitiesDoNotMergeDifferentAppsWithMatchingDisplayNames() {
        let order = GroupedRecentWindows.order(apps: ["bundle.one", "bundle.two", "bundle.one"], activeApp: "bundle.two")
        XCTAssertEqual(order, [1, 0, 2])
    }

    func testOnlyOneActiveVisibleWindowIsWideAndVisibleFollowersStaySquare() {
        let sizes = GroupedRecentWindows.sizes(apps: ["T", "T", "T", "S", "S", "USB"],
            applications: [false, false, false, false, false, true],
            desktops: [.current, .current, .other, .current, .other, .current], activeApp: "T")
        XCTAssertEqual(sizes, [.wide, .square, .application, .square, .application, .application])
        XCTAssertEqual(sizes.filter { $0 == .wide }.count, 1)
    }

    func testRepresentativeSkipsHiddenWindowsWithoutChangingTheirOrder() {
        XCTAssertEqual(GroupedRecentWindows.sizes(apps: ["T", "T", "T"], applications: [false, false, false],
            desktops: [.other, .current, .current], activeApp: "T"), [.application, .wide, .square])
    }

    func testWindowlessOrUnknownActiveAppCannotCreateALargeTile() {
        XCTAssertEqual(GroupedRecentWindows.sizes(apps: ["T", "S", "X"], applications: [true, false, false],
            desktops: [.current, .current, .unknown], activeApp: "T"), [.application, .square, .application])
        XCTAssertEqual(GroupedRecentWindows.sizes(apps: ["T", "S"], applications: [false, false],
            desktops: [.other, .current], activeApp: nil), [.application, .square])
    }

    func testLargeGroupedInventoryPreservesAllWindowIndicesAcrossAppSwitches() {
        let apps = (0..<1000).map { $0 % 13 }
        for active in [0, 7, 12] {
            let order = GroupedRecentWindows.order(apps: apps, activeApp: active)
            XCTAssertEqual(Set(order), Set(apps.indices))
            XCTAssertEqual(order.count, apps.count)
            XCTAssertEqual(apps[order[0]], active)
            for app in Set(apps) {
                XCTAssertEqual(order.filter { apps[$0] == app }, apps.indices.filter { apps[$0] == app })
            }
        }
    }
}
