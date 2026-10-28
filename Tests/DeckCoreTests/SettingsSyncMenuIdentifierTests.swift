import XCTest
@testable import DeckCore

final class SettingsSyncMenuIdentifierTests: XCTestCase {
    private func stamp(_ seconds: Double, _ sequence: UInt64 = 1) -> SettingsSyncStamp {
        .init(date: .init(timeIntervalSince1970: seconds), device: "mac-a", sequence: sequence)
    }
    private func menu(_ choice: SettingsSyncField<MenuExecutionSelection>? = nil) -> SettingsSyncMenu {
        .init(id: "profile", appID: "com.googlecode.iterm2", appName: "iTerm2", path: ["Profiles", "fish"],
              presence: .init(true, stamp: stamp(1)), pinned: .init(true, stamp: stamp(1)),
              icon: .init([.init(symbol: nil, stamp: stamp(1))]), execution: choice)
    }
    func testLegacyPayloadAndIdentifiedPayloadRoundTrip() throws {
        for choice: SettingsSyncField<MenuExecutionSelection>? in [nil, .init(.init(identifier: "NewTab:fish"), stamp: stamp(2)), .init(.init(identifier: nil), stamp: stamp(3))] {
            let record = SettingsSyncRecord(menu: menu(choice))
            let decoded = try SettingsSyncRecord.decodeVerified(JSONEncoder().encode(record))
            XCTAssertEqual(decoded, record)
            XCTAssertNoThrow(try decoded.fragment())
        }
    }
    func testOlderPayloadCannotEraseSelectionAndNewerExplicitClearWins() throws {
        let chosen = menu(.init(.init(identifier: "NewWindow:fish"), stamp: stamp(2)))
        XCTAssertEqual(try chosen.merged(with: menu()).execution, chosen.execution)
        XCTAssertEqual(try menu().merged(with: chosen).execution, chosen.execution)
        let cleared = menu(.init(.init(identifier: nil), stamp: stamp(3)))
        let merged = try chosen.merged(with: cleared)
        XCTAssertNotNil(merged.execution)
        XCTAssertTrue(merged.execution?.value.isEmpty == true)
        XCTAssertEqual(merged.execution, try cleared.merged(with: chosen).execution)
    }
    func testSelectionUsesEditTimeAndCountsAsMenuEdit() throws {
        let early = menu(.init(.init(identifier: "NewTab:fish"), stamp: stamp(5)))
        let late = menu(.init(.init(identifier: "NewWindow:fish"), stamp: stamp(9)))
        XCTAssertEqual(try early.merged(with: late).execution?.value.identifier, "NewWindow:fish")
        XCTAssertEqual(try late.merged(with: early).execution?.value.identifier, "NewWindow:fish")
        var deleted = early
        deleted.presence = .init(false, stamp: stamp(7))
        XCTAssertFalse(deleted.isPresent)
        XCTAssertTrue(try deleted.merged(with: late).isPresent)
    }
    func testMalformedIdentifierAndStampAreRejected() throws {
        for bad in ["", "bad\nvalue", String(repeating: "x", count: 4097)] {
            XCTAssertThrowsError(try SettingsSyncRecord(menu: menu(.init(.init(identifier: bad), stamp: stamp(2)))).fragment())
        }
        let invalid = SettingsSyncStamp(date: Date(), device: "", sequence: 0)
        XCTAssertThrowsError(try SettingsSyncRecord(menu: menu(.init(.init(identifier: "NewTab:fish"), stamp: invalid))).fragment())
    }
    func testUnknownSelectionFieldsRemainQuarantined() throws {
        let record = SettingsSyncRecord(menu: menu(.init(.init(identifier: "NewTab:fish"), stamp: stamp(2))))
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        var object = root["menu"] as! [String: Any]
        var field = object["execution"] as! [String: Any]
        field["future"] = true
        object["execution"] = field; root["menu"] = object
        XCTAssertThrowsError(try SettingsSyncRecord.decodeVerified(JSONSerialization.data(withJSONObject: root)))
    }
    func testFirstMergeAsksAboutUnknownTimeSelectionsAndHonorsChoice() throws {
        var a = SettingsSyncReplica(), b = SettingsSyncReplica()
        var command = MenuCommand(appID: "app", appName: "App", path: ["File", "Run"])
        command.axIdentifier = "primary-a"
        a.capture(before: nil, after: .init(preferences: [:], commands: [command]), at: Date())
        command.axIdentifier = "primary-b"
        b.capture(before: nil, after: .init(preferences: [:], commands: [command]), at: Date())
        XCTAssertTrue(a.legacyConflicts(with: b.snapshot).contains(where: { $0.hasPrefix("execution:") }))
        var local = a
        try local.mergeInitial(b.snapshot, preferLocal: true, at: Date())
        XCTAssertEqual(local.snapshot.combinedMenus[0].execution?.value.identifier, "primary-a")
        try a.mergeInitial(b.snapshot, preferLocal: false, at: Date())
        XCTAssertEqual(a.snapshot.combinedMenus[0].execution?.value.identifier, "primary-b")
    }
    func testUpgradeNeverOverwritesAnExplicitClear() {
        var command = MenuCommand(appID: "app", appName: "App", path: ["File", "Run"])
        command.axIdentifier = "old"
        var replica = SettingsSyncReplica()
        replica.capture(before: nil, after: .init(preferences: [:], commands: [command]), at: Date())
        let id = replica.snapshot.combinedMenus[0].id
        replica.snapshot.menus[id]?.execution = .init(.init(identifier: nil), stamp: stamp(10))
        replica.seedExecutionSelections(from: .init(preferences: [:], commands: [command]))
        XCTAssertTrue(replica.snapshot.menus[id]?.execution?.value.isEmpty == true)
    }

}
