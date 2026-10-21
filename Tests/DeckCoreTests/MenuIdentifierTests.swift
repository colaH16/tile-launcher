import XCTest
@testable import DeckCore

final class MenuIdentifierTests: XCTestCase {
    private let path = ["Profiles", "openmaru8 in local"]
    private func capture(_ identifier: String?) -> CapturedMenu {
        .init(appID: "com.googlecode.iterm2", appName: "iTerm2", path: path,
              shortcutKnown: true, axIdentifier: identifier)
    }
    func testIdentifierRoundTripAndOldCommandsWithoutField() throws {
        var command = MenuCommand(appID: "com.googlecode.iterm2", appName: "iTerm2", path: path)
        command.axIdentifier = "NewTab:openmaru8 in local"
        let encoded = try JSONEncoder().encode(command)
        XCTAssertEqual(try JSONDecoder().decode(MenuCommand.self, from: encoded), command)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacy.removeValue(forKey: "axIdentifier")
        let decoded = try JSONDecoder().decode(MenuCommand.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(decoded.axIdentifier)
        XCTAssertEqual(decoded.id, command.id)
        XCTAssertEqual(decoded.path, path)
    }
    func testIdentifierPreservesExactSpellingAndTagTabsButRejectsInvalidValues() {
        XCTAssertEqual(MenuAXIdentifier.validated("tag\tNewTab:local"), "tag\tNewTab:local")
        XCTAssertEqual(MenuAXIdentifier.validated(" NewTab:local "), " NewTab:local ")
        for value in ["", " \t ", "bad\nvalue", "bad\0value", String(repeating: "a", count: 4097)] {
            XCTAssertNil(MenuAXIdentifier.validated(value))
        }
    }
    func testCapturingAnotherVariantKeepsTileAndUpdatesIdentifierWithoutShortcut() {
        let tab = capture("NewTab:openmaru8 in local")
        var saved = MenuCaptureHistory.record(tab, in: [], at: .init(timeIntervalSince1970: 1))[0]
        saved.isPinned = true; saved.symbol = "star"
        let updated = MenuCaptureHistory.record(capture("NewWindow:openmaru8 in local"), in: [saved], at: .init(timeIntervalSince1970: 2))
        XCTAssertEqual(updated.count, 1)
        XCTAssertEqual(updated[0].id, saved.id)
        XCTAssertEqual(updated[0].axIdentifier, "NewWindow:openmaru8 in local")
        XCTAssertNil(updated[0].shortcut)
        XCTAssertEqual(updated[0].observedCount, 2)
        XCTAssertTrue(updated[0].isPinned)
        XCTAssertEqual(updated[0].symbol, "star")
    }
    func testHelpCannotGuessBetweenIdentifiedAlternates() {
        let tab = capture("NewTab:openmaru8 in local")
        let window = capture("NewWindow:openmaru8 in local")
        XCTAssertNil(MenuCapturePolicy.resolveHelp(title: path[1], choices: [tab, window]))
        XCTAssertEqual(MenuCapturePolicy.resolveHelp(title: path[1], choices: [tab, tab])?.axIdentifier, tab.axIdentifier)
    }
    func testDraftRebindingPreservesConcurrentUsageAndUneditedIdentifierRefresh() {
        var base = MenuCommand(appID: "com.googlecode.iterm2", appName: "iTerm2", path: path)
        base.axIdentifier = "NewTab:openmaru8 in local"
        var edited = base; edited.axIdentifier = "NewWindow:openmaru8 in local"
        var used = base; used.recordUse(at: Date())
        let applied = SettingsDraftMerge.commands(before: [base], edited: [edited], latest: [used])
        XCTAssertEqual(applied[0].axIdentifier, edited.axIdentifier)
        XCTAssertEqual(applied[0].useCount, 1)
        var iconEdit = base; iconEdit.symbol = "star"
        let refreshed = SettingsDraftMerge.commands(before: [base], edited: [iconEdit], latest: [edited])
        XCTAssertEqual(refreshed[0].axIdentifier, edited.axIdentifier)
        XCTAssertEqual(refreshed[0].symbol, "star")
        let concurrentAddition = SettingsDraftMerge.commands(before: [], edited: [edited], latest: [used])
        XCTAssertEqual(concurrentAddition[0].id, used.id)
        XCTAssertEqual(concurrentAddition[0].axIdentifier, edited.axIdentifier)
    }
    func testIdentifierRemainsLocalAndCloudApplicationPreservesLocalBinding() {
        var command = MenuCommand(appID: "com.googlecode.iterm2", appName: "iTerm2", path: path)
        command.axIdentifier = "NewTab:openmaru8 in local"
        let before = SettingsSyncProjection(preferences: [:], commands: [command])
        var replica = SettingsSyncReplica()
        replica.capture(before: nil, after: before, at: Date())
        let snapshot = replica.snapshot, sequence = replica.sequence
        var changed = command; changed.axIdentifier = "NewWindow:openmaru8 in local"
        let after = SettingsSyncProjection(preferences: [:], commands: [changed])
        replica.capture(before: before, after: after, at: Date())
        XCTAssertEqual(replica.snapshot, snapshot)
        XCTAssertEqual(replica.sequence, sequence)
        XCTAssertEqual(replica.applying(to: after).commands.first?.axIdentifier, changed.axIdentifier)
        var otherMac = SettingsSyncReplica(); otherMac.snapshot = snapshot
        XCTAssertNil(otherMac.applying(to: .init(preferences: [:], commands: [])).commands.first?.axIdentifier)
    }
}
