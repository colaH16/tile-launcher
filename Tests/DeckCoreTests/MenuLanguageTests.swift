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
    private func binding(_ key: String, _ paths: [[String]], archive: String = "MainMenu.nib") -> MenuResourceBinding {
        .init(identity: .init(appID: "finder", archive: archive, keys: ["parent", key]), paths: paths)
    }
    func testSameLeafUnderDifferentParentsNeverSharesTranslations() {
        let file = binding("file.open", [["File", "Open"], ["파일", "문서 열기"]])
        let project = binding("project.open", [["Project", "Open"], ["프로젝트", "프로젝트 열기"]])
        let matched = MenuResourceMatch.binding(appID: "finder", path: ["File", "Open"], entries: [file, project])
        XCTAssertEqual(matched, file)
        var command = MenuCommand(appID: "finder", appName: "Finder", path: ["File", "Open"])
        command.resourceBinding = matched
        XCTAssertTrue(MenuPathMatch.matches(["파일", "문서 열기"], command))
        XCTAssertFalse(MenuPathMatch.matches(["파일", "프로젝트 열기"], command))
        XCTAssertFalse(MenuPathMatch.matches(["프로젝트", "프로젝트 열기"], command))
    }
    func testWholePathsDoNotCombineLanguagesOrTrustLegacyAliases() {
        var command = MenuCommand(appID: "finder", appName: "Finder", path: ["File", "Open"])
        command.pathAliases = [["파일"], ["문서 열기", "프로젝트 열기"]]
        XCTAssertFalse(MenuPathMatch.matches(["파일", "프로젝트 열기"], command))
        command.resourceBinding = binding("file.open", [["File", "Open"], ["파일", "문서 열기"], ["ファイル", "開く"]])
        XCTAssertFalse(MenuPathMatch.matches(["파일", "開く"], command))
        XCTAssertEqual(MenuPathMatch.paths(command).count, 3)
    }
    func testDuplicateFullPathOrResourceArchiveDoesNotGuessIdentity() {
        let a = binding("open", [["File", "Open"], ["파일", "열기"]])
        let b = binding("open", [["Project", "Open"], ["파일", "열기"]], archive: "OtherMenu.nib")
        XCTAssertNil(MenuResourceMatch.binding(appID: "finder", path: ["파일", "열기"], entries: [a,b]))
        let english = MenuResourceMatch.binding(appID: "finder", path: ["File", "Open"], entries: [a,b])
        XCTAssertEqual(english?.paths, [["File", "Open"]])
        XCTAssertNil(MenuResourceMatch.binding(appID: "another.app", path: ["File", "Open"], entries: [a]))
    }
    func testCaptureInAnotherLanguageMergesIntoTheSavedMenu() {
        var english = MenuCommand(appID: "finder", appName: "Finder", path: ["File", "New Tab"])
        english.resourceBinding = binding("new.tab", [["File", "New Tab"], ["파일", "새로운 탭"]])
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
