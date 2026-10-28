import XCTest
@testable import DeckCore

final class ProfileNavigationTests: XCTestCase {
    let profiles = ["default", "work", "dev"].map { LauncherProfile(id: $0, name: $0) }

    func testNavigationWrapsInStoredOrderWithoutChangingProfiles() {
        XCTAssertEqual(ProfileNavigation.target(in: profiles, currentID: "default", step: -1)?.id, "dev")
        XCTAssertEqual(ProfileNavigation.target(in: profiles, currentID: "dev", step: 1)?.id, "default")
        XCTAssertEqual(ProfileNavigation.target(in: [profiles[1], profiles[0], profiles[2]], currentID: "work", step: 1)?.id, "default")
        XCTAssertNil(ProfileNavigation.target(in: [], currentID: "default", step: 1))
        XCTAssertNil(ProfileNavigation.target(in: [profiles[0]], currentID: "default", step: 1))
        XCTAssertNil(ProfileNavigation.target(in: profiles, currentID: "missing", step: 1))
    }
    func testTemporaryProfileResetsWithoutUnpinningOrTouchingWindowOrderDuringUse() {
        let presentation = OverlayPresentation()
        presentation.pin()
        let windowID = UUID()
        presentation.windowDesktops = [windowID: .current]
        presentation.profile = profiles[1]
        XCTAssertTrue(presentation.isPinned)
        XCTAssertEqual(presentation.windowDesktops, [windowID: .current])
        presentation.reset()
        XCTAssertNil(presentation.profile)
    }
    func testSingleSwipeAndMomentumDoNotSkipProfiles() {
        var gesture = ProfileScrollGesture()
        XCTAssertNil(gesture.scroll(x: 20, y: 1, precise: true, inverted: false, time: 1,
                                    began: true, ended: false, phased: true, momentum: false).step)
        XCTAssertEqual(gesture.scroll(x: 30, y: 1, precise: true, inverted: false, time: 1.02,
                                     began: false, ended: false, phased: true, momentum: false).step, 1)
        XCTAssertNil(gesture.scroll(x: 200, y: 0, precise: true, inverted: false, time: 1.1,
                                   began: false, ended: true, phased: true, momentum: false).step)
        let momentum = gesture.scroll(x: 300, y: 0, precise: true, inverted: false, time: 1.2,
                                      began: false, ended: false, phased: false, momentum: true)
        XCTAssertNil(momentum.step)
        XCTAssertTrue(momentum.consume)
        XCTAssertEqual(gesture.scroll(x: -60, y: 0, precise: true, inverted: false, time: 2,
                                     began: true, ended: false, phased: true, momentum: false).step, -1)
    }
    func testNaturalScrollingAndTraditionalScrollingHaveSamePhysicalDirection() {
        for inverted in [false, true] {
            var gesture = ProfileScrollGesture()
            XCTAssertEqual(gesture.scroll(x: inverted ? -60 : 60, y: 0, precise: true, inverted: inverted,
                                         time: 1, began: true, ended: false, phased: true, momentum: false).step, 1)
        }
    }
    func testVerticalAndDiagonalJitterDoNotChangeProfiles() {
        var gesture = ProfileScrollGesture()
        XCTAssertFalse(gesture.scroll(x: 7, y: 20, precise: true, inverted: false, time: 1,
                                      began: true, ended: false, phased: true, momentum: false).consume)
        XCTAssertNil(gesture.scroll(x: 90, y: 1, precise: true, inverted: false, time: 1.02,
                                    began: false, ended: false, phased: true, momentum: false).step)
    }
    func testWheelBurstsOnlyAdvanceOnceAndAllowLaterScroll() {
        var gesture = ProfileScrollGesture()
        for (time, expected): (Double, Int?) in [(1, 1), (1.1, nil), (1.2, nil), (1.6, 1)] {
            XCTAssertEqual(gesture.scroll(x: 1, y: 0, precise: false, inverted: false, time: time,
                                         began: false, ended: false, phased: false, momentum: false).step, expected)
        }
    }
    func testCancelledSwipeCannotCommitAProfile() {
        var gesture = ProfileScrollGesture()
        _ = gesture.scroll(x: 30, y: 0, precise: true, inverted: false, time: 1,
                           began: true, ended: false, phased: true, momentum: false)
        XCTAssertNil(gesture.scroll(x: 100, y: 0, precise: true, inverted: false, time: 1.1,
                                   began: false, ended: true, phased: true, momentum: false, cancelled: true).step)
    }
}
