import XCTest
@testable import DeckCore

final class SettingsSyncLifecycleTests: XCTestCase {
    private typealias L = SettingsSyncLifecycle
    private func projection(theme: String = "classic", commands: [MenuCommand] = []) -> SettingsSyncProjection {
        .init(preferences: ["theme": .text(theme), "showAppSettings": .bool(true)], commands: commands)
    }

    func testOnlyAReadableDifferentAccountOrSignOutIsAChange() {
        XCTAssertEqual(L.accountDecision(previous: "a", status: .available("a")), .connect)
        XCTAssertEqual(L.accountDecision(previous: "a", status: .available("b")), .changed)
        XCTAssertEqual(L.accountDecision(previous: nil, status: .available("b")), .connect)
        XCTAssertEqual(L.accountDecision(previous: "a", status: .noAccount), .changed)
        XCTAssertEqual(L.accountDecision(previous: nil, status: .noAccount), .none)
        for transient: L.AccountStatus in [.available(nil), .temporarilyUnavailable, .couldNotDetermine, .restricted] {
            XCTAssertEqual(L.accountDecision(previous: "a", status: transient), .none, "\(transient)")
        }
    }

    func testOnlyAnAppDeletionRecreatesTheZone() {
        XCTAssertEqual(L.action(for: .deletedByApp), .recreate)
        for reason: L.ZoneDeletion in [.purgedByUser, .encryptedDataReset, .unknown] {
            XCTAssertEqual(L.action(for: reason), .stopWithoutResend)
        }
    }

    func testStartupUsesTheCommitCheckpointNotValuesAlone() {
        let journaled = projection(theme: "classic")
        // Older app restored exactly the previous value: checkpoint matches → external.
        XCTAssertEqual(L.startup(current: projection(theme: "glass"), observed: journaled,
                                 journalCommit: "n2", defaultsCheckpoint: "n2", managed: []), .externalEdit)
        // The defaults never received the last journal commit → replay.
        XCTAssertEqual(L.startup(current: projection(theme: "glass"), observed: journaled,
                                 journalCommit: "n2", defaultsCheckpoint: "n1", managed: []), .interruptedWrite)
        XCTAssertEqual(L.startup(current: projection(theme: "glass"), observed: journaled,
                                 journalCommit: "n2", defaultsCheckpoint: nil, managed: []), .interruptedWrite)
        // An earlier journal format without a nonce keeps this Mac's values.
        XCTAssertEqual(L.startup(current: projection(theme: "glass"), observed: journaled,
                                 journalCommit: nil, defaultsCheckpoint: nil, managed: []), .externalEdit)
        XCTAssertEqual(L.startup(current: journaled, observed: journaled,
                                 journalCommit: "n2", defaultsCheckpoint: "n1", managed: []), .consistent)
    }

    func testRuntimeHistoryAndUnsharedCollectedMenusAreNotEdits() {
        var manual = MenuCommand(appID: "test.app", appName: "Test", path: ["File", "Open"])
        let journaled = projection(commands: [manual])
        manual.recordUse(at: Date())
        var collected = MenuCommand(appID: "test.app", appName: "Test", path: ["File", "Collected"], isPinned: false)
        collected.isAutomatic = true
        XCTAssertEqual(L.startup(current: projection(commands: [manual, collected]), observed: journaled,
                                 journalCommit: "n", defaultsCheckpoint: "n", managed: [manual.id]), .consistent)
        var unpinned = manual; unpinned.isPinned = false
        XCTAssertEqual(L.startup(current: projection(commands: [unpinned]), observed: journaled,
                                 journalCommit: "n", defaultsCheckpoint: "n", managed: [manual.id]), .externalEdit)
    }

    func testExternalImportRecordsNoEditTime() {
        let command = MenuCommand(appID: "test.app", appName: "Test", path: ["File", "Open"])
        var replica = SettingsSyncReplica()
        let before = projection(commands: [command])
        replica.capture(before: nil, after: before, at: Date())
        var pinned = command; pinned.isPinned = false; pinned.symbol = "gear"
        let added = MenuCommand(appID: "test.app", appName: "Test", path: ["File", "Added"])
        replica.importExternal(before: before, after: projection(theme: "glass", commands: [pinned, added]))
        XCTAssertNil(replica.snapshot.preferences["theme"]?.stamp.date)
        XCTAssertEqual(replica.snapshot.preferences["theme"]?.value, .text("glass"))
        for menu in replica.snapshot.menus.values {
            XCTAssertNil(menu.presence.stamp.date); XCTAssertNil(menu.pinned.stamp.date)
            XCTAssertTrue(menu.icon.edits.allSatisfy { $0.stamp.date == nil })
        }
        XCTAssertTrue(replica.snapshot.orders.values.allSatisfy { $0.stamp.date == nil })
        XCTAssertEqual(replica.applying(to: projection(theme: "glass", commands: [pinned, added])).commands.first?.symbol, "gear")
    }

    func testExternalImportAtSequenceRolloverStillRecordsNoEditTime() {
        var replica = SettingsSyncReplica()
        replica.capture(before: nil, after: projection(), at: Date())
        replica.sequence = .max
        let device = replica.device
        replica.importExternal(before: projection(), after: projection(theme: "glass"))
        XCTAssertNotEqual(replica.device, device)
        XCTAssertNil(replica.snapshot.preferences["theme"]?.stamp.date)
    }

    /// Documented limitation: a value whose previous version already had a
    /// real edit time loses to that older copy in another Mac, because the
    /// external change has no time. Kept as a characterization test.
    func testLegacyImportLosesToAnEarlierTimedCopyElsewhere() throws {
        var replica = SettingsSyncReplica()
        replica.capture(before: nil, after: projection(), at: Date())
        replica.capture(before: projection(), after: projection(theme: "glass"), at: .init(timeIntervalSince1970: 100))
        let uploaded = replica.snapshot
        // An older version restores classic; the import has no time.
        replica.importExternal(before: projection(theme: "glass"), after: projection(theme: "classic"))
        XCTAssertEqual(replica.snapshot.preferences["theme"]?.value, .text("classic"))
        let merged = try replica.snapshot.merged(with: uploaded)
        XCTAssertEqual(merged.preferences["theme"]?.value, .text("glass"))
    }
}
