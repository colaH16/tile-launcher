import XCTest
@testable import DeckCore

final class MenuCaptureTests: XCTestCase {
    private func menu(_ title: String = "Go to Folder…", app: String = "finder") -> CapturedMenu {
        CapturedMenu(appID: app, appName: app, path: ["Go", title])
    }
    func testHighlightWithoutPhysicalConfirmationAndCancelledInputAreIgnored() {
        var gate = MenuCaptureGate()
        let preferences = MenuCapturePreferences()
        XCTAssertNil(gate.take(menu(), matchedUserSelection: true, time: 1, preferences: preferences))
        gate.arm(time: 1)
        XCTAssertNil(gate.take(menu(), matchedUserSelection: false, time: 1.1, preferences: preferences))
        gate.cancel()
        XCTAssertNil(gate.take(menu(), matchedUserSelection: true, time: 1.2, preferences: preferences))
    }
    func testOnePhysicalSelectionIsCountedOnceEvenWithDuplicateNotifications() {
        var gate = MenuCaptureGate()
        gate.arm(time: 1)
        XCTAssertNotNil(gate.take(menu(), matchedUserSelection: true, time: 1.1, preferences: .init()))
        XCTAssertNil(gate.take(menu(), matchedUserSelection: true, time: 1.2, preferences: .init()))
        gate.arm(time: 1.3)
        XCTAssertNotNil(gate.take(menu(), matchedUserSelection: true, time: 1.4, preferences: .init()))
    }
    func testExpiredOrOutOfOrderEventsCannotClaimAnotherInput() {
        var gate = MenuCaptureGate()
        gate.arm(time: 3)
        XCTAssertNil(gate.take(menu(), matchedUserSelection: true, time: 2.9, preferences: .init()))
        XCTAssertNil(gate.take(menu(), matchedUserSelection: true, time: 4, preferences: .init()))
    }
    func testCopyAndPasteSelectedThroughMenusAreIncluded() {
        for (title, key) in [("Copy", "c"), ("Paste", "v"), ("복사", "c"), ("붙여넣기", "v")] {
            let candidate = CapturedMenu(appID: "editor", appName: "Editor", path: ["Edit", title],
                                         shortcut: key, commandModifier: true)
            XCTAssertTrue(MenuCapturePolicy.allows(candidate, preferences: .init()))
        }
    }
    func testDirectShortcutsTypingRepeatsAndEscapeNeverConfirmAMenu() {
        for key in UInt16(0)...UInt16(127) {
            XCTAssertEqual(MenuCaptureKeyDecision.resolve(keyCode: key, shortcutModifier: true,
                                                          repeating: false, menuWasOpen: true), .cancel)
            if key != 53 {
                XCTAssertEqual(MenuCaptureKeyDecision.resolve(keyCode: key, shortcutModifier: false,
                                                              repeating: false, menuWasOpen: false), .clearHighlight)
            }
        }
        XCTAssertEqual(MenuCaptureKeyDecision.resolve(keyCode: 53, shortcutModifier: false, repeating: false, menuWasOpen: true), .cancel)
        for key: UInt16 in [36, 76] {
            XCTAssertEqual(MenuCaptureKeyDecision.resolve(keyCode: key, shortcutModifier: false, repeating: false, menuWasOpen: true), .confirm)
            XCTAssertEqual(MenuCaptureKeyDecision.resolve(keyCode: key, shortcutModifier: false, repeating: true, menuWasOpen: true), .clearHighlight)
        }
    }
    func testCorruptCollectionPreferencesPauseInsteadOfEnablingUnexpectedly() {
        XCTAssertTrue(MenuCapturePreferences.restore(nil).enabled)
        XCTAssertFalse(MenuCapturePreferences.restore(Data("broken".utf8)).enabled)
    }
    func testGlobalPauseAppExclusionAndHiddenMenuPreferencesRoundTrip() throws {
        var preferences = MenuCapturePreferences()
        XCTAssertTrue(MenuCapturePolicy.allows(menu(), preferences: preferences))
        preferences.excludedApps.insert("finder")
        XCTAssertFalse(MenuCapturePolicy.allows(menu(), preferences: preferences))
        XCTAssertTrue(MenuCapturePolicy.allows(menu(app: "editor"), preferences: preferences))
        preferences.excludedApps.remove("finder")
        preferences.excludedMenus.insert(menu().identity)
        XCTAssertFalse(MenuCapturePolicy.allows(menu(), preferences: preferences))
        XCTAssertEqual(MenuCapturePreferences.restore(try JSONEncoder().encode(preferences)), preferences)
        preferences.enabled = false
        XCTAssertFalse(MenuCapturePolicy.allows(menu(app: "editor"), preferences: preferences))
    }
    func testHelpMustResolveToOneCanonicalCommandRatherThanSearchResultPath() {
        let a = menu()
        let b = CapturedMenu(appID: "finder", appName: "Finder", path: ["File", "Go to Folder…"])
        XCTAssertEqual(MenuCapturePolicy.resolveHelp(title: "Go to Folder...", choices: [a])?.identity, a.identity)
        XCTAssertTrue(MenuCapturePolicy.resolveHelp(title: "Go to Folder…", choices: [a])?.fromHelpSearch == true)
        XCTAssertNil(MenuCapturePolicy.resolveHelp(title: "Go to Folder…", choices: [a, b]))
        XCTAssertNil(MenuCapturePolicy.resolveHelp(title: "Missing", choices: [a]))
    }
    func testRecentDocumentEntriesAndInvalidPathsAreNotLearned() {
        for path in [["File", "Open Recent", "Private.pdf"], ["이동", "최근 폴더", "개인 폴더"],
                     ["Window", "Document"], ["Go"], ["", "Leaf"]] {
            XCTAssertFalse(MenuCapturePolicy.allows(CapturedMenu(appID: "app", appName: "App", path: path), preferences: .init()))
        }
    }
    func testCaptureMergesIntoExistingManualMenuWithoutChangingPinOrID() {
        let manual = MenuCommand(appID: "finder", appName: "Finder", path: menu().identity.path)
        var history = [manual]
        for _ in 0..<3 { history = MenuCaptureHistory.record(menu(), in: history, at: Date()) }
        XCTAssertEqual(history.count, 1)
        XCTAssertEqual(history[0].id, manual.id)
        XCTAssertTrue(history[0].isPinned)
        XCTAssertFalse(history[0].isAutomatic)
        XCTAssertEqual(history[0].observedCount, 3)
        XCTAssertEqual(history[0].useCount, 0)
    }
    func testAutomaticMenusBecomeWideAndKeepIndependentApps() {
        var history: [MenuCommand] = []
        for _ in 0..<3 { history = MenuCaptureHistory.record(menu(), in: history, at: Date()) }
        history = MenuCaptureHistory.record(menu(app: "editor"), in: history, at: Date())
        XCTAssertTrue(history[0].isAutomatic)
        XCTAssertFalse(history[0].isPinned)
        XCTAssertTrue(history[0].isWide)
        XCTAssertFalse(history[1].isWide)
    }
    func testLegacyMenuRecordsMigrateWithoutLosingManualData() throws {
        let command = MenuCommand(appID: "app", appName: "App", path: ["File", "Export"])
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(command)) as! [String: Any]
        object.removeValue(forKey: "observedCount"); object.removeValue(forKey: "isAutomatic")
        let decoded = try JSONDecoder().decode(MenuCommand.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertEqual(decoded, command)
    }
    func testHistoryLimitsNeverEvictManualOrPinnedEntries() {
        let manual = MenuCommand(appID: "finder", appName: "Finder", path: ["File", "Manual"])
        var pinned = MenuCommand(appID: "finder", appName: "Finder", path: ["File", "Pinned"])
        pinned.isAutomatic = true
        var history = [manual, pinned]
        for i in 0..<110 { history = MenuCaptureHistory.record(menu("Item \(i)"), in: history, at: Date(timeIntervalSince1970: Double(i))) }
        XCTAssertEqual(history.count, 102)
        XCTAssertTrue(history.contains { $0.id == manual.id })
        XCTAssertTrue(history.contains { $0.id == pinned.id })
        XCTAssertFalse(history.contains { $0.title == "Item 0" })
        for i in 0..<510 {
            history = MenuCaptureHistory.record(menu("Item \(i)", app: "app\(i)"), in: history,
                                                at: Date(timeIntervalSince1970: Double(i + 200)))
        }
        XCTAssertEqual(history.filter { $0.isAutomatic && !$0.isPinned }.count, 500)
        XCTAssertTrue(history.contains { $0.id == manual.id })
        XCTAssertTrue(history.contains { $0.id == pinned.id })
    }
}
