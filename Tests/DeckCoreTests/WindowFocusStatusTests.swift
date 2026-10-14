import XCTest
@testable import DeckCore

final class WindowFocusStatusTests: XCTestCase {
    func testActivationOfAnotherWindowIsNotSuccess() {
        XCTAssertEqual(WindowFocusStatus.evaluate(targetExists: true, frontmost: true, focused: false, desktop: .current, attempt: 0), .retry)
        XCTAssertEqual(WindowFocusStatus.evaluate(targetExists: true, frontmost: true, focused: false, desktop: .current, attempt: 7), .unconfirmed)
    }
    func testOffSpaceWindowMustActuallyBecomeVisible() {
        XCTAssertEqual(WindowFocusStatus.evaluate(targetExists: true, frontmost: true, focused: true, desktop: .other, attempt: 2), .retry)
        XCTAssertEqual(WindowFocusStatus.evaluate(targetExists: true, frontmost: true, focused: true, desktop: .current, attempt: 7), .confirmed)
    }
    func testBackgroundAppOrClosedWindowCannotClaimSuccess() {
        XCTAssertEqual(WindowFocusStatus.evaluate(targetExists: true, frontmost: false, focused: true, desktop: .current, attempt: 7), .unconfirmed)
        XCTAssertEqual(WindowFocusStatus.evaluate(targetExists: false, frontmost: true, focused: true, desktop: .current, attempt: 0), .closed)
    }
    func testMissingPrivateMetadataStillAllowsPublicAXConfirmation() {
        XCTAssertEqual(WindowFocusStatus.evaluate(targetExists: nil, frontmost: true, focused: true, desktop: .unknown, attempt: 1), .confirmed)
        XCTAssertEqual(WindowFocusStatus.evaluate(targetExists: nil, frontmost: true, focused: false, desktop: .unknown, attempt: 7), .unconfirmed)
    }
}
