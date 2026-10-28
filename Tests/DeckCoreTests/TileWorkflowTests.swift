import XCTest
import CoreGraphics
@testable import DeckCore

final class TileWorkflowTests: XCTestCase {
    func testMixedHistoryWrapsWithoutMovingLaterWindowsIntoTheGap() {
        let spans = TileArrangement.spans(for: ["Terminal", "Terminal", "Safari", "Terminal", "Mail", "Finder"])
        XCTAssertEqual(spans, [2, 1, 2, 2, 2, 2])
        let placements = TileArrangement.place(spans: spans, columns: 6)
        XCTAssertEqual(placements.map(\.row), [0, 0, 0, 1, 1, 1])
        XCTAssertEqual(placements.map(\.column), [0, 2, 3, 0, 2, 4])
        XCTAssertEqual(placements.map(\.index), [0, 1, 2, 3, 4, 5])
    }
    func testNextPresentationUsesNewNeighborsButLeavesCapturedHistoryAlone() {
        var recent = Recency<String>()
        let owner = ["cc2": "T", "se3": "T", "naver": "S", "local": "T"]
        for key in ["local", "naver", "se3", "cc2"] { recent.touch(key) }
        let captured = recent.sorted(["cc2", "se3", "naver", "local"])
        recent.touch("naver")
        let next = recent.sorted(captured)
        XCTAssertEqual(captured, ["cc2", "se3", "naver", "local"])
        XCTAssertEqual(next, ["naver", "cc2", "se3", "local"])
        XCTAssertEqual(TileArrangement.spans(for: next.map { owner[$0]! }), [2, 2, 1, 1])
        recent.touch("se3")
        XCTAssertEqual(TileArrangement.spans(for: recent.sorted(captured).map { owner[$0]! }), [2, 2, 2, 1])
    }
    func testAutoKeepsAllRowsForScrollingAndManualHasNoFixedCeiling() {
        let layout = PanelLayout.calculate(visibleFrame: CGRect(x: 0, y: 0, width: 1000, height: 720), cursor: .zero)
        let columns = layout.columns * 2
        let spans = Array(repeating: [2, 1], count: 20).flatMap { $0 }
        let count = layout.windowLimit(manual: nil, actual: spans.count)
        let positions = TileArrangement.place(spans: spans, columns: columns)
        XCTAssertEqual(count, spans.count)
        XCTAssertGreaterThanOrEqual(positions.prefix { $0.row < 3 }.count, 6)
        XCTAssertGreaterThan(positions.last!.row, 1)
        XCTAssertEqual(layout.windowLimit(manual: Int.max, actual: 45), 45)
    }
    func testSquareModuleAndWideTilesShareDimensionsAcrossSupportedWidths() {
        for width: CGFloat in [512, 640, 760, 900, 1040] {
            let compact = width < 760
            let g = DeckGeometry(width: width, compact: compact)
            XCTAssertGreaterThanOrEqual(g.windowColumns, 4)
            XCTAssertGreaterThan(g.unit, 50)
            let occupied = g.windowWidth + (compact ? 0 : g.menuWidth + 24)
            XCTAssertEqual(occupied, width - 48, accuracy: 0.01)
        }
    }
    func testAllTenDigitsBothAssignmentsAndUnsupportedModifiers() {
        let keys: [UInt16] = [18, 19, 20, 21, 23, 22, 26, 28, 25, 29]
        for (index, key) in keys.enumerated() {
            XCTAssertEqual(OverlayShortcut.resolve(keyCode: key, modifiers: .option), .number(index: index, command: false))
            XCTAssertEqual(OverlayShortcut.resolve(keyCode: key, modifiers: [.option, .command]), .number(index: index, command: true))
            XCTAssertNil(OverlayShortcut.resolve(keyCode: key, modifiers: []))
            XCTAssertNil(OverlayShortcut.resolve(keyCode: key, modifiers: [.option, .shift]))
            XCTAssertNil(OverlayShortcut.resolve(keyCode: key, modifiers: [.option, .control]))
        }
        XCTAssertFalse(NumberShortcutAssignment.registeredFirst.targetsWindows(command: false))
        XCTAssertTrue(NumberShortcutAssignment.registeredFirst.targetsWindows(command: true))
        XCTAssertTrue(NumberShortcutAssignment.windowsFirst.targetsWindows(command: false))
        XCTAssertFalse(NumberShortcutAssignment.windowsFirst.targetsWindows(command: true))
        XCTAssertEqual(NumberShortcutAssignment.digit(for: 9), "0")
        XCTAssertNil(NumberShortcutAssignment.digit(for: 10))
    }
    func testLegacyProfileMigrationKeepsExactOrderAndFolderModes() throws {
        var folder = PinnedItem(kind: .folder, path: "/tmp/example", bundleID: nil, name: "예시")
        folder.setOpenMode(.finder)
        let items = [folder, PinnedItem(kind: .app, path: "/Applications/Example.app", bundleID: "example", name: "Example")]
        let migrated = LauncherProfile.restore(profiles: nil, legacyPins: try JSONEncoder().encode(items))
        XCTAssertEqual(migrated.count, 1)
        XCTAssertEqual(migrated[0].id, "default")
        XCTAssertEqual(migrated[0].items, items)
        let additional = LauncherProfile(name: "업무", items: Array(items.reversed()))
        let restored = LauncherProfile.restore(profiles: try JSONEncoder().encode(migrated + [additional]), legacyPins: nil)
        XCTAssertEqual(restored, migrated + [additional])
    }
    func testMenuPinningFrequencyAndRecencyAreAppLocal() {
        var a = MenuCommand(appID: "excel", appName: "Excel", path: ["파일", "A"], isPinned: false)
        var b = MenuCommand(appID: "excel", appName: "Excel", path: ["파일", "B"], isPinned: false)
        let c = MenuCommand(appID: "excel", appName: "Excel", path: ["파일", "C"])
        let foreign = MenuCommand(appID: "safari", appName: "Safari", path: ["파일", "D"])
        for _ in 0..<3 { a.recordUse(at: Date()) }; b.recordUse(at: Date())
        XCTAssertEqual(MenuCommand.ordered([a, b, foreign, c], appID: "excel").map(\.title), ["C", "A", "B"])
        XCTAssertTrue(a.isWide)
        XCTAssertFalse(b.isWide)
        b.isPinned = true
        XCTAssertEqual(MenuCommand.ordered([a, b, foreign, c], appID: "excel").map(\.title), ["B", "C", "A"])
    }
}
