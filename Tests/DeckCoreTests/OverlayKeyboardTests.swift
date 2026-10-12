import XCTest
@testable import DeckCore

final class OverlayKeyboardTests: XCTestCase {
    func testCommandBeforeHoldCompletesCancelsButAfterOpeningDoesNot() {
        var gesture = HoldGesture()
        XCTAssertEqual(gesture.flags(option: true, otherModifier: false), .arm)
        XCTAssertEqual(gesture.flags(option: true, otherModifier: true), .cancel)
        XCTAssertEqual(gesture.flags(option: false, otherModifier: false), .release)
        XCTAssertEqual(gesture.flags(option: true, otherModifier: false), .arm)
        XCTAssertEqual(gesture.flags(option: true, otherModifier: true, overlayVisible: true), .none)
        XCTAssertEqual(gesture.flags(option: true, otherModifier: false, overlayVisible: true), .none)
        XCTAssertEqual(gesture.flags(option: false, otherModifier: false, overlayVisible: true), .release)
    }
    func testOptionPressWhilePinnedDoesNotStartAnotherHoldTimer() {
        var gesture = HoldGesture()
        XCTAssertEqual(gesture.flags(option: true, otherModifier: false, overlayVisible: true), .none)
        XCTAssertEqual(gesture.flags(option: false, otherModifier: false, overlayVisible: true), .release)
    }
    func testSettingsAndCloseAcceptOptionStillHeld() {
        for modifiers: OverlayShortcut.Modifiers in [.command, [.option, .command]] {
            XCTAssertEqual(OverlayShortcut.resolve(keyCode: 43, modifiers: modifiers), .settings)
            XCTAssertEqual(OverlayShortcut.resolve(keyCode: 13, modifiers: modifiers), .close)
        }
        XCTAssertEqual(OverlayShortcut.resolve(keyCode: 53, modifiers: .option), .close)
        XCTAssertNil(OverlayShortcut.resolve(keyCode: 43, modifiers: [.command, .shift]))
        XCTAssertNil(OverlayShortcut.resolve(keyCode: 43, modifiers: .option))
    }
    func testPinOnlyUsesOptionXLeavingSpaceAndOtherCombinationsAlone() {
        XCTAssertEqual(OverlayShortcut.resolve(keyCode: 7, modifiers: .option), .pin)
        XCTAssertNil(OverlayShortcut.resolve(keyCode: 7, modifiers: []))
        XCTAssertNil(OverlayShortcut.resolve(keyCode: 7, modifiers: [.option, .command]))
        XCTAssertNil(OverlayShortcut.resolve(keyCode: 49, modifiers: .option))
        XCTAssertNil(OverlayShortcut.resolve(keyCode: 0, modifiers: .option))
        let presentation = OverlayPresentation()
        presentation.pin()
        presentation.pin()
        XCTAssertFalse(presentation.dismisses(for: .release))
        XCTAssertTrue(presentation.dismisses(for: .escape))
    }
}
