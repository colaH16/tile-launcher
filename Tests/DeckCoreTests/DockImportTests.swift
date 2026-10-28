import XCTest
@testable import DeckCore

final class DockImportTests: XCTestCase {
    private func tile(_ type: String, _ path: String, encoding: Int = 15) -> [String: Any] {
        ["tile-type": type, "tile-data": ["file-data": ["_CFURLString": path, "_CFURLStringType": encoding]]]
    }

    func testDockKeepsAppAndFolderOrderAndDecodesPaths() {
        let result = DockImport.parse(apps: [
            tile("file-tile", "file:///Applications/First%20App.app/"),
            tile("file-tile", "/Applications/둘째.app", encoding: 0)
        ], others: [tile("directory-tile", "file:///Users/example/My%20Files/"),
                    tile("directory-tile", "file:///Users/example/Downloads/")])
        XCTAssertEqual(result.items.map(\.kind), [.app, .app, .folder, .folder])
        XCTAssertEqual(result.items.map(\.name), ["First App", "둘째", "My Files", "Downloads"])
        XCTAssertEqual(result.items[0].path, "/Applications/First App.app")
        XCTAssertTrue(result.items[2].opensInOverlay)
        XCTAssertEqual(result.skipped, 0)
    }

    func testDockSkipsUnsupportedMalformedAndRemoteEntries() {
        let result = DockImport.parse(apps: [["tile-type": "spacer-tile"], "invalid",
            tile("file-tile", "https://example.com/Fake.app"),
            tile("file-tile", "file://server/Apps/Remote.app"),
            tile("file-tile", "relative.app", encoding: 0),
            tile("file-tile", "/Applications/Unknown.app", encoding: 99)
        ], others: [tile("file-tile", "file:///tmp/document.pdf"),
                    tile("url-tile", "file:///tmp/Folder"),
                    tile("directory-tile", "file:///tmp/Valid")])
        XCTAssertEqual(result.items.map(\.path), ["/tmp/Valid"])
        XCTAssertEqual(result.skipped, 7)
    }

    func testImportPreservesSettingsDeduplicatesAndKeepsRemainingPins() {
        let app = PinnedItem(kind: .app, path: "/Applications/Existing.app", bundleID: "test.app", name: "내 앱")
        let folder = PinnedItem(kind: .folder, path: "/tmp/Folder", bundleID: nil, name: "내 폴더", openMode: .finder)
        let extra = PinnedItem(kind: .folder, path: "/tmp/Other", bundleID: nil, name: "기존 항목")
        let trash = PinnedItem(kind: .trash, path: "/tmp/.Trash", bundleID: nil, name: "휴지통")
        let imported = [
            PinnedItem(kind: .folder, path: "/tmp/Folder/", bundleID: nil, name: "Folder"),
            PinnedItem(kind: .app, path: "/Applications/Moved.app", bundleID: "test.app", name: "Moved"),
            app, trash, PinnedItem(kind: .trash, path: "/other/.Trash", bundleID: nil, name: "Bin")]
        let result = DockImport.merge(imported, into: [extra, app, folder, trash])
        XCTAssertEqual(result, [folder, app, trash, extra])
        XCTAssertEqual(DockImport.merge(imported, into: result), result)
        XCTAssertEqual(DockImport.merge([], into: result), result)
    }

    func testCanonicallyEquivalentFolderPathsDoNotDuplicate() {
        let original = PinnedItem(kind: .folder, path: "/tmp/폴더".decomposedStringWithCanonicalMapping,
                                  bundleID: nil, name: "기존 폴더", openMode: .finder)
        let dock = PinnedItem(kind: .folder, path: "/tmp/폴더", bundleID: nil, name: "폴더")
        XCTAssertEqual(DockImport.merge([dock], into: [original]), [original])
    }
}
