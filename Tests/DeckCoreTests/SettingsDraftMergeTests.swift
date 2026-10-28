import XCTest
@testable import DeckCore

final class SettingsDraftMergeTests: XCTestCase {
    func testAppearanceKeepsUntouchedColorsAndAppliesOnlyEditedFields() {
        let base = AppearanceSettingsDraft(theme: .classic, colors: .init())
        var edit = base; edit.colors.menus = TileColor(0x123456)
        var live = base; live.theme = .glass; live.colors.windows = TileColor(0xABCDEF)
        let merged = edit.rebased(from: base, onto: live)
        XCTAssertEqual(merged.theme, .glass)
        XCTAssertEqual(merged.colors.menus, edit.colors.menus)
        XCTAssertEqual(merged.colors.windows, live.colors.windows)
    }
    func testMenuPinEditsPreserveNewCapturesAndAllLatestUsage() {
        let original = MenuCommand(appID: "editor", appName: "Editor", path: ["File", "Open"], isPinned: false)
        var edit = original; edit.isPinned = true; edit.symbol = "star"
        var live = original; live.recordUse(at: Date(), observed: true); live.recordUse(at: Date())
        live.shortcut = .init(key: "o", modifiers: 0)
        let newlyCaptured = MenuCommand(appID: "other", appName: "Other", path: ["File", "Save"])
        let merged = SettingsDraftMerge.commands(before: [original], edited: [edit], latest: [live, newlyCaptured])
        XCTAssertEqual(merged.count, 2)
        XCTAssertTrue(merged[0].isPinned)
        XCTAssertEqual(merged[0].symbol, "star")
        XCTAssertEqual(merged[0].observedCount, 1)
        XCTAssertEqual(merged[0].useCount, 1)
        XCTAssertEqual(merged[0].recentUses, live.recentUses)
        XCTAssertEqual(merged[0].shortcut, live.shortcut)
        XCTAssertEqual(merged[1], newlyCaptured)
    }
    func testMenuDeletionAndOrderingDoNotDiscardNewRuntimeEntries() {
        let base = (0..<3).map { MenuCommand(appID: "editor", appName: "Editor", path: ["File", "Item \($0)"]) }
        let fresh = MenuCommand(appID: "editor", appName: "Editor", path: ["File", "Fresh"])
        let result = SettingsDraftMerge.commands(before: base, edited: [base[2], base[0]], latest: base + [fresh])
        XCTAssertEqual(result.map(\.id), [base[2].id, base[0].id, fresh.id])
    }
    func testManualAdditionUsesConcurrentCaptureIdentityWithoutLosingHistory() {
        var captured = MenuCommand(appID: "editor", appName: "Editor", path: ["File", "Open"], isPinned: false)
        captured.recordUse(at: Date(), observed: true)
        let manual = MenuCommand(appID: "editor", appName: "Editor", path: captured.path)
        let result = SettingsDraftMerge.commands(before: [], edited: [manual], latest: [captured])
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].id, captured.id)
        XCTAssertEqual(result[0].observedCount, 1)
        XCTAssertTrue(result[0].isPinned)
    }
    func testUsageAloneDoesNotMakeMenuSettingsDirty() {
        let menu = MenuCommand(appID: "app", appName: "App", path: ["File", "Open"])
        let base = MenuSettingsDraft(showsAppSettings: true, capture: .init(), history: .init(), commands: [menu])
        var latest = base; latest.commands[0].recordUse(at: Date())
        XCTAssertEqual(base, latest)
        latest.commands[0].symbol = "star"
        XCTAssertNotEqual(base, latest)
    }
    func testExcludedMenuEditsKeepNewExclusionsFromAnotherApp() {
        let a = MenuIdentity(appID: "a", path: ["File", "Open"])
        let b = MenuIdentity(appID: "b", path: ["File", "Save"])
        XCTAssertEqual(SettingsDraftMerge.set([a], [], [a, b]), [b])
    }
    private var registered: RegisteredSettingsDraft {
        .init(profiles: [.init(id: "default", name: "기본"), .init(id: "work", name: "작업")],
              selectedID: "default", followsFocus: true)
    }
    func testProfileEditKeepsOtherProfileChangesAndFocusPreference() throws {
        let base = registered
        let a = PinnedItem(kind: .folder, path: "/tmp/a", bundleID: nil, name: "A")
        let b = PinnedItem(kind: .folder, path: "/tmp/b", bundleID: nil, name: "B")
        var edit = base; edit.profiles[0].items = [a]; edit.selectedID = "work"; edit.followsFocus = false
        var live = base; live.profiles[1].items = [b]
        let merged = try edit.rebased(from: base, onto: live)
        XCTAssertEqual(merged.profiles[0].items, [a])
        XCTAssertEqual(merged.profiles[1].items, [b])
        XCTAssertEqual(merged.selectedID, "work")
        XCTAssertFalse(merged.followsFocus)
    }
    func testConflictingProfileEditsAndDeletionAreRejected() {
        let base = registered
        var edit = base; edit.profiles[0].name = "내 변경"
        var live = base; live.profiles[0].name = "외부 변경"
        XCTAssertThrowsError(try edit.rebased(from: base, onto: live))
        live.profiles.removeFirst(); live.selectedID = "work"
        XCTAssertThrowsError(try edit.rebased(from: base, onto: live))
        edit = base; edit.profiles.removeLast()
        live = base; live.profiles[1].name = "외부 변경"
        XCTAssertThrowsError(try edit.rebased(from: base, onto: live))
    }
}
