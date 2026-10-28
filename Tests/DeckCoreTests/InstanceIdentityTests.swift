import XCTest
@testable import DeckCore

final class InstanceIdentityTests: XCTestCase {
    private let first = ProcessIdentity(pid: 10, startedSeconds: 100, startedMicroseconds: 5)
    private let later = ProcessIdentity(pid: 11, startedSeconds: 100, startedMicroseconds: 6)
    private let v1 = AppBuild(version: "0.1.0", build: "1", fingerprint: "aaa")
    private let v2 = AppBuild(version: "0.1.1", build: "2", fingerprint: "bbb")

    func testSameBuildKeepsExistingProcess() {
        XCTAssertEqual(InstanceOwner(process: first, build: v1).decision(
            for: InstanceOwner(process: later, build: v1)), .keepExisting)
    }
    func testLastLaunchWinsForBothUpgradeAndDowngrade() {
        for (old, new) in [(v1, v2), (v2, v1)] {
            XCTAssertEqual(InstanceOwner(process: first, build: old).decision(
                for: InstanceOwner(process: later, build: new)), .replaceExisting)
        }
    }
    func testLocalRebuildWithSameDisplayVersionReplacesExisting() {
        let rebuilt = AppBuild(version: v1.version, build: v1.build, fingerprint: "changed")
        XCTAssertEqual(InstanceOwner(process: first, build: v1).decision(
            for: InstanceOwner(process: later, build: rebuilt)), .replaceExisting)
    }
    func testOlderLaunchCannotDisplaceNewerOneWhenLockOrderIsReversed() {
        XCTAssertEqual(InstanceOwner(process: later, build: v1).decision(
            for: InstanceOwner(process: first, build: v2)), .keepExisting)
    }
    func testOwnerRoundTripAndPIDReuseValidation() throws {
        let owner = InstanceOwner(process: first, build: v1)
        XCTAssertEqual(try JSONDecoder().decode(InstanceOwner.self, from: JSONEncoder().encode(owner)), owner)
        XCTAssertNotEqual(first, ProcessIdentity(pid: first.pid, startedSeconds: 101, startedMicroseconds: 5))
        let current = try XCTUnwrap(ProcessIdentity.read(pid: ProcessInfo.processInfo.processIdentifier))
        XCTAssertEqual(current, ProcessIdentity.read(pid: current.pid))
        XCTAssertGreaterThan(current.startedSeconds, 0)
    }
}
