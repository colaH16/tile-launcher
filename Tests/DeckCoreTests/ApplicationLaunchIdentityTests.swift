import XCTest
@testable import DeckCore

final class ApplicationLaunchIdentityTests: XCTestCase {
    let identity = ApplicationLaunchIdentity(bundlePath: "/Apps/STP.app", bundleID: "browser",
                                              executablePath: "/Apps/STP.app/Contents/MacOS/Browser")
    func testSharedBundleAuthenticationAgentCannotOwnLaunch() {
        XCTAssertFalse(identity.matches(bundlePath: "/Apps/STP.app", bundleID: "authentication-agent",
                                        executablePath: "/Apps/STP.app/Contents/MacOS/AuthAgent"))
        XCTAssertTrue(identity.matches(bundlePath: "/Apps/STP.app", bundleID: "browser",
                                       executablePath: "/Apps/STP.app/Contents/MacOS/Browser"))
    }
    func testSameIDHelperOrDifferentAppCopyIsNotExactTarget() {
        XCTAssertFalse(identity.matches(bundlePath: "/Apps/STP.app", bundleID: "browser",
                                        executablePath: "/Apps/STP.app/Contents/MacOS/Helper"))
        XCTAssertFalse(identity.matches(bundlePath: "/Other/STP.app", bundleID: "browser",
                                        executablePath: "/Other/STP.app/Contents/MacOS/Browser"))
    }
    func testMissingMetadataIsNotPermissionToAttachAnyProcess() {
        let unknown = ApplicationLaunchIdentity(bundlePath: "/Apps/Unknown.app", bundleID: nil, executablePath: nil)
        XCTAssertFalse(unknown.matches(bundlePath: "/Apps/Unknown.app", bundleID: nil, executablePath: nil))
    }
    func testExecutableIdentifiesAppWithoutBundleID() {
        let noID = ApplicationLaunchIdentity(bundlePath: "/Apps/App.app", bundleID: nil, executablePath: "/Apps/App.app/run")
        XCTAssertTrue(noID.matches(bundlePath: "/Apps/App.app", bundleID: nil, executablePath: "/Apps/App.app/run"))
        XCTAssertFalse(noID.matches(bundlePath: "/Apps/App.app", bundleID: nil, executablePath: "/Apps/App.app/helper"))
    }
    func testCachedActiveFlagAloneCannotTriggerCooperativeHandoff() {
        XCTAssertEqual(WindowActivationHandoff.evaluate(sourceActive: true, sourceFrontmost: false, targetActive: true, attempt: 1), .wait)
        XCTAssertEqual(WindowActivationHandoff.evaluate(sourceActive: true, sourceFrontmost: true, targetActive: true, attempt: 1), .wait)
        XCTAssertEqual(WindowActivationHandoff.evaluate(sourceActive: true, sourceFrontmost: true, targetActive: false, attempt: 0), .wait)
        XCTAssertEqual(WindowActivationHandoff.evaluate(sourceActive: true, sourceFrontmost: true, targetActive: false, attempt: 1), .cooperative)
    }
    func testHandoffIsBoundedAndDoesNotAssumeSuccessfulSourceActivation() {
        XCTAssertEqual(WindowActivationHandoff.evaluate(sourceActive: false, sourceFrontmost: false, targetActive: true, attempt: 8), .fallback)
        XCTAssertEqual(WindowActivationHandoff.evaluate(sourceActive: true, sourceFrontmost: false, targetActive: true, attempt: 8), .fallback)
    }
}
