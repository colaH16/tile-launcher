import XCTest
@testable import DeckCore

final class SettingsSyncMenuIdentifierTests: XCTestCase {
    private func stamp(_ seconds: Double, _ sequence: UInt64 = 1) -> SettingsSyncStamp {
        .init(date: .init(timeIntervalSince1970: seconds), device: "mac-a", sequence: sequence)
    }
    private func menu(_ choice: SettingsSyncField<String?>? = nil) -> SettingsSyncMenu {
        .init(id: "profile", appID: "com.googlecode.iterm2", appName: "iTerm2", path: ["Profiles", "fish"],
              presence: .init(true, stamp: stamp(1)), pinned: .init(true, stamp: stamp(1)),
              icon: .init([.init(symbol: nil, stamp: stamp(1))]), executionIdentifier: choice)
    }
    func testLegacyPayloadAndIdentifiedPayloadRoundTrip() throws {
        for choice: SettingsSyncField<String?>? in [nil, .init("NewTab:fish", stamp: stamp(2)), .init(nil, stamp: stamp(3))] {
            let record = SettingsSyncRecord(menu: menu(choice))
            let decoded = try SettingsSyncRecord.decodeVerified(JSONEncoder().encode(record))
            XCTAssertEqual(decoded, record)
            XCTAssertNoThrow(try decoded.fragment())
        }
    }
    func testOlderPayloadCannotEraseSelectionAndNewerExplicitClearWins() throws {
        let chosen = menu(.init("NewWindow:fish", stamp: stamp(2)))
        XCTAssertEqual(try chosen.merged(with: menu()).executionIdentifier, chosen.executionIdentifier)
        XCTAssertEqual(try menu().merged(with: chosen).executionIdentifier, chosen.executionIdentifier)
        let cleared = menu(.init(nil, stamp: stamp(3)))
        let merged = try chosen.merged(with: cleared)
        XCTAssertNotNil(merged.executionIdentifier)
        XCTAssertNil(merged.executionIdentifier?.value)
        XCTAssertEqual(merged.executionIdentifier, try cleared.merged(with: chosen).executionIdentifier)
    }
    func testSelectionUsesEditTimeAndCountsAsMenuEdit() throws {
        let early = menu(.init("NewTab:fish", stamp: stamp(5)))
        let late = menu(.init("NewWindow:fish", stamp: stamp(9)))
        XCTAssertEqual(try early.merged(with: late).executionIdentifier?.value, "NewWindow:fish")
        XCTAssertEqual(try late.merged(with: early).executionIdentifier?.value, "NewWindow:fish")
        var deleted = early
        deleted.presence = .init(false, stamp: stamp(7))
        XCTAssertFalse(deleted.isPresent)
        XCTAssertTrue(try deleted.merged(with: late).isPresent)
    }
    func testMalformedIdentifierAndStampAreRejected() throws {
        for bad in ["", "bad\nvalue", String(repeating: "x", count: 4097)] {
            XCTAssertThrowsError(try SettingsSyncRecord(menu: menu(.init(bad, stamp: stamp(2)))).fragment())
        }
        let invalid = SettingsSyncStamp(date: Date(), device: "", sequence: 0)
        XCTAssertThrowsError(try SettingsSyncRecord(menu: menu(.init("NewTab:fish", stamp: invalid))).fragment())
    }
    func testUnknownSelectionFieldsRemainQuarantined() throws {
        let record = SettingsSyncRecord(menu: menu(.init("NewTab:fish", stamp: stamp(2))))
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(record)) as? [String: Any])
        var object = root["menu"] as! [String: Any]
        var field = object["executionIdentifier"] as! [String: Any]
        field["future"] = true
        object["executionIdentifier"] = field; root["menu"] = object
        XCTAssertThrowsError(try SettingsSyncRecord.decodeVerified(JSONSerialization.data(withJSONObject: root)))
    }
}
