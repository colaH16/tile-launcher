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

    private func remoteMenu(_ id: String, path: [String] = ["File", "Open"], present: Bool = true,
                            device: String = "remote", identity: MenuResourceIdentity? = nil) -> SettingsSyncMenu {
        let stamp = SettingsSyncStamp(date: .init(timeIntervalSince1970: 5), device: device, sequence: 1)
        return .init(id: id, appID: "test.app", appName: "Test", path: path, resourceIdentity: identity,
                     presence: .init(present, stamp: stamp), pinned: .init(true, stamp: stamp),
                     icon: .init([.init(symbol: nil, stamp: stamp)]))
    }

    func testUnrelatedEditDoesNotRestampAnOrderMissingARemoteMenu() throws {
        let local = command()
        var replica = SettingsSyncReplica()
        let before = projection([local])
        replica.capture(before: nil, after: before, at: .init(timeIntervalSince1970: 1))
        replica.snapshot.menus["R"] = remoteMenu("R", path: ["File", "Remote"])
        let applied = replica.applying(to: before)
        XCTAssertEqual(applied.commands.count, 2)
        let order = replica.snapshot.orders["test.app"]
        replica.capture(before: applied, after: projection(applied.commands, theme: "glass"), at: .init(timeIntervalSince1970: 50))
        XCTAssertEqual(replica.snapshot.orders["test.app"], order)
        XCTAssertEqual(replica.snapshot.preferences["theme"]?.stamp.date, .init(timeIntervalSince1970: 50))
    }

    func testNewlyTrackedPreferenceKeepsAnUnknownTime() {
        var replica = SettingsSyncReplica()
        let before = SettingsSyncProjection(preferences: ["theme": .text("classic")], commands: [])
        replica.capture(before: nil, after: before, at: Date())
        var after = before; after.preferences["showAppSettings"] = .bool(false)
        replica.capture(before: before, after: after, at: .init(timeIntervalSince1970: 60))
        XCTAssertNil(replica.snapshot.preferences["showAppSettings"]?.stamp.date)
    }

    func testRemoteDeletionRemovesOnlyTheLinkedCommand() throws {
        var collected = command(); collected.isAutomatic = true; collected.isPinned = false
        collected.recordUse(at: .init(timeIntervalSince1970: 3), observed: true)
        var replica = SettingsSyncReplica()
        replica.capture(before: nil, after: projection([collected]), at: Date())
        replica.snapshot.menus["R"] = remoteMenu("R", present: false)
        let applied = replica.applying(to: projection([collected]))
        XCTAssertEqual(applied.commands.map(\.id), [collected.id], "Local usage history must survive a same-path tombstone")
    }

    func testLinkedCommandIsNeverRelinkedToAnotherRecordWithTheSamePath() throws {
        let local = command()
        var replica = SettingsSyncReplica()
        replica.capture(before: nil, after: projection([local]), at: Date())
        let shared = replica.localIDs[local.id]!
        replica.snapshot.menus["Z-other"] = remoteMenu("Z-other", present: false, device: "other")
        let applied = replica.applying(to: projection([local]))
        XCTAssertEqual(applied.commands.map(\.id), [local.id])
        XCTAssertEqual(replica.localIDs[local.id], shared)
    }

    func testExistingCommandKeepsExecutingWhenTheSharedRecordHasAHint() throws {
        let local = command()
        var replica = SettingsSyncReplica()
        replica.capture(before: nil, after: projection([local]), at: Date())
        let shared = replica.localIDs[local.id]!
        replica.snapshot.menus[shared]!.resourceIdentity = .init(appID: "test.app", archive: "Main", keys: ["root", "open"])
        let applied = replica.applying(to: projection([local]))
        XCTAssertNil(applied.commands[0].syncResourceIdentity)
        XCTAssertEqual(MenuPathMatch.paths(applied.commands[0]), [local.path])
        // A menu first created from iCloud still waits for a verified binding.
        replica.snapshot.menus["N"] = remoteMenu("N", path: ["File", "New"],
                                                 identity: .init(appID: "test.app", archive: "Main", keys: ["root", "new"]))
        let created = replica.applying(to: applied).commands.first { $0.path == ["File", "New"] }!
        XCTAssertTrue(MenuPathMatch.paths(created).isEmpty)
    }

    func testAliasesFromDifferentMacsCannotChainTwoCommandsOfOneMac() {
        var snapshot = SettingsSyncSnapshot()
        var x = remoteMenu("X"); x.origins = ["mac": "local-1"]
        var y = remoteMenu("Y", device: "peer"); y.aliases = ["X", "Y"]
        var z = remoteMenu("Z"); z.origins = ["mac": "local-2"]; z.aliases = ["Y", "Z"]
        snapshot.menus = ["X": x, "Y": y, "Z": z]
        let groups = snapshot.menuGroups
        XCTAssertFalse(groups.contains { group in group.contains { $0.id == "X" } && group.contains { $0.id == "Z" } })
        XCTAssertEqual(snapshot.combinedMenus.count, groups.count)
    }

    func testOneSharedRecordIsClaimedByOnlyOneLocalCommand() {
        let first = command()
        var replica = SettingsSyncReplica()
        replica.snapshot.menus["R"] = remoteMenu("R")
        replica.capture(before: nil, after: projection([first]), at: Date())
        XCTAssertEqual(replica.localIDs[first.id], "R")
        let second = command()
        replica.capture(before: projection([first]), after: projection([first, second]), at: .init(timeIntervalSince1970: 9))
        XCTAssertNotEqual(replica.localIDs[second.id], "R")
    }

    func testPayloadWithUnknownKeysIsRejectedButKnownPayloadsDecode() throws {
        let stamp = SettingsSyncStamp(date: Date(timeIntervalSince1970: 7), device: "a", sequence: 1)
        let records = [SettingsSyncRecord(menu: remoteMenu("R")),
                       SettingsSyncRecord(preference: "menuColor", value: .init(.color(nil), stamp: stamp)),
                       SettingsSyncRecord(preference: "theme", value: .init(.text("glass"), stamp: stamp)),
                       SettingsSyncRecord(appOrder: "test.app", order: .init(["R"], stamp: stamp))]
        for record in records {
            XCTAssertEqual(try SettingsSyncRecord.decodeVerified(JSONEncoder().encode(record)), record)
        }
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(records[0])) as! [String: Any]
        var menu = object["menu"] as! [String: Any]; menu["futureField"] = 1; object["menu"] = menu
        XCTAssertThrowsError(try SettingsSyncRecord.decodeVerified(JSONSerialization.data(withJSONObject: object)))
        object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(records[0])) as! [String: Any]
        object["extra"] = true
        XCTAssertThrowsError(try SettingsSyncRecord.decodeVerified(JSONSerialization.data(withJSONObject: object)))
    }

    func testClaimingRemoteMenuRecordsLocalOriginBeforeReconciliation() throws {
        let first = command(), second = command()
        var replica = SettingsSyncReplica()
        replica.snapshot.menus["R"] = remoteMenu("R")
        replica.capture(before: nil, after: projection([first]), at: Date())
        replica.capture(before: projection([first]), after: projection([first, second]), at: Date())
        try replica.snapshot.reconcileMenuIdentities()
        XCTAssertEqual(replica.snapshot.combinedMenus.count, 2,
                       "A remote record adopted by this Mac must not alias its two distinct local menus")
        XCTAssertNotEqual(replica.snapshot.canonicalMenuIDs[replica.localIDs[first.id]!],
                          replica.snapshot.canonicalMenuIDs[replica.localIDs[second.id]!])
    }

    func testMalformedMenuRecordCannotChangeAnExistingReplica() throws {
        var original = SettingsSyncSnapshot()
        try original.merge(record: .init(menu: remoteMenu("safe")))
        var wrongApp = remoteMenu("bad")
        wrongApp.resourceIdentity = .init(appID: "other.app", archive: "Main", keys: ["open"])
        var emptyPath = remoteMenu("empty"); emptyPath.path = []
        var invalidStamp = remoteMenu("stamp")
        invalidStamp.presence.stamp = .init(date: Date(), device: "", sequence: 0)
        var noIcons = remoteMenu("icons"); noIcons.icon = .init([])
        for invalid in [wrongApp, emptyPath, invalidStamp, noIcons] {
            var snapshot = original
            XCTAssertThrowsError(try snapshot.merge(record: .init(menu: invalid)))
            XCTAssertEqual(snapshot, original)
        }
    }

    func testMixedRecordPayloadAndInvalidOrderAreRejected() {
        let stamp = SettingsSyncStamp(date: Date(), device: "a", sequence: 1)
        var mixed = SettingsSyncRecord(menu: remoteMenu("R"))
        mixed.value = .init(.text("glass"), stamp: stamp)
        XCTAssertThrowsError(try mixed.fragment())
        XCTAssertThrowsError(try SettingsSyncRecord(appOrder: "test.app", order: .init(["R", "R"], stamp: stamp)).fragment())
        let invalid = SettingsSyncStamp(date: nil, device: "", sequence: 0)
        XCTAssertThrowsError(try SettingsSyncRecord(preference: "theme", value: .init(.text("glass"), stamp: invalid)).fragment())
    }

    func testManyIndependentMenusStaySeparateAndGroupingIsStable() throws {
        let records = (0..<200).map { remoteMenu("menu-\($0)", path: ["File", "Command \($0)"]) }
        var a = SettingsSyncSnapshot(), b = SettingsSyncSnapshot()
        for record in records { a.menus[record.id] = record }
        for record in records.reversed() { b.menus[record.id] = record }
        XCTAssertEqual(a.combinedMenus.count, 200)
        XCTAssertEqual(a.combinedMenus, b.combinedMenus)
        // One explicit alias joins only its two records, regardless of arrival.
        a.menus["menu-1"]!.aliases = ["menu-1", "menu-2"]
        b.menus["menu-1"]!.aliases = ["menu-1", "menu-2"]
        XCTAssertEqual(a.combinedMenus.count, 199)
        XCTAssertEqual(a.combinedMenus, b.combinedMenus)
    }

    func testThreeMacsWithOneUnambiguousMenuEachConvergeToOneMenu() throws {
        var replicas = [SettingsSyncReplica(), SettingsSyncReplica(), SettingsSyncReplica()]
        for index in replicas.indices {
            replicas[index].capture(before: nil, after: projection([command()]), at: Date())
        }
        var all = try replicas[0].snapshot.merged(with: replicas[1].snapshot).merged(with: replicas[2].snapshot)
        try all.reconcileMenuIdentities()
        XCTAssertEqual(all.combinedMenus.count, 1)
        var reversed = try replicas[2].snapshot.merged(with: replicas[1].snapshot).merged(with: replicas[0].snapshot)
        try reversed.reconcileMenuIdentities()
        XCTAssertEqual(all, reversed)
        XCTAssertEqual(all.combinedMenus.first?.origins?.count, 3)
    }

}
