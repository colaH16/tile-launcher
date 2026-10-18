import XCTest
@testable import DeckCore

final class SettingsSyncReplicaTests: XCTestCase {
    private func projection(_ commands: [MenuCommand], theme: String = "classic") -> SettingsSyncProjection {
        .init(preferences: ["theme": .text(theme), "showAppSettings": .bool(true)], commands: commands)
    }
    private func command(_ path: [String] = ["File", "Open"]) -> MenuCommand {
        .init(appID: "test.app", appName: "Test", path: path)
    }
    func testRuntimeUsageDoesNotBecomeUserEdit() throws {
        var replica = SettingsSyncReplica()
        let original = command(); let before = projection([original])
        replica.capture(before: nil, after: before, at: .init(timeIntervalSince1970: 10))
        let snapshot = replica.snapshot; let sequence = replica.sequence
        var used = original; used.recordUse(at: .init(timeIntervalSince1970: 20))
        replica.capture(before: before, after: projection([used]), at: .init(timeIntervalSince1970: 20))
        XCTAssertEqual(snapshot, replica.snapshot); XCTAssertEqual(sequence, replica.sequence)
    }
    func testAutomaticMenusAndLocalPreferencesNeverEnterRecords() {
        var automatic = command(); automatic.isAutomatic = true; automatic.isPinned = false
        var value = projection([automatic]); value.preferences["captureMenus"] = .bool(true)
        var replica = SettingsSyncReplica()
        replica.capture(before: nil, after: value, at: Date())
        XCTAssertTrue(replica.snapshot.menus.isEmpty)
        XCTAssertNil(replica.snapshot.preferences["captureMenus"])
    }
    func testInitialSameMenuKeepsLocalUUIDAndRecordsAliases() throws {
        let a = command(), b = command()
        var left = SettingsSyncReplica(), right = SettingsSyncReplica()
        left.capture(before: nil, after: projection([a]), at: Date())
        right.capture(before: nil, after: projection([b]), at: Date())
        XCTAssertTrue(left.legacyConflicts(with: right.snapshot).isEmpty)
        try left.mergeInitial(right.snapshot, preferLocal: nil, at: Date())
        try right.mergeInitial(left.snapshot, preferLocal: nil, at: Date())
        XCTAssertEqual(left.snapshot.combinedMenus.count, 1)
        XCTAssertEqual(right.snapshot.combinedMenus.count, 1)
        let local = left.applying(to: projection([a]))
        XCTAssertEqual(local.commands.map(\.id), [a.id])
        XCTAssertEqual(left.snapshot.canonicalMenuIDs, right.snapshot.canonicalMenuIDs)
    }
    func testSameMacDifferentCommandsAreNeverMerged() throws {
        let first = command(), second = command()
        var replica = SettingsSyncReplica()
        replica.capture(before: nil, after: projection([first, second]), at: Date())
        try replica.snapshot.reconcileMenuIdentities()
        XCTAssertEqual(replica.snapshot.combinedMenus.count, 2)
    }
    func testWeakPathCannotBridgeDifferentResourceIdentities() throws {
        var a = SettingsSyncReplica(), b = SettingsSyncReplica(), c = SettingsSyncReplica()
        a.capture(before: nil, after: projection([command()]), at: Date())
        b.capture(before: nil, after: projection([command()]), at: Date())
        c.capture(before: nil, after: projection([command()]), at: Date())
        let aid = a.snapshot.menus.keys.first!, cid = c.snapshot.menus.keys.first!
        a.snapshot.menus[aid]!.resourceIdentity = .init(appID: "test.app", archive: "Main", keys: ["first"])
        c.snapshot.menus[cid]!.resourceIdentity = .init(appID: "test.app", archive: "Main", keys: ["second"])
        var snapshot = try a.snapshot.merged(with: b.snapshot).merged(with: c.snapshot)
        try snapshot.reconcileMenuIdentities()
        XCTAssertEqual(snapshot.combinedMenus.count, 3)
    }
    func testLegacyChoiceTouchesOnlyConflicts() throws {
        var a = SettingsSyncReplica(), b = SettingsSyncReplica()
        a.capture(before: nil, after: projection([], theme: "classic"), at: Date())
        b.capture(before: nil, after: projection([], theme: "glass"), at: Date())
        let unchanged = a.snapshot.preferences["showAppSettings"]!
        XCTAssertEqual(a.legacyConflicts(with: b.snapshot), ["pref:theme"])
        try a.mergeInitial(b.snapshot, preferLocal: false, at: .init(timeIntervalSince1970: 30))
        XCTAssertEqual(a.snapshot.preferences["theme"]?.value, .text("glass"))
        XCTAssertEqual(a.snapshot.preferences["theme"]?.stamp.date, .init(timeIntervalSince1970: 30))
        XCTAssertNil(a.snapshot.preferences["showAppSettings"]?.stamp.date)
        XCTAssertEqual(a.snapshot.preferences["showAppSettings"]?.value, unchanged.value)
    }
    func testActualEditsAreNotLegacyConflicts() throws {
        var a = SettingsSyncReplica(), b = SettingsSyncReplica()
        a.capture(before: nil, after: projection([]), at: Date())
        b.capture(before: nil, after: projection([]), at: Date())
        b.capture(before: projection([]), after: projection([], theme: "glass"), at: .init(timeIntervalSince1970: 40))
        XCTAssertTrue(a.legacyConflicts(with: b.snapshot).isEmpty)
        try a.mergeInitial(b.snapshot, preferLocal: nil, at: Date())
        XCTAssertEqual(a.snapshot.preferences["theme"]?.stamp.date, .init(timeIntervalSince1970: 40))
    }
    func testRecordFailureDoesNotMutatePreviouslyMergedRecords() throws {
        var snapshot = SettingsSyncSnapshot()
        let stamp = SettingsSyncStamp(date: Date(), device: "a", sequence: 1)
        try snapshot.merge(record: .init(preference: "theme", value: .init(.text("classic"), stamp: stamp)))
        let retained = snapshot
        var bad = SettingsSyncRecord(preference: "theme", value: .init(.text("glass"), stamp: stamp)); bad.version = 99
        XCTAssertThrowsError(try snapshot.merge(record: bad))
        XCTAssertEqual(snapshot, retained)
        try snapshot.merge(record: .init(preference: "showAppSettings", value: .init(.bool(false), stamp: stamp)))
        XCTAssertEqual(snapshot.preferences.count, 2)
    }
    func testNewerSavedDraftRestoresDeletedMenuPreservingRemotePin() throws {
        let original = command()
        var deleted = original; deleted.isPinned = false
        var draft = original; draft.symbol = "gear"
        let result = SettingsDraftMerge.commands(before: [original], edited: [draft], latest: [], tombstones: [original.id: deleted])
        XCTAssertEqual(result.count, 1); XCTAssertFalse(result[0].isPinned); XCTAssertEqual(result[0].symbol, "gear")
        XCTAssertTrue(SettingsDraftMerge.commands(before: [original], edited: [original], latest: []).isEmpty)
    }
    func testDeletionAndRestorationDoNotMoveTheStoredOrderSlot() throws {
        let first = command(["File", "First"]), second = command(["File", "Second"])
        var replica = SettingsSyncReplica()
        let before = projection([first, second])
        replica.capture(before: nil, after: before, at: Date())
        let initial = replica.snapshot.orders["test.app"]!
        replica.capture(before: before, after: projection([second]), at: .init(timeIntervalSince1970: 10))
        XCTAssertEqual(replica.snapshot.orders["test.app"], initial)
        replica.capture(before: projection([second]), after: projection([second, first]), at: .init(timeIntervalSince1970: 20))
        XCTAssertEqual(replica.snapshot.orders["test.app"], initial)
        XCTAssertEqual(replica.applying(to: projection([second, first])).commands.map(\.id), [first.id, second.id])
    }

