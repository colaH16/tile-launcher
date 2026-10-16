import XCTest
@testable import DeckCore

final class DockImportChangeTests: XCTestCase {
    private let oldApp = PinnedItem(kind: .app, path: "/Applications/A.app", bundleID: "app.a", name: "내 이름")
    private let folder = PinnedItem(kind: .folder, path: "/tmp/folder", bundleID: nil, name: "자료", openMode: .finder)
    private let newApp = PinnedItem(kind: .app, path: "/Applications/B.app", bundleID: "app.b", name: "B")
    private var profile: LauncherProfile { LauncherProfile(id: "work", name: "작업", items: [folder, oldApp]) }
    private var imported: DockImportResult { DockImportResult(items: [oldApp, newApp], skipped: 2) }

    func testPreviewDoesNotMutateProfileAndApplyUndoRestoreExactOrderAndModes() throws {
        let original = profile
        let change = DockImportChange(profile: original, imported: imported)
        XCTAssertEqual(original, profile)
        XCTAssertEqual(change.before, [folder, oldApp])
        XCTAssertEqual(change.after, [oldApp, newApp, folder])
        XCTAssertEqual(change.addedIDs, [newApp.id])
        XCTAssertEqual(change.skipped, 2)
        var target = original
        target.items = try XCTUnwrap(change.applying(to: target))
        XCTAssertEqual(target.items.last?.openMode, .finder)
        XCTAssertEqual(target.items.first?.name, "내 이름")
        XCTAssertEqual(change.undoing(in: target), original.items)
    }
    func testSwitchingProfilesCannotApplyOrUndoInTheOtherProfile() {
        let change = DockImportChange(profile: profile, imported: imported)
        var other = LauncherProfile(id: "other", name: "다른 구성", items: change.before)
        XCTAssertNil(change.applying(to: other))
        other.items = change.after
        XCTAssertNil(change.undoing(in: other))
    }
    func testEditsAfterPreviewAndAfterImportAreNeverOverwritten() {
        let change = DockImportChange(profile: profile, imported: imported)
        var target = profile
        target.items.reverse()
        XCTAssertNil(change.applying(to: target))
        target.items = change.after
        target.items.removeLast()
        XCTAssertNil(change.undoing(in: target))
        target.items = change.after
        target.items[2].setOpenMode(.overlay)
        XCTAssertNil(change.undoing(in: target))
    }
    func testRepeatedImportCanBeANoOpOrUndoOnlyTheLatestImport() throws {
        let first = DockImportChange(profile: profile, imported: imported)
        var target = profile; target.items = try XCTUnwrap(first.applying(to: target))
        XCTAssertFalse(DockImportChange(profile: target, imported: imported).hasChanges)
        let second = DockImportChange(profile: target, imported: .init(items: [newApp, oldApp], skipped: 0))
        XCTAssertTrue(second.hasChanges)
        XCTAssertTrue(second.addedIDs.isEmpty)
        target.items = try XCTUnwrap(second.applying(to: target))
        XCTAssertEqual(second.undoing(in: target), first.after)
    }
}
