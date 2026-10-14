import SwiftUI
import AppKit
import DeckCore

private struct DeckThemeKey: EnvironmentKey {
    static let defaultValue: DeckTheme = .glass
}
private struct TileColorsKey: EnvironmentKey {
    static let defaultValue = TileColors()
}
private struct DeckScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}
extension EnvironmentValues {
    var deckScale: CGFloat {
        get { self[DeckScaleKey.self] }
        set { self[DeckScaleKey.self] = newValue }
    }
    var deckTheme: DeckTheme {
        get { self[DeckThemeKey.self] }
        set { self[DeckThemeKey.self] = newValue }
    }
    var tileColors: TileColors {
        get { self[TileColorsKey.self] }
        set { self[TileColorsKey.self] = newValue }
    }
}
extension TileColor {
    var swiftUIColor: Color { Color(red: red, green: green, blue: blue) }
    init?(color: Color) {
        guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return nil }
        let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]
        guard channels.allSatisfy({ $0.isFinite }) else { return nil }
        let bytes = channels.map { UInt32((min(1, max(0, $0)) * 255).rounded()) }
        self.init(bytes[0] << 16 | bytes[1] << 8 | bytes[2])
    }
}
struct DeckPalette {
    private let surface: TileSurfaceColors
    init(section: TileSection, emphasized: Bool = false, dark: Bool, theme: DeckTheme, colors: TileColors) {
        surface = TileSurfaceColors(section: section, emphasized: emphasized, dark: dark, theme: theme, colors: colors)
    }
    var fill: Color { surface.fill.swiftUIColor }
    var ink: Color { surface.ink.swiftUIColor }
    var secondary: Color { surface.secondary.swiftUIColor }
}