    func testRemoteResourceHintCannotExecuteAnUnverifiedSameNameMenu() throws {
        var command = command()
        let expected = MenuResourceIdentity(appID: command.appID, archive: "Main", keys: ["root", "open"])
        command.syncResourceIdentity = expected
        XCTAssertTrue(MenuPathMatch.paths(command).isEmpty)
        command.resourceBinding = .init(identity: .init(appID: command.appID, archive: "Main", keys: ["root", "different"]), paths: [command.path])
        XCTAssertTrue(MenuPathMatch.paths(command).isEmpty)
        command.resourceBinding = .init(identity: expected, paths: [command.path])
        XCTAssertEqual(MenuPathMatch.paths(command), [command.path])
        let restored = try JSONDecoder().decode(MenuCommand.self, from: JSONEncoder().encode(command))
        XCTAssertEqual(restored.syncResourceIdentity, expected)
    }

    func testManualReadditionWithANewLocalUUIDRestoresTheSharedMenu() throws {
        let original = command()
        var replica = SettingsSyncReplica()
        replica.capture(before: nil, after: projection([original]), at: Date())
        let shared = replica.localIDs[original.id]!
        replica.capture(before: projection([original]), after: projection([]), at: .init(timeIntervalSince1970: 10))
        let replacement = command()
        replica.capture(before: projection([]), after: projection([replacement]), at: .init(timeIntervalSince1970: 20))
        XCTAssertEqual(replica.localIDs[replacement.id], shared)
        XCTAssertEqual(replica.snapshot.combinedMenus.count, 1)
        XCTAssertTrue(replica.snapshot.combinedMenus[0].isPresent)
    }

}
