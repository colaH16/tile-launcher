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
    func testKnownIdentifierMismatchRejectsBeforeCanonicalizingPaths() {
        var pathReads = 0, executableReads = 0
        XCTAssertFalse(identity.matches(bundleID: "authentication-agent",
                                        bundlePath: { pathReads += 1; return "/Apps/STP.app" },
                                        executablePath: { executableReads += 1; return "/Apps/STP.app/Contents/MacOS/Browser" }))
        XCTAssertFalse(identity.matches(bundleID: nil,
                                        bundlePath: { pathReads += 1; return "/Apps/STP.app" },
                                        executablePath: { executableReads += 1; return "/Apps/STP.app/Contents/MacOS/Browser" }))
        XCTAssertEqual(pathReads, 0)
        XCTAssertEqual(executableReads, 0)
        // The same identifier still requires both canonical paths.
        XCTAssertTrue(identity.matches(bundleID: "browser",
                                       bundlePath: { pathReads += 1; return "/Apps/STP.app" },
                                       executablePath: { executableReads += 1; return "/Apps/STP.app/Contents/MacOS/Browser" }))
        XCTAssertEqual(pathReads, 1)
        XCTAssertEqual(executableReads, 1)
        // A different bundle path stops before the executable is read.
        XCTAssertFalse(identity.matches(bundleID: "browser",
                                        bundlePath: { pathReads += 1; return "/Other/STP.app" },
                                        executablePath: { executableReads += 1; return "/Other/STP.app/Contents/MacOS/Browser" }))
        XCTAssertEqual(executableReads, 1)
    }
    func testUnknownExpectedIdentifierStillComparesPathsAndExecutable() {
        let noID = ApplicationLaunchIdentity(bundlePath: "/Apps/App.app", bundleID: nil, executablePath: "/Apps/App.app/run")
        var reads = 0
        // Any reported identifier is acceptable when the bundle declares none.
        XCTAssertTrue(noID.matches(bundleID: "reported.by.process",
                                   bundlePath: { reads += 1; return "/Apps/App.app" },
                                   executablePath: { reads += 1; return "/Apps/App.app/run" }))
        XCTAssertEqual(reads, 2)
        XCTAssertFalse(noID.matches(bundleID: nil, bundlePath: { "/Apps/App.app" }, executablePath: { "/Apps/App.app/helper" }))
        XCTAssertFalse(noID.matches(bundleID: nil, bundlePath: { "/Copy/App.app" }, executablePath: { "/Copy/App.app/run" }))
        // Eager and lazy forms keep the same rule.
        XCTAssertTrue(noID.matches(bundlePath: "/Apps/App.app", bundleID: "reported.by.process", executablePath: "/Apps/App.app/run"))
    }
    func testNewProcessFallbackNeedsKnownIdentifierAndMainExecutableName() {
        // An alternate or translocated copy may run under another path.
        XCTAssertTrue(identity.admitsNewProcess(bundleID: "browser", executableName: { "Browser" }))
        XCTAssertFalse(identity.admitsNewProcess(bundleID: "browser", executableName: { "Helper" }))
        XCTAssertFalse(identity.admitsNewProcess(bundleID: "browser", executableName: { nil }))
        XCTAssertFalse(identity.admitsNewProcess(bundleID: "authentication-agent", executableName: { "Browser" }))
        let noExecutable = ApplicationLaunchIdentity(bundlePath: "/Apps/App.app", bundleID: "app", executablePath: nil)
        XCTAssertTrue(noExecutable.admitsNewProcess(bundleID: "app", executableName: { "anything" }))
        let noID = ApplicationLaunchIdentity(bundlePath: "/Apps/App.app", bundleID: nil, executablePath: "/Apps/App.app/run")
        XCTAssertFalse(noID.admitsNewProcess(bundleID: nil, executableName: { "run" }))
    }
    func testNewProcessFallbackReadsExecutableOnlyAfterIdentifierMatches() {
        var reads = 0
        XCTAssertFalse(identity.admitsNewProcess(bundleID: "authentication-agent", executableName: { reads += 1; return "Browser" }))
        XCTAssertFalse(identity.admitsNewProcess(bundleID: nil, executableName: { reads += 1; return "Browser" }))
        let noID = ApplicationLaunchIdentity(bundlePath: "/Apps/App.app", bundleID: nil, executablePath: "/Apps/App.app/run")
        XCTAssertFalse(noID.admitsNewProcess(bundleID: "reported", executableName: { reads += 1; return "run" }))
        XCTAssertEqual(reads, 0)
        // The same identifier still compares the main executable name.
        XCTAssertTrue(identity.admitsNewProcess(bundleID: "browser", executableName: { reads += 1; return "Browser" }))
        XCTAssertFalse(identity.admitsNewProcess(bundleID: "browser", executableName: { reads += 1; return "AuthAgent" }))
        XCTAssertEqual(reads, 2)
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
