import SwiftUI
import DeckCore

private struct DeckThemeKey: EnvironmentKey {
    static let defaultValue: DeckTheme = .glass
}
extension EnvironmentValues {
    var deckTheme: DeckTheme {
        get { self[DeckThemeKey.self] }
        set { self[DeckThemeKey.self] = newValue }
    }
}

enum DeckTileTone { case neutral, pinnedMenu, currentDesktop }

struct DeckPalette {
    let tone: DeckTileTone
    let dark: Bool
    let theme: DeckTheme
    private func rgb(_ hex: UInt32) -> Color {
        Color(red: Double((hex >> 16) & 255) / 255,
              green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255)
    }
    var fill: Color {
        if theme.isClassic {
            switch tone {
            case .neutral: return rgb(dark ? 0x364A5C : 0xE0E8F0)
            case .pinnedMenu: return rgb(dark ? 0x247758 : 0xCCECDB)
            case .currentDesktop: return rgb(dark ? 0x236A9C : 0xCDE8FB)
            }
        }
        switch tone {
        case .neutral: return rgb(dark ? 0x444C56 : 0xF7F9FC)
        case .pinnedMenu: return rgb(dark ? 0xEAD390 : 0xFFEAB0)
        case .currentDesktop: return rgb(dark ? 0xAED3EF : 0xCCE8FC)
        }
    }
    var ink: Color {
        if theme.isClassic {
            return dark ? rgb(0xFFFFFF) : rgb(tone == .pinnedMenu ? 0x123F2A : 0x17354F)
        }
        switch tone {
        case .neutral: return dark ? rgb(0xF5F7FA) : rgb(0x252B32)
        case .pinnedMenu: return rgb(0x493910)
        case .currentDesktop: return rgb(0x173C57)
        }
    }
    var secondary: Color {
        if theme.isClassic {
            return dark ? rgb(0xEBF3FA) : rgb(tone == .pinnedMenu ? 0x295B3E : 0x315570)
        }
        switch tone {
        case .neutral: return dark ? rgb(0xCED5DF) : rgb(0x5A6370)
        case .pinnedMenu: return rgb(0x62501B)
        case .currentDesktop: return rgb(0x305873)
        }
    }
}
