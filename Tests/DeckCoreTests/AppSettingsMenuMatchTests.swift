import XCTest
@testable import DeckCore

final class AppSettingsMenuMatchTests: XCTestCase {
    private func item(_ title: String, _ key: String? = nil, _ modifiers: Int = 0) -> AppSettingsMenuMatch.Candidate {
        .init(title: title, shortcut: key.flatMap { MenuShortcut(key: $0, modifiers: modifiers) })
    }
    func testStandardShortcutWorksWithoutKnownAppOrLanguage() {
        XCTAssertEqual(AppSettingsMenuMatch.index(in: [item("Über"), item("Einstellungen…", ","), item("Beenden", "q")]), 1)
    }
    func testCurrentAndLegacyNamesWorkWithNoShortcutOrRemappedShortcut() {
        for name in ["Settings…", "Preferences...", "설정…", "환경설정…", "환경 설정…", "設定…", "環境設定…", "设置…", "偏好設定…"] {
            XCTAssertEqual(AppSettingsMenuMatch.index(in: [item("About"), item(name)]), 1, name)
            XCTAssertEqual(AppSettingsMenuMatch.index(in: [item(name, "p", 2)]), 0, name)
        }
    }
    func testUnrelatedCommandsAreNotSettingsAndExtraModifiersDoNotMatch() {
        for key in [",", ";", "<"] {
            for modifiers in [1, 2, 4, 8] {
                XCTAssertNil(AppSettingsMenuMatch.index(in: [item("Arrange", key, modifiers)]))
            }
        }
        for name in ["Project Settings…", "Document Settings", "Reset Settings…", "Settings Sync", "설정 초기화", "환경설정 가져오기"] {
            XCTAssertFalse(AppSettingsMenuMatch.isSettingsTitle(name), name)
        }
    }
    func testDuplicateShortcutsOrAmbiguousNamesAreNeverGuessed() {
        XCTAssertNil(AppSettingsMenuMatch.index(in: [item("One", ","), item("Two", ",")]))
        XCTAssertNil(AppSettingsMenuMatch.index(in: [item("Settings…"), item("Preferences…")]))
        XCTAssertNil(AppSettingsMenuMatch.index(in: []))
    }
    func testUniqueStandardShortcutTakesPriorityOverLegacyName() {
        XCTAssertEqual(AppSettingsMenuMatch.index(in: [item("Preferences…"), item("Settings…", ",")]), 1)
    }
}
