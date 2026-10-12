import XCTest
import CoreGraphics
@testable import DeckCore

final class DeckCoreTests: XCTestCase {
    func testRecencyExamplesKeepAppsAndWindowsSeparate() {
        for (history, expectedApps, expectedWindows) in [
            (["cc2", "se3", "naver", "google"], ["iTerm", "Safari", "Chrome"], ["cc2", "se3", "naver"]),
            (["cc2", "naver", "se3", "google"], ["iTerm", "Safari", "Chrome"], ["cc2", "naver", "se3"]),
            (["cc2", "naver", "google"], ["iTerm", "Safari", "Chrome"], ["cc2", "naver", "google"])
        ] {
            let owner = ["cc2": "iTerm", "se3": "iTerm", "naver": "Safari", "google": "Chrome"]
            var apps = Recency<String>(), windows = Recency<String>()
            for window in history.reversed() {
                windows.touch(window)
                apps.touch(owner[window]!)
            }
            XCTAssertEqual(apps.sorted(["Chrome", "Safari", "iTerm"]), expectedApps)
            XCTAssertEqual(Array(windows.sorted(history).prefix(3)), expectedWindows)
        }
    }
    func testClosedItemsAreRemovedWithoutChangingSurvivorOrder() {
        var list = Recency<String>()
        ["a", "b", "c"].forEach { list.touch($0) }
        list.retain(["a", "c"])
        XCTAssertEqual(list.sorted(["a", "unknown", "c"]), ["c", "a", "unknown"])
    }
    func testPanelBoundsAndRatiosAcrossScreenShapesAndOrigins() {
        for size in [CGSize(width: 1280, height: 800), CGSize(width: 3440, height: 1440),
                     CGSize(width: 3840, height: 1080), CGSize(width: 1024, height: 768),
                     CGSize(width: 900, height: 1600), CGSize(width: 800, height: 600)] {
            for origin in [CGPoint.zero, CGPoint(x: -3440, y: -600)] {
                let screen = CGRect(origin: origin, size: size)
                for point in [CGPoint(x: screen.midX, y: screen.midY), screen.origin,
                              CGPoint(x: screen.maxX, y: screen.maxY)] {
                    let layout = PanelLayout.calculate(visibleFrame: screen, cursor: point)
                    XCTAssertTrue(screen.contains(layout.frame))
                    XCTAssertGreaterThanOrEqual(layout.frame.width / layout.frame.height, 1.199)
                    XCTAssertLessThanOrEqual(layout.frame.width / layout.frame.height, 1.501)
                    XCTAssertGreaterThanOrEqual(layout.capacity, 6)
                    XCTAssertLessThanOrEqual(layout.frame.width, 1040)
                    XCTAssertLessThanOrEqual(layout.frame.height, 720)
                    if !layout.compact {
                        XCTAssertGreaterThanOrEqual(layout.frame.width, 760)
                        XCTAssertGreaterThanOrEqual(layout.frame.height, 620)
                    }
                }
            }
        }
    }
    func testUltraWideDoesNotStretchPanel() {
        let narrow = PanelLayout.calculate(visibleFrame: CGRect(x: 0, y: 0, width: 1200, height: 900), cursor: .zero)
        let wide = PanelLayout.calculate(visibleFrame: CGRect(x: 0, y: 0, width: 3200, height: 900), cursor: .zero)
        XCTAssertEqual(narrow.frame.size, wide.frame.size)
    }
    func testCursorChangesOnlyPositionAndTinyScreenNeverOverflows() {
        let screen = CGRect(x: -1800, y: 50, width: 1600, height: 1000)
        let first = PanelLayout.calculate(visibleFrame: screen, cursor: .zero)
        let second = PanelLayout.calculate(visibleFrame: screen, cursor: CGPoint(x: -1200, y: 400))
        XCTAssertEqual(first.frame.size, second.frame.size)
        let tiny = CGRect(x: 0, y: 0, width: 400, height: 300)
        let result = PanelLayout.calculate(visibleFrame: tiny, cursor: .zero)
        XCTAssertTrue(tiny.contains(result.frame))
        XCTAssertFalse(result.supported)
    }
    func testCountUsesCapacityAndDoesNotAllocateManualMaximum() {
        let layout = PanelLayout.calculate(visibleFrame: CGRect(x: 0, y: 0, width: 1400, height: 900), cursor: .zero)
        XCTAssertEqual(layout.windowLimit(manual: nil, actual: 100), layout.capacity)
        XCTAssertEqual(layout.windowLimit(manual: Int.max, actual: 7), 7)
        XCTAssertEqual(layout.windowLimit(manual: 1, actual: 10), 6)
        XCTAssertEqual(layout.windowLimit(manual: 12, actual: 0), 0)
        XCTAssertEqual(layout.windowLimit(manual: nil, actual: 5), 5)
    }
    func testOptionComboNeverRearmsUntilRelease() {
        var gesture = HoldGesture()
        XCTAssertEqual(gesture.flags(option: true, otherModifier: false), .arm)
        XCTAssertEqual(gesture.interrupt(), .cancel)
        XCTAssertEqual(gesture.flags(option: true, otherModifier: false), .none)
        XCTAssertEqual(gesture.flags(option: false, otherModifier: false), .release)
        XCTAssertEqual(gesture.flags(option: true, otherModifier: false), .arm)
    }
    func testModifierCombinationIsNotAStandaloneOptionPress() {
        var gesture = HoldGesture()
        XCTAssertEqual(gesture.flags(option: true, otherModifier: true), .cancel)
        XCTAssertEqual(gesture.flags(option: true, otherModifier: false), .none)
        XCTAssertEqual(gesture.flags(option: false, otherModifier: false), .release)
        XCTAssertEqual(gesture.flags(option: false, otherModifier: false), .none)
    }
    func testFolderCatalogUsesNaturalNamesAndDoesNotDescendIntoPackages() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["file10.txt", "file2.txt", ".hidden"] {
            try Data().write(to: root.appendingPathComponent(name))
        }
        for name in ["Folder", "Sample.app"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        let entries = try FolderCatalog.read(root)
        XCTAssertEqual(entries.count, 4)
        XCTAssertEqual(FolderCatalog.sorted(entries.filter { $0.name.hasPrefix("file") }, by: .name).map(\.name),
                       ["file2.txt", "file10.txt"])
        XCTAssertTrue(try XCTUnwrap(entries.first { $0.name == "Folder" }).directory)
        XCTAssertFalse(try XCTUnwrap(entries.first { $0.url.pathExtension == "app" }).directory)
        XCTAssertThrowsError(try FolderCatalog.read(root.appendingPathComponent("missing")))
    }
    func testAddedDateSortAndMissingDateFallbackAreDeterministic() {
        let base = URL(fileURLWithPath: "/tmp")
        let entries = [
            FolderEntry(url: base.appendingPathComponent("b"), name: "b", directory: false, dateAdded: nil),
            FolderEntry(url: base.appendingPathComponent("old"), name: "old", directory: false, dateAdded: Date(timeIntervalSince1970: 1)),
            FolderEntry(url: base.appendingPathComponent("new"), name: "new", directory: false, dateAdded: Date(timeIntervalSince1970: 2)),
            FolderEntry(url: base.appendingPathComponent("a"), name: "a", directory: false, dateAdded: nil)
        ]
        XCTAssertEqual(FolderCatalog.sorted(entries, by: .added).map(\.name), ["new", "old", "a", "b"])
    }
}
