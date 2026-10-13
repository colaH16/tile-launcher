import XCTest
@testable import DeckCore

final class TileColorsTests: XCTestCase {
    func testExistingSettingsAndMalformedDataUseDefaults() {
        XCTAssertEqual(TileColors.restore(nil), TileColors())
        XCTAssertEqual(TileColors.restore(Data("invalid".utf8)), TileColors())
        XCTAssertEqual(TileColors.restore(Data("{\"menus\":4294967295}".utf8)), TileColors())
        XCTAssertEqual(TileColors.restore(Data("{}".utf8)), TileColors())
    }
    func testIndependentSectionsPersistAndResetWithoutChangingOtherColors() throws {
        var colors = TileColors()
        colors[.menus] = TileColor(0xCC5511)
        colors[.windows] = TileColor(0x8E36A2)
        let restored = TileColors.restore(try JSONEncoder().encode(colors))
        XCTAssertEqual(restored, colors)
        colors[.menus] = nil
        XCTAssertEqual(colors.windows, restored.windows)
        XCTAssertNil(colors.registered)
        XCTAssertEqual(colors.seed(for: .menus, theme: .classic), TileColor(0x247758))
    }
    func testThemeSwitchPreservesCustomHueButAdaptsSurfaces() {
        var colors = TileColors()
        colors.windows = TileColor(0xCC6622)
        XCTAssertEqual(colors.seed(for: .windows, theme: .glass), colors.seed(for: .windows, theme: .classic))
        let glass = TileSurfaceColors(section: .windows, emphasized: true, dark: true, theme: .glass, colors: colors)
        let classic = TileSurfaceColors(section: .windows, emphasized: true, dark: true, theme: .classic, colors: colors)
        XCTAssertNotEqual(glass.fill, classic.fill)
        XCTAssertEqual(classic.fill, colors.windows)
    }
    func testDefaultSectionsAreDistinctAndEmphasisStaysDistinct() {
        for theme in DeckTheme.allCases {
            for dark in [false, true] {
                let basics = TileSection.allCases.map {
                    TileSurfaceColors(section: $0, emphasized: false, dark: dark, theme: theme, colors: TileColors()).fill.hex
                }
                XCTAssertEqual(Set(basics).count, 3)
                for section in [TileSection.menus, .windows] {
                    let base = TileSurfaceColors(section: section, emphasized: false, dark: dark, theme: theme, colors: TileColors())
                    let highlight = TileSurfaceColors(section: section, emphasized: true, dark: dark, theme: theme, colors: TileColors())
                    XCTAssertNotEqual(base.fill, highlight.fill)
                }
            }
        }
    }
    func testTextContrastForCustomColorsIncludingBlackWhiteAndMiddleTones() {
        // A sampled RGB cube catches the white/dark text crossover as well as extremes.
        for red in stride(from: UInt32(0), through: 255, by: 51) {
            for green in stride(from: UInt32(0), through: 255, by: 51) {
                for blue in stride(from: UInt32(0), through: 255, by: 51) {
                    var colors = TileColors()
                    colors.menus = TileColor(red << 16 | green << 8 | blue)
                    for theme in DeckTheme.allCases {
                        for dark in [false, true] {
                            for emphasized in [false, true] {
                                let palette = TileSurfaceColors(section: .menus, emphasized: emphasized,
                                                                dark: dark, theme: theme, colors: colors)
                                XCTAssertGreaterThanOrEqual(palette.ink.contrast(with: palette.fill), 4.5)
                                XCTAssertGreaterThanOrEqual(palette.secondary.contrast(with: palette.fill), 4.5)
                            }
                        }
                    }
                }
            }
        }
    }
}
