import XCTest
@testable import DeckCore

final class MenuLanguageTests: XCTestCase {
    func testKeepsEveryPreferredLanguageUSEnglishAndDevelopment() {
        let available = ["en", "en_GB", "ko", "ja", "es", "de", "fr", "Base"]
        let selected = MenuLanguageSelection.select(available: available, preferred: ["en-GB", "ko-KR", "ja-JP"],
                                                    development: "en")
        XCTAssertEqual(selected, ["en_GB", "en", "ko", "ja"])
    }
    func testSingleLanguageAppAndCapturedLanguageAreKept() {
        XCTAssertEqual(MenuLanguageSelection.select(available: ["es"], preferred: ["en-GB", "ko-KR"], development: "es"), ["es"])
        let withCaptured = MenuLanguageSelection.select(available: ["en", "ko", "de"], preferred: ["ko-KR"],
                                                        development: "en", capturedIn: ["de", "xx"])
        XCTAssertEqual(withCaptured, ["en", "ko", "de"])
    }
    func testAliasesLinkTranslatedNamesOfTheSameItem() {
        let index = MenuAliasIndex.build(items: [("File", "f.title"), ("New Tab", "t.title"), ("Untranslated", nil)],
                                         tables: [["f.title": "파일", "t.title": "새로운 탭"], ["t.title": "新規タブ"]])
        XCTAssertEqual(MenuAliasIndex.aliases(for: ["File", "New Tab"], in: index)?.map { $0.sorted() }, [["파일"], ["新規タブ", "새로운 탭"].sorted()])
        XCTAssertEqual(MenuAliasIndex.aliases(for: ["파일", "새로운 탭"], in: index)?[1].sorted(), ["New Tab", "新規タブ"])
        XCTAssertNil(MenuAliasIndex.aliases(for: ["Untranslated"], in: index))
    }
    func testCaptureInAnotherLanguageMergesIntoTheSavedMenu() {
        var english = MenuCommand(appID: "finder", appName: "Finder", path: ["File", "New Tab"])
        english.pathAliases = [["파일"], ["새로운 탭"]]
        english.shortcut = MenuShortcut(key: "t", modifiers: 0)
        let korean = CapturedMenu(appID: "finder", appName: "Finder", path: ["파일", "새로운 탭"], shortcut: "t", shortcutKnown: true)
        let merged = MenuCaptureHistory.record(korean, in: [english], at: Date())
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].observedCount, 1)
        XCTAssertEqual(merged[0].path, ["File", "New Tab"])
        XCTAssertTrue(MenuPathMatch.matches(["파일", "새로운 탭"], english))
        XCTAssertFalse(MenuPathMatch.matches(["파일", "새로운 폴더"], english))
    }
    func testOnlyAConfirmedReadingClearsAShortcut() {
        var saved = MenuCommand(appID: "a", appName: "A", path: ["Go", "Connect"])
        saved.shortcut = MenuShortcut(key: "k", modifiers: 0)
        let unknown = CapturedMenu(appID: "a", appName: "A", path: ["Go", "Connect"], shortcutKnown: false)
        XCTAssertEqual(MenuCaptureHistory.record(unknown, in: [saved], at: Date())[0].shortcut?.display, "⌘K")
        let removed = CapturedMenu(appID: "a", appName: "A", path: ["Go", "Connect"], shortcutKnown: true)
        XCTAssertNil(MenuCaptureHistory.record(removed, in: [saved], at: Date())[0].shortcut)
    }
}
