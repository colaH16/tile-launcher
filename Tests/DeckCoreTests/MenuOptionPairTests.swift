import XCTest
@testable import DeckCore

final class MenuOptionPairTests: XCTestCase {
    func testDifferentTitlesNormalizeToOneTileAndKeepOptionTarget() throws {
        let primary = CapturedMenu(appID: "finder", appName: "Finder", path: ["Window", "Minimise"], shortcut: "m", modifiers: 0)
        let alternate = MenuActionReference(path: ["Window", "Minimise All"], identifier: nil)
        let pair = try XCTUnwrap(MenuOptionPair(primary: primary, alternate: alternate, primaryModifiers: 0, alternateModifiers: 2))
        XCTAssertTrue(pair.matches(path: alternate.path, identifier: nil))
        let normalized = pair.normalized()
        XCTAssertEqual(normalized.identity, primary.identity)
        XCTAssertEqual(normalized.optionAction, alternate)
        let saved = MenuCaptureHistory.record(normalized, in: [], at: Date())[0]
        let option = try XCTUnwrap(saved.optionCommand())
        XCTAssertEqual(option.path, alternate.path)
        XCTAssertEqual(option.id, saved.id)
        XCTAssertEqual(try JSONDecoder().decode(MenuCommand.self, from: JSONEncoder().encode(saved)), saved)
    }
    func testSameNameWithoutShortcutRequiresDistinctIdentifiers() {
        let primary = CapturedMenu(appID: "iterm", appName: "iTerm", path: ["Profiles", "local"], axIdentifier: "NewTab:local")
        let alternate = MenuActionReference(path: primary.identity.path, identifier: "NewWindow:local")
        XCTAssertNotNil(MenuOptionPair(primary: primary, alternate: alternate, primaryModifiers: 0, alternateModifiers: 10))
        XCTAssertNil(MenuOptionPair(primary: primary, alternate: .init(path: primary.identity.path, identifier: primary.axIdentifier), primaryModifiers: 0, alternateModifiers: 10))
        XCTAssertNil(MenuOptionPair(primary: primary, alternate: alternate, primaryModifiers: 0, alternateModifiers: 3))
        XCTAssertNil(MenuOptionPair(primary: primary, alternate: .init(path: ["Other", "local"], identifier: "other"), primaryModifiers: 0, alternateModifiers: 2))
    }
    func testCommandDifferenceIsNotIgnoredForRealKeyboardEquivalents() {
        let primary = CapturedMenu(appID: "test", appName: "Test", path: ["File", "Run"], shortcut: "x", modifiers: 8)
        let alternate = MenuActionReference(path: ["File", "Run All"], identifier: nil)
        XCTAssertNil(MenuOptionPair(primary: primary, alternate: alternate, primaryModifiers: 8, alternateModifiers: 2, alternateShortcut: "x"))
        XCTAssertNotNil(MenuOptionPair(primary: primary, alternate: alternate, primaryModifiers: 8, alternateModifiers: 10, alternateShortcut: "x"))
    }
    func testSelectionMergesAtomicallyAndReceiverPreservesBothActions() throws {
        var first = MenuCommand(appID: "test", appName: "Test", path: ["File", "Run"])
        first.axIdentifier = "primaryA"; first.optionAction = .init(path: ["File", "Run All"], identifier: "optionA")
        let before = SettingsSyncProjection(preferences: [:], commands: [first])
        var replica = SettingsSyncReplica(); replica.capture(before: nil, after: before, at: Date())
        let old = replica.snapshot
        var last = first; last.axIdentifier = "primaryB"; last.optionAction = .init(path: ["File", "Run All"], identifier: "optionB")
        replica.capture(before: before, after: .init(preferences: [:], commands: [last]), at: Date())
        replica.snapshot = try old.merged(with: replica.snapshot)
        var remote = SettingsSyncReplica(); remote.snapshot = replica.snapshot
        let received = remote.applying(to: .init(preferences: [:], commands: []))
        XCTAssertEqual(received.commands[0].executionSelection, last.executionSelection)
        var normalUsage = last; normalUsage.recordUse(at: Date())
        let seq = replica.sequence
        replica.capture(before: .init(preferences: [:], commands: [last]), after: .init(preferences: [:], commands: [normalUsage]), at: Date())
        XCTAssertEqual(replica.sequence, seq)
    }
    func testDraftNeverMixesPrimaryFromOnePairWithAlternateFromAnother() {
        var base = MenuCommand(appID: "test", appName: "Test", path: ["File", "Run"])
        base.axIdentifier = "a"; base.optionAction = .init(path: ["File", "All"], identifier: "aa")
        var draft = base; draft.axIdentifier = "b"; draft.optionAction = nil
        var live = base; live.optionAction = .init(path: ["File", "All"], identifier: "new-aa")
        let saved = SettingsDraftMerge.commands(before: [base], edited: [draft], latest: [live])[0]
        XCTAssertEqual(saved.executionSelection, draft.executionSelection)
    }
}
