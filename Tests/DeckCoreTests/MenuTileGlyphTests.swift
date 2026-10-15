import XCTest
@testable import DeckCore

final class MenuTileGlyphTests: XCTestCase {
    func testChosenSymbolThenShortcutThenText() {
        let shortcut = MenuShortcut(key: "j", modifiers: 0)
        XCTAssertEqual(MenuTileGlyph.resolve(symbol: "folder.badge.plus", shortcut: shortcut), .symbol("folder.badge.plus"))
        XCTAssertEqual(MenuTileGlyph.resolve(symbol: nil, shortcut: shortcut), .shortcut("⌘J"))
        XCTAssertEqual(MenuTileGlyph.resolve(symbol: "  ", shortcut: nil), .text)
    }
    func testPresetAppliesUnlessUserChoseOrHidIcon() {
        XCTAssertEqual(MenuSymbolPreset.symbol(for: "Go to Folder…"), "folder")
        XCTAssertEqual(MenuSymbolPreset.symbol(for: "New Window"), "macwindow.badge.plus")
        XCTAssertEqual(MenuSymbolPreset.symbol(for: "새로운 폴더"), "folder.badge.plus")
        XCTAssertNil(MenuSymbolPreset.symbol(for: "New Finder Window"))
        XCTAssertNil(MenuSymbolPreset.symbol(for: "Open in New Tab"))
        let shortcut = MenuShortcut(key: "i", modifiers: 0)
        XCTAssertEqual(MenuTileGlyph.resolve(symbol: nil, preset: "info.circle", shortcut: shortcut), .symbol("info.circle"))
        XCTAssertEqual(MenuTileGlyph.resolve(symbol: "star", preset: "info.circle", shortcut: shortcut), .symbol("star"))
        XCTAssertEqual(MenuTileGlyph.resolve(symbol: MenuSymbolName.hidden, preset: "info.circle", shortcut: shortcut), .shortcut("⌘I"))
        XCTAssertEqual(MenuSymbolName.stored(""), MenuSymbolName.hidden)
        XCTAssertNil(MenuSymbolName.stored(nil))
    }
    func testSymbolNamesAreTrimmedAndRestricted() {
        XCTAssertEqual(MenuSymbolName.normalized(" star.fill "), "star.fill")
        XCTAssertNil(MenuSymbolName.normalized("../etc"))
        XCTAssertNil(MenuSymbolName.normalized("별"))
    }
    func testShortcutDisplayUsesMacModifierOrder() {
        XCTAssertEqual(MenuShortcut(key: "s", modifiers: 4)?.display, "⌃⌘S")
        XCTAssertEqual(MenuShortcut(key: "n", modifiers: 1)?.display, "⇧⌘N")
        XCTAssertEqual(MenuShortcut(key: "x", modifiers: 2 | 8)?.display, "⌥X")
        XCTAssertNil(MenuShortcut(key: " ", modifiers: 0))
    }
    func testCaptureStoresShortcutAndOldDataDecodes() throws {
        let menu = CapturedMenu(appID: "a", appName: "A", path: ["File", "Export"], shortcut: "e", modifiers: 1)
        let commands = MenuCaptureHistory.record(menu, in: [], at: Date())
        XCTAssertEqual(commands.first?.shortcut?.display, "⇧⌘E")
        var legacy = try JSONSerialization.jsonObject(with: JSONEncoder().encode(commands)) as! [[String: Any]]
        legacy[0]["shortcut"] = nil
        legacy[0]["symbol"] = nil
        let decoded = try JSONDecoder().decode([MenuCommand].self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(decoded.first?.shortcut)
        XCTAssertNil(decoded.first?.symbol)
    }
}
